# Remote Pi — Cockpit (Flutter Desktop)

Cliente **desktop** (macOS first) do Remote Pi. GUI multi-pane sobre o motor do
Pi: projetos à esquerda, agentes no centro, árvore de arquivos à direita. Cada
agente é um `pi --mode rpc` que o app spawna e dirige **localmente** — sem relay,
sem pareamento, sem crypto. É a contraparte local do `app/` (que é o gateway
remoto). Plano de referência: [`../plan/37-desktop-cockpit.md`](../plan/37-desktop-cockpit.md).

## Escopo atual (MVP — provar o conceito)

Fase de validação: provar que o Flutter desktop aguenta o `--mode rpc` — spawn de
child process, streaming de stdout, `send` por stdin, kill limpo. **Layout básico
primeiro; panes (multiplexação) ainda NÃO** — decisão adiada (ver plano 37). Nada
de relay/mesh/crypto nesta fase.

Decisões fechadas (plano 37, 2026-06-05):

| # | Decisão |
|---|---|
| **A** | Código mora aqui em `cockpit/` (não dentro de `app/`). Reuso futuro com `app/` via `packages/pi_core` — **ainda não extraído** |
| **B** | Spawna `pi --mode rpc` **puro**, sem a extensão remote-pi. Local-only, sem relay |
| **C** | Spawn **próprio** — não reusa o supervisor do plano 26 (que é fire-and-forget sem streaming) |

## Stack

- Flutter desktop / Dart (mesma major do `app/`)
- Plataforma: **macOS first** (Windows/Linux possíveis via Flutter, não testados)
- DI + roteamento + estado: **`flutter_modular`** (v7). Cada feature é um módulo
  (`createModule`) que declara **suas próprias rotas + binds**; estado page-scoped
  via `provide`/`addChangeNotifier` (sobre `ChangeNotifier`), estado app-scoped
  (tema/fonte) via `ModularApp.provide`. Substituiu `provider` + `auto_injector` +
  `go_router`.
- Consumo de estado na UI: `context.watch/read/select`, `Consumer`/`Selector`
  (re-exportados pelo `flutter_modular` — API igual à do `provider`).
- Resultado tipado: `Result<T, E>`
- Subprocesso: `dart:io` `Process.start` (spawn do `pi --mode rpc`)
- Menu de app: abstração em `core/ui/menu/` — modelo declarativo único
  (`menu_model.dart`), renderizado nativo no macOS (`PlatformMenuBar`) e
  desenhado na barra de título no Windows/Linux (`Menubar` do shadcn, via
  `WindowMenuBar`). Fonte de verdade em `buildAppMenus()`

> **Diverge do `app/` de propósito**: o cockpit é organizado em **fatias verticais
> por feature** (`lib/app/<feature>/{domain,data,ui}`), não em camadas globais. A
> motivação foi matar os god classes `router.dart`/`dependencies.dart` e deixar
> cada feature auto-contida (cresce sem editar arquivos compartilhados). O `app/`
> (mobile) segue na arquitetura por camadas — não espelhe um no outro.

## Motores (onde mora cada engine)

Mapa dos motores que o Cockpit usa — quem é **nosso** (no repo, manutenção
nossa) e quem é pacote externo:

| Motor | Onde | Origem / nota |
|---|---|---|
| **Emulador de terminal** (VT/ANSI) | `libghostty` + `lib/app/core/terminal/xterm/` | Ghostty é o padrão de buffers novos; o xterm absorvido continua disponível e é usado por layouts legados |
| **Render do terminal** | `flterm` + `lib/app/core/terminal/cockpit_terminal*.dart` | `flterm` renderiza Ghostty; a view/painter interna permanece integral para xterm. Ver `core/terminal/CLAUDE.md` |
| **PTY** (spawn nativo de shell — forkpty/ConPTY) | `plugins/cockpit_pty/` | **Nosso** — plugin C/FFI absorvido do `kyroon_pty` v1.0.6, renomeado; não publicado |
| **Markdown** (GFM + code do agente/viewer) | pacote `gpt_markdown` ^1.1.8 (pub.dev) | Externo (upstream ativo). O **frontmatter** YAML é nosso: `core/ui/widgets/markdown_frontmatter.dart` (pré-processamento no `AgentMarkdown`) |
| **Syntax highlight** (léxico, ~190 linguagens) | pacote `highlight` ^0.7.0 + `core/ui/widgets/code_highlight.dart` (tema/integração) | Externo; decisão do plano LSP: highlight léxico mantido (LSP não colore) |
| **LSP** (diagnostics/formatação — a camada "IDE") | `lib/app/core/data/lsp/` (cliente JSON-RPC genérico + pool por (lang, raiz)) | **Nosso** — fala com servidores externos achados no PATH |
| **Agente** (`pi --mode rpc`) | `lib/app/cockpit/data/rpc/` (spawn/stream/kill) | Motor é o binário `pi`; nosso é o harness RPC. Protocolo em `docs/rpc-protocol.md` |
| **DB drivers** (SQLite/Postgres/MySQL/MSSQL/Mongo/Redis) | pacotes `anaki_*` (Rust/FFI, do Jacob) + `lib/app/cockpit/data/db/` (Isolate workers + serviços) | Externo-mas-nosso (mantido pelo Jacob fora do repo) |
| **Git** | `lib/app/cockpit/data/filesystem/git_*` (roda o binário `git`) | Motor é o git do sistema; nosso é o parser/orquestração |
| **Mídia** (áudio/vídeo no viewer) | pacote `media_kit` (libmpv) | Externo |
| **Self-update** | pacote `auto_updater` (Sparkle/WinSparkle) + `lib/app/cockpit/data/update/` | Externo + integração nossa (plano 47) |

