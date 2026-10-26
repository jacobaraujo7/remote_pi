import 'dart:io';
import 'dart:typed_data';
import 'package:cockpit/app/cockpit/data/terminal/local_terminal_attachments.dart';
import 'package:cockpit/app/cockpit/domain/contracts/terminal_attachments.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late Directory source;
  const store = LocalTerminalAttachmentStore();
  setUp(() async {
    root = await Directory.systemTemp.createTemp('attachments-test-');
    source = await Directory.systemTemp.createTemp('attachments-source-');
  });
  tearDown(() async {
    await root.delete(recursive: true);
    await source.delete(recursive: true);
  });
  Future<TerminalImportResult> copy(
    List<String> paths, {
    Uint8List? image,
    String? projectRoot,
    bool alive = true,
    void Function(int, int)? progress,
  }) => store.import(
    projectRoot: projectRoot ?? root.path,
    paths: paths,
    image: image,
    isAlive: () => alive,
    onProgress: progress ?? (_, _) {},
  );

  test(
    'copy preserves content, extension and name after original is removed',
    () async {
      final file = await File(
        p.join(source.path, "a b's \u00e9.pdf"),
      ).writeAsString('original');
      final result = await copy([file.path]);
      await file.delete();
      expect(result.errors, isEmpty);
      expect(p.basename(result.paths.single), "a b's \u00e9.pdf");
      expect(
        p.isWithin(
          p.join(root.path, '.cockpit', 'attachments'),
          result.paths.single,
        ),
        isTrue,
      );
      expect(await File(result.paths.single).readAsString(), 'original');
    },
  );
  test(
    'same basenames and repeated operations never overwrite files',
    () async {
      final secondDir = await Directory(p.join(source.path, 'second')).create();
      final a = await File(p.join(source.path, 'a.txt')).writeAsString('one');
      final b = await File(
        p.join(secondDir.path, 'a.txt'),
      ).writeAsString('two');
      final first = await copy([a.path, b.path]);
      final next = await copy([a.path]);
      expect(first.paths.toSet(), hasLength(2));
      expect(await File(first.paths[0]).readAsString(), 'one');
      expect(await File(first.paths[1]).readAsString(), 'two');
      expect(p.dirname(next.paths.single), isNot(p.dirname(first.paths.first)));
    },
  );
  test('filename ending in partial cannot be overwritten by staging', () async {
    final a = await File(
      p.join(source.path, 'a.partial'),
    ).writeAsString('keep');
    final b = await File(p.join(source.path, 'a')).writeAsString('new');
    final result = await copy([a.path, b.path]);
    expect(await File(result.paths[0]).readAsString(), 'keep');
    expect(await File(result.paths[1]).readAsString(), 'new');
  });
  test(
    'directory is referenced without copying its children or creating attachments',
    () async {
      await File(p.join(source.path, 'child')).writeAsString('child');
      final result = await copy([source.path]);
      expect(result.paths, [await source.resolveSymbolicLinks()]);
      expect(await Directory(p.join(root.path, '.cockpit')).exists(), isFalse);
    },
  );
  test(
    'missing item does not prevent subsequent successful file import',
    () async {
      final file = await File(
        p.join(source.path, 'ok.txt'),
      ).writeAsString('ok');
      final result = await copy([p.join(source.path, 'missing'), file.path]);
      expect(result.paths, hasLength(1));
      expect(result.errors, hasLength(1));
    },
  );
  test(
    'empty, nonexistent and non-directory project roots fail explicitly',
    () async {
      final file = await File(
        p.join(source.path, 'ok.txt'),
      ).writeAsString('ok');
      for (final target in ['', p.join(root.path, 'absent'), file.path]) {
        final result = await copy([file.path], projectRoot: target);
        expect(result.paths, isEmpty);
        expect(result.errors, isNotEmpty);
      }
    },
  );
  test('metadata directory blocked by a file reports write failure', () async {
    await File(p.join(root.path, '.cockpit')).writeAsString('do not overwrite');
    final file = await File(p.join(source.path, 'ok.txt')).writeAsString('ok');
    final result = await copy([file.path]);
    expect(result.paths, isEmpty);
    expect(result.errors, isNotEmpty);
    expect(
      await File(p.join(root.path, '.cockpit')).readAsString(),
      'do not overwrite',
    );
  });
  test('bitmap saved persistently as clipboard.png with progress', () async {
    final progress = <(int, int)>[];
    final result = await copy(
      [],
      image: Uint8List.fromList([137, 80, 78, 71]),
      progress: (a, b) => progress.add((a, b)),
    );
    expect(p.basename(result.paths.single), 'clipboard.png');
    expect(await File(result.paths.single).readAsBytes(), [137, 80, 78, 71]);
    expect(progress, [(0, 1), (1, 1)]);
  });
  test('already disposed session never creates files', () async {
    final result = await copy([], image: Uint8List.fromList([1]), alive: false);
    expect(result.paths, isEmpty);
    expect(await Directory(p.join(root.path, '.cockpit')).exists(), isFalse);
  });
  test(
    'WSL conversion preserves Unicode and trailing filename spaces, verifies accessibility',
    () async {
      final calls = <List<String>>[];
      final converter = LocalTerminalPathConverter(
        run: (args) async {
          calls.add(args);
          return ProcessResult(
            1,
            0,
            calls.length == 1 ? '/mnt/c/projeto/ação final \n' : '',
            '',
          );
        },
      );
      final converted = await converter.forWsl(
        r'C:\projeto\ação final ',
        'Ubuntu-24.04',
      );
      expect(converted, '/mnt/c/projeto/ação final ');
      expect(calls[0].take(3), ['--distribution', 'Ubuntu-24.04', '--exec']);
      expect(calls[1].skip(3), ['test', '-e', converted]);
    },
  );
  test(
    'WSL conversion failure or inaccessible output never yields a usable path',
    () async {
      for (final conversionFails in [true, false]) {
        var calls = 0;
        final converter = LocalTerminalPathConverter(
          run: (_) async {
            calls++;
            return ProcessResult(
              1,
              conversionFails || calls == 2 ? 1 : 0,
              calls == 1 ? '/mnt/c/missing\n' : '',
              'not accessible',
            );
          },
        );
        await expectLater(
          converter.forWsl(r'C:\missing', 'Ubuntu'),
          throwsA(isA<FileSystemException>()),
        );
      }
    },
  );
}
