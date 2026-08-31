enum NeovimErrorKind { unavailable, connectionFailed, timeout }

/// Falha estruturada ao detectar ou controlar uma instância do Neovim.
///
/// [detail] é saída crua do processo e só deve ser interpolada pela UI.
class NeovimError implements Exception {
  const NeovimError(this.kind, {this.detail});

  final NeovimErrorKind kind;
  final String? detail;
}
