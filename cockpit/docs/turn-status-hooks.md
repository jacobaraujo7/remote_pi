# Status de turno — hooks dos harnesses

Como o Cockpit sabe que um agente numa aba está trabalhando, terminou o turno ou
precisa de uma ação do usuário (spinner, badge, chime, notificação do SO).

Suportados hoje: **Claude Code** e **Codex CLI** (0.147+).

## Como funciona

1. No boot, `bootstrapper.dart` roda os `HookInstaller` de cada harness. Eles
   materializam a CLI interna em `~/.cockpit/bin/cockpit` e registram
   `<cli> hook` nos eventos de ciclo de vida da config do harness.
2. A cada evento, o harness executa `cockpit hook` passando um JSON pelo stdin.
3. `cli/src/hook.rs` traduz o evento num status (`working` / `waiting` / `idle`)
   e manda pro app por socket Unix (TCP + token no Windows).
4. O roteamento é pela env `COCKPIT_PANE_ID`, que o app injeta na PTY da aba.
   Sessão de agente aberta **fora** do Cockpit não tem essa env, então o hook é
   no-op. É o gate natural: nada a configurar, nada a desligar.

Por que socket e não OSC na PTY: os harnesses rodam hooks sem terminal
controlador, e escrever em `/dev/tty` falha com `ENXIO`.

## Onde cada um instala

| Harness | Arquivo | Formato |
|---|---|---|
| Claude Code | `~/.claude/settings.json` | `hooks.<Evento>[]`, cada item `{matcher, hooks:[{type, command}]}` |
| Codex CLI | `~/.codex/hooks.json` | mesma forma; **mais** um bloco de trust no `~/.codex/config.toml` |

Os dois instaladores fazem **append idempotente** de um entry marcado
(`_cockpit: v1`): re-rodar remove o entry antigo nosso e re-adiciona, sem nunca
reescrever a lista (hooks do usuário, de plugins ou do iTerm2 sobrevivem).

## Mapeamento de eventos

| Evento | Claude | Codex | Status |
|---|:--:|:--:|---|
| `UserPromptSubmit` | ✓ | ✓ | `working` (início de turno) |
| `PreToolUse` | ✓ | ✓ | `working` — exceto ferramenta bloqueante do Claude (ver abaixo) |
| `PostToolUse` | ✓ | ✓ | `working` |
| `Notification` | ✓ | — | `waiting` / `idle` (heurística sobre o texto) |
| `PermissionRequest` | — | ✓ | `waiting` |
| `Stop` | ✓ | ✓ | `idle` |
| `SessionStart` / `SessionEnd` | ✓ | ✓ | `idle` |
| `SubagentStart` / `SubagentStop`, `PreCompact` / `PostCompact` | — | ✓ | **ignorados**: não são o turno da aba |

Duas assimetrias que importam:

- **Claude**: ferramentas que bloqueiam esperando o usuário (`AskUserQuestion`,
  `ExitPlanMode`) não emitem `Notification`. O último hook antes do bloqueio é o
  `PreToolUse`, então ele vira `waiting` para essas duas — senão a aba fica com
  spinner eterno, sem chime.
- **Codex**: a aprovação tem evento próprio (`PermissionRequest`), então não há
  heurística de texto nem desvio no `PreToolUse`. O desvio do Claude continua no
  código e é inerte aqui (aquelas ferramentas não existem no Codex).

O envelope é praticamente o mesmo nos dois (`hook_event_name`, `session_id`,
`transcript_path`, `cwd`, `tool_name`, `tool_input`, `permission_mode`). O Codex
manda um `turn_id` a mais, que o helper repassa como `tid`.

## Retomar a sessão (quem é o dono do session-id)

O app persiste no layout o `session_id` que veio pelo hook, e no restore da aba
digita o comando que reata a conversa. **O id sozinho não diz de qual harness
é**, e os comandos diferem:

| Harness | Comando de resume |
|---|---|
| Claude Code | `claude --resume <id>` |
| Codex CLI | `codex resume <id>` |

