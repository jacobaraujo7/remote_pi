import 'dart:io';

import 'package:cockpit/app/cockpit/domain/contracts/file_system_mutator.dart';
import 'package:cockpit/app/core/domain/result.dart';

/// Mutação via `dart:io`; a lixeira no macOS é delegada ao Finder por
/// `osascript` (move pra Trash, reversível). Erros de IO viram `Failure` com
/// mensagem amigável — sem `catch` genérico solto na UI.
class FileSystemMutatorImpl implements FileSystemMutator {
  const FileSystemMutatorImpl({this.useSystemTrash = true});

  /// Quando `true` (produção), o macOS delega à Lixeira do Finder via
  /// `osascript`. `false` força a deleção permanente — usado em **testes**, que
  /// não devem mandar arquivos pra Lixeira de verdade a cada `flutter test`.
  final bool useSystemTrash;

  @override
  Future<Result<void, String>> createFile(String path) async {
    final name = _basename(path);
    if (await _exists(path)) {
      return Failure('Already exists: “$name”.');
    }
    try {
      await File(path).create();
      return const Success(null);
    } on FileSystemException catch (e) {
      return Failure(e.message);
    }
  }

  @override
  Future<Result<void, String>> createDirectory(String path) async {
    final name = _basename(path);
    if (await _exists(path)) {
      return Failure('Already exists: “$name”.');
    }
    try {
      await Directory(path).create();
      return const Success(null);
    } on FileSystemException catch (e) {
      return Failure(e.message);
    }
  }

  @override
  Future<Result<void, String>> rename(String from, String to) async {
    if (from == to) return const Success(null);
    if (await _exists(to)) {
      return Failure('Already exists: “${_basename(to)}”.');
    }
    try {
      final type = await FileSystemEntity.type(from, followLinks: false);
      switch (type) {
        case FileSystemEntityType.directory:
          await Directory(from).rename(to);
        case FileSystemEntityType.notFound:
          return Failure('Not found: “${_basename(from)}”.');
        default:
          await File(from).rename(to);
      }
      return const Success(null);
    } on FileSystemException catch (e) {
      return Failure(e.message);
    }
  }

  @override
  Future<Result<void, String>> copy(String from, String to) async {
    if (from == to) return const Success(null);
    if (await _exists(to)) {
      return Failure('Already exists: “${_basename(to)}”.');
    }
    try {
      final type = await FileSystemEntity.type(from, followLinks: false);
      switch (type) {
        case FileSystemEntityType.directory:
          await _copyDirectory(Directory(from), Directory(to));
        case FileSystemEntityType.notFound:
          return Failure('Not found: “${_basename(from)}”.');
        default:
          await File(from).copy(to);
      }
      return const Success(null);
    } on FileSystemException catch (e) {
      return Failure(e.message);
    }
  }

  /// Copia [source] em [target] recursivamente (cria [target] e desce a árvore).
  Future<void> _copyDirectory(Directory source, Directory target) async {
    await target.create(recursive: true);
    await for (final entity in source.list(followLinks: false)) {
      final name = _basename(entity.path);
      final destPath = '${target.path}/$name';
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(destPath));
      } else if (entity is File) {
        await entity.copy(destPath);
      }
    }
  }

  @override
  Future<Result<void, String>> moveToTrash(String path) async {
    if (!await _exists(path)) return const Success(null); // idempotente
    if (Platform.isMacOS && useSystemTrash) return _macTrash(path);
    return _permanentDelete(path);
  }

  /// macOS: pede ao Finder pra mover pra lixeira (reversível pelo usuário).
  Future<Result<void, String>> _macTrash(String path) async {
    final script =
        'tell application "Finder" to delete POSIX file "${_osaEscape(path)}"';
    try {
      final r = await Process.run('osascript', ['-e', script]);
      if (r.exitCode == 0) return const Success(null);
      final err = (r.stderr as String).trim();
      return Failure(err.isEmpty ? 'Could not move to Trash.' : err);
    } on ProcessException catch (e) {
      return Failure(e.message);
    }
  }

  /// Fallback (Windows/Linux): deleção permanente. A confirmação é da UI.
  Future<Result<void, String>> _permanentDelete(String path) async {
    try {
      final type = await FileSystemEntity.type(path, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        await Directory(path).delete(recursive: true);
      } else {
        await File(path).delete();
      }
      return const Success(null);
    } on FileSystemException catch (e) {
      return Failure(e.message);
    }
  }

  Future<bool> _exists(String path) async =>
      await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.notFound;

  String _basename(String path) =>
      path.split('/').where((p) => p.isNotEmpty).lastOrNull ?? path;

  /// Escapa `\` e `"` pra interpolar com segurança numa string AppleScript.
  String _osaEscape(String path) =>
      path.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
}
