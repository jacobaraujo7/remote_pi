/// Motivos de falha ao ler o historico Git.
enum GitHistoryErrorKind { commandFailed }

/// Falha tipada da leitura read-only do historico Git.
///
/// [detail] e saida de terceiros e deve ser exibido sem traducao pela UI.
class GitHistoryError implements Exception {
  const GitHistoryError(this.kind, {this.detail});

  final GitHistoryErrorKind kind;
  final String? detail;
}
