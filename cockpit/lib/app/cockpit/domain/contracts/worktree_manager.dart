import 'package:cockpit/app/cockpit/domain/entities/worktree.dart';
import 'package:cockpit/app/core/domain/result.dart';

/// Falha de uma operação de worktree, carregando a saída do git pra mostrar
/// inline no dialog (plan/42, decisão 21).
class WorktreeOpError {
  const WorktreeOpError(this.message);

  /// Mensagem legível (geralmente o stderr do git).
  final String message;
}

/// Branches locais + nomes de worktree já em uso num repo — insumo da validação
/// de unicidade (decisão 11), coletado uma vez quando o dialog de criar abre.
class WorktreeNamespace {
  const WorktreeNamespace({
    required this.branches,
    required this.worktreeNames,
  });

  const WorktreeNamespace.empty()
    : branches = const <String>{},
      worktreeNames = const <String>{};

  /// Nomes de branch locais (`git branch`).
  final Set<String> branches;

  /// Nomes (basename) das worktrees existentes (`git worktree list`).
  final Set<String> worktreeNames;
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

  /// Cria uma worktree em `<repoPath>/.cockpit/worktrees/<name>` numa branch
  /// **nova** [name] a partir do HEAD atual do repo (decisões 2, 3, 15),
  /// garantindo antes que `.cockpit/worktrees/` está no `.gitignore` do repo.
  /// [name] já deve ter passado pela validação de nome.
  Future<Result<Worktree, WorktreeOpError>> add(String repoPath, String name);

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
