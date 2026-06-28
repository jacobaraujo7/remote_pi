# Plano 48 — Cockpit Task Run (executor de tarefas com watch/hot-reload)

> Subprojeto alvo: **`cockpit/`** (Flutter Desktop). Local-only, sem relay.
> Referência de arquitetura: [`37-desktop-cockpit.md`](./37-desktop-cockpit.md) e
> as convenções de feature vertical em `cockpit/lib/app/CLAUDE.md`.

## Contexto

O cockpit já roda processos (`pi --mode rpc`), tem PTY embutido com cores
corretas e terminal próprio (`CockpitTerminal`), detecta raiz de projeto por
marcadores, e tem conceito de Projeto/cwd persistido. Falta a camada de **rodar
os comandos de build/dev do projeto** (`npm run dev`, `flutter run`, `go run`,
`make`) com:

- **Descoberta automática** das tarefas a partir dos manifestos do projeto.
- **Streaming de output** num terminal (reusa `CockpitTerminal`).
- **Várias tasks em paralelo**, cada uma no seu processo + terminal.
- **Ciclo de vida visual**: play / stop / restart, badge de estado.
- **Teclas interativas** (ex.: Flutter `r`/`R`) expostas como botões.
- **Watch opcional** ("reload ao salvar") implementado pelo cockpit — porque o
  `flutter run` CLI **não** recarrega sozinho (isso é feature de IDE/plugin).

Inspiração: `tasks.json` + `launch.json` do VSCode (`isBackground`,
`problemMatcher`, `beginsPattern/endsPattern`), **melhorando** em: detecção
semântica em vez de JSON obrigatório, comando montado sempre visível, controles
de ciclo de vida embutidos, diagnósticos via LSP em vez de regex frágil.

## Princípio de design (regra de ouro)

**O core é genérico; o específico de stack vira adapter opcional na borda.**
O executor não sabe o que é "flavor", "dart-define" ou "NODE_ENV" — sabe só
`command`, `args[]`, `env{}`. Tudo de Flutter/React/Go mora num **adapter de
detecção+UI**, nunca no contrato do domain. Mesma filosofia do
`core/data/lsp/project_root_finder.dart` (conhece marcadores de várias stacks
num lugar só).

## Modelo de domínio

Nova feature vertical `cockpit/lib/app/tasks/` com módulo próprio
(`tasks_module.dart`), seguindo `domain/ data/ ui/`.

### Entities (domain) — todas genéricas

```dart
// Definição estática de uma task (detectada ou do JSON).
class TaskDefinition {
  final String id;
  final String label;            // "dev", "app", "build"
  final String command;          // "npm", "flutter", "go"
  final List<String> args;       // ["run", "dev"]
  final TaskKind kind;           // oneShot | watch
  final TaskSource source;       // detected | manual
  final List<TaskProfile> profiles;         // variantes (args/env extras)
  final List<InteractiveKey> interactiveKeys; // teclas (r/R/q/...) — vazio se n/a
  final TaskWatch? watch;        // observador opcional (null = sem watch)
  final List<ProgressPattern> progressPatterns; // begin/end p/ badge building→ready
}

enum TaskKind { oneShot, watch }
enum TaskSource { detected, manual }

// "launch config": conjunto nomeado de args/env. NADA específico de stack aqui.
class TaskProfile {
  final String name;             // "dev", "prod"
  final List<String> args;       // concatenado após TaskDefinition.args
  final Map<String, String> env; // mesclado no env do processo
}

// Uma tecla interativa enviada ao stdin do PTY.
class InteractiveKey {
  final String key;     // "r", "R", "q"
  final String label;   // "Hot reload"
  final String? icon;   // token de ícone opcional → sem icon, mostra chip [r]
  final bool primary;   // true = botão fixo; false = vai pro menu overflow ⌨
}

// Watcher opcional: observa paths e dispara uma ação ao mudar.
class TaskWatch {
  final List<String> paths;    // ["lib/**", "assets/**"]
  final List<String> ignore;   // ["build/**", ".dart_tool/**"]
  final String onChange;       // referencia uma InteractiveKey.label OU "restart"
  final int debounceMs;        // 300
}

// Equivalente ao beginsPattern/endsPattern do VSCode (badge building→ready).
class ProgressPattern {
  final String begin;  // regex "Performing hot reload"
  final String end;    // regex "Reloaded .* in .*ms"
}

// Estado vivo de uma execução.
class TaskRun {
  final String taskId;
  final String? profileName;
  final TaskRunStatus status;  // idle|building|running|success|failed|stopped
  final int? pid;
  // output vai pro CockpitTerminal; o TaskRun só guarda status/metadata.
}
enum TaskRunStatus { idle, building, running, success, failed, stopped }
```

