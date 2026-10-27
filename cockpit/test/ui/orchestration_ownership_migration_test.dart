import 'dart:convert';

import 'package:cockpit/app/cockpit/domain/entities/orchestration_document.dart';
import 'package:cockpit/app/cockpit/ui/services/orchestration_ownership_migration.dart';
import 'package:cockpit/app/cockpit/ui/services/orchestration_restore_state.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> copy(Map<String, dynamic> value) =>
    (jsonDecode(jsonEncode(value)) as Map).cast<String, dynamic>();

class Fixture {
  final original = <String, dynamic>{
    'type': 'orchestration',
    'path': '/repo/old.orchestration',
  };
  final files = <String, String>{
    '/repo/old.orchestration': 'old file must be preserved',
  };
  Map<String, dynamic>? persisted;
  int checkpoints = 0, paths = 0, writes = 0, seeds = 0;
  int? failCheckpoint;
  bool crashAfterCreate = false;
  bool failCreate = false;
  bool createRace = false;
  final operations = <String>[];

  OrchestrationOwnershipMigration get migration =>
      OrchestrationOwnershipMigration(
        checkpoint: (state) async {
          operations.add('checkpoint');
          if (++checkpoints == failCheckpoint) throw StateError('disk full');
          persisted = copy(state);
        },
        read: (file) async => files[file],
        createNew: (file, text) async {
          operations.add('create');
          expect(persisted?['ownershipMigration'], isNotNull);
          if (failCreate) throw StateError('disconnected');
          if (createRace) {
            createRace = false;
            files[file] = 'someone else created this';
            return false;
          }
          if (files.containsKey(file)) return false;
          files[file] = text;
          writes++;
          if (crashAfterCreate) {
            crashAfterCreate = false;
            throw StateError('process died after file creation');
          }
          return true;
        },
        newPath: () => '/repo/new-${++paths}.orc',
        validDestination: (file) => file.startsWith('/repo/new-'),
        seed: () {
          seeds++;
          var id = 0;
          return OrchestrationDocument.defaultTerminals(
            newId: () => 'fresh-$seeds-${++id}',
          );
        },
      );
  Future<Map<String, dynamic>> run() =>
      migration.migrate(persisted ?? original);
}

void main() {
  test(
    'checkpoints first, starts clean and never reads/imports old tabs or file',
    () async {
      final f = Fixture();
      final before = copy(f.original);
      final result = await f.run();
      expect(f.operations.first, 'checkpoint');
      expect(result['path'], '/repo/new-1.orc');
      expect(result['bindings'], isEmpty);
      expect(result['sessions'], isEmpty);
      final restored = OrchestrationRestoreState.parse(
        result,
        instanceId: 'app',
        projectId: 'repo',
      );
      expect(restored.document!.boxes.length, 3);
      expect(
        restored.document!.boxes.every((b) => b.box.harness.isEmpty),
        isTrue,
      );
      expect(restored.document!.boxes.every((b) => b.box.role.isEmpty), isTrue);
      expect(f.files['/repo/old.orchestration'], 'old file must be preserved');
      expect(f.original, before);
      expect(f.persisted, result);
    },
  );
  for (final checkpoint in [1, 2, 3]) {
    test(
      'recovers a crash at checkpoint $checkpoint without duplicate files',
      () async {
        final f = Fixture()..failCheckpoint = checkpoint;
        await expectLater(f.run(), throwsStateError);
        if (checkpoint == 1) expect(f.writes, 0);
        f.failCheckpoint = null;
        final result = await f.run();
        expect(f.writes, 1);
        expect(
          f.files.keys
              .where((file) => file != '/repo/old.orchestration')
              .length,
          1,
        );
        expect(result['ownershipVersion'], 2);
        expect(
          f.files['/repo/old.orchestration'],
          'old file must be preserved',
        );
      },
    );
  }
  test(
    'recovers creation before journal acknowledgement without overwriting',
    () async {
      final f = Fixture()..crashAfterCreate = true;
      await expectLater(f.run(), throwsStateError);
      final reserved =
          (f.persisted!['ownershipMigration'] as Map)['targetPath'];
      final result = await f.run();
      expect(result['path'], reserved);
      expect(f.writes, 1);
      expect(f.seeds, 1);
    },
  );
  test(
    'keeps a conflicting file and checkpoints a fresh destination',
    () async {
      final f = Fixture()..files['/repo/new-1.orc'] = 'unrelated file';
      final result = await f.run();
      expect(result['path'], '/repo/new-2.orc');
      expect(f.files['/repo/new-1.orc'], 'unrelated file');
      expect(f.writes, 1);
    },
  );
  test('exclusive create losing a race never overwrites the winner', () async {
    final f = Fixture()..createRace = true;
    final result = await f.run();
    expect(result['path'], '/repo/new-2.orc');
    expect(f.files['/repo/new-1.orc'], 'someone else created this');
    expect(f.writes, 1);
  });
  test(
    'host failure preserves the reservation for an explicit retry',
    () async {
      final f = Fixture()..failCreate = true;
      await expectLater(f.run(), throwsStateError);
      expect(f.writes, 0);
      final journal = copy(f.persisted!);
      f.failCreate = false;
      final result = await f.run();
      expect(
        result['path'],
        (journal['ownershipMigration'] as Map)['targetPath'],
      );
      expect(f.seeds, 1);
    },
  );
  test(
    'completed local snapshot retries its checkpoint without creating files',
    () async {
      final f = Fixture();
      final result = await f.run();
      f.failCheckpoint = f.checkpoints + 1;
      await expectLater(f.migration.migrate(result), throwsStateError);
      expect(f.writes, 1);
      f.failCheckpoint = null;
      expect(await f.migration.migrate(result), result);
      expect(f.writes, 1);
    },
  );
  test(
    'confirmed created file with invalid external edits reports error without overwriting',
    () async {
      final f = Fixture()..failCheckpoint = 3;
      await expectLater(f.run(), throwsStateError);
      final target =
          (f.persisted!['ownershipMigration'] as Map)['targetPath'] as String;
      f.files[target] = '{invalid';
      f.failCheckpoint = null;
      await expectLater(f.run(), throwsFormatException);
      expect(f.files[target], '{invalid');
      expect(f.writes, 1);
    },
  );
  test(
    'invalid journal, unsupported version and outside destination have no file side effect',
    () async {
      final f = Fixture();
      await expectLater(
        f.migration.migrate({...f.original, 'ownershipVersion': 99}),
        throwsFormatException,
      );
      await expectLater(
        f.migration.migrate({
          ...f.original,
          'ownershipMigration': {'version': 99},
        }),
        throwsFormatException,
      );
      await expectLater(
        f.migration.migrate({
          ...f.original,
          'ownershipMigration': {
            'version': 1,
            'sourcePath': f.original['path'],
            'targetPath': '/other/new.orchestration',
            'document': const OrchestrationDocument().encode(),
          },
        }),
        throwsFormatException,
      );
      expect(f.checkpoints, 0);
      expect(f.writes, 0);
    },
  );
}
