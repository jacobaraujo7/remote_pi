/// Erro tipado das operações de LSP, já traduzido do mundo de I/O em `data/`
/// (spawn do language server, framing JSON-RPC) para algo que a UI entende.
/// Nunca vaza `Exception` cru nem `ProcessResult`.
class LspError {
  const LspError(this.message, {this.cause, this.stackTrace});

  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() => 'LspError: $message';
}
