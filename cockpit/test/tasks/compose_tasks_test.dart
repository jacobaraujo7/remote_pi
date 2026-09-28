import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/cockpit/data/tasks/compose_tasks.dart';
import 'package:cockpit/app/cockpit/domain/entities/task_definition.dart';
import 'package:cockpit/app/core/data/jsonc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ComposeFileParser', () {
    late Directory tmp;
    setUp(
      () async => tmp = await Directory.systemTemp.createTemp('compose_tasks'),
    );
    tearDown(() => tmp.delete(recursive: true));

    test('accepts a non-empty services map', () async {
      final file = File('${tmp.path}/compose.yaml')
        ..writeAsStringSync(
          'services:\n  api:\n    image: api\n  custom-name: {}\n',
        );
      final parsed = await const ComposeFileParser().parse(file.path, tmp.path);
      expect(parsed?.services, ['api', 'custom-name']);
    });

    test('rejects invalid, empty, and outside files', () async {
      final invalid = File('${tmp.path}/bad.yml')
        ..writeAsStringSync('services: [');
      final empty = File('${tmp.path}/empty.yaml')
        ..writeAsStringSync('services: {}');
      final outside = File('${Directory.systemTemp.path}/outside-compose.yaml')
        ..writeAsStringSync('services:\n  api: {}');
      expect(
        await const ComposeFileParser().parse(invalid.path, tmp.path),
        isNull,
      );
      expect(
        await const ComposeFileParser().parse(empty.path, tmp.path),
        isNull,
      );
      expect(
        await const ComposeFileParser().parse(outside.path, tmp.path),
        isNull,
      );
      outside.deleteSync();
    });

    test('uses an including parent as the execution file', () async {
      final childDir = Directory('${tmp.path}/docker')..createSync();
      final child = File('${childDir.path}/compose.yaml')
        ..writeAsStringSync('services:\n  api: {}\n');
      final parent = File('${tmp.path}/compose.yaml')
        ..writeAsStringSync(
          'include:\n  - path: docker/compose.yaml\n    project_directory: .\n',
        );
      final parsed = await const ComposeFileParser().parse(
        child.path,
        tmp.path,
      );
      expect(parsed?.path, parent.absolute.path);
      expect(parsed?.services, ['api']);
    });
  });

  test('generator creates canonical profiles for integrated engine', () {
    final map = const ComposeTaskGenerator().taskMap(
      ComposeEngine.docker,
      '/repo/infra/compose.yml',
      'api',
      '/repo',
    );
    expect(map['command'], 'docker');
    expect(map['args'], ['compose', '-f', 'compose.yml']);
    expect(map['cwd'], 'infra');
    expect(map['kind'], 'watch');
    expect(map['preview'], false);
    expect((map['profiles'] as List).map((e) => e['name']), [
      'up',
      'build',
      'recreate',
      'recreate-deps',
    ]);
  });

  group('ComposeTaskRecognizer', () {
    TaskDefinition def(
      String command,
      List<String> args,
      List<String> profile,
    ) => TaskDefinition(
      id: 'json:api',
      label: 'api',
      cwd: '/repo',
      command: command,
      args: args,
      profiles: [TaskProfile(name: 'up', args: profile)],
    );

    test('recognizes integrated, legacy, absolute and --file forms', () {
      const r = ComposeTaskRecognizer();
      expect(
        r
            .recognize(
              def(
                '/usr/bin/docker',
                ['compose', '--file=compose.yml'],
                ['up', '-d', 'api'],
              ),
            )
            ?.service,
        'api',
      );
      expect(
        r
            .recognize(
              def('podman-compose', ['--file', '/x/c.yml'], ['build', 'api']),
            )
            ?.engine,
        ComposeEngine.podmanLegacy,
      );
    });

    test('rejects multiple services and missing file', () {
      const r = ComposeTaskRecognizer();
      expect(
        r.recognize(
          def('docker', ['compose', '-f', 'c.yml'], ['up', 'api', 'db']),
        ),
        isNull,
      );
      expect(r.recognize(def('docker', ['compose'], ['up', 'api'])), isNull);
    });
  });

  test(
    'JSONC merger preserves comments/manual tasks and reports conflicts',
    () {
      const source = '''{
  // keep this comment
  "extra": true,
  "tasks": [
    {"label":"manual", "command":"echo", "args":["ok"]},
  ],
}''';
      final generated = const ComposeTaskGenerator().taskMap(
        ComposeEngine.docker,
        '/repo/compose.yml',
        'manual',
        '/repo',
      );
      final added = const ComposeTaskGenerator().taskMap(
        ComposeEngine.docker,
        '/repo/compose.yml',
        'api',
        '/repo',
      );
      final result = const ComposeTasksJsonMerger().merge(source, [
        generated,
        added,
      ], '/repo');
      expect(result.conflicts, ['manual']);
      expect(result.content, contains('// keep this comment'));
      final decoded = jsonDecode(stripJsonc(result.content)) as Map;
      expect(decoded['extra'], true);
      expect((decoded['tasks'] as List).length, 2);
    },
  );

  test('invalid JSONC is not mergeable', () {
    expect(
      () => const ComposeTasksJsonMerger().merge('{bad', const [], '/repo'),
      throwsFormatException,
    );
  });

  test('regeneration resets profiles and preserves removed services', () {
    final generator = const ComposeTaskGenerator();
    final oldApi = generator.taskMap(
      ComposeEngine.docker,
      '/repo/compose.yml',
      'api',
      '/repo',
    );
    // Simulates a valid manual edit until the next explicit regeneration.
    (oldApi['profiles'] as List).first['args'] = ['up', 'api'];
    final removed = generator.taskMap(
      ComposeEngine.docker,
      '/repo/compose.yml',
      'old-worker',
      '/repo',
    );
    final source = const JsonEncoder.withIndent(' ').convert({
      'tasks': [oldApi, removed],
    });
    final freshApi = generator.taskMap(
      ComposeEngine.docker,
      '/repo/compose.yml',
      'api',
      '/repo',
    );
    final result = const ComposeTasksJsonMerger().merge(source, [
      freshApi,
    ], '/repo');
    final tasks =
        (jsonDecode(stripJsonc(result.content)) as Map)['tasks'] as List;
    expect(tasks, hasLength(2));
    final api = tasks.cast<Map>().singleWhere((t) => t['label'] == 'api');
    expect((api['profiles'] as List).first['args'], ['up', '-d', 'api']);
    expect(tasks.cast<Map>().any((t) => t['label'] == 'old-worker'), isTrue);
  });

  test('same label from another Compose file is a conflict', () {
    final generator = const ComposeTaskGenerator();
    final source = jsonEncode({
      'tasks': [
        generator.taskMap(
          ComposeEngine.docker,
          '/repo/a/compose.yml',
          'api',
          '/repo',
        ),
      ],
    });
    final other = generator.taskMap(
      ComposeEngine.podman,
      '/repo/b/compose.yml',
      'api',
      '/repo',
    );
    final result = const ComposeTasksJsonMerger().merge(source, [
      other,
    ], '/repo');
    expect(result.conflicts, ['api']);
    expect(result.content, contains('docker'));
    expect(result.content, isNot(contains('podman')));
  });

  test('regeneration migrates an included child to its parent file', () async {
    final tmp = await Directory.systemTemp.createTemp('compose_include_merge');
    addTearDown(() => tmp.delete(recursive: true));
    final childDir = Directory('${tmp.path}/docker')..createSync();
    final child = File('${childDir.path}/compose.yaml')
      ..writeAsStringSync('services:\n  api: {}\n');
    final parent = File('${tmp.path}/compose.yaml')
      ..writeAsStringSync('include:\n  - path: docker/compose.yaml\n');
    final generator = const ComposeTaskGenerator();
    final source = jsonEncode({
      'tasks': [
        generator.taskMap(ComposeEngine.docker, child.path, 'api', tmp.path),
      ],
    });
    final migrated = generator.taskMap(
      ComposeEngine.docker,
      parent.path,
      'api',
      tmp.path,
    );
    final result = const ComposeTasksJsonMerger().merge(source, [
      migrated,
    ], tmp.path);
    expect(result.conflicts, isEmpty);
    final task = ((jsonDecode(result.content) as Map)['tasks'] as List).single;
    expect(task['cwd'], '.');
    expect(task['args'], ['compose', '-f', 'compose.yaml']);
  });
}
