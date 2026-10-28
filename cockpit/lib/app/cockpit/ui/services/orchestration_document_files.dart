import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cockpit_core/cockpit_core.dart';
import 'package:path/path.dart' as paths;
import '../../domain/contracts/file_change_watcher.dart';

/// App-side local adapter; importing cockpit_engine would break mobile builds.
class LocalDocumentFiles implements FileService {
  const LocalDocumentFiles();
  @override
  Future<String> home() async =>
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
  @override
  Future<List<FileEntry>> list(String path) async => [
    await for (final entry in Directory(path).list(followLinks: false))
      FileEntry(
        name: paths.basename(entry.path),
        isDirectory: await FileSystemEntity.isDirectory(entry.path),
      ),
  ];
  @override
  Future<Uint8List> read(String path, {int maxBytes = 8 * 1024 * 1024}) async {
    final file = File(path);
    if (await file.length() > maxBytes) {
      throw const FileException(FileErrorKind.tooLarge);
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > maxBytes) {
      throw const FileException(FileErrorKind.tooLarge);
    }
    return bytes;
  }

  @override
  Future<void> write(String path, Uint8List bytes) async {
    await File(path).writeAsBytes(bytes, flush: true);
  }
}

/// Reconnect may replace a connection, but never changes the captured host.
class CapturedDocumentFiles implements FileService {
  CapturedDocumentFiles(this.source);
  final Future<FileService> Function() source;
  @override
  Future<String> home() async => (await source()).home();
  @override
  Future<List<FileEntry>> list(String path) async =>
      (await source()).list(path);
  @override
  Future<Uint8List> read(String path, {int maxBytes = 8 * 1024 * 1024}) async =>
      (await source()).read(path, maxBytes: maxBytes);
  @override
  Future<void> write(String path, Uint8List bytes) async =>
      (await source()).write(path, bytes);
}

/// Remote services have no native filesystem watcher. Poll the original service
/// while its document is visible; equal-size edits must still be detected.
class ServiceDocumentWatcher implements FileChangeWatcher {
  ServiceDocumentWatcher(
    this.files, {
    required this.active,
    this.interval = const Duration(seconds: 2),
  });
  final FileService files;
  final bool Function() active;
  final Duration interval;
  @override
  Stream<void> watchFile(String path) => _watch(
    () async => base64Encode(await files.read(path, maxBytes: 2 * 1024 * 1024)),
  );
  @override
  Stream<void> watchFolder(String path) => _watch(() async {
    final entries = (await files.list(path)).toList();
    entries.sort((a, b) => a.name.compareTo(b.name));
    return jsonEncode([
      for (final entry in entries)
        [
          entry.name,
          entry.isDirectory,
          if (!entry.isDirectory)
            base64Encode(
              await files.read(
                paths.posix.join(path, entry.name),
                maxBytes: 2 * 1024 * 1024,
              ),
            ),
        ],
    ]);
  });
  Stream<void> _watch(Future<String> Function() snapshot) =>
      Stream.multi((events) {
        var cancelled = false;
        var running = false;
        String? previous;
        Future<void> tick() async {
          if (cancelled || running || !active()) return;
          running = true;
          try {
            String next;
            try {
              next = 'ok:${await snapshot()}';
            } on Object catch (error) {
              next = 'error:$error';
            }
            if (cancelled || !active()) return;
            if (previous != next) {
              previous = next;
              events.add(null);
            }
          } finally {
            running = false;
          }
        }

        final timer = Timer.periodic(interval, (_) => unawaited(tick()));
        events.onCancel = () {
          cancelled = true;
          timer.cancel();
        };
        unawaited(tick());
      });
}
