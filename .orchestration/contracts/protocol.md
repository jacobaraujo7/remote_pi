# Protocol — Remote Pi

Fonte de verdade do protocolo de mensagens entre **app** (Flutter) e
**pi-extension** (Node), trafegando através do **relay** (Rust). Cada
subprojeto implementa tipos derivados desta spec; mudanças aqui disparam
realinhamento nos 3 lados.

> **Modelo MVP**: 1 pareamento = 1 sessão Pi. Sem session manager, sem
> project scope, sem switch_session. Ver `plan/00-decisions.md`.

> **Crypto E2E removida no plano 06** (2026-05-19). O `ct` do envelope
> externo é **base64 do JSON do inner em claro**. Relay continua opaco
> (nunca chama `JSON.parse(ct)`). O shape permanece igual ao desenhado
> originalmente — re-ativar Noise XX no futuro (plano 09 opcional) só
> troca o gerador/parser do `ct`, sem mexer em transporte ou schema.

---

## Camadas

```
┌──────────────────────────────────────────────────────────────────────┐
│  Inner envelope (app ↔ pi-extension)                                  │
│  Semântica do produto. JSON em claro.                                 │
│  Schema: { type, id?, in_reply_to?, ...payload }                      │
└──────────────────────────────────────────────────────────────────────┘
                              ▲
                              │  base64(JSON.stringify(inner))
                              ▼
┌──────────────────────────────────────────────────────────────────────┐
│  Outer envelope (relay)                                               │
│  Roteamento puro. Payload opaco ao relay (não decodificado).          │
│  Schema: { peer: "<id>", ct: "<base64>" }                             │
└──────────────────────────────────────────────────────────────────────┘
                              ▲
                              │  framing JSONL (\n)
                              ▼
                          WebSocket  +  Control frames (plano 12)
```

### Control frames (plano 12 — presence push)

Além de envelopes opacos `{peer, ct}`, o WebSocket transporta **control
frames** consumidos diretamente pelo relay (não roteados pra outro peer).
Distinguíveis pelo campo `type` no topo do JSON em vez de `peer`+`ct`:

```
              app ⇄ relay (frames próprios, não opacos)
┌──────────────────────────────────────────────────────────────────────┐
│  Control: hello, auth, subscribe_presence, presence_check,            │
│           peer_online (push), peer_offline (push), presence (resp)    │
│  Relay parseia esses tipos e responde / faz push                      │
└──────────────────────────────────────────────────────────────────────┘
```

Relay continua **opaco ao `ct`** dos envelopes — não decodifica payload
de roteamento. Mas aprende a ler `hello`/`auth` (auth, já existia) e
agora os 5 frames de presence.

---

## Decisões fixadas

| Decisão | Valor |
|---|---|
| Framing | **JSONL** (LF-delimited, UTF-8 estrito) |
| Envelope externo | `{ "peer": "<id>", "ct": "<base64>" }` (único que o relay parseia) |
| Conteúdo de `ct` | **base64 do JSON do inner em claro** (sem cifra, sem MAC) |
| Envelope interno | `{ "type": "<kind>", "id"?: "<uuid>", "in_reply_to"?: "<uuid>", ...payload }` |
| ID de correlação | **UUIDv7** (string) em qualquer mensagem que espera resposta |
| `in_reply_to` | Campo opcional em respostas, ecoa `id` da request |
| Versionamento | **Sem campo `v` no MVP** (v1 implícito) |
| Limite de tamanho | 1 MiB do `ct` base64-decoded (relay rejeita maior) |
| Heartbeat | Qualquer lado pode iniciar `ping` após 25s de idle; outro responde `pong` |

---

## Outer envelope

```json
{ "peer": "string-peer-id", "room": "string-room-id?", "ct": "<base64 do JSON inner>" }
```

> **`room` (plano 17)**: identifica sub-canal dentro do peer_id. Pi-ext
> deriva `room_id = base64url(sha256(realpath(cwd)))[:12]`. App envia
> `room: "main"` (cliente). Default ausente = "main". Permite múltiplas
> sessões Pi paralelas no mesmo Mac sem conflito de conexão no relay.

**Semântica do campo `peer` (muda com o sentido do tráfego)**:

