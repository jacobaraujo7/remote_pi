import 'dart:io';

import 'package:cockpit/domain/contracts/file_system_reader.dart';
import 'package:cockpit/domain/entities/file_node.dart';

/// Lê a árvore via `dart:io`: pastas primeiro (ordenadas), depois arquivos.
/// Inclui ocultos úteis (`.pi`, `.claude`, `.env`…), mas **esconde pastas de
/// VCS** ([_hiddenDirs]) em qualquer nível — `.git` nunca interessa navegar.
class FileSystemReaderImpl implements FileSystemReader {
  const FileSystemReaderImpl();

  /// Pastas de versionamento ocultadas em toda a árvore (não só na raiz).
  static const Set<String> _hiddenDirs = <String>{'.git', '.hg', '.svn'};

  @override
  Future<List<FileNode>> children(String dirPath) async {
    if (dirPath.isEmpty) return const <FileNode>[];
    final dir = Directory(dirPath);
    if (!await dir.exists()) return const <FileNode>[];

    final dirs = <FileNode>[];
    final files = <FileNode>[];
    try {
      await for (final entity in dir.list(followLinks: false)) {
        final name = entity.path.split(Platform.pathSeparator).last;
        final isDir = entity is Directory;
        if (isDir && _hiddenDirs.contains(name)) continue;
        final node = FileNode(name: name, path: entity.path, isDirectory: isDir);
        (isDir ? dirs : files).add(node);
      }
    } on FileSystemException {
      return const <FileNode>[];
    }

    int byName(FileNode a, FileNode b) =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase());
    dirs.sort(byName);
    files.sort(byName);
    return <FileNode>[...dirs, ...files];
  }
}
