/// URL de repositório git aceita pelo fluxo "Clonar repositório": HTTPS/HTTP,
/// `ssh://` ou o formato scp do SSH (`git@github.com:org/repo.git`).
///
/// De propósito NÃO aceita caminho local, `file://`, `git://` nem transports
/// exóticos (`ext::`): o campo é pra colar o link do GitHub/GitLab/etc.
bool isGitCloneUrl(String raw) {
  final url = raw.trim();
  if (url.isEmpty || RegExp(r'\s').hasMatch(url)) return false;
  // Barra invertida nunca aparece numa URL git; aparece em caminho de Windows.
  if (url.contains(r'\')) return false;
  // `C:/Users/me/repo` casaria com o formato scp (host "C"); o git trata letra
  // de drive como caminho local, então aqui também é caminho, não URL.
  if (RegExp(r'^[A-Za-z]:[\\/]').hasMatch(url)) return false;
  final uri = Uri.tryParse(url);
  if (uri != null && uri.hasScheme) {
    const schemes = {'https', 'http', 'ssh', 'git+ssh'};
    return schemes.contains(uri.scheme) &&
        uri.host.isNotEmpty &&
        uri.pathSegments.any((s) => s.isNotEmpty) &&
        repoNameFromGitUrl(url) != null;
  }
  // scp-like: [user@]host:path (`git@host:/srv/repo.git` também vale).
  final scp = RegExp(r'^(?:[A-Za-z0-9._-]+@)?[A-Za-z0-9.-]+:(.+)$');
  return scp.hasMatch(url) && repoNameFromGitUrl(url) != null;
}

/// Nome da pasta que o `git clone` criaria pra [raw]: último segmento do path
/// sem `.git` (`https://github.com/org/repo.git` → `repo`). `null` quando não
/// há segmento utilizável.
String? repoNameFromGitUrl(String raw) {
  var path = raw.trim();
  // Query/fragment não fazem parte do nome.
  final cut = path.indexOf(RegExp('[?#]'));
  if (cut >= 0) path = path.substring(0, cut);
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  final slash = path.lastIndexOf('/');
  final colon = path.lastIndexOf(':');
  var name = path.substring((slash > colon ? slash : colon) + 1);
  if (name.endsWith('.git')) name = name.substring(0, name.length - 4);
  if (name.isEmpty || name == '.' || name == '..') return null;
  return name;
}
