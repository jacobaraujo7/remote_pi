# 51 — `ask_user` no app via contrato `extension_ui_request`

## Contexto

Hoje, quando o agente chama `ask_user` (tool do pacote `@eko24ive/pi-ask`), o
fluxo abre no TUI do Pi no desktop. O usuário no celular fica preso — só
consegue destravar voltando ao cliente desktop. O [plano 42](./42-ask-user-cancel.md)
resolveu só o **cancelamento** (Stop remoto via `abort`). Este plano traz a
**renderização interativa completa** no app (responder de verdade pelo celular).

Direção do maintainer (plano 42, "próximo plano possível"): *espelhar o contrato
RPC/Cockpit `extension_ui_request` + `extension_ui_response`*.

### Achados da pesquisa

1. `extension_ui_request`/`extension_ui_response` é o contrato do SDK
   `pi --mode rpc`. Tipos canônicos: `RpcExtensionUIRequest` /
   `RpcExtensionUIResponse` em
   `@earendil-works/pi-coding-agent/dist/modes/rpc/rpc-types.d.ts`. Métodos
   interativos: `select` / `confirm` / `input` / `editor` (+ `notify`
   fire-and-forget; `setStatus`/`setWidget`/`setTitle`/`set_editor_text` são
   chrome do TUI).
2. O Cockpit (`cockpit/.../rpc_event_mapper.dart`) já mapeia esse contrato — mas
   em **RPC mode**. O **pi-extension roda o Pi em modo TUI**, onde o SDK **não**
   emite `extension_ui_request`. Logo o pi-extension não tem frames pra
   forwardar diretamente.
3. O pi-ask publica um contrato de eventos **same-process** (`pi.events`:
   `@eko24ive/pi-ask:started|submit|submit-result|completed`; doc
   `docs/remote-events.md`) que **dispara em modo TUI** e carrega o fluxo
   **completo** do `ask_user` (multi-pergunta, preview, notes, elaborate). É a
   única fonte viável no pi-extension. (Em modo não-TUI o pi-ask retorna
   `nonInteractiveResponse` — não bloqueia, não emite UI.)
4. Sem pi-ask instalado, a tool `ask_user` não existe → nenhum evento dispara →
   qualquer bridge fica inert. Não há como quebrar.

### Tensão de design (decisão registrada)

O contrato `extension_ui_request` é **simples demais** pro fluxo rico do pi-ask:
`select` carrega só `options: string[]` (labels), **sem** multi-select, preview
ou notes. "Espelhar o contrato" e "suportar as adições do pi-ask" conflitam.

**Decisão**: contrato upstream como **base/precedência** + envelope opcional
`ask` com o schema completo do pi-ask.

- Os frames seguem o schema do SDK verbatim (methods / ids / response shapes).
- Um campo opcional `ask` carrega o contexto rico (flow_id, questão corrente,
  schema `AskQuestion` completo).
- Clientes antigos/estritos ignoram o extra; o app renderiza rico quando presente.
- Reversível: dropar o envelope degrada limpo pra `select` simples (revert de
  1 campo) caso o maintainer queira mirror estrito.

Assim o canal é o **mesmo** contrato do Cockpit (UI interativa unificada — vale
pra pi-ask hoje e prompts genéricos no futuro), as adições do pi-ask viajam sem
divergir do contrato base, e sem pi-ask nada quebra.

Casing: **snake_case** no wire (consistente com o resto do protocolo relay:
`tool_call_id`, `in_reply_to`), não o camelCase do RPC do SDK. Mirror é
**semântico**, não literal.

## Objetivo

`ask_user` do pi-ask renderiza interativamente no app (modal full-screen) com
submit real, espelhando o contrato `extension_ui_request` /
`extension_ui_response`.

## Não-objetivos

- Não mudar o relay (frames viajam opacos no `ct` existente).
- Não reimplementar model picker / compact (já existem).
- Não replay de flows ask em `session_sync` (são transientes; o
  `tool_request`/`tool_result` do `ask_user` já é replayado). Fica pra próximo.
- No primeiro corte: `editor` vira `input` simples no mobile (customText/notes);
  editor multi-linha com diff fica pra próximo.
- **elaborate mode não exposto**: o wire suporta `mode: submit|elaborate`, mas o
  app sempre envia `submit` no v1 (não há botão "elaborate/refine" no modal). O
  bridge repassa qualquer `mode`; só falta UI pra escolher elaborate.

