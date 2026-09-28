import 'dart:io';
import 'dart:typed_data';

import 'package:cockpit/app/cockpit/domain/contracts/file_change_watcher.dart';
import 'package:cockpit/app/cockpit/domain/entities/file_node.dart';
import 'package:cockpit/app/cockpit/ui/session/document_host.dart';
import 'package:cockpit/app/cockpit/ui/session/file_viewer_session.dart';
import 'package:cockpit/app/core/data/lsp/lsp_text_edit.dart';
import 'package:cockpit/app/core/domain/entities/lsp_diagnostic.dart';
import 'package:cockpit/app/core/domain/entities/lsp_semantic_tokens.dart';
import 'package:cockpit/app/core/domain/exceptions/file_operation_error.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:cockpit/app/core/utils/path_utils.dart';

/// [DocumentHost] da **janela de documento**: um arquivo (ou `.notebook`)
/// aberto solto, fora do shell do Cockpit. Filesystem direto por `dart:io`;
/// **sem LSP e sem git** — a janela mostra e edita; diagnóstico, formatação
/// por servidor e source control ficam no workspace do app. Manter isso
/// pequeno é o que deixa a janela abrir em menos de um segundo.
class StandaloneDocumentHost implements DocumentHost {
  StandaloneDocumentHost({required this.workspaceRoot, required this.changes});

  /// Raiz "de fato" do arquivo: a pasta mais próxima acima dele com `.git`,
  /// ou a própria pasta do arquivo quando não há repositório. Só serve para
  /// o caminho de exibição (breadcrumb) e o limite de leitura do preview.
  final String workspaceRoot;

  /// Live-reload do caderno (mesmo serviço da aba e do arquivo solto).
  final FileChangeWatcher changes;

  /// Sobe a partir de [path] até achar uma pasta com `.git`. Sem repositório,
  /// devolve a pasta que contém [path].
  static String findWorkspaceRoot(String path) {
    final start = FileSystemEntity.isDirectorySync(path)
        ? Directory(path)
        : File(path).parent;
    var dir = start;
    while (true) {
      if (Directory(joinPath(dir.path, '.git')).existsSync() ||
          File(joinPath(dir.path, '.git')).existsSync()) {
        return dir.path;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) return start.path;
      dir = parent;
    }
  }

  @override
  String? projectRootOf(String projectId) =>
      workspaceRoot.isEmpty ? null : workspaceRoot;

  @override
  String displayPath(String projectId, String absolutePath) {
    if (workspaceRoot.isEmpty) return absolutePath;
    final prefix = workspaceRoot.endsWith(Platform.pathSeparator)
        ? workspaceRoot
        : '$workspaceRoot${Platform.pathSeparator}';
    return absolutePath.startsWith(prefix)
        ? absolutePath.substring(prefix.length)
        : absolutePath;
  }

  // ---- SCM / LSP: fora do escopo da janela solta (no-ops) -----------------

  @override
  void ensureScmCoordinator(FileViewerSession session) {}

  @override
  Future<void> lspOpenDocument(String path, String text, String projectId) =>
      Future.value();

  @override
  Future<void> lspChangeDocument(String path, String text) => Future.value();

  @override
  Future<void> lspCloseDocument(String path) => Future.value();

  @override
  Stream<LspDiagnosticsBatch> get lspDiagnostics =>
      const Stream<LspDiagnosticsBatch>.empty();

  @override
  Future<List<LspTextEdit>> lspFormat(String path, String text) =>
      Future.value(const <LspTextEdit>[]);

  @override
  Future<SemanticTokens> lspSemanticTokensFull(String path) =>
      Future.value(const SemanticTokens(tokens: []));

  @override
  Future<void> goToDefinition(String path, int line, int character) =>
      Future.value();

  // ---- filesystem ----------------------------------------------------------

  @override
  Future<List<FileNode>> listChildren(String path) async {
    final out = <FileNode>[];
    try {
      await for (final e in Directory(path).list(followLinks: false)) {
        out.add(
          FileNode(
            name: e.path.split(Platform.pathSeparator).last,
            path: e.path,
            isDirectory: e is Directory,
          ),
        );
      }
    } on FileSystemException {
      return const [];
    }
    out.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return out;
  }

  @override
  Future<String?> readTextAt(String path) async {
    try {
      return await File(path).readAsString();
    } on FileSystemException {
      return null;
    }
  }

  @override
  Stream<void> watchFolder(String path) => changes.watchFolder(path);

  @override
  Future<bool> writeTextAt(String path, String content) async {
    try {
      await File(path).writeAsString(content, flush: true);
      return true;
    } on FileSystemException {
      return false;
    }
  }

  @override
  Future<bool> writeBytesAt(String path, Uint8List bytes) async {
    try {
      await File(path).writeAsBytes(bytes, flush: true);
      return true;
    } on FileSystemException {
      return false;
    }
  }

  @override
  Future<Result<void, FileOperationError>> deletePath(String path) async {
    try {
      final type = FileSystemEntity.typeSync(path, followLinks: false);
      if (type == FileSystemEntityType.notFound) {
        return const Failure(
          FileOperationError(FileOperationErrorKind.notFound),
        );
      }
      if (type == FileSystemEntityType.directory) {
        await Directory(path).delete(recursive: true);
      } else {
        await File(path).delete();
      }
      return const Success(null);
    } on FileSystemException catch (e) {
      return Failure(
        FileOperationError(FileOperationErrorKind.osFailure, detail: e.message),
      );
    }
  }
}