| Fase | Significado de `peer` |
|---|---|
| Mensagem **saindo** do peer (app/pi-ext → relay) | **destino** — quem deve receber |
| Mensagem **chegando** num peer (relay → app/pi-ext) | **remetente** — quem mandou |

Relay reescreve o campo `peer` antes de encaminhar: substitui o destino pelo
`peer_id` do remetente autenticado. Assim, quem recebe sabe imediatamente quem
mandou e pode responder usando o mesmo valor como destino na próxima mensagem.

Relay também:
- Valida que `peer` (destino, no envio) é um peer conectado
- Mede tamanho de `ct` base64-decoded (rejeita > 1 MiB)
- Encaminha pro outro peer pareado
- **Nunca** chama `JSON.parse(ct)` — payload é opaco ao roteamento
- Logs proibidos de incluir o conteúdo de `ct` (princípio mantido pós-rollback E2E)

`peer_id` é base64 STANDARD (RFC 4648 §4, com `+/=`) da Ed25519 pubkey de
longo prazo, idêntico ao que o peer enviou no `hello` do challenge-response
(ver `pairing.md`).

---

## Control frames (relay, plano 12)

Frames trafegados **direto na WS** (sem envelope `{peer, ct}`), consumidos
pelo relay e/ou empurrados pelo relay. Identificáveis por `type` no topo.

### App → Relay

| `type` | Campos | Descrição |
|---|---|---|
| `hello` | `pubkey` (base64 Ed25519), `room_id?` (string, default `"main"`), `room_meta?: {name, cwd, model?}` (plano 17/18) | Auth + identifica sub-canal. Pi-ext usa room_id derivado do cwd; `model` é nome do modelo IA ativo (plano 18, opcional). App sempre `"main"` |
| `room_meta_update` | `room_id`, `meta: {model?}` | Plano 18: Pi envia ao detectar `model_select` event do SDK. Relay atualiza RoomMeta + broadcast `room_meta_updated` |
| `auth` | `sig` (base64) | Auth — já existia |
| `subscribe_presence` | `peers` (array de epk base64 standard) | Inscreve este peer pra receber `peer_online`/`peer_offline` dos epks listados. Idempotente: chamadas subsequentes substituem a lista. Lista vazia = unsubscribe all |
| `unsubscribe_presence` | `peers` (array) | Remove subset de peers do subscribe (opcional — chamar `subscribe_presence` com lista nova é equivalente) |
| `presence_check` | `peers` (array) | Pede snapshot pontual; relay responde com `presence` |
| `subscribe_rooms` | `peers` (array de epk) | Plano 17: inscreve pra receber `room_announced`/`room_ended` dos peers listados |
| `unsubscribe_rooms` | `peers` (array) | Remove subset de subscribe_rooms |
| `rooms_check` | `peers` (array) | Snapshot pontual; relay responde com `rooms` |

### Relay → App

| `type` | Campos | Descrição |
|---|---|---|
| `challenge` | `nonce` | Auth — já existia |
| `peer_online` | `peer` (epk) | Push: peer subscrito acabou de autenticar |
| `peer_offline` | `peer` (epk), `since_ts` (number, epoch ms) | Push: peer subscrito desconectou. `since_ts` é quando o disconnect aconteceu (relay knows) |
| `presence` | `states: [{peer, online: bool, since_ts: number\|null}]` | Resposta a `presence_check`. `since_ts` é quando peer entrou neste estado (null se sempre offline / sempre online — relay define) |
| `room_announced` | `peer` (epk), `room_id`, `name?`, `cwd?`, `model?` (plano 18), `started_at` | Plano 17 push: peer subscrito acabou de abrir uma room nova. `model` é o nome do modelo IA atual |
| `room_ended` | `peer`, `room_id`, `since_ts` | Push: room foi fechada (peer desconectou esse sub-canal) |
| `room_meta_updated` | `peer`, `room_id`, `meta: {model?}` | Plano 18: relay broadcast quando Pi enviou `room_meta_update`. App atualiza RoomInfo |
| `rooms` | `peer`, `rooms: [{room_id, name?, cwd?, model?, started_at}]` | Resposta a `rooms_check`. Lista todas as rooms ativas daquele peer (com `model` quando presente) |

