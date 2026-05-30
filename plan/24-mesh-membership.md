# Plano 24 — Membership do Owner persistida no relay

Objetivo: persistir a **lista de peers (Pis) + nicknames** que pertencem a um Owner num storage com estado no relay, assinada pela Owner-key, com recuperação automática ao reinstalar app ou trocar de device. Resolve diretamente o cenário observado pós-Wave 2 do plan/23: "reinstalei o app, identidade voltou via iCloud, mas peers sumiram → app vai pra welcome".

Esta é a **primeira pavimentação concreta** da visão PC-mesh (ver memory `project-vision-pc-mesh`). Aqui o relay deixa de ser stateless e vira "cartório de cópias autenticadas": guarda blobs assinados pela Owner-sk, qualquer cliente verifica localmente.

---

## Contexto e relação com plan/23

Pós-Wave 2 do plan/23:
- Owner-key sincroniza via iCloud Keychain / Block Store (plugin `remote_pi_identity`)
- Lista de peers vive **só local** em `flutter_secure_storage` (sem `synchronizable`)
- Re-pareamento manual ao reinstalar/trocar device foi trade-off **aceito como temporário**

Este plano fecha esse gap, mantendo Owner-key onde está (plataforma) e movendo membership pro relay como autoridade assinada.

### O que muda na natureza do relay

Hoje (pós-plan 23):
- Stateful pra rooms/presence em memória (não persistido)
- Sem disco
- `~1k LOC Rust`

Após este plano:
- Stateful pra rooms/presence em memória **+ persistência de mesh_versions em SQLite**
- Schema de uma tabela
- ~150-250 LOC novas

Continua **neutro**: relay valida assinatura mas nunca decide membership — só armazena o que foi assinado pelo Owner. Comprometer o relay permite negar serviço, não forjar membership (sem Owner-sk).

Revisão formal de decisão fixada: `00-decisions.md` linha "Relay stateless" passa a precisar de strikethrough com nota apontando este plano.

---

## Decisões fixadas neste plano

| Decisão | Valor |
|---|---|
| Autoridade | Owner-key (Ed25519) é a única fonte de verdade. Relay verifica assinatura, nunca decide membership |
| Storage no relay | **SQLite** (uma tabela `mesh_versions`). Embedded, sem servidor adicional. Self-hosting continua trivial |
| Versionamento | Monotônico crescente (`version: int`). Anti-rollback: cliente rejeita versão menor que a última vista local |
| Concorrência | **Last-write-wins** (LWW). Dois devices editando ao mesmo tempo → último a publicar ganha. Cliente que perdeu re-busca e percebe sobrescrita. Aceito pra MVP por simplicidade |
| Conteúdo do blob | **Plaintext signed** — relay armazena JSON assinado mas em claro. Relay sabe topology social (quem é dono de quais Pis, nicknames). Coerente com modelo de relay público + recomendação de self-hosting |
| Cifrar nicknames? | **Não no MVP.** Trade-off documentado. Variante "blob cifrado opaco" fica como evolução se demanda real aparecer |
| Endpoint HTTP | `POST /mesh/<owner_pk_hash>` (escrita), `GET /mesh/<owner_pk_hash>` (leitura). HTTP separado do WebSocket — relay já expõe `/health` em port separada, modelo análogo |
| Identificação | `owner_pk_hash = sha256(owner_pk)` na URL. `owner_pk` raw no body pra verificação |
| Quem publica | Qualquer device com Owner-sk (no plan/23 todos os devices móveis têm via Keychain). Assinatura prova autorização |
| Pi-extension | Consome mesh_versions ao iniciar + periodicamente (polling). Se não está mais listado, se desliga (self-revoke) |
| Backup do SQLite | Operacional do relay. Não é responsabilidade do plano de protocolo |

---

## Decisões fechadas (2026-05-23, defaults pra Wave 1)

