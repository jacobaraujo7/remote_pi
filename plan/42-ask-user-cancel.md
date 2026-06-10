# 42 — Stop remoto para `ask_user` (escopo mínimo)

## Contexto

O pedido original tinha duas features grandes:

1. **Steering/follow-up** pelo app enquanto o agente trabalha.
2. **Suporte completo ao `ask_user`** no Android/iOS.

O meio-termo escolhido agora é menor: **quando o agente estiver bloqueado num
`ask_user`, tocar Stop no app deve cancelar/destravar a pergunta**. Não precisa
renderizar nem responder o prompt no app nesta fase.

O app já tem um botão Stop durante `working` e já envia `cancel{target_id}`. O
problema provável está no lado `pi-extension`: o `cancel` chama `ctx.abort()` a
partir de um contexto capturado de comando (`_lastCtx`) ou de `_noopCtx`. Isso é
frágil em dois casos importantes:

- **daemon/headless**: o auto-start cria `daemonCtx` sem `abort`; `_lastCtx` pode
  nunca existir → `cancel` vira no-op real.
- **troca de sessão/reload/new**: `_lastCtx` pode ficar stale; já existe
  `_lastEventCtx` recapturado em `session_start` justamente para evitar stale ctx
  em outras ações.

Há também uma ressalva de SDK/pacote: o `pi-ask-user` em modo TUI escuta o
`AbortSignal` e deve fechar no abort; em modo RPC ele cai em `ui.select/input` e,
pelo código atual do pacote, não repassa o `signal` ao fallback. Portanto o plano
abaixo separa **correção Remote Pi** de possível **bug upstream do pi-ask-user**.

## Objetivo

Tocar **Stop** no app durante um `ask_user` deve abortar a operação atual do Pi e
fazer a pergunta ser cancelada, sem implementar UI remota para responder.

## Não-objetivos

- Não implementar cards/respostas de `ask_user` no app.
- Não implementar steering/follow-up.
- Não mudar relay.
- Não mexer em push notifications.
- Não reativar approval gate.

## Diagnóstico / hipótese principal

Fluxo atual:

```text
App Stop
  -> ClientMessage { type: "cancel", target_id }
  -> pi-extension _routeClientMessageFrom(..., ctx)
  -> ctx.abort()
  -> sender.send({ type:"cancelled", ... })
```

Pontos frágeis no `pi-extension/src/index.ts`:

- `_lastCtx` guarda contexto de comando, não necessariamente o contexto corrente.
- `_lastEventCtx` é recapturado em todo `session_start`, mas hoje só é tipado para
  `compact`; deveria também carregar `abort` para cancelamento.
- No daemon auto-init (`REMOTE_PI_DAEMON=1`), `daemonCtx` só tem `ui` e `cwd`, sem
  `abort`; se esse for o contexto usado, `cancel` não interrompe nada.

## Arquitetura proposta

Usar o contexto mais fresco de sessão (`session_start`) como fonte primária para
abort:

```text
session_start ctx  ──> _lastEventCtx.abort  (preferido)
command ctx        ──> _lastCtx.abort       (fallback)
noop               ──> erro controlado      (último fallback)
```

O app continua igual no primeiro corte: ele envia `cancel`, recebe `cancelled` ou
`error`, e limpa o estado local como já faz hoje. Atenção: `cancelled` permanece
**sender-only** neste plano, porque o app atual remove `target_id` ao receber
`Cancelled`; broadcastar esse frame para todos os phones poderia apagar a bolha de
usuário confirmada em todos os devices. O estado global dos outros owners deve ser
limpo por `agent_done`/`room_meta.working=false`; se isso não acontecer no teste
multi-owner, parar e abrir decisão de protocolo/app antes de broadcastar qualquer
cancelamento.

## Passos

### Wave 0 — Reproduzir e fixar o bug em teste

**Projeto**: `pi-extension/`

**Arquivos prováveis**:

- `src/extension.test.ts`
- `src/index.ts`

Adicionar regressões obrigatórias:

1. **Fresh session ctx vence fallback/stale**
   - Inicializar a extensão e capturar o handler de `session_start`.
   - Disparar `session_start` com um contexto contendo `abort: vi.fn()`.
   - Simular um owner/channel ativo pelo caminho de produção (`_routeClientMessageFrom`
     com sender fake ou frame de relay; evitar apenas o shim legado se possível).
   - Enviar `ClientMessage { type:"cancel", id:"c1", target_id:"u1" }`.
   - Assertar que o `abort` do contexto de `session_start` foi chamado, o fallback
     stale/noop não foi chamado, e o sender recebe
     `cancelled{in_reply_to:"c1", target_id:"u1"}`.

2. **Sem contexto abortável não gera falso ack**
   - Limpar/evitar `_lastEventCtx` e `_lastCtx` real; usar só `_noopCtx`/fallback
     sem `abort` real.
   - Enviar `cancel`.
   - Assertar que o sender recebe `error{code:"internal_error", in_reply_to:"c1"}`
     e **não** recebe `cancelled`.

