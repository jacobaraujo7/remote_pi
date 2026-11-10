import 'dart:io';

import 'package:cockpit/app/cockpit/data/terminal/file_terminal_scrollback_store.dart';
import 'package:cockpit/app/core/data/diagnostics/diagnostics_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late List<DiagnosticsRecord> warnings;
  late void Function(DiagnosticsRecord)? previousSink;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('scrollback-prune-');
    warnings = [];
    previousSink = DiagnosticsLog.instance.telemetrySink;
    DiagnosticsLog.instance.telemetrySink = warnings.add;
  });
  tearDown(() async {
    DiagnosticsLog.instance.telemetrySink = previousSink;
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<File> write(String path) async {
    final file = File('${root.path}/$path');
    await file.parent.create(recursive: true);
    await file.writeAsString('history');
    return file;
  }

  test('missing root is harmless and does not warn', () async {
    await root.delete();
    await FileTerminalScrollbackStore(root: root).pruneExcept({});
    expect(warnings, isEmpty);
  });

  test(
    'keeps escaped session IDs and unrelated files without changing format',
    () async {
      final store = FileTerminalScrollbackStore(root: root);
      await store.save(
        projectId: 'project',
        sessionId: 'keep::a b',
        contents: 'kept',
      );
      final stale = await write('project/stale.log');
      final unrelated = await write('project/notes.txt');
      final temp = await write('project/stale.log.tmp');
      final nested = await write('project/subdirectory/unrelated.log');
      final topLevel = await write('top-level.log');

      await store.pruneExcept({'keep::a b'});

      expect(
        await store.load(projectId: 'project', sessionId: 'keep::a b'),
        'kept',
      );
      expect(await stale.exists(), isFalse);
      for (final file in [unrelated, temp, nested, topLevel]) {
        expect(await file.exists(), isTrue);
      }
      expect(warnings, isEmpty);
    },
  );

  test(
    'removed project between enumeration and listing does not stop siblings',
    () async {
      final removed = Directory('${root.path}/removed');
      await removed.create();
      final stale = await write('healthy/stale.log');
      Stream<FileSystemEntity> list(Directory directory) async* {
        if (directory.path == root.path) {
          await removed.delete();
          yield removed;
          yield Directory('${root.path}/healthy');
        } else {
          yield* directory.list(followLinks: false);
        }
      }

      await FileTerminalScrollbackStore(
        root: root,
        listDirectory: list,
      ).pruneExcept({});
      expect(await stale.exists(), isFalse);
      expect(warnings, isEmpty);
    },
  );

  test('root removed when listing starts is harmless', () async {
    Stream<FileSystemEntity> list(Directory directory) async* {
      await root.delete();
      yield* directory.list();
    }

    await FileTerminalScrollbackStore(
      root: root,
      listDirectory: list,
    ).pruneExcept({});
    expect(warnings, isEmpty);
  });

  test(
    'asynchronous access failure is sanitized and siblings still get pruned',
    () async {
      final denied = Directory('${root.path}/private-project');
      await denied.create();
      final stale = await write('healthy/stale.log');
      Stream<FileSystemEntity> list(Directory directory) async* {
        if (directory.path == root.path) {
          yield denied;
          yield Directory('${root.path}/healthy');
        } else if (directory.path == denied.path) {
          throw FileSystemException(
            'secret customer message',
            directory.path,
            const OSError('private details', 5),
          );
        } else {
          yield* directory.list();
        }
      }

      await FileTerminalScrollbackStore(
        root: root,
        listDirectory: list,
      ).pruneExcept({});
      expect(await stale.exists(), isFalse);
      expect(warnings, hasLength(1));
      expect(warnings.single.message, 'cache prune list failed (errno 5)');
      expect(warnings.single.error, isNull);
      expect(warnings.single.message, isNot(contains(root.path)));
      expect(warnings.single.message, isNot(contains('secret')));
    },
  );

  test(
    'file removed between listing and deletion does not stop siblings',
    () async {
      final disappeared = await write('project/disappeared.log');
      final stale = await write('project/stale.log');
      Stream<FileSystemEntity> list(Directory directory) async* {
        if (directory.path == root.path) {
          yield Directory('${root.path}/project');
        } else {
          await disappeared.delete();
          yield disappeared;
          yield stale;
        }
      }

      await FileTerminalScrollbackStore(
        root: root,
        listDirectory: list,
      ).pruneExcept({});
      expect(await stale.exists(), isFalse);
      expect(warnings, isEmpty);
    },
  );

  test('root listing failure is logged without escaping cleanup', () async {
    Stream<FileSystemEntity> list(Directory directory) async* {
      throw FileSystemException(
        'denied',
        directory.path,
        const OSError('denied', 5),
      );
    }

    await FileTerminalScrollbackStore(
      root: root,
      listDirectory: list,
    ).pruneExcept({});
    expect(warnings, hasLength(1));
  });

  test(
    'long Windows-style project IDs preserve kept history and prune stale history',
    () async {
      final projectId = 'root::C:/worktrees/${List.filled(190, 'p').join()}';
      expect(root.path.length + projectId.length + 12, greaterThan(260));
      final store = FileTerminalScrollbackStore(root: root);
      await store.save(
        projectId: projectId,
        sessionId: 'keep',
        contents: 'long kept',
      );
      await store.save(
        projectId: projectId,
        sessionId: 'remove',
        contents: 'long stale',
      );
      expect(
        await store.load(projectId: projectId, sessionId: 'keep'),
        'long kept',
      );
      await store.pruneExcept({'keep'});
      expect(
        await store.load(projectId: projectId, sessionId: 'keep'),
        'long kept',
      );
      expect(
        await store.load(projectId: projectId, sessionId: 'remove'),
        isNull,
      );
      expect(warnings, isEmpty);
    },
  );
}
