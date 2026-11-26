import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:cockpit/app/cockpit/ui/services/orchestration_document_files.dart';
import 'package:cockpit_core/cockpit_core.dart';
import 'package:flutter_test/flutter_test.dart';

class _Files implements FileService {
  Uint8List bytes = Uint8List.fromList([1, 2, 3]);
  int reads = 0;
  int? limit;
  Completer<Uint8List>? pending;
  @override
  Future<Uint8List> read(String path, {int maxBytes = 8 * 1024 * 1024}) async {
    reads++;
    limit = maxBytes;
    return pending == null ? bytes : await pending!.future;
  }

  @override
  Future<void> write(String path, Uint8List value) async {
    bytes = value;
  }

  @override
  Future<String> home() async => '/original';
  @override
  Future<List<FileEntry>> list(String path) async => const [];
}

void main() {
  test(
    'captured service reconnects without retaining a stale connection',
    () async {
      final first = _Files();
      final second = _Files()..bytes = Uint8List.fromList([4]);
      FileService current = first;
      final files = CapturedDocumentFiles(() async => current);
      expect(await files.read('note', maxBytes: 7), [1, 2, 3]);
      expect(first.limit, 7);
      current = second;
      expect(await files.read('note'), [4]);
      await files.write('note', Uint8List.fromList([5]));
      expect(second.bytes, [5]);
      expect(first.bytes, [1, 2, 3]);
    },
  );

  test(
    'watcher detects equal-size edits and stops reads while hidden',
    () async {
      final files = _Files();
      var active = true;
      final initial = Completer<void>();
      final changed = Completer<void>();
      var events = 0;
      final watcher = ServiceDocumentWatcher(
        files,
        active: () => active,
        interval: const Duration(milliseconds: 5),
      );
      final subscription = watcher.watchFile('note').listen((_) {
        events++;
        if (events == 1) initial.complete();
        if (events == 2) changed.complete();
      });
      addTearDown(subscription.cancel);
      await initial.future.timeout(const Duration(seconds: 2));
      files.bytes = Uint8List.fromList([3, 2, 1]);
      await changed.future.timeout(const Duration(seconds: 2));
      active = false;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final reads = files.reads;
      files.bytes = Uint8List.fromList([4, 5, 6]);
      await Future<void>.delayed(const Duration(milliseconds: 25));
      expect(files.reads, reads);
      expect(events, 2);
    },
  );

  test('cancellation discards an in-flight snapshot', () async {
    final files = _Files()..pending = Completer<Uint8List>();
    var events = 0;
    final watcher = ServiceDocumentWatcher(
      files,
      active: () => true,
      interval: const Duration(milliseconds: 5),
    );
    final subscription = watcher.watchFile('note').listen((_) => events++);
    await Future<void>.delayed(Duration.zero);
    expect(files.reads, 1);
    await subscription.cancel();
    files.pending!.complete(Uint8List.fromList([1]));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(events, 0);
    expect(files.reads, 1);
  });

  test(
    'local adapter enforces byte limit before returning file data',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'cockpit-document-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/note');
      await file.writeAsBytes([1, 2, 3]);
      const files = LocalDocumentFiles();
      await expectLater(
        files.read(file.path, maxBytes: 2),
        throwsA(isA<FileException>()),
      );
      expect(await files.read(file.path, maxBytes: 3), [1, 2, 3]);
    },
  );
}
