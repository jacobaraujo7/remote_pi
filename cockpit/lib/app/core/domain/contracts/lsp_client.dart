import 'package:cockpit/app/core/domain/entities/lsp_diagnostic.dart';
import 'package:cockpit/app/core/domain/exceptions/lsp_error.dart';
import 'package:cockpit/app/core/domain/result.dart';

/// Como ligar um language server: o comando (binário + args) e o `languageId`
/// LSP que o servidor atende. A tabela `lsp_launchers.dart` (Wave 2) produz uma
/// destas por linguagem; na Wave 0 é construída na mão para o Dart.
class LspServerSpec {
  const LspServerSpec({
    required this.languageId,
    required this.executable,
    this.args = const <String>[],
  });

  /// `languageId` do LSP (ex.: `dart`, `typescript`, `php`). Vai no `didOpen`.
  final String languageId;

  /// Caminho/nome do binário do servidor (resolvido no PATH antes de spawnar).
  final String executable;

  /// Argumentos fixos (ex.: `language-server`, `--stdio`).
  final List<String> args;
}

/// Cliente de **um** language server (um processo, uma raiz de projeto). Fala
/// JSON-RPC 2.0 com framing `Content-Length` por stdin/stdout. O pool
/// (`LspServerPool`) é quem cria/reusa/descarta instâncias por
/// `(linguagem, raiz)` — este contrato é a peça de baixo nível.
abstract class LspClient {
  /// Diagnostics publicados pelo servidor (`textDocument/publishDiagnostics`),
  /// um batch por documento a cada publicação. Broadcast.
  Stream<LspDiagnosticsBatch> get diagnostics;

  bool get isRunning;

  /// Raiz absoluta do projeto que este servidor atende.
  String get rootPath;

  /// Spawna o processo e faz o handshake (`initialize` → `initialized`).
  Future<Result<void, LspError>> start();

  /// `textDocument/didOpen`. [path] é absoluto; vira `file://` URI internamente.
  Future<void> didOpen({required String path, required String text});

  /// `textDocument/didChange` (full sync). [version] cresce a cada edição.
  Future<void> didChange({
    required String path,
    required String text,
    required int version,
  });

  /// `textDocument/didClose`.
  Future<void> didClose({required String path});

  /// Request JSON-RPC genérico (ex.: `textDocument/formatting` na Wave 3).
  /// Lança/retorna falha em timeout ou erro do servidor.
  Future<Result<Object?, LspError>> request(
    String method,
    Map<String, dynamic> params,
  );

  /// Encerra graciosamente (`shutdown`/`exit` → close stdin → SIGTERM → SIGKILL).
  Future<void> kill();

  /// Rede de segurança síncrona (shutdown do app): mata o processo sem órfão.
  void dispose();
}

/// Fábrica de [LspClient] — interface nomeada (não `Function()`) para seguir a
/// regra de injeção `.new` do projeto (o parser do auto_injector quebra em
/// `X Function()`). O pool injeta esta factory e cria um cliente por raiz.
abstract class LspClientFactory {
  LspClient create({required LspServerSpec spec, required String rootPath});
}