**Regras**:
- Relay aceita subscribe sem validar identidade do peer alvo (zero-knowledge — qualquer epk pode ser monitorado)
- Subscribers desconectados são removidos automaticamente das subscriptions
- Broadcast acontece em `PeerRegistry.connect` (online) e `PeerRegistry.disconnect` (offline)
- Sem batching/throttle no MVP — adicionado em plano futuro via env vars

---

## Inner envelope — tipos do MVP

> **Approval gate removido (plano 10.2 revisado, 2026-05-19)**: o pi-extension
> do MVP **não usa** `approve_tool`. Tool calls executam direto, sem prompt.
> Quando ecossistema Pi padronizar permissions, plano futuro religa o gate
> sem mudar shape.
>
> **`tool_request` continua sendo emitido como notificação visual (plano 10.6,
> 2026-05-19)**: pi-ext envia `tool_request` via evento `tool_execution_start`
> do SDK assim que cada tool VAI executar — apenas pra app mostrar processo
> na timeline. Não bloqueia execução, não espera `approve_tool`. App segue
> recebendo `tool_result` no fim. Forward-compat: o tipo `approve_tool`
> permanece no contrato mas é silenciosamente ignorado pelo pi-ext.

Como 1 pareamento = 1 sessão Pi, **não há `session_id`** em mensagem
nenhuma. Cada conexão peer↔peer já é exclusiva daquela sessão.

### Direção: app → extension (cliente)

| `type` | Campos | Espera resposta? |
|---|---|---|
| `pair_request` | `id`, `token`, `device_name` | Sim → `pair_ok` ou `pair_error` |
| `user_message` | `id`, `text` | Sim → stream de `agent_chunk` + `agent_done` |
| `approve_tool` | `id`, `tool_call_id`, `decision: "allow" \| "deny"` | Não (continua o fluxo) |
| `cancel` | `id`, `target_id` | Sim → `cancelled` ou `error` |
| `ping` | `id` | Sim → `pong` |
| `session_sync` | `id`, `limit` (number, opcional — default 30, server clampa contra próprio env) | Sim → `session_history` com últimas N (mirror, não delta). Pós-plano 16 simplificado: sem `since_ts`/`session_started_at` no request |

### Direção: extension → app (servidor)

| `type` | Campos | Iniciado por |
|---|---|---|
| `pair_ok` | `in_reply_to`, `session_name`, `session_started_at` (number, epoch ms), `room_id` (string, plano 17 fix) | Resposta ao `pair_request` válido. App salva `room_id` no PeerRecord pra reconectar futuros (em vez de chutar "main") |
| `pair_error` | `in_reply_to`, `code`, `message` | Resposta ao `pair_request` inválido (ver `pairing.md`) |
| `user_input` | `id`, `text` | Push — input que o user digitou no terminal Pi (ou via RPC). Permite app espelhar perguntas que não vieram dele. `id` correlaciona com `agent_chunk`/`agent_done` subsequentes (`in_reply_to = id`) |
| `agent_chunk` | `in_reply_to`, `delta` | Push streaming |
| `agent_done` | `in_reply_to`, `usage?` | Push terminal |
| `agent_message` | `in_reply_to`, `text`, `usage?` | Usado **apenas** em `session_history`: representa uma resposta consolidada do agente (texto final). Em real-time o pareamento é `agent_chunk`* + `agent_done` |
| `tool_request` | `tool_call_id`, `tool`, `args` | Push (notificação visual; sem approval pós plano 10.2) |
| `tool_update` | `tool_call_id`, `tool`, `args`, `result?`, `details?` (objeto JSON) | Progresso de `tool_execution_update`; atualiza a mesma linha sem concluir tool ou turno. Ignorado se a linha já terminou |
| `tool_result` | `tool_call_id`, `result?`, `error?`, `details?` (objeto JSON) | Push após tool executar; detalhes estruturados também preservados no histórico |
| `session_history` | `in_reply_to`, `session_started_at` (number, diagnóstico), `events: [{ts, type, ...}]`, `eos` (bool), `truncated` (bool, plano 16) | Resposta a `session_sync` — **mirror das últimas N** (não delta). Eventos têm os mesmos shapes dos types acima (user_input, agent_message, tool_request, tool_result) com `ts` (epoch ms) adicional. Pós-plano 16: server sempre devolve em 1 frame (eos:true), `truncated` indica se Pi tem mais que o limit |
| `error` | `in_reply_to?`, `code`, `message` | Qualquer falha não-pair |
| `cancelled` | `in_reply_to`, `target_id` | Push após cancel |
| `pong` | `in_reply_to` | Resposta ao ping |
| `bye` | `reason: "peer_stop" \| "session_replaced" \| "shutdown"` | Push final antes de o pi fechar a conexão (graceful disconnect). App marca offline imediato e PARA tentativas de retry até user reconectar manualmente |

