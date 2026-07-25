/// Commit disponível como alvo de amend no Source Control.
class GitCommit {
  const GitCommit({
    required this.hash,
    required this.subject,
    required this.message,
  });

  final String hash;
  final String subject;
  final String message;
}
