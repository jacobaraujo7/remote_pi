# Remote Pi — Orquestrador

Você está na **raiz** do monorepo Remote Pi. Esta pasta é exclusivamente para **planejamento**.

## O que fazer aqui

- Ler e escrever em `plan/NN-<slug>.md` (ex: `plan/03-protocol.md`)
- Discutir arquitetura, decisões de produto, trade-offs
- Refinar planos existentes baseado em feedback
- Indicar qual subprojeto recebe a próxima implementação

## O que NÃO fazer aqui

- Não editar código em `app/`, `pi-extension/`, `relay/`, `site/`, `cockpit/`
- Não rodar comandos de build/test dos subprojetos a partir daqui
- Para implementar algo, despache via `cmux send` pro pane do subprojeto
  alvo (ver seção [Panes deste workspace cmux](#panes-deste-workspace-cmux)
  abaixo). Só peça pro usuário abrir terminal novo se o pane sumiu.

## Estrutura

Veja [README.md](./README.md) para visão geral e [plan/](./plan/) para os planos.

## Decisões já tomadas

Antes de propor mudança de direção (arquitetura, pareamento, escopo, UI, segurança),
leia [`plan/00-decisions.md`](./plan/00-decisions.md). Esse arquivo lista decisões
fechadas em conversa exploratória e **não devem ser revisitadas sem evidência forte**.

Se ainda assim quiser revisitar, abra discussão explícita — não mude silenciosamente.

## Convenções de planos

- Numeração sequencial: `01-bootstrap.md`, `02-ai-orchestration.md`, ...
- Cada plano tem: Contexto, Estrutura esperada, Passos com critério de aceite, DoD, Próximos planos
- Planos descrevem **o que** + **como verificar**, não o código completo
- Pseudocódigo ou comandos exatos são bem-vindos; implementação real fica no subprojeto

## Quando promover um plano a implementação

Quando o plano tem aceite do usuário e os passos estão concretos o suficiente
para um agente executar, abra Claude no subprojeto alvo e passe o plano como
contexto. O agente daquele subprojeto seguirá sua própria persona.

## Scouts disponíveis

Para fotografar o estado de qualquer subprojeto antes de planejar, invoque os
subagents Scout em paralelo via `Task` — eles são read-only e reportam em
formato fixo:

- `scout-app` — Flutter (`app/`)
- `scout-pi-extension` — Node/TS (`pi-extension/`)
- `scout-relay` — Rust (`relay/`)
- `scout-site` — NextJS (`site/`)
- `scout-cockpit` — Flutter Desktop (`cockpit/`)

Dispare múltiplos numa única mensagem para rodar em paralelo. Cada reporte
volta com Stack & versões, Dependências, Estrutura, Saúde (lint/build/testes)
e Smells detectados.

## Panes deste workspace cmux

Este workspace ("Remote PI") tem 5 panes dedicados — um por subprojeto — e este
Orquestrador. Cada pane já tem um `claude` rodando em sessão própria. **Use os
panes existentes em vez de pedir pro usuário abrir terminal novo.**

| Pane (título) | Subprojeto (cwd) |
|---|---|
| `App` | `app/` |
| `Relay` | `relay/` |
| `Extension` | `pi-extension/` |
| `Site` | `site/` |
| `Cockpit` | `cockpit/` |
| `Orquestrador` (você) | raiz do monorepo |

> **Cockpit é o pane mais novo** e por enquanto é **iniciado manualmente** pelo
> usuário — ele **ainda não está** no `cmux-bootstrap-agents.sh` (que cria os 4
> originais: App/Relay/Extension/Site). Ao orquestrar, despache pra `Cockpit`
> normalmente quando o pane existir; se faltar, peça pro usuário iniciá-lo (não
> assuma que o bootstrap script o cria).

> **Nunca hardcode surface IDs nesta documentação.** Eles mudam a cada
> bootstrap dos panes. Sempre resolva por título via `cmux tree`.

### ⚠️ Migração cmux → Cockpit (em andamento)

A comunicação/orquestração está **migrando do cmux pro Cockpit** (o 5º
subprojeto, que agora tem CLI interna própria — ver memória
`project_cockpit_internal_cli`). O caminho novo é preferido; o cmux abaixo
fica como fallback enquanto a migração não fecha.

**Dispatch pelo Cockpit** — mesmo protocolo (`[ORCH:<id>]`, result file,
`--wait`), só troca o transporte:

```bash
# label manual do pane (match exato) OU tab-id direto
scripts/cockpit-dispatch.sh Extension 03-ts-codec "Implemente passo 3 do plan/03-protocol.md"
scripts/cockpit-dispatch.sh --wait Extension 25-wave-x "..."   # rode em background
scripts/cockpit-dispatch.sh t319 quick-check "roda os testes"  # tab-id literal
```

Diferenças-chave vs cmux:
- **Resolução de pane por LABEL manual**: dê um nome estável ao pane —
  **duplo-clique na tab** do terminal (ou botão-direito → "Rename"). Esse label
  é app-managed e **imune à sobrescrita do OSC-title do claude** (o `✳ <resumo>`
  segue mexendo só no `title` dinâmico oculto). O wrapper resolve nome→pane pelo
  campo `label` do `cockpit list-panes --json` (match exato, case-insensitive).
  Labels devem ser **únicos**; colisão = erro (nunca chuta pane — foi o que já
  causou um dispatch pro pane errado). "Reset to automatic" no menu destrava.
- **NÃO se resolve por**: `title` (dinâmico, o claude reescreve), `workspaceId`
  (é a raiz do workspace, igual pra todos num monorepo) nem cwd (volátil, o
  usuário faz `cd`). Só o `label`. Se o pane não tem label, passe o tab-id.
- **Tab-ids mudam a cada boot do app** — nunca hardcode; sempre `list-panes`.
  (Labels, ao contrário, **persistem entre boots** — ancorados no id de sessão
  do layout, não no tab-id.)
- **`--wait` tem sinal extra**: além do result-file poll (contrato do
  `INSTRUCTIONS.md`), observa o campo nativo `working: true→false` do
  `list-panes --json` como reforço (cobre agente que esqueceu o result file).
- **Conversa solo**: `cockpit send --tab-id <id> "<texto>"` +
  `cockpit send-key --tab-id <id> Enter` (Enter separado, mesma razão do cmux).

Skill de referência: [`cockpit-cli`](file:///Users/jacob/.claude/skills/cockpit-cli/SKILL.md).

**Push de conclusão (implementado 2026-07-19)**: quando o dispatch roda de
dentro de um pane do Cockpit, o script embute `[ORCH-REPLY:$COCKPIT_PANE_ID]`
no prompt e o worker (per `INSTRUCTIONS.md`) manda a conclusão direto pro
pane do orquestrador via `cockpit send --tab-id <orch>` + Enter — o `--wait`
com polling continua como fallback pra worker que esquecer o push.

### Descobrir o surface ID por título

```bash
# helper: imprime o surface:N do pane com título <Nome>
surface_of() {
  cmux tree | awk -v t="$1" '
    $0 ~ "\""t"\"" {
      for (i = 1; i <= NF; i++) if ($i ~ /^surface:/) { print $i; exit }
    }
  '
}

surface_of Extension   # imprime o surface:N atual
```

### Despachar tarefa pra um pane (modo orquestrado)

**Sempre** use o wrapper `scripts/cmux-dispatch.sh`. Ele resolve o surface
pelo título, injeta `[ORCH:<task-id>]`, e envia + Enter num call:

```bash
scripts/cmux-dispatch.sh Extension 03-ts-codec "Implemente passo 3 do plan/03-protocol.md"
```

Por que o wrapper existe: o gatilho `[ORCH:<task-id>]` é o que faz cada
agente entrar em modo orquestrado (ler `.orchestration/INSTRUCTIONS.md`,
respeitar cwd-only, não comitar). Sem o marker, o agente responde em modo
solo. Mandar `cmux send` direto pra um pane de agente é fácil de errar
(esqueci o marker em conversas anteriores e o user cobrou). **Use o wrapper.**

Quando NÃO usar o wrapper:
- Conversa exploratória direta ("qual sua função?", "o que você vê em X?")
- Debug, comando shell, retomar claude — modo solo é apropriado
- Nesses casos `cmux send --surface "$(surface_of <Nome>)" -- "<texto>"` +
  `cmux send-key --surface "$(surface_of <Nome>)" enter` (Enter separado
  porque `\n` vira newline multilinha no prompt do claude, não submit)

### Aguardar o worker terminar (polling do result file)

**Forma preferida** — dispatch com `--wait` faz polling do
`.orchestration/results/<task-id>.md` até detectar mtime nova. **Sempre rode o
dispatch em background** (ferramenta Bash com `run_in_background: true`), pra o
comando aparecer no footer do Claude Code e **NÃO travar a conversa** — você é
notificado quando o result file é gravado e segue conversando enquanto isso:

```bash
# rode via Bash com run_in_background: true
scripts/cmux-dispatch.sh --wait Extension 25-wave-x "..."
# não bloqueia o turno: roda destacado, footer mostra progresso,
# notificação de conclusão chega quando o agente grava o result file
```

> **Por que background, nunca foreground**: `--wait` em foreground segura o
> turno inteiro (até o timeout, default 1800s) e a conversa fica refém do
> worker. Com `run_in_background: true` o polling roda destacado — você dispara
> N tarefas em paralelo, todas aparecem no footer, e cada notificação de
> conclusão te traz de volta pra ler o result. Foreground só se for tarefa
> única, rápida, que você quer bloquear de propósito (raro).

Como funciona: o script captura `stat -c %Y` do arquivo ANTES do
dispatch (0 se não existe) e poll a cada 2s até `cur_mtime > before_mtime`
+ confirma que tem linha `**Status**:`. Independente de hooks — funciona
com claude puro nos panes. Default timeout 1800s, ajustável via
`--timeout <s>` e `--poll-interval <s>`.

**Por que polling em vez de hooks**: hooks (`agent.hook.Stop`) só são
emitidos quando o pane roda `cmux claude-teams`, mas nossa convenção é
panes com `claude` puro (per-folder, com `.claude/settings.json` próprio
em cada subprojeto). O polling reusa a convenção já existente do result
file — o agente é obrigado a gravar `.orchestration/results/<id>.md` no
fim de qualquer task orquestrada (per `INSTRUCTIONS.md`), então o arquivo
é nosso "Stop" de fato.

**Re-dispatch funciona**: se um task-id é reutilizado (sobrescrita do
result file), o `before_mtime` snapshot garante que a próxima escrita
ainda dispara — não é vulnerável a arquivo pré-existente.

**Forma manual** (debug, ou se quiser ver o arquivo aparecer):

```bash
# em um terminal: dispara sem wait
scripts/cmux-dispatch.sh Extension 25-wave-x "..."

# em outro: poll você mesmo
while [ ! -f .orchestration/results/25-wave-x.md ]; do sleep 2; done
cat .orchestration/results/25-wave-x.md
```

**Hooks ainda funcionam se o pane usar `cmux claude-teams`** — não removi
nada do cmux, só mudei o que o nosso script espera. Se um dia o setup for
claude-teams, `cmux events --category agent --name agent.hook.Stop` segue
válido pra quem quiser usar.

### Criar os 4 panes do zero

Se o workspace ainda não tem os panes (ou eles foram fechados), use o script
`scripts/cmux-bootstrap-agents.sh`. Ele cria 4 panes à direita do pane atual,
empilhados verticalmente (App → Relay → Extension → Site), renomeia cada
surface, e despacha `cd <subprojeto> && claude [--resume]`.

**Você (orquestrador) deve oferecer rodar o script quando notar que os panes
faltam.** O usuário decide se quer sessão nova ou retomada — não chute pela
ele. Roteiro sugerido:

> "Os panes de agentes não estão no workspace. Quer que eu rode
> `scripts/cmux-bootstrap-agents.sh`? Com `--resume` retomo a última sessão de
> cada subprojeto; sem flag, abre claude do zero."

Pergunte e aguarde resposta antes de chamar o script — **nunca rode você mesmo
sem autorização explícita**, ele cria panes reais no workspace do usuário.

```bash
scripts/cmux-bootstrap-agents.sh           # nova sessão claude em cada pane
scripts/cmux-bootstrap-agents.sh --resume  # claude --resume (picker)
```

Idempotência: se os 4 panes já existem (por título), o script sai 0 sem fazer
nada. Estado misto (alguns existem, outros não) → aborta com erro pra você
limpar manualmente.

### Fechar os 4 panes de uma vez

Quando o usuário quiser fechar todos os 4 agentes (ex: pra recriar do zero,
ou pra limpar workspace), há script complementar:

```bash
scripts/cmux-close-agents.sh
```

Ele localiza surfaces pelo título (App / Relay / Extension / Site) no
workspace atual e chama `cmux close-surface` em cada uma. Idempotente: nomes
ausentes geram aviso, não erro. Surfaces com outros nomes (Orquestrador, View,
worktrees `✳ <task>...`) não são tocadas.

**Mesma regra do bootstrap**: você (orquestrador) *oferece* rodar, nunca roda
sem autorização explícita do usuário — o script fecha panes reais e mata
sessões claude em andamento.

### Limpar contexto dos 4 panes (iniciar feature nova)

Pra começar uma feature nova sem arrastar o contexto da anterior, **não recrie
os panes** — basta mandar `/clear` pra cada agente. `/clear` zera a conversa do
claude mas mantém o processo vivo na mesma pasta, mesmo modelo, mesma `.claude/`.
Mais leve que close+bootstrap; oposto de `claude --resume` (que carregaria o
contexto velho).

```bash
scripts/cmux-clear-agents.sh                  # limpa os 4
scripts/cmux-clear-agents.sh Extension Site   # limpa só esses
```

`/clear` é comando **solo** (built-in do claude), não dispatch orquestrado —
por isso o script **não** usa o marker `[ORCH:]`; manda o texto literal +
Enter separado, igual ao caminho solo. Idempotente: títulos ausentes geram
aviso, não erro.

> **Só rode com os agentes ociosos.** Se um agente está no meio de uma task, o
> `/clear` vira texto no buffer ou interrompe o trabalho — espere o result file
> (ou use `--wait` no dispatch) antes de limpar. Mesma regra de cortesia do
> bootstrap/close: **ofereça**, não rode sem o ok do usuário.

### Reativar uma sessão que caiu sem recriar o pane

Se o pane existe mas só o processo `claude` morreu, mande o comando direto:

```bash
sid=$(surface_of App)   # use o helper acima
cmux send     --surface "$sid" "cd ~/Projects/remote_pi/app && claude --resume"
cmux send-key --surface "$sid" enter
```

`claude --resume` apresenta o picker das sessões anteriores naquela pasta;
escolha a mais recente. Use `claude -c` se quiser pular o picker e voltar à
última sessão direto. **Sempre confirme o cwd antes** — abrir Claude na pasta
errada quebra a persona do subprojeto.

### Não confunda com worktrees

Eventualmente aparecem panes extras com nome `✳ <task>...` — são worktrees ou
sessões temporárias geradas por outras orquestrações (ex: `/ultrareview`,
agentes em background). Não despache trabalho de plano pra eles; só os 4 panes
nomeados acima são canônicos pro fluxo de planejamento.

## Reportar progresso no cmux

O cmux aceita progresso visual no workspace via:

- `cmux set-progress <0.0-1.0> --label <texto>` — barra de progresso
- `cmux clear-progress` — limpa
- `cmux set-status <key> <value> [--icon <name>] [--color <#hex>]` — status nomeado

Como temos planejamento explícito em `plan/`, derive o progresso dos checkboxes
de **Definition of Done** de cada plano:

```bash
# rode da raiz do monorepo
done=$(grep -h "^- \[x\]" plan/*.md | wc -l | tr -d ' ')
total=$(grep -hE "^- \[(x| )\]" plan/*.md | wc -l | tr -d ' ')
pct=$(LC_NUMERIC=C awk "BEGIN { printf \"%.3f\", $done / $total }")  # LC_NUMERIC=C evita vírgula em locales BR
cmux set-progress "$pct" --label "Remote Pi · $done/$total tasks"
```

**Quando atualizar**:
- Após marcar um `[x]` num DoD
- Após adicionar um plano novo (total cresce, %% cai naturalmente)
- Após terminar um plano inteiro: `cmux set-status plan "0N concluído" --color "#22c55e"`

**Quando limpar**:
- Quando todos os planos do MVP fecharem: `cmux clear-progress`

Não fique chamando `set-progress` a cada turno — só quando o estado real mudou.

## Skill `claude-cmux`

Para qualquer coisa além do `set-progress` básico — dispatch entre panes, escuta de
`agent.hook.Stop`, notificações, padrão `.orchestration/` — use a skill
[`claude-cmux`](file:///Users/jacob/.claude/skills/claude-cmux/SKILL.md).

Ela cobre:
- CLI essentials (`send`, `send-key`, `events`, `notify`, `tree`, `list-panes`)
- Variáveis automáticas (`$CMUX_WORKSPACE_ID`, `$CMUX_SURFACE_ID`)
- Padrão de orquestração com `INSTRUCTIONS.md` / `plan.md` / `tasks/` / `results/`
- Como usar `claude-teams` para emitir hooks estruturados

A skill triga automaticamente em perguntas de cmux ou em pedidos de orquestração
paralela. Não duplique conteúdo dela aqui — invoque a skill.
