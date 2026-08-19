import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/cockpit/data/filesystem/git_binary.dart';
import 'package:cockpit/app/cockpit/data/filesystem/unified_diff_parser.dart';
import 'package:cockpit/app/cockpit/domain/contracts/git_diff_reader.dart';
import 'package:cockpit/app/cockpit/domain/entities/file_diff.dart';

/// Lê o diff de um arquivo contra o HEAD rodando `git diff HEAD` e parseando o
/// unified diff. Untracked (sem HEAD) é lido direto como "tudo adicionado".
class GitDiffReaderImpl implements GitDiffReader {
  GitDiffReaderImpl(this._gitBinary);

  final GitBinary _gitBinary;

  @override
  Future<FileDiff> read(String repoPath, String absPath) async {
    try {
      final git = await _gitBinary.resolve();
      final rel = _relative(repoPath, absPath);

      // Untracked? `git diff HEAD` não mostra arquivo não rastreado — detecta via
      // status e lê o arquivo inteiro como adicionado.
      final status = await Process.run(
        git,
        ['-C', repoPath, 'status', '--porcelain', '--', rel],
        stdoutEncoding: utf8,
      );
      final statusOut = status.exitCode == 0 ? (status.stdout as String) : '';
      if (statusOut.startsWith('??')) {
        return _untrackedDiff(absPath);
      }

      final diff = await Process.run(
        git,
        ['-C', repoPath, 'diff', 'HEAD', '--', rel],
        stdoutEncoding: utf8,
      );
      if (diff.exitCode != 0) return FileDiff.unchanged(absPath);
      final out = diff.stdout as String;
      if (out.trim().isEmpty) return FileDiff.unchanged(absPath);
      if (unifiedDiffLooksBinary(out)) return FileDiff.binary(absPath);

      final (hunks, kind) = parseUnifiedDiff(out);
      if (hunks.isEmpty) return FileDiff.unchanged(absPath);
      return FileDiff(path: absPath, kind: kind, hunks: hunks);
    } catch (_) {
      return FileDiff.unchanged(absPath);
    }
  }

  @override
  Future<FileDiff> readCommit(
    String repoPath,
    String commitHash,
    String relativePath, {
    String? previousRelativePath,
  }) async {
    final absPath =
        '${repoPath.endsWith('/') ? repoPath.substring(0, repoPath.length - 1) : repoPath}/$relativePath';
    try {
      final git = await _gitBinary.resolve();
      final parentResult = await Process.run(
        git,
        ['-C', repoPath, 'show', '--format=%P', '--no-patch', commitHash],
        stdoutEncoding: utf8,
      );
      if (parentResult.exitCode != 0) return FileDiff.unchanged(absPath);
      final parentLine = (parentResult.stdout as String).trim();
      final beforeRevision = parentLine.isEmpty
          ? null
          : parentLine.split(RegExp(r'\s+')).first;
      final renameOrCopy =
          previousRelativePath != null && previousRelativePath != relativePath;
      final result = renameOrCopy && beforeRevision != null
          // `git show <commit> -- old new` separa rename com mudancas em
          // delete + add. Comparar os blobs diretamente preserva o conteudo
          // original e modificado como um unico diff.
          ? await Process.run(
              git,
              [
                '-C',
                repoPath,
                'diff',
                '$beforeRevision:$previousRelativePath',
                '$commitHash:$relativePath',
              ],
              stdoutEncoding: utf8,
            )
          : await Process.run(
              git,
              [
                '-C',
                repoPath,
                'show',
                '--format=',
                '--first-parent',
                '--find-renames',
                commitHash,
                '--',
                relativePath,
              ],
              stdoutEncoding: utf8,
            );
      if (result.exitCode != 0) return FileDiff.unchanged(absPath);
      final out = result.stdout as String;
      if (unifiedDiffLooksBinary(out)) {
        return FileDiff(
          path: absPath,
          kind: FileDiffKind.binary,
          beforeRevision: beforeRevision,
          afterRevision: commitHash,
        );
      }

      final (hunks, kind) = parseUnifiedDiff(out);
      if (hunks.isEmpty) {
        return FileDiff(
          path: absPath,
          kind: FileDiffKind.unchanged,
          beforeRevision: beforeRevision,
          afterRevision: commitHash,
        );
      }
      return FileDiff(
        path: absPath,
        kind: kind,
        hunks: hunks,
        beforeRevision: beforeRevision,
        afterRevision: commitHash,
      );
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
      final content = utf8.decode(bytes, allowMalformed: true);
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

  /// Heurística: NUL nos primeiros 8000 bytes → binário.
  bool _looksBinary(List<int> bytes) {
    final n = bytes.length < 8000 ? bytes.length : 8000;
    for (var i = 0; i < n; i++) {
      if (bytes[i] == 0) return true;
    }
    return false;
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
