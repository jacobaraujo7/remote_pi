# Plano — status de turno para o Codex CLI

Estender o indicador de turno das abas (spinner / badge / chime / notificação),
hoje exclusivo do Claude Code, para sessões do **Codex CLI**.

> **Status: implementado (2026-08-11), pendente E2E no app.** As waves 0–4 estão
> fechadas; falta rodar o app de verdade e ver os quatro estados numa aba (é o
> que o usuário vai testar). A documentação de referência do resultado final
> mora em [`turn-status-hooks.md`](turn-status-hooks.md) — este arquivo fica
> como registro do caminho percorrido e dos achados da investigação.

## Contexto

O Cockpit já sabe quando um agente está trabalhando, terminou o turno ou precisa
de ação do usuário. O mecanismo (ver `project_cockpit_claude_turn_status`):

1. `ClaudeHookInstallerImpl` materializa a CLI interna em `~/.cockpit/bin/` e faz
   append idempotente de um entry marcado (`_cockpit: v1`) em cada evento de
   `~/.claude/settings.json`, sem tocar nos hooks do usuário.
2. O Claude executa `<cli> hook` a cada evento, passando um JSON por stdin.
3. `cli/src/hook.rs` traduz o evento num status (`working` / `waiting` / `idle`)
   e manda pro app por socket Unix (TCP + token no Windows), roteando pela env
   `COCKPIT_PANE_ID` que o app injeta na PTY da aba.
4. Sessão de agente fora do Cockpit não tem essas envs → o hook é no-op. Gate
   natural, sem configuração.

O Codex CLI 0.147.0 ganhou um sistema de hooks **espelhado no do Claude Code**,
o que torna a extensão majoritariamente reuso.

### O que foi apurado no binário (0.147.0)

- `codex features list` → `hooks · stable · true`. Ligado por padrão, sem flag.
- Eventos (nomes iguais aos do Claude, em PascalCase no arquivo de config):
  `PreToolUse`, `PermissionRequest`, `PostToolUse`, `PreCompact`, `PostCompact`,
  `SessionStart`, `SessionEnd`, `UserPromptSubmit`, `SubagentStart`,
  `SubagentStop`, `Stop`.
- Envelope de entrada (schemas embutidos, ex. `post-tool-use.command.input`):
  `hook_event_name`, `session_id`, `transcript_path`, `cwd`, `model`,
  `permission_mode`, `tool_name`, `tool_input`, `tool_response`, `tool_use_id`,
  e um `turn_id` que o Claude não manda.
- Config em `hooks.json` (global sob `~/.codex/`, project-local sob `.codex/`),
  com a mesma forma `{ matcher, hooks: [{ type, command, timeout }] }`.
  Handlers possíveis: `command` | `prompt` | `agent` — usamos `command`.
- Existe `hooks.state` com `enabled` / `trusted_hash`: há um **gate de
  confiança** sobre hooks. Era a principal incógnita do plano; a Wave 0
  resolveu (ver "Resultado da Wave 0" abaixo).
- O `notify` legado (`agent-turn-complete`) continua existindo, mas só cobre fim
  de turno. Fica como plano B se o gate de confiança inviabilizar os hooks.

### Mapeamento de eventos → status

| Evento Codex | Status | Nota |
|---|---|---|
| `UserPromptSubmit` | `working` | início de turno |
| `PreToolUse` / `PostToolUse` | `working` | atividade mid-turn |
| `PermissionRequest` | `waiting` | **melhor que no Claude**: evento explícito, sem heurística de texto |
| `Stop` | `idle` | fim de turno (chime/notificação) |
| `SessionStart` / `SessionEnd` | `idle` | também amarra aba → sessão |
| `SubagentStart` / `SubagentStop` | — | ignorados na v1 (subagente não deve mexer no indicador da aba) |
| `PreCompact` / `PostCompact` | — | ignorados |

O desvio do `PreToolUse` bloqueante (`AskUserQuestion` / `ExitPlanMode` →
`waiting`) **não tem equivalente aqui**: no Codex a aprovação tem evento próprio.
Não replicar a heurística.

