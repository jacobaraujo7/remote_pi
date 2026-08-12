/// Um commit imutavel do historico do repositorio.
///
/// Diferente de [GitCommit], que atende exclusivamente ao fluxo de amend, este
/// modelo traz os metadados e arestas necessarios para desenhar o grafo.
class GitHistoryCommit {
  const GitHistoryCommit({
    required this.hash,
    required this.parents,
    required this.refs,
    required this.subject,
    required this.author,
    required this.authoredAt,
  });

  final String hash;
  final List<String> parents;
  final List<String> refs;
  final String subject;
  final String author;
  final DateTime? authoredAt;

  String get shortHash => hash.length <= 8 ? hash : hash.substring(0, 8);

  bool get isHead =>
      refs.any((ref) => ref == 'HEAD' || ref.startsWith('HEAD -> '));
}
