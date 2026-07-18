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
