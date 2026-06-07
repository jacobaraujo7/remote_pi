# 38 — Malha: identidade estruturada de peer (workspace + worktree)

## Contexto

A identidade de um agente na malha hoje é uma **string achatada**: o **nome** é, ao
mesmo tempo, a única identidade *e* o único endereço. Identidade, lock, room e id
derivam de `realpath(cwd)` (`src/rooms.ts`, `src/daemon/id.ts`,
`src/session/cwd_lock.ts`); o nome vem de `agent_name` no
`<cwd>/.pi/remote-pi/config.json` ou do default `parent/folder`. O broker mapeia
`name → conexão` e resolve colisão com sufixo `#N` (`broker.ts:_uniqueName`).
Endereçamento: local por nome; cross-PC por `<pcLabel>:<name>` (split no 1º `:`,
`broker_remote.ts:parseAddress`); `broadcast` = todos os locais.

Isso quebra em dois cenários que vão ficar comuns:

1. **Vários projetos / um broker local** — dois agentes com o **mesmo
   `agent_name` explícito** (ex.: `backend`) em projetos diferentes colidem → um
   vira `backend#2`. Ninguém sabe quem é quem. (O default `parent/folder` mascara
   parcialmente isso hoje, justamente porque já enfia o "workspace" dentro da
   string do nome — que é o problema que queremos desfazer.)
2. **Git worktrees** (o gatilho desta discussão) — uma worktree mora num path
   diferente → realpath diferente → coexiste sem travar (lock/room/id próprios).
   **Mas** o mesh não tem consciência de git: a worktree é "só outra pasta". Se o
   checkout principal roda `app` e a worktree também roda `app`, o broker local
   resolve com `app#2`, e **nenhum peer tem como saber** que o outro está numa
   worktree (o broker só vê a string do nome).

**A armadilha que travou as primeiras ideias**: concatenar tudo no nome
(`acme/feat-login/app`) e inferir escopo por **prefixo de string** não fecha —
tanto `workspace` quanto `agent_name` podem conter `/` (o default já é
`parent/folder`), então o limite das dimensões fica ambíguo e a lógica de "mesmo
workspace" adivinha e erra.

**A solução** é trocar a identidade plana por um **objeto estruturado de peer**
com 4 eixos — `pc` · `workspace` · `worktree` · `name` — carregado no `register`
e devolvido pelo `list_peers`, mantendo o endereçamento como uma **string
canônica opaca** (ecoada, nunca montada à mão). Toda decisão de escopo (quem fala
com quem, broadcast) passa a usar **campos**, não split de string. Bônus: o app
mobile ganha a estrutura de graça pra agrupar/filtrar agentes.

> **Origem**: handoff do pane `Extension`
> (`.orchestration/results/handoff-mesh-structured-identity.md`, 2026-06-05).
> Promovido a plano após aprovação do Orquestrador.

### Relação com planos/decisões existentes

- **Baseline real é o plano 34** (malha: entrega confiável + presença passiva,
  DoD fechado): busy-drop removido, presença passiva via `list_peers` (pull),
  `mesh_server` descarta envelopes `from=broker`. Este plano constrói sobre esse
  broker.
- **Plano 35 (mesh leaderless, UDS-direto) foi DESCONTINUADO** (2026-06-05, ver
  lápide `plan/35-mesh-leaderless-redesign.md`). Logo o **broker** (planos 19/25 +
  34) é a arquitetura **permanente e mantida** — não um transporte de transição.
  A identidade estruturada assenta sobre ele, sem ressalva de "reconciliar com 35".
- **Decisão de escopo de visibilidade (`00-decisions.md`)**: o MVP cortou
  "project scope"/multi-sessão pro App↔Pi 1:1. Isto **não conflita** — aqui o
  escopo é *entre agentes da malha* (mesh peers), não o pareamento App↔Pi.
- **Modelo de rooms (plano 17) é uma camada DIFERENTE — não confundir.** O
  `roomId = sha256(realpath(cwd))` identifica uma **sessão App↔Pi** (o que o app
  abre e conversa); é opaco e já distingue worktrees por path. A identidade
  estruturada deste plano (`name`/`workspace`/`worktree`) é da **malha**
  (agente↔agente), legível. São ortogonais: o app já agrupa por `(peer, room)`;
  a **Fase 3** adiciona uma superfície **nova** (mesh peers por workspace) que
  **não** substitui nem se mistura com a lista de rooms.
