# Remote Pi — Protocol & Security

Documentação canônica do protocolo Remote Pi e do modelo de proteção.
Atualizada em 2026-07-18.

---

## Visão de 30 segundos

- **Mesh de agentes coding** rodando em múltiplos PCs do mesmo usuário
- **Cada PC** roda o `pi-extension` (Node.js daemon) com **uma Pi-key** Ed25519 no Keychain do sistema (macOS/Linux/Windows)
- **Celular** é o **autenticador inicial** (estilo WhatsApp Web QR) — depois do pareamento, PCs operam autonomamente entre si
- **Owner-key** Ed25519 vive no Keychain do celular (iOS Keychain / Android Block Store), sincroniza entre devices do mesmo Apple ID / Google Account
- **Relay** WebSocket roteia e armazena/verifica `mesh_versions` assinadas pelo Owner; autoriza co-membership direta
- **Cross-PC routing** por Pi-key canônica no Relay; a Extension `0.6` mantém por uma release o prefixo wire legado para interoperar com Extensions antigas, sem substituir aliases receiver-local públicos

---

## Identidades

| Chave | Algoritmo | Onde mora | Quem cria | Quem usa |
|---|---|---|---|---|
| **Owner-key** | Ed25519 | iOS Keychain (sync iCloud) / Android Block Store (sync Google) | App mobile no 1º boot | Assina `mesh_versions`, prova autoridade pra parear/revogar PCs |
| **Pi-key** | Ed25519 | `@napi-rs/keyring` no PC (Keychain macOS / libsecret Linux / Credential Manager Windows). Fallback `~/.pi/remote/identity.json` (`0600`) com warning em sistemas headless | pi-extension no 1º boot | Autentica a conexão WS no relay e fornece a identidade técnica canônica usada no `from_pc` autenticado e no roteamento por `to_pc`; não assina envelopes cross-PC individuais |
| **App-key** | Ed25519 efêmera | RAM do app mobile | App por sessão de pareamento | Establishment de canal autenticado durante pair |

**Identidade técnica** de cada Pi/PC é a chave pública Ed25519 bruta de 32 bytes. Nas fronteiras do protocolo, Pi-key e Owner-key usam Base64 RFC 4648 padrão **com padding** como representação canônica; entradas URL-safe ou sem padding podem ser aceitas apenas para normalização. Nicknames e aliases locais efetivos nunca substituem essa identidade técnica.

**Constraint fixada**: "1 Pi-key por PC; troca de hardware = re-pareamento". Não há migração de Pi-key entre máquinas. Owner-key compensa (Owner sincroniza cross-device via Keychain do sistema).

---

## Camadas do protocolo

