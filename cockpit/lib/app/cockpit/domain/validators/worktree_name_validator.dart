/// Por que a validação falhou — granular o suficiente pro dialog mostrar a causa
/// certa ao vivo (plan/42, decisões 10, 11).
enum WorktreeNameError {
  /// Vazio (nada digitado ainda).
  empty,

  /// Contém espaço (ou outro whitespace) — regra explícita do usuário.
  whitespace,

  /// Contém caractere que o git rejeita: `~ ^ : ? * [ \` ou control char.
  invalidChar,

  /// Sequência/posição inválida: `..`, `@{`, `//`, começa/termina com `/`, é só `@`.
  invalidSequence,

  /// Reservado: começa com `-`/`.`, termina em `.`/`.lock`, ou um componente
  /// (separado por `/`) começa com `.` ou termina em `.lock`.
  reserved,

  /// Já existe uma branch local com esse nome.
  duplicateBranch,

  /// Já existe uma worktree com esse nome.
  duplicateWorktree,

  /// Já existe um branch com uma hierarquia conflitante (D/F conflict).
  branchHierarchicalConflict,
}

/// Resultado da validação de um nome de worktree/branch.
class WorktreeNameCheck {
  const WorktreeNameCheck.valid() : error = null;
  const WorktreeNameCheck.invalid(this.error);

  /// `null` quando válido; senão a causa.
  final WorktreeNameError? error;

  bool get isValid => error == null;
}

/// Valida um nome de worktree como branch nova do git — **Dart puro**, sem I/O,
/// pra dar feedback instantâneo no dialog e ser testável sem o binário git. É
/// uma reimplementação fiel do subconjunto documentado de `git check-ref-format
/// --branch` (decisão 10); o `git worktree add` real continua sendo o gate final.
///
/// Unicidade (decisão 11) é checada contra os conjuntos passados — branches
/// locais + worktrees existentes — coletados uma vez quando o dialog abre.
class WorktreeNameValidator {
  const WorktreeNameValidator();

  static const Set<String> _forbiddenChars = <String>{
    ' ', '\t', '\n', '\r', // whitespace tratado antes, mas defensivo
    '~', '^', ':', '?', '*', '[', r'\',
  };

  WorktreeNameCheck validate(
    String name, {
    required Set<String> existingBranches,
    required Set<String> existingWorktreeNames,
  }) {
    if (name.isEmpty) {
      return const WorktreeNameCheck.invalid(WorktreeNameError.empty);
    }

    // 1. Whitespace (regra explícita do usuário — mensagem própria).
    for (final unit in name.codeUnits) {
      if (unit == 0x20 || unit == 0x09 || unit == 0x0a || unit == 0x0d) {
        return const WorktreeNameCheck.invalid(WorktreeNameError.whitespace);
      }
    }

    // 2. Caracteres proibidos + control chars (< 0x20) e DEL (0x7f).
    for (final unit in name.codeUnits) {
      if (unit < 0x20 || unit == 0x7f) {
        return const WorktreeNameCheck.invalid(WorktreeNameError.invalidChar);
      }
    }
    for (final ch in _forbiddenChars) {
      if (name.contains(ch)) {
        return const WorktreeNameCheck.invalid(WorktreeNameError.invalidChar);
      }
    }

    // 3. Sequências/posições inválidas.
    if (name == '@' ||
        name.contains('..') ||
        name.contains('@{') ||
        name.contains('//') ||
        name.startsWith('/') ||
        name.endsWith('/')) {
      return const WorktreeNameCheck.invalid(WorktreeNameError.invalidSequence);
    }

    // 4. Reservas de posição (global + por componente).
    if (name.startsWith('-') || name.endsWith('.') || name.endsWith('.lock')) {
      return const WorktreeNameCheck.invalid(WorktreeNameError.reserved);
    }
    for (final part in name.split('/')) {
      if (part.startsWith('.') || part.endsWith('.lock')) {
        return const WorktreeNameCheck.invalid(WorktreeNameError.reserved);
      }
    }

    // 5. Unicidade (decisão 11): branches locais + worktrees existentes.
    if (existingBranches.contains(name)) {
      return const WorktreeNameCheck.invalid(WorktreeNameError.duplicateBranch);
    }
    if (existingWorktreeNames.contains(name)) {
      return const WorktreeNameCheck.invalid(
        WorktreeNameError.duplicateWorktree,
      );
    }

    // 6. Conflito hierárquico (D/F conflict):
    for (final branch in existingBranches) {
      if (branch.startsWith('$name/')) {
        return const WorktreeNameCheck.invalid(
          WorktreeNameError.branchHierarchicalConflict,
        );
      }
      if (name.startsWith('$branch/')) {
        return const WorktreeNameCheck.invalid(
          WorktreeNameError.branchHierarchicalConflict,
        );
      }
    }

    return const WorktreeNameCheck.valid();
  }
}
