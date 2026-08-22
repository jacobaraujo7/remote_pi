import 'dart:async';
import 'dart:io';

import 'package:cockpit/app/cockpit/domain/contracts/task_discovery.dart';
import 'package:cockpit/app/cockpit/domain/contracts/task_runner_gateway.dart';
import 'package:cockpit/app/cockpit/domain/entities/task_definition.dart';
import 'package:cockpit/app/cockpit/domain/entities/task_run.dart';
import 'package:flutter/foundation.dart';

/// ViewModel page-scoped do subpane de Tasks. Descobre as tasks do projeto
/// selecionado e dirige o ciclo de vida via [TaskRunnerGateway], refletindo o
/// stream de estados vivos. A `ui/` nunca toca `data/` direto.
class TasksViewModel extends ChangeNotifier {
  TasksViewModel(this._localDiscovery, this._localRunner) {
    _subscribeRuns();
  }

  final TaskDiscovery _localDiscovery;
  final TaskRunnerGateway _localRunner;

  /// Contexto de tasks REMOTO por cwd (plano 58): setado pela `CockpitPage`,
  /// devolve o par (descoberta + runner) do host quando o workspace é remoto,
  /// ou `null` no local. O par por host é cacheado no call-site (runner precisa
  /// sobreviver às trocas de cwd pra manter as tasks rodando).
  ({TaskDiscovery discovery, TaskRunnerGateway runner})? Function(String cwd)?
  remoteContextFor;

  ({TaskDiscovery discovery, TaskRunnerGateway runner})? _remote;

  TaskDiscovery get _discovery => _remote?.discovery ?? _localDiscovery;
  TaskRunnerGateway get _runner => _remote?.runner ?? _localRunner;

  StreamSubscription<TaskRun>? _sub;
  void _subscribeRuns() {
    _sub?.cancel();
    _sub = _runner.runs().listen(_onRun);
  }

  StreamSubscription<FileSystemEvent>? _configWatch;
  Timer? _reloadDebounce;

  String _cwd = '';
  List<TaskDefinition> _tasks = const [];
  bool _loading = false;
  bool _hasConfig = false;
  final _states = <String, TaskRun>{};
  // Profile escolhido por task (default = primeiro). Persiste só em memória.
  final _profile = <String, String>{};

  List<TaskDefinition> get tasks => _tasks;
  bool get loading => _loading;

  /// `true` se já existe um `.cockpit/tasks.json` no projeto (esconde o botão
  /// de criar exemplo).
  bool get hasConfig => _hasConfig;

  /// Há um projeto selecionado (cwd não-vazio) — habilita criar o exemplo.
  bool get hasProject => _cwd.isNotEmpty;

  String _configPath(String cwd) {
    final sep = Platform.pathSeparator;
    return '$cwd$sep.cockpit${sep}tasks.json';
  }

  /// Estado atual de uma task (idle se nunca rodou).
  TaskRun stateOf(String taskId) => _states[taskId] ?? _runner.runOf(taskId);

  /// (Re)carrega as tasks do projeto em [cwd]. No-op se já é o cwd corrente.
  Future<void> loadFor(String cwd) async {
    final remote = remoteContextFor?.call(cwd);
    if (cwd == _cwd && identical(remote?.runner, _remote?.runner)) return;
    _cwd = cwd;
    // Troca de runner (local ↔ remoto, ou entre hosts) → reassina o stream de
    // estados e reaponta a descoberta.
    if (!identical(remote?.runner, _remote?.runner)) {
      _remote = remote;
      _subscribeRuns();
    }
    _watchConfig(cwd);
    await _runDiscovery();
  }

  /// Redescobre as tasks do cwd atual (botão de refresh / watch do tasks.json).
  Future<void> reload() => _runDiscovery();

