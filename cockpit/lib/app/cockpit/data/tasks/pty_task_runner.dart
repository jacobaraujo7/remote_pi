import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cockpit/app/cockpit/data/rpc/pi_process_registry.dart';
import 'package:cockpit/app/core/data/setup/remote_pi_resolver.dart';
import 'package:cockpit/app/cockpit/domain/contracts/task_runner_gateway.dart';
import 'package:cockpit/app/cockpit/domain/entities/task_definition.dart';
import 'package:cockpit/app/cockpit/domain/entities/task_run.dart';
import 'package:kyroon_pty/kyroon_pty.dart';

/// Executor de tasks num PTY nativo (`kyroon_pty`). Roda cada task via **login
/// shell** (`$SHELL -lc "<cmd>"`) pra herdar o PATH do perfil do usuário — sem
/// isso o app GUI não acharia `flutter`/`npm`/`go` (PATH mínimo do Finder).
/// Mesma razão e mesmas vars (`TERM`/`COLORTERM`) do terminal embutido.
class PtyTaskRunner implements TaskRunnerGateway {
  final _runs = StreamController<TaskRun>.broadcast();
  final _running = <String, _RunningTask>{};
  final _lastState = <String, TaskRun>{};
  final _watchers = <String, StreamSubscription<FileSystemEvent>>{};
  final _watchDebounce = <String, Timer>{};

  @override
  Stream<TaskRun> runs() => _runs.stream;

  @override
  TaskRun runOf(String taskId) =>
      _running[taskId]?.state ??
      _lastState[taskId] ??
      TaskRun.idleFor(taskId);

  @override
  Stream<List<int>> output(String taskId) =>
      _running[taskId]?.out.stream ?? const Stream<List<int>>.empty();

  @override
  Future<void> start(
    TaskDefinition def, {
    String? profileName,
    List<String> adHocArgs = const [],
  }) async {
    if (_running.containsKey(def.id)) return; // idempotente

    final profile = profileName == null
        ? null
        : def.profiles.firstWhere((p) => p.name == profileName);
    final argv = [...def.resolveArgs(profile), ...adHocArgs];
    final cmdLine = _join([def.command, ...argv]);

    final env = {
      ...await envWithNodeOnPath(),
      if (profile != null) ...profile.env,
      'TERM': 'xterm-256color',
      'COLORTERM': 'truecolor',
    };

    final pty = Pty.start(
      _shell(),
      arguments: _shellArgs(cmdLine),
      workingDirectory: def.cwd.isEmpty ? null : def.cwd,
      environment: env,
      rows: 24,
      columns: 80,
    );
    unawaited(PiProcessRegistry.register(pty.pid));

    final initial = TaskRun(
      taskId: def.id,
      status: TaskRunStatus.running,
      profileName: profileName,
      pid: pty.pid,
    );
    final task = _RunningTask(pty, def, initial);
    _running[def.id] = task;
    _emit(initial);

    // Fan-out do output: alimenta o terminal e o detector de progresso.
    task.outSub = pty.output.listen((bytes) {
      task.out.add(bytes);
      _detectProgress(task, bytes);
    });

    unawaited(pty.exitCode.then((code) => _onExit(def.id, code)));
  }

  @override
  Future<void> stop(String taskId) async {
    final task = _running[taskId];
    if (task == null) return;
    task.stopping = true;
    try {
      task.pty.kill(ProcessSignal.sigterm);
    } catch (_) {}
    // Garante SIGKILL se não morrer em 3s.
    unawaited(
      Future<void>.delayed(const Duration(seconds: 3), () {
        if (_running.containsKey(taskId)) {
          try {
            task.pty.kill(ProcessSignal.sigkill);
          } catch (_) {}
        }
      }),
    );
  }