### Contratos (domain)

```dart
abstract class TaskRunnerGateway {        // impl no data/ (reusa PTY/Process)
  Stream<TaskRun> runs();                  // estados vivos
  Future<void> start(TaskDefinition def, {String? profileName, List<String> adHocArgs});
  Future<void> stop(String taskId);
  Future<void> restart(String taskId);
  Future<void> sendKey(String taskId, String key); // pty.write(key)
}

abstract class TaskDiscovery {            // dado um cwd → tasks detectadas
  Future<List<TaskDefinition>> discover(String cwd);
}

abstract class TaskAdapter {              // 1 por stack — preenche specifics
  bool matches(String cwd);               // tem pubspec? package.json?
  List<TaskDefinition> tasksFor(String cwd);
}
```

O `TaskDiscovery` agrega vários `TaskAdapter` (mesmo padrão multi-marcador do
`project_root_finder`). MVP: `NpmAdapter` (lê `package.json.scripts`) +
`FlutterAdapter` (gera `flutter run`/`flutter test` + `interactiveKeys` r/R/q +
`watch` + `progressPatterns`). Stacks sem adapter → o usuário edita
`args`/`env` na mão (campo cru) ou via `.cockpit/tasks.json`.

## Persistência / JSON (opcional)

- **Detecção primeiro**: ao selecionar projeto, roda `TaskDiscovery.discover(cwd)`
  e mostra as tasks sem JSON nenhum. 90% dos casos = zero config.
- **`.cockpit/tasks.json`** (versionável) só pra customização: profiles, env,
  args, qual é a "dev default". Editável por botão "⚙ editar tasks.json".
- Schema do JSON = espelho das entities (genérico). Flavor/dart-define do Flutter
  **não** são chaves do schema — viram `args` (`["--flavor","dev","--dart-define=…"]`)
  gerados pelo formulário amigável do FlutterAdapter na UI.
- **`cwd` por task, relativo à pasta do `tasks.json`** (decisão 2026-06-27):
  - **per-task é canônico** (explícito, sem herança escondida): cada task declara
    o seu `cwd`. Cobre **monorepo** onde as pastas divergem: UM `tasks.json` na
    raiz dirige `app/` (flutter, `cwd:"app"`), `backend/` (dart, `cwd:"backend"`),
    etc. — sem espalhar arquivo por subpacote.
  - `cwd` **omitido** numa task → roda na pasta do arquivo (workspace). Cobre repo
    de pacote único.
  - top-level `"cwd"` é só **açúcar de DRY opcional** (default quando todas
    compartilham a pasta); a task sempre vence. Pode nem existir.
  - O loader resolve absoluto = `join(dir_do_tasks_json, cwd_relativo)` e grava em
    `TaskDefinition.cwd` (o campo já existe — zero mudança de domínio).
  - Convive com a detecção: pacote único → adapters detectam sozinhos; monorepo
    (raiz sem manifesto) → JSON com `cwd` por task.

## UI / Layout

### Subpane de Tasks na coluna direita (abaixo dos Files)

A coluna direita hoje é o `FileTreePanel`, que já compõe slots (`searchPanel`,
`footer`/`_LspStatusBar`). O subpane de Tasks entra como **mais um slot
redimensionável e colapsável** abaixo da árvore (ver `cockpit_page.dart:479-539`).

```
┌ Projects ┬ Agentes / Terminal ──┬ Files ──────────────┐
│  ● app   │  (terminal central)  │ ▾ lib/  …            │
│  ○ web   │                      ├═════════════════════┤ ← divisória arrastável
│          │                      │ TASKS          [+]  │
│          │                      │ ◐ web   ⟳  ◼       │
│          │                      │ ● app   ↻ ⟳ ⌨▾ ◼  │
│          │                      │ ○ build       ▶     │
│          │                      │ ✓ test        ▶     │
└──────────┴──────────────────────┴─────────────────────┘
```

- **Subpane = controle; terminal central = janela.** Clicar numa task rodando
  abre/foca o output dela num `CockpitTerminal` (aba). Não enche a coluna de logs.
- Estados por cor (`context.colors`): `○ idle` cinza · `● running` azul ·
  `◐ building` âmbar (pulsando) · `✓ success` verde · `✗ failed` vermelho.
- Botões contextuais pelo estado: parada → `▶`; rodando → `◼ stop` + `⟳ restart`.

### Profiles (flavor/dart-define genérico)

