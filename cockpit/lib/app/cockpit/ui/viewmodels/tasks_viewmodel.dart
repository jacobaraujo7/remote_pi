import 'dart:async';
import 'dart:io';

import 'package:cockpit/app/cockpit/domain/contracts/task_discovery.dart';
import 'package:cockpit/app/cockpit/domain/contracts/task_runner_gateway.dart';
import 'package:cockpit/app/cockpit/domain/entities/gallery_template.dart';
import 'package:cockpit/app/cockpit/domain/entities/task_definition.dart';
import 'package:cockpit/app/cockpit/domain/entities/task_run.dart';
import 'package:flutter/foundation.dart';

enum TaskImportNotice { sourceMissing, failed }

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
  String? _sourceWorkspaceCwd;
  int _contextVersion = 0;
  bool _disposed = false;
  bool _importing = false;
  TaskImportNotice? _importNotice;
  List<TaskDefinition> _tasks = const [];
  bool _loading = false;
  bool _hasConfig = false;
  final _states = <String, TaskRun>{};
  // Profile escolhido por task (default = primeiro). Persiste só em memória.
  final _profile = <String, String>{};

  List<TaskDefinition> get tasks => _tasks;
  bool get loading => _loading;
  bool get importing => _importing;
  TaskImportNotice? get importNotice => _importNotice;
  bool get canImport =>
      hasProject &&
      !isRemote &&
      !_hasConfig &&
      _tasks.isEmpty &&
      !_loading &&
      (_sourceWorkspaceCwd?.isNotEmpty ?? false) &&
      _sourceWorkspaceCwd != _cwd;

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
  Future<void> loadFor(String cwd, {String? sourceWorkspaceCwd}) async {
    final remote = remoteContextFor?.call(cwd);
    if (cwd == _cwd &&
        sourceWorkspaceCwd == _sourceWorkspaceCwd &&
        identical(remote?.runner, _remote?.runner)) {
      return;
    }
    _contextVersion++;
    _cwd = cwd;
    _sourceWorkspaceCwd = sourceWorkspaceCwd;
    _importNotice = null;
    _importing = false;
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
    final version = _contextVersion;
    _loading = true;
    notifyListeners();
    final found = cwd.isEmpty
        ? const <TaskDefinition>[]
        : await _discovery.discover(cwd);
    if (_disposed || version != _contextVersion) return;
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

  /// Importação explícita de uma cópia independente, sem consultar o Git.
  Future<void> importWorkspaceConfig() async {
    if (!canImport || _importing) return;
    final cwd = _cwd;
    final version = _contextVersion;
    final source = File(_configPath(_sourceWorkspaceCwd!));
    final destination = File(_configPath(cwd));
    _importing = true;
    _importNotice = null;
    notifyListeners();
    TaskImportNotice? notice;
    try {
      if (!await source.exists()) {
        notice = TaskImportNotice.sourceMissing;
      } else {
        final bytes = await source.readAsBytes();
        // Sem awaits entre a reserva exclusiva e a escrita: o watcher e as
        // ações da UI só observam o arquivo depois da cópia completa.
        if (FileSystemEntity.typeSync(destination.path, followLinks: false) ==
            FileSystemEntityType.notFound) {
          destination.parent.createSync(recursive: true);
          destination.createSync(exclusive: true);
          try {
            destination.writeAsBytesSync(bytes, flush: true);
          } on FileSystemException {
            destination.deleteSync();
            rethrow;
          }
        }
      }
    } on FileSystemException {
      notice = TaskImportNotice.failed;
    } finally {
      if (!_disposed && version == _contextVersion) {
        _importing = false;
        _importNotice = notice;
        _watchConfig(cwd);
        await reload();
      }
    }
  }

  /// Cria um `.cockpit/tasks.json` de exemplo (Flutter + Node + C#) no projeto
  /// atual, se ainda não existe; depois redescobre. Botão "Create tasks.json".
  Future<void> createExampleConfig() async {
    if (_cwd.isEmpty || _remote != null || _importing) return;
    final sep = Platform.pathSeparator;
    final dir = Directory('$_cwd$sep.cockpit');
    dir.createSync(recursive: true);
    final file = File(_configPath(_cwd));
    if (!file.existsSync()) {
      file.createSync(exclusive: true);
      file.writeAsStringSync(GalleryTemplate.tasks.content);
    }
    _watchConfig(_cwd); // `.cockpit` agora existe → arma o watcher
    await reload();
  }

  /// Observa o `.cockpit/tasks.json` do projeto e redescobre (debounced) quando
  /// ele muda — edições no arquivo refletem na hora, sem trocar de projeto.
  void _watchConfig(String cwd) {
    _reloadDebounce?.cancel();
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
    _disposed = true;
    _sub?.cancel();
    _configWatch?.cancel();
    _reloadDebounce?.cancel();
    super.dispose();
  }
}