- **Q1 — Periodicidade do polling**: **60s em foreground** + leitura on-demand em boot, reconexão WS e mutações. Push via WS fica como otimização futura.
- **Q2 — Retenção de versões**: **só última versão por `owner_pk_hash`** (UPSERT). Sem histórico no MVP.
- **Q3 — Primeiro mesh_versions**: cliente sempre `GET` antes de `POST`. Se relay retorna `404`, assume `current_version = 0` e publica `version: 1`. Concorrência inicial resolve via LWW (último vence).
- **Q4 — Limite de tamanho**: **cap defensivo de 500KB** no relay (responde `413 Payload Too Large` se body acima). Cliente não impõe cap de N peers — confia que 500KB é folga absoluta na prática.
- **Q5 — Cliente que perdeu LWW**: detecta comparando blob publicado com blob retornado no próximo poll. **Loga warning + aceita a perda silenciosamente.** Sem retry automático no MVP.

---

## Estrutura final esperada

```
remote_pi/
├── relay/
│   ├── Cargo.toml                            ← adiciona rusqlite, sha2, ed25519-dalek (já tem)
│   ├── src/
│   │   ├── lib.rs
│   │   ├── main.rs                           ← inicializa SQLite + monta router HTTP
│   │   ├── mesh/                             ← novo módulo
│   │   │   ├── mod.rs
│   │   │   ├── store.rs                      ← SQLite wrapper (upsert/get por hash)
│   │   │   ├── handler.rs                    ← HTTP handlers GET/POST
│   │   │   ├── verify.rs                     ← validação Ed25519 + monotonic version
│   │   │   └── types.rs                      ← MeshBlob, MeshVersion structs
│   │   └── handlers/...
│   ├── tests/mesh_test.rs                    ← integration: post + get + anti-rollback
│   └── migrations/
│       └── 001_mesh_versions.sql             ← schema inicial
├── app/
│   ├── lib/
│   │   ├── data/mesh/                        ← novo módulo
│   │   │   ├── mesh_client.dart              ← HTTP client contra o relay
│   │   │   ├── mesh_blob.dart                ← (de)serialização canônica + assinatura
│   │   │   └── mesh_sync_service.dart        ← orquestra publish/consume + poll
│   │   ├── pairing/storage.dart              ← PairingStorage vira cache; source é MeshClient
│   │   └── config/dependencies.dart          ← registra MeshClient + MeshSyncService
│   └── test/data/mesh/...
├── pi-extension/
│   ├── src/
│   │   ├── mesh/                             ← novo módulo
│   │   │   ├── client.ts                     ← HTTP fetch + verify Ed25519
│   │   │   └── self_revoke.ts                ← poll + se-desliga
│   │   └── index.ts                          ← inicia mesh client ao bootstrap
│   └── src/mesh/client.test.ts
└── plan/24-mesh-membership.md                ← este arquivo
```

---

## Estrutura do mesh blob (canonical)

```json
{
  "version": 18,
  "issued_at": 1747958400000,
  "owner_pk": "<base64>",
  "members": [
    {
      "remote_epk": "<base64>",
      "relay_url": "https://relay-rp1.jacobmoura.work",
      "paired_at": "2026-05-15T10:30:00Z",
      "nickname": "Mac do trabalho"
    },
    ...
  ]
}
```

Wrapper assinado (o que vai no body do POST e no banco):

```json
{
  "blob": "<base64 do JSON acima, canonicalized — chaves ordenadas, sem espaços>",
  "sig": "<base64 da Ed25519 sig sobre blob bytes>"
}
```

Canonicalização importa pra verificação determinística — diferentes serializadores JSON podem gerar bytes diferentes pro mesmo objeto lógico. Decisão: usar JSON com chaves ordenadas alfabeticamente + separadores `,` e `:` sem espaços. Mesma regra em Dart, Rust, TypeScript.

---

## API HTTP

### `POST /mesh/<owner_pk_hash>`

Request body:
```json
{
  "blob": "<base64>",
  "sig": "<base64>"
}
```

Servidor:
1. Decodifica `blob` (base64 → bytes JSON)
2. Parse pra extrair `owner_pk` e `version`
3. Verifica `sha256(owner_pk) == owner_pk_hash` na URL
4. Verifica `Ed25519::verify(blob_bytes, sig, owner_pk)`
5. Lê versão atual do banco. Se existe e `new_version <= current_version` → 409 Conflict
6. UPSERT na tabela
7. 200 OK com `{version, updated_at}`

