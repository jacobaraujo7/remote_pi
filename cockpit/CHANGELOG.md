# Changelog — Remote Pi Cockpit

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).
As versões seguem o `version:` do `pubspec.yaml` (SSOT). O campo `notes` do
`latest.json` (VPS) deriva deste arquivo.

<!--
  ATENÇÃO: a PRIMEIRA seção `## ` deste arquivo é o texto que o usuário vê no
  diálogo de update (Sparkle/WinSparkle) e na página de download. Regras:

  - **Seções novas em INGLÊS** (a partir da 1.20.0). É texto user-facing, então
    vale a mesma regra da UI do app. As seções antigas ficam em português —
    são o que já foi publicado, não reescreva.

  - A seção da versão que está saindo fica no TOPO. O job `meta` do
    .github/workflows/cockpit-release.yml **falha a release** se a versão do
    primeiro `## ` não bater com a tag — foi assim que 1.16/1.17/1.18 saíram
    repetindo a nota da 1.15.4.
  - Nada de `## [Unreleased]` na frente: o guard reprova.
  - Markdown normal (parágrafo, `### Fixed`, lista, `**negrito**`, `código`) —
    o CI converte pra HTML (cockpit/packaging/release_notes_html.py) antes de
    pôr no appcast, então quebra de linha e formatação aparecem certinho.
  - O `notes` do latest.json (página de download) ainda usa só as 20 primeiras
    linhas não-vazias — o começo da seção deve fazer sentido sozinho.
-->

## [1.26.0] - 2026-08-11

Codex tabs now report what they are doing, just like Claude Code tabs.

### Added

- **Turn status for the Codex CLI.** A tab running `codex` now shows the
  spinner while it works, raises the attention badge when it asks for approval,
  and plays the completion sound when the turn ends — the same treatment Claude
  Code tabs already had. Notifications when the window is in the background work
  too.
- Cockpit sets this up on its own at startup, including Codex's hook trust, so
  there is nothing to enable or approve by hand. Your own Codex hooks are left
  untouched, and the rest of `config.toml` is never rewritten. Requires Codex
  CLI 0.147 or newer; if Codex isn't installed, nothing is created.
- **Restoring a tab reattaches the right session.** Cockpit now remembers which
  agent a conversation belongs to, so a restored tab resumes with `codex resume`
  or `claude --resume` accordingly.

## [1.25.1] - 2026-08-11

A smoother terminal under heavy output, and realm switching that remembers where you were.

### Fixed

- The window no longer freezes when a command floods the terminal with output.
  PTY output now shares a frame-time budget across every terminal, and hidden
  terminals stop painting entirely instead of competing for the frame. Thanks,
  @pretodev.
- Switching realms (keyboard shortcut or the realm picker) now brings you back to the
  worktree you were working in, not to its main workspace. If that worktree is
  gone, focus falls back to the workspace it belonged to.
- The tab bar scrolls horizontally with the mouse wheel again when there are
  more tabs than fit the panel. Thanks, @pretodev.

## [1.25.0] - 2026-08-09

Sounds you can tell apart, worktrees you can configure, and one less crash.

### Added

- **A sound per event.** Turn completed, action required and agent error each
  get their own sound, with a volume control, a preview button, and the option
  to play even when the tab is already active. Any of them can be swapped for
  an audio file of your own, or reset back to the default.
- **Advanced settings when creating a worktree** (thanks, @pretodev). A
  collapsed section adds: pick the **base branch** instead of always branching
  from the current HEAD, **fetch the remote** first so that base is up to date,
  and copy **ignored** (`.env`, local keys) or **untracked** files into the new
  worktree.
- **Flexoki theme** (thanks, @pretodev), the first built-in that brings its own
  syntax palette rather than reusing GitHub's.

### Fixed

- **Closing the selected workspace could take the app down with it** (thanks,
  @jamesldr). The terminal was freed while its view was still on screen, and
  the next frame touched memory that was already gone. Being a native crash, it
  left nothing behind in the logs. Teardown now waits for the views to leave
  before releasing anything.

## [1.24.0] - 2026-08-07

Git history, a real font picker, and clickable paths that actually click.

### Added

- **Git history panel.** Browse the repository's commits, see which files each
  one touched, and open the change in the editor from there (thanks,
  @HumbertoChiesi).