  Future<void> _runDiscovery() async {
    final cwd = _cwd;
    _loading = true;
    notifyListeners();
    final found = cwd.isEmpty
        ? const <TaskDefinition>[]
        : await _discovery.discover(cwd);
    if (cwd != _cwd) return; // corrida com outra troca de projeto
    _tasks = found;
    // Remoto: o tasks.json vive no host — não dá pra `File.existsSync` aqui;
    // a presença é inferida por ter descoberto tasks.
    _hasConfig = _remote != null
        ? found.isNotEmpty
        : (cwd.isNotEmpty && File(_configPath(cwd)).existsSync());
    _loading = false;
    notifyListeners();
  }

  /// `true` quando o workspace ativo é remoto (o painel esconde ações que só
  /// fazem sentido no local — criar o tasks.json de exemplo).
  bool get isRemote => _remote != null;

  /// Cria um `.cockpit/tasks.json` de exemplo (Flutter + Node + C#) no projeto
  /// atual, se ainda não existe; depois redescobre. Botão "Create tasks.json".
  Future<void> createExampleConfig() async {
    if (_cwd.isEmpty || _remote != null) return; // remoto: edita no host
    final sep = Platform.pathSeparator;
    final dir = Directory('$_cwd$sep.cockpit');
    await dir.create(recursive: true);
    final file = File(_configPath(_cwd));
    if (!await file.exists()) {
      await file.writeAsString(_exampleConfig);
    }
    _watchConfig(_cwd); // `.cockpit` agora existe → arma o watcher
    await reload();
  }

  /// Observa o `.cockpit/tasks.json` do projeto e redescobre (debounced) quando
  /// ele muda — edições no arquivo refletem na hora, sem trocar de projeto.
  void _watchConfig(String cwd) {
    _configWatch?.cancel();
    _configWatch = null;
    // Remoto: sem watch de FS do host (o tasks.json muda no host). Refresh só
    // manual pelo botão. Local segue com o watcher.
    if (cwd.isEmpty || _remote != null) return;
    final dir = Directory('$cwd${Platform.pathSeparator}.cockpit');
    try {
      if (!dir.existsSync()) return;
      _configWatch = dir.watch().listen((e) {
        if (!e.path.endsWith('tasks.json')) return;
        _reloadDebounce?.cancel();
        _reloadDebounce = Timer(const Duration(milliseconds: 250), reload);
      });
    } catch (_) {
      // FS sem watch → fica só o refresh manual.
    }
  }

  /// Nome do profile selecionado (default = primeiro; null se a task não tem).
  String? selectedProfile(TaskDefinition def) {
    if (def.profiles.isEmpty) return null;
    return _profile[def.id] ?? def.profiles.first.name;
  }

  /// Avança pro próximo profile (cicla). No-op com < 2 profiles.
  void cycleProfile(TaskDefinition def) {
    if (def.profiles.length < 2) return;
    final names = def.profiles.map((p) => p.name).toList();
    final cur = selectedProfile(def);
    final next = names[(names.indexOf(cur ?? names.first) + 1) % names.length];
    _profile[def.id] = next;
    notifyListeners();
  }

  /// Comando final (preview) com os args do profile escolhido aplicados.
  String commandPreview(TaskDefinition def) {
    final name = selectedProfile(def);
    final profile = name == null
        ? null
        : def.profiles.firstWhere((p) => p.name == name);
    return '${def.command} ${def.resolveArgs(profile).join(' ')}'.trim();
  }

  Future<void> start(TaskDefinition def) =>
      _runner.start(def, profileName: selectedProfile(def));

  Future<void> stop(String taskId) => _runner.stop(taskId);

  Future<void> restart(String taskId) => _runner.restart(taskId);

  void sendKey(String taskId, String key) => _runner.sendKey(taskId, key);

  void resize(String taskId, int rows, int columns) =>
      _runner.resize(taskId, rows, columns);

  /// Output decodificado de uma task para o terminal embutido.
  Stream<String> output(String taskId) => _runner.output(taskId);

