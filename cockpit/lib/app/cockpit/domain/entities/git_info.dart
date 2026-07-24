import 'package:cockpit/app/cockpit/domain/entities/git_file_status.dart';

/// Estado git de um projeto (workspace): branch atual, posição relativa ao
/// upstream (ahead/behind) e o status por arquivo sujo.
class GitInfo {
  const GitInfo({
    required this.branch,
    this.ahead = 0,
    this.behind = 0,
    this.files = const <String, GitFileStatus>{},
    this.stagedFiles = const <String, GitFileStatus>{},
    this.changedFiles = const <String, GitFileStatus>{},
    this.ignored = const <String>{},
    this.untrackedDirs = const <String>{},
  });

  /// Branch atual (ou short SHA se detached HEAD).
  final String branch;

  /// Commits à **frente** do upstream (precisam de push). 0 se não há upstream.
  final int ahead;

  /// Commits **atrás** do upstream (precisam de pull). 0 se não há upstream.
  /// Reflete o último `fetch` conhecido — não buscamos do remoto sozinhos.
  final int behind;

  /// Status por arquivo sujo. Chave = caminho **relativo à raiz do projeto**,
  /// sempre com separador `/`. Vazio = árvore limpa.
  final Map<String, GitFileStatus> files;

  /// Entradas presentes no index (a seção **Staged Changes**).
  final Map<String, GitFileStatus> stagedFiles;

  /// Entradas pendentes no working tree (a seção **Changes**). Um arquivo pode
  /// estar nos dois mapas quando recebeu novas edições depois do stage.
  final Map<String, GitFileStatus> changedFiles;

  /// Raízes ignoradas pelo `.gitignore` (caminhos relativos, sem barra final;
  /// `git` colapsa pastas ignoradas → um caminho cobre tudo abaixo dele). Não
  /// contam como sujo; só pintam a árvore de cinza.
  final Set<String> ignored;

  /// Diretórios **untracked colapsados** pelo `git` (uma pasta totalmente nova
  /// vira uma única entrada `?? dir/`; os filhos não são enumerados). Guardamos
  /// a raiz (sem barra) pra colorir todos os descendentes como untracked.
  final Set<String> untrackedDirs;

  /// `true` se [rel] (caminho relativo, separador `/`) está sob algo ignorado.
  bool isIgnored(String rel) => _under(ignored, rel);

  /// `true` se [rel] está sob um diretório untracked colapsado.
  bool isUntracked(String rel) => _under(untrackedDirs, rel);

  static bool _under(Set<String> roots, String rel) {
    if (roots.isEmpty) return false;
    if (roots.contains(rel)) return true;
    for (final root in roots) {
      if (rel.startsWith('$root/')) return true;
    }
    return false;
  }

  /// Nº de arquivos com mudança. 0 = árvore limpa.
  int get dirtyCount => files.length;

  bool get isDirty => files.isNotEmpty;

  /// `true` quando há divergência de commits com o upstream.
  bool get hasUpstreamDiff => ahead > 0 || behind > 0;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GitInfo &&
        other.branch == branch &&
        other.ahead == ahead &&
        other.behind == behind &&
        _sameFiles(other.files, files) &&
        _sameFiles(other.stagedFiles, stagedFiles) &&
        _sameFiles(other.changedFiles, changedFiles) &&
        other.ignored.length == ignored.length &&
        other.ignored.containsAll(ignored) &&
        other.untrackedDirs.length == untrackedDirs.length &&
        other.untrackedDirs.containsAll(untrackedDirs);
  }

  @override
  int get hashCode => Object.hash(
    branch,
    ahead,
    behind,
    files.length,
    stagedFiles.length,
    changedFiles.length,
    ignored.length,
    untrackedDirs.length,
  );

  static bool _sameFiles(
    Map<String, GitFileStatus> a,
    Map<String, GitFileStatus> b,
  ) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }
}
