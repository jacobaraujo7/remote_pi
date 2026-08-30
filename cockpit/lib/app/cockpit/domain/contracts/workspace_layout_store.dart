/// Persiste o layout do multiplexador de um projeto (árvore de panes + os
/// descritores de cada aba) como um **documento JSON opaco**, keyed por
/// `projectId`.
///
/// A *forma* do documento é detalhe da `ui/` (quem conhece `PaneNode` e as
/// sessões) — aqui é só um blob versionado que a `data/` guarda e devolve. Por
/// isso o contrato trafega `Map<String, dynamic>` em vez de um tipo do domínio:
/// o store não interpreta o conteúdo, só o persiste.
abstract class WorkspaceLayoutStore {
  /// Documento salvo do projeto, ou `null` se nunca foi salvo.
  Future<Map<String, dynamic>?> load(String projectId);

  /// Salva (sobrescreve) o documento do projeto.
  Future<void> save(String projectId, Map<String, dynamic> document);

  /// Remove o documento do projeto (ao deletar o projeto).
  Future<void> remove(String projectId);

  /// Todos os documentos salvos, por `projectId`.
  ///
  /// Existe para o GC do scrollback: ele precisa conhecer **todo** layout
  /// persistido, e não só os que já foram carregados em memória. Os forks de
  /// worktree entram na lista de projetos depois do boot, então varrer apenas
  /// o que estava carregado apagava o scrollback dos terminais deles.
  Future<Map<String, Map<String, dynamic>>> loadAll();
}
