import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cockpit/app/cockpit/data/tasks/task_process_registry.dart';
import 'package:cockpit/app/cockpit/data/tasks/compose_tasks.dart';
import 'package:cockpit/app/core/data/setup/remote_pi_resolver.dart';
import 'package:cockpit/app/core/terminal/pty_output_scheduler.dart';
import 'package:cockpit/app/core/terminal/terminal_line_ending_normalizer.dart';
import 'package:cockpit/app/core/utils/login_shell.dart';
import 'package:cockpit/app/cockpit/domain/contracts/task_runner_gateway.dart';
import 'package:cockpit/app/cockpit/domain/contracts/telemetry_ingest.dart';
import 'package:cockpit/app/cockpit/domain/entities/task_definition.dart';
import 'package:cockpit/app/cockpit/domain/entities/task_run.dart';
import 'package:cockpit_pty/cockpit_pty.dart';

/// Executor de tasks num PTY nativo (`kyroon_pty`). Roda cada task via **login
/// shell** (o shell de login do usuário + `-ilc "<cmd>"`, ver [resolveLoginShell])
/// pra herdar o PATH do perfil do usuário — sem
/// isso o app GUI não acharia `flutter`/`npm`/`go` (PATH mínimo do Finder).
/// Mesma razão e mesmas vars (`TERM`/`COLORTERM`) do terminal embutido.
class PtyTaskRunner implements TaskRunnerGateway, ReconciledTaskRunnerGateway {
  PtyTaskRunner(this._telemetry);

  /// Telemetria (plano 66): toda task alimenta a Caixa Preta por padrão. A
  /// sessão nasce antes do spawn (injeta `COCKPIT_RUN_ID`/`OTEL_*` no env),
  /// recebe cada chunk de output e fecha com o exit code.
  final TelemetryIngest _telemetry;

  // Síncrono para o TaskTerminalStore assinar o stream de output antes que o
  // primeiro byte do processo possa chegar. Evita perder o prólogo de builds
  // muito rápidas e inclui o parse do terminal no orçamento do scheduler.
  final _runs = StreamController<TaskRun>.broadcast(sync: true);
  final _previews = StreamController<TaskPreviewUrl>.broadcast();
  final _running = <String, _RunningTask>{};
  final _starting = <String>{};
  final _lastState = <String, TaskRun>{};
  final _watchers = <String, StreamSubscription<FileSystemEvent>>{};
  final _watchDebounce = <String, Timer>{};
  final _composeDefinitions =
      <String, ({TaskDefinition def, ComposeTask task})>{};
  final _composeOutput = <String, StreamController<String>>{};
  final _composeFollowers = <String, Process>{};
  final _composeActive = <String>{};
  Timer? _composePoll;
  bool _composePolling = false;

  @override
  Stream<TaskRun> runs() => _runs.stream;

  @override
  Stream<TaskPreviewUrl> previewUrls() => _previews.stream;

  @override
  TaskRun runOf(String taskId) =>
      _running[taskId]?.state ?? _lastState[taskId] ?? TaskRun.idleFor(taskId);

  @override
  Stream<String> output(String taskId) =>
      _running[taskId]?.out.stream ??
      _composeOutput[taskId]?.stream ??
      const Stream<String>.empty();

  @override
  Future<void> start(
    TaskDefinition def, {
    String? profileName,
    List<String> adHocArgs = const [],
  }) {
    final compose =
        _composeDefinitions[def.id]?.task ??
        const ComposeTaskRecognizer().recognize(def);
    if (compose != null) {
      return _startCompose(def, compose, profileName);
    }
    return _launch(def, profileName: profileName, adHocArgs: adHocArgs);
  }

  @override
  Future<void> reconcileDefinitions(List<TaskDefinition> definitions) async {
    _composeDefinitions.clear();
    for (final def in definitions) {
      var compose = const ComposeTaskRecognizer().recognize(def);
      if (compose != null) {
        final workspace = _workspaceFor(def.cwd);
        if (workspace != null) {
          final parsed = await const ComposeFileParser().parse(
            compose.file,
            workspace,
          );
          if (parsed != null) {
            compose = ComposeTask(
              engine: compose.engine,
              file: parsed.path,
              service: compose.service,
            );
          }
        }
        _composeDefinitions[def.id] = (def: def, task: compose);
        _composeOutput.putIfAbsent(
          def.id,
          () => StreamController<String>.broadcast(),
        );
      }
    }
    await _pollCompose();
    _composePoll?.cancel();
    if (_composeDefinitions.isNotEmpty) {
      _composePoll = Timer.periodic(
        const Duration(seconds: 3),
        (_) => unawaited(_pollCompose()),
      );
    }
  }

