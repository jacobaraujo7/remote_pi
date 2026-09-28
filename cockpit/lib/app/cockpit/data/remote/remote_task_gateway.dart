import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cockpit/app/cockpit/data/tasks/tasks_json_loader.dart';
import 'package:cockpit/app/cockpit/domain/contracts/task_discovery.dart';
import 'package:cockpit/app/cockpit/domain/contracts/task_runner_gateway.dart';
import 'package:cockpit/app/cockpit/domain/entities/task_definition.dart';
import 'package:cockpit/app/cockpit/domain/entities/task_run.dart';
import 'package:cockpit_core/cockpit_core.dart';
import 'package:cockpit_remote/cockpit_remote.dart';

/// Descoberta de tasks num workspace REMOTO (plano 58): lê o
/// `<root>/.cockpit/tasks.json` do host via `fs.read` e reusa o parser do
/// [TasksJsonLoader]. Sem auto-detecção por adapters (que varreria o FS do
/// host) — no remoto as tasks vêm só do JSON, definido explicitamente.
class RemoteTaskDiscovery implements TaskDiscovery {
  RemoteTaskDiscovery(this._filesProvider);

  /// Resolve o serviço de arquivos do host (conecta por SSH se preciso).
  final Future<RemoteFileService> Function() _filesProvider;
  final _loader = TasksJsonLoader();

  @override
  Future<List<TaskDefinition>> discover(String cwd) async {
    if (cwd.isEmpty) return const [];
    try {
      final files = await _filesProvider();
      final bytes = await files.read('$cwd/.cockpit/tasks.json');
      return _loader.parseContent(
        utf8.decode(bytes, allowMalformed: true),
        cwd,
      );
    } catch (_) {
      return const []; // arquivo ausente/ilegível → sem tasks
    }
  }
}

/// Executa tasks num host REMOTO (plano 58): spawna o comando num PTY do
/// `cockpit-server` (via [TerminalService]) e mapeia os [PtyEvent] pro modelo
/// [TaskRun]. Reusa 100% do stack de terminal remoto (stream/input/resize/kill).
///
/// Diferenças vs o [TaskRunnerGateway] local (`PtyTaskRunner`):
/// - **Sem reload-on-save** (`startWatch`/`stopWatch` são no-op): não há watch
///   de filesystem remoto. As teclas interativas seguem funcionando (stdin).
/// - **Sem detecção de progresso** (badge building→running): o estado vai de
///   `running` direto a `success`/`failed`/`stopped` no exit.
class RemoteTaskRunner implements TaskRunnerGateway {
  RemoteTaskRunner(this._terminalProvider);

  /// Resolve o serviço de terminal do host (conecta por SSH se preciso);
  /// cacheado após a primeira task (a conexão é estável por host).
  final Future<TerminalService> Function() _terminalProvider;
  TerminalService? _terminal;

  Future<TerminalService> _svc() async =>
      _terminal ??= await _terminalProvider();

  final _runs = StreamController<TaskRun>.broadcast(sync: true);
  final _running = <String, _RemoteRunning>{};
  final _lastState = <String, TaskRun>{};

  @override
  Stream<TaskRun> runs() => _runs.stream;

  // Detecção de dev-server URL (auto-open do navegador) é do runner LOCAL; no
  // remoto o preview embutido não aponta pra localhost do host (plano 58/60).
  @override
  Stream<TaskPreviewUrl> previewUrls() => const Stream<TaskPreviewUrl>.empty();

  @override
  TaskRun runOf(String taskId) =>
      _running[taskId]?.state ?? _lastState[taskId] ?? TaskRun.idleFor(taskId);

  @override
  Stream<String> output(String taskId) =>
      _running[taskId]?.out.stream ?? const Stream<String>.empty();