Task parametrizada mostra dropdown de profile antes do play, com preview da
linha de comando montada (transparência — sempre se vê o comando real):

```
▶ app  flutter run  [ dev ▾ ]  ● running  ↻ ⟳ ◼
     └ --flavor dev --dart-define=ENV=staging
```

- Trocar profile com a task viva → "requer restart" (flavor/dart-define são
  baked no start; `r`/`R` só agem dentro do profile rodando).
- Campo "+ args" ad-hoc pra override de uma execução só (não vira profile).
- Dois profiles ao mesmo tempo (`app/dev` + `app/prod`) = dois processos/terminais.

### interactiveKeys — data-driven

A UI renderiza N controles a partir da lista (0, 2, 5 — tanto faz). **Sem
`if (flutter)` em lugar nenhum:**

- `primary: true` → botão fixo com ícone (`↻` reload, `⟳` restart).
- `primary: false` → vai pro overflow `⌨▾` (popover lista label + tecla crua).
- sem `icon` → chip com a própria tecla (`[r]`).
- lista vazia (ex.: vite) → nenhum botão de tecla, só `◼`.
- Tooltip revela o mapeamento: `[↻]` → "Hot reload (envia 'r')".

Cada botão/item = `gateway.sendKey(taskId, key)` → `pty.write(key)`.

### Watch toggle ("reload ao salvar")

`flutter run` CLI **não** recarrega ao salvar — isso é o plugin do VSCode/IntelliJ
observando o save e mandando `r`. O cockpit reimplementa como watcher genérico
(`Directory.watch()` nativo), ligável por task:

```
● app   flutter run   [🔥 reload-on-save: on]   ↻ ⟳ ◼
```

- `on` → observa `watch.paths`, ignora `watch.ignore`, debounce `watch.debounceMs`,
  dispara `watch.onChange` (manda a tecla `r`).
- `off` → manual (aperta `↻`).
- **Genérico**: dev-servers que já observam (vite/next/nodemon/`tsc --watch`)
  têm `watch == null` no adapter → toggle nem aparece (evita watcher duplo).

### Capacidade vs Atividade (não confundir)

- **Capacidade** (o botão aparece) → vem da *definição* (`interactiveKeys`),
  conhecida na detecção.
- **Atividade** (o badge `◐ building → ●`) → vem do *output* em runtime, casando
  `progressPatterns` (begin/end) — defaults embutidos por adapter:
  | Ferramenta | begin → `◐` | end → `●` |
  |---|---|---|
  | flutter (reload) | `Performing hot reload` | `Reloaded .* in .*ms` |
  | flutter (restart) | `Performing hot restart` | `Restarted application in .*ms` |
  | vite | `hmr update` | `✓ .* in .*ms` |
  | tsc --watch | `File change detected` | `Found 0 errors` |

## Reuso do que já existe

| Já existe | Arquivo | Uso |
|---|---|---|
| Spawn/stream/kill gracioso + anti-órfão | `cockpit/data/rpc/pi_rpc_process.dart` | molde do runner oneShot/captured |
| PTY real (stdin/stdout/resize, cores) | `cockpit/data/terminal/pty_terminal_gateway.dart` | runner de watch (TUI/spinners/teclas) |
| Terminal próprio | `cockpit/ui/widgets/` (`CockpitTerminal`) | janela de output das tasks |
| Detector de raiz multi-marcador | `core/data/lsp/project_root_finder.dart` | base do `TaskDiscovery` + lista de ignore |
| Projeto/cwd persistido | `Project` + `ProjectRepository` (Hive) | tasks são por-projeto |
| Slots da coluna direita | `cockpit_page.dart:479-539` (`FileTreePanel` `searchPanel`/`footer`) | encaixe do subpane de Tasks |
| Diagnósticos | LSP em curso (memória `project_cockpit_lsp`) | substitui `problemMatcher` regex |

## Passos (com critério de aceite)

### Passo 1 — Domain + contratos
Criar `tasks/domain/` com entities e contratos acima.
**Aceite**: `flutter analyze` zero issues; `domain/` não importa `data/`/`ui/`.

### Passo 2 — Runner (data) reusando PTY/Process
`TaskRunnerGateway` impl: `watch` kind via PTY gateway; `oneShot` via molde do
`pi_rpc_process`. `sendKey` = `pty.write`. Registry anti-órfão ao fechar o app.
**Aceite**: rodar `npm run dev` num projeto real, ver output no terminal, parar
limpo (SIGTERM→SIGKILL); `sendKey('r')` chega no stdin (testar com `flutter run`).