- **Font picker.** Pick interface, code and terminal fonts from the families
  installed on the machine, each name drawn in its own font, with search. Typing
  an exact family name by hand still works.
- **Terminal size and weight of their own.** The terminal no longer has to
  follow the code size, and the stroke weight is now a setting. Auto lightens it
  on low-density screens, where the same font renders heavier, and leaves Retina
  untouched.
- **Copy branch** in the workspace menu. In a multi-repo workspace it opens a
  submenu with one entry per root, like Pull and Push.

### Fixed

- **Clicking a relative file path in the terminal did nothing.** Absolute paths
  opened, so the failure was easy to miss, but `lib/foo.dart:12:3` is exactly
  what `dart analyze` and `flutter test` print. Paths are now resolved against
  the tab's directory. The same click now works in a task's output pane, which
  had no handler at all.

## [1.23.0] - 2026-08-06

Themes: eight of them, and any JSON file can become one.

### Added

- **Themes.** One choice now paints the whole app: interface, code highlighting
  and terminal palette together. Eight come built in, from the official
  **Cockpit** to **Pantera** (pure black in dark, pure white in light), each
  with a light and a dark variant picked by the new **Mode** setting.
- **Import and export themes**, in Settings, Appearance. A theme is a single
  JSON file you can share, version or edit by hand: declare only the tokens you
  want to change and the rest is inherited. Format in `docs/theme-format.md`.
- **Live preview** of how code and terminal will look, in the Appearance tab.
- **Middle-click a tab to close it** (thanks, @thKali).

### Fixed

- **"Cockpit closed unexpectedly" on every launch (Windows).** Closing through
  the title bar X destroyed the window without Cockpit noticing, so the next
  launch always assumed a crash, and dismissing the notice did not help because
  the notice is not what clears it. Cockpit now handles the closing itself.
- **Code and terminal share the tab's background**, instead of two neighbouring
  tabs showing two different shades of black with a seam between them.
- Text over the accent color is picked by measuring contrast instead of
  assuming white, so a light accent no longer gets unreadable labels.
- Closing a workspace no longer floods the console (thanks, @thKali).

## [1.22.0] - 2026-08-05

A focus overhaul for the terminal, plus a rescue for workspaces whose folder is
gone.

### Fixed

- **The terminal would stop taking the keyboard mid-session.** Typing went
  nowhere, the cursor stopped blinking, and the only way back was clicking the
  tab header. Two separate gaps caused it: clicking inside a terminal that had
  lost focus could not restore it, and switching realm or workspace left the
  keyboard behind on the previous pane while the new tab already looked
  selected. Both paths now hand the keyboard over.
- **Deleting a workspace folder no longer bricks the app.** Cockpit used to
  hang on the loading screen forever, with nothing on screen to explain it,
  because restoring a terminal in a folder that no longer exists failed the
  whole boot. Now the terminal opens in the nearest folder that does exist and
  says so, and a workspace that fails to restore no longer stops the rest.
- Images in the viewer kept showing the previous version after the file changed
  on disk, even after closing and reopening the tab.
- Duplicate scrollbars in the code editor. Thanks, @pretodev.

### Added

- **Creating a worktree now shows git's output live**, including anything your
  post-checkout hook prints, instead of freezing the dialog until it finishes.
  The dialog also warns beforehand when the repository has such a hook. Thanks,
  @pretodev.

## [1.21.0] - 2026-08-05

Cockpit now speaks your language, and can write your commit messages for you.

### Added

- **Interface in English, Português (BR) and Español.** Cockpit follows your
  system language on first launch and falls back to English when the system
  language isn't supported. You can pin one in **Settings → General →
  Language**; the whole window, including the menu bar, switches immediately.
  Thanks, @tecrodrigocastro.
- **Commit messages written by a coding agent.** Pick a CLI you already have
  installed in **Settings → Automations** (Pi, Claude Code, Codex CLI, Gemini
  CLI, OpenCode or Copilot CLI), optionally pick a model, and a **Generate**
  button shows up in Source Control and in the per-file commit dialog. Only the
  diff you're committing and your recent commit subjects are sent, common
  credential patterns and sensitive files are stripped first, and nothing is
  committed until you review the message. Thanks, @pretodev.
- The Source Control list/tree toggle now sticks across sessions and
  workspaces.

### Fixed

- The window no longer freezes when a terminal produces a burst of output, such
  as a busy TUI redrawing. Thanks, @pretodev.