  String? _workspaceFor(String cwd) {
    var dir = Directory(cwd).absolute;
    while (true) {
      if (File(
        '${dir.path}${Platform.pathSeparator}.cockpit${Platform.pathSeparator}tasks.json',
      ).existsSync()) {
        return dir.path;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) return null;
      dir = parent;
    }
  }

  Future<void> _pollCompose() async {
    if (_composePolling) return;
    _composePolling = true;
    try {
      final grouped = <String, ({ComposeTask task, List<String> ids})>{};
      for (final e in _composeDefinitions.entries) {
        final key = '${e.value.task.engine.name}:${e.value.task.file}';
        grouped
            .putIfAbsent(key, () => (task: e.value.task, ids: <String>[]))
            .ids
            .add(e.key);
      }
      for (final group in grouped.values) {
        final running = await const ComposeEngineResolver().runningServices(
          group.task.engine,
          group.task.file,
        );
        for (final id in group.ids) {
          final service = _composeDefinitions[id]!.task.service;
          final active = running.contains(service);
          if (active && _composeActive.add(id)) {
            _emit(
              _lastState[id] = TaskRun(
                taskId: id,
                status: TaskRunStatus.running,
              ),
            );
          } else if (!active && _composeActive.remove(id)) {
            await _stopComposeFollower(id);
            _emit(
              _lastState[id] = TaskRun(
                taskId: id,
                status: TaskRunStatus.stopped,
              ),
            );
          }
        }
      }
    } finally {
      _composePolling = false;
    }
  }

  Future<void> _startCompose(
    TaskDefinition def,
    ComposeTask task,
    String? profileName,
  ) async {
    if (_composeActive.contains(def.id) || _starting.contains(def.id)) return;
    final profile = def.profiles
        .where((p) => p.name == profileName)
        .firstOrNull;
    if (profile == null) return;
    _starting.add(def.id);
    final out = _composeOutput.putIfAbsent(
      def.id,
      () => StreamController<String>.broadcast(),
    );
    _emit(
      _lastState[def.id] = TaskRun(
        taskId: def.id,
        status: TaskRunStatus.starting,
        profileName: profileName,
      ),
    );
    TelemetryIngestSession? telemetry;
    try {
      final argv = [...task.engine.prefix, '-f', task.file, ...profile.args];
      telemetry = await _telemetry.openTaskRun(
        def,
        command: _join([def.command, ...argv]),
      );
      final result = await Process.run(
        def.command,
        argv,
        workingDirectory: File(task.file).parent.path,
        environment: {
          ...await envWithNodeOnPath(),
          ...profile.env,
          ...?telemetry?.childEnvironment,
        },
      );
      if ('${result.stdout}'.isNotEmpty) {
        out.add(_normalizeComposeOutput('${result.stdout}'));
        telemetry?.add('${result.stdout}');
      }
      if ('${result.stderr}'.isNotEmpty) {
        out.add(_normalizeComposeOutput('${result.stderr}'));
        telemetry?.add('${result.stderr}');
      }
      if (result.exitCode != 0) {
        _emit(
          _lastState[def.id] = TaskRun(
            taskId: def.id,
            status: TaskRunStatus.failed,
            profileName: profileName,
            exitCode: result.exitCode,
          ),
        );
      } else if (profile.name == 'build') {
        _emit(
          _lastState[def.id] = TaskRun(
            taskId: def.id,
            status: TaskRunStatus.success,
            profileName: profileName,
            exitCode: 0,
          ),
        );
      } else {
        _composeActive.add(def.id);
        _emit(
          _lastState[def.id] = TaskRun(
            taskId: def.id,
            status: TaskRunStatus.running,
            profileName: profileName,
          ),
        );
        await attachOutput(def.id);
      }
      await telemetry?.close(exitCode: result.exitCode);
      telemetry = null;
    } catch (e) {
      out.add('$e\r\n');
      telemetry?.add('$e\n');
      await telemetry?.close(exitCode: -1);
      telemetry = null;
      _emit(
        _lastState[def.id] = TaskRun(
          taskId: def.id,
          status: TaskRunStatus.failed,
          profileName: profileName,
        ),
      );
    } finally {
      _starting.remove(def.id);
    }
  }

