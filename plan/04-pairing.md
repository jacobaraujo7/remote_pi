# Plano 04 — Pareamento (E2E)

Objetivo: implementar pareamento QR + cripto E2E entre **app** (Flutter) e **pi-extension** (Node) via **relay** (Rust). Modelo MVP: **1 pareamento = 1 sessão**.

Resultado esperado ao final: rodar `/remote-pi` num Pi vivo gera QR, mobile escaneia, handshake fecha, app conversa com aquela sessão por canal cifrado. Quando Pi fecha, pareamento marca offline. Para outra sessão, novo QR.

**Este plano não cobre**: switch_session, lista multi-sessão por projeto, project scope resolution, histórico de sessões. Tudo isso fica fora de escopo (ver `00-decisions.md`, seção "Em aberto").

---

## Contexto

Plan 03 entregou o protocolo de mensagens com framing JSONL e envelope externo `{ peer, ct }`. O campo `ct` é hoje base64 do JSON em claro — placeholder. Este plano ativa cifra real.

Plan 02 e os 4 personas já estão configurados e o overlay `.orchestration/` foi ativado em Plan 03. Este plano também toca os 3 subprojetos (app + pi-extension + relay) — gatilho natural pra usar o overlay de orquestração.

A decisão de escopo (revertida hoje, 2026-05-18, de C → A) está em `00-decisions.md` com strikethroughs. Resumo:

- Pareamento é 1:1 com uma sessão Pi
- Sem session manager, sem project scope, sem switch_session
- N sessões = N pareamentos independentes
- Quando Pi fecha, app mostra offline (sem reconectar a outra sessão)

Trade-offs aceitos:
- Power user precisa parear cada sessão separadamente
- App não ressuscita sessão histórica — pra "voltar" a uma sessão antiga, dev abre Pi com `--session X` e roda `/remote-pi` novamente
- Sem `switch_session` no protocolo (refletir em `contracts/protocol.md`)

Ganho:
- pi-extension não precisa expor `SessionManager.list()` nem `resume(id)`
- relay não muda — autenticação por pubkey já é por-peer, não por-projeto
- app UX simplifica: lista de pareamentos = lista de sessões, sem estado complexo
- ~70% menos código vs modelo C

---

## Decisões fixadas (do `00-decisions.md`, ainda válidas)

| Decisão | Valor |
|---|---|
| Cifra simétrica | ChaCha20-Poly1305 (libsodium `crypto_secretbox_*` ou Noise transport) |
| Cifra assimétrica | Curve25519 (libsodium `crypto_kx_*` ou Noise XX/IK) |
| Protocolo de handshake | **A decidir neste plano** entre libsodium direto e Noise XX |
| QR validity | 60s, rotaciona, single-use |
| Forward secrecy | ECDH efêmero a cada reconexão |
| Safety number | 6 emojis bilateral (estilo Signal). Opcional, exibido após handshake |
| Identidade | Pubkey, sem username |
| Auth no relay | Challenge-response (relay assina nonce com sua chave; peer responde com assinatura usando sua pubkey) |
| Storage Mac | `~/.pi/remote/peers.json` (público: pubkeys + nomes) + Keychain (privado: chave longa) |
| Storage mobile | Keychain (iOS) / Keystore (Android) — pubkey do peer + chave longa do mobile |
| TLS 1.3 + cert pinning | Obrigatório no app contra o relay |
| Lifetime do pareamento | Persistente até revoke (revoke não está no MVP — só previsto) |

---

## Decisões fechadas neste plano (2026-05-18)

**Q1: protocolo de handshake → Noise XX (Caminho C)**