```
┌─────────────────────────────────────────────────────────────────────┐
│  Agent layer       Pi coding agent (futuro: Claude Code, OpenCode)  │
├─────────────────────────────────────────────────────────────────────┤
│  Envelope          {from, to, id, re, body}  — JSONL 5 campos       │
├─────────────────────────────────────────────────────────────────────┤
│  Routing           Local UDS broker  /  Cross-PC via relay forward  │
│                    Público [<alias-local-do-receptor>:]<cwd>@<agent>│
│                    Local <cwd>@<agent>; `broker` reservado          │
├─────────────────────────────────────────────────────────────────────┤
│  ACK protocol      received | busy | denied | timeout               │
│                    Broker/BrokerRemote gera ACK sem LLM             │
├─────────────────────────────────────────────────────────────────────┤
│  Transport         UDS (local)  /  WebSocket sobre TLS (relay)      │
├─────────────────────────────────────────────────────────────────────┤
│  Trust             Ed25519 challenge-response                       │
│                    Owner-sig em mesh_versions                       │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Envelope

Formato único pra todo o sistema. Funciona local (UDS) e cross-PC (relay forward).

```text
{
  "from": "<sender-name>",
  "to": "<recipient-name>" | ["<r1>", "<r2>"] | "broadcast",
  "id": "<UUID v7 normal gerado pela Extension>",
  "re": "<id-of-message-being-replied-to>" | null,
  "body": <any JSON>
}
```

Naming:
- **Local**: `<cwd>@<agent>`; `broker` é um endereço local reservado.
- **Endereço público**: `[<alias-local-do-receptor>:]<cwd>@<agent>`; o alias é apresentação/roteamento local ao receptor, não identidade estável nem alegação do remetente.
- Cada byte UTF-8 fora de `[A-Za-z0-9._-]` no nickname vira `%HH` literal em maiúsculas. Assim `:`, `%`, `~`, espaços, controles e Unicode nunca aparecem crus; `~<prefixo-base64url-da-chave>` é reservado para resolver colisões.
- Para cada chave canônica, coletam-se candidatos de nickname não vazios das contribuições Owner diretas e escolhe-se o menor já codificado em ASCII; em empate, vence o menor UTF-8 bruto. Ausente/vazio usa `pc-<prefixo-base64url-da-chave-canônica>` com prefixo inicial de 8 caracteres. Reservam-se todas as bases e, em colisões, cada candidato recebe `~<prefixo-da-chave-base64url>`, expandido adaptativamente dos 8 caracteres até a chave completa de 43 caracteres para não colidir; assim chave→alias e alias→chave são bijetivos.
- Ao enviar, um alias remoto conhecido vence primeiro. A exceção é um endereço Windows de drive absoluto (`C:\...@agent`) exatamente registrado, que permanece local; outros endereços locais exatos são fallback quando não resolvem para alias remoto. O alias remoto resolve para a Pi-key canônica e o `to_pc` canônico é o alvo técnico.
- Durante a compatibilidade de uma release da Extension `0.6`, o prefixo cross-PC no wire é o nickname assinado bruto selecionado deterministicamente ou, sem nickname, os primeiros 8 caracteres da Pi-key canônica Base64 padrão com padding. Esse label legado nunca vira identidade, autorização ou endereço público.
- Ao receber pelo relay, o broker renderiza `envelope.from` com seu próprio alias local para `from_pc` e remove apenas o prefixo de apresentação/compatibilidade de destino: o relay já entregou ao PC autenticado selecionado por `to_pc`. ACKs retornam ao `from` wire exato recebido.

UUID v7 garante ordenação temporal sem coordenação para envelopes normais gerados pela Extension.

---

## ACK protocol

Em unicast, cada chamada de `agent_send` aguarda um ACK rápido (default 5s) gerado pelo `Broker` local ou pelo `BrokerRemote` receptor após a entrega — não pelo LLM. Custo: microsegundos local, milissegundos cross-PC. Os resultados públicos atuais de unicast são `received | denied | timeout`; broadcast é enviado como `sent`, sem ACK.

| Status compatível de ACK | Significado |
|---|---|
| `received` | Peer online aceitou/recebeu a mensagem, inclusive durante um turn; ela será processada no turno atual ou seguinte. |
| `busy` | Compatibilidade defensiva com um broker líder antigo: a mensagem foi descartada. Não é comportamento atual; reinicie/substitua o líder antigo antes de reenviar. |
| `denied` | Peer recusou; abandona. |
| `timeout` | ACK não chegou em 5s; silêncio genuíno não tem reason. |

Os motivos fechados do relay são `offline`, `not_authorized` e `bad_envelope`: `offline → timeout`; `not_authorized | bad_envelope → denied`. O resultado carrega reason/error explícito (`transport_error: <reason>`) quando o relay confiável o informou.

**Reply de conteúdo** é assíncrona: peer responde com **outro send normal** carregando `re: <send-id-original>`. Sender vê a reply na inbox no próximo turn. `agent_request` continua disponível apenas como comportamento legado/deprecado; o fluxo preferido é `agent_send` + reply assíncrona.

---

## Cross-PC routing

Hoje cross-PC é mediado pelo relay (não P2P direto — fica pra futuro).

A Extension `0.6` inclui por uma release um label wire legado para a janela
mixed-version. Nova↔antiga funciona quando os dois lados selecionam o mesmo
nickname assinado, único e sem `:`, ou quando nenhum tem nickname e ambos usam o
prefixo de 8 caracteres da chave Base64 padrão canônica. Nicknames com delimitador
ou colisão e visões divergentes de nickname não são cobertos; o receptor antigo
pode descartá-los silenciosamente. Por isso todos os participantes Extension/MCP
devem ser atualizados na mesma janela de manutenção, não gradualmente.

### Frame wire WS (Pi-A → Relay)

```jsonc
{
  "type": "pi_envelope",
  "to_pc": "<Pi-B-key Base64 RFC 4648 padrão com padding>",
  "envelope": {
    "from": "<label-wire-legado-de-A>:/Users/alice/projeto@frontend",
    "to": "<label-wire-legado-de-B>:/home/bob/projeto@backend",
    // demais campos do envelope
  }
}
```

### Frame entregue pelo relay (Relay → Pi-B)

```jsonc
{
  "type": "pi_envelope_in",
  "from_pc": "<Pi-A-key canônica Base64 RFC 4648 padrão com padding, autenticada>",
  "envelope": { /* envelope encaminhado */ }
}
```

### Autorização e anti-spoof

Antes de consultar presença do destino, o Relay permite `A → B` somente se encontrar **um** blob corretamente assinado por um Owner que liste diretamente ambas as Pi-keys. Essa checagem valida assinatura e conteúdo, mas não prova que o Owner pareou ou controla qualquer Pi. Não há fechamento transitivo: `{A,B}` e `{B,C}` não autoriza `A → C`. Um membro malformado invalida toda a contribuição daquele Owner. O cache por remetente é limitado a 1.024 entradas; grants positivos expiram em até 60 segundos e misses negativos em 1 segundo.

No receptor, `from_pc` canônico e autenticado é a única identidade técnica: ele deve pertencer ao snapshot de irmãos diretos, ou o frame é rejeitado. O receptor substitui o prefixo de `envelope.from` pelo seu alias local para essa chave e remove só o prefixo de apresentação/compatibilidade de `envelope.to`, pois `to_pc` já selecionou o destino técnico. Texto de nickname/prefixo enviado pelo remetente nunca é identidade nem regra anti-spoof.

### Erros de transporte com proveniência confiável

O relay envia erros como o seguinte `pi_envelope_in` reservado:

```jsonc
{
  "type": "pi_envelope_in",
  "from_pc": "_relay",
  "envelope": {
    "from": "_relay",
    "to": "<endereço original não vazio ou _unknown>",
    "id": "<UUID válido para o parser da Extension; atualmente UUIDv4>",
    "re": "<UUID original válido ou null>",
    "body": {
      "type": "transport_error",
      "reason": "offline | not_authorized | bad_envelope"
    }
  }
}
```

Somente esse outer autenticado, com essa gramática interna exata, reason fechado e correlação UUID válida, pode virar localmente `from: "broker"` e liquidar uma operação pendente. Um erro confiável é consumido internamente no máximo uma vez. Frames outer privilegiados `_relay` malformados são descartados. Já conteúdo com forma `transport_error` de um peer comum — inclusive texto `_relay` — continua conteúdo comum de inbox/handler, mas nunca liquida pending maps nem ganha proveniência `broker`.

### Compatibilidade e rollout

Implante o Relay `0.3` primeiro: uma Extension antiga pode consumir os erros UUID do Relay novo. Depois coordene a atualização para Extension `0.6` e minimize o período com Extensions antigas e novas, pois a interoperabilidade de wire labels mistos fora dos casos limitados descritos acima permanece adiada. A Extension `0.6` aceita o ID legado lowercase de 32 hex apenas no caminho autenticado e fechado de erro `_relay`, para Relay antigo ou rollback do Relay; esse shim não é o motivo de Relay-first ser seguro. Envelopes comuns continuam exigindo UUID.

---

## Mesh membership

`mesh_versions` é o "cartório" assinado pelo Owner.

### Estrutura

Blob canônico decodificado e assinado pelo Owner:

```json
{
  "version": 7,
  "issued_at": 1780000000000,
  "owner_pk": "<Owner-key Base64 padrão com padding, 32B>",
  "members": [
    { "remote_epk": "<Pi-key Base64 padrão com padding, 32B>", "relay_url": "wss://...", "paired_at": "2026-05-22T...", "nickname": "casa" },
    { "remote_epk": "<Pi-key Base64 padrão com padding, 32B>", "relay_url": "wss://...", "paired_at": "2026-05-23T...", "nickname": null }
  ]
}
```

O envelope wire/storage carrega esse JSON canônico como `blob` Base64 e sua assinatura Ed25519 como `sig` Base64:

```json
{
  "blob": "<Base64 padrão do JSON canônico acima>",
  "sig": "<Base64 padrão da assinatura Ed25519 do blob por owner_sk>"
}
```

`nickname` pode faltar, ser `null` ou string. Apenas contribuições Owner válidas que contêm diretamente a Pi local podem adicionar irmãos; histórico, transitividade e nickname não concedem confiança.

### Storage

Relay armazena o blob inteiro em SQLite, indexado por `owner_pk_hash`: SHA-256 em hexadecimal minúsculo dos 32 bytes brutos decodificados da Owner-key.

- **POST /mesh/<hash>**: cliente publica nova versão (relay verifica assinatura + version monotônica)
- **GET /mesh/<hash>**: cliente lê última versão; valida assinatura localmente

LWW (last-write-wins) em conflito concorrente. Anti-rollback via version monotônica.

### Self-revoke

Pi-extension faz polling periódico. Se sua Pi-pubkey saiu de `members`, faz self-revoke (sai do mesh) graciosamente.

Detalhes em `plan/24-mesh-membership.md`.

---

## App actions

Vocabulário curado de ações tipadas que o app mobile invoca sobre a sessão do Pi pareado. **Não é** um picker genérico de slash commands — cada ação tem payload estruturado e mapeia pra uma API pública do SDK. Pi-extension lida; app não parseia nada.

| Action | ClientMessage | SDK call no pi-extension |
|---|---|---|
| Compact context | `session_compact` | `ctx.compact()` |
| New session | `session_new` | `ctx.newSession()` |
| Set model | `model_set {provider, model_id}` | `ModelRegistry.find(...)` + `pi.setModel(model)` |
| Set thinking | `thinking_set {level}` | `pi.setThinkingLevel(level)` |
| List models | `list_models` | `ModelRegistry.getAvailable()` |

### Wire — exemplos

```json
// Request
{ "type": "session_compact", "id": "<uuid>" }