  @override
  Future<void> attachOutput(String taskId) async {
    if (_composeFollowers.containsKey(taskId)) return;
    final entry = _composeDefinitions[taskId];
    if (entry == null || !_composeActive.contains(taskId)) return;
    final task = entry.task;
    final Process process;
    try {
      process = await Process.start(task.engine.command, [
        ...task.engine.prefix,
        '-f',
        task.file,
        'logs',
        '--tail',
        '200',
        '--follow',
        task.service,
      ], workingDirectory: File(task.file).parent.path);
    } catch (e) {
      _composeOutput
          .putIfAbsent(taskId, () => StreamController<String>.broadcast())
          .add('Unable to attach Compose logs: $e\r\n');
      return;
    }
    _composeFollowers[taskId] = process;
    final out = _composeOutput.putIfAbsent(
      taskId,
      () => StreamController<String>.broadcast(),
    );
    _pipeComposeLogs(process.stdout, out);
    _pipeComposeLogs(process.stderr, out);
    unawaited(
      process.exitCode.whenComplete(() => _composeFollowers.remove(taskId)),
    );
  }

  void _pipeComposeLogs(
    Stream<List<int>> source,
    StreamController<String> destination,
  ) {
    final endings = TerminalLineEndingNormalizer();
    source
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(
          (chunk) {
            final normalized = endings.add(chunk);
            if (normalized.isNotEmpty && !destination.isClosed) {
              destination.add(normalized);
            }
          },
          onDone: () {
            final tail = endings.close();
            if (tail.isNotEmpty && !destination.isClosed) {
              destination.add(tail);
            }
          },
        );
  }

  String _normalizeComposeOutput(String value) {
    final endings = TerminalLineEndingNormalizer();
    return endings.add(value) + endings.close();
  }

  /// O spawn de verdade. [restarting] distingue o start inicial do re-spawn do
  /// [restart] — é isso que faz `previewOpen: "start"` não reabrir o navegador
  /// a cada restart. Interno de propósito: o contrato do gateway não muda.
  Future<void> _launch(
    TaskDefinition def, {
    String? profileName,
    List<String> adHocArgs = const [],
    bool restarting = false,
  }) async {
    if (_running.containsKey(def.id)) return; // idempotente
    if (!_starting.add(def.id)) return; // spawn já em preparação

    // Feedback imediato: o botão troca antes dos awaits de resolução
    // (login shell / which node), que podem levar segundos.
    _emit(
      _lastState[def.id] = TaskRun(
        taskId: def.id,
        status: TaskRunStatus.starting,
        profileName: profileName,
      ),
    );

    final Pty pty;
    TelemetryIngestSession? telemetry;
    try {
      final profile = profileName == null
          ? null
          : def.profiles.firstWhere((p) => p.name == profileName);
      final argv = [...def.resolveArgs(profile), ...adHocArgs];
      final cmdLine = _join([def.command, ...argv]);
      telemetry = await _telemetry.openTaskRun(def, command: cmdLine);

      final env = {
        ...await envWithNodeOnPath(),
        if (profile != null) ...profile.env,
        ...?telemetry?.childEnvironment,
        // TERM fora do Windows: no PowerShell nativo o TERM quebra o auto-load
        // do PSReadLine e o ConPTY já entrega o VT (ver pty_terminal_gateway).
        if (!Platform.isWindows) 'TERM': 'xterm-256color',
        'COLORTERM': 'truecolor',
      };

      final spawn = await _spawnFor(cmdLine);
      pty = Pty.start(
        spawn.exe,
        arguments: spawn.args,
        workingDirectory: def.cwd.isEmpty ? null : def.cwd,
        environment: env,
        rows: 24,
        columns: 80,
        // Mesmo backpressure dos terminais interativos (plan/57).
        ackRead: true,
      );
    } catch (_) {
      _starting.remove(def.id);
      unawaited(telemetry?.close(exitCode: -1));
      _emit(
        _lastState[def.id] = TaskRun(
          taskId: def.id,
          status: TaskRunStatus.failed,
          profileName: profileName,
        ),
      );
      rethrow;
    }
    _starting.remove(def.id);
    unawaited(TaskProcessRegistry.register(pty.pid));

    final initial = TaskRun(
      taskId: def.id,
      status: TaskRunStatus.running,
      profileName: profileName,
      pid: pty.pid,
    );
    late final _RunningTask task;
    task = _RunningTask(
      pty,
      def,
      initial,
      isRestart: restarting,
      telemetry: telemetry,
      onOutput: (data) {
        if (!task.out.isClosed) task.out.add(data);
        task.telemetry?.add(data);
        _detectProgress(task, data);
        _detectPreviewUrl(task, data);
      },
    );
    _running[def.id] = task;
    _emit(initial);

    // `preview` fixo no tasks.json: abre já no start, sem esperar output. A URL
    // fixa marca `previewNotified` mesmo com o auto-open suprimido — ela
    // substitui a detecção por output, não convive com ela.
    final forced = def.previewUrl;
    if (def.previewEnabled && forced != null && forced.isNotEmpty) {
      task.previewNotified = true;
      if (def.shouldOpenPreview(isRestart: restarting) && !_previews.isClosed) {
        _previews.add(TaskPreviewUrl(def.id, forced));
      }
    }

    // Decoder incremental + scheduler GLOBAL. O callback de flush alimenta um
    // stream síncrono: parse VT e progressPatterns contam dentro do budget de
    // CPU antes que o scheduler reconheça o chunk e libere mais output nativo.
    task.outSub = pty.output
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(task.coalescer.add);

    unawaited(pty.exitCode.then((code) => _onExit(def.id, code)));
  }