Respostas:
- `200 OK` — gravado
- `400 Bad Request` — JSON inválido, base64 quebrado, version não numérico
- `403 Forbidden` — assinatura inválida ou owner_pk_hash não bate
- `409 Conflict` — version não é maior que current (caller deve re-fetch e re-tentar)
- `413 Payload Too Large` — blob > 500KB (defensivo)

### `GET /mesh/<owner_pk_hash>?since=<version>`

Query opcional `since`. Se `current_version <= since`, retorna 304 Not Modified (cliente já tem a última).

Response body (200):
```json
{
  "blob": "<base64>",
  "sig": "<base64>",
  "version": 18,
  "updated_at": 1747958400000
}
```

Respostas:
- `200 OK` — retorna versão atual
- `304 Not Modified` — cliente já está atualizado
- `404 Not Found` — owner_pk_hash nunca foi publicado

**Notas**:
- Endpoint não exige autenticação — qualquer um que conheça `owner_pk_hash` pode ler. Mas só quem tem Owner-sk pode forjar uma versão assinada. Modelo de "público mas verificável", coerente com `assetlinks.json` ou DNS TXT records.
- Rate limit por IP + por owner_pk_hash recomendado (mesma postura do relay WS).

---

## Schema SQLite

```sql
CREATE TABLE IF NOT EXISTS mesh_versions (
    owner_pk_hash TEXT PRIMARY KEY,
    owner_pk      BLOB NOT NULL,    -- raw 32 bytes pra evitar re-derivação
    version       INTEGER NOT NULL,
    blob          BLOB NOT NULL,    -- bytes JSON canonical
    sig           BLOB NOT NULL,    -- 64 bytes Ed25519
    updated_at    INTEGER NOT NULL  -- ms epoch
);

CREATE INDEX idx_mesh_updated ON mesh_versions(updated_at);
```

Single-table, UPSERT por `owner_pk_hash`. Simples, atômico, suficiente.

---

## Waves

### Wave 1 — Relay: SQLite + endpoints HTTP + verify

**Localização**: `relay/src/mesh/`

**Mudanças**:
- Adicionar dependência `rusqlite` (com bundled SQLite — sem dep externa)
- Adicionar `sha2` pra computar `owner_pk_hash`
- `ed25519-dalek` já existe (usado no challenge-response)
- Novo módulo `mesh/`:
  - `store.rs` — `MeshStore::new(path)` abre conexão; `upsert(owner_pk_hash, blob, sig, version)`; `get(owner_pk_hash, since)`
  - `verify.rs` — `verify_blob(blob_bytes, sig, owner_pk) -> Result<MeshHeader, VerifyError>` retornando version + owner_pk extraído
  - `handler.rs` — handlers HTTP usando o mesmo framework do `/health` (provavelmente `axum` ou `hyper` direto)
  - `types.rs` — structs `MeshBlob`, `MeshEnvelope`
- Em `main.rs`: inicializa `MeshStore` + monta endpoints na porta HTTP do relay (mesma do `/health`, ou nova porta — decisão de ops)
- Migration aplicada idempotentemente no boot
- Testes em `relay/tests/mesh_test.rs`: post válido → get → post v2 → get retorna v2; post v1 depois de v2 → 409; assinatura inválida → 403; hash não bate → 403

**Critério de aceite**:
- `cargo test` passa cobrindo os caminhos acima
- `cargo clippy -- -D warnings` passa
- Endpoint manualmente acessível via `curl` no relay local

### Wave 2 — App: cliente mesh + publish + consume

**Localização**: `app/lib/data/mesh/`

**Mudanças**:
- `MeshClient` — HTTP client usando `dio` (já no app); métodos `post(envelope)`, `get(ownerPkHash, since)` retornando `Result<MeshEnvelope, AppException>`
- `MeshBlob.signWith(ownerSk)` — monta envelope assinado
- `MeshBlob.verify(ownerPk)` — valida sig
- `MeshSyncService`:
  - `publish(peers, nicknames)` — busca current version, monta v+1, assina, posta
  - `pullAndApply()` — busca, valida, atualiza `PairingStorage` local
  - `startPolling(interval: 60s)` — chama `pullAndApply` periodicamente quando app está em foreground
  - `pullOnDemand()` — chamado pelo router em momentos chave (boot, reconexão WS, deep link)
