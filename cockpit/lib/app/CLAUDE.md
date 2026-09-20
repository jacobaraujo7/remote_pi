# `lib/app/` — features verticais + módulos

Tudo do cockpit mora aqui. Cada **feature** é um mini-app auto-contido; o
`core/` é o kernel transversal (ver [`core/CLAUDE.md`](core/CLAUDE.md)).

## Anatomia de uma feature

```
app/<feature>/
├── <feature>_module.dart   # rotas + binds da feature (createModule)
├── domain/                 # contratos (interfaces) + entities da feature
├── data/                   # implementações dos contratos (IO, processos, repos)
└── ui/
    ├── <feature>_page.dart # entry widget da rota
    ├── viewmodels/         # ChangeNotifiers page-scoped
    ├── widgets/            # widgets locais (barrel widgets.dart opcional)
    └── states/  session/   # estruturas de estado próprias da feature (quando houver)
```

Regra de dependência (vale por feature):
`ui ──► domain ◄── data`, com `<feature>_module.dart` compondo as três.

- `domain/` não importa `data/`, `ui/` nem módulos. Só Dart + `core/domain`.
- `data/` implementa `domain/`, nunca importa `ui/`.
- `ui/` consome `domain/` via ViewModels — **nunca** chama `data/` direto.
- Uma feature pode importar de `core/`; **nunca** de outra feature.

## O módulo da feature (`<feature>_module.dart`)

É o coração: substitui os antigos god classes `dependencies.dart` (DI) e
`router.dart` (rotas). Padrão (`flutter_modular` v7):

```dart
Module buildFooModule(/* deps async resolvidas no main */) => createModule(
  path: '/foo',                         // feature → rotas flattenadas sob /foo;
  register: (c) {                       //   sem path = só DI (caso do core)
    c
      // binds da feature: contrato → impl. addInstance (instância pronta),
      // addLazySingleton/add (constructor tear-off, auto-injetado).
      ..addInstance<FooRepository>(FooRepositoryImpl(box))
      ..route(
        '/',                            // resolve para /foo
        transition: TransitionType.fade,
        // provide: estado PAGE-SCOPED — nasce ao montar a rota, dispose ao sair.
        // Registre via tear-off `.new`: o auto_injector resolve os parâmetros
        // pelos binds acima. init()/check() rodam no initState da página.
        provide: (s) => s..addChangeNotifier<FooViewModel>(FooViewModel.new),
        child: (context, state) => const FooPage(),
      );
  },
);
```

- **DI lifecycle**: bind em módulo **com `path`** = feature-scoped (vive enquanto
  a feature está na pilha). Bind no `core` (sem `path`) = root-owned (app inteiro).
- **Injeção `.new`** (regra): registre com o tear-off do construtor (`Foo.new`) e
  deixe o auto_injector resolver os parâmetros pelo grafo — **não** escreva
  `() => Foo(inject<A>(), inject<B>())`. `inject<T>()` fica só para onde não há
  construtor (guards, callbacks). O parser de params do auto_injector é regex sobre
  o `toString` do construtor, então use sempre **tipos nomeados**:
  - dependência **factory** ("um X novo por uso"): interface
    `XFactory { X create(); }` (impl no `data/`), **nunca** `X Function()` — o `=>`
    quebra o parser e dois params factory seguidos fundem. Ver
    `TerminalGatewayFactory` + `CockpitViewModel`.
  - **vários primitivos** ambíguos (`String`...): um **value object injetável**
    (ex.: `UpdateTarget`).
- **Valores async** (stores JSON, perfis de terminal, versão) são resolvidos no `main`
  e passados às factories `buildXModule(...)` — `register` é síncrono.
- Registre a feature no `app_module.dart` com `c.module(fooModule)`.

## ViewModels

`ChangeNotifier` puro, **page-scoped** via `provide`. Não há mais base
`ViewModel<T>` nem `states/` sealed obrigatório (era aspiracional, nunca usado).
A página consome via `context.watch<T>()` (rebuild), `context.read<T>()`
(callback) ou `context.select<T,R>()` (rebuild granular). `Consumer`/`Selector`
também existem. **Nunca** instancie ViewModel na página.

Estado **app-global** (tema/fonte = `SettingsController`) não é de feature: vive
em `ModularApp.provide` (no `main`), acima do `ShadcnApp` → `context.watch` em
qualquer lugar.

## Navegação

`context.pushNamed('/settings')` empilha modal-like (fica fora da URL; `pop`
volta). `context.navigate('/x')` troca a base da pilha. `context.pop([result])`.
Paths em [`core/routes.dart`](core/routes.dart) (`RoutePaths`).

## Dialogs com estado próprio

`flutter_modular` não tem provider de árvore ad-hoc. Para um controller de dialog
crie-o no call-site, passe por **construtor** e consuma com
`ListenableBuilder` — e **descarte no fim** (`ctrl.dispose()` após `showDialog`),
senão vaza o que ele segurar (processo, stream, timer).

## Regra crítica: `BuildContext` em código assíncrono

Acessar `context` após `await` (ou dentro de `.then/.onSuccess/.flatMap/
.whenComplete`) crasha se o widget desmontou. O lint não pega callbacks
encadeados — transforme para `await` + guard (`if (!mounted) return;` /
`if (!context.mounted) return;`). Detalhe no [CLAUDE.md raiz](../../CLAUDE.md).

## Checklist — nova feature

1. `mkdir app/<feature>/{domain,data,ui}`.
2. Contratos em `domain/contracts/`, impls em `data/`, página + VMs em `ui/`.
3. `<feature>_module.dart`: registra binds + `route(...)` + `provide:` dos VMs.
4. `c.module(<feature>Module)` no `app_module.dart` (passando deps async do `main`).
5. Path em `core/routes.dart` se for navegado de fora.
6. `flutter analyze` (zero issues) — pega import cruzando feature/quebra de camada.
