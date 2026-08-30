import 'dart:io';

import 'package:cockpit/app/cockpit/data/repositories/json_dismissed_update_store.dart';
import 'package:cockpit/app/cockpit/data/repositories/json_project_repository.dart';
import 'package:cockpit/app/cockpit/data/repositories/json_realm_repository.dart';
import 'package:cockpit/app/cockpit/data/repositories/json_workspace_layout_store.dart';
import 'package:cockpit/app/cockpit/domain/entities/project.dart';
import 'package:cockpit/app/cockpit/domain/entities/realm.dart';
import 'package:cockpit/app/core/data/repositories/json_settings_store.dart';
import 'package:cockpit/app/core/data/setup/json_state_store.dart';
import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

/// Impls JSON contra os contratos de domain — mesma semântica das antigas
/// impls Hive (roundtrip, defaults e migrações de leitura).
void main() {
  late Directory tmp;
  late JsonStateStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('json_stores_test');
    store = await JsonStateStore.open(tmp.path, 'box');
  });

  tearDown(() async {
    JsonStateStore.resetCacheForTesting();
    await tmp.delete(recursive: true);
  });

  group('JsonSettingsStore', () {
    test('roundtrip save/load', () async {
      final s = JsonSettingsStore(store);
      await s.save(const AppSettings(enableAgent: true));
      final loaded = await s.load();
      expect(loaded.enableAgent, isTrue);
    });

    test('sem registro → defaults', () async {
      final loaded = await JsonSettingsStore(store).load();
      expect(loaded, const AppSettings());
    });

    test('registro sem enableAgent → migra ligando a flag', () async {
      final json = const AppSettings().toJson()..remove('enableAgent');
      await store.put('app', json);
      final loaded = await JsonSettingsStore(store).load();
      expect(loaded.enableAgent, isTrue);
    });
  });

  group('JsonProjectRepository', () {
    test('roundtrip + ordenação + last-selected por realm', () async {
      final repo = JsonProjectRepository(store);
      final a = Project(
        id: 'a',
        name: 'A',
        path: '/x/a',
        colorValue: 0xFF2F6FF0,
        createdAt: DateTime.fromMillisecondsSinceEpoch(2),
        order: 1,
      );
      final b = Project(
        id: 'b',
        name: 'B',
        path: '/x/b',
        colorValue: 0xFF2F6FF0,
        createdAt: DateTime.fromMillisecondsSinceEpoch(1),
      );
      await repo.save(a);
      await repo.save(b);
      expect((await repo.all()).map((x) => x.id), ['b', 'a']);

      await repo.saveLastSelected(Realm.defaultId, 'a');
      expect(await repo.loadLastSelected(Realm.defaultId), 'a');
      expect(await repo.loadLastSelected('outro'), isNull);

      await repo.remove('a');
      expect((await repo.all()).map((x) => x.id), ['b']);
    });
  });

  group('JsonRealmRepository', () {
    test('store vazio → cria e persiste o realm Default', () async {
      final repo = JsonRealmRepository(store);
      final realms = await repo.all();
      expect(realms.single.isDefault, isTrue);
      expect(await repo.loadActive(), Realm.defaultId);
    });
  });

  group('JsonWorkspaceLayoutStore', () {
    test('roundtrip como String JSON', () async {
      final s = JsonWorkspaceLayoutStore(store);
      await s.save('p1', {
        'tree': {'a': 1},
      });
      expect(await s.load('p1'), {
        'tree': {'a': 1},
      });
      await s.remove('p1');
      expect(await s.load('p1'), isNull);
    });

    test(
      'loadAll devolve TODOS os layouts salvos, inclusive de forks',
      () async {
        // O GC do scrollback depende disto: os forks de worktree entram na lista
        // de projetos depois do boot, então varrer só o que está em memória
        // apagaria o scrollback dos terminais deles.
        final s = JsonWorkspaceLayoutStore(store);
        await s.save('root', {'tree': {}});
        await s.save('root::/repo/.cockpit/worktrees/fix', {'tree': {}});

        final all = await s.loadAll();
        expect(
          all.keys,
          containsAll(<String>['root', 'root::/repo/.cockpit/worktrees/fix']),
        );
      },
    );

    test('documento corrompido fica de fora do loadAll', () async {
      final s = JsonWorkspaceLayoutStore(store);
      await store.put('quebrado', 'nao é json');
      await s.save('ok', {'tree': {}});
      expect((await s.loadAll()).keys, ['ok']);
    });
  });

  group('JsonDismissedUpdateStore', () {
    test('roundtrip', () async {
      final s = JsonDismissedUpdateStore(store);
      expect(s.dismissedVersion(), isNull);
      await s.dismiss('1.2.3');
      expect(s.dismissedVersion(), '1.2.3');
    });
  });
}
