import 'dart:io';
import 'dart:typed_data';

import 'package:cockpit_core/cockpit_core.dart';

/// [FileService] sobre o filesystem local do servidor (plano 58, Wave 3).
class NativeFileService implements FileService, ExclusiveFileCreator {
  const NativeFileService();

  @override
  Future<String> home() async {
    final env = Platform.environment;
    return env['HOME'] ?? env['USERPROFILE'] ?? '';
  }

  @override
  Future<List<FileEntry>> list(String path) async {
    final dir = Directory(path);
    if (!dir.existsSync()) {
      throw FileException(FileErrorKind.notFound, path);
    }
    final entries = <FileEntry>[];
    try {
      await for (final entity in dir.list(followLinks: false)) {
        final stat = await entity.stat();
        entries.add(
          FileEntry(
            name: entity.uri.pathSegments.where((s) => s.isNotEmpty).last,
            isDirectory: stat.type == FileSystemEntityType.directory,
            size: stat.size,
          ),
        );
      }
    } on FileSystemException catch (e) {
      throw FileException(FileErrorKind.io, e.message);
    }
    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  @override
  Future<Uint8List> read(String path, {int maxBytes = 8 * 1024 * 1024}) async {
    final file = File(path);
    if (!file.existsSync()) {
      throw FileException(FileErrorKind.notFound, path);
    }
    final length = await file.length();
    if (length > maxBytes) {
      throw FileException(FileErrorKind.tooLarge, '$length');
    }
    try {
      return await file.readAsBytes();
    } on FileSystemException catch (e) {
      throw FileException(FileErrorKind.io, e.message);
    }
  }

  @override
  Future<bool> createNew(String path, Uint8List bytes) async {
    final file = File(path);
    try {
      await file.create(exclusive: true);
    } on PathExistsException {
      return false;
    } on FileSystemException catch (e) {
      // Windows reports an existing directory as access denied rather than
      // PathExistsException. Detect it without following symlinks or writing.
      if (await FileSystemEntity.type(path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        return false;
      }
      throw FileException(FileErrorKind.io, e.message);
    }
    try {
      await file.writeAsBytes(bytes, flush: true);
      return true;
    } on FileSystemException catch (e) {
      // Keep a partial file on failure; a journaled retry chooses a fresh path.
      // Never delete or overwrite a path whose ownership is now uncertain.
      throw FileException(FileErrorKind.io, e.message);
    }
  }

  @override
  Future<void> write(String path, Uint8List bytes) async {
    try {
      // Pasta-pai ausente é criada (ex.: `.cockpit/tasks.json` num workspace
      // que nunca teve `.cockpit/`) — mesmo contrato do `File.create`.
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    } on FileSystemException catch (e) {
      throw FileException(FileErrorKind.io, e.message);
    }
  }
}
