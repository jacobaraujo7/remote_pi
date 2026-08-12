/// Um arquivo alterado por um commit do historico Git.
class GitHistoryFileChange {
  const GitHistoryFileChange({
    required this.status,
    required this.path,
    this.previousPath,
  });

  /// Codigo `--name-status` do Git, como A, M, D ou R100.
  final String status;
  final String path;

  /// Caminho antes da renomeacao/copia; nulo nas outras operacoes.
  final String? previousPath;

  List<String> get _pathParts =>
      path.split('/').where((part) => part.isNotEmpty).toList();

  String get fileName => _pathParts.last;

  /// Pasta imediatamente acima do arquivo; e o contexto mais util no painel
  /// estreito, sem gastar a largura com a raiz inteira do repositorio.
  String? get parentDirectory =>
      _pathParts.length < 2 ? null : _pathParts[_pathParts.length - 2];

  String get displayPath =>
      previousPath == null ? path : '$previousPath → $path';

  String get displayLabel => switch (parentDirectory) {
    final parent? => '$fileName - $parent',
    null => fileName,
  };
}