  void _onRun(TaskRun run) {
    _states[run.taskId] = run;
    // Reload-on-save sempre ligado quando a task tem `watch` configurado
    // (kind=watch). O runner ignora tasks sem watch. Desarma ao morrer.
    if (run.isActive) {
      final def = _defOf(run.taskId);
      if (def != null) _runner.startWatch(def);
    } else {
      _runner.stopWatch(run.taskId);
    }
    notifyListeners();
  }

  TaskDefinition? _defOf(String taskId) {
    for (final d in _tasks) {
      if (d.id == taskId) return d;
    }
    return null;
  }

  @override
  void dispose() {
    _sub?.cancel();
    _configWatch?.cancel();
    _reloadDebounce?.cancel();
    super.dispose();
  }
}

/// Modelo de `.cockpit/tasks.json` gerado pelo botão "Create tasks.json":
/// um exemplo de Flutter (watch + hot reload), Node e C#. O usuário edita os
/// `cwd`/comandos pro projeto dele. Ver `docs/tasks-json.md`.
const String _exampleConfig = '''
{
  // .cockpit/tasks.json — Cockpit Task Run config (JSONC: // , /* */ and
  // trailing commas are allowed; they're stripped before parsing).
  // Lives at the workspace root you open in Cockpit. Detected tasks (npm
  // scripts, pubspec) appear automatically; this file adds/overrides them.
  // Full reference: cockpit/docs/tasks-json.md
  "tasks": [
    {
      "label": "Flutter Example", // shown in the Tasks list
      "cwd": "app", // run dir, relative to this file (monorepo-friendly)
      "command": "flutter", // base executable
      "args": ["run"], // base args, before the profile
      "kind": "watch", // "watch" = long-running (dev server); else "oneShot"
      // Optional: only show this task on some OSes — "macos" | "windows" |
      // "linux", as a string or array. Omitted -> visible everywhere.
      // "platforms": ["macos", "linux"],
      // Interactive keys -> buttons that write a key to the process stdin.
      // primary=true shows a fixed button; the rest go under a key menu.
      // icon: bolt | refresh | restart | stop (omit -> a chip with the key).
      "interactiveKeys": [
        { "key": "r", "label": "Hot reload", "icon": "bolt", "primary": true },
        { "key": "R", "label": "Hot restart", "icon": "restart", "primary": true },
        { "key": "p", "label": "Toggle debug paint" },
        { "key": "o", "label": "Toggle platform" }
      ],
      // Reload-on-save: `flutter run` doesn't reload on save by itself (that's
      // an IDE plugin) — Cockpit watches the files and fires `onChange`.
      "watch": {
        "paths": ["lib", "assets"], // dirs to watch (relative to cwd)
        "ignore": ["build", ".dart_tool"], // skip these (avoid loops)
        "onChange": "Hot reload", // an interactiveKey label, or "__restart__"
        "debounceMs": 300 // wait after a change before firing
      },
      // Drive the building/running badge by matching the output.
      "progressPatterns": [
        { "begin": "Performing hot reload", "end": "Reloaded .* in .*ms" },
        { "begin": "Performing hot restart", "end": "Restarted application in .*ms" }
      ],
      // Named arg/env variants, picked by the chip before Run (flavor /
      // dart-define just become args here — no stack-specific keys).
      "profiles": [
        { "name": "web", "args": ["-d", "chrome"] },
        { "name": "macos", "args": ["-d", "macos"] }
      ]
    },
    {
      // No "kind" -> defaults to "oneShot".
      "label": "Node Example",
      "cwd": "site",
      "command": "npm",
      "args": ["run", "dev"]
      // Browser auto-open. "preview": true (default) opens the first local URL
      // found in the output; false turns it off; a string opens that fixed URL
      // right at start.
      // "preview": "http://localhost:3000",
      // When it opens: "always" (default: start and restart), "start" (only on
      // start — Restart and the file watcher won't reopen it) or "never".
      // "previewOpen": "start",
    },
    {
      "label": "C# Example",
      "cwd": "api",
      "command": "dotnet",
      "args": ["watch", "run"],
      "kind": "watch"
    }
  ]
}
''';