- **Sem novo tipo no protocolo App↔Pi**: as mudanças vivem no wire da **malha**
  (`register`/`list_peers` entre brokers/peers), não no envelope App↔Pi.

## Decisões fechadas (2026-06-05)

| # | Decisão | Valor | Por quê |
|---|---|---|---|
| **A** | Derivação do `workspace` | **Auto-derivada, marker-gated** (revisado 2026-06-05): `workspace = basename(parent)` **se** o `parent` tem `CLAUDE.md`/`AGENTS.md`; senão `workspace = basename(projectRoot)`. `name = agent_name` explícito ou `basename(projectRoot)`. Config explícita (`workspace`/`agent_name`) sobrescreve | O default de HOJE (`parent/folder`, `local_config.ts:67-73`) **já é** um workspace achatado dentro do nome. Esta regra **ergue** o `parent` pro campo `workspace` só quando ele é um root real (marcador), e cai pro próprio folder quando não é. Resolve o #1 **inclusive com `agent_name` explícito** (que hoje colide); torna o broadcast per-projeto de graça; deixa `name` uma folha limpa (sanitização da decisão B deixa de ser issue) |
| **B** | Render do `address` | **Legível + sanitizado** (`pc:workspace/worktree/name`; `sanitizeSegment` já troca `/ : #`/espaços → `-` e rejeita reservados `broadcast`/`broker` — **feito 2026-06-06**), roteado por **exact-match** no broker dono | Debuggável em log/UI sem comprometer correção (o lookup é igualdade exata na `Map<address,conn>`); address opaco+hash perde legibilidade sem ganho — o modelo de ameaça não exige endereço opaco (qualquer peer da malha já enxerga os outros) |
| **C** | Escopo default do broadcast | Par exato **`(workspace, worktree)`** — colegas da *mesma* worktree; **local-only** (cross-PC segue unicast) | Broadcast não deve vazar entre worktrees (é o ponto do isolamento) nem entre workspaces. Com `workspace`/`worktree` ambos vazios (caso default), todos os agentes de nome-puro do mesmo PC se enxergam — igual a hoje. Aceito |
| **D** | Derivação da `worktree` | **`branch` sanitizada** + fallback **`basename(toplevel)`** em detached HEAD; **+ override opcional via config `worktree?`** (normalmente unset — derivado em runtime, não persistido) | Branch é o rótulo humano da worktree; basename do toplevel cobre o detached HEAD sem virar hash ilegível; o override deixa Cockpit/usuário fixar um rótulo custom |

> **Consequência da decisão A**: o problema #1 (colisão multi-projeto) e o #2
> (worktree) são resolvidos **de fábrica** — sem exigir config. O `workspace`
> auto-derivado (marker-gated) desambigua projetos mesmo com `agent_name`
> explícito; a `worktree` auto-derivada do git desambigua checkouts. Config
> explícita (`workspace`/`agent_name`) só **sobrescreve** o rótulo.
>
> **Heurística do marcador (assumida, ajustável na Fase 1):**
> - `CLAUDE.md`/`AGENTS.md` no `parent` = "este pai é um root de workspace
>   (monorepo / projeto multi-agente)". É um chute bom porque é o sinal que o
>   próprio ecossistema de agentes usa. Risco conhecido: um `CLAUDE.md` solto num
>   diretório genérico de dev (`~/Projects/CLAUDE.md`) agruparia tudo embaixo
>   dele — aceitável; o usuário controla com `workspace` explícito.
> - **Colapso `name == workspace`**: no caso standalone (parent sem marcador →
>   `workspace = name = basename(projectRoot)`), a render omite o `name`
>   redundante → address `myapp`, não `myapp/myapp`.
> - **Worktree**: o `projectRoot` ancora no repo principal (via `git-common-dir`),
>   então principal e worktree **compartilham** `workspace`; o campo `worktree`
>   os distingue. (Combinação monorepo-subpasta-em-worktree é detalhe de impl da
>   Fase 1 — preservar o `workspace` do marcador do repo principal.)

## Solução — objeto estruturado de peer

### Os 4 eixos (worktree é campo próprio, irmão do workspace — não aninhado)

