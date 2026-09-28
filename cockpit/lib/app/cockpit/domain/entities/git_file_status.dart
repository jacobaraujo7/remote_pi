/// Estado git de **um** caminho (arquivo ou pasta agregada) na árvore.
///
/// A ordem da declaração é a **precedência** de severidade (do mais fraco ao
/// mais forte): ao agregar uma pasta, vence o estado de maior `index`
/// ([strongest]). Ex.: uma pasta com um untracked e um modified mostra
/// `modified`; com um conflito, mostra `conflict`.
enum GitFileStatus {
  /// Ignorado pelo `.gitignore` (`!!`). O mais fraco — qualquer mudança real
  /// vence na agregação de pasta.
  ignored,

  /// Arquivo novo, ainda não rastreado (`??`).
  untracked,

  /// Mudança no index (staged) sem mudança pendente no working tree.
  staged,

  /// Mudança no working tree ainda não comitada (modificado/typechange).
  modified,

  /// Removido (no index ou no working tree).
  deleted,

  /// Conflito de merge (ambos os lados mexeram — `UU`, `AA`, `DD`, …).
  conflict;

  /// O mais severo entre dois estados (maior `index` vence). `null` é o vazio.
  static GitFileStatus? strongest(GitFileStatus? a, GitFileStatus? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.index >= b.index ? a : b;
  }

  /// Como o estado de um DESCENDENTE contribui para a cor de uma pasta.
  /// Deleção não sobe como deleção: o arquivo removido nem aparece na árvore,
  /// e pintar a pasta de vermelho por causa dele escondia os arquivos novos
  /// ao lado (pasta com um `rm` e três arquivos criados ficava "excluída").
  /// Para a pasta, uma remoção é uma mudança comum. Conflito segue subindo.
  static GitFileStatus? strongestForFolder(
    GitFileStatus? folder,
    GitFileStatus child,
  ) => strongest(
    folder,
    child == GitFileStatus.deleted ? GitFileStatus.modified : child,
  );
}