- `PairingStorage`: vira cache local hidratado por `MeshSyncService`. Mutações locais (parear novo Pi, rename, revogar) publicam via `MeshClient`. Falha de rede → fica pendente, retenta no próximo poll.
- `dependencies.dart`: registra `MeshClient` + `MeshSyncService` no `auto_injector`
- Boot do app: se `OwnerIdentity.load()` retornou identity **e** `MeshSyncService.pullOnDemand()` retorna não-vazio → home; senão → welcome com "pareie seu primeiro Pi"

**Critério de aceite**:
- App reinstalado em iOS 26 device: identidade recupera + peers recupera → home direto
- Rename de peer reflete em outro device do mesmo Apple ID após ~60s
- Falha de rede em publish: muda local, fica pendente, retenta no próximo poll
- `flutter test` + `flutter analyze` zero issues

### Wave 2D — Pi-extension: multi-channel broadcast (2026-05-23)

Decisão arquitetural fechada nesta sessão: revisar 08-Q2 do registry em direção complementar à Wave 2C. Agora o **pi-extension** passa a suportar **N owners conectados simultaneamente**, todos compartilhando a mesma sessão do agent.

Razão: usuário não tem requisito de privacidade entre Owners pareados no mesmo Mac. Modelo mental "rede mesh assistindo a sessão" é coerente com a visão PC-mesh. Catch-22 atual ("pra parear novo, precisa stop, mas stop desconecta o atual") fica resolvido.

**Mudanças**:
- `_appPeerId: string | null` → `_activePeers: Map<string, PeerChannel>` em pi-extension/src/index.ts
- State machine: `idle` → `started`. Remove estado `paired` (vira métrica derivada `_activePeers.size > 0`)
- `_cmdPair`: sempre permite gerar QR (sem rejeição quando há outro active)
- `_cmdList`: mostra status `online/offline` por peer (não mais "active")
- `_handleSessionSync`: recebe sender channel como parâmetro; responde via channel que mandou (não via singleton)
- Helpers: `broadcastToActive(msg)` + `sendToSpecific(peerId, msg)`
- Auto-listener: roteia mensagens recebidas pro channel certo via sender peer_id no envelope
- `_messageBuffer` continua compartilhado (estado da sessão é global, todos os owners veem mesmo histórico)

**Trade-offs aceitos explicitamente**:
- Race em digitação simultânea — agent processa em ordem de chegada
- Conflito de aprovação — primeiro a aprovar vence
- Sem indicador de origem nas mensagens (pode adicionar no futuro via metadata opcional se virar dor)
- Owner offline durante sessão — perde o que aconteceu, mirror cache recupera na reconexão

**Critério de aceite**:
- Dois Owners diferentes pareados, ambos conectados simultâneo
- Pi-ext envia `agent_chunk` → ambos os apps renderizam paralelo
- Owner novo conecta → recebe history completo via session_sync
- `/remote-pi pair` gera QR mesmo se já tem owner conectado
- `/remote-pi revoke <id>` desativa só aquele owner; resto continua
- Testes cobrem broadcast multi-channel + sender-routing do session_sync

---

### Wave 3 — Pi-extension: self-revoke

**Localização**: `pi-extension/src/mesh/`

**Mudanças**:
- `MeshClient` (TypeScript) — fetch HTTP, verificação Ed25519 com `@noble/ed25519`
- `SelfRevoke` — polling periódico (60s) pra cada Owner que conhece (lê do `peers.json` o set de `owner_pk` distintos). Se ele próprio (`my_pubkey`) não está mais em `members` daquele Owner → revoga aquele pareamento local + desconecta
- Integração no bootstrap do pi-ext: inicia poll após conexão WS estabelecida
- Tratamento de 404: Owner nunca publicou mesh → assume "tudo OK por enquanto", continua. Owner pode nunca publicar se for cliente velho — backward-compat preservada

**Critério de aceite**:
- Pi-ext rodando, app revoga via outro device do mesmo Owner → pi-ext detecta em ≤60s e desconecta
- Pi-ext continua funcionando se Owner nunca publicou mesh_versions (cliente velho)
- `pnpm test` cobre verify + self-revoke logic

