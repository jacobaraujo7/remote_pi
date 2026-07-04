import 'dart:io';

import 'package:cockpit/app/cockpit/data/filesystem/git_binary.dart';
import 'package:cockpit/app/cockpit/domain/contracts/git_diff_reader.dart';
import 'package:cockpit/app/cockpit/domain/entities/file_diff.dart';

/// Lê o diff de um arquivo contra o HEAD rodando `git diff HEAD` e parseando o
/// unified diff. Untracked (sem HEAD) é lido direto como "tudo adicionado".
class GitDiffReaderImpl implements GitDiffReader {
  GitDiffReaderImpl(this._gitBinary);

  final GitBinary _gitBinary;

  static final RegExp _hunkHeader = RegExp(
    r'^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@',
  );

  @override
  Future<FileDiff> read(String repoPath, String absPath) async {
    try {
      final git = await _gitBinary.resolve();
      final rel = _relative(repoPath, absPath);

      // Untracked? `git diff HEAD` não mostra arquivo não rastreado — detecta via
      // status e lê o arquivo inteiro como adicionado.
      final status = await Process.run(git, [
        '-C',
        repoPath,
        'status',
        '--porcelain',
        '--',
        rel,
      ]);
      final statusOut = status.exitCode == 0 ? (status.stdout as String) : '';
      if (statusOut.startsWith('??')) {
        return _untrackedDiff(absPath);
      }

      final diff = await Process.run(git, [
        '-C',
        repoPath,
        'diff',
        'HEAD',
        '--',
        rel,
      ]);
      if (diff.exitCode != 0) return FileDiff.unchanged(absPath);
      final out = diff.stdout as String;
      if (out.trim().isEmpty) return FileDiff.unchanged(absPath);
      if (_isBinary(out)) return FileDiff.binary(absPath);

      final (hunks, kind) = _parse(out);
      if (hunks.isEmpty) return FileDiff.unchanged(absPath);
      return FileDiff(path: absPath, kind: kind, hunks: hunks);
    } catch (_) {
      return FileDiff.unchanged(absPath);
    }
  }

  /// Lê o arquivo untracked inteiro como um único hunk todo-adicionado.
  Future<FileDiff> _untrackedDiff(String absPath) async {
    try {
      final file = File(absPath);
      final bytes = await file.readAsBytes();
      if (_looksBinary(bytes)) return FileDiff.binary(absPath);
      final content = String.fromCharCodes(bytes);
      final lines = content.split('\n');
      // split deixa uma string vazia no fim quando o arquivo termina em '\n'.
      if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
      final diffLines = <DiffLine>[];
      for (var i = 0; i < lines.length; i++) {
        diffLines.add(
          DiffLine(kind: DiffLineKind.added, text: lines[i], newLine: i + 1),
        );
      }
      return FileDiff(
        path: absPath,
        kind: FileDiffKind.added,
        hunks: [DiffHunk(header: '@@ +1,${lines.length} @@', lines: diffLines)],
      );
    } catch (_) {
      return FileDiff.unchanged(absPath);
    }
  }

  bool _isBinary(String diffOut) =>
      RegExp(r'^Binary files .* differ$', multiLine: true).hasMatch(diffOut);

  /// Heurística: NUL nos primeiros 8000 bytes → binário.
  bool _looksBinary(List<int> bytes) {
    final n = bytes.length < 8000 ? bytes.length : 8000;
    for (var i = 0; i < n; i++) {
      if (bytes[i] == 0) return true;
    }
    return false;
  }

  /// Parseia o unified diff em hunks, inferindo se é novo/deletado pelos
  /// marcadores `--- /dev/null` / `+++ /dev/null`.
  (List<DiffHunk>, FileDiffKind) _parse(String out) {
    final hunks = <DiffHunk>[];
    var kind = FileDiffKind.modified;
    DiffHunk? current;
    var oldNo = 0;
    var newNo = 0;
    List<DiffLine> lines = [];

    void flush() {
      final c = current;
      if (c != null) hunks.add(DiffHunk(header: c.header, lines: lines));
    }

    for (final line in out.split('\n')) {
      if (line.startsWith('--- ')) {
        if (line.startsWith('--- /dev/null')) kind = FileDiffKind.added;
        continue;
      }
      if (line.startsWith('+++ ')) {
        if (line.startsWith('+++ /dev/null')) kind = FileDiffKind.deleted;
        continue;
      }
      if (line.startsWith('diff --git') ||
          line.startsWith('index ') ||
          line.startsWith('new file') ||
          line.startsWith('deleted file') ||
          line.startsWith('similarity ') ||
          line.startsWith('rename ')) {
        continue;
      }
      final m = _hunkHeader.firstMatch(line);
      if (m != null) {
        flush();
        oldNo = int.parse(m.group(1)!);
        newNo = int.parse(m.group(2)!);
        lines = [];
        current = DiffHunk(header: line, lines: lines);
        continue;
      }
      if (current == null) continue;
      if (line.startsWith(r'\')) continue; // "\ No newline at end of file"
      if (line.startsWith('+')) {
        lines.add(
          DiffLine(
            kind: DiffLineKind.added,
            text: line.substring(1),
            newLine: newNo++,
          ),
        );
      } else if (line.startsWith('-')) {
        lines.add(
          DiffLine(
            kind: DiffLineKind.removed,
            text: line.substring(1),
            oldLine: oldNo++,
          ),
        );
      } else if (line.startsWith(' ')) {
        lines.add(
          DiffLine(
            kind: DiffLineKind.context,
            text: line.substring(1),
            oldLine: oldNo++,
            newLine: newNo++,
          ),
        );
      }
    }
    flush();
    return (hunks, kind);
  }

  /// Caminho de [absPath] relativo a [repoPath] (com `/`). Fora do repo → devolve
  /// o próprio absPath.
  String _relative(String repoPath, String absPath) {
    var root = repoPath.replaceAll(r'\', '/');
    if (root.endsWith('/')) root = root.substring(0, root.length - 1);
    final p = absPath.replaceAll(r'\', '/');
    if (p == root) return p;
    final prefix = '$root/';
    return p.startsWith(prefix) ? p.substring(prefix.length) : p;
  }
}
