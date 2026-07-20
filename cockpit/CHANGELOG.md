# Changelog — Remote Pi Cockpit

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).
As versões seguem o `version:` do `pubspec.yaml` (SSOT). O campo `notes` do
`latest.json` (VPS) deriva deste arquivo.

<!--
  ATENÇÃO: o CI publica as notas da release a partir da PRIMEIRA seção `## `
  deste arquivo, e só as 20 primeiras linhas não-vazias dela
  (`awk '/^## /{n++} n==1' | tail -n +2 | sed '/^$/d' | head -20` em
  .github/workflows/cockpit-release.yml). Então: a seção da versão que está
  saindo fica no TOPO, e cabe em 20 linhas — não deixe um `## [Unreleased]`
  vazio na frente (as notas sairiam vazias) nem escreva demais (sai cortado no
  meio da frase).
-->

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