## Arquitetura

### Wire (novo — pi-extension ↔ app)

ServerMessage `extension_ui_request` (espelha `RpcExtensionUIRequest`):

```jsonc
{ "type": "extension_ui_request", "id": "<flow-id>",
  "method": "select", "title": "...", "options": ["A", "B"],
  "ask": { /* opcional — envelope pi-ask, TODAS as questões num frame só */
    "flow_id": "<flow-id>", "tool_call_id": "<tcid>|null", "source": "tool",
    "title": "...|null",
    "questions": [{ "id": "...", "label": "...", "prompt": "...",
                    "type": "single|multi|preview", "required": true,
                    "options": [{ "value": "...", "label": "...",
                                  "description": "...", "preview": "...", "freeform": false }] }] } }
```

> **Mudança vs rascunho original**: o rascunho previa **um request por questão**
> (`question_index`/`total_questions`/`question`). A implementação enviou **um
> request por flow** com array `questions` — modal único no mobile, menos
> round-trips. Consequência: o caminho degradado (cliente estrito sem envelope)
> só funciona de fato pra flows de **1 questão** — com N questões, a resposta
> simples cobre uma só e o pi-ask rejeita por required faltante (ver Riscos).

ClientMessage `extension_ui_response` (espelha `RpcExtensionUIResponse`):

```jsonc
{ "type": "extension_ui_response", "id": "<req-id>",
  "value": "<label>" | "confirmed": true | "cancelled": true,
  "ask": { /* opcional — resposta estruturada pi-ask */
    "flow_id": "<flow-id>", "kind": "answer",
    "mode": "submit|elaborate",
    "answers": { "<qid>": { "values": ["..."], "customText": "...",
                            "note": "...", "optionNotes": {...} } } } }
// ou { "type":"extension_ui_response", "id":"...", "cancelled": true,
//       "ask": { "flow_id":"...", "kind":"cancel" } }
```

### pi-extension — `src/extension_ui_bridge.ts`

Subscreve `pi.events` (feature-detect; inert sem pi-ask):

- `@eko24ive/pi-ask:started` → emite **um** `extension_ui_request` por **flow**
  (method `select` base + envelope `ask` com o array `questions` completo).
  Mantém map `requestId → { flowId, label→value }` pro caminho degradado.
- `@eko24ive/pi-ask:completed` → emite `notify` com o mesmo `id` (o app trata
  como "dispensa este request").
- `@eko24ive/pi-ask:submit-result` erro → emite `notify` warning **reusando o
  `flowId` como `id`** (mesmo id do request aberto) + `notify_type:"warning"`.
  O app correlaciona pelo id e expõe a mensagem como `pendingUiError` → o modal
  permanece aberto e habilita retry. O `completed` (dismiss, `notify_type`
  ausente/info) é o que fecha o modal. Sucesso (ok:true) é no-op aqui.
- **TTL de flow**: cada flow em `activeFlows` ganha um timer de 10min
  (`FLOW_TTL_MS`) — pi-ask dispõe flows no `session_shutdown` **sem** emitir
  `completed`, então sem isso o map vazava uma entrada por flow abandonado.

Handler `extension_ui_response` no router (`_routeClientMessageFrom`):

- Se `ask` envelope presente → monta `RemoteAskResponse` e emite
  `@eko24ive/pi-ask:submit`.
- Senão → mapeia `value` (label) → option `value` via o map do request, monta
  answer, submit.

### app

- `protocol.dart`: models `ExtensionUiRequest`/`ExtensionUiResponse` +
  `AskQuestionWire`/`AskOptionWire`/`AskAnswerWire` + novos cases em
  `ServerMessage.fromJson` e novo `ClientMessage`.
- Estado: `OpenUiRequest` no `ChatViewModel` (ou equivalente), keyado por `id`.
- UI: **modal full-screen** `extension_ui_sheet.dart`. Se `ask` presente →
  render pi-ask rico (radio single, checkbox multi, preview pane, customText,
  notes); senão → render SDK simples (select/confirm/input).
- **Fallback**: `tool_request{tool:"ask_user"}` sem `extension_ui_request`
  correlato → render informativo "responda no desktop" (sem submit), pois sem
  bridge não há canal de resposta. **DEFERIDO na v1**: com o bridge ativo o
  `ask_user` sempre chega como `extension_ui_request`; o caminho "bare
  tool_request" é quase inalcançável e criaria segundo trigger path.