Por isso o instalador registra o comando do hook com `--harness <nome>`
(`cockpit hook --harness codex`), o helper carimba o payload com `hn`, e o
layout guarda `harness` ao lado de `claude_sid`. Sem a flag, o helper assume
`claude` — é o que os entries instalados por versões anteriores passam, e todos
eles eram do Claude.

Foi exatamente esse o bug do primeiro E2E: o app restaurou uma aba de Codex com
`claude --resume <id do codex>` e o Claude respondeu "No conversation found with
session ID".

## O gate de confiança do Codex

O Codex **só executa hook confiado**. Sem trust ele ignora o hook **em
silêncio** — nenhum aviso, nenhum log. O trust vive no `~/.codex/config.toml`:

```toml
[hooks.state."/Users/você/.codex/hooks.json:session_start:0:0"]
enabled = true
trusted_hash = "sha256:…"
```

- **Chave**: `"<caminho do hooks.json>:<evento_snake>:<índice do grupo>:<índice do handler>"`.
- **Hash**: `sha256` (hex, prefixado `sha256:`) do **JSON canônico** — chaves
  ordenadas, sem espaços — da identidade normalizada do handler:

  ```json
  {"event_name":"session_start","hooks":[{"async":false,"command":"…","timeout":600,"type":"command"}]}
  ```

  O `timeout` é o **normalizado**: 600s para todos os eventos, exceto
  `SessionEnd`, que tem default 1s (teto 3s). Campos ausentes (`matcher`,
  `commandWindows`, `statusMessage`, `additionalContextLimit`) não entram.
  Campos extras no arquivo — como o nosso marcador `_cockpit` — são ignorados
  na desserialização e **não** afetam o hash.

Como o hash deriva da config e não do binário, o Cockpit computa e grava o trust
junto com a instalação: o usuário não precisa aprovar nada na mão. É o mesmo
grau de confiança que já assumimos ao escrever no `settings.json` do Claude —
instalamos o nosso helper, e só ele. O bloco fica entre delimitadores
(`# >>> cockpit hooks` … `# <<< cockpit hooks`) e é regerado a cada boot;
o resto do `config.toml` nunca é tocado.

Referência no fonte do Codex: `codex-rs/hooks/src/engine/discovery.rs`
(`hook_hash`, `hook_key`) e `codex-rs/config/src/fingerprint.rs`
(`version_for_toml`).

### Limitações conhecidas

- **Índice do grupo faz parte da chave.** Se o usuário adicionar um hook próprio
  *antes* do nosso no mesmo evento, nosso índice muda e o trust deixa de bater —
  o hook para de rodar, em silêncio. O instalador corrige no boot seguinte,
  porque recalcula os índices a partir do arquivo final.
- **Editar o `hooks.json` na mão** entre boots tem o mesmo efeito, e a mesma
  correção.
- Se o Codex mudar o algoritmo do hash, o teste de golden em
  `test/data/codex_hook_installer_test.dart` quebra — os valores lá foram
  capturados de uma sessão real que executou os hooks sem
  `--dangerously-bypass-hook-trust`.

## Estrutura no código

```
cli/src/hook.rs                                   # tradução evento → status (agnóstico de harness)
lib/app/cockpit/domain/contracts/hook_installer.dart
lib/app/cockpit/data/hooks/hook_installer_base.dart      # CLI + comando (comum)
lib/app/cockpit/data/hooks/claude_hook_installer_impl.dart
lib/app/cockpit/data/hooks/codex_hook_installer_impl.dart
lib/app/bootstrapper.dart                         # roda os dois no boot, não-fatal
```


## Fork em nova aba

A barra da pane mostra **Fork em nova aba** quando a aba ativa contém um
agente reconhecido. O botão desaparece quando o agente encerra; abas ocultas
continuam executando normalmente. O fork usa a mesma pasta, perfil e engine
na mesma pane, seleciona a nova aba e mantém o terminal original intacto.

A disponibilidade é conservadora e específica por agente:

| Agente | Integração desta entrega |
|---|---|
| Claude Code | `claude --resume <id> --fork-session` |
| Codex CLI | `codex fork <id> --no-daemon` |
| Pi | `pi --fork <caminho exato do transcript>` |
| OpenCode e GitHub Copilot CLI | Desabilitado: falta vínculo validado entre a sessão do servidor/API e a aba |
| Cursor Agent e Agy | Desabilitado: o `/fork` interativo não é um mecanismo externo seguro |

