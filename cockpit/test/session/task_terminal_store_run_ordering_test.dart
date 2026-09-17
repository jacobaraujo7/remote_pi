import 'dart:async';

import 'package:cockpit/app/cockpit/domain/contracts/task_runner_gateway.dart';
import 'package:cockpit/app/cockpit/domain/contracts/terminal_scrollback_store.dart';
import 'package:cockpit/app/cockpit/domain/entities/task_definition.dart';
import 'package:cockpit/app/cockpit/domain/entities/task_run.dart';
import 'package:cockpit/app/cockpit/ui/session/task_terminal_store.dart';
import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:cockpit/app/core/terminal/terminal_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runner que imita a mecânica do `PtyTaskRunner`: `runs()` é broadcast
/// SÍNCRONO, `output()` só devolve o stream real enquanto a task está em
/// `_running` (senão `Stream.empty()`), e cada run tem seu próprio controller
/// de output. É exatamente essa ordem (registrar em `_running` ANTES de emitir
/// `running`) que o store depende pra não assinar um stream vazio pra sempre.
class SequencedRunner implements TaskRunnerGateway {
  final _runs = StreamController<TaskRun>.broadcast(sync: true);
  final _running = <String, StreamController<String>>{};

  /// Spawn: registra o output e emite `running` com [pid].
  void spawn(String taskId, {int? pid}) {
    _running[taskId] = StreamController<String>.broadcast(sync: true);
    _runs.add(TaskRun(taskId: taskId, status: TaskRunStatus.running, pid: pid));
  }

  /// Emite `running` SEM ter registrado output (ordem errada de propósito).
  void emitRunningBeforeRegister(String taskId, {int? pid}) => _runs.add(
    TaskRun(taskId: taskId, status: TaskRunStatus.running, pid: pid),
  );

  void write(String taskId, String data) => _running[taskId]!.add(data);

  void exit(String taskId, {int code = 0}) {
    final out = _running.remove(taskId);
    _runs.add(
      TaskRun(
        taskId: taskId,
        status: code == 0 ? TaskRunStatus.success : TaskRunStatus.failed,
        exitCode: code,
      ),
    );
    unawaited(out?.close());
  }

  @override
  Stream<TaskRun> runs() => _runs.stream;

  @override
  Stream<String> output(String taskId) =>
      _running[taskId]?.stream ?? const Stream<String>.empty();

  @override
  Stream<TaskPreviewUrl> previewUrls() => const Stream<TaskPreviewUrl>.empty();

  @override
  TaskRun runOf(String taskId) => TaskRun.idleFor(taskId);

  @override
  void resize(String taskId, int rows, int columns) {}

  @override
  Future<void> start(
    TaskDefinition def, {
    String? profileName,
    List<String> adHocArgs = const [],
  }) async {}

  @override
  Future<void> stop(String taskId) async {}

  @override
  Future<void> restart(String taskId) async {}

  @override
  void sendKey(String taskId, String key) {}

  @override
  void startWatch(TaskDefinition def) {}

  @override
  void stopWatch(String taskId) {}

  @override
  Future<void> disposeAll() async {}
}

class NullScrollbackStore implements TerminalScrollbackStore {
  @override
  Future<String?> load({
    required String projectId,
    required String sessionId,
  }) async => null;

  @override
  Future<void> save({
    required String projectId,
    required String sessionId,
    required String contents,
  }) async {}

  @override
  Future<void> delete({
    required String projectId,
    required String sessionId,
  }) async {}

  @override
  Future<void> pruneExcept(Set<String> keep) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SequencedRunner runner;
  late TaskTerminalStore store;

  setUp(() {
    runner = SequencedRunner();
    store = TaskTerminalStore(runner, NullScrollbackStore())
      ..setDefaultEngine(TerminalEngine.xterm);
  });

  tearDown(() => store.dispose());

  String screen(String taskId) =>
      (store.existingTerminal(taskId)! as XtermTerminalController)
          .plainLines()
          .join('\n');

  test('output do 1º run chega ao terminal (subscribe no próprio emit)', () {
    runner.spawn('t', pid: 100);
    runner.write('t', 'hello\r\n');
    expect(screen('t'), contains('hello'));
  });

  test('run com pid null ainda assina o output (mapa vazio != pid null)', () {
    runner.spawn('t');
    runner.write('t', 'no-pid\r\n');
    expect(screen('t'), contains('no-pid'));
  });

  test('re-run com o MESMO pid assina o stream do processo novo', () {
    runner.spawn('t', pid: 7);
    runner.write('t', 'first\r\n');
    runner.exit('t');
    runner.spawn('t', pid: 7); // pid reutilizado pelo SO
    runner.write('t', 'second\r\n');
    final s = screen('t');
    expect(s, contains('second'));
    expect(s, isNot(contains('first'))); // restart limpou a tela
  });

  test('building<->running do mesmo pid não re-subscreve', () {
    runner.spawn('t', pid: 5);
    runner._runs.add(
      const TaskRun(taskId: 't', status: TaskRunStatus.building, pid: 5),
    );
    runner._runs.add(
      const TaskRun(taskId: 't', status: TaskRunStatus.running, pid: 5),
    );
    runner.write('t', 'once\r\n');
    // Uma subscription só: a linha aparece uma vez (sem duplicar nem limpar).
    expect('once'.allMatches(screen('t')).length, 1);
  });

  test('emitir running ANTES de registrar output deixa a aba vazia', () {
    // Documenta a dependência de ordem do contrato: o runner precisa registrar
    // `_running` antes do `_emit(initial)` (PtyTaskRunner/RemoteTaskRunner
    // fazem isso). Se inverter, o store assina Stream.empty() pra sempre.
    runner.emitRunningBeforeRegister('t', pid: 9);
    runner._running['t'] = StreamController<String>.broadcast(sync: true);
    runner.write('t', 'lost\r\n');
    expect(screen('t'), isNot(contains('lost')));
  });
}