  @override
  Future<void> stop(String taskId) async {
    final compose = _composeDefinitions[taskId];
    if (compose != null && _composeActive.contains(taskId)) {
      _emit(
        _lastState[taskId] = TaskRun(
          taskId: taskId,
          status: TaskRunStatus.stopping,
        ),
      );
      final task = compose.task;
      final result = await Process.run(task.engine.command, [
        ...task.engine.prefix,
        '-f',
        task.file,
        'stop',
        task.service,
      ], workingDirectory: File(task.file).parent.path);
      await _stopComposeFollower(taskId);
      _composeActive.remove(taskId);
      _emit(
        _lastState[taskId] = TaskRun(
          taskId: taskId,
          status: result.exitCode == 0
              ? TaskRunStatus.stopped
              : TaskRunStatus.failed,
          exitCode: result.exitCode,
        ),
      );
      return;
    }
    final task = _running[taskId];
    if (task == null) return;
    if (task.stopping) return; // já em curso — não empilha kills
    task.stopping = true;
    // Feedback imediato: o botão vira "stopping" antes do processo morrer
    // (o stopped real chega no _onExit).
    _transition(task, TaskRunStatus.stopping);
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
    final compose = _composeDefinitions[taskId];
    if (compose != null && _composeActive.contains(taskId)) {
      final task = compose.task;
      _emit(
        _lastState[taskId] = TaskRun(
          taskId: taskId,
          status: TaskRunStatus.starting,
        ),
      );
      final result = await Process.run(task.engine.command, [
        ...task.engine.prefix,
        '-f',
        task.file,
        'restart',
        task.service,
      ], workingDirectory: File(task.file).parent.path);
      await _stopComposeFollower(taskId);
      if (result.exitCode == 0) {
        _emit(
          _lastState[taskId] = TaskRun(
            taskId: taskId,
            status: TaskRunStatus.running,
          ),
        );
        await attachOutput(taskId);
      } else {
        _composeActive.remove(taskId);
        _emit(
          _lastState[taskId] = TaskRun(
            taskId: taskId,
            status: TaskRunStatus.failed,
            exitCode: result.exitCode,
          ),
        );
      }
      return;
    }
    final task = _running[taskId];
    if (task == null) return;
    final def = task.def;
    final profileName = task.state.profileName;
    await stop(taskId);
    // Aguarda o slot liberar (até ~3.5s) antes de re-spawnar.
    for (var i = 0; i < 35 && _running.containsKey(taskId); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await _launch(def, profileName: profileName, restarting: true);
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
    _composePoll?.cancel();
    for (final id in _composeFollowers.keys.toList()) {
      await _stopComposeFollower(id);
    }
    for (final out in _composeOutput.values) {
      await out.close();
    }
    for (final id in _watchers.keys.toList()) {
      stopWatch(id);
    }
    for (final task in _running.values) {
      task.stopping = true;
      try {
        task.pty.kill(ProcessSignal.sigkill);
      } catch (_) {}
      await TaskProcessRegistry.unregister(task.pty.pid);
      await task.outSub?.cancel();
      task.coalescer.dispose();
      await task.out.close();
    }
    _running.clear();
    await _runs.close();
    await _previews.close();
  }

  Future<void> _stopComposeFollower(String taskId) async {
    final process = _composeFollowers.remove(taskId);
    if (process == null) return;
    process.kill(ProcessSignal.sigterm);
  }

  // --- internals ---------------------------------------------------------

  void _onExit(String taskId, int code) {
    final task = _running.remove(taskId);
    if (task == null) return;
    task.ended = true;
    stopWatch(taskId); // o processo morreu → nada pra recarregar
    unawaited(TaskProcessRegistry.unregister(task.pty.pid));
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
    unawaited(_finishOutput(task));
    unawaited(task.telemetry?.close(exitCode: code) ?? Future.value());
    _emit(ended);
  }

  Future<void> _finishOutput(_RunningTask task) async {
    await task.outSub?.cancel();
    // Entra na mesma fila limitada do restante: encerrar uma task ruidosa não
    // pode produzir um flush síncrono gigante no isolate da UI.
    task.coalescer.add('\r\n\r\nfinished\r\n');
    await task.coalescer.drained;
    task.coalescer.dispose();
    if (!task.out.isClosed) await task.out.close();
  }

  /// Casa os [ProgressPattern]s da task no output pra oscilar building↔running.
  void _detectProgress(_RunningTask task, String text) {
    if (task.ended) return;
    final patterns = task.def.progressPatterns;
    if (patterns.isEmpty) return;
    for (final p in patterns) {
      if (RegExp(p.begin).hasMatch(text)) {
        _transition(task, TaskRunStatus.building);
      }
      if (RegExp(p.end).hasMatch(text)) {
        _transition(task, TaskRunStatus.running);
      }
    }
  }

  /// Sequências ANSI (cores/cursor) — removidas antes de casar a URL.
  static final _ansiRe = RegExp(r'\x1b\[[0-9;?]*[a-zA-Z]');

  /// URL de dev server no output (`http://localhost:5173/`, `127.0.0.1`,
  /// `0.0.0.0`). Path sem espaços/aspas/fechamentos.
  static final _localUrlRe = RegExp(
    r'''https?://(?:localhost|127\.0\.0\.1|0\.0\.0\.0)(?::\d+)?(?:/[^\s"'`)\]]*)?''',
  );

  /// Primeira URL local do run → emite pro shell abrir o navegador (plano 58).
  /// Mantém uma cauda curta do texto limpo pra URL partida entre chunks.
  void _detectPreviewUrl(_RunningTask task, String data) {
    if (task.previewNotified) return;
    if (!task.def.shouldOpenPreview(isRestart: task.isRestart)) return;
    final haystack = task.previewTail + data.replaceAll(_ansiRe, '');
    final match = _localUrlRe.firstMatch(haystack);
    if (match == null) {
      task.previewTail = haystack.length > 256
          ? haystack.substring(haystack.length - 256)
          : haystack;
      return;
    }
    // URL no fim do chunk pode estar incompleta (porta/path cortados) — espera
    // o próximo chunk fechar a fronteira antes de emitir.
    if (match.end == haystack.length) {
      task.previewTail = haystack.substring(match.start);
      return;
    }
    task.previewNotified = true;
    task.previewTail = '';
    if (!_previews.isClosed) {
      _previews.add(TaskPreviewUrl(task.def.id, match.group(0)!));
    }
  }

  void _transition(_RunningTask task, TaskRunStatus status) {
    // Output tardio (progressPatterns) não pode reverter um stop em curso.
    if (task.stopping && status != TaskRunStatus.stopping) return;
    if (task.state.status == status) return;
    task.state = task.state.copyWith(status: status);
    _emit(task.state);
  }

  void _emit(TaskRun run) {
    if (!_runs.isClosed) _runs.add(run);
  }

  /// Executável + args pra rodar [cmdLine] num shell (login/interactive).
  ///
  /// No **macOS**, prefixa com `launchctl asuser <uid>` pra **reparentar o
  /// processo ao launchd** e quebrar a atribuição de *responsible process* ao
  /// Cockpit. Sem isso, um app GUI lançado por uma task (`flutter run -d macos`)
  /// é atribuído ao app pai (o Cockpit) e — no modo "merged UI and platform
  /// thread" do embedder — não consegue ativar/foregroundar e **morre antes de
  /// inicializar** (`Failed to foreground app; open returned 1`, sem janela).
  /// Lançado a partir de um terminal o mesmo comando funciona, justamente porque
  /// o pai não é um app GUI. O reparent **não exige root** (asuser do próprio
  /// uid), **preserva o PTY no stdin** (hot reload `r`/`R` segue funcionando) e
  /// **mantém o environment** (PATH/`TERM`/`COLORTERM`). Windows/Linux não têm
  /// essa atribuição → spawn direto. Se o uid não resolver, cai no spawn direto.
  Future<({String exe, List<String> args})> _spawnFor(String cmdLine) async {
    final shellArgv = [await _shell(), ..._shellArgs(cmdLine)];
    if (Platform.isMacOS) {
      final uid = await _currentUid();
      if (uid != null) {
        return (exe: '/bin/launchctl', args: ['asuser', uid, ...shellArgv]);
      }
    }
    return (exe: shellArgv.first, args: shellArgv.sublist(1));
  }

  String? _cachedUid;

  /// UID do usuário atual (string), pro `launchctl asuser`. `null` se falhar —
  /// não há API Dart pra `getuid()`, então lê de `id -u` (cacheado).
  Future<String?> _currentUid() async {
    if (_cachedUid != null) return _cachedUid;
    try {
      final r = await Process.run('id', ['-u']);
      if (r.exitCode == 0) {
        final out = (r.stdout as String).trim();
        if (out.isNotEmpty) return _cachedUid = out;
      }
    } catch (_) {}
    return null;
  }

  /// Shell da task. POSIX: o shell de **login real** do usuário — `$SHELL` some
  /// quando o app é aberto pelo Finder/Dock (sem shell-pai) e o fish/bash do
  /// usuário viraria zsh (issue #42).
  Future<String> _shell() async {
    if (Platform.isWindows) {
      return Platform.environment['ComSpec'] ?? 'cmd.exe';
    }
    return resolveLoginShell();
  }

  /// Args do shell pra rodar UM comando e herdar o PATH do perfil. POSIX
  /// `-ilc "<cmd>"`: **interactive + login**. O `-l` carrega `~/.zprofile`/
  /// `/etc/paths`, mas só `-i` (interactive) faz o zsh ler `~/.zshrc` — onde a
  /// maioria coloca o PATH de `flutter`/`fvm`/`asdf`. Sem o `-i`, um login
  /// **não-interativo** (`-lc`) pula o `.zshrc` e o comando falha com
  /// `command not found: flutter`. É o mesmo shell interativo do terminal
  /// embutido (que roda `-l` com PTY → interativo), só que com `-c <cmd>`.
  /// Windows: `/c <cmd>`.
  List<String> _shellArgs(String cmdLine) =>
      Platform.isWindows ? ['/c', cmdLine] : ['-ilc', cmdLine];

  /// Junta executável + args numa linha de shell, citando o que tem espaço.
  String _join(List<String> parts) => parts.map(_quote).join(' ');

  String _quote(String s) {
    if (s.isNotEmpty && !RegExp(r'''[\s"'$`\\]''').hasMatch(s)) return s;
    return "'${s.replaceAll("'", r"'\''")}'";
  }
}

class _RunningTask {
  _RunningTask(
    this.pty,
    this.def,
    this.state, {
    required void Function(String data) onOutput,
    this.isRestart = false,
    this.telemetry,
  }) : coalescer = PtyOutputCoalescer(
         onFlush: onOutput,
         onAcknowledge: pty.ackRead,
       );

  final Pty pty;
  final TaskDefinition def;
  final TelemetryIngestSession? telemetry;
  // Síncrono: o trabalho do consumidor acontece dentro do slice cronometrado
  // pelo PtyOutputScheduler, não numa fila de eventos sem limite posterior.
  final out = StreamController<String>.broadcast(sync: true);
  final PtyOutputCoalescer coalescer;
  StreamSubscription<String>? outSub;
  TaskRun state;
  bool stopping = false;
  bool ended = false;

  /// `true` quando o run nasceu de um restart (botão ou watcher) em vez de um
  /// start. Só o auto-open do preview olha isso (`previewOpen: "start"`).
  final bool isRestart;

  /// Auto-open do navegador (plano 58): no máximo uma emissão por run.
  bool previewNotified = false;

  /// Cauda do output decodificado (sem ANSI) — cobre URL partida entre chunks.
  String previewTail = '';
}