// Success reply
{ "type": "action_ok", "in_reply_to": "<uuid>", "action": "session_compact" }

// Failure reply
{ "type": "action_error", "in_reply_to": "<uuid>", "action": "session_compact",
  "error": "compact unavailable (no active session ctx)" }
```

```json
// Model list request → reply
{ "type": "list_models", "id": "<uuid>" }
{
  "type": "models_list",
  "in_reply_to": "<uuid>",
  "models": [
    { "id": "claude-opus-4-7", "name": "Claude Opus 4.7", "provider": "anthropic",
      "reasoning": true, "context_window": 200000 }
  ],
  "current": { "id": "claude-opus-4-7", "name": "Claude Opus 4.7", "...": "..." }
}
```

### Thinking levels (enum fixo)

```
"off" | "minimal" | "low" | "medium" | "high" | "xhigh"
```

`"xhigh"` só é honrado em famílias de modelo específicas (Anthropic 4.x reasoning, OpenAI o-series). Pi cai pra um nível vizinho quando não suporta — sem erro.

### Side-effects

Os replies (`action_ok` / `models_list`) só confirmam dispatch. Efeitos visíveis chegam pelos canais normais:
- Compact concluído → `agent_chunk`/`agent_done` no chat
- Modelo trocado → evento `model_select` broadcast pra todos os owners conectados
- Nova sessão → `pair_ok` (ou equivalente) com novo `session_started_at`

### Por que ações tipadas em vez de picker genérico

O SDK `@mariozechner/pi-coding-agent` não expõe API genérica de invocação dos slash commands builtin (`/compact`, `/model`, `/fork`, `/copy`, etc.) — apenas alguns têm equivalente em `ExtensionContextActions`. Tentar espelhar o picker do TUI exigiria mirror manual da lista builtin + matriz de invocabilidade + UX de chip canonizado, com vários comandos sendo só hint informativo. Vocabulário tipado é mais simples, mais honesto, e cobre 100% das ações que fazem sentido em mobile. Padrão validado pelo adapter `pi-telegram` (mesmo abordagem: vocabulário curado, sem picker genérico).

Detalhes em `plan/28-pi-commands.md`.

---

## Imagens (plan/30)

`user_message` aceita um anexo de imagem inline (uma por mensagem hoje),
opcional e retrocompatível — mensagem só-texto não muda no fio.

### Wire
ClientMessage `user_message` ganha `images?`:

```jsonc
{ "type": "user_message", "id": "msg-1", "text": "o que é isto?",
  "images": [{ "data": "<base64>", "mime": "image/jpeg" }] }
