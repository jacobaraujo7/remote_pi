import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:cockpit/app/cockpit/domain/contracts/terminal_scrollback_store.dart';
import 'package:cockpit/app/core/data/setup/storage_location.dart';
import 'package:cockpit/app/core/data/diagnostics/diagnostics_log.dart';

/// [TerminalScrollbackStore] em arquivo, sob o applicationSupport do app
/// (`.../terminal_scrollback/<projectId>/<sessionId>.log`, UTF-8). Localização
/// resolvida por [StorageLocation.scrollbackDir] — **cache local**, não segue a
/// pasta escolhida pelo usuário (não faz sentido sincronizar logs pesados), mas
/// é apagado no reset.
///
/// Store **burra**: o ring buffer e o tracking de alt-screen vivem no
/// [TerminalSession]; aqui só há IO. Escrita atômica via `.tmp` + `rename`.
class FileTerminalScrollbackStore implements TerminalScrollbackStore {
  const FileTerminalScrollbackStore({Directory? root, this.listDirectory})
    : _rootOverride = root;

  // Optional IO seams keep cleanup races deterministic in tests. Normal app
  // instances still use the same storage location and on-disk format.
  final Directory? _rootOverride;
  final Stream<FileSystemEntity> Function(Directory)? listDirectory;

  Future<Directory> _root() async =>
      _rootOverride ?? Directory(await StorageLocation.scrollbackDir());

  File _fileIn(Directory root, String projectId, String sessionId) =>
      File('${root.path}/${_safe(projectId)}/${_safe(sessionId)}.log');

  /// Ids viram nome de arquivo, mas nem todo id é um nome válido: forks de
  /// multi-root são namespaced `rootId::path` (issue #88 — `:` é ilegal no
  /// Windows, errno 123) e um `/` embutido criaria subpasta acidental. Escapa
  /// tudo fora de `[A-Za-z0-9._-]` como `%XX` — identidade pra ids antigos
  /// (UUIDs), preservando o scrollback existente.
  static String _safe(String id) {
    final buf = StringBuffer();
    for (final unit in id.codeUnits) {
      final c = String.fromCharCode(unit);
      final ok =
          (unit >= 0x30 && unit <= 0x39) || // 0-9
          (unit >= 0x41 && unit <= 0x5a) || // A-Z
          (unit >= 0x61 && unit <= 0x7a) || // a-z
          c == '.' ||
          c == '_' ||
          c == '-';
      if (ok) {
        buf.write(c);
      } else {
        buf.write('%${unit.toRadixString(16).padLeft(2, '0').toUpperCase()}');
      }
    }
    return buf.toString();
  }

  @override
  Future<String?> load({
    required String projectId,
    required String sessionId,
  }) async {
    final file = _fileIn(await _root(), projectId, sessionId);
    if (!file.existsSync()) return null;
    try {
      return await file.readAsString();
    } catch (_) {
      return null; // arquivo corrompido/ilegível → ignora.
    }
  }

  @override
  Future<void> save({
    required String projectId,
    required String sessionId,
    required String contents,
  }) async {
    // Best-effort: scrollback é cache — falha de IO aqui jamais pode derrubar
    // o app (o dispose chama via `unawaited`, e um throw vira erro async fatal;
    // foi o crash da issue #88).
    try {
      final file = _fileIn(await _root(), projectId, sessionId);
      await file.parent.create(recursive: true);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(contents, flush: true);
      await tmp.rename(file.path); // atômico no mesmo filesystem.
    } on FileSystemException {
      // Disco cheio/caminho inválido/lock transitório: perde este snapshot.
    }
  }

  @override
  Future<void> delete({
    required String projectId,
    required String sessionId,
  }) async {
    final file = _fileIn(await _root(), projectId, sessionId);
    if (file.existsSync()) {
      try {
        await file.delete();
      } catch (_) {
        // já removido / corrida — ignora.
      }
    }
  }

  @override
  Future<void> pruneExcept(Set<String> keep) async {
    try {
      final root = await _root();
      // Names on disk use the same escaping as save/load. Do not check exists
      // first: a directory can disappear before its asynchronous listing starts.
      final keepSafe = keep.map(_safe).toSet();
      await for (final projectDir in _entries(root)) {
        if (projectDir is! Directory) continue;
        await for (final entry in _entries(projectDir)) {
          if (entry is! File || !entry.path.endsWith('.log')) continue;
          final name = entry.uri.pathSegments.last;
          final sessionId = name.substring(0, name.length - '.log'.length);
          if (keepSafe.contains(sessionId)) continue;
          try {
            await entry.delete();
          } on FileSystemException catch (error) {
            _reportPruneFailure('delete', error);
          }
        }
      }
    } on FileSystemException catch (error) {
      _reportPruneFailure('root', error);
    }
  }

  Stream<FileSystemEntity> _entries(Directory directory) async* {
    try {
      final entries =
          listDirectory?.call(directory) ??
          _directoryForListing(directory).list(followLinks: false);
      await for (final entry in entries) {
        yield entry;
      }
    } on FileSystemException catch (error) {
      // Catch each project's stream independently so a removed/inaccessible
      // project cannot prevent cleanup of its siblings.
      _reportPruneFailure('list', error);
    }
  }

  Directory _directoryForListing(Directory directory) {
    if (!Platform.isWindows) return directory;
    final path = p.windows.normalize(directory.absolute.path);
    // Dart file IO accepts long paths, but Windows directory enumeration can
    // still report errno 3 without the extended-length prefix. Apply it only
    // to enumeration: IDs and the physical cache layout remain unchanged.
    if (path.startsWith(r'\\?\')) return Directory(path);
    if (path.startsWith(r'\\')) {
      return Directory(r'\\?\UNC\' + path.substring(2));
    }
    return Directory(r'\\?\' + path);
  }

  void _reportPruneFailure(String operation, FileSystemException error) {
    final code = error.osError?.errorCode;
    if (error is PathNotFoundException ||
        code == 2 ||
        (Platform.isWindows && code == 3)) {
      return;
    }
    // Paths and exception messages may contain workspace or customer details.
    DiagnosticsLog.instance.warn(
      'scrollback',
      'cache prune $operation failed (errno ${code ?? 'unknown'})',
    );
  }
}