3. **Abort que lança não quebra listener**
   - Fazer `abort()` lançar.
   - Assertar `error{code:"internal_error", in_reply_to:"c1"}`.
   - Enviar um `ping` em seguida e assertar `pong`, provando que o listener/router
     continua usável.

4. **Multi-owner não fica divergente**
   - Dois owners conectados; um toca Stop para um turno global.
   - O sender pode receber `cancelled` sender-only.
   - O outro owner deve sair de `working` via eventos globais normais
     (`agent_done`/`room_meta.working=false`) ou o teste/smoke deve bloquear a
     release para uma decisão de protocolo/app. Não broadcastar `cancelled` neste
     plano sem corrigir antes o app que remove `target_id`.

**Aceite**: pelo menos o teste fresh-session-ctx falha no código atual antes da
correção; os demais protegem os invariantes novos.

### Wave 1 — Corrigir o cancel no `pi-extension`

**Arquivo**: `pi-extension/src/index.ts`

Mudanças esperadas:

1. Ampliar `_lastEventCtx` para carregar `abort` além de `compact`:

```ts
let _lastEventCtx: Pick<ExtensionContext, "compact" | "abort"> | null = null;
```

2. Em `session_start`, continuar atribuindo `ctx` a `_lastEventCtx`.

3. Criar helper pequeno para abortar com o contexto mais fresco, pulando `_noopCtx`
   e qualquer fallback que não tenha `abort` real:

```ts
function _abortCurrentTurn(fallback?: Pick<ExtensionContext, "abort">): boolean {
  const candidates = [_lastEventCtx, _lastCtx, fallback];
  for (const ctx of candidates) {
    if (!ctx || ctx === _noopCtx || typeof ctx.abort !== "function") continue;
    ctx.abort();
    return true;
  }
  return false;
}
```

A implementação exata pode diferir (por causa da tipagem de `_noopCtx`), mas o
invariante é: **primeiro contexto abortável real vence**, com `_lastEventCtx` antes
de `_lastCtx`.

4. Tratar `cancel` antes/fora do guard `if (!_pi) return`, igual `session_sync`,
   para evitar silent drop se o cancel chegar enquanto `_pi` não está bound.

5. No case `cancel`, usar o helper em vez do `ctx` passado pelo channel:

```ts
case "cancel": {
  try {
    const aborted = _abortCurrentTurn();
    if (!aborted) {
      sender.send({
        type: "error",
        code: "internal_error",
        in_reply_to: msg.id,
        message: "No active Pi context to abort",
      });
      break;
    }
    sender.send({ type: "cancelled", in_reply_to: msg.id, target_id: msg.target_id });
  } catch (err) {
    sender.send({
      type: "error",
      code: "internal_error",
      in_reply_to: msg.id,
      message: `Abort failed: ${String(err)}`,
    });
  }
  break;
}
```

A forma exata pode variar, mas os invariantes são:

- preferir `session_start` ctx;
- não depender de `_noopCtx` para cancelamento real;
- não deixar exceção de abort quebrar o listener;
- incluir `in_reply_to: msg.id` nos erros de cancel para correlação;
- não dizer ao app que cancelou se não havia abort disponível.

6. Manter `routeClientMessage(msg, ctx)` compatível com testes legados se algum
   teste injeta contexto explicitamente. Se necessário, o helper pode aceitar um
   fallback explícito, mas o caminho de produção deve preferir `_lastEventCtx`.

**Aceite**:

- `pnpm test -- src/extension.test.ts` verde.
- `pnpm typecheck` verde.

### Wave 2 — Verificar `ask_user` TUI manualmente

**Cenário manual**:

1. Rodar Pi interativo com `remote-pi` e `pi-ask-user` instalados.
2. Parear/abrir a sessão no Android.
3. Pedir algo que force o agente a chamar `ask_user`.
4. Quando o prompt aparecer no terminal e o app mostrar working, tocar **Stop** no app.
5. Verificar:
   - o prompt some/cancela no terminal;
   - o agente recebe resultado cancelado (`User cancelled the question` ou equivalente);
   - o app sai de `working`;
   - não há crash/log de listener quebrado.

**Aceite**: Stop destrava o `ask_user` em modo TUI.

### Wave 3 — Verificar daemon/RPC e registrar limitação se existir

**Motivo**: em RPC, o `pi-ask-user` cai no fallback `askViaDialogs(...)`. Pelo
código observado, esse fallback não passa o `AbortSignal` para `ctx.ui.select` /
`input`, embora o RPC mode suporte `opts.signal`.

**Cenário manual**:

1. Rodar uma sessão via daemon/supervisor.
2. Fazer o agente chamar `ask_user`.
3. Tocar Stop no Android.
4. Verificar se o prompt cancela ou se continua aguardando resposta RPC.

