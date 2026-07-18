import 'dart:io';

import 'package:cockpit/app/cockpit/data/repositories/hive_project_repository.dart';
import 'package:cockpit/app/cockpit/data/repositories/project_schema_migrator.dart';
import 'package:cockpit/app/cockpit/domain/entities/realm.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory tmp;
  late Box<dynamic> projects;
  late Box<dynamic> layouts;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('migrator_test');
    Hive.init(tmp.path);
    projects = await Hive.openBox<dynamic>('projects_test');
    layouts = await Hive.openBox<dynamic>('layouts_test');
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await tmp.delete(recursive: true);
  });

  Map<String, dynamic> legacyProject(String path, {String name = 'proj'}) =>
      <String, dynamic>{
        'id': path, // schema antigo: id == path
        'name': name,
        'path': path,
        'color': 0xFF2F6FF0,
        'createdAt': 1000,
        'order': 0,
      };

  test('re-keya projeto legado pra UUID e move layout junto', () async {
    const path = '/Users/x/proj';
    await projects.put(path, legacyProject(path));
    await layouts.put(path, '{"tree":{}}');
    await projects.put(HiveProjectRepository.lastSelectedPrefix, path);

    await const ProjectSchemaMigrator().run(projects, layouts);

    // Chave antiga sumiu; a nova é um UUID com o mesmo conteúdo + realm.
    expect(projects.get(path), isNull);
    final maps = projects.values.whereType<Map<dynamic, dynamic>>().toList();
    expect(maps, hasLength(1));
    final migrated = maps.single;
    final newId = migrated['id'] as String;
    expect(newId, isNot(path));
    expect(newId, matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(migrated['path'], path);
    expect(migrated['realm'], Realm.defaultId);
    expect(migrated['name'], 'proj');

    // Layout re-keyed.
    expect(layouts.get(path), isNull);
    expect(layouts.get(newId), '{"tree":{}}');

    // Last-selected legado → per-realm do Default, apontando pro id novo.
    expect(projects.get(HiveProjectRepository.lastSelectedPrefix), isNull);
    expect(
      projects.get(
        '${HiveProjectRepository.lastSelectedPrefix}::${Realm.defaultId}',
      ),
      newId,
    );
  });

  test('é idempotente: segunda passada não muda nada', () async {
    const path = '/Users/x/proj';
    await projects.put(path, legacyProject(path));
    await const ProjectSchemaMigrator().run(projects, layouts);
    final after1 = Map<dynamic, dynamic>.of(
      projects.values.whereType<Map<dynamic, dynamic>>().single,
    );

    await const ProjectSchemaMigrator().run(projects, layouts);
    final after2 = projects.values.whereType<Map<dynamic, dynamic>>().single;
    expect(after2, after1); // mesmo id (não re-gerou UUID)
  });

  test(
    'last-selected legado apontando pro Cockpit sintético é preservado',
    () async {
      await projects.put(
        HiveProjectRepository.lastSelectedPrefix,
        '__cockpit__',
      );

      await const ProjectSchemaMigrator().run(projects, layouts);

      expect(
        projects.get(
          '${HiveProjectRepository.lastSelectedPrefix}::${Realm.defaultId}',
        ),
        '__cockpit__',
      );
      expect(projects.get(HiveProjectRepository.lastSelectedPrefix), isNull);
    },
  );

  test('registro já migrado convive com legado (migração parcial)', () async {
    const legacyPath = '/Users/x/legacy';
    await projects.put(legacyPath, legacyProject(legacyPath));
    const doneId = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
    await projects.put(doneId, <String, dynamic>{
      'id': doneId,
      'name': 'done',
      'path': '/Users/x/done',
      'color': 0,
      'createdAt': 0,
      'order': 1,
      'realm': 'outro-realm',
    });

    await const ProjectSchemaMigrator().run(projects, layouts);

    final maps = projects.values.whereType<Map<dynamic, dynamic>>().toList();
    expect(maps, hasLength(2));
    final done = maps.singleWhere((m) => m['id'] == doneId);
    expect(done['realm'], 'outro-realm'); // intocado
    final migrated = maps.singleWhere((m) => m['id'] != doneId);
    expect(migrated['path'], legacyPath);
    expect(migrated['realm'], Realm.defaultId);
  });
}
