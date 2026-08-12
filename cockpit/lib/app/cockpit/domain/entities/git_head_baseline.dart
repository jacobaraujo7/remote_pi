/// Conteúdo textual de um arquivo rastreado no commit apontado por `HEAD`.
class GitHeadBaseline {
  const GitHeadBaseline({required this.headIdentity, required this.content});

  /// Identidade estável de `HEAD` (`git rev-parse HEAD`) no momento da leitura.
  final String headIdentity;

  /// Texto do blob em `HEAD` (UTF-8 tolerante).
  final String content;
}