Zero `dependency_overrides` git no pubspec (limpeza 2026-07-19): o que era fork
virou módulo/plugin interno; o resto vem do pub.dev.

## Comandos

- `flutter pub get` — instala deps
- `flutter analyze` — lint estático (deve passar zero issues)
- `flutter test` — testes
- `flutter run -d macos` — abre no desktop
- `dart format .` — formata
- `flutter build macos` — build verificável

## Arquitetura — fatias verticais por feature

Tudo vive sob `lib/app/`. Cada **feature** é um mini-app auto-contido com suas
próprias camadas `domain/ data/ ui/` e **um módulo** (`<feature>_module.dart`) que
declara as rotas e os binds daquela feature. O `app/core/` guarda só o que é
transversal (usado por 2+ features). **Leia [`lib/app/CLAUDE.md`](lib/app/CLAUDE.md)
(convenções de feature/módulo) e [`lib/app/core/CLAUDE.md`](lib/app/core/CLAUDE.md)
(o que é kernel) antes de editar.**

```
lib/
├── main.dart                 # bootstrap async (Hive/boxes/config/notifier) + runApp(ModularApp)
└── app/
    ├── app_module.dart       # raiz: compõe core + features (só composição)
    ├── app_widget.dart       # AppRoot: ShadcnApp.router + watch<SettingsController>
    ├── core/                 # kernel transversal (módulo SEM path → binds root-owned)
    │   ├── core_module.dart  # binds compartilhados (PiSpawnConfig)
    │   ├── routes.dart  env.dart  app_intents.dart
    │   ├── domain/  data/    # markers (Service/Disposable), Result, contratos/impls compartilhados
    │   └── ui/               # themes/  widgets/  file_icons/  settings_controller.dart (app-scoped)
    ├── cockpit/              # FEATURE: o shell (projetos | panes/agentes/terminal | arquivos)
    │   ├── cockpit_module.dart   # path '/', binds + route('/', provide: Cockpit/Setup/Update VMs)
    │   └── domain/  data/  ui/   # ui/ = cockpit_page + viewmodels/ session/ states/ widgets/
    └── settings/             # FEATURE: conectividade + daemon agents + agendamentos (cron)
        ├── settings_module.dart  # path '/settings', binds + route('/', provide: Connectivity/Daemons/Cron VMs)
        └── domain/  data/  ui/
```

Fluxo de dependência **dentro de cada feature** (e do core):

```
ui ──► domain ◄── data
        ▲
   <feature>_module.dart   (compõe: registra binds + declara rota + provê ViewModels)
```

- `domain/` (de cada feature e do core) **não** importa `data/`, `ui/` nem módulos.
- `data/` implementa contratos de `domain/`, nunca importa de `ui/`.
- `ui/` consome `domain/` via ViewModels page-scoped — nunca chama `data/` direto.
- `<feature>_module.dart` é o único lugar que conhece as 3 camadas da feature.
- Uma feature **pode importar de `core/`, nunca de outra feature**; o `core/` não
  importa de feature nenhuma. (Ex.: o `SupervisorClientImpl`, que serve daemons **e**
  cron, e o `SettingsController` global moram onde são compartilhados, não numa aba.)

## Convenções

- **Naming**: arquivos `snake_case.dart`, classes `PascalCase`, widgets `PascalCase`
- **Imports**: relativos dentro do mesmo feature; absolutos via `package:cockpit/...`
  quando cruzando features ou camadas
- **Barrel files**: cada feature/módulo pode expor um `<nome>.dart` agregando os
  símbolos públicos; consumidores externos importam só o barrel
- **Async**: prefira `Future`/`Stream` tipados, evite `dynamic` (o stream de
  eventos RPC é tipado em `domain/`, nunca `Map<String, dynamic>` cru na `ui/`)