  @override
  Future<void> start(
    TaskDefinition def, {
    String? profileName,
    List<String> adHocArgs = const [],
  }) async {
    if (_running.containsKey(def.id)) return; // idempotente
    _emit(
      _lastState[def.id] = TaskRun(
        taskId: def.id,
        status: TaskRunStatus.starting,
        profileName: profileName,
      ),
    );
    final profile = profileName == null
        ? null
        : def.profiles.firstWhere(
            (p) => p.name == profileName,
            orElse: () => def.profiles.first,
          );
    final argv = [...def.resolveArgs(profile), ...adHocArgs];
    final cmdLine = _join([def.command, ...argv]);

    final TerminalService terminal;
    final PtySessionInfo info;
    try {
      terminal = await _svc();
      info = await terminal.open(
        PtySpawnSpec(
          // Login shell: carrega o PATH do usuário no host (flutter/npm/…) e o
          // `exec` faz o processo da task ser o filho direto do PTY (stdin/
          // teclas interativas vão pra ele).
          executable: '/bin/sh',
          arguments: ['-lc', 'exec $cmdLine'],
          workingDirectory: def.cwd.isEmpty ? null : def.cwd,
          environment: {'TERM': 'xterm-256color'},
        ),
      );
    } catch (e) {
      _emit(
        _lastState[def.id] = TaskRun(
          taskId: def.id,
          status: TaskRunStatus.failed,
          profileName: profileName,
        ),
      );
      return;
    }

    final task = _RemoteRunning(
      def: def,
      sessionId: info.id,
      state: TaskRun(
        taskId: def.id,
        status: TaskRunStatus.running,
        profileName: profileName,
        pid: info.pid,
      ),
    );
    _running[def.id] = task;
    _emit(task.state);

    task.sub = terminal
        .attach(info.id)
        .listen(
          (event) {
            switch (event) {
              case PtyOutputEvent(:final chunk):
                if (!task.out.isClosed) {
                  task.out.add(utf8.decode(chunk.bytes, allowMalformed: true));
                }
                unawaited(terminal.ack(info.id, chunk.bytes.length));
              case PtyExitEvent(:final exitCode):
                _onExit(def.id, exitCode);
            }
          },
          onError: (_) => _onExit(def.id, -1),
          onDone: () => _onExit(def.id, task.exitCode ?? 0),
        );
  }

  @override
  Future<void> stop(String taskId) async {
    final task = _running[taskId];
    if (task == null) return;
    task.stopping = true;
    _emit(task.state = task.state.copyWith(status: TaskRunStatus.stopping));
    try {
      await _terminal?.kill(task.sessionId);
    } catch (_) {
      // kill falhou (sessão já morta) → o exit/onDone reconcilia.
    }
  }

  @override
  Future<void> restart(String taskId) async {
    final task = _running[taskId];
    if (task == null) return;
    final def = task.def;
    final profileName = task.state.profileName;
    await stop(taskId);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await start(def, profileName: profileName);
  }

  @override
  void sendKey(String taskId, String key) {
    final task = _running[taskId];
    if (task == null) return;
    unawaited(
      _terminal?.write(task.sessionId, Uint8List.fromList(utf8.encode(key))),
    );
  }

  @override
  void resize(String taskId, int rows, int columns) {
    final task = _running[taskId];
    if (task == null) return;
    unawaited(_terminal?.resize(task.sessionId, rows, columns));
  }

  // Reload-on-save não existe no remoto (sem watch de FS): no-op.
  @override
  void startWatch(TaskDefinition def) {}

  @override
  void stopWatch(String taskId) {}

  void _onExit(String taskId, int code) {
    final task = _running.remove(taskId);
    if (task == null) return;
    unawaited(task.sub?.cancel());
    final status = task.stopping
        ? TaskRunStatus.stopped
        : (code == 0 ? TaskRunStatus.success : TaskRunStatus.failed);
    _emit(
      _lastState[taskId] = TaskRun(
        taskId: taskId,
        status: status,
        profileName: task.state.profileName,
        exitCode: code,
      ),
    );
    unawaited(task.out.close());
  }

  void _emit(TaskRun run) {
    if (!_runs.isClosed) _runs.add(run);
  }

  @override
  Future<void> disposeAll() async {
    for (final task in _running.values) {
      task.stopping = true;
      try {
        await _terminal?.kill(task.sessionId);
      } on Object catch (_) {
        // conexão já caiu: o host mata o filho pelo exit-on-parent-close.
      }
      await task.sub?.cancel();
      await task.out.close();
    }
    _running.clear();
    await _runs.close();
  }

  String _join(List<String> parts) => parts.map(_quote).join(' ');

  String _quote(String s) {
    if (s.isNotEmpty && !RegExp(r'''[\s"'$`\\]''').hasMatch(s)) return s;
    return "'${s.replaceAll("'", r"'\''")}'";
  }
}

class _RemoteRunning {
  _RemoteRunning({
    required this.def,
    required this.sessionId,
    required this.state,
  });

  final TaskDefinition def;
  final String sessionId;
  TaskRun state;
  final out = StreamController<String>.broadcast(sync: true);
  StreamSubscription<PtyEvent>? sub;
  bool stopping = false;
  int? exitCode;
}
