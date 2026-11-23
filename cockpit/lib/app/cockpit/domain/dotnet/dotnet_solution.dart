/// Nó lógico de uma solução .NET, no formato do Solution Explorer.
enum DotnetNodeKind { solution, solutionFolder, project, folder, file }

/// Um item da árvore lógica. Arquivos do projeto no disco não entram aqui:
/// a UI lista [directory] sob demanda.
class DotnetNode {
  const DotnetNode({
    required this.id,
    required this.kind,
    required this.name,
    this.path,
    this.directory,
    this.projectCount = 0,
    this.children = const [],
  });

  final String id;
  final DotnetNodeKind kind;
  final String name;

  /// Arquivo que abre no viewer (projeto ou fonte).
  final String? path;

  /// Pasta cujos filhos físicos são lidos ao expandir.
  final String? directory;

  /// Projetos descendentes. Só solução e solution folder mostram o total.
  final int projectCount;
  final List<DotnetNode> children;

  bool get showsChevron {
    switch (kind) {
      case DotnetNodeKind.solution:
      case DotnetNodeKind.solutionFolder:
      case DotnetNodeKind.project:
      case DotnetNodeKind.folder:
        return children.isNotEmpty || directory != null;
      case DotnetNodeKind.file:
        return false;
    }
  }
}

/// Solução já analisada, pronta pra cachear e desenhar.
class DotnetSolutionSnapshot {
  const DotnetSolutionSnapshot({
    required this.path,
    required this.name,
    required this.fingerprint,
    required this.projectPaths,
    required this.root,
  });

  final String path;
  final String name;
  final String fingerprint;

  /// Projetos lidos junto da solução. O watch observa estes arquivos.
  final List<String> projectPaths;
  final DotnetNode root;

  DotnetSolutionSnapshot withFingerprint(String fingerprint) {
    return DotnetSolutionSnapshot(
      path: path,
      name: name,
      fingerprint: fingerprint,
      projectPaths: projectPaths,
      root: root,
    );
  }
}

/// Solução achada no scan leve, antes de qualquer parse.
class DotnetSolutionRef {
  const DotnetSolutionRef({
    required this.path,
    required this.name,
    required this.depth,
  });

  final String path;
  final String name;
  final int depth;
}

/// Pastas e projetos antes dos arquivos. Cada grupo fica em ordem alfabética,
/// sem diferenciar maiúsculas — o mesmo critério do Solution Explorer do Rider.
int compareSolutionNames({
  required bool aIsFile,
  required String aName,
  required bool bIsFile,
  required String bName,
}) {
  if (aIsFile != bIsFile) return aIsFile ? 1 : -1;
  return aName.toLowerCase().compareTo(bName.toLowerCase());
}