- **Erros**: `Result<T, E>` ou exceptions tipadas; nunca `catch (e)` genérico em produção
- **Scroll = CLAMP**: todo scroll do app usa `ClampingScrollPhysics` (nada de
  bounce/overscroll estranho). Isso já é global via `ClampingScrollBehavior`
  (`core/ui/clamping_scroll_behavior.dart`), ligado no `ShadcnApp.router(scrollBehavior:)`
  — qualquer `ListView`/`SingleChildScrollView`/`Scrollable` novo **herda** e não
  precisa setar `physics:`. **Nunca** use `BouncingScrollPhysics` (default do shadcn);
  se precisar customizar um scrollable, mantenha a física clamp (ou omita `physics:`
  pra herdar). `ScrollConfiguration.of(context).copyWith(...)` preserva o clamp.
- **ViewModels**: `ChangeNotifier` page-scoped, providos no `provide:` da rota
  (`s.addChangeNotifier<T>(…)`) **dentro do `<feature>_module.dart`**; páginas nunca
  instanciam ViewModel — sempre `context.watch/read/select`. Nascem ao montar a
  rota e são `dispose()`-ados ao sair. Estado app-global (tema/fonte =
  `SettingsController`) vive em `ModularApp.provide`, acima do `ShadcnApp`.
- **Injeção via `.new`** (regra): registre binds e ViewModels com o **tear-off do
  construtor** (`addChangeNotifier<Foo>(Foo.new)`, `addLazySingleton<Bar>(Bar.new)`)
  e deixe o `auto_injector` resolver os parâmetros pelo grafo. **Não** escreva
  `() => Foo(inject<A>(), inject<B>())` quando `Foo.new` resolve. Pós-construção
  (`init()`/`check()`) roda no `initState` da página, não encadeada no factory.
  Dois casos exigem um **tipo nomeado** para seguir `.new` (o parser de parâmetros
  do `auto_injector` é regex sobre o `toString` do construtor):
  - **dependência factory** ("crie um X novo a cada uso"): use uma **interface de
    factory** (`abstract class XFactory { X create(); }`, impl no `data/`), **não**
    `X Function()` — o parser quebra no `=>` e funde dois params factory seguidos.
    Ver `PairingGatewayFactory` + `ConnectivityViewModel`.
  - **vários primitivos ambíguos** (vários `String`): troque por um **value object
    injetável** (ex.: `UpdateTarget` no `cockpit_module`).
- **Tema**: nunca hardcode `Color(0x…)` / `TextStyle(fontFamily:…)`; leia via
  `context.colors.<token>` / `context.typo.<estilo>` (barrel `app/core/ui/themes`)

## Regra crítica: `BuildContext` em código assíncrono

Acessar `context` após um `await` (ou dentro de `.then/.onSuccess/.flatMap/.whenComplete`)
pode crashar com `Null check operator used on a null value` se o widget já tiver
sido desmontado. O lint `use_build_context_synchronously` **não detecta** callbacks
encadeados — a prevenção é manual.

```dart
// CORRETO — await + guard
final result = await viewModel.spawnAgent();
if (!mounted) return;           // em StatefulWidget
// if (!context.mounted) return; // em StatelessWidget
context.useContextSomehow();
```

```dart
// ERRADO — context dentro de callback assíncrono
await viewModel.spawnAgent().onSuccess((_) {
  context.useContextSomehow(); // CRASH se desmontado
});
```

> Nunca use `context` dentro de `.onSuccess()`, `.onFailure()`, `.flatMap()`,
> `.then()` ou `.whenComplete()`. Sempre transforme para `await` + guard.

## NÃO fazer

- Editar arquivos fora de `cockpit/`
- Adicionar **relay, mesh, crypto ou pareamento** nesta fase — Cockpit é
  local-only (decisão B). Reachability remota é evolução futura (plano 37)
- Criar **panes/multiplexação** antes de revalidar o conceito com layout básico
  (plano 37 — panes deliberadamente adiados)
- Reusar o supervisor do plano 26 (decisão C — spawn próprio)
- Implementar crypto manual (não há crypto nesta fase)
- Comitar `build/`, `.dart_tool/`, `macos/Pods/`
- Adicionar dependência sem registrar no plano 37
- Misturar responsabilidades entre camadas/features — quando bater dúvida, leia
  [`lib/app/CLAUDE.md`](lib/app/CLAUDE.md) e o `domain/data/ui` da feature alvo
- Importar de uma feature para outra, ou do `core/` para uma feature — só
  feature→core é permitido (ver fluxo de dependência acima)
- Recriar god classes: **não** centralize rotas ou binds num arquivo só — cada
  feature declara os seus no próprio `<feature>_module.dart`

## Modo orquestrado

Se receber um prompt começando com `[ORCH:<task-id>]`, leia
[`../.orchestration/INSTRUCTIONS.md`](../.orchestration/INSTRUCTIONS.md) antes de
qualquer outra ação. Esse marker indica que outro agente está coordenando o
trabalho e tem regras específicas (onde escrever resultado, não comitar, etc).