- Submit → `extension_ui_response` ClientMessage.

## Passos

### Wave 0 — Contrato + bridge pi-extension (TS)

- `src/protocol/types.ts`: novos tipos wire + `ExtensionUiRequestWire` /
  `ExtensionUiResponseWire` + adições nos unions `ServerMessage` / `ClientMessage`.
- `src/protocol/codec.ts`: registrar `extension_ui_request` em `SERVER_TYPES`.
- `src/extension_ui_bridge.ts`: subscribe / translate / state mapping.
- `src/index.ts`: init do bridge na factory; handler `extension_ui_response`.
- Testes (vitest): started→frames; response→submit (com e sem envelope);
  label→value mapping; sem pi-ask = inert.
- `pnpm typecheck && pnpm test`.

### Wave 1 — App protocol + estado (Dart)

- `protocol.dart`: models + `fromJson`/`toJson` + cases.
- roteamento no ConnectionManager / ChatViewModel.
- `flutter test` de parsing.

### Wave 2 — App UI (modal full-screen)

- `extension_ui_sheet.dart` (select/confirm/input + ask rico).
- fallback `tool_request{ask_user}` informativo.
- integração no chat page + submit path.

### Wave 3 — Smoke manual

Pi TUI + pi-ask + remote-pi + app pareado → forçar `ask_user` → responder no
celular → confirmar resolução no desktop.

## Definition of Done

- [x] pi-extension: `pnpm typecheck && pnpm test` verdes (2026-07-18: typecheck
      ok + 10 vitest verdes; 5 falhas pré-existentes não relacionadas — symlink
      Windows em daemon/* e rooms.test.ts). Re-verificado após os fixes
      pós-review (submit-result id=flowId + TTL de flow): typecheck + 10 tests
      verdes.
- [ ] app: `flutter test` verde nos testes novos (pendente — Flutter ausente no
      ambiente de autoria; despachar pro pane App).
- [ ] Smoke: `ask_user` respondido do celular resolve o fluxo no desktop;
      multi-owner first-response-wins.
- [x] Sem pi-ask: nada quebra (bridge inert) — coberto por vitest; smoke real
      pendente junto com o item acima.
- [x] PR referencia a tensão de design e a decisão (contrato upstream + envelope
      `ask`).

## Riscos

1. **Fidelidade do mapeamento**: multi/preview/notes não cabem no contract base;
   mitigado pelo envelope `ask` (app renderiza rico).
2. ~~**Estado do bridge**: map `requestId → flow/label-value` precisa cleanup
   pra não vazar.~~ **Resolvido**: TTL de 10min por flow (`FLOW_TTL_MS`) limpa
   entries de flows abandonados (session_shutdown dispõe sem `completed`).
3. **Multi-owner**: primeiro response vence (pi-ask idempotente via flag
   `completed`); outros owners recebem `completed`/`notify` e dispensam.
4. **Aceitação upstream**: o envelope `ask` diverge do "espelhar estrito";
   justificar no PR. Reversível (revert de 1 campo) se o maintainer preferir
   mirror estrito.
5. **Caminho degradado limitado a 1 questão**: com todas as questões num frame
   só, cliente estrito (sem envelope) responde só a primeira; flows
   multi-questão travam no required faltante e o submit-result warning é
   descartado na v1. Documentar como limitação conhecida no PR.
6. ~~**Modal vs answer inválida**: fechar otimista no submit + rejeição =
   dead end.~~ **Resolvido**: o app **não** fecha o modal otimista no submit.
   Ele permanece em estado "submitting" e só fecha no `completed` dismiss.
   Rejeição (submit-result warning, id casado) vira `pendingUiError` → o sheet
   re-habilita Submit/Cancel e mostra a mensagem pra retry. Backstop de 25s no
   sheet reseta o spinner se nenhum `completed`/error chegar (relay drop).
7. **Keyboard inset (v1)**: modal é Stack overlay, não rota — teclado pode
   cobrir a action bar inferior. Aceito como limitação v1.

## Próximo plano possível

- Replay/resolução de flows ask em `session_sync`.
- `editor` rico no mobile (multi-linha com preview de diff).