Se **cancelar**: marcar daemon/RPC como verde.

Se **não cancelar**: registrar explicitamente que o restante é bug upstream do
`pi-ask-user`/SDK integration, não do Remote Pi cancel plumbing. Próximo fix
provável fora deste repo:

- alterar `pi-ask-user` para passar `signal` também no fallback dialog:
  `askViaDialogs(ctx.ui, ..., { signal, timeout })` / equivalente;
- ou abrir PR upstream no `pi-ask-user`.

**Aceite mínimo deste plano**: TUI funciona; daemon/RPC fica verificado e, se
bloqueado por upstream, documentado como risco residual.

### Wave 4 — App: só teste/regressão se necessário

O app provavelmente não precisa mudar para o primeiro corte, mas precisa de
regressões/triagem explícitas para não mascarar falso sucesso:

- `SyncService.cancel()` envia `Cancel(id,target_id)` do turno ativo.
- `Cancelled` limpa streaming/working.
- `ErrorMessage` resultante de cancel falho não deixa `ChatViewModel.isWorking`
  verdadeiro por causa de `_streaming` residual.
- Stop button aparece enquanto `isWorking` e `cancelTargetId != null`.
- `Cancelled` hoje remove `target_id`; confirmar em teste/smoke que isso não apaga
  histórico confirmado indevidamente no caso de Stop durante `ask_user`. Se apagar,
  corrigir app antes de broadcastar qualquer cancelamento.

Testes candidatos:

- `app/test/ui/chat/chat_viewmodel_test.dart`
- `app/test/data/sync/sync_service_test.dart`

Status: regressões adicionadas para `SyncService.cancel`, `Cancelled` limpando
turno sem apagar histórico confirmado, `Cancelled` removendo bolha otimista ainda
pendente, `Cancelled`/`ErrorMessage` cancelando o flush coalescido de chunks para
não ressuscitar `_streaming`, e `ChatViewModel` saindo do estado Stop após
`Cancelled`. Verificado com `flutter test test/data/sync/sync_service_test.dart
test/ui/chat/chat_viewmodel_test.dart` após instalar Android SDK em
`~/code/android-sdk`.

**Não** desbloquear composer nem mudar UI de steering neste plano.

## Definition of Done

- [x] Teste de regressão no `pi-extension` prova que `cancel` usa contexto fresco
      de `session_start` quando `_lastCtx` não serve.
- [x] `cancel` não é no-op silencioso quando não há contexto abortável; retorna
      `error{code:"internal_error", in_reply_to:<cancel-id>}` e não `cancelled`.
- [x] Abort que lança vira erro controlado e o router/listener continua usável.
- [ ] Multi-owner verificado: o owner que não tocou Stop não fica preso em
      `working`; skipped for this commit because only one phone/owner was available.
- [x] `pnpm test` relevante + `pnpm typecheck` verdes no `pi-extension`.
- [x] Regressões app-side adicionadas para cancel/working/history e corrida de
      flush de chunks; `flutter test test/data/sync/sync_service_test.dart
      test/ui/chat/chat_viewmodel_test.dart` passou.
- [x] Smoke TUI: `ask_user` aberto → Stop no Android cancela/destrava.
      Verificado em 2026-06-09: prompt `ask_user` cancelado pelo Stop do app Android.
- [x] Smoke app: Android sai de working após cancelamento real.
- [ ] Daemon/RPC verificado; se ainda não cancelar por limitação do `pi-ask-user`,
      registrar como risco/upstream em README/plano ou issue.

## Riscos

1. **`ask_user` RPC pode precisar de patch upstream**: Remote Pi pode chamar
   `abort`, mas o fallback dialog do pacote precisa respeitar signal.
2. **Ack falso**: enviar `cancelled` sem abort real faz o app parecer ok enquanto
   o Pi continua bloqueado. Evitar.
3. **Ctx stale**: priorizar `session_start` ctx reduz o risco já conhecido de
   contexto stale após `/new`, `/resume`, reload ou daemon auto-init.
4. **Multi-owner divergente**: `cancelled` é sender-only porque o app remove
   `target_id`; outros owners precisam limpar via eventos globais. Se não limpar,
   isso vira decisão de protocolo/app, não patch silencioso.
5. **Escopo crescer para UI de ask_user**: não fazer neste plano; fica para plano
   futuro de `extension_ui_request`/`extension_ui_response` completo.

## Próximo plano possível

- **43 — `ask_user` completo no app**: espelhar o contrato RPC/Cockpit
  `extension_ui_request` + `extension_ui_response`, cards inline no chat,
  first-response-wins para múltiplos phones, e replay/resolução em `session_sync`.
- **44 — Steering/follow-up no app**: usar `sendUserMessage(...,{deliverAs})`,
  separar `activeTurnId` de mensagens enfileiradas e destravar o composer.