  @override
  Future<void> restart(String taskId) async {
    final task = _running[taskId];
    if (task == null) return;
    final def = task.def;
    final profileName = task.state.profileName;
    await stop(taskId);
    // Aguarda o slot liberar (até ~3.5s) antes de re-spawnar.
    for (var i = 0; i < 35 && _running.containsKey(taskId); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await start(def, profileName: profileName);
  }

  @override
  void sendKey(String taskId, String key) {
    final task = _running[taskId];
    if (task == null) return;
    task.pty.write(Uint8List.fromList(utf8.encode(key)));
  }

  @override
  void startWatch(TaskDefinition def) {
    final w = def.watch;
    if (w == null || _watchers.containsKey(def.id)) return;
    final dir = Directory(def.cwd);
    if (!dir.existsSync()) return;
    try {
      _watchers[def.id] = dir.watch(recursive: true).listen((event) {
        if (!_matchesWatch(def.cwd, w, event.path)) return;
        _watchDebounce[def.id]?.cancel();
        _watchDebounce[def.id] = Timer(
          Duration(milliseconds: w.debounceMs),
          () => _dispatchWatch(def, w),
        );
      });
    } catch (_) {
      // FS sem suporte a watch recursivo → silencioso (sem reload automático).
    }
  }

  @override
  void stopWatch(String taskId) {
    unawaited(_watchers.remove(taskId)?.cancel());
    _watchDebounce.remove(taskId)?.cancel();
  }

  @override
  void resize(String taskId, int rows, int columns) {
    final task = _running[taskId];
    if (task == null) return;
    try {
      task.pty.resize(rows, columns);
    } catch (_) {}
  }

  /// `true` se [path] (mudou) está sob algum [TaskWatch.paths] e fora de
  /// [TaskWatch.ignore], tudo relativo a [cwd]. Glob simples por segmento de
  /// prefixo (ex.: `lib` casa `lib/...`; `build` ignora `build/...`).
  bool _matchesWatch(String cwd, TaskWatch w, String path) {
    final sep = Platform.pathSeparator;
    var rel = path;
    if (path.startsWith(cwd)) {
      rel = path.substring(cwd.length);
      if (rel.startsWith(sep)) rel = rel.substring(1);
    }
    bool under(String base) =>
        rel == base || rel.startsWith('$base$sep') || rel.startsWith('$base/');
    if (w.ignore.any(under)) return false;
    if (w.paths.isEmpty) return true;
    return w.paths.any(under);
  }

  void _dispatchWatch(TaskDefinition def, TaskWatch w) {
    if (!_running.containsKey(def.id)) return; // morreu nesse meio tempo
    if (w.onChange == TaskWatch.restart) {
      unawaited(restart(def.id));
      return;
    }
    for (final k in def.interactiveKeys) {
      if (k.label == w.onChange) {
        sendKey(def.id, k.key);
        return;
      }
    }
  }

  @override
  Future<void> disposeAll() async {
    for (final id in _watchers.keys.toList()) {
      stopWatch(id);
    }
    for (final task in _running.values) {
      task.stopping = true;
      try {
        task.pty.kill(ProcessSignal.sigkill);
      } catch (_) {}
      await task.outSub?.cancel();
      await task.out.close();
    }
    _running.clear();
    await _runs.close();
  }

  // --- internals ---------------------------------------------------------

  void _onExit(String taskId, int code) {
    final task = _running.remove(taskId);
    if (task == null) return;
    stopWatch(taskId); // o processo morreu → nada pra recarregar
    unawaited(PiProcessRegistry.unregister(task.pty.pid));
    final TaskRunStatus status;
    if (task.stopping) {
      status = TaskRunStatus.stopped;
    } else if (task.def.kind == TaskKind.oneShot) {
      status = code == 0 ? TaskRunStatus.success : TaskRunStatus.failed;
    } else {
      // watch que morreu sozinho = falha (dev-server caiu).
      status = code == 0 ? TaskRunStatus.stopped : TaskRunStatus.failed;
    }
    final ended = task.state.copyWith(
      status: status,
      exitCode: code,
      pid: -1, // pid não vivo
    );
    _lastState[taskId] = TaskRun(
      taskId: taskId,
      status: status,
      profileName: task.state.profileName,
      exitCode: code,
    );
    unawaited(task.outSub?.cancel());
    unawaited(task.out.close());
    _emit(ended);
  }

  /// Casa os [ProgressPattern]s da task no output pra oscilar building↔running.
  void _detectProgress(_RunningTask task, List<int> bytes) {
    final patterns = task.def.progressPatterns;
    if (patterns.isEmpty) return;
    final text = utf8.decode(bytes, allowMalformed: true);
    for (final p in patterns) {
      if (RegExp(p.begin).hasMatch(text)) {
        _transition(task, TaskRunStatus.building);
      }
      if (RegExp(p.end).hasMatch(text)) {
        _transition(task, TaskRunStatus.running);
      }
    }
  }

  void _transition(_RunningTask task, TaskRunStatus status) {
    if (task.state.status == status) return;
    task.state = task.state.copyWith(status: status);
    _emit(task.state);
  }

  void _emit(TaskRun run) {
    if (!_runs.isClosed) _runs.add(run);
  }

  String _shell() {
    if (Platform.isWindows) {
      return Platform.environment['ComSpec'] ?? 'cmd.exe';
    }
    return Platform.environment['SHELL'] ?? '/bin/zsh';
  }

  /// Args do shell pra rodar UM comando e herdar o PATH do perfil:
  /// POSIX `-lc "<cmd>"` (login → carrega ~/.zprofile etc); Windows `/c <cmd>`.
  List<String> _shellArgs(String cmdLine) =>
      Platform.isWindows ? ['/c', cmdLine] : ['-lc', cmdLine];

  /// Junta executável + args numa linha de shell, citando o que tem espaço.
  String _join(List<String> parts) => parts.map(_quote).join(' ');

  String _quote(String s) {
    if (s.isNotEmpty && !RegExp(r'''[\s"'$`\\]''').hasMatch(s)) return s;
    return "'${s.replaceAll("'", r"'\''")}'";
  }
}

class _RunningTask {
  _RunningTask(this.pty, this.def, this.state);

  final Pty pty;
  final TaskDefinition def;
  final out = StreamController<List<int>>.broadcast();
  StreamSubscription<List<int>>? outSub;
  TaskRun state;
  bool stopping = false;
}
