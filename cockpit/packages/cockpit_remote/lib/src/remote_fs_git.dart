import 'dart:convert';
import 'dart:typed_data';

import 'package:cockpit_core/cockpit_core.dart';

import 'remote_connection.dart';

/// [FileService] via protocolo (Wave 3). Reidrata as exceptions tipadas a
/// partir do `code` do servidor, pra UI tratar igual ao caminho local.
class RemoteFileService implements FileService, ExclusiveFileCreator {
  RemoteFileService(this._connection);

  final RemoteConnection _connection;

  @override
  Future<List<FileEntry>> list(String path) async {
    final data = await _call('fs.list', {'path': path});
    return [
      for (final e in (data['entries'] as List).cast<Map>())
        FileEntry.fromJson(e.cast<String, Object?>()),
    ];
  }

  @override
  Future<Uint8List> read(String path, {int maxBytes = 8 * 1024 * 1024}) async {
    final data = await _call('fs.read', {'path': path, 'max': maxBytes});
    return base64Decode(data['b64'] as String);
  }

  @override
  Future<String> home() async {
    final data = await _call('fs.home', const {});
    return data['home'] as String? ?? '';
  }

  @override
  Future<bool> createNew(String path, Uint8List bytes) async {
    // A distinct method fails closed on older hosts; never fall back to write,
    // which could silently overwrite a pre-existing file.
    final data = await _call('fs.create', {
      'path': path,
      'b64': base64Encode(bytes),
    });
    final created = data['created'];
    if (created is! bool) {
      throw const FileException(
        FileErrorKind.io,
        'Invalid exclusive-create response',
      );
    }
    return created;
  }

  @override
  Future<void> write(String path, Uint8List bytes) async {
    try {
      await _connection.call('fs.write', {
        'path': path,
        'b64': base64Encode(bytes),
      });
    } on RemoteRpcException catch (e) {
      throw FileException(_fileKind(e.code), e.detail);
    }
  }

  Future<Map<String, Object?>> _call(
    String method,
    Map<String, Object?> params,
  ) async {
    try {
      return ((await _connection.call(method, params)) as Map)
          .cast<String, Object?>();
    } on RemoteRpcException catch (e) {
      throw FileException(_fileKind(e.code), e.detail);
    }
  }

  static FileErrorKind _fileKind(String code) =>
      FileErrorKind.values.asNameMap()[code] ?? FileErrorKind.io;
}

/// [GitService] via protocolo (Wave 3).
class RemoteGitService implements GitService {
  RemoteGitService(this._connection);

  final RemoteConnection _connection;

  @override
  Future<GitStatus> status(String repoPath) async {
    final data = await _call('git.status', {'repo': repoPath});
    return GitStatus.fromJson(data.cast<String, Object?>());
  }

  @override
  Future<String> diff(
    String repoPath,
    String file, {
    bool staged = false,
  }) async {
    final data = await _call('git.diff', {
      'repo': repoPath,
      'file': file,
      'staged': staged,
    });
    return data['diff'] as String;
  }

  @override
  Future<void> stage(String repoPath, List<String> files) =>
      _call('git.stage', {'repo': repoPath, 'files': files});

  @override
  Future<void> unstage(String repoPath, List<String> files) =>
      _call('git.unstage', {'repo': repoPath, 'files': files});

  @override
  Future<void> commit(String repoPath, String message) =>
      _call('git.commit', {'repo': repoPath, 'message': message});

  @override
  Future<GitRunResult> run(String repoPath, List<String> args) async {
    final data = await _call('git.run', {'repo': repoPath, 'args': args});
    return GitRunResult.fromJson(data.cast<String, Object?>());
  }

  Future<Map<String, Object?>> _call(
    String method,
    Map<String, Object?> params,
  ) async {
    try {
      final result = await _connection.call(method, params);
      return result is Map ? result.cast<String, Object?>() : const {};
    } on RemoteRpcException catch (e) {
      throw GitException(
        e.code == 'notARepo' ? GitErrorKind.notARepo : GitErrorKind.command,
        e.detail,
      );
    }
  }
}