- Language servers that failed to start are no longer left running in the
  background.
- Choosing a workspace photo now opens the file picker in the workspace folder.

## [1.20.0] - 2026-08-04

The internal CLI was rewritten in Rust. It now works on Intel Macs, can be
called from outside the app, and can submit what it types.

### Added
- **`cockpit send --enter`**: types the text and presses Enter in one call,
  instead of always pairing `send` with `send-key Enter`.
- **`cockpit send --focused`**: targets the tab you are looking at, so external
  tools (a dictation app, a script) no longer need a tab id to type into.
- **The CLI works from outside a Cockpit terminal.** With no environment
  inherited it finds the running app by itself, and `list-tabs` now marks which
  tab is focused.

### Fixed
- **Intel Macs had no internal CLI and no Claude turn status.** The app itself
  was universal, but its two helper binaries were Apple Silicon only, so the
  `cockpit` command and the spinner/chime silently did nothing there.

### Changed
- The `cockpit-hook` helper is now `cockpit hook`, a subcommand of the CLI. One
  binary instead of two: the app is about 11 MB lighter, and the hook that runs
  on every Claude event starts in milliseconds.

## [1.19.0] — 2026-08-02

Precisão do mouse: menus, foco de pane e seleção de texto voltam a cair onde
você clica. E a nota que aparece no update finalmente é legível.

### Added
- **Frequência da verificação de update** em Configurações → Updates: diária,
  semanal, mensal ou nunca (obrigado, @OrlandoEduardo101).

### Fixed
- **Menus e dropdowns abriam fora do lugar** com "Interface size" diferente de
  14 — menu de contexto da aba, opções do workspace e as listas das
  Configurações. O erro crescia conforme a distância do canto da janela.
- **Clicar dentro do terminal não ativava o pane:** com vários agentes lado a
  lado, o clique era engolido e o que você digitava saía na aba anterior — às
  vezes só clicando na aba resolvia.
- **Seleção de texto escorregava depois de rolar** no markdown, no viewer de
  código e no diff: quanto mais rolado, mais a seleção saía abaixo do cursor.
- **Notas de update repetidas e ilegíveis:** o diálogo de atualização mostrava
  o texto de uma versão antiga, com o markdown cru e tudo numa linha só.
- Erro ao abrir as Configurações e falha de injeção na tela de update.

## [1.15.4] — 2026-07-28

Conexão de banco por túnel SSH: o Mongo em Atlas finalmente funciona.

### Fixed
- **Túnel SSH pendurava o primeiro comando pra sempre:** o registro de abertura
  em voo era limpo com `whenComplete(() => map.remove(key))` e o future passava
  a esperar por si mesmo — só o primeiro chamador travava, o que aparecia como
  "o painel carrega pra sempre mas a CLI responde".
- **Proxy SOCKS do túnel morria em silêncio** a cada teardown de pool do driver
  Mongo; agora é nosso, sobrevive a reset e o cache reabre quando ele cai.
- **Comando Mongo custava ~7s:** `anaki_mongodb` 0.1.7 devolve o `close()` na
  hora (era 5s, e 59s antes disso em `mongodb+srv://`).

### Added
- **Mongo escolhe o database:** URL de Atlas não traz database e o painel caía
  no `admin`, mostrando `system.*`. A conexão agora expande nos databases.
- **`cockpit mongo --database <nome>`:** o agente escolhe a base sem mexer no
  que o humano vê; sem database resolvível, erro listando as disponíveis.
- **"Copy name"** no menu da conexão (o nome que a CLI usa em `--db`).

## [1.14.6] — 2026-07-20

Correção de digitação de acentos no terminal.