```jsonc
// identidade de um peer — enviada no register e devolvida pelo list_peers
{
  "name":      "app",            // o agente (folha)
  "workspace": "acme",           // projeto lógico — OPCIONAL, só config explícita (decisão A)
  "worktree":  "feat-login",     // variante de checkout — só em worktree linkada, auto do git
  "pc":        "laptop",         // máquina (label cross-PC) — preenchido por broker_remote/relay
  "address":   "laptop:acme/feat-login/app"  // string canônica pro `to` — ECOAR, nunca montar
}
```

`workspace` pode atravessar PCs (mesmo projeto em duas máquinas); `worktree` é
por-checkout (local). São ortogonais → campos separados, não uma string só.

### Princípio que mantém o endereçamento são

> **O roteamento NUNCA re-deriva dimensões da string.** As dimensões viajam como
> campos. A `address` é um **handle opaco**, casado por **igualdade exata** no
> broker dono do peer. A única coisa parseada na string é o salto `<pc>:` (split
> no 1º `:`, como hoje).

Consequências:
- Agente/app **nunca constrói** o endereço — pega o peer do `list_peers` e usa
  `peer.address` verbatim (a skill já diz "use o nome exato do list_peers"). A
  complexidade de montagem mora num único encoder.
- O broker que **possui** o peer gerou aquela string e a guarda em
  `Map<address, conn>` → lookup exato, não importa se a `address` tem `/`/`#`.
- "Mesmo escopo" (teammates/broadcast) compara **campos** (`workspace` +
  `worktree`), nunca prefixo. Acabou a adivinhação.

### Render do `address` (decisão A = workspace auto-derivado, marker-gated)

Formato: `[pc:]workspace[/worktree][/name]` — o `name` é **omitido quando ==
workspace** (evita `myapp/myapp`).

| Layout (cwd) | `parent` tem marcador? | workspace · worktree · name | render (local) |
|---|---|---|---|
| `~/acme/backend` (monorepo, `acme/CLAUDE.md`) | sim | `acme` · — · `backend` | `acme/backend` |
| `~/acme/backend` + worktree `feat-login` | sim | `acme` · `feat-login` · `backend` | `acme/feat-login/backend` |
| `~/Projects/myapp` (standalone) | não | `myapp` · — · `myapp` | `myapp` |
| `~/Projects/myapp` + worktree `feat-x` | não | `myapp` · `feat-x` · `myapp` | `myapp/feat-x` |
| `~/Projects/myapp` + `agent_name=reviewer` | não | `myapp` · — · `reviewer` | `myapp/reviewer` |

Cross-PC: prefixa `<pc>:` (ex.: `laptop:acme/feat-login/backend`). `/` interno de
qualquer componente é sanitizado pra `-` antes de compor (decisão B) — mas com
`name` virando folha limpa, isso quase nunca dispara.

**Compor, não sobrescrever**: principal e worktree compartilham `workspace`; é o
campo `worktree` que os separa. Sem compor (ou se o explícito ignorasse a
worktree), ambos colidiriam no mesmo address.

### Detecção de worktree (git plumbing, 1–2 chamadas no startup)

```bash
git rev-parse --absolute-git-dir   # principal: /repo/.git ; worktree: /repo/.git/worktrees/<nome>
git rev-parse --git-common-dir     # SEMPRE o .git compartilhado (principal + todas as worktrees)
git branch --show-current          # branch da worktree ("" se detached HEAD)
git rev-parse --show-toplevel      # raiz daquela worktree
```

**Regra**: é worktree linkada ⟺ `absolute-git-dir` contém `/worktrees/`
(equiv. `git-dir != git-common-dir`). `dirname(realpath(git-common-dir))` dá a
**raiz do repo principal** — âncora estável compartilhada por principal + todas
as worktrees. Validado no checkout atual ("NÃO é worktree linkada").

Valor de `worktree` (decisão D): `sanitize(git branch --show-current)`; se vazio
(detached HEAD), `basename(git rev-parse --show-toplevel)`. Pasta não-git ou git
sem worktree linkada → campo ausente.

### Derivação do `workspace` (decisão A — marker-gated)

Roda no startup, depois da detecção de worktree (reusa o `git-common-dir`):

```
projectRoot = worktree linkada ? dirname(realpath(git-common-dir))   // raiz do repo principal
                               : realpath(cwd)
parent      = dirname(projectRoot)
workspace   = exists(parent/CLAUDE.md) || exists(parent/AGENTS.md)
                ? basename(parent)        // o pai é um root de workspace real
                : basename(projectRoot)   // o próprio folder é o workspace
name        = config.agent_name ?? basename(projectRoot)
// config.workspace explícito sobrescreve o derivado; config.agent_name sobrescreve o name
```