```

`WireImage = { data: string /* base64 */, mime: string }`. O echo ServerMessage
`user_message` (broadcast a todos os owners) também carrega `images`, pra cada
device renderizar o mesmo balão.

### Mapeamento pro modelo
O Pi monta o content multimodal do SDK na ordem **imagem(ns) → texto**:
`[{ type:"image", data, mimeType: mime }, { type:"text", text }]` →
`sendUserMessage(content)`. `mime` (wire) vira `mimeType` (SDK). Sem `images` →
`sendUserMessage(text)` (string), idêntico ao anterior.

### Capacidade do modelo
`WireModel` (em `models_list` / `current`) ganha `vision: boolean`, derivado de
`Model.input.includes("image")`. O app desabilita o anexo quando o modelo ativo
tem `vision:false`.

### Transporte
A imagem vai **inline** na `user_message` (base64), dentro do `ct` atual: no caminho App↔Pi ele pode ser encaminhado sem parse, mas é Base64 de JSON em claro, não ciphertext/E2E, e o operador do relay pode lê-lo. Custo: double-base64 (~+77%),
aceito nesta fatia por usar imagem comprimida (~150–400 KB). Histórico/
`session_sync` trafega os bytes (decisão #8). Canal binário fica pra Trilha 2.

---

## Mensagem enfileirada durante turn ativo

Fila curta **Pi-side, em memória**, de propriedade do Android: enquanto há turn
ativo, o app pode guardar próximos prompts textuais de follow-up. A
Pi-extension drena um item quando o turn atual acaba. Não é fila offline do
relay; restart perde o estado.

### Wire

```jsonc
// app → Pi-extension
{ "type": "queued_message_set", "id": "msg-2", "text": "próximo prompt" }
{ "type": "queued_message_clear", "id": "clear-1", "target_id": "msg-2" }
{ "type": "queued_message_clear", "id": "clear-all" }

