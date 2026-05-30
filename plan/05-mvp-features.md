# Plano 05 — MVP features (chat + approval + reconexão)

Objetivo: tornar o app realmente útil. Depois do plano 04, temos canal
cifrado funcionando — mas não há chat UI, approval cards, indicador de
streaming, reconexão automática nem bridge entre o canal Noise e o
`AgentSession` do Pi SDK. Plano 05 fecha o MVP funcional.

Resultado esperado ao final: usuário pareia → vê o chat → digita → vê
resposta streamar → aprova tool calls inline → fecha o app e ao reabrir
reconecta sem novo QR. Se Pi fechar, app mostra offline em <5s.

**Este plano não cobre**: push notifications (parking, v2), revoke
remoto (só local), multi-pareamento UX rica (lista plana é suficiente),
TLS real (plan 06), deploy do relay (plan 06).

---

## Contexto

Estado dos subprojetos após plano 04:

- **app/lib/pairing/**: Noise XX SHA-256 sobre `cryptography`,
  `flutter_secure_storage`, scanner QR, tela de safety number.
  `handshake.dart#performHandshake` retorna `NoiseSession` (send/recv
  CipherStates) e persiste `PeerRecord`.
- **app/lib/protocol/**: sealed classes `ClientMessage` (4) +
  `ServerMessage` (7) + codec JSONL. Sem dependência de WS ainda.
- **pi-extension/src/pairing/**: gera QR, responde Noise XX, persiste
  peer no Keychain do Mac. Emite `runHandshakeResponder` que devolve
  CipherStates simétricos.
- **pi-extension/src/protocol/**: discriminated unions TS + codec
  (encode/decode + DecodeError + SERVER_TYPES guard).
- **pi-extension/package.json**: `@mariozechner/pi-coding-agent@0.73.1`
  já é dep — é o SDK que dá `AgentSession`.
- **relay/src/{auth,protocol}/**: Ed25519 challenge-response + parsing
  do outer envelope `{peer, ct}`. Já faz roteamento básico (foi feito no
  plano 01).

O que ainda não existe e plano 05 precisa entregar:

1. **WebSocket transport real** no app (até aqui só in-memory test)
2. **Bridge `AgentSession` ↔ canal Noise** no pi-extension (consumir
   user_message, emitir agent_chunk/done, trap tool calls)
3. **Chat UI** no app (lista de mensagens + input + indicador streaming)
4. **Approval cards inline** no app (diff/comando + allow/deny inline)
5. **Botão cancel** durante streaming
6. **Reconexão automática** no app (lê PeerRecord, refaz Noise XX)
7. **Estado offline** (banner + retry exponential)
8. **Settings screen** (ver pareamento atual, safety, revoke local)

Wave 2 do plano 04 (roundtrip integrado) está em parking — pode ser
fechada como parte deste plano, já que o chat funcionando é o teste
roundtrip por excelência.

---

## Decisões fixadas (do `00-decisions.md`, ainda válidas)

| Decisão | Valor |
|---|---|
| 1 pareamento = 1 sessão | Não há lista multi-sessão, switch_session ou histórico |
| Hierarquia plana: Pareamento ↔ Sessão (1:1) | UI navega direto do pair pro chat daquela sessão |
| Auto-approve read-only | `Read`, `Glob`, `Grep` rodam sem prompt |
| Approval obrigatório | `Bash`, `Edit`, `Write` sempre param |
| Timeout default 60s | `on_timeout=abort` — se user não respondeu, não executa |
| Sem push notification | Reconexão = on-demand quando user abre app |
| Sem revoke remoto | Cada lado limpa seu Keychain; outro lado falha no próximo reconnect |
| Heartbeat | Qualquer lado envia `ping` após 25s de idle |

---

## Decisões fechadas (2026-05-18)

**Q1 — state management Flutter**: ViewModel custom já estabelecido no
app. Stack: `ViewModel<T>` extends `ChangeNotifier` com single field
imutável e `emit()` (ver `app/lib/ui/core/viewmodel/viewmodel.dart`) +
`provider` + `auto_injector` (`CustomInjector` em
`app/lib/config/utils/injector.dart`). Convenção: sealed states em
`ui/<feature>/states/`, registro via `_injector.addViewModel<T>(T.new)`
em `setupDependencies`, wire no router com `ViewmodelProvider<T>()`.
**Não trocar essa stack.** Os CLAUDE.md das camadas já documentam.

**Q2 — granularidade streaming**: buffer 16ms (1 frame). Coalesce
chunks por frame de vídeo, sem flicker e sem latência perceptível.

**Q3 — comportamento offline**: bloquear input (TextField + botão
desabilitados). Banner explica o motivo. Evita fila stale.

**Q4 — revoke local no settings**: incluir. Botão "Esquecer pareamento"
+ confirmação → limpa Keychain → navega pra QR scanner. ~20 LOC.

**Q5 — virtualização do chat**: `ListView.builder` direto, sem
preocupação até 500 mensagens. Tunar quando dor aparecer (provavelmente
nunca pro MVP).

---

## Referência de design

`app/wareframe/` contém os mockups originais (HTML + JSX) e
`FLUTTER_GUIDE.md` (1452 linhas) — guia de tradução pra Flutter com
design tokens, TextStyle presets, componentes. **Agente App deve
consultar antes de implementar UI.**

⚠️ **Reconciliar com decisão 1:1**: o mockup tem 3 telas — `ScreenPair`,
`ScreenSessions`, `ScreenChat`. A `ScreenSessions` foi desenhada para o
modelo C (multi-sessão) revertido. No MVP atual ela se torna
desnecessária; o que aproveita é o card de "pareamento atual" pra a
`SettingsPage` (passo 8). O fluxo é: `ScreenPair` → `ScreenChat`
→ (drawer) `SettingsPage` (com elementos visuais do que era
`ScreenSessions`).

---

## Estrutura final esperada após este plano

```
remote_pi/
├── .orchestration/
│   ├── contracts/
│   │   └── (sem mudanças — protocol.md e pairing.md já cobrem)
│   └── results/
│       └── 05-NN-<task>.md
├── app/
│   └── lib/
│       ├── data/
│       │   ├── transport/
│       │   │   ├── ws_transport.dart      ← passo 1 (WebSocket real)
│       │   │   └── peer_channel.dart      ← passo 1 (Noise + protocolo)
│       │   └── repositories/
│       │       └── session_repository.dart ← passo 4 (state observable)
│       ├── domain/
│       │   └── session_state.dart          ← passo 4 (modelo)
│       ├── ui/
│       │   ├── chat/
│       │   │   ├── chat_page.dart          ← passo 5 (tela principal)
│       │   │   ├── message_bubble.dart     ← passo 5
│       │   │   ├── streaming_bubble.dart   ← passo 5 (com buffer 16ms)
│       │   │   ├── tool_request_card.dart  ← passo 6 (approval inline)
│       │   │   └── input_bar.dart          ← passo 5 (+ cancel button)
│       │   ├── offline_banner.dart         ← passo 7
│       │   └── settings/
│       │       └── settings_page.dart      ← passo 8
│       └── routing/
│           └── app_router.dart             ← passo 9 (pairing → chat → settings)
├── pi-extension/
│   └── src/
│       └── session/
│           ├── agent_bridge.ts             ← passo 2 (AgentSession ↔ canal)
│           ├── tool_gate.ts                ← passo 2 (auto-approve vs ask)
│           └── agent_bridge.test.ts        ← passo 2
└── relay/
    └── (sem mudanças — roteamento já funciona)
```

---

## Passo 1 — `app`: WebSocket transport + canal Noise integrado

**Função**: substituir o `_MemTransport` dos testes do plano 04 por
WebSocket real conectado ao relay. Envolver tudo em `PeerChannel` que
recebe/envia `ClientMessage`/`ServerMessage` (do `protocol/`) através do
canal Noise estabelecido.

**Arquivos**:
- `lib/data/transport/ws_transport.dart` — `NoiseTransport` over WS
- `lib/data/transport/peer_channel.dart` — encode/decode + criptografia

**Comportamento**:
- `PeerChannel.send(ClientMessage)` → JSON → `ClientCipherState.encrypt`
  → base64 → JSONL outer `{peer, ct}` → WS send
- WS receive → JSONL outer → base64 decode →
  `ServerCipherState.decrypt` → JSON → `ServerMessage.fromJson` → stream
- Falhas de decode → emit `error` evento; não derruba o canal

**Dependências novas** (`pubspec.yaml`):
- `web_socket_channel` — WebSocket cross-platform

**Critério de aceite**:
- `flutter test test/transport/` passa contra um `web_socket_channel`
  mock
- Roundtrip in-memory: `PeerChannel` initiator + responder trocam
  `user_message` ↔ `agent_chunk` corretamente

---

## Passo 2 — `pi-extension`: bridge `AgentSession` ↔ canal Noise

**Função**: consumir mensagens cifradas vindas do canal, traduzir para
chamadas no `AgentSession` do Pi SDK, e emitir respostas de volta.

**Arquivos**:
- `src/session/agent_bridge.ts` — orquestração principal
- `src/session/tool_gate.ts` — decide auto-approve vs ask
- `src/session/agent_bridge.test.ts` — mock `AgentSession`

**Fluxo**:
1. Canal recebe `user_message` → `AgentSession.send(text)`
2. `AgentSession` emite stream de eventos → para cada:
   - `text_delta` → emite `agent_chunk{in_reply_to, delta}`
   - `tool_call` (Bash/Edit/Write) → emite `tool_request{tool_call_id,
     tool, args}`; aguarda `approve_tool` com timeout 60s; se allow,
     executa via SDK; se deny, aborta turn
   - `tool_call` (Read/Glob/Grep) → executa direto sem ask; emite
     `tool_result` quando terminar
   - `done` → emite `agent_done{in_reply_to, usage?}`
3. Canal recebe `cancel{target_id}` → `AgentSession.abort(target_id)`;
   emite `cancelled{target_id}`
4. Canal recebe `ping{id}` → emite `pong{in_reply_to: id}`

**Auto-approve** (em `tool_gate.ts`):
- whitelist hardcoded: `["Read", "Glob", "Grep"]` → não emite request
- todos os outros → emite request, aguarda

**Critério de aceite**:
- Test com `AgentSession` mock: ciclo completo `user_message` → 3
  chunks → `agent_done`
- Test approval: `Bash` cmd → `tool_request` emitido → após
  `approve_tool deny`, turn aborta sem rodar comando
- Test auto-approve: `Read` cmd → direto pra `tool_result` sem
  intermediate

---

## Passo 3 — `app`: reconexão automática + estado offline

**Função**: ao abrir o app, se existe `PeerRecord` no Keychain, conecta
automaticamente. Detecta queda do canal e tenta reconectar com
exponential backoff.

**Arquivos**:
- `lib/data/transport/connection_manager.dart` — máquina de estados
  (connecting, online, offline, retrying) + backoff
- `lib/ui/offline_banner.dart` — banner

**Estados**:
```
[no_peer] → (parear) → [connecting] → (handshake OK) → [online]
                              ↓                          ↓
                         (handshake fail)             (WS close OR ping miss)
                              ↓                          ↓
                          [offline]  ← retry timer ← [retrying]
```

**Backoff**:
- 1s → 2s → 5s → 10s → 30s (capped)
- Reset ao chegar em `online`

**Ping miss**: app envia ping a cada 25s; se 2 pings sem pong (~50s+),
considera offline.

**Critério de aceite**:
- Test: simular WS close → estado vai pra `retrying` → backoff incrementa
- Test: simular handshake fail (fingerprint mismatch) → estado vai pra
  `offline` permanente com erro distinto
- Banner aparece em <100ms quando estado vira `offline` ou `retrying`

---

## Passo 4 — `app`: state management + session repository

**Função**: source of truth do estado da sessão (lista de mensagens,
streaming atual, tool requests pendentes, estado de conexão).

**Arquivos**:
- `lib/domain/session_state.dart` — modelo imutável
- `lib/data/repositories/session_repository.dart` — orquestra
  `ConnectionManager` + `PeerChannel`, expõe stream/signal do estado

**Modelo** (`session_state.dart`):
```dart
class SessionState {
  final ConnectionStatus connection;
  final List<ChatMessage> messages;
  final StreamingMessage? streaming;
  final List<PendingTool> pendingTools;
  // ...
}

sealed class ChatMessage { ... }
class UserMsg extends ChatMessage { ... }
class AssistantMsg extends ChatMessage { ... }
class ToolEvent extends ChatMessage { ... }  // request + result colapsados
```

**Critério de aceite**:
- Decisão Q1 aplicada (Riverpod / signals_flutter / provider)
- Test: enviar `user_message` → estado ganha `UserMsg` → stream de
  `agent_chunk` → `streaming` cresce → `agent_done` → `streaming` vira
  `AssistantMsg` e `streaming` zera

---

## Passo 5 — `app`: tela de chat

**Função**: viewport com mensagens, input bar, indicador streaming.

**Arquivos**:
- `lib/ui/chat/chat_page.dart` — Scaffold com lista + input
- `lib/ui/chat/message_bubble.dart` — user/assistant bubbles
- `lib/ui/chat/streaming_bubble.dart` — bolha que cresce em tempo real
  (buffer 16ms — decidido em Q2)
- `lib/ui/chat/input_bar.dart` — TextField + send/cancel button

**Comportamento**:
- `ListView.builder` reverse=true (mensagens novas no bottom, scroll
  invertido — padrão chat)
- Auto-scroll pra bottom quando chega chunk novo (mas pausa se user
  scrollou pra cima)
- Input desabilitado quando offline ou quando streaming ativo
- Botão envia vira "cancel" durante streaming (dispara `cancel{target_id:
  <id da user_message atual>}`)

**Critério de aceite**:
- Test widget: input → send → bubble user aparece → chunks → bubble
  assistant cresce → done → bubble final
- `flutter test integration_test/chat_test.dart` (mock channel) passa
- Visual: rodar `flutter run` no simulador, conversa flui

---

## Passo 6 — `app`: approval cards inline

**Função**: quando chega `tool_request`, exibir um card inline (no fluxo
da conversa) com diff/comando + botões allow/deny. Bloqueia visualmente
mas não bloqueia o canal (outras mensagens continuam fluindo).

**Arquivo**: `lib/ui/chat/tool_request_card.dart`

**Conteúdo do card**:
- Header: nome do tool (Bash, Edit, Write)
- Body por tipo:
  - `Bash`: comando em `<pre>` com font monospace
  - `Edit`: file path + diff (red/green linhas)
  - `Write`: file path + preview (primeiras N linhas)
- Botões: `Approve` (verde) / `Deny` (vermelho)
- Timeout visível: countdown 60s
- Após decisão: card vira "approved"/"denied" + (se approved) result
  abaixo

**Critério de aceite**:
- Test widget: receber `tool_request{tool:"Bash"}` → card aparece →
  click "Deny" → `approve_tool{decision:"deny"}` despachado
- Test timeout: card mostra 60s countdown; ao zerar, envia auto-deny e
  card mostra "expired"
- Card auto-approve não aparece pra `Read`/`Glob`/`Grep` (esses nem
  chegam como `tool_request`)

---

## Passo 7 — `app`: offline banner

**Função**: banner amarelo no topo quando estado é `retrying` ou
`offline`.

**Arquivo**: `lib/ui/offline_banner.dart`

**Conteúdo**:
- `retrying`: "Conectando... próxima tentativa em Ns" + spinner
- `offline` (handshake fail / fingerprint mismatch): "Offline. Peer
  inválido." + botão "Re-parear"
- `online`: banner colapsa (height 0)

**Critério de aceite**:
- Test widget: state → `retrying` → banner aparece com countdown; state
  → `online` → banner some
- Estado `offline` por fingerprint mismatch oferece "Re-parear" que
  apaga PeerRecord e navega pra QR scanner

---

## Passo 8 — `app`: settings screen

**Função**: ver pareamento atual + safety number + botão revoke local.

**Arquivo**: `lib/ui/settings/settings_page.dart`

**Conteúdo**:
- Card do peer atual: nome (rename inline), safety number (6 emojis),
  `paired_at`, relay URL, peer pubkey (hex truncado)
- Botão "Esquecer pareamento" (revoke local, Q4): confirma → limpa
  Keychain → navega pra QR scanner
- (futuro): toggle "always allow Bash" / lista de tools auto-approved
  custom — não MVP

**Critério de aceite**:
- Test widget: revogar → Keychain limpo → ao restart app, vai pra QR
  scanner (não auto-reconnect)
- Rename inline: edita campo `name` no PeerRecord, persiste no Keychain

---

## Passo 9 — `app`: routing

**Função**: definir transições entre telas baseado no estado.

**Arquivo**: `lib/routing/app_router.dart` (atualizar do que existe)

**Fluxo**:
- `boot`:
  - se há `PeerRecord` válido → conecta, vai pra `chat`
  - se não → `qr_scanner`
- `qr_scanner` → scan QR → handshake → safety number page → `chat`
- `chat` → drawer/appbar abre `settings`
- `settings` → "Esquecer pareamento" → `qr_scanner`

**Critério de aceite**:
- Test integration: cold start sem peer → QR scanner. Cold start com
  peer válido → chat. Falha de fingerprint → tela de erro com "Re-parear"

---

## Passo 10 — Roundtrip integrado (fecha Wave 2 do plano 04)

**Função**: validar que tudo funciona end-to-end com cripto real.

**Cenário** (mesmo do passo 5 do plano 04, agora finalmente possível):
1. Sobe relay local (`cargo run` no relay)
2. Sobe pi-extension num Pi local (`pi --no-auto-quit` + `/remote-pi`)
3. App em simulador iOS escaneia QR (ou deep link no test)
4. Handshake fecha, safety number bate
5. App envia `user_message`, Pi processa via `AgentSession`
6. App vê `agent_chunk` streamar
7. Tool call `Bash` aparece como approval card; app aprova
8. Tool roda, `tool_result` chega, conversa continua
9. Mata o Pi → app mostra offline em <5s
10. Sobe Pi de novo (re-pareando) → reconnect automático (mesma sessão? ou nova?)

**Critério de aceite**:
- Cenário acima roda
- Wireshark/tcpdump no relay confirma que `ct` é opaco
- Reiniciar app reconecta automaticamente sem novo pareamento
- 2 Pi terminals na mesma pasta = 2 QRs distintos = 2 pareamentos
  independentes (não interfere)

---

## Definition of Done

- [x] Q1, Q2, Q3, Q4, Q5 fechados em conversa explícita (2026-05-18)
- [x] `app/lib/data/transport/{ws_transport,peer_channel,connection_manager}.dart` implementados (passos 1, 3)
- [x] `app/lib/data/repositories/session_repository.dart` + `domain/session_state.dart` (passo 4)
- [x] `app/lib/ui/chat/{chat_page,widgets/message_bubble,widgets/streaming_bubble,widgets/tool_request_card,widgets/input_bar}.dart` (passos 5, 6)
- [x] `app/lib/ui/chat/widgets/offline_banner.dart` + `app/lib/ui/settings/settings_page.dart` (passos 7, 8)
- [x] `app/lib/routing/app_router.dart` atualizado (passo 9) — go_router + boot redirect
- [x] `pi-extension/src/session/{agent_bridge,tool_gate,agent_bridge.test}.ts` (passo 2)
- [x] Contrato `pairing.md` atualizado com campos `epk` + device-singleton Ed25519
- [x] `flutter test` no app passa (76/76 após wiring final) — unit + widget
- [x] `pnpm test` no pi-extension passa (36/36)
- [x] Wiring final completo (App): `_productionConnectionFactory` real + PairingViewModel + PairingPage wired (zero `UnimplementedError`)
- [x] Wiring runtime (Relay): `TcpListener::bind("0.0.0.0:3000")` + `tokio-tungstenite accept_async` + auth loop usando `auth/challenge.rs` + peer registry `HashMap<peer_id, Sender>` + roteamento por outer envelope + graceful shutdown
- [x] Wiring runtime (pi-extension slash): `/remote-pi`, `/remote-pi list`, `/remote-pi revoke` registrados como slash commands via ExtensionFactory; event wiring usa `pi.on("tool_call"|"message_update"|"tool_execution_end"|"agent_end")` em vez do `beforeToolCall` (limitação do SDK documentada)
- [x] Wiring runtime (pi-extension PeerChannel real): `src/transport/{relay_client,peer_channel}.ts` — WS auth Ed25519 + ChaCha20-Poly1305 IETF encrypt/decrypt + outer envelope + `runHandshakeResponder` plugado no cmdPair (stub removido)
- [x] Default URL/porta alinhado nos 3 lados: `http://localhost:3000` (env `REMOTE_PI_RELAY` no app/extension, `REMOTEPI_RELAY_PORT` no relay)
- [ ] Roundtrip do passo 10 passa em simulador (manual: precisa relay rodando + Pi local + device/simulador)
- [ ] Banner offline aparece em <5s após Pi fechar (depende do roundtrip)
- [ ] Reconnect automático funciona após app fechar e reabrir (depende do roundtrip)
- [ ] Approval card para `Bash` aparece, `Read` é auto-approved sem UI (depende do roundtrip)
- [ ] Safety number bate visualmente entre Pi terminal e app (depende do roundtrip)
- [ ] Commit final por wave: `mvp: chat ui + approval + bridge + reconexão`

---

## Notas de execução

1. **Wave structure**:
   - Wave 0 (raiz): fechar Q1-Q5. Sem nova fonte de verdade — protocol.md
     e pairing.md já cobrem.
   - Wave 1 paralelo: passos 1+3+4 (app transport+conn+state) **e**
     passo 2 (pi-ext bridge). Roda em paralelo (cwds diferentes).
   - Wave 2 paralelo: passos 5+6+7+8+9 (app UI completa). Depende de
     Wave 1 do app.
   - Wave 3: passo 10 (roundtrip), sequencial e manual.

2. **State management em Wave 1**: Q1 precisa estar fechado antes de
   começar a Wave. O passo 4 depende dessa decisão.

3. **`AgentSession` API**: confirmar com `@mariozechner/pi-coding-agent`
   docs como o stream de eventos funciona (text_delta vs tool_call vs
   done). Se a API mudar, ajustar `agent_bridge.ts` sem mexer no
   contrato.

4. **Não inventar UI complexa**: chat é lista linear + bubbles + input.
   Sem animações exageradas, sem drag-to-react, sem markdown rendering
   (chunks de texto puro no MVP). Plano 06 ou v2 podem adicionar.

5. **Approval card é parte do fluxo, não modal**: aparece inline na
   conversa. Fica no histórico depois de approved/denied (deixa rastro
   visual do que aconteceu).

6. **Cancel é "stop generation" não "delete"**: cancela o turn em curso
   no Pi, mensagens já recebidas ficam.

7. **`flutter_secure_storage` em simulador iOS**: usar
   `IOSOptions.defaultOptions` com accessibility apropriada. Plan 04 já
   deixou isso configurado em `pairing/storage.dart`.

---

## Próximos planos

- **`06-relay-deploy.md`** — onde hospedar (Fly.io? Railway? self-hosted
  Hetzner?), TLS real (Let's Encrypt), cert pinning no app contra a cert
  real, instruções de self-host pra usuários paranoicos
- **`07-revoke-and-multi-session.md`** (eventual, **só com demanda
  real**) — revoke remoto (Pi mantém revogations list), multi-pareamento
  com lista UX, switch de pareamento por gesto
- **`08-app-polish.md`** (eventual) — markdown rendering, code
  highlighting, copy-message, search in history, dark mode toggle
