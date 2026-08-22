import 'dart:async';

import 'package:cockpit/app/cockpit/domain/contracts/task_runner_gateway.dart';
import 'package:cockpit/app/cockpit/domain/contracts/terminal_scrollback_store.dart';
import 'package:cockpit/app/cockpit/domain/entities/task_definition.dart';
import 'package:cockpit/app/cockpit/domain/entities/task_run.dart';
import 'package:cockpit/app/cockpit/ui/session/task_terminal_store.dart';
import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runner de mentira: só bombeia runs e output, que é o que o store consome.
class FakeTaskRunner implements TaskRunnerGateway {
  final _runs = StreamController<TaskRun>.broadcast();
  final _output = StreamController<String>.broadcast();

  void emitRun(TaskRun run) => _runs.add(run);
  void emitOutput(String data) => _output.add(data);

  @override
  Stream<TaskRun> runs() => _runs.stream;

  @override
  Stream<String> output(String taskId) => _output.stream;

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

class FakeScrollbackStore implements TerminalScrollbackStore {
  String? saved;

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
  }) async => saved = contents;

  @override
  Future<void> delete({
    required String projectId,
    required String sessionId,
  }) async {}

  @override
  Future<void> pruneExcept(Set<String> keep) async {}
}

TaskRun running(int pid) =>
    TaskRun(taskId: 'json:api', status: TaskRunStatus.running, pid: pid);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeTaskRunner runner;
  late FakeScrollbackStore scrollback;
  late TaskTerminalStore store;

  setUp(() {
    runner = FakeTaskRunner();
    scrollback = FakeScrollbackStore();
    store = TaskTerminalStore(runner, scrollback)
      // xterm é Dart puro — o Ghostty exigiria a dylib nativa no teste.
      ..setDefaultEngine(TerminalEngine.xterm);
  });

  tearDown(() => store.dispose());

  Future<void> pump() => Future<void>.delayed(Duration.zero);

  test('output JSON chega colorido ao terminal e ao scrollback', () async {
    runner.emitRun(running(1));
    await pump();
    runner.emitOutput('{"level":"error","msg":"db down"}\n');
    await pump();
    await store.flushAll();

    expect(scrollback.saved, contains('\x1b[91m"error"\x1b[0m'));
    expect(scrollback.saved, contains('\x1b[97m"db down"\x1b[0m'));
  });

  test('output com ANSI próprio passa intacto', () async {
    runner.emitRun(running(1));
    await pump();
    runner.emitOutput('\x1b[32mBuilt in 1.2s\x1b[0m\n');
    await pump();
    await store.flushAll();

    expect(scrollback.saved, '\x1b[32mBuilt in 1.2s\x1b[0m\n');
  });

  test('linha JSON sem \\n é solta crua quando o run termina', () async {
    runner.emitRun(running(1));
    await pump();
    runner.emitOutput('{"level":"info"'); // processo morreu no meio
    await pump();
    expect(scrollback.saved, isNull); // retida

    runner.emitRun(
      const TaskRun(taskId: 'json:api', status: TaskRunStatus.failed),
    );
    await pump();
    await store.flushAll();

    expect(scrollback.saved, '{"level":"info"');
  });
}