### Workflows pi-subagents (opcional, read-only)

`details` preserva os metadados públicos do resultado do Pi: `mode`,
`results[]`, `progress[]`, `workflowChildren` (inventário v1), estados e outputs
dos filhos. Scripts correlacionam filhos por `workflowKey`/`childId`, não
pelo `index` local de cada execução. O texto legível
continua em `result`/`error`; clientes antigos podem ignorar `details`.
Updates em andamento são reenviados depois de `session_history`, inclusive
quando o celular não recebeu o início da tool.

Background usa o RPC in-process `subagents:rpc:v1:request` com `method: status`,
reativo aos eventos públicos de lifecycle (coalescidos, sem polling periódico).
Snapshots v1 de `asyncSnapshot` viram linhas `subagent-run:<run-id>` com filhos
aninhados. Ausência do package/API é tolerada; erros RPC são logados.
O bridge não inicia nem controla runs. Mensagens custom `subagent-notify`
viram notificações de conclusão com ID estável e entram no replay do chat.

---

## Erros — códigos canônicos

Erros do `error` genérico (qualquer momento pós-pair):

| `code` | Significado |
|---|---|
| `unknown_peer` | App tentou enviar pra peer não pareado (não está em `peers.json` do Pi) |
| `tool_approval_required` | Tool call esperando approval; tentar de novo após `approve_tool` |
| `invalid_message` | Inner envelope mal formado (JSON inválido ou campos faltando) |
| `unsupported_type` | `type` não reconhecido pelo receiver (forward-compat) |
| `too_large` | `ct` > 1 MiB no outer |
| `rate_limited` | Cliente excedeu rate limit |
| `timeout` | Operação interna excedeu prazo (ex: tool sem `approve_tool` em 60s) |
| `internal_error` | Falha não esperada no servidor; ver logs do Pi |

Erros específicos do `pair_error` (resposta a `pair_request`):

| `code` | Significado |
|---|---|
| `token_expired` | QR expirou (>60s desde geração) |
| `token_consumed` | Token já foi usado por outro `pair_request` |
| `token_unknown` | Token não foi emitido por este Pi |
| `internal_error` | Falha ao persistir peer |

`ErrorCode` é **aberto**: receivers devem tolerar codes desconhecidos
(tratar como genérico) para forward-compat.

---

## Fixtures

Pasta `fixtures/` carrega 1 exemplo JSONL por `type`. Cada subprojeto
roda seu codec contra esses arquivos pra garantir que o shape bate em TS,
Dart e Rust simultaneamente. Mudanças aqui são **breaking** — alinhar os
3 codecs antes de comitar.

Lista atual em `fixtures/` (24 arquivos):
- **Pair (novos no plano 06)**: `pair_request.jsonl`, `pair_ok.jsonl` (com `session_started_at` desde plano 11), `pair_error.jsonl`
- **Client (inner)**: `user_message.jsonl`, `approve_tool.jsonl`, `cancel.jsonl`, `ping.jsonl`, `session_sync.jsonl` (plano 11)
- **Server (inner)**: `agent_stream.jsonl` (sequência de chunks + done), `user_input.jsonl` (plano 10.5), `agent_message.jsonl` (plano 11, usado em history), `tool_request.jsonl`, `tool_result.jsonl`, `session_history.jsonl` (plano 11), `error.jsonl`, `cancelled.jsonl`, `pong.jsonl`, `bye.jsonl`
- **Control frames (plano 12, fora do envelope)**: `subscribe_presence.jsonl`, `unsubscribe_presence.jsonl`, `presence_check.jsonl`, `peer_online.jsonl`, `peer_offline.jsonl`, `presence.jsonl`
