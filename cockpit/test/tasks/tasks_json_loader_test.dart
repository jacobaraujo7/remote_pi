import 'dart:io';

import 'package:cockpit/app/cockpit/data/tasks/tasks_json_loader.dart';
import 'package:cockpit/app/cockpit/domain/entities/task_definition.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cockpit/app/cockpit/data/tasks/project_paths.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('tasks_json_test');
    await Directory('${tmp.path}/.cockpit').create();
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<void> write(String json) =>
      File('${tmp.path}/.cockpit/tasks.json').writeAsString(json);

  test('arquivo ausente → lista vazia', () async {
    expect(await const TasksJsonLoader().load(tmp.path), isEmpty);
  });

  test('JSON malformado → lista vazia (silencioso)', () async {
    await write('{ not json');
    expect(await const TasksJsonLoader().load(tmp.path), isEmpty);
  });

  test('cwd per-task resolve relativo à raiz do workspace', () async {
    await write('''
      { "tasks": [
        { "label": "app", "cwd": "app", "command": "flutter", "args": ["run"] },
        { "label": "api", "cwd": "backend", "command": "dart", "args": ["run"] }
      ] }
    ''');
    final tasks = await const TasksJsonLoader().load(tmp.path);
    final app = tasks.firstWhere((t) => t.label == 'app');
    final api = tasks.firstWhere((t) => t.label == 'api');
    expect(app.cwd, joinPath(tmp.path, 'app'));
    expect(api.cwd, joinPath(tmp.path, 'backend'));
    expect(app.id, 'json:app');
    expect(app.source, TaskSource.manual);
  });

  test('cwd omitido → raiz; top-level cwd vira default', () async {
    await write('''
      { "cwd": "app", "tasks": [
        { "label": "run", "command": "flutter", "args": ["run"] },
        { "label": "root", "cwd": "", "command": "make", "args": [] }
      ] }
    ''');
    final tasks = await const TasksJsonLoader().load(tmp.path);
    // "run" sem cwd → herda o default top-level "app".
    expect(
      tasks.firstWhere((t) => t.label == 'run').cwd,
      joinPath(tmp.path, 'app'),
    );
    // "root" com cwd vazio → raiz do workspace.
    expect(tasks.firstWhere((t) => t.label == 'root').cwd, tmp.path);
  });

  test('parseia kind, interactiveKeys, watch, profiles, patterns', () async {
    await write('''
      { "tasks": [{
        "label": "run", "cwd": "app", "command": "flutter", "args": ["run"],
        "kind": "watch",
        "interactiveKeys": [
          { "key": "r", "label": "Hot reload", "icon": "refresh", "primary": true },
          { "key": "q", "label": "Quit" }
        ],
        "watch": { "paths": ["lib"], "ignore": ["build"], "onChange": "Hot reload", "debounceMs": 500 },
        "progressPatterns": [ { "begin": "reloading", "end": "Reloaded" } ],
        "profiles": [ { "name": "dev", "args": ["--flavor", "dev"], "env": { "X": "1" } } ]
      }] }
    ''');
    final t = (await const TasksJsonLoader().load(tmp.path)).single;
    expect(t.kind, TaskKind.watch);
    expect(t.interactiveKeys.length, 2);
    expect(t.interactiveKeys.first.primary, isTrue);
    expect(t.interactiveKeys[1].primary, isFalse);
    expect(t.watch?.debounceMs, 500);
    expect(t.watch?.onChange, 'Hot reload');
    expect(t.progressPatterns.single.end, 'Reloaded');
    expect(t.profiles.single.name, 'dev');
    expect(t.profiles.single.args, ['--flavor', 'dev']);
    expect(t.profiles.single.env, {'X': '1'});
  });

  test(
    'task env is inherited and profiles override only matching keys',
    () async {
      await write('''{
      "tasks": [{
        "label": "api", "command": "npm",
        "env": {"API_URL": "https://api.example.com", "LOG_LEVEL": "info"},
        "profiles": [
          {"name": "development", "env": {"API_URL": "http://localhost:3000"}},
          {"name": "production", "env": {"LOG_LEVEL": "error"}},
          {"name": "inherited"}
        ]
      }]
    }''');
      final task = (await const TasksJsonLoader().load(tmp.path)).single;
      expect(task.resolveEnv(task.profiles[0]), {
        'API_URL': 'http://localhost:3000',
        'LOG_LEVEL': 'info',
      });
      expect(task.resolveEnv(task.profiles[1]), {
        'API_URL': 'https://api.example.com',
        'LOG_LEVEL': 'error',
      });
      expect(task.resolveEnv(task.profiles[2]), task.env);
      final resolved = task.resolveEnv(null);
      expect(resolved, task.env);
      resolved['LOG_LEVEL'] = 'changed';
      expect(task.env['LOG_LEVEL'], 'info');
      expect(task.profiles[0].env, {'API_URL': 'http://localhost:3000'});
    },
  );

  test(
    'absent, empty and invalid env retain existing tolerant behavior',
    () async {
      await write('''{"tasks": [
      {"label": "absent", "command": "npm"},
      {"label": "empty", "command": "npm", "env": {}, "profiles": [{"name": "empty", "env": {}}]},
      {"label": "invalid", "command": "npm", "env": [], "profiles": [{"name": "invalid", "env": false}]},
      {"label": "legacy", "command": "npm", "profiles": [{"name": "dev", "env": {"PORT": "3000"}}]}
    ]}''');
      final tasks = await const TasksJsonLoader().load(tmp.path);
      for (final task in tasks.take(3)) {
        expect(task.resolveEnv(null), isEmpty);
        for (final profile in task.profiles) {
          expect(task.resolveEnv(profile), isEmpty);
        }
      }
      expect(tasks.last.resolveEnv(tasks.last.profiles.single), {
        'PORT': '3000',
      });
      expect(tasks.last.resolveEnv(null), isEmpty);
    },
  );

  test('platforms filtra pelo SO do host (string ou lista)', () async {
    await write('''
      { "tasks": [
        { "label": "all", "command": "make" },
        { "label": "win-only", "command": "make", "platforms": "windows" },
        { "label": "mac-only", "command": "make", "platforms": ["macos"] },
        { "label": "desktop", "command": "make", "platforms": ["Windows", "linux"] },
        { "label": "broken", "command": "make", "platforms": 42 }
      ] }
    ''');
    final onWin = await const TasksJsonLoader(hostOs: 'windows').load(tmp.path);
    expect(
      onWin.map((t) => t.label),
      unorderedEquals(['all', 'win-only', 'desktop', 'broken']),
    );
    final onMac = await const TasksJsonLoader(hostOs: 'macos').load(tmp.path);
    expect(
      onMac.map((t) => t.label),
      unorderedEquals(['all', 'mac-only', 'broken']),
    );
  });

  test(
    'sem preview/previewOpen → default retrocompatível (abre sempre)',
    () async {
      await write('{ "tasks": [ { "label": "api", "command": "go" } ] }');
      final task = (await const TasksJsonLoader().load(tmp.path)).single;
      expect(task.previewEnabled, isTrue);
      expect(task.previewUrl, isNull);
      expect(task.previewOpen, TaskPreviewOpen.always);
    },
  );

  test('preview string vira URL fixa; preview false desliga', () async {
    await write('''
      { "tasks": [
        { "label": "fixa", "command": "go", "preview": "http://localhost:8080" },
        { "label": "off", "command": "go", "preview": false }
      ] }
    ''');
    final tasks = await const TasksJsonLoader().load(tmp.path);
    final fixa = tasks.firstWhere((t) => t.label == 'fixa');
    final off = tasks.firstWhere((t) => t.label == 'off');
    expect(fixa.previewUrl, 'http://localhost:8080');
    expect(fixa.previewEnabled, isTrue);
    expect(off.previewEnabled, isFalse);
    expect(off.previewUrl, isNull);
  });

  test('previewOpen aceita always/start/never', () async {
    await write('''
      { "tasks": [
        { "label": "a", "command": "go", "previewOpen": "always" },
        { "label": "s", "command": "go", "previewOpen": "start" },
        { "label": "n", "command": "go", "previewOpen": "never" }
      ] }
    ''');
    final tasks = await const TasksJsonLoader().load(tmp.path);
    expect(
      {for (final t in tasks) t.label: t.previewOpen},
      {
        'a': TaskPreviewOpen.always,
        's': TaskPreviewOpen.start,
        'n': TaskPreviewOpen.never,
      },
    );
  });

  test('previewOpen inválido ou de tipo errado → always', () async {
    await write('''
      { "tasks": [
        { "label": "typo", "command": "go", "previewOpen": "onstart" },
        { "label": "tipo", "command": "go", "previewOpen": true }
      ] }
    ''');
    final tasks = await const TasksJsonLoader().load(tmp.path);
    expect(
      tasks.map((t) => t.previewOpen),
      everyElement(TaskPreviewOpen.always),
    );
  });

  test('preview false vence previewOpen always', () async {
    await write('''
      { "tasks": [
        { "label": "off", "command": "go", "preview": false, "previewOpen": "always" }
      ] }
    ''');
    final task = (await const TasksJsonLoader().load(tmp.path)).single;
    expect(task.previewEnabled, isFalse);
    expect(task.previewOpen, TaskPreviewOpen.always);
  });

  test('task sem label ou command é ignorada', () async {
    await write('''
      { "tasks": [
        { "command": "x" },
        { "label": "ok", "command": "y" }
      ] }
    ''');
    final tasks = await const TasksJsonLoader().load(tmp.path);
    expect(tasks.map((t) => t.label), ['ok']);
  });
}
