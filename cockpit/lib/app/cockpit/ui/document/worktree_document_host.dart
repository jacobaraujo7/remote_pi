import 'dart:convert';
import 'dart:typed_data';

import 'package:cockpit_core/cockpit_core.dart';
import 'package:path/path.dart' as paths;
import '../../data/filesystem/file_reader_impl.dart';
import '../../domain/entities/file_node.dart';
import '../../domain/entities/file_view.dart';
import '../../../core/domain/exceptions/file_operation_error.dart';
import '../../../core/domain/result.dart';
import 'standalone_document_host.dart';

/// A document's immutable filesystem destination, independent of active project.
/// No global VM, tab registry, local fallback or process launch is available.
class WorktreeDocumentHost extends StandaloneDocumentHost {
  WorktreeDocumentHost({
    required super.workspaceRoot,
    required super.changes,
    required this.files,
    required this.remote,
    required this.available,
    paths.Context? pathContext,
  }) : pathContext =
           pathContext ??
           paths.Context(style: remote ? paths.Style.posix : paths.style);

  final FileService files;
  final bool remote;
  final bool Function() available;
  final paths.Context pathContext;

  void ensureAvailable() {
    if (!available()) {
      throw StateError('Originating document or host is unavailable');
    }
  }

  Future<T> _checked<T>(Future<T> Function() action) async {
    ensureAvailable();
    final result = await action();
    ensureAvailable();
    return result;
  }

  /// Resolve against the terminal cwd captured when the link was activated.
  Future<String> resolve(String value, {required String cwd}) async {
    ensureAvailable();
    if (value.isEmpty || value.contains('\u0000')) {
      throw const FormatException('Invalid document path');
    }
    var file = value;
    if (file.startsWith('file:')) file = pathContext.fromUri(Uri.parse(file));
    if (file == '~' || file.startsWith('~/')) {
      final home = await _checked(files.home);
      if (home.isEmpty) throw StateError('Source host HOME is unavailable');
      file = file == '~' ? home : pathContext.join(home, file.substring(2));
    }
    return pathContext.normalize(
      pathContext.isAbsolute(file) ? file : pathContext.join(cwd, file),
    );
  }

  Future<FileView> readView(String path) => _checked(() async {
    // Local media keeps the existing lazy native file/player path behavior.
    if (!remote) return const FileReaderImpl().read(path);
    return FileReaderImpl.fromBytes(
      path,
      await files.read(path, maxBytes: 2 * 1024 * 1024),
    );
  });

  @override
  String displayPath(String projectId, String absolutePath) =>
      pathContext.isWithin(workspaceRoot, absolutePath)
      ? pathContext.relative(absolutePath, from: workspaceRoot)
      : absolutePath;

  @override
  Future<List<FileNode>> listChildren(String path) => _checked(
    () async => [
      for (final item in await files.list(path))
        FileNode(
          name: item.name,
          path: pathContext.join(path, item.name),
          isDirectory: item.isDirectory,
        ),
    ],
  );

  @override
  Future<String?> readTextAt(String path) => _checked(
    () async => utf8.decode(await files.read(path), allowMalformed: true),
  );

  @override
  Stream<void> watchFolder(String path) {
    ensureAvailable();
    return changes.watchFolder(path);
  }

  @override
  Future<bool> writeTextAt(String path, String content) =>
      writeBytesAt(path, Uint8List.fromList(utf8.encode(content)));

  @override
  Future<bool> writeBytesAt(String path, Uint8List bytes) async {
    try {
      await _checked(() => files.write(path, bytes));
      return true;
    } on Object {
      return false;
    }
  }

  @override
  Future<Result<void, FileOperationError>> deletePath(String path) async {
    ensureAvailable();
    // The current remote FileService has no delete capability. Never inherit
    // standalone dart:io deletion for a path that belongs to another machine.
    if (remote) {
      return const Failure(
        FileOperationError(
          FileOperationErrorKind.osFailure,
          detail: 'Delete is unavailable on this source host',
        ),
      );
    }
    final result = await super.deletePath(path);
    ensureAvailable();
    return result;
  }
}
