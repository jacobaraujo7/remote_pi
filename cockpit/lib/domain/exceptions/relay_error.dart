/// Erro tipado das operações de conectividade (relay/aparelhos), já traduzido do
/// mundo de I/O em `data/` — shell-out do `remote-pi` ou leitura do config — para
/// algo que a UI entende. Nunca vaza `Exception` cru nem `ProcessResult`.
class RelayError {
  const RelayError(this.message, {this.cause, this.stackTrace});

  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() => 'RelayError: $message';
}
