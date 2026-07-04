import 'dart:async';
import 'dart:io';

import 'package:cockpit/app/cockpit/domain/contracts/terminal_scrollback_store.dart';
import 'package:cockpit/app/core/data/setup/storage_location.dart';

/// [TerminalScrollbackStore] em arquivo, sob o applicationSupport do app
/// (`.../terminal_scrollback/<projectId>/<sessionId>.log`, UTF-8). Localização
/// resolvida por [StorageLocation.scrollbackDir] — **cache local**, não segue a
/// pasta escolhida pelo usuário (não faz sentido sincronizar logs pesados), mas
/// é apagado no reset.
///
/// Store **burra**: o ring buffer e o tracking de alt-screen vivem no
/// [TerminalSession]; aqui só há IO. Escrita atômica via `.tmp` + `rename`.
class FileTerminalScrollbackStore implements TerminalScrollbackStore {
  const FileTerminalScrollbackStore();

  Future<Directory> _root() async =>
      Directory(await StorageLocation.scrollbackDir());

  File _fileIn(Directory root, String projectId, String sessionId) =>
      File('${root.path}/$projectId/$sessionId.log');

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
    final file = _fileIn(await _root(), projectId, sessionId);
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(contents, flush: true);
    await tmp.rename(file.path); // atômico no mesmo filesystem.
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
    final root = await _root();
    if (!root.existsSync()) return;
    await for (final projectDir in root.list()) {
      if (projectDir is! Directory) continue;
      await for (final entry in projectDir.list()) {
        if (entry is! File || !entry.path.endsWith('.log')) continue;
        final name = entry.uri.pathSegments.last; // '<sessionId>.log'
        final sessionId = name.substring(0, name.length - '.log'.length);
        if (keep.contains(sessionId)) continue;
        try {
          await entry.delete();
        } catch (_) {
          // ignora falha individual.
        }
      }
    }
  }
}
