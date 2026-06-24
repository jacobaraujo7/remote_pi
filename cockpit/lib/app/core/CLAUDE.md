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
├── core_module.dart   # binds root-owned: PiSpawnConfig + Pairing/RevokeGatewayFactory
├── routes.dart        # RoutePaths (consts de path; evita string mágica)
├── env.dart           # PiSpawnConfig (resolve o binário pi + args)
├── app_intents.dart   # ponte global de atalhos (foco do composer)
├── domain/
│   ├── contracts/     # markers: Service/Disposable/UseCase; settings_store;
│   │                  #   pairing_gateway, revoke_gateway (+ factories)
│   ├── entities/      # app_settings (preferências); pair_event
│   ├── exceptions/    # relay_error
│   └── result.dart    # Result<T, E>
├── data/              # utils compartilhados: jsonl_line_splitter, remote_pi_resolver,
│   │                  #   hive_settings_store
│   └── relay/         # ephemeral_pi_rpc + pairing/revoke gateway impls
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
- **Exceção (DI)**: um bind de nível de feature (módulo com `path`) **não enxerga
  o core** na resolução do `auto_injector` — só o `provide` page-scoped e o próprio
  core enxergam. Logo um bind que resolve uma dep do core **pelo construtor** mora
  aqui (root-owned) mesmo que só uma feature o use. É o caso das
  `Pairing/RevokeGatewayFactory`: recebem `PiSpawnConfig` no construtor, então
  ficam no core junto do config, e o `ConnectivityViewModel` (settings, page-scoped)
  as injeta.
- Ex.: `SupervisorClientImpl` serve daemons **e** cron (mesma instância sob dois
  contratos) → fica em `settings/data` porque ambos são da feature *settings*; já
  o `SettingsController` (tema lido pelo shell **e** editado em settings) e o
  `PiSpawnConfig` (RPC do cockpit **e** pi efêmero do settings) são core.

## Tema

Toda cor/tipografia vem de `themes/` via `context.colors.<token>` /
`context.typo.<estilo>` (barrel `themes/themes.dart`). Nunca hardcode `Color(0x…)`
ou `TextStyle(fontFamily:…)` em widget.