### Wave 4 — Roundtrip end-to-end

**Cenário**:
1. iPhone pareia Pi-A e Pi-B; nicknames "Mac trabalho" e "Mac casa"
2. App publica mesh_versions v3 (depois de pares e renames)
3. iPad mesmo Apple ID instala app → identidade desce via iCloud → `pullOnDemand` busca mesh → vê 2 peers → home conectado direto
4. iPhone revoga Pi-A → publica v4
5. iPad (em foreground): próximo poll (≤60s) detecta v4 → remove Pi-A do local
6. Pi-A (offline durante revoke): quando volta, próximo poll detecta que saiu de `members` → self-revoke + desconecta

**Critério de aceite**:
- Cenário acima roda end-to-end sem ação manual extra além das esperadas
- Trade-off LWW documentado se houver edição concorrente

---

## Definition of Done

### Wave 1 — Relay
- [ ] Migration SQLite aplicada no boot
- [ ] POST /mesh com validação Ed25519 + monotonic version
- [ ] GET /mesh com filtro `since`
- [ ] Testes de integração cobrem todos os códigos de status
- [ ] `00-decisions.md` atualizado: "Relay stateless" ganha strikethrough com referência a este plano

### Wave 2 — App
- [ ] `MeshClient` + `MeshSyncService` implementados
- [ ] Boot busca mesh antes de decidir welcome vs home
- [ ] Mutações locais (par/revoke/rename) publicam automaticamente
- [ ] Polling 60s em foreground
- [ ] Reinstalei app + identidade voltou → peers voltam → home direto

### Wave 3 — Pi-extension
- [ ] Cliente mesh + self-revoke implementados
- [ ] Pi-ext sai gracefully ao detectar revogação
- [ ] Backward-compat com Owners sem mesh_versions preservada

### Wave 4 — Roundtrip
- [ ] Cenário end-to-end valida em devices físicos
- [ ] Documentado no app: "sua lista de Pis sincroniza via relay"
- [ ] memory `project-vision-pc-mesh` atualizada: mesh_versions deixa de ser roadmap, vira fundação

---

## Trade-offs explícitos

- **Relay deixa de ser stateless.** Vira "neutro stateful" — não decide, só armazena assinado. Decisão "Relay stateless" do registry passa por strikethrough.
- **Topology social visível pro operador do relay.** Quem é dono de quais Pis + nicknames em claro. Mitigação: self-hosting. Variante "blob cifrado" fica como `plan/27` se demanda.
- **LWW pode perder edições concorrentes** silenciosamente. Aceito por simplicidade. Cenário raro em prática (dois devices editando exatamente o mesmo segundo).
- **Polling em vez de push**. ~60s de latência pra propagação. Aceitável pro caso de uso. Push via WebSocket fica como otimização futura.
- **404 quando Owner nunca publicou**: backward-compat com clientes velhos. Pi-ext não trava — só não tem mesh pra consultar.

---

## Não-objetivos

- **Sem suporte a múltiplos Owners por Pi.** Cada Pi pode estar pareado com 1 Owner (modelo de identidade do plan/23). Multi-tenancy fica fora.
- **Sem histórico de versões.** Só a última versão fica no banco. Audit log é roadmap separado se virar requisito.
- **Sem cifrar blob.** Plaintext signed. Variante cifrada fica como evolução.
- **Sem rate limiting estruturado no MVP.** Confia na postura geral do relay. Vale revisitar quando lançar publicamente.

---

## Próximos planos

- **`plan/25-pc-mesh-bootstrap.md`** — usar a primitiva `mesh_versions` pra autorizar PCs novos no mesh PC-to-PC. Celular assina entrada do PC novo na membership; outros PCs reconhecem via Owner-sig. WebRTC ou QUIC pra transporte P2P.
- **`plan/26-android-live-sync.md`** (opcional) — `MeshSyncService` no Android passa a usar Drive App Folder em vez de polling no relay pra latência menor de sync móvel-móvel.
- **`plan/27-mesh-encryption.md`** (opcional) — se topology social no relay virar problema, mover pra blob cifrado opaco com chave derivada da Owner-sk.