### Fixed
- **Caracteres acentuados duplicados no terminal** (@pretodev, #66): o IME
  podia reenviar o mesmo caractere já commitado (dead keys como `´` + vogal),
  e cada reenvio ia pro PTY — `á` virava `ááá`. Agora cada commit é emitido
  uma única vez.
- **Build Linux com Clang novo:** warning legado do
  `flutter_secure_storage_linux` (nlohmann/json antigo) não derruba mais o
  build com `-Werror`.

## [1.14.5] — 2026-07-20

Drivers de DB com TLS de verdade (anakiORM atualizado) e tela de loading
no boot.

### Added
- **Tela de loading no boot** (@jamesldr, #65): a janela abre na hora com
  splash animado no tema salvo enquanto o setup roda atrás; falha no boot
  mostra tela de erro com Retry em vez de fechar sem feedback.

### Fixed
- **TLS nos drivers:** anaki_postgres 0.1.4 / anaki_mysql 0.1.5 compilados
  com rustls — `sslmode=require` funciona (antes: "SQLx was built without
  TLS support"). MySQL repassa `ssl-mode`, MSSQL repassa `encrypt`.
- **FFI:** fix de colisão de símbolos quando vários drivers anaki carregam
  no mesmo processo (sqlite/mssql/redis/mongodb 0.1.4).
- **New query:** o SELECT gerado pela árvore cita o nome da tabela na
  sintaxe do engine (`"Tabela"`, backtick, `[colchete]`) — tabela CamelCase
  no Postgres quebrava sem aspas.

## [1.14.3] — 2026-07-20

Switch de SSL/TLS no dialog de conexão do Database.

### Added
- **Use SSL/TLS:** switch no dialog de conexão grava a forma certa por
  engine (Postgres `sslmode=require`, MySQL `ssl-mode=REQUIRED`, MSSQL
  `encrypt=true`, Mongo `tls=true`, Redis `rediss://`); OFF remove a chave
  preservando os demais query params. SRV (Atlas) implica TLS (switch
  travado). Necessário pra bancos gerenciados (RDS `rds.force_ssl` etc).

## [1.14.2] — 2026-07-20

Fix no parse de URL do Database.

### Fixed
- **Senha crua na URL:** conexão com senha sem percent-encoding
  (`user:8nJM9g8%?FC(@host`) falhava no parse e sumia da lista; agora o
  userinfo é re-encodado automaticamente ao carregar.

## [1.14.1] — 2026-07-20

Fixes no painel Database (Mongo Atlas).

### Fixed
- **Mongo Atlas (`mongodb+srv://`):** URLs SRV agora são reconhecidas; antes
  a entrada era tratada como engine desconhecido.
- **Painel Database:** uma conexão inválida no `databases.json` zerava a
  lista inteira; agora só a entrada com problema é pulada.
- **Editar conexão Atlas:** o dialog preserva o formato SRV e os query
  params da URL (antes reescrevia pra `mongodb://host:porta` e quebrava a
  conexão).

## [1.14.0] — 2026-07-20

Motores internalizados (terminal, PTY, frontmatter), CLI cria abas de
terminal e melhorias de multirepo/UI.

### Added
- **CLI `cockpit new-tab`:** agentes abrem abas de terminal (cwd, título,
  split) de dentro dos panes.
- **Multirepo:** Files volta à árvore única com seções por repo + popup de
  branches no badge da rail.
- **Guardrails de DB:** cada conexão define acesso read/readwrite e se fica
  visível pros agentes na CLI (default: só leitura).

### Changed
- **Motores absorvidos pro repo:** emulador de terminal (xterm) virou módulo
  interno; PTY nativo virou o plugin `cockpit_pty`; frontmatter YAML do
  markdown agora é pré-processamento próprio. Zero forks git no pubspec —
  markdown vem do pub.dev 1.1.8 (fix de links consecutivos incluso).

### Fixed
- Source Control mostrava pasta nova como arquivo; play/stop de Tasks sem
  resposta imediata; submenu e tooltips desalinhados sob zoom da interface;
  atalho ⌘`/⌘⇧` de realm parava após o primeiro uso.

## [1.13.0] — 2026-07-19

Novo: browsers visuais de Redis e MongoDB na tab Database — tabela de chaves
editável e collection browser estilo Compass, com abertura via CLI.

### Added
- **Redis key table:** clique na conexão abre a tabela key/value/type/ttl —
  edição inline (valor, TTL e rename de chave), compostos expandem com o valor
  completo, criação dos 5 tipos, SCAN paginado com busca por pattern.
- **Mongo collection browser:** collections no painel; documentos como cards
  JSON com highlight, filter bar JSON, editar/inserir/deletar por `_id`.
  Extended JSON (`$oid`/`$date`) preservado de ponta a ponta.
- **CLI `cockpit redis|mongo browse`:** o agente abre a view já filtrada pro
  humano (`--pattern` / `--filter`), sem expor credenciais.
- Logos de marca (Redis/MongoDB) nas abas dos browsers.

### Fixed
- `cockpit mongo` agora devolve ObjectId/Date como extended JSON canônico
  (antes saía hex/string ambíguos).

## [1.12.0] — 2026-07-19

Novo: acesso a bancos de dados direto no Cockpit — painel de conexões, tab de
query `.dbq` e a CLI `cockpit db` para os agentes.

### Added
- **Painel Database:** conexões por workspace (`.cockpit/databases.json`),
  SQLite detectado automaticamente, senha no cofre do SO. Árvore de schema
  (tabelas → colunas) e logos de marca por engine.
- **Tab de query `.dbq`:** editor SQL com highlight + grid de resultado (split
  arrastável), Run por statement sob o cursor, resultado como tabela ou JSON
  (copiável), buffers *untitled* (o arquivo nasce só ao salvar).
- **Engines:** SQLite, Postgres, MySQL e SQL Server (via anakiORM).
- **CLI `cockpit db list|schema|query|execute|run`** — JSON de uma linha para
  os agentes; execução no app, credenciais nunca passam pela CLI.
- **Redis e MongoDB via CLI** (`cockpit redis` / `cockpit mongo`) — acesso do
  agente sem UI por enquanto.

## [1.11.0] — 2026-07-18

Melhorias na árvore de Files (criação e reveal), no multi-root e na CLI interna.

### Added
- **New file/folder ciente da seleção:** cria dentro da pasta selecionada, na
  pasta-mãe do arquivo selecionado, ou na raiz quando nada está selecionado.
  Clicar numa área vazia da árvore deseleciona.
- **Revelar na árvore:** selecionar uma tab de arquivo destaca o arquivo no
  painel Files e expande as pastas-pai até ele.
- **Copy Absolute/Relative Path** no menu de contexto de cada repo (multi-root).

### Changed
- **CLI interna (`cockpit`):** nomenclatura alinhada pra *tab* — `list-tabs`,
  `read-tab`, `$COCKPIT_TAB_ID`. Os antigos `list-panes`/`read-pane`/
  `$COCKPIT_PANE_ID` seguem como aliases de compatibilidade.

### Fixed
- **Multi-root:** New file/New folder agora funcionam por repo (antes o botão do
  header não criava nada num workspace multirepo).
- **Multi-root:** o chip “N roots · M” contava divergência de upstream como se
  fosse alteração; agora conta só arquivos modificados.

## [1.10.1] — 2026-07-18

### Fixed
- **Commit falhava em repositórios com hook de `pre-commit`** que chama
  `npx`/`node` (ex.: `lint-staged`, `husky`, `simple-git-hooks`): o app roda com
  um PATH mínimo e o hook não achava o `npx` ("command not found"). O Source
  Control agora passa o mesmo PATH com `node` do terminal/tasks — o hook resolve.

## [1.10.0] — 2026-07-17

Workspaces multi-root pra quem trabalha com multirepo, mais git no Source
Control e novas ações de worktree.

### Added
- **Workspace multi-root:** pasta sem `.git` com repositórios dentro vira um
  workspace só — cada repo é uma root na árvore, com branch e status próprios;
  Sync/Pull/Push/worktree escolhem a root num submenu.
- **Source Control:** botão-direito no arquivo — View Diff, Commit (com dialog
  de mensagem validado), Unstage ou Discard; deletados aparecem riscados.
- **Worktrees:** "Update from Parent" (traz a branch do pai) e "Fork Worktree"
  (nova worktree a partir da branch do fork).

### Fixed
- Tooltips e menus de contexto abrindo fora do lugar (agora seguem o cursor e
  respeitam o tamanho da interface).

## [1.9.0] — 2026-07-17

Atalhos de teclado pra navegar o workspace, além de vários acertos no terminal,
nas Tasks e no visualizador de arquivos.

### Added
- **Selecionar aba por teclado:** ⌘1…⌘8 vão pra aba N da pane focada e ⌘9 pula
  pra última (View → Select Tab).
- **Navegar entre panes:** ⌘⌥ + setas move o foco pra pane vizinha na direção
  (View → Focus Pane).

### Changed
- **Visualizador de arquivos:** os botões Format/Discard/Save saíram da barra
  inferior — as ações seguem no menu File (e nos atalhos ⌘S / ⇧⌘F).
- **Worktrees** passam a morar em `.cockpit/worktrees` (antes `.pi/`), com
  `.cockpit/worktrees/` garantido no `.gitignore` do repo.

### Fixed
- **Spinner preso ao interromper o agente:** apertar ESC pra parar o harness
  agora apaga o indicador de "trabalhando" na hora.
- **Tasks:** o debug tab escreve "finished" ao encerrar, sinalizando o fim.

## [1.8.5] — 2026-07-16

Correções de Windows: o updater não reoferece mais a mesma versão, e o
PowerShell 7 aparece na lista de terminais.

### Fixed
- **Updater reoferecia a mesma versão pra sempre.** O VERSIONINFO levava o build
  number (`1.8.4+21`) e o appcast anuncia a versão marketing (`1.8.4`); o
  WinSparkle lê o `+` como texto e trata `1.8.4+21` como um pré-lançamento de
  `1.8.4`. Agora o VERSIONINFO publica só `x.y.z`.
- **PowerShell 7 não aparecia** no seletor do `+` nem nas Configurações: era
  tratado como substituto do `powershell.exe`, o alias MSIX escapava da detecção
  e o PTY duplicava o executável na linha de comando. "PowerShell 7" e "Windows
  PowerShell" agora são perfis separados.
- **Arrastar a janela pela barra de título com o dedo** não movia nada em telas
  de toque.
- Espaçamento do menu hambúrguer no Windows.

### Known issues
- **Teclado virtual não abre ao tocar** num campo. Não é do app: o Windows
  recusa exibi-lo mesmo pedido via COM, e nem o Notepad o levanta nesta
  configuração — ligue em *Configurações › Hora e idioma › Digitação › Teclado
  de toque*.

## [1.8.4] — 2026-07-16

### Added
- **Seletor de terminal (plano 50):** seta ao lado do `+` para escolher qual
  shell abrir, e Configurações › Terminal para definir o padrão (só Windows, onde
  há escolha real). Descoberta de PowerShell/cmd/distros WSL.
- Barra de menu do Windows/Linux recolhida num **menu hambúrguer**.

### Fixed
- **Self-update do Windows travado:** o WinSparkle não baixa sozinho nem avisa
  que baixou, então o card ficava eternamente em "Downloading v…" e o clique era
  no-op. O card agora vai direto para "click to install".
- **IME/acentuação no terminal do Windows:** o fork do xterm não passava o
  `viewId` no `TextInputConfiguration`, o `TextInput.setClient` era rejeitado e a
  digitação morria — o contorno era desligar o IME e ler teclas cruas.

## [1.8.3] — 2026-07-04

### Added
- **Self-update (plano 47):** Cockpit agora se atualiza sozinho no macOS e no
  Windows via Sparkle/WinSparkle (pacote `auto_updater`): checa e baixa em
  background, mostra "restart to install" no card do rail e troca o binário ao
  reiniciar. **Linux** segue no aviso + download manual (`latest.json`). O CI
  passa a publicar `appcast-macos.xml` e `appcast-windows.xml` (assinados EdDSA)
  ao lado do `latest.json`.

## [1.1.0] — 2026-06-12

### Changed
- Interface fully translated to **English** (all on-screen text, tooltips,
  dialogs, notifications and error messages). The machine name in the rail now
  shows the real hostname.

## [1.0.0] — 2026-06-12

Primeira release distribuível do Cockpit (cliente desktop do Remote Pi).

### Adicionado
- Identidade de release: app ID `work.jacobmoura.cockpit`, nome de exibição
  **Remote Pi Cockpit** nas três plataformas.
- macOS: Hardened Runtime no Release; build assinado com Developer ID +
  notarização + staple (DMG universal x86_64+arm64).
- Linux: integração de desktop (`.desktop`, ícones hicolor, AppStream
  `metainfo.xml`) e controles de janela na barra customizada.
- Windows: metadados do executável (CompanyName/ProductName) e controles de
  janela na barra customizada.
- Empacotamento via Fastforge: `distribute_options.yaml` + `make_config.yaml`
  de dmg/exe/deb/rpm.

### Funcionalidades do app (MVP)
- Multiplexador de panes por workspace: agentes (`pi --mode rpc`) e terminais
  lado a lado, com splits e abas.
- Árvore de arquivos com menu de contexto (criar agente/terminal numa pasta).
- Worktrees por workspace (clona a estrutura de panes pro fork).
- Onboarding que checa/instala `pi`, extensão `remote-pi` e supervisor.
- Agendamento de daemons e conectividade (pareamento via relay).
