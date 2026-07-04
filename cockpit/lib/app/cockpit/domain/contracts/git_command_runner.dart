/// Um comando `git` em execução: stream unificado de stdout+stderr (por linha) e
/// o exit code final. A UI (dialog de processo) escuta [output] ao vivo e reage
/// a [exitCode] pra mostrar ✅/❌.
class GitRun {
  const GitRun({required this.output, required this.exitCode});

  /// stdout e stderr mesclados, uma linha por evento, na ordem que chegam.
  final Stream<String> output;

  /// Completa quando o processo termina. Convenção git: `0` = sucesso.
  final Future<int> exitCode;
}

/// Como um `mergeIntoParent` terminou.
enum GitMergeStatus {
  /// Merge concluído e worktree+branch removidos.
  merged,

  /// Worktree tinha mudanças não commitadas → nada foi feito.
  dirtyWorktree,

  /// Merge deu conflito → `git merge --abort` rodado, pai intocado.
  conflict,

  /// Falha inesperada (git ausente, remoção falhou, etc).
  error,
}

/// Handle **ao vivo** de um `mergeIntoParent`: stream de linhas + o status final
/// (quando o processo termina), pra o dialog mostrar o processo e reagir a ✅/❌.
class GitMergeOutcome {
  const GitMergeOutcome({required this.status, required this.output});

  /// Resolve quando o merge (e a limpeza/abort) termina.
  final Future<GitMergeStatus> status;

  /// Linhas do merge (e do abort, se houve conflito), na ordem que chegam.
  final Stream<String> output;
}

/// Lado **de escrita/sincronização** do git pro Cockpit: roda comandos e devolve
/// o processo ao vivo. Separado do [WorktreeManager] (worktrees) e do
/// [GitStatusReader] (leitura de estado). A impl mora em `data/`.
abstract class GitCommandRunner {
  /// Roda `git -C <repoPath> <args>` e devolve o processo ao vivo. Baixo nível —
  /// usado por Pull (`['pull']`) e Push (`['push']`).
  GitRun run(String repoPath, List<String> args);

  /// Sync = `git pull` e, se terminar com exit 0, `git push` — no mesmo stream
  /// (linhas prefixadas por `$ git pull` / `$ git push`). Para no primeiro
  /// comando que falhar.
  GitRun syncPullPush(String repoPath);

  /// Mergeia [worktreeBranch] no checkout do pai em [parentPath].
  ///
  /// 1. Se o worktree em [worktreePath] tem mudanças não commitadas → devolve
  ///    [GitMergeStatus.dirtyWorktree] sem tocar em nada.
  /// 2. `git -C <parentPath> merge <worktreeBranch>`. Conflito → `merge --abort`
  ///    e [GitMergeStatus.conflict] (pai intocado).
  /// 3. Sucesso → [GitMergeStatus.merged]. A remoção do worktree/branch é feita
  ///    pelo chamador (o `CockpitViewModel` reusa `removeWorktree`).
  ///
  /// Devolve o handle imediatamente (stream ao vivo); o `status` resolve no fim.
  GitMergeOutcome mergeIntoParent(
    String parentPath,
    String worktreePath,
    String worktreeBranch,
  );
}
