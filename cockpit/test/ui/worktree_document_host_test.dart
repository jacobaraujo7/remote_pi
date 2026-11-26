import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cockpit/app/cockpit/domain/contracts/file_change_watcher.dart';
import 'package:cockpit/app/cockpit/domain/entities/file_view.dart';
import 'package:cockpit/app/cockpit/ui/document/worktree_document_host.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:cockpit_core/cockpit_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as paths;

class _Files implements FileService {
  final reads = <String>[];
  final writes = <String, Uint8List>{};
  Uint8List bytes = Uint8List.fromList(utf8.encode('# original host'));
  Future<Uint8List>? delayedRead;
  Object? failure;
  @override
  Future<String> home() async => '/home/source';
  @override
  Future<List<FileEntry>> list(String path) async => const [
    FileEntry(name: 'note.md', isDirectory: false),
  ];
  @override
  Future<Uint8List> read(String path, {int maxBytes = 8 * 1024 * 1024}) async {
    reads.add(path);
    if (failure case final error?) throw error;
    if (delayedRead case final pending?) return await pending;
    return bytes;
  }

  @override
  Future<void> write(String path, Uint8List bytes) async {
    if (failure case final error?) throw error;
    writes[path] = bytes;
  }
}

class _Changes implements FileChangeWatcher {
  @override
  Stream<void> watchFile(String path) => const Stream.empty();
  @override
  Stream<void> watchFolder(String path) => const Stream.empty();
}

void main() {
  late _Files original;
  late _Files other;
  late WorktreeDocumentHost host;
  var available = true;
  setUp(() {
    available = true;
    original = _Files();
    other = _Files();
    host = WorktreeDocumentHost(
      workspaceRoot: '/work/original',
      changes: _Changes(),
      files: original,
      remote: true,
      available: () => available,
    );
  });

  test(
    'relative paths and HOME use the source host and captured cwd',
    () async {
      expect(
        await host.resolve('../lib/code.dart', cwd: '/work/original/src'),
        '/work/original/lib/code.dart',
      );
      expect(
        await host.resolve('~/notes.md', cwd: '/work/original'),
        '/home/source/notes.md',
      );
      expect(
        await host.resolve('file:///work/original/a%20b.md', cwd: '/elsewhere'),
        '/work/original/a b.md',
      );
      expect(
        host.displayPath('irrelevant-active-project', '/work/original/lib/x'),
        'lib/x',
      );
      final windows = WorktreeDocumentHost(
        workspaceRoot: r'C:\work',
        changes: _Changes(),
        files: original,
        remote: false,
        available: () => true,
        pathContext: paths.Context(style: paths.Style.windows),
      );
      expect(
        await windows.resolve(
          'file:///C:/work/code.dart',
          cwd: r'C:\elsewhere',
        ),
        r'C:\work\code.dart',
      );
    },
  );

  test(
    'read write and directory entries keep their original service',
    () async {
      final view = await host.readView('/work/original/note.md');
      expect((view as FileViewMarkdown).text, '# original host');
      expect(await host.writeTextAt('/work/original/note.md', 'saved'), isTrue);
      expect(utf8.decode(original.writes.values.single), 'saved');
      expect(
        (await host.listChildren('/work/original')).single.path,
        '/work/original/note.md',
      );
      expect(other.reads, isEmpty);
      expect(other.writes, isEmpty);
    },
  );

  test(
    'concurrent reads of identical paths stay on separate captured hosts',
    () async {
      final gateA = Completer<Uint8List>();
      final gateB = Completer<Uint8List>();
      original.delayedRead = gateA.future;
      other.delayedRead = gateB.future;
      final second = WorktreeDocumentHost(
        workspaceRoot: '/work/original',
        changes: _Changes(),
        files: other,
        remote: true,
        available: () => true,
      );
      final readingA = host.readView('/same/note.md');
      final readingB = second.readView('/same/note.md');
      gateB.complete(Uint8List.fromList(utf8.encode('host B')));
      expect((await readingB as FileViewMarkdown).text, 'host B');
      gateA.complete(Uint8List.fromList(utf8.encode('host A')));
      expect((await readingA as FileViewMarkdown).text, 'host A');
      expect(original.reads, ['/same/note.md']);
      expect(other.reads, ['/same/note.md']);
    },
  );

  test('late reads are rejected when the owning app closes', () async {
    final gate = Completer<Uint8List>();
    original.delayedRead = gate.future;
    final pending = host.readView('/work/original/note.md');
    final checked = expectLater(pending, throwsStateError);
    available = false;
    gate.complete(Uint8List.fromList(utf8.encode('late')));
    await checked;
    expect(
      await host.writeTextAt('/work/original/note.md', 'not written'),
      isFalse,
    );
    expect(original.writes, isEmpty);
  });

  test(
    'remote failure and deletion never fall back to an existing local path',
    () async {
      final dir = await Directory.systemTemp.createTemp('orc-source-trap-');
      final file = File('${dir.path}/trap.md');
      await file.writeAsString('local content must stay untouched');
      addTearDown(() async {
        await file.delete();
        await dir.delete();
      });
      original.failure = const FileException(
        FileErrorKind.permission,
        'remote denied',
      );
      await expectLater(
        host.readView(file.path),
        throwsA(isA<FileException>()),
      );
      expect(await host.writeTextAt(file.path, 'remote write'), isFalse);
      expect(await host.deletePath(file.path), isA<Failure<void, Object>>());
      expect(await file.readAsString(), 'local content must stay untouched');
    },
  );

  test(
    'remote text classification preserves encoding and rejects local media paths',
    () async {
      original.bytes = Uint8List.fromList(latin1.encode('café'));
      final text =
          await host.readView('/work/original/note.txt') as FileViewText;
      expect(text.text, 'café');
      expect(text.encoding, latin1);
      expect(
        await host.readView('/work/original/photo.png'),
        isA<FileViewUnsupported>(),
      );
      expect(
        await host.readView('/work/original/movie.mp4'),
        isA<FileViewUnsupported>(),
      );
    },
  );

  test('unavailable origin fails before filesystem access', () async {
    available = false;
    await expectLater(
      host.readView('/work/original/note.md'),
      throwsStateError,
    );
    await expectLater(
      host.resolve('note.md', cwd: '/work/original'),
      throwsStateError,
    );
    expect(original.reads, isEmpty);
    expect(original.writes, isEmpty);
  });
}