Pontos finos (ver também o box "Heurística do marcador" na seção de decisões):
- **2 `existsSync`** no `parent` — barato, no startup.
- **Worktree ancora no repo principal**: o `projectRoot` de uma worktree é a raiz
  do repo principal (não a pasta da worktree), então principal + worktrees
  **compartilham** `workspace`; o campo `worktree` os separa.
- **Colapso**: quando `name == workspace` (standalone sem `agent_name`), a render
  do address omite o `name` redundante.
- A detecção git serve a **dois** campos agora: `worktree` (branch) e a âncora do
  `workspace` (em worktrees).

### Compatibilidade — comunicação não se perde

- `register` ganha `workspace?`/`worktree?` **opcionais** → builds antigos
  registram só `name`, e pra eles `address == name` (comportamento de hoje).
- **Rollout — o address derivado muda no upgrade**: um agente que hoje é
  `Projects/myapp` (default `parent/folder`) vira `myapp` (ou `acme/backend` etc.)
  com a derivação nova. Isso **não quebra roteamento** porque o princípio é
  sempre **ecoar `peer.address` do `list_peers`**, nunca hardcodar — quem segue a
  skill nem percebe. Risco só pra address hardcodado (que o design já desencoraja).
- `list_peers_reply` devolve **os dois**: `peers: string[]` (addresses, cliente
  velho) **+** `peers_detailed: PeerInfo[]` (estruturado, cliente novo).
  Migração sem big-bang; ninguém perde endereçamento.
- A skill só redeploya no próximo `remote-pi claude` (`_deployClaudeMeshSkill`),
  então sessões rodando mantêm o comportamento antigo até relaunch — fases sobem
  sem quebrar malha viva.

## Estrutura esperada (touchpoints — pi-extension)

| Arquivo | Mudança |
|---|---|
| `src/session/local_config.ts` | campo `workspace?` (override explícito); **substitui** `defaultAgentName` (`:67-73`) pela derivação estruturada — `workspace` marker-gated (`CLAUDE.md`/`AGENTS.md` no parent) + `worktree` via git + `name`=folha |
| `src/session/broker.ts` | `RegisterMsg`/`PeerConn`/`register_ack`/`_handleBrokerMessage` (list_peers detailed); broadcast escopado por `(workspace, worktree)`; encoder do `address` |
| `src/session/peer.ts` · `src/session/mesh_node.ts` | propagar os campos no register; API de `listPeers` estruturada |
| `src/session/broker_remote.ts` · `src/session/peer_inventory.ts` | campos no inventário cross-PC (**Fase 2**) |
| `src/mcp/mesh_server.ts` · `src/session/tools.ts` | passar workspace/worktree na construção; render de list_peers; `agent_send` por `address` |
| `src/daemon/rpc_child.ts` | 3º callsite de resolução de nome (`sessionName`) deve usar a identidade efetiva (workspace prefix) também nos daemons |
| `skills/agent-network/SKILL.md` | seção de workspace/worktree: explicar que `workspace` é **auto-derivado** (marker-gated) e que setar `workspace` no config é só **override**; preferir mesmo escopo; exemplo de `list_peers` estruturado |

> **Correção de caminho**: o handoff e o `plan/34` citam variações
> (`skills/claude-agent-network/SKILL.md`). O arquivo real é
> **`pi-extension/skills/agent-network/SKILL.md`**, copiado pra
> `~/.claude/skills/agent-network/SKILL.md` a cada launch de `remote-pi claude`
> (`_deployClaudeMeshSkill`, `index.ts`). Fonte-da-verdade = repo; não editar
> `~/.claude/skills/` na mão.

### Relay — nenhuma mudança (verificado no código, 2026-06-05)

A identidade estruturada é **inteiramente pi-extension + app**. O relay é cego ao
conteúdo por design e continua assim:

- **Cross-PC (`peer_inventory`) → `POST/GET /mesh/:hash`**: o relay
  (`relay/src/mesh/handler.rs`, `relay/src/mesh/types.rs:23-27`) só inspeciona
  **`version` + `owner_pk`** do blob — *"Members and other fields exist in the
  blob but are NOT inspected by the relay"*. Verifica a assinatura Ed25519 sobre
  os **bytes crus** (não re-canonicaliza), confere `url_hash == sha256(owner_pk)`
  e guarda o blob versionado intacto. Logo `workspace`/`worktree`/`pc` entram
  **dentro do blob assinado** sem tocar o relay: sem `deny_unknown_fields`, sem
  schema do member-list, assinatura segue válida (cliente assina os bytes novos).
  Único limite real: o cap de **500 KB** por body (`MAX_BODY_BYTES`) — alguns
  strings curtos por peer são desprezíveis.
- **App↔Pi (`pi_forward`)**: outra rota, e o envelope App↔Pi é não-objetivo deste
  plano. Intacto.
- **Mesh local (`broker.ts`)**: UDS puro, nem passa pelo relay.

## Impacto nos legados / rollout (verificado no código, 2026-06-05)

**Sem quebra (aditivo):** wire da malha (`register` opcional → `address == name`
pra build velho; malha mista OK), `list_peers` dual, **relay zero**, **app intacto
até Fase 3**, **`daemons.json` guarda só `cwd`** (`registry.ts:10-14` — nome
recomputado, sem dado stale), sessões rodando não quebram (skill redeploya só no
relaunch).

**Muda comportamento:**
1. **Nome efetivo muda em ~12 callsites de `defaultAgentName`** (não só a malha:
   `getAgentName` `index.ts:523`, wizard `:1379/1420/2916`, `mesh_server.ts:48`
   `AGENT_NAME`, daemon `rpc_child.ts:116` / `supervisor.ts:207`, footer). Por isso
   a Fase 1 **triagem os callsites** (estruturado vs display name), não faz replace
   cego.
2. **Broadcast estreita** (decisão C): "todos os locais" → "mesma
   `(workspace, worktree)`". Setup multi-projeto que dependia de broadcast
   cross-projeto vê menos destinatários — mudança semântica, intencional.
3. **Colisão `#N` fica rara** (workspace desambigua) — melhoria, strings mudam.
4. **App vê o nome via `room_meta` (cosmético, NÃO quebra)** — o `room_meta.name`
   que o app exibe vem de `_displayName(cwd)` → `_meshNode.name()` (com malha) ou
   `agent_name || defaultAgentName` (`index.ts:520-523`, `:1501`). Como o 38 muda
   essa derivação, o **valor** do rótulo muda (`Projects/myapp` → `myapp` etc.);
   mesmo campo/tipo, app velho só re-rotula. O **apelido local** do pareamento
   (Keychain) é app-local e **não** é afetado.
   - **Decisão de Fase 1 que respinga no app**: o que `_meshNode.name()` retorna
     pós-38 — a folha `name` (`relay`) ou o `address` composto (`remote_pi/relay`)?
     Define o rótulo da sessão no app. **Parkear pro dive do app** (ver Fase 3).

**Exige migração:**
- **Config com `agent_name` achatado congelado**: `index.ts:1870-1874` persiste
  `agent_name: defaultAgentName(cwd)` ao criar daemon sem nome → `remote_pi/app`
  fica gravado e, pós-upgrade, é tratado como explícito (sanitiza pra
  `remote_pi-app`, sem split). **Migração**: no load, se `agent_name` ==
  `defaultAgentName_legado(cwd)` (auto-preenchido, contém `/`), **re-derivar** em
  vez de honrar como explícito. (Manter a função legada só pra comparação.)
- **Addresses hardcodados** em CLAUDE.md/contexto/skills ficam stale → mitigado
  pelo princípio "ecoar `peer.address`, nunca hardcodar".
- **Testes a atualizar**: `footer.test.ts`, `e2e.test.ts`, `setup_wizard.test.ts`
  assertam nome default / roteamento / sugestão.

## Passos (por fase, com critério de aceite)

### Fase 1 — broker + extension (local)  ← cai no pane `Extension`