Stack escolhido:
- **Node** (pi-extension): `noise-protocol` (npm) — implementação Noise XX pura, sem amarração libp2p
- **Dart** (app): `cryptography` (dint.dev) como base + implementar Noise XX manual seguindo [spec oficial](https://noiseprotocol.org/noise.html) em ~200 LOC. Não há lib Noise XX madura pura Dart (`noise_protocol_framework` tem só 69 downloads/sem — risco pra cripto crítica)
- **Rust** (relay): `ed25519-dalek` pra challenge-response. Relay **não participa** do Noise — só autentica peers e roteia ciphertext

Validação obrigatória:
- Test vectors oficiais do Noise pra Dart manual
- Roundtrip Node↔Dart no localhost antes de declarar done

**Q2: pacote Dart de cripto → `cryptography` (dint.dev)**

309k downloads/semana, X25519 + ChaCha20-Poly1305 + HKDF + Ed25519 todos presentes. Híbrido (platform crypto + Dart fallback). Substitui o que era pré-considerado (`sodium_libs`).

---

## Estrutura final esperada

```
remote_pi/
├── .orchestration/
│   ├── contracts/
│   │   ├── protocol.md                    ← (já existe — atualizar, passo 6)
│   │   └── pairing.md                     ← passo 1 (fonte de verdade)
│   └── tasks/                             ← novo, gerado pelo orquestrador
│       ├── 04-01-contract.md
│       ├── 04-02-pi-extension.md
│       ├── 04-03-app.md
│       ├── 04-04-relay-auth.md
│       └── 04-05-roundtrip.md
├── pi-extension/
│   └── src/pairing/                       ← passo 2
│       ├── qr.ts                          ← gera QR (token + pubkey + relay URL)
│       ├── handshake.ts                   ← responde Noise XX como responder
│       ├── crypto.ts                      ← wrapping libsodium
│       ├── storage.ts                     ← ~/.pi/remote/peers.json + Keychain
│       └── pairing.test.ts                ← roundtrip
├── app/
│   └── lib/pairing/                       ← passo 3
│       ├── qr_scanner.dart                ← câmera + parse
│       ├── handshake.dart                 ← inicia Noise XX como initiator
│       ├── crypto.dart                    ← wrapping
│       ├── storage.dart                   ← Keychain/Keystore via flutter_secure_storage
│       └── pairing_test.dart              ← unit
└── relay/
    └── src/auth/                          ← passo 4
        ├── mod.rs
        ├── challenge.rs                   ← challenge-response no connect
        └── auth_test.rs                   ← unit
```

Note: relay autentica pubkey no momento de WS connect, mas **não decifra payload**. Cripto E2E é entre app e pi-extension. Relay vê só `{ peer, ct }`.

---

## Passo 1 — `.orchestration/contracts/pairing.md`

**Função**: fonte de verdade do pareamento. App, pi-extension e relay implementam tipos derivados.

**Conteúdo mínimo**:

```markdown
# Contrato — Pareamento

## QR payload

URI scheme: `remotepi://pair?...`

Campos (query string, URL-encoded):
- `t` — token efêmero (16 bytes, base64url). Single-use. Válido por 60s.
- `pk` — pubkey de longo prazo do Mac (Curve25519, 32 bytes, base64url)
- `r` — URL do relay (ex: `https://relay-rp1.jacobmoura.work`)
- `n` — nome legível da sessão (ex: `remote_pi/feature/protocol`). UTF-8, max 80 chars.

QR rotaciona a cada 60s no terminal do Pi. Cada QR aceita 1 scan.

## Handshake (Noise XX, papéis fixos)

- **Initiator**: app (mobile)
- **Responder**: pi-extension (Mac)
- Roteado via relay (que vê só ciphertext do handshake)

Sequência:
1. App escaneia QR, valida `t` ainda não expirou
2. App conecta no relay com sua pubkey efêmera
3. App envia mensagem 1 do Noise XX → relay roteia pro Mac (identificado por `pk` do QR)
4. Pi-extension valida `t`, responde mensagem 2 com sua pubkey de longo prazo
5. App envia mensagem 3 com sua pubkey de longo prazo + autenticação
6. Ambos derivam chaves de sessão (rx + tx)
7. Token `t` é marcado consumido em pi-extension

## Safety number

Após handshake completo, ambos lados derivam um número de segurança bilateral:
- 6 emojis de um alfabeto de 256 (ex: lista emoji-256 já publicada)
- Derivação: HKDF(handshake_hash, "remotepi/safety/v1", 6 bytes) → 6 emojis
- Exibido no app e no terminal do Pi
- Usuário compara visualmente; se bater = sem MITM

## Storage pós-handshake

### No Mac (`~/.pi/remote/peers.json`)
```json
{
  "peers": [
    {
      "name": "iPhone do Jacob",
      "remote_pk": "<base64>",
      "session_id": "<uuid>",
      "session_name": "remote_pi/feature/protocol",
      "paired_at": "2026-05-18T19:00:00Z"
    }
  ]
}
```

### No Mac (Keychain)
- Chave de longo prazo (privada) — singleton por Mac
- Bridge: comando `security add-generic-password ...`

### No mobile (Keychain/Keystore)
```
service: dev.remotepi.peers
account: <session_id ou hash do remote_pk>
data: {
  "remote_pk": "...",
  "local_pk": "...",
  "local_sk": "...",     # chave longa do mobile
  "session_name": "...",
  "relay_url": "...",
  "paired_at": "..."
}
```

## Reconexão

Em cada reconexão:
- ECDH efêmero (nova chave temporária a cada sessão de WS) garante forward secrecy
- Identidade autenticada pela chave de longo prazo (não muda)
- Se `remote_pk` não bate com o salvo → mostra erro "fingerprint mudou — possível MITM ou re-pareamento manual necessário"

## Revoke (não implementado no MVP — apenas previsto)

- Mac: remover entrada de `~/.pi/remote/peers.json` + revogar via `/remote-pi revoke <nome>`
- Mobile: remover entrada do Keychain/Keystore via UI de settings
- Sem propagação remota — cada lado limpa seu próprio storage
```

**Critério de aceite**: arquivo existe, lido por orquestrador como `contracts/pairing.md`, referenciado pelos passos 2-4.

---

## Passo 2 — pi-extension: QR + handshake + storage

**Localização**: `pi-extension/src/pairing/`

**Função**: gerar QR efêmero, responder ao handshake Noise XX vindo do app, persistir peer.

**Comandos novos expostos pelo Pi**:
- `/remote-pi` — gera QR (60s, rotaciona até alguém parear ou comando cancelar)
- `/remote-pi list` — lista peers persistidos
- `/remote-pi revoke <nome>` — previsto no contrato, deixar como `TODO` no MVP

**Dependências a instalar** (pi-extension/package.json):
- `noise-protocol` — Noise XX puro (decidido)
- `qrcode-terminal` — render QR no terminal
- `keytar` — wrapper Keychain Node
- `tweetnacl` ou `@noble/ed25519` — só pra assinar challenge do relay (Ed25519 separado do X25519 do Noise)

**Critério de aceite**:
- `/remote-pi` no Pi rodando exibe QR escaneável (~30 chars/lado)
- QR é regenerado a cada 60s
- Mobile escaneia → handshake fecha → safety number aparece em ambos os lados
- `~/.pi/remote/peers.json` ganha entrada
- Test roundtrip em `pairing.test.ts` simula app local com Noise initiator e fecha handshake

---

## Passo 3 — app: scanner + handshake + storage

**Localização**: `app/lib/pairing/`

**Função**: escanear QR, iniciar Noise XX, derivar safety number, persistir pareamento no Keychain.

**Dependências a instalar** (`app/pubspec.yaml`):
- `mobile_scanner` — scanner QR moderno (substitui `qr_code_scanner` legado)
- `flutter_secure_storage` — Keychain/Keystore wrapper
- `cryptography` — X25519, ChaCha20-Poly1305, HKDF, Ed25519 (decidido — ver Q2)

Noise XX é implementado a mão sobre `cryptography`, em `lib/pairing/noise.dart`, seguindo a spec literalmente. Test vectors oficiais do Noise (em `app/test/noise_vectors.dart`) garantem compatibilidade com o lado Node.

**UI mínima** (já vimos no mockup):
- Tela "Pair device" com viewfinder QR
- Após scan: tela de safety number (6 emojis) com botão "Confirma" e "Diferente"
- Sucesso: vai direto pra tela de chat daquela sessão (não há lista no MVP — 1:1)

**Critério de aceite**:
- App escaneia QR válido → handshake fecha em <3s no localhost
- QR expirado mostra erro "QR expired, gere outro no Mac"
- Safety number aparece e é igual ao do terminal Pi
- Pareamento salvo em Keychain (verificado com `flutter_secure_storage.readAll()`)
- Próxima abertura do app reconecta automaticamente ao peer salvo

---

## Passo 4 — relay: challenge-response (autenticação de peer)

**Localização**: `relay/src/auth/`

**Função**: autenticar pubkey antes de permitir WS estabelecer canal. Relay não decifra payload — só impede peers não-autenticados de roteamento.

**Mecanismo**:
1. Cliente abre WS, envia `{ "type": "hello", "pubkey": "..." }`
2. Relay responde `{ "type": "challenge", "nonce": "<32 bytes random>" }`
3. Cliente assina `nonce` com sua privkey de longo prazo e envia `{ "type": "auth", "sig": "..." }`
4. Relay valida assinatura com `pubkey` declarada
5. Se válido → adiciona peer ao roteamento. Se não → fecha WS

**Cripto**: Ed25519 (libsodium `crypto_sign_*`) — separado da Curve25519 usada pra X25519/Noise. Padrão: Ed25519 pra identidade, X25519 pra key agreement.

**Dependências relay** (`Cargo.toml`):
- `ed25519-dalek` ou `dalek-cryptography` — verificação Ed25519
- `rand` (já tem) — nonce

**Critério de aceite**:
- Cliente sem `hello` → WS fecha em <100ms
- Cliente com assinatura inválida → WS fecha
- Cliente com assinatura válida → mensagens routeam pra peer destinatário
- Test `auth_test.rs` cobre os 3 casos

---

## Passo 5 — Roundtrip integrado (3 lados)

**Função**: validar que tudo conecta de ponta a ponta com cifra real.

**Cenário**:
1. Sobe relay local (`cargo run` no relay)
2. Sobe pi-extension num Pi local (`pi --no-auto-quit` + comando `/remote-pi`)
3. App em simulador iOS escaneia QR
4. Handshake fecha, safety number bate
5. App envia `user_message`, pi-extension recebe via canal cifrado
6. Pi processa, retorna `agent_chunk` streaming
7. App renderiza
8. Mata o Pi → app mostra offline em <5s

**Critério de aceite**:
- Cenário acima roda end-to-end sem erros
- Wireshark/tcpdump no relay confirma que `ct` é opaco (não-JSON-legível)
- Reiniciar app reconecta automaticamente sem novo pareamento
- 2 Pi terminals na mesma pasta = 2 QRs distintos = 2 pareamentos independentes (não interfere)

---

## Passo 6 — Refletir mudanças em `contracts/protocol.md`

**Função**: remover tipos que foram revertidos junto com a decisão de escopo.

**Remover** do protocol.md (se presentes):
- Tipo `switch_session`
- Tipo `list_sessions` no shape multi-sessão
- Campos relacionados a `project_scope`

**Manter** (relacionados a 1:1 pareamento ↔ sessão):
- `user_message`, `agent_chunk`, `tool_request`, `approval`, `error`, `ping`/`pong`

**Critério de aceite**:
- `contracts/protocol.md` reflete só os tipos do MVP A
- Fixtures em `contracts/fixtures/` removem qualquer cenário multi-sessão
- pi-extension, app e relay implementam tipos derivados sem código morto

---

## Definition of Done

- [x] `.orchestration/contracts/pairing.md` escrito (passo 1)
- [x] Q1 e Q2 decididos em conversa explícita (Noise XX + SHA-256, `cryptography` no Dart)
- [x] `.orchestration/contracts/emoji_alphabet_256.txt` canônico (compartilhado entre Dart/Node)
- [x] `pi-extension/src/pairing/` implementado (passo 2) — Noise XX SHA-256 + cacophony test vector passa
- [x] `app/lib/pairing/` implementado (passo 3) — Noise XX manual sobre `cryptography`
- [x] `relay/src/auth/` implementado (passo 4) — Ed25519 challenge-response
- [ ] Roundtrip integrado passa (passo 5) — **parking** (decisão de pular por ora, retomar quando for testar manual)
- [x] `contracts/protocol.md` atualizado para 1:1 (passo 6 — feito antes da Wave 1)
- [x] `~/.pi/remote/peers.json` persiste corretamente no Mac (validado em unit test do Extension)
- [ ] Mobile reconecta automaticamente após reabrir app (depende do passo 5)
- [ ] 2 Pi terminals = 2 pareamentos independentes (depende do passo 5)
- [ ] Safety number bate visualmente em pelo menos 1 teste manual (depende do passo 5)
- [ ] Commit final por wave (orquestrador): `pairing: e2e crypto + qr + storage`

---

## Notas de execução

1. **Use o overlay `.orchestration/`** ativado em plan 03. Cada subprojeto recebe sua task via `[ORCH:04-NN]` e escreve `results/04-NN.md`.
2. **Wave 0**: passo 1 (contract). Wave 1: passos 2+3+4 em paralelo. Wave 2: passo 5 (roundtrip, sequencial). Wave 3: passo 6 (refletir mudanças no protocolo, sequencial).
3. **Não rolar cripto manual** — qualquer dúvida, parar e perguntar. "Não inventar protocolo" é princípio fixado.
4. **Cert pinning no app** — adicionar quando relay tiver TLS real (provavelmente em plan 06 ao decidir hosting). No MVP local, deixar pinned na cert de dev (mkcert) e documentar.

---

## Próximos planos

- **`05-mvp-features.md`** — features de app fora do pareamento: chat UI, approval cards inline, indicador de streaming, settings, revoke. UX completa do que já temos cifrado.
- **`06-relay-deploy.md`** — onde hospedar, TLS, custos, fallback self-hosted. Inclui cert pinning real e domínio.
- **`07-v2-multi-session.md`** (eventual, **só com demanda real**) — reverter pra C: project scope, lista multi-sessão, switch_session. Verificar antes que decisão foi correta de cortar pro MVP.
