# Changelog — Remote Pi Cockpit

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).
As versões seguem o `version:` do `pubspec.yaml` (SSOT). O campo `notes` do
`latest.json` (VPS) deriva deste arquivo.

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