1. **Identidade + derivação git/marcador** (`local_config.ts`)
   - **✅ Camada de config FEITA (2026-06-06, não commitada)**: campos `workspace?`
     (override) e `worktree?` (override opcional) + `sanitizeSegment` + refactor
     `parseLocalConfig` + env `REMOTE_PI_DIRECT_CONFIG` (ver plano 37). 445/445
     verde. **Falta o resto deste passo** (derivação marker-gated + migração +
     triagem dos callsites) e o consumo (passos 2-8).
   - Campo `workspace?` opcional no config (override explícito do derivado).
   - Helper que retorna `{ name, workspace, worktree? }` resolvendo, nesta ordem:
     `worktree` via git plumbing (decisão D); `projectRoot` (repo principal se
     worktree, senão `realpath(cwd)`); `workspace` **marker-gated** (`parent` com
     `CLAUDE.md`/`AGENTS.md` → `basename(parent)`, senão `basename(projectRoot)`),
     com `config.workspace` sobrescrevendo; `name` = `config.agent_name` ??
     `basename(projectRoot)`.
   - **Atenção**: o default atual `defaultAgentName` (`parent/folder`,
     `local_config.ts:67-73`) é **substituído** por esta derivação estruturada —
     não somar os dois (senão volta o achatamento).
   - **Migração do nome congelado**: se `config.agent_name` == o que o
     `defaultAgentName` **legado** produziria pra aquele cwd (auto-preenchido,
     contém `/`), **re-derivar** em vez de honrar como explícito — manter a função
     legada só pra essa comparação. Senão daemons criados pré-38
     (`index.ts:1870-1874`) ficam com `name` achatado + sanitizado.
   - **Triagem dos ~12 callsites de `defaultAgentName`**: os de **malha**
     (`getAgentName` `index.ts:523`, `mesh_server.ts:48`, `rpc_child.ts:116`)
     passam à identidade estruturada; os de **display/wizard**
     (`index.ts:1379/1420/2916`) podem seguir mostrando só o `name`. Mapear cada
     um explicitamente — não trocar em massa.
   - *Aceite*: testes unitários cobrem —
     - monorepo (`parent` com `CLAUDE.md`) → `workspace=parent`, `name=folha`;
     - standalone (`parent` sem marcador) → `workspace == name == basename(cwd)`;
     - `agent_name=backend` em 2 projetos distintos → workspaces distintos (sem `#2`);
     - worktree linkada → `worktree=branch` + `workspace` ancorado no repo principal
       (principal e worktree compartilham workspace);
     - detached HEAD → `worktree = basename(toplevel)`;
     - pasta não-git → sem `worktree`, `workspace = basename(cwd)`;
     - `workspace`/`agent_name` no config **sobrescrevem** o derivado;
     - **migração**: config com `agent_name` == default legado (com `/`) →
       re-deriva (não vira `parent-folder`).

2. **Encoder do `address`** (`broker.ts` ou helper)
   - Compõe `[pc:]workspace[/worktree][/name]`, **omitindo `name` quando ==
     workspace** (colapso standalone), com sanitização `/`→`-` por componente
     (decisões A+B). Único lugar que monta string.
   - *Aceite*: a matriz da tabela de render (5 linhas locais + variante cross-PC)
     passa em teste; colapso `name==workspace` confere; componentes com `/` são
     sanitizados.

3. **Register carrega os campos** (`peer.ts`/`mesh_node.ts` → `broker.ts`)
   - `RegisterMsg` ganha `workspace?`/`worktree?` opcionais; `PeerConn` guarda os
     campos + a `address` canônica; `_uniqueName`/`Map` chaveado por `address`.
   - *Aceite*: build antigo (sem campos) registra e `address == name`; build novo
     registra com campos e `address` composta; dois `app` em worktrees diferentes
     coexistem sem `#2` (addresses distintas).

4. **`list_peers` aditivo** (`broker.ts` `_handleBrokerMessage` + `mesh_server.ts`/`tools.ts`)
   - `list_peers_reply` devolve `peers: string[]` **e** `peers_detailed:
     PeerInfo[]`. O render do MCP mostra address; o detailed expõe os 4 eixos.
   - *Aceite*: cliente velho lê `peers` (addresses) e roteia; cliente novo lê
     `peers_detailed`; ambos no mesmo reply.

5. **Broadcast escopado** (`broker.ts`)
   - Broadcast entrega só a peers locais com `(workspace, worktree)` == do
     remetente (decisão C). Cross-PC permanece unicast-only.
   - *Aceite*: broadcast de um agente em `(acme, feat-login)` não chega a peer em
     `(acme, main)` nem em `(outro, …)`; chega aos da mesma worktree; caso default
     (ambos vazios, mesmo PC) mantém o alcance de hoje.

6. **`rpc_child.ts`** — `sessionName` usa a identidade efetiva (workspace prefix)
   também nos daemons.
   - *Aceite*: daemon registra com a mesma `address` que a sessão interativa
     geraria pra aquela pasta/config.

