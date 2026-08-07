import 'package:cockpit/app/cockpit/domain/entities/worktree.dart';
import 'package:cockpit/app/core/domain/result.dart';

/// Falha de uma operação de worktree, carregando a saída do git pra mostrar
/// inline no dialog (plan/42, decisão 21).
class WorktreeOpError {
  const WorktreeOpError(this.message);

  /// Mensagem legível (geralmente o stderr do git).
  final String message;
}

/// Handle ao vivo de um `git worktree add`: stream de stdout/stderr + resultado
/// final. A UI escuta [output] enquanto o comando (e o post-checkout, se houver)
/// roda, e reage a [result] pra fechar ou mostrar erro.
///
/// [T] é [Worktree] no manager e [Project] no ViewModel (após refresh/select).
class WorktreeAddRun<T> {
  const WorktreeAddRun({required this.output, required this.result});

  /// Linhas de stdout/stderr na ordem que chegam.
  final Stream<String> output;

  /// Completa quando o `worktree add` (e o pós-processamento do VM) termina.
  final Future<Result<T, WorktreeOpError>> result;
}

/// Branches locais + nomes de worktree já em uso num repo — insumo da validação
/// de unicidade (decisão 11), coletado uma vez quando o dialog de criar abre.
class WorktreeNamespace {
  const WorktreeNamespace({
    required this.branches,
    required this.worktreeNames,
    this.remoteBranches = const <String>{},
    this.defaultBranch,
  });

  const WorktreeNamespace.empty()
    : branches = const <String>{},
      worktreeNames = const <String>{},
      remoteBranches = const <String>{},
      defaultBranch = null;

  /// Nomes de branch locais (`git branch`).
  final Set<String> branches;

  /// Nomes (basename) das worktrees existentes (`git worktree list`).
  final Set<String> worktreeNames;

  /// Nomes de branch remotas (`git branch -r`).
  final Set<String> remoteBranches;

  /// A branch principal padrão (geralmente detectada do remote HEAD).
  final String? defaultBranch;
}

/// Lado **mutável** do git pro Cockpit: listar/criar/remover worktrees. Contrato
/// no domínio; a impl (roda `git worktree …`) mora em `data/`. O lado de leitura
/// de estado (branch/dirtyCount) continua no [GitStatusReader] — não misturar.
abstract class WorktreeManager {
  /// Worktrees de [repoPath], **excluindo** a raiz (que é o próprio workspace).
  /// Lista vazia se [repoPath] não é repo git ou o git está indisponível
  /// (decisões 4, 5).
  Future<List<Worktree>> list(String repoPath);

  /// Branches locais + nomes de worktree de [repoPath], pra alimentar a
  /// validação de unicidade. Vazio se não-git/erro.
  Future<WorktreeNamespace> namespace(String repoPath);

  /// `true` se o repo tem um hook `post-checkout` resolvido via
  /// `git rev-parse --git-path hooks` (respeita `core.hooksPath` / husky).
  Future<bool> hasPostCheckoutHook(String repoPath);

  /// Cria uma worktree em `<repoPath>/.cockpit/worktrees/<name>` numa branch
  /// **nova** [name] (decisões 2, 3, 15), garantindo antes que
  /// `.cockpit/worktrees/` está no `.gitignore` do repo. A base é o HEAD atual
  /// do repo, ou [baseRef] quando informado ("Fork Worktree": ramifica da
  /// branch de outro fork, mas a pasta nasce sempre sob o repo de origem —
  /// nunca aninhada dentro de outra worktree). [name] já deve ter passado pela
  /// validação de nome.
  ///
  /// Devolve o handle imediatamente (stream ao vivo); o [WorktreeAddRun.result]
  /// resolve no fim. O post-checkout do repo, se existir, roda dentro do git e
  /// aparece no stream.
  WorktreeAddRun<Worktree> add(
    String repoPath,
    String name, {
    String? baseRef,
    bool copyIgnored = false,
    bool copyUntracked = false,
  });

  /// Remove a worktree em [worktreePath] e, se [branch] não for vazio, apaga a
  /// branch (decisão 6 — `git worktree remove` **antes** de `git branch -D`).
  Future<Result<void, WorktreeOpError>> remove(
    String repoPath,
    String worktreePath,
    String branch,
  );

  /// `true` se [branch] já foi mergeada na linha principal do repo (`git branch
  /// --merged`). Alimenta o aviso de "branch não-mergeada" antes de remover
  /// (decisão 6). Em dúvida/erro, retorna `false` (mostra o aviso por segurança).
  Future<bool> isBranchMerged(String repoPath, String branch);
}
