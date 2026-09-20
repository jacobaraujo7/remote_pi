# `lib/app/core/` — kernel transversal

O que é **compartilhado por 2+ features** ou é app-global. Não é uma feature: o
`core_module.dart` é um `createModule` **sem `path`** → seus binds são root-owned
(vivem o app inteiro, nunca descartados).

> **Regra de ouro**: o `core/` **não importa de feature nenhuma**. Features
> importam do `core/`, nunca o contrário. Se algo no core precisar de uma feature,
> ele não é core — mora na feature.

## O que mora aqui

```
core/
├── core_module.dart   # binds root-owned: LSP pool, automação, perfis de terminal, permissões
├── routes.dart        # RoutePaths (consts de path; evita string mágica)
├── app_intents.dart   # pontes globais do menu nativo (settings, abrir projeto, updates)
├── domain/
│   ├── contracts/     # markers: Service/Disposable/UseCase; settings_store;
│   │                  #   lsp_client, neovim_gateway, system_permissions
│   ├── entities/      # app_settings (preferências), sound_event, terminal_profile
│   ├── exceptions/    # automation_error, file_operation_error, lsp_error
│   └── result.dart    # Result<T, E>
├── data/              # lsp/, automation/, neovim/, terminal/, repositories/ (stores
│                      #   JSON), setup/ (storage_location, permissões, sons)
└── ui/
    ├── settings_controller.dart  # APP-SCOPED (tema/fonte) — construído no main,
    │                             #   provido em ModularApp.provide (não em rota)
    ├── themes/        # tema dark; context.colors / context.typo / syntax
    ├── widgets/       # widgets reutilizados por +1 feature (hover_tap, app_menu,
    │                  #   code_highlight, window_controls)
    └── file_icons/    # mapa de ícone por tipo de arquivo
```

## Critério: core vs feature

- Usado por **só uma** feature → vai para a feature (`app/<feature>/...`).
- Usado por **duas ou mais** (ou é app-global) → core.
- Ex.: o `SettingsController` (tema lido pelo shell **e** editado em settings) e
  o `LspServerPool` (global, compartilhado por todos os workspaces) são core.

## Tema

Toda cor/tipografia vem de `themes/` via `context.colors.<token>` /
`context.typo.<estilo>` (barrel `themes/themes.dart`). Nunca hardcode `Color(0x…)`
ou `TextStyle(fontFamily:…)` em widget.
