/// Erro tipado das operações de daemon (supervisor), traduzido do mundo de I/O
/// em `data/` — UDS do `pi-supervisord` ou shell-out do `remote-pi`. Nunca vaza
/// `Exception` cru.
class DaemonError {
  const DaemonError(this.message, {this.cause, this.stackTrace});

  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() => 'DaemonError: $message';
}