Nos três primeiros, o Cockpit verifica a opção na ajuda do executável antes
de habilitar a ação. Esta entrega habilita hosts locais POSIX com perfis
`sh`, `bash`, `zsh` ou `fish` (também PowerShell em POSIX). Windows, WSL,
hosts remotos e outros perfis permanecem desabilitados com explicação.
Não há fallback para a sessão mais recente nem leitura do texto do terminal.

O envelope dos hooks aceita `pids`, uma lista de inteiros positivos com a
ancestralidade do helper, encerrada no agente mais próximo. O monitor liga
essa lista ao PID do agente em foreground. A identidade usada pelo fork é
separada do ID persistido para restore: hooks antigos sem `pids` continuam
atualizando status, mas não habilitam fork. Antes de abrir a nova aba, uma
inspeção fresca confirma que o processo e a conversa continuam sendo os mesmos.

No Pi, o bootstrap instala `~/.pi/agent/extensions/cockpit-status.ts`, sem
alterar extensões do usuário. A extensão usa `session_start`, `agent_start`,
`agent_end` e `session_shutdown` para reportar status, ID, transcript salvo e
PID pelo transporte autenticado existente. Fora de um terminal do Cockpit,
é inerte. Uma conversa efêmera/ainda não salva não habilita o botão. O caminho
exato permite ramificar sessões guardadas em diretórios personalizados.
Instalações isoladas continuam sem modificar hooks/extensões globais.

É necessário reconstruir o app e sua CLI embarcada para usar o novo envelope;
sessões anteriores podem precisar ser reiniciadas. O fork não cria worktree
nem copia permissões temporárias que o CLI não restaure por conta própria.
Erros de inicialização ficam visíveis na nova aba para diagnóstico.


### Codex e servidor compartilhado

Desde o servidor compartilhado, hooks do Codex executam no app-server e
herdam o ambiente do primeiro cliente, sem um vínculo confiável com a aba
que está exibindo a conversa. Por isso iniciar simplesmente `codex` pode
não fornecer identidade de fork nesta aba. O botão explica que é necessário
abrir uma nova aba de terminal, em vez de aguardar indefinidamente.

Abertura pelo menu da pasta, boxes do grafo, restore e forks criados pelo
Cockpit passam `--no-daemon`. Esse modo usa um servidor privado da sessão;
não encerra nem altera o servidor compartilhado de outros clientes. O
monitor e o helper ignoram processos `codex app-server`/`exec-server` como
agente interativo e continuam até o TUI correto. Sessões já abertas no modo
compartilhado precisam ser relançadas; o Cockpit não interrompe a conversa.


### Comando normal, integração automática

Nos terminais locais do Cockpit, basta digitar `codex`, `codex resume` ou
`codex fork`: o app fornece um launcher privado `cockpit-codex` ao shell,
que acrescenta o modo de servidor privado quando o executável instalado
suporta essa opção. Não é preciso incluir flags no comando digitado.

A função exportada do Bash, os proxies de startup do Zsh e o init-command do
Fish mantêm essa integração mesmo quando um gerenciador como mise reorganiza
o PATH. Os arquivos de configuração do usuário são lidos normalmente e não
são editados. A configuração do shell muda somente no processo da aba; o
launcher é materializado junto da CLI do app e não se registra como um Codex
instalado no PATH. Ambos os backends locais, sidecar e PTY in-process, usam
a mesma preparação. Hosts SSH/WSL não recebem caminhos ou configuração local.

O launcher busca o Codex real, ignora aliases que apontem para ele próprio e
usa exec para preservar PID, terminal, argumentos, sinais e status de saída.
Comandos não interativos, ajuda/versão, modo remoto explícito e a opção já
informada pelo usuário são repassados sem alteração. Fora das abas do
Cockpit, o comando Codex continua usando seu comportamento normal. Abas que
já estavam abertas antes dessa integração precisam ser reabertas uma vez.
