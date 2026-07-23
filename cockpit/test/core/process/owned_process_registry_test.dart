import 'dart:io';

import 'package:cockpit/app/core/data/process/owned_process_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('owned_process_registry_test');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  File ownerFile(String category, int owner) => File(
    '${tmp.path}${Platform.pathSeparator}$category'
    '${Platform.pathSeparator}$owner.pids',
  );

  Future<void> seed(String category, int owner, List<int> children) async {
    final file = ownerFile(category, owner);
    await file.parent.create(recursive: true);
    await file.writeAsString('${children.join('\n')}\n');
  }

  test(
    'register/unregister ficam isolados por categoria e proprietário',
    () async {
      final agents = OwnedProcessRegistry(
        category: 'agents',
        rootPath: tmp.path,
        ownerPid: 101,
      );
      final tasks = OwnedProcessRegistry(
        category: 'tasks',
        rootPath: tmp.path,
        ownerPid: 101,
      );

      await agents.register(11);
      await agents.register(12);
      await tasks.register(21);
      await agents.unregister(11);

      expect(await ownerFile('agents', 101).readAsLines(), ['12']);
      expect(await ownerFile('tasks', 101).readAsLines(), ['21']);
    },
  );

  test('cleanOrphans limpa instância atual e proprietários mortos', () async {
    await seed('tasks', 101, [11]);
    await seed('tasks', 202, [22]);
    await seed('tasks', 303, [33]);
    final killed = <int>[];
    final registry = OwnedProcessRegistry(
      category: 'tasks',
      rootPath: tmp.path,
      ownerPid: 101,
      isProcessAlive: (owner) async => owner == 202,
      killProcess: killed.add,
    );

    await registry.cleanOrphans();

    expect(killed, unorderedEquals([11, 33]));
    expect(await ownerFile('tasks', 101).exists(), isFalse);
    expect(await ownerFile('tasks', 202).readAsLines(), ['22']);
    expect(await ownerFile('tasks', 303).exists(), isFalse);
  });

  test('Cockpit filho preserva a task do Cockpit pai vivo', () async {
    final parent = OwnedProcessRegistry(
      category: 'tasks',
      rootPath: tmp.path,
      ownerPid: 100,
    );
    await parent.register(999);
    final killed = <int>[];
    final child = OwnedProcessRegistry(
      category: 'tasks',
      rootPath: tmp.path,
      ownerPid: 200,
      isProcessAlive: (owner) async => owner == 100,
      killProcess: killed.add,
    );

    await child.cleanOrphans();

    expect(killed, isEmpty);
    expect(await ownerFile('tasks', 100).readAsLines(), ['999']);
  });

  test('falha ao verificar proprietário preserva seus processos', () async {
    await seed('lsp', 202, [22]);
    final killed = <int>[];
    final registry = OwnedProcessRegistry(
      category: 'lsp',
      rootPath: tmp.path,
      ownerPid: 101,
      isProcessAlive: (_) => throw const FileSystemException('ps unavailable'),
      killProcess: killed.add,
    );

    await registry.cleanOrphans();

    expect(killed, isEmpty);
    expect(await ownerFile('lsp', 202).readAsLines(), ['22']);
  });

  test('arquivo legado é consumido uma única vez', () async {
    final legacy = File('${tmp.path}${Platform.pathSeparator}agent-pids');
    await legacy.writeAsString('41\n42\ninvalid\n');
    final killed = <int>[];
    final registry = OwnedProcessRegistry(
      category: 'agents',
      rootPath: tmp.path,
      ownerPid: 101,
      legacyFiles: [legacy.path],
      killProcess: killed.add,
    );

    await registry.cleanOrphans();
    await registry.cleanOrphans();

    expect(killed, [41, 42]);
    expect(await legacy.exists(), isFalse);
  });
}
