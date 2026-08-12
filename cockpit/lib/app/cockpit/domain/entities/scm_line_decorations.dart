/// Marcadores SCM imutáveis do buffer atual em relação ao baseline `HEAD`.
///
/// [addedLines] e [modifiedLines] usam numeração **base 1** das linhas atuais.
/// [removalBoundaries] usa fronteiras `0..lineCount`: `0` = antes da primeira
/// linha; `lineCount` = depois da última. Fronteiras repetidas são consolidadas
/// no [Set].
class ScmLineDecorations {
  const ScmLineDecorations({
    required this.addedLines,
    required this.modifiedLines,
    required this.removalBoundaries,
  });

  static const empty = ScmLineDecorations(
    addedLines: <int>{},
    modifiedLines: <int>{},
    removalBoundaries: <int>{},
  );

  /// Linhas atuais (base 1) introduzidas sem correspondente no baseline.
  final Set<int> addedLines;

  /// Linhas atuais (base 1) que substituem linhas do baseline.
  final Set<int> modifiedLines;

  /// Fronteiras `0..lineCount` onde linhas do baseline foram removidas.
  final Set<int> removalBoundaries;

  bool get isEmpty =>
      addedLines.isEmpty && modifiedLines.isEmpty && removalBoundaries.isEmpty;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ScmLineDecorations &&
        _setEq(addedLines, other.addedLines) &&
        _setEq(modifiedLines, other.modifiedLines) &&
        _setEq(removalBoundaries, other.removalBoundaries);
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(addedLines),
    Object.hashAllUnordered(modifiedLines),
    Object.hashAllUnordered(removalBoundaries),
  );

  @override
  String toString() =>
      'ScmLineDecorations(added: $addedLines, modified: $modifiedLines, '
      'removals: $removalBoundaries)';

  static bool _setEq(Set<int> a, Set<int> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }
}
