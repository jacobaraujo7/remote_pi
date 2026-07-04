/// Tipo de uma linha num diff.
enum DiffLineKind { context, added, removed }

/// Uma linha de diff: o texto + os números de linha no lado antigo/novo (um deles
/// é `null` conforme o tipo — added não tem linha antiga, removed não tem nova).
class DiffLine {
  const DiffLine({
    required this.kind,
    required this.text,
    this.oldLine,
    this.newLine,
  });

  final DiffLineKind kind;
  final String text;
  final int? oldLine;
  final int? newLine;
}

/// Um hunk de diff (`@@ -a,b +c,d @@ …`) com suas linhas em ordem.
class DiffHunk {
  const DiffHunk({required this.header, required this.lines});

  /// A linha `@@ … @@` (com o eventual contexto de função à direita).
  final String header;
  final List<DiffLine> lines;
}

/// Como um arquivo se relaciona com o HEAD, pra o diff viewer decidir o layout.
enum FileDiffKind {
  /// Arquivo de texto rastreado e modificado (hunks normais).
  modified,

  /// Novo/untracked — sem versão no HEAD (lado esquerdo vazio, tudo adicionado).
  added,

  /// Removido — sem versão no working tree (lado direito vazio, tudo removido).
  deleted,

  /// Binário/imagem — sem diff textual.
  binary,

  /// Sem mudanças (idêntico ao HEAD).
  unchanged,
}

/// O diff de um arquivo contra o HEAD, já parseado — insumo **só leitura** do
/// `DiffViewer` (split). Sem ações.
class FileDiff {
  const FileDiff({
    required this.path,
    required this.kind,
    this.hunks = const [],
  });

  const FileDiff.binary(String path)
    : this(path: path, kind: FileDiffKind.binary);

  const FileDiff.unchanged(String path)
    : this(path: path, kind: FileDiffKind.unchanged);

  /// Caminho absoluto do arquivo.
  final String path;

  final FileDiffKind kind;

  /// Hunks parseados (vazio para binário/unchanged).
  final List<DiffHunk> hunks;
}