## Estrutura esperada

```
cli/src/hook.rs                     # status_for ganha os eventos do Codex
lib/app/cockpit/domain/contracts/
  hook_installer.dart               # contrato genérico (renomeia claude_hook_installer)
lib/app/cockpit/data/hooks/
  hook_installer_base.dart          # materialização da CLI + append idempotente
  claude_hook_installer_impl.dart   # alvo ~/.claude/settings.json
  codex_hook_installer_impl.dart    # alvo ~/.codex/hooks.json
lib/app/bootstrapper.dart           # instala os dois no boot
```

## Waves

### Wave 0 — Spike: confirmar formato e gate de confiança

Antes de escrever código de produção, provar o caminho na mão.

1. Escrever um `~/.codex/hooks.json` apontando pra um script que faz `cat` do
   stdin num arquivo, registrado em `UserPromptSubmit`, `PermissionRequest`,
   `Stop`, `SessionStart`, `SessionEnd`.
2. Rodar um `codex exec` curto num diretório de teste.
3. Capturar: caminho real do arquivo de config, forma exata do JSON aceito,
   payload cru de cada evento, e **se o Codex pediu confirmação de confiança**
   (o `trusted_hash`).

**Aceite**: um arquivo de exemplo commitável em `docs/` com o `hooks.json` que
funciona e um payload real de cada um dos 5 eventos. Resposta escrita para: o
gate de confiança bloqueia instalação por fora? Se sim, qual é o fluxo (aprovar
uma vez, pré-computar o hash, ou variável de ambiente)?

**Gate**: se o gate de confiança exigir interação a cada mudança do arquivo,
reavaliar antes das waves seguintes — possivelmente cair pro `notify` legado
(cobertura menor: só fim de turno) e documentar a limitação.

#### Resultado da Wave 0

Melhor que o esperado: **o trust é pré-computável**, o plano B não foi
necessário.

- Arquivo: `~/.codex/hooks.json` (só a raiz do `CODEX_HOME`; `~/.codex/hooks/`
  não é lido). Forma igual à do Claude, com os eventos em PascalCase.
- Sem trust, o hook é ignorado **em silêncio** — nem aviso, nem log. Foi o que
  fez a primeira tentativa parecer "formato errado".
- O trust vive em `[hooks.state."<path>:<evento_snake>:<grupo>:<handler>"]` no
  `config.toml`, com `trusted_hash = "sha256:…"` sobre o JSON canônico da
  identidade normalizada do handler. Como deriva da config e não do binário,
  computamos e gravamos junto — sem interação do usuário.
- Campos extras no handler (nosso marcador `_cockpit`) são ignorados pelo
  parser e **não** entram no hash.
- Ciclo observado numa sessão real: `SessionStart` → `UserPromptSubmit` →
  `PreToolUse` (`tool_name: "Bash"`) → `PostToolUse` → `Stop` → `SessionEnd`.

Detalhes do algoritmo e das limitações em
[`turn-status-hooks.md`](turn-status-hooks.md).

### Wave 1 — CLI: `status_for` entende os eventos do Codex

`cli/src/hook.rs` é agnóstico de harness: lê `hook_event_name` e roteia pelo env.
Mudanças:

1. `PermissionRequest` → `waiting`.
2. `SubagentStart` / `SubagentStop` / `PreCompact` / `PostCompact` → `None`
   (explícito, com teste, pra não mexerem no indicador).
3. Manter o desvio do `PreToolUse` bloqueante como está (é do Claude; no Codex
   `tool_name` não bate com `AskUserQuestion`/`ExitPlanMode`, então é inerte).
4. Repassar `turn_id` no payload quando presente — o app hoje usa `ev`/`sid` pra
   descartar `working` fora de ordem, e o `turn_id` torna isso mais preciso
   (opcional na v1: só transportar, sem consumir).

**Aceite**: testes unitários no `hook.rs` cobrindo os eventos novos; `cargo test`
verde. O hook do Claude continua com o comportamento atual (nenhum teste
existente muda).

### Wave 2 — Instalador genérico