// Pi-extension → app(s)
{
  "type": "queued_message_state",
  "id": "msg-2",
  "text": "próximo prompt",
  "items": [
    { "id": "msg-2", "text": "próximo prompt", "editable": true, "created_at": 1782250000000 }
  ]
}
{ "type": "queued_message_state", "items": [] } // vazio
```

### Semântica

- `queued_message_set`: cria/substitui uma pendência textual Android-owned. `id`
  vira o id do `user_message` drenado.
- `queued_message_clear.target_id`: cancela um item. Sem `target_id`, cancela
  todos os itens Android-owned (compat com o antigo clear de slot único).
- Enquanto o Pi está ocupado, cada mudança broadcasta o estado completo para
  todos os owners conectados.
- Se `queued_message_set` chega quando o Pi já está idle, a extensão drena
  imediatamente como `user_message` normal e broadcasta estado vazio, para não
  deixar item preso esperando um turn futuro.
- Drain: quando `currentTurnId == null`, `working != true` e não há compaction
  ativa, remove um item, broadcasta `queued_message_state`, faz handoff para o
  SDK, e só então ecoa `user_message` normal para todos os owners.
- `session_sync`: envia o `queued_message_state` atual antes do histórico.
- Só texto. `images` seguem apenas no `user_message` imediato.
- Filas internas do Pi/TUI não são expostas/editáveis neste MVP: a extension API
  não fornece ids estáveis nem mutação segura dessa fila.
- Relay inalterado; não há E2E e o operador do relay pode ler o conteúdo atual.

---

## Pareamento

QR code mostra Pi-pubkey + room hint + token de uso único.

1. App escaneia QR, conecta no relay como peer efêmero
2. App envia `pair_request` assinado com **Owner-sk** (prova autoridade)
3. Pi-extension valida assinatura, adiciona App-key na sua `peers.json` local
4. App adiciona Pi-pubkey no seu `mesh_versions` local + publica versão nova no relay
5. Pi-extension passa a aceitar mensagens daquele Owner

Múltiplos Owners podem parear o mesmo PC (concomitância — `peers.json` aceita N entries).

Detalhes em `plan/04-pairing.md`.

---

## Modelo de proteção (Trust Model)

### O que está protegido

- **Pareamento autenticado**: pair_request assinado pela Owner-sk; spoofing requer Owner-sk
- **WS pro relay sobre TLS**: ninguém na rota (ISP, NAT, MITM clássico) vê o tráfego em claro
- **Cross-PC checagem assinada**: o Relay só encaminha quando encontra um blob corretamente assinado que liste diretamente ambas as Pi-keys, sem transitividade. Isso não prova pareamento ou controle pelo Owner
- **Anti-spoof entre Pis**: broker aceita somente `from_pc` canônico autenticado que exista entre irmãos diretos e renderiza seu alias local
- **Anti-rollback de membership em processo**: versão monotônica + assinatura rejeita regressão durante a vida da instância. O floor da Extension reinicia com o processo; `issued_at` é informativo e memberships não expiram. Persistência anti-rollback entre reinícios não é implementada
- **Pi-secret protegida**: Keychain do sistema (macOS Keychain / libsecret Linux desktop / Credential Manager Windows). Atacante precisa contexto do user logado E unlock do Keychain
- **Owner-secret protegida**: iOS Keychain / Android Block Store, sincroniza via iCloud/Google account; recuperável trocando de device

### O que NÃO está protegido (declarado honestamente)

- **Relay vê plaintext do conteúdo atual**. TLS protege o trânsito, mas App↔Pi usa `ct` como Base64 de JSON em claro (pode ser encaminhado sem parse, não é ciphertext), e conteúdo Pi↔Pi, controle/routing/erros e membership assinada são parseados em memória pelo relay conforme necessário. Operador vê quem manda para quem e o conteúdo. Mitigação: **self-hosting** do relay (open source)
- **Não há E2E** entre app e pi-extension nem entre Pis cross-PC. **Não afirmamos E2E em copy nenhuma do produto**
- **Headless Linux** (Docker, VPS sem D-Bus session): Pi-key cai pra arquivo `0600` em disco com warning loud. Atacante com acesso ao user pode ler. Recomenda-se GNOME Keyring / KWallet pra hardening real
- **Backup encriptado completo** (Time Machine, iCloud Drive criptografado etc) pode carregar a Keychain. Atacante precisa do user passphrase do backup
- **Clone detection ainda não implementado**: 2 PCs com mesma Pi-key (via cópia de arquivo headless ou comprometimento) podem coexistir no relay sem alerta. Em roadmap (plan/27 Wave E3)

### Threat model resumido

| Adversário | Capacidade | Protegido? |
|---|---|---|
| Network passive | Sniff TLS | ✅ Sim (cipher TLS) |
| Network active (MITM) | Sniff + inject | ✅ Sim (TLS + Ed25519 pairing) |
| Operador do relay público | Lê tudo que passa, persiste | ⚠️ Parcial (mitigação: self-host) |
| Outro user no PC do alvo | Lê filesystem do alvo | ✅ Sim (Keychain user-bound) |
| Atacante com root no PC do alvo | Memory dump, processo injection | ❌ Não (modelo de threat aceitável: root = jogo perdido) |
| Atacante com backup do disco | Restaura disco em outro Mac | ✅ Sim em macOS com FileVault on (recomendado) |
| Atacante que rouba só `peers.json` | Vê metadata pública (Owner-pubkeys + nicks) | Privacy issue, não impersonation |

---

## Failure modes

| Falha | Comportamento |
|---|---|
| Relay desconecta | pi-extension reconnect com backoff; agentes locais continuam falando entre si via UDS broker |
| Pi-B offline durante envio cross-PC | Sender recebe `timeout` com `transport_error: offline` imediatamente. Sem queue offline no relay |
| Nenhum blob corretamente assinado lista Pi-A e Pi-B diretamente | Sender recebe `denied` com `transport_error: not_authorized`; a checagem ocorre antes de presença |
| Owner revoga Pi-A da mesh | Pi-A detecta na próxima poll de mesh_versions, faz self-revoke, sai gracefully |
| WS Pi reconecta frequente (NAT timeout) | Relay dedupa peer_online emit (transição offline→online apenas); cliente dedupa snapshots idênticos |
| Relay crash | Tudo cross-PC para; agentes locais continuam funcionando (UDS) |

---

## Roadmap arquitetural (público)

Curto prazo:
- Wave E2: `chmod 0o600` em `peers.json` + atomic write
- Wave E3: detecção de clone server-side (alerta quando 2 WS mesma Pi-pubkey de IPs diferentes)

Médio prazo:
- **Wrappers de harness** (`remote-pi claude`, `remote-pi opencode`): outros agentes coding plugam no broker UDS local via wrapper, ganham mesh sem reimplementar protocolo
- E2E cifragem do payload (Curve25519 + ChaCha20-Poly1305 entre App ↔ Pi; opcional cross-PC)

Longo prazo:
- PC-to-PC direto via WebRTC/QUIC (relay vira fallback)
- HW-bound Pi-key opcional via Secure Enclave (Apple Silicon) / TPM (Linux/Windows)

---

## Implementações de referência

- **Relay** (Rust, axum): [`relay/src/`](relay/src/)
- **Pi-extension** (Node/TS): [`pi-extension/src/`](pi-extension/src/)
- **App mobile** (Flutter): [`app/lib/`](app/lib/)
- **Planos arquiteturais**: [`plan/`](plan/) (especialmente `plan/03-protocol.md`, `plan/23-owner-key-sync.md`, `plan/24-mesh-membership.md`, `plan/25-pc-mesh-bootstrap.md`)

---

## Reportar problemas de segurança

[Definir canal] — por enquanto, abra issue marcando como `security` ou contate maintainers diretamente.