### Passo 3 — Discovery + adapters (Npm, Flutter)
`TaskDiscovery` agrega adapters. `NpmAdapter` lê `package.json.scripts`.
`FlutterAdapter` gera run/test + `interactiveKeys` + `watch` + `progressPatterns`.
**Aceite**: abrir projeto Flutter → aparece task `app` com botões `↻/⟳`; abrir
projeto npm → aparecem os scripts; teste unitário do parse de `package.json`.

### Passo 4 — Subpane de Tasks (ui)
Slot redimensionável/colapsável abaixo do `FileTreePanel`. Lista data-driven com
badges de estado e botões contextuais. Clique → foca terminal da task.
**Aceite**: várias tasks rodando em paralelo, cada uma seu terminal; badges
refletem estado; subpane colapsa e Files volta a ocupar tudo.

### Passo 5 — Profiles + args ad-hoc + JSON opcional
Dropdown de profile com preview do comando; campo "+ args"; ler/gravar
`.cockpit/tasks.json` (com `cwd` opcional relativo ao arquivo → resolve absoluto
em `TaskDefinition.cwd`; default top-level + override por task; suporta monorepo
com UM arquivo na raiz). Formulário amigável de flavor/dart-define no
FlutterAdapter → gera `args` genéricos.
**Aceite**: rodar `app/dev` e `app/prod` em paralelo; editar tasks.json e ver
refletir; preview mostra a linha real.

### Passo 6 — Watch toggle + progress patterns
Watcher `Directory.watch` com debounce/ignore; toggle "reload-on-save"; badge
`building→ready` via `progressPatterns`.
**Aceite**: salvar um `.dart` com toggle on → cockpit manda `r` sozinho e o
badge pisca `◐→●`; toggle off → manual; vite não mostra o toggle.

## Definition of Done

- [x] Passo 1 — domain + contratos genéricos (sem stack specifics)
- [x] Passo 2 — runner reusa PTY (`kyroon_pty`), start/stop/restart/sendKey/resize
- [x] Passo 3 — discovery + NpmAdapter + FlutterAdapter (+ teste do npm)
- [x] Passo 4 — subpane de Tasks na coluna direita, controles data-driven
- [~] Passo 5 — `.cockpit/tasks.json` loader + `cwd` per-task FEITO (mesclado no
      discover, JSON tem precedência); falta o UI de profiles/args ad-hoc
- [ ] Doc do `.cockpit/tasks.json`: documentar o schema (campos, `cwd` per-task,
      interactiveKeys, watch, progressPatterns, profiles) + publicar/− referenciar
      um JSON Schema de verdade (substituindo a URL aspiracional removida)
- [x] Passo 6 — watcher reload-on-save (`Directory.watch` recursivo, debounce,
      match por path/ignore) + toggle por task (default on); dispara a tecla de
      `onChange` (ou restart). (progress patterns já vinham do passo 2)
- [x] Output ao vivo de cada task numa **aba read-only do pane central**
      (`TaskOutputSession`): clique na task abre/foca a aba; abrir/fechar à
      vontade sem matar a task; buffer preservado no `TaskTerminalStore`
      (app-scoped, alimenta o xterm desde o boot); efêmera no restart do app
- [x] `flutter analyze` zero issues; `flutter test` (145) e `build macos` ok
- [x] Sem `if (flutter)` no core/ui — tudo via dados do adapter

> **Entregue (commits desta branch)**: domain + runner PTY + discovery/adapters
> + subpane com badges e botões de tecla (`r`/`R`/...), montado abaixo da árvore
> de arquivos via novo slot `tasksPanel` do `FileTreePanel`. O runner já expõe
> `output(taskId)` e `progressPatterns` estão modelados — falta plugar o
> terminal embutido (passo de UI) e ligar os profiles + watcher (passos 5-6).

## Decisões em aberto (resolver antes do Passo 1)

1. **PTY vs pipe por kind**: watch → PTY (cores/teclas); oneShot → pipe capturado
   (parse limpo). Confirmar se vale os dois caminhos no runner desde já.
2. **Onde persistir**: só Hive, ou também `.cockpit/tasks.json` versionado desde
   o MVP? (recomendação: JSON desde já, dá portabilidade entre máquinas.)
3. **Diagnósticos**: acoplar ao LSP (`project_cockpit_lsp`) e pular regex de
   problem matcher? (recomendação: sim, não reinventar regex frágil.)

## Próximos planos (futuro)

- Diagnósticos de task no painel do LSP (clicar erro → abre arquivo:linha).
- "Compound tasks" (rodar um grupo de uma vez, tipo `launch.json` compounds).
- Mais adapters (Cargo `features`, Make targets, `just`).