`ClaudeHookInstallerImpl` já contém tudo o que o Codex precisa: materialização da
CLI (`_ensureCli`, `_sameContent`, `_chmodExec`), resolução do comando
(`_resolveHookCommand`, `_shellQuote`, `_hookPath` com as barras normais do
Windows) e o append idempotente marcado (`_isOurs`).

1. Extrair a parte comum para uma base, deixando nas subclasses só: caminho do
   arquivo de config, lista de eventos e a chave onde os hooks moram (`hooks` nos
   dois casos, a confirmar pelo spike).
2. `CodexHookInstallerImpl` escreve em `~/.codex/hooks.json` com os eventos:
   `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PermissionRequest`, `Stop`,
   `SessionStart`, `SessionEnd`.
3. Preservar as garantias atuais: nunca reescrever a lista de hooks do usuário,
   remover o entry antigo nosso antes de readicionar, tolerar arquivo ausente ou
   ilegível sem derrubar o boot.
4. Renomear o contrato para `HookInstaller` (mantendo `ClaudeHookInstaller` como
   alias se algo externo depender do nome).

**Aceite**: rodar o app duas vezes seguidas não duplica entries em nenhum dos
dois arquivos; hooks pré-existentes do usuário em `~/.codex/hooks.json`
sobrevivem; sem `~/.codex/`, a instalação do Codex falha em silêncio e a do
Claude segue normal.

### Wave 3 — Ligar no boot e E2E

1. `bootstrapper.dart` chama os dois instaladores (falha de um não impede o
   outro).
2. E2E manual, com build `.debug` (bundle id isolado, memória
   `project_cockpit_debug_flavor`): abrir aba, rodar `codex`, mandar um prompt
   que use ferramenta e peça aprovação, e conferir na aba: spinner ao enviar,
   badge de "precisa de ação" na aprovação, chime/notificação no fim do turno,
   indicador limpo ao sair.
3. Conferir que uma sessão `codex` **fora** do Cockpit não emite nada (gate por
   env).

**Aceite**: os quatro estados observados numa sessão real de Codex, e o Claude
sem regressão na mesma build.

### Wave 4 — Documentação

1. Seção no `CLAUDE.md` do cockpit (ou em `docs/`) descrevendo que o status de
   turno cobre Claude Code **e** Codex CLI, e onde cada arquivo de config mora.
2. Nota no CHANGELOG na release que levar isso (em inglês, user-facing).

## Definition of Done

- [x] Wave 0: `hooks.json` validado + payloads reais capturados
- [x] Wave 0: resposta escrita sobre o gate de confiança (`trusted_hash`)
- [x] Wave 1: `status_for` cobre os eventos do Codex, com testes
- [x] Wave 2: instalador genérico + `CodexHookInstallerImpl`, idempotente
- [x] Wave 3: instalação no boot
- [ ] Wave 3: E2E dos quatro estados numa aba do app **(a testar)**
- [ ] Wave 3: sessão de Codex fora do Cockpit não emite status **(a testar)**
- [x] Wave 4: documentação (`turn-status-hooks.md`)
- [ ] Wave 4: CHANGELOG — a seção é escrita no `/deploy` (o guard reprova
      `## [Unreleased]` no topo, então não dá pra adiantar aqui)

### O que sobrou para o teste manual

O `PermissionRequest` não apareceu nas capturas porque `codex exec` roda com
aprovação desligada. Ele é o evento que vira o badge de "precisa de ação", então
vale conferir explicitamente: numa aba, com o Codex em modo interativo, pedir
algo que exija aprovação e ver a aba mudar para `waiting` (badge + chime).

## Fora de escopo

- Subagentes do Codex movendo o indicador da aba (só a sessão principal).
- Usar os handlers `prompt` / `agent` do Codex — só `command`.
- Bloquear ou modificar comportamento do agente pelo hook (nosso hook é
  observador puro: nunca escreve no stdout, nunca falha barulhento).
- Outros harnesses (`pi`, Gemini CLI): o instalador genérico abre o caminho, mas
  cada um exige investigação própria.