7. **Skill `agent-network`** — seção workspace/worktree: explicar que `workspace`
   é **auto-derivado** (marker-gated) e `worktree` vem do git; setar `workspace`
   no config é **override**; preferir mesmo escopo; usar `peer.address` verbatim.
   - *Aceite*: a skill não instrui montar address à mão; explica a derivação e
     quando vale **sobrescrever** com `workspace` explícito.

8. **`pnpm test` verde** com os novos casos (identidade, encoder, register c/
   campos, list_peers detailed, broadcast escopado).

### Fase 2 — cross-PC

- `broker_remote.ts` + `peer_inventory.ts` carregam `workspace`/`worktree`/`pc`
  no inventário cross-PC → `list_peers` cross-PC estruturado com `pc` preenchido.
- *Aceite*: dois PCs na malha; `list_peers` de um lado mostra peers do outro com
  `pc` correto e address `<pc>:…`; roteamento cross-PC por `address` verbatim
  funciona; broadcast continua local-only (não vaza cross-PC).

### Fase 3 — app (mobile)

- App consome `peers_detailed`: agrupa por `workspace`, badge de `worktree`/branch,
  ícone de `pc`. **Não parseia nome.** (Cai no pane `App`.)
- *Aceite*: lista de peers no app agrupada/filtrada pelos campos, sem string-split;
  worktree aparece como badge; PC como ícone.

## DoD

- [ ] **Fase 1** — identidade estruturada + detecção git de worktree;
      `register`/`PeerConn` com campos; `list_peers` aditivo (`peers` +
      `peers_detailed`); encoder de `address` (sanitizado, exact-match); broadcast
      escopado por `(workspace, worktree)`; `rpc_child` alinhado; skill atualizada;
      `pnpm test` verde
      — *parcial: camada de config (`workspace?`/`worktree?` + `sanitizeSegment` +
      env `REMOTE_PI_DIRECT_CONFIG`) FEITA 2026-06-06 (445/445), não commitada;
      falta derivação marker-gated + consumo (register/list_peers/broadcast)*
- [ ] **Fase 2** — `broker_remote` + `peer_inventory` propagam os campos;
      `list_peers` cross-PC estruturado com `pc`; roteamento por address verbatim;
      broadcast local-only preservado
- [ ] **Fase 3** — app consome `peers_detailed` (agrupa por workspace, badge de
      worktree, ícone de pc), sem parsear nome
- [ ] **Compat** — build antigo (sem campos) continua registrando e roteando
      (`address == name`); nenhum peer perde endereçamento na migração
- [ ] **Migração de legado** — config com `agent_name` == default legado é
      re-derivada (não congela `parent-folder`); triagem dos ~12 callsites de
      `defaultAgentName` feita; testes `footer`/`e2e`/`setup_wizard` atualizados

## Não-objetivos

- **Walk-up multi-nível pelo marcador** — a derivação do `workspace` checa **só o
  `parent` imediato** por `CLAUDE.md`/`AGENTS.md` (decisão A). Subir a árvore
  procurando o "root mais alto" fica fora; se a heurística errar, o usuário corrige
  com `workspace` explícito.
- **Mudar o envelope App↔Pi** — as mudanças são no wire da malha (register /
  list_peers), não no protocolo de pareamento.
- **Address opaco/hash** (decisão B = legível). 
- **Broadcast cross-PC** (decisão C = local-only; cross-PC é unicast).
- **Mexer no transporte da malha** — o broker (planos 19/25 + 34) é o baseline
  mantido (o redesign leaderless da 35 foi descontinuado). A identidade
  estruturada é aditiva a ele.

## Próximos planos / evolução

- **Transporte leaderless** (se um dia ressuscitar — a 35 foi descontinuada):
  a identidade estruturada é ortogonal ao transporte e valeria igual sobre
  UDS-direto. Reabrir como discussão explícita.
- **Reachability do cockpit (plano 37 "Próximos")**: quando o cockpit spawnar com
  a extensão remote-pi, os agentes entram na malha já com identidade estruturada
  (workspace/worktree) de graça.
- **Refinar a heurística do marcador** (se a derivação errar na prática): além de
  `CLAUDE.md`/`AGENTS.md`, considerar `.git`/`pyproject.toml`/`package.json`, ou
  walk-up. Só com evidência de erro real — hoje o `workspace` explícito é o escape.
