import 'dart:async';
import 'dart:io';

import 'package:cockpit/app/cockpit/data/tasks/task_discovery_impl.dart';
import 'package:cockpit/app/cockpit/domain/contracts/task_runner_gateway.dart';
import 'package:cockpit/app/cockpit/domain/entities/task_run.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/tasks_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

class IdleTaskRunner implements TaskRunnerGateway {
  @override
  Stream<TaskRun> runs() => const Stream.empty();

  @override
  TaskRun runOf(String taskId) => TaskRun.idleFor(taskId);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const taskConfig = '''{
  // Keep this comment and trailing commas.
  "tasks": [{"label": "API", "command": "echo", "cwd": "backend",}],
}
''';

void main() {
  late Directory temp;
  late Directory source;
  late Directory worktree;
  late TasksViewModel vm;
  File config(Directory dir) => File('${dir.path}/.cockpit/tasks.json');

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('tasks-import-');
    source = await Directory('${temp.path}/source').create();
    worktree = await Directory('${temp.path}/worktree').create();
    vm = TasksViewModel(TaskDiscoveryImpl(const []), IdleTaskRunner());
  });

  tearDown(() async {
    vm.dispose();
    await temp.delete(recursive: true);
  });

  Future<void> writeSource() async {
    await config(source).parent.create(recursive: true);
    await config(source).writeAsString(taskConfig);
  }

  Future<void> load() =>
      vm.loadFor(worktree.path, sourceWorkspaceCwd: source.path);

  for (final ignored in [false, true]) {
    test(
      'imports ${ignored ? 'ignored' : 'untracked'} JSONC verbatim',
      () async {
        final init = await Process.run('git', ['init', source.path]);
        expect(init.exitCode, 0);
        if (ignored) {
          await File('${source.path}/.gitignore').writeAsString('.cockpit/\n');
        }
        await writeSource();
        await load();
        expect(vm.tasks, isEmpty);
        expect(vm.canImport, isTrue);
        expect(await config(worktree).exists(), isFalse);

        await vm.importWorkspaceConfig();

        expect(
          await config(worktree).readAsBytes(),
          await config(source).readAsBytes(),
        );
        expect(vm.tasks.single.label, 'API');
        expect(vm.tasks.single.cwd, '${worktree.path}/backend');
        expect(vm.hasConfig, isTrue);
        expect(vm.canImport, isFalse);
        expect(vm.importing, isFalse);
        expect(vm.importNotice, isNull);
      },
    );
  }

  test('missing source creates nothing and allows retry', () async {
    await load();
    await vm.importWorkspaceConfig();
    expect(await config(worktree).parent.exists(), isFalse);
    expect(vm.importNotice, TaskImportNotice.sourceMissing);
    expect(vm.canImport, isTrue);
    await writeSource();
    await vm.importWorkspaceConfig();
    expect(vm.tasks, hasLength(1));
    expect(vm.importNotice, isNull);
  });

  test('import arms the watcher for later edits', () async {
    await writeSource();
    await load();
    await vm.importWorkspaceConfig();
    final updated = Completer<void>();
    vm.addListener(() {
      if (vm.tasks.singleOrNull?.label == 'Updated' && !updated.isCompleted) {
        updated.complete();
      }
    });
    await config(
      worktree,
    ).writeAsString(taskConfig.replaceFirst('API', 'Updated'));
    await updated.future.timeout(const Duration(seconds: 5));
    expect(await config(source).readAsString(), taskConfig);
  });

  test('read failure is reported without creating destination', () async {
    await writeSource();
    await load();
    final result = await Process.run('chmod', ['000', config(source).path]);
    expect(result.exitCode, 0);
    try {
      await vm.importWorkspaceConfig();
      expect(vm.importNotice, TaskImportNotice.failed);
      expect(await config(worktree).exists(), isFalse);
    } finally {
      await Process.run('chmod', ['600', config(source).path]);
    }
  }, skip: Platform.isWindows);

  for (final content in ['{"tasks": []}', 'invalid JSON']) {
    test('preserves existing config: $content', () async {
      await writeSource();
      await config(worktree).parent.create();
      await config(worktree).writeAsString(content);
      await load();
      expect(vm.canImport, isFalse);
      await vm.importWorkspaceConfig();
      expect(await config(worktree).readAsString(), content);
    });
  }

  test('rechecks destination created after discovery', () async {
    await writeSource();
    await load();
    await config(worktree).parent.create();
    await config(worktree).writeAsString('existing');
    await vm.importWorkspaceConfig();
    expect(await config(worktree).readAsString(), 'existing');
    expect(vm.hasConfig, isTrue);
  });

  test('write failure is reported and can be retried', () async {
    await writeSource();
    await load();
    final obstruction = File('${worktree.path}/.cockpit');
    await obstruction.writeAsString('not a directory');
    await vm.importWorkspaceConfig();
    expect(vm.importNotice, TaskImportNotice.failed);
    expect(vm.importing, isFalse);
    await obstruction.delete();
    await vm.importWorkspaceConfig();
    expect(vm.tasks, hasLength(1));
  });

  test(
    'duplicate clicks and example creation cannot replace the import',
    () async {
      await writeSource();
      await load();
      final pending = vm.importWorkspaceConfig();
      expect(vm.importing, isTrue);
      await vm.importWorkspaceConfig();
      await vm.createExampleConfig();
      await pending;
      expect(await config(worktree).readAsString(), taskConfig);
    },
  );

  test(
    'switching project keeps the original destination and new panel state',
    () async {
      await writeSource();
      await load();
      final other = await Directory('${temp.path}/other').create();
      final pending = vm.importWorkspaceConfig();
      await vm.loadFor(other.path);
      await pending;
      expect(await config(worktree).readAsString(), taskConfig);
      expect(await config(other).exists(), isFalse);
      expect(vm.tasks, isEmpty);
      expect(vm.hasConfig, isFalse);
      expect(vm.importNotice, isNull);
      expect(vm.importing, isFalse);
    },
  );

  test('root workspace and remote context cannot import', () async {
    await writeSource();
    await vm.loadFor(worktree.path);
    expect(vm.canImport, isFalse);
    final runner = IdleTaskRunner();
    vm.remoteContextFor = (_) =>
        (discovery: TaskDiscoveryImpl(const []), runner: runner);
    await load();
    expect(vm.canImport, isFalse);
    await vm.importWorkspaceConfig();
    expect(await config(worktree).exists(), isFalse);
  });
}
