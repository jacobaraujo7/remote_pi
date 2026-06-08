# 38 — Malha: endereçamento por `(pc, cwd, nome)`

> **Reescrito 2026-06-08.** Versão anterior (identidade estruturada de 4 eixos
> `pc·workspace·worktree·name` com derivação marker-gated + detecção git de
> worktree) foi **descontinuada** — ver [Decisões revertidas](#decisões-revertidas-2026-06-08).
> A extension passou a permitir **vários agentes na mesma pasta** com primary key
> `(cwd, nome)` (já implementado na camada de identidade local). Este plano
> alinha **a malha** a esse modelo: o endereço de um peer passa a ser
> `(pc, cwd, nome)`, e ponto. Sem workspace, sem worktree, sem heurística.

## Contexto

A identidade de um agente na malha hoje é **só o nome**, e o broker roteia por
nome **global**. Verificado no HEAD (`41cdeac`):

- `RegisterMsg = { type: "register", name }` — o peer manda só o nome
  (`broker.ts:83-86`, enviado em `peer.ts:268`).
- `peers = Map<string, PeerConn>` chaveado pelo **nome assinado** (`broker.ts:100`,
  set em `:228`); roteamento é `this.peers.get(env.to)` (`injectFromRemote`
  `:139`, `_route` `:293+`).
- `_uniqueName` resolve colisão com `#N` **global** — dois agentes com o mesmo
  nome em **pastas diferentes** colidem (`broker.ts:276-283`).
- `defaultAgentName(cwd)` ainda devolve `parent/folder` achatado
  (`local_config.ts:136-142`) — o "workspace enfiado no nome" que queremos desfazer.

Isso quebra no mundo novo: **a extension agora permite N agentes na mesma pasta**,
com primary key `(cwd, nome)`. A malha não enxerga `cwd` — ela só vê a string do
nome. Logo:

1. Dois agentes na **mesma pasta** com o mesmo nome → `#2` (ok, caso genuíno).
2. Dois agentes em **pastas diferentes** com o mesmo nome → `#2` (colisão falsa —
   são agentes distintos, não deviam disputar nome).
3. Worktree (= outra pasta, outro `realpath`) coexiste por path, mas a malha não
   distingue: vira `app` e `app#2`, e nenhum peer sabe quem é quem.

**A solução é tornar o `cwd` um eixo de primeira classe no endereço da malha**,
do mesmo jeito que ele já é a chave de lock/room/id local. O endereço vira:

```
[<pc>:]<cwd>@<nome>
```

`cwd` (path absoluto) é a fonte da verdade que já desambigua pasta **e** worktree
**por construção** — sem marker-gating, sem `git plumbing`. `nome` é o
discriminador **dentro** da pasta (agora que cabem vários). `pc` é o salto
cross-PC (como hoje). `#N` só dispara no caso real: **mesmo cwd + mesmo nome**.

> **Origem da reescrita**: decisão do Orquestrador (2026-06-08) de colapsar a
> identidade estruturada em `(cwd, nome)` — "a única coisa que iremos manter é
> cwd e nome pra termos vários agentes na mesma pasta". Cortamos os eixos
> derivados (`workspace`/`worktree`) por YAGNI (`00-decisions.md:113`).

### Relação com planos/decisões existentes

- **Baseline = plano 34** (entrega confiável + presença passiva): broker é a
  arquitetura permanente; o leaderless da **35 foi descontinuado**. Este plano é
  aditivo ao broker.
- **Rooms (plano 17) são camada DIFERENTE.** `roomId = sha256(realpath(cwd))`
  identifica a **sessão App↔Pi**. Este plano mexe no **wire da malha**
  (`register`/`list_peers` entre peers/brokers), não no envelope App↔Pi.
  - ⚠️ **Consequência a rastrear (não é deste plano)**: se cabem N agentes por
    pasta, o room `sha256(realpath(cwd))` deixa de ser 1:1 com agente. Avaliar no
    plano do **app** se o room precisa virar `sha256(realpath + nome)`. Aqui só
    registramos a dependência.
- **`00-decisions.md`**: project-scope por marcador/walk-up já foi **refutado**
  no lado App↔Pi (`:43-44`, `:56`). Reforça cortar a heurística de workspace.
- **Relay intacto** (mesma análise da versão anterior, ainda válida): o relay é
  cego ao conteúdo do blob cross-PC (`relay/src/mesh/handler.rs` só inspeciona
  `version` + `owner_pk`, assina os bytes crus). `cwd` entra **dentro do blob
  assinado** sem tocar o relay. Único limite: cap de 500 KB por body
  (`MAX_BODY_BYTES`) — paths curtos são desprezíveis.

## Decisões (2026-06-08)

| # | Decisão | Valor | Por quê |
|---|---|---|---|
| **A** | Eixos da identidade | **`(pc, cwd, nome)`** — três campos, fim. `cwd` = `realpath(cwd)`; `nome` = `config.agent_name` ?? `basename(cwd)`; `pc` = label cross-PC (preenchido por broker_remote/relay). | `cwd` já é a chave de lock/room/id e desambigua pasta+worktree de fábrica. Não há o que adivinhar — sem marker-gating, sem detecção git. |
| **B** | Render do `address` | **`[<pc>:]<cwd>@<nome>`**, legível, casado por **igualdade exata** no broker dono. `@` separa o nome do path (não colide com `/`). Sanitização só no `nome` (`sanitizeSegment`, de `af66d04`). | Debuggável em log/UI; lookup é igualdade exata na `Map<address,conn>`, então `/` no path não atrapalha. Threat model não exige endereço opaco (qualquer peer da malha já enxerga os outros). Path absoluto vaza home/username — aceitável pro modelo (máquinas do próprio dono). |
| **C** | Escopo do broadcast | **mesma `cwd`** (colegas da mesma pasta); **local-only** (cross-PC segue unicast). | Reframe do antigo `(workspace, worktree)`. Com N agentes por pasta, "broadcast = minha pasta" é o escopo natural e preciso. Cross-PC não deve vazar broadcast. Revisitável se aparecer demanda de broadcast multi-pasta. |
| **D** | `nome` = folha limpa | `defaultAgentName` deixa de ser `parent/folder`; vira `basename(cwd)`. `config.agent_name` sobrescreve. | O `cwd` agora viaja como campo próprio; não precisa mais enfiar o "workspace" no nome. Folha limpa → `#N` quase nunca dispara. |
| **E** | Persistência do nome | **Só o nome limpo explícito** é persistido em `agent_name`. O sufixo `#N` — venha do lock (`_lockedName`) ou do broker — é **runtime-only**, recomputado a cada register, **nunca** gravado. `_cmdJoin` para de persistir o `assigned` (`index.ts:2760`); nome derivado (`basename(cwd)`) também não se persiste (é re-derivável). | `#N` é resolução de colisão em runtime; gravá-lo congela um acidente como identidade e gera **ping-pong cross-folder** a cada restart (relatado pelo pane Extension, 2026-06-08). Com o broker por `(cwd,nome)` (passo 4) a colisão cross-folder some na raiz; a decisão E garante que nem o `#N` residual (mesmo cwd+nome) fossilize. |

### Princípio que mantém o endereçamento são

> **O roteamento NUNCA re-deriva nada da string.** `cwd` e `nome` viajam como
> campos no `register`. O broker dono **compõe** o `address` e o guarda em
> `Map<address, conn>` → lookup por igualdade exata. A única coisa parseada na
> string é o salto `<pc>:` (split no 1º `:`, como hoje). Agente/app **nunca
> montam** o endereço — pegam `peer.address` do `list_peers` e ecoam verbatim.

Consequências:
- Único encoder de `address` (no broker). Todo mundo ecoa.
- "Mesmo escopo" (broadcast) compara o **campo `cwd`**, nunca prefixo de string.
- Address hardcodado fica stale no upgrade → mitigado pelo "ecoar, nunca montar".

### Render — exemplos

| Cenário | pc · cwd · nome | render |
|---|---|---|
| 1 agente, pasta `~/acme/backend`, sem `agent_name` | — · `/Users/jacob/acme/backend` · `backend` | `/Users/jacob/acme/backend@backend` |
| 2º agente na mesma pasta, `agent_name=reviewer` | — · `…/acme/backend` · `reviewer` | `/Users/jacob/acme/backend@reviewer` |
| Worktree em `~/.wt/feat-login` | — · `/Users/jacob/.wt/feat-login` · `backend` | `/Users/jacob/.wt/feat-login@backend` |
| Mesmo cwd + mesmo nome (colisão real) | — · `…/backend` · `backend` | `…/backend@backend#2` |
| Cross-PC | `MacMini` · `/Users/jose/work/acme` · `app` | `MacMini:/Users/jose/work/acme@app` |

> **Worktree é grátis**: mora noutro `realpath` → endereço distinto sem nenhum
> código de git. (A versão anterior gastava 4 chamadas de `git plumbing` pra
> derivar um rótulo de branch que o path já tornava redundante.)

## Compatibilidade — comunicação não se perde

- `register` **ganha `cwd`** (campo novo, obrigatório no build novo). Build antigo
  manda só `name` → o broker compõe `address = name` (sem `@cwd`), comportamento
  de hoje. Malha mista funciona.
- `register_ack` devolve `address_assigned` (era `name_assigned`); cliente antigo
  que lê `name_assigned` recebe o mesmo campo por compat (alias) com o address.
- `list_peers_reply` devolve **os dois**: `peers: string[]` (addresses, cliente
  velho roteia) **+** `peers_detailed: PeerInfo[]` (`{ pc?, cwd, name, address }`,
  cliente novo agrupa por `cwd` sem parsear). Migração sem big-bang.
- Skill redeploya só no próximo `remote-pi claude` (`_deployClaudeMeshSkill`) →
  sessões rodando mantêm o comportamento antigo até relaunch. Malha viva não quebra.
- **O address derivado muda no upgrade** (`Projects/myapp` vira
  `/abs/Projects/myapp@myapp`). Não quebra roteamento porque o princípio é
  **ecoar `peer.address`**, nunca hardcodar.
- **App antigo NÃO quebra (App↔Pi intacto)**: o app só consome `session_name`
  (= `_displayName(cwd)`, `index.ts:953`) e `room_id` (= `roomIdForCwd` =
  `sha256(realpath)`, `rooms.ts:12`) no `pair_ok`. `room_id` **não muda** (segue
  por realpath). `session_name` muda só de **valor** (`parent/folder` →
  `basename(cwd)`), mesmo campo/tipo → app apenas re-rotula.
  - **Invariante a manter (Fase 1)**: `_meshNode.name()` / `_displayName`
    (`index.ts:555-556`) devolvem a **folha `nome`**, NUNCA o `address` composto.
    Senão o app velho exibiria o path absoluto como nome (vaza path, regressão
    cosmética). O `address` é acessor **separado**, só pra roteamento/`list_peers`.
- **Migração de nome congelado** (re-derivado no load — decisão E): `agent_name`
  com `#N` (só pode vir de assignment do broker/lock — `sanitizeSegment` troca
  `#`→`-`, então o usuário nunca grava `#`) tem o sufixo **removido**; o legado
  `parent/folder` (contém `/`) vira `basename(cwd)`. Sem isso, daemons/sessões
  pré-fix carregam `#N` ou `parent/folder` fossilizado como se fosse explícito.

## Touchpoints (pi-extension) — verificados no HEAD `41cdeac`

| Arquivo | Mudança |
|---|---|
| `src/session/local_config.ts:136-142` | `defaultAgentName` → `basename(cwd)` (folha limpa), não mais `parent/folder`. `config.agent_name` sobrescreve. |
| `src/session/broker.ts:83-86` | `RegisterMsg` ganha `cwd: string`. |
| `src/session/broker.ts:88-91` | `RegisterAck.name_assigned` → `address_assigned` (valor = address composto); manter `name_assigned` como alias de compat. |
| `src/session/broker.ts:100` | `peers: Map<string, PeerConn>` passa a ser chaveado pelo **`address`** (`cwd@nome`), não pelo nome cru. |
| `src/session/broker.ts:167` | `PeerConn` ganha `cwd` + `address`. |
| `src/session/broker.ts:207-237` | `_handleRegister`: parseia `cwd`, **compõe `address`** (único encoder), chaveia o Map por address, ack devolve `address_assigned`. |
| `src/session/broker.ts:276-283` | `_uniqueName` → chave composta `(cwd, nome)`: `#N` só em **mesmo cwd + mesmo nome**. |
| `src/session/broker.ts:133-151,293+` | `injectFromRemote`/`_route`: lookup por `env.to` (= address) — só muda a chave do Map. |
| `src/session/broker.ts:236,288` | `peer_joined`/`peer_left` carregam `address` (não nome cru). |
| `src/session/broker.ts:247-274` | `list_peers`/observer probe: devolve addresses + `peers_detailed`. |
| `src/session/peer.ts:259,268` | register **envia `cwd`**; ack lê `address_assigned` (fallback `name_assigned`). |
| `src/session/peer.ts` · `mesh_node.ts` | opts/propagação carregam `cwd` ao lado de `name`; API de `listPeers` expõe os campos. |
| `src/mcp/mesh_server.ts` · `src/session/tools.ts` | passar `cwd` (da sessão) na construção; render de `list_peers` por address; `agent_send` por address verbatim. |
| `src/session/broker_remote.ts` · `peer_inventory.ts` | `cwd` + `pc` no inventário cross-PC (**Fase 2**). |
| `src/daemon/rpc_child.ts` | daemon registra com a **mesma** `(cwd, nome)` que a sessão interativa geraria. |
| `src/index.ts:2654-2760` | `_cmdJoin`: **já encaminha `cwd`** ao `MeshNode` (`:2676-2682`, progresso parcial do passo 3). **Mudar `:2760`** (decisão E): não persistir o `assigned` (com `#N`); persistir só `agent_name` explícito. Evento `name-assigned` (`:2752`) fica. |
| `src/index.ts:545-558` (load) | `getAgentName`/`loadLocalConfig`: migração — strip de `#N` e do legado `parent/folder` ao ler `agent_name`, re-derivando. |
| `skills/agent-network/SKILL.md` | explicar `(cwd, nome)`, N agentes por pasta, e **usar `peer.address` verbatim** (nunca montar). |

> **`af66d04` (camada de config) — o que sobra**: `sanitizeSegment` é reusado pro
> `nome` no render. `REMOTE_PI_DIRECT_CONFIG` é ortogonal (intacto). Os campos de
> config `workspace?`/`worktree?` ficam **órfãos** (ninguém deriva mais) — remover
> no cleanup ou deixar como no-op inerte. Não consumir.

> **Fonte-da-verdade da skill = repo** (`pi-extension/skills/agent-network/SKILL.md`),
> copiada pra `~/.claude/skills/` a cada `remote-pi claude`. Não editar à mão a cópia.

## Passos (por fase, com critério de aceite)

### Fase 1 — broker + extension (local) ← cai no pane `Extension`

1. **`nome` = folha** (`local_config.ts`) — `defaultAgentName` → `basename(cwd)`;
   `agent_name` explícito sobrescreve.
   - *Aceite*: pasta `~/acme/backend` sem config → `nome = backend` (não
     `acme/backend`); `agent_name=reviewer` → `nome = reviewer`.

2. **Encoder do `address`** (`broker.ts`, helper único) — compõe
   `[<pc>:]<cwd>@<nome>`, sanitizando só o `nome`.
   - *Aceite*: a matriz da tabela de render passa em teste; `@` separa nome do
     path; nome com `/`/`#`/espaço é sanitizado; cross-PC prefixa `<pc>:`.

3. **Register carrega `cwd`** (`peer.ts`/`mesh_node.ts` → `broker.ts`) —
   `RegisterMsg.cwd`; `PeerConn` guarda `cwd` + `address`; Map chaveado por address.
   - *Aceite*: build antigo (sem `cwd`) registra e `address == name` (compat);
     build novo registra com `cwd` e address composto; dois `backend` em pastas
     diferentes coexistem **sem `#2`** (addresses distintas).

4. **`#N` por `(cwd, nome)` e runtime-only** (`broker.ts` + `index.ts`)
   - `_uniqueName` (`broker.ts:276`) chaveia por `(cwd, nome)` → `#N` só em mesmo
     cwd + mesmo nome; pastas diferentes não colidem.
   - **Persistência sem drift** (decisão E): `_cmdJoin` (`index.ts:2760`) **não**
     grava o `assigned` (com `#N`) em `agent_name`; só nome explícito persiste.
     O evento `name-assigned` (`index.ts:2752`, runtime) continua informando o
     Cockpit do nome efetivo.
   - **Migração no load**: `agent_name` com `#N` (só vem de assignment — o usuário
     nunca grava `#`, que `sanitizeSegment` troca por `-`) tem o sufixo removido e
     re-deriva; idem o legado `parent/folder` (contém `/`).
   - *Aceite*: 2 agentes mesma pasta mesmo nome → `…@backend` + `…@backend#2`
     (runtime); pastas diferentes mesmo nome → **sem** `#N`; restart repetido de A
     e B (mesmo nome, pastas distintas) → cada uma mantém o nome limpo, **nenhum
     config ganha `#N`**, sem ping-pong; config pré-fix com `#N`/`parent/folder`
     re-deriva no load.

5. **`list_peers` aditivo** (`broker.ts` + `mesh_server.ts`/`tools.ts`) —
   `peers: string[]` (addresses) **e** `peers_detailed: PeerInfo[]`
   (`{ pc?, cwd, name, address }`).
   - *Aceite*: cliente velho lê `peers` e roteia; cliente novo lê `peers_detailed`
     e agrupa por `cwd` sem string-split; ambos no mesmo reply.

6. **Broadcast escopado por `cwd`** (`broker.ts`) — entrega só a peers locais com
   `cwd` == do remetente; cross-PC permanece unicast.
   - *Aceite*: broadcast de um agente em `/a/b` não chega a peer em `/a/c`; chega
     aos da mesma pasta.

7. **`rpc_child.ts`** — daemon registra com a mesma `(cwd, nome)` da sessão interativa.
   - *Aceite*: daemon gera a mesma `address` que a sessão geraria pra aquela pasta/config.

8. **Skill `agent-network`** — `(cwd, nome)`, N agentes por pasta, `peer.address` verbatim.
   - *Aceite*: a skill não instrui montar address à mão; explica o modelo.

9. **`pnpm test` verde** com os casos novos (folha, encoder, register c/ `cwd`,
   `_uniqueName` por `(cwd,nome)`, list_peers detailed, broadcast por cwd).

### Fase 2 — cross-PC

- `broker_remote.ts` + `peer_inventory.ts` carregam `cwd` + `pc` no inventário →
  `list_peers` cross-PC com `pc` preenchido e address `<pc>:<cwd>@<nome>`.
- ⚠️ **Wrinkle Windows** (plano 40 colocou Windows em escopo): o split do salto no
  1º `:` colide com a letra de drive (`C:\...`). Mitigação: o parser do salto
  cross-PC testa o prefixo contra o **conjunto conhecido de PCs da malha** (se não
  é PC conhecido, é path local) — ou o encoder usa um separador de pc que não
  aparece em path. Decidir na Fase 2 (não bloqueia a Fase 1, que é local e sem
  prefixo de pc).
- *Aceite*: dois PCs; `list_peers` de um mostra peers do outro com `pc` correto e
  address `<pc>:…@…`; roteamento cross-PC por address verbatim; broadcast local-only
  preservado; address com drive-letter Windows roteia certo.

### Fase 3 — app (mobile)

- App consome `peers_detailed`: agrupa por `cwd` (pasta), ícone de `pc`. **Não
  parseia nome nem path** pra escopo — usa os campos.
- *Aceite*: lista agrupada/filtrada pelos campos, sem string-split.

## DoD

- [x] **Fase 1** — `nome`=folha; `register` carrega `cwd`; `PeerConn`/`Map` por
      `address`; encoder único `[pc:]cwd@nome`; `_uniqueName` por `(cwd,nome)`;
      `#N` runtime-only (não persistido) + migração strip `#N`/`parent/folder` no
      load; `list_peers` aditivo (`peers` + `peers_detailed`); broadcast por `cwd`;
      `rpc_child` alinhado; skill atualizada; `pnpm test` verde
      — *implementado 2026-06-08, 529/529 verde, typecheck limpo, invariante
      `_meshNode.name()`=folha verificado (sem vazar address pro app). **Sem
      commit** (modo orquestrado). `rpc_child` não exigiu código (daemon roda a
      mesma extensão → mesma address por construção).*
- [ ] **Fase 2** — `broker_remote` + `peer_inventory` propagam `cwd`/`pc`;
      `list_peers` cross-PC com `pc`; roteamento por address verbatim; wrinkle
      Windows resolvido; broadcast local-only preservado
- [ ] **Fase 3** — app agrupa por `cwd`/`pc` via `peers_detailed`, sem parsear nome/path
- [ ] **Compat** — build antigo (sem `cwd`) continua registrando e roteando
      (`address == name`); nenhum peer perde endereçamento na migração

## Não-objetivos

- **Reintroduzir `workspace`/`worktree`** como eixos ou derivação — cortados
  (ver Decisões revertidas). `cwd` subsume a desambiguação.
- **Cross-PC "mesmo projeto"** — sem campo `workspace`, a malha não diz que dois
  cwds em PCs diferentes são o mesmo projeto. Aceito; re-adicionar um campo no dia
  que houver demanda (não é redesign).
- **Aninhar worktree sob o repo-pai no app** — exigiria git; app agrupa por
  pasta (cwd), que resolve o caso comum.
- **Address opaco/hash** (decisão B = legível).
- **Broadcast cross-PC** (decisão C = local-only).
- **Mexer no envelope App↔Pi / no transporte da malha** — broker (34) é o baseline; isto é aditivo.

## Decisões revertidas (2026-06-08)

Da versão anterior deste plano (identidade estruturada de 4 eixos):

- ❌ **Workspace auto-derivado marker-gated** (`CLAUDE.md`/`AGENTS.md` no parent).
  Heurística admitidamente "chute bom" com falhas conhecidas; já refutada análoga
  no App↔Pi (`00-decisions.md:43-44,56`). **Substituída** por `cwd` cru.
- ❌ **Detecção git de worktree** (`git-common-dir`, branch, detached-HEAD
  fallback). O `realpath` já distingue worktree por path; o rótulo de branch era
  cosmético. **Removida.**
- ⚠️ **Migração do "nome congelado" + triagem dos ~12 callsites de
  `defaultAgentName`**: a triagem dos callsites cai (sem workspace prefix), e a
  derivação vira `basename(cwd)` (decisão D). Mas **uma migração mais leve
  permanece** (decisão E): strip do `#N` persistido e do legado `parent/folder` no
  load — caso contrário o drift de runtime fossiliza no config.
- ✅ **Mantido/aproveitado**: `sanitizeSegment` (`af66d04`), princípio "ecoar
  `peer.address`, nunca montar", `list_peers` dual, relay-zero, broadcast escopado
  (agora por `cwd`), `register` aditivo.

## Próximos planos / evolução

- **Campo `workspace` opcional** (só se aparecer demanda real de agrupar projeto
  cross-PC) — aditivo, não redesign.
- **Room por `(cwd, nome)`** no app, se a multiplicidade de agentes por pasta
  exigir (rastreado no Contexto; é plano do app, não deste).
- **Reachability do cockpit (plano 37)**: agentes spawnados pela extensão entram
  na malha já com `(cwd, nome)` de graça.
