# 34 — Malha: entrega confiável + presença passiva

## Contexto

Dogfooding via o projeto BussolaApp (Orquestrador + App, Claude na mesma malha)
expôs 3 problemas no broker da malha (`pi-extension`), confirmados por scout no
código em 2026-06-01:

1. **Busy gate dropa send fresco** a peer mid-turn — `broker.ts:304-310` (local)
   e `broker_remote.ts:148-160` (cross-PC). Causa *fan-in livelock*,
   *fan-out reply-race* e o buraco de *primeiro-contato* (agente novo sem id pra
   `re=` nunca alcança peer ocupado).
2. **`re=` fura o gate validando só `env.re !== null`** (`broker.ts:293`) — bypass
   forjável (qualquer peer cita um id autêntico do alvo e entra).
3. **Join faz broadcast PUSH O(N)** — `_broadcastSystem({type:"peer_joined"})`
   (`broker.ts:247`) escreve no socket de cada peer existente. Não escala.

**Decisão** (revisa `plan/25` Wave 0 "drop em busy"): **remover o drop; sempre
entregar.** O harness do Pi (`_pi.sendMessage(triggerTurn:true)`) sabe enfileirar
mensagem que chega mid-turn — confirmado pelo Owner. Não precisa de buffer/mailbox
no broker; o "mailbox" era preciosismo. Com o drop fora, o bypass do `re=` vira
desnecessário (não há gate pra furar) e `re=` reverte a puro campo de correlação.

## Mudanças

### A. Entrega confiável (remover busy-drop) — **Extension**
- `broker.ts`: remover o branch de drop em busy (~304-310). Sempre escrever no
  socket do destino, independente de `busyPeers`.
- `broker_remote.ts`: idem no caminho cross-PC (~148-160).
- `busy` ACK deixa de ocorrer pra unicast new-work → sender sempre recebe
  `received`.
- `busyPeers` / sinal `turn_state`: parar de usar pra gatear envio. **Verificar se
  há outro consumidor** (ex: working-indicators / `plan/32`) antes de remover o
  tracking — se só servia ao drop, pode sair; se a UI usa, manter o estado mas sem
  gatear entrega.
- **Aceite**: mensagem pra peer mid-turn é entregue (não dropada); nenhum `busy`
  pra unicast new-work; `pnpm test` verde (a matriz received/busy do `plan/25`
  precisa ser atualizada — o caso "busy → drop" deixa de existir).

### B. Presença passiva (join não acorda turn) — **Extension**
- Join/leave **não devem ACORDAR turn** dos peers existentes. Converter
  `peer_joined`/`peer_left` em atualização de **roster passivo**, descoberto via
  `list_peers` (pull). Quem entra chama `list_peers` pra descobrir os outros —
  O(1) pelo joiner, em vez de O(N) push.
- Preservar usos legítimos não-turn (UI/presença/working-indicators) se existirem —
  o critério é **não disparar `triggerTurn`** no join.
- **Aceite**: peer novo entrando NÃO faz agentes existentes reagirem/tomarem turn;
  `list_peers` ainda reflete o novo peer; `pnpm test` verde.

### C. Guidance do protocolo — **Extension** (a skill é empacotada no repo!)
- Descoberta por scout: a skill é versionada em
  `pi-extension/skills/claude-agent-network/SKILL.md` e **copiada pra
  `~/.claude/skills/agent-network/SKILL.md` a cada launch** de `remote-pi claude`
  (`_deployClaudeMeshSkill()`, `index.ts:2895-2907`). Editar `~/.claude/skills/` na
  mão seria sobrescrito no próximo launch — a fonte-da-verdade é o repo. Logo a
  correção vai pro **Extension**, no mesmo dispatch que A/B.
- Editar:
  - `skills/claude-agent-network/SKILL.md` (~88, 92-96): remover "retry on busy /
    you own the retry" e o enquadramento "replies bypass the busy gate". Novo
    comportamento: msg pra peer ocupado é ENTREGUE (harness enfileira); `re=` vira
    só correlação, sem bypass.
  - `src/mcp/mesh_server.ts:131`: a string de feedback de `busy`
    ("message dropped, retry later") fica obsoleta sem o drop — remover/ajustar.
- Coordenação natural: a skill só redeploya no próximo `remote-pi claude`, então
  sessões rodando mantêm o comportamento antigo até relaunch — A/B/C sobem juntos.

## DoD

- [x] A — busy-drop + `busyPeers` removidos (broker local + injectFromRemote); `pnpm test` 426 verde
- [x] B — turn-wake eliminado na CAUSA REAL (`mesh_server` descarta envelopes `from=broker`); broadcast O(N) preservado p/ UI de contagem do app Pi (deferido)
- [x] C — guidance corrigida: ambas as `SKILL.md` do repo + `mesh_server.ts` + `tools.ts`

## Próximos

- Bound/backpressure só se flood virar problema real (hoje o UDS já faz
  backpressure de SO; sem limite de app). Reavaliar com o stakeholder BussolaApp.
- Remover de vez a semântica de bypass do `re=` no código (com A, já fica inerte).
- **O(N) push do broker no join PERMANECE** (descoberta na impl: o turn-wake vinha
  do `mesh_server` repassando envelopes do broker, não do broadcast em si — já
  corrigido em B). Eliminar o broadcast degradaria a contagem live de peers no app
  Pi; avaliar coalescing/backpressure com o stakeholder antes de mexer.
- `peer.ts` ainda carrega o tipo `busy` (AckStatus) como fallthrough inerte —
  limpar quando conveniente.
