import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cockpit/app/cockpit/data/filesystem/git_binary.dart';
import 'package:cockpit/app/cockpit/domain/contracts/git_head_baseline_reader.dart';
import 'package:cockpit/app/cockpit/domain/entities/git_head_baseline.dart';

/// Lê blobs de `HEAD` via `git rev-parse` / `git cat-file` — sem working tree.
class GitHeadBaselineReaderImpl implements GitHeadBaselineReader {
  GitHeadBaselineReaderImpl(this._gitBinary);

  final GitBinary _gitBinary;

  static const int _maxTextBytes = 2 * 1024 * 1024;

  @override
  Future<String?> resolveHeadIdentity(String repoPath) async {
    try {
      final git = await _gitBinary.resolve();
      final result = await Process.run(git, [
        '-C',
        repoPath,
        'rev-parse',
        'HEAD',
      ]);
      if (result.exitCode != 0) return null;
      final id = (result.stdout as String).trim();
      return id.isEmpty ? null : id;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<GitHeadBaseline?> readTrackedText(
    String repoPath,
    String absPath,
  ) async {
    try {
      final git = await _gitBinary.resolve();
      final rel = _relative(repoPath, absPath);
      if (rel == null || rel.isEmpty || rel.startsWith('..')) return null;

      final head = await resolveHeadIdentity(repoPath);
      if (head == null) return null;

      // Existe no snapshot HEAD? (cobre untracked/ignored/novo sem blob).
      final exists = await Process.run(git, [
        '-C',
        repoPath,
        'cat-file',
        '-e',
        '$head:$rel',
      ]);
      if (exists.exitCode != 0) return null;

      final blob = await Process.run(git, [
        '-C',
        repoPath,
        'cat-file',
        '-p',
        '$head:$rel',
      ], stdoutEncoding: null);
      if (blob.exitCode != 0) return null;

      final bytes = _asBytes(blob.stdout);
      if (bytes == null) return null;
      if (bytes.length > _maxTextBytes) return null;
      if (_isBinary(bytes)) return null;

      return GitHeadBaseline(
        headIdentity: head,
        content: utf8.decode(bytes, allowMalformed: true),
      );
    } catch (_) {
      return null;
    }
  }

  static String? _relative(String repoPath, String absPath) {
    final root = repoPath.endsWith('/')
        ? repoPath.substring(0, repoPath.length - 1)
        : repoPath;
    final abs = absPath.endsWith('/') && absPath.length > 1
        ? absPath.substring(0, absPath.length - 1)
        : absPath;
    if (abs == root) return '';
    final prefix = '$root/';
    if (!abs.startsWith(prefix)) return null;
    return abs.substring(prefix.length);
  }

  static Uint8List? _asBytes(Object? stdout) {
    if (stdout is Uint8List) return stdout;
    if (stdout is List<int>) return Uint8List.fromList(stdout);
    if (stdout is String) return Uint8List.fromList(utf8.encode(stdout));
    return null;
  }

  /// Heurística alinhada ao Git: NUL nos primeiros 8 KiB ⇒ binário.
  static bool _isBinary(Uint8List bytes) {
    final n = bytes.length < 8192 ? bytes.length : 8192;
    for (var i = 0; i < n; i++) {
      if (bytes[i] == 0) return true;
    }
    return false;
  }
}
