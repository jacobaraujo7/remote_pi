import 'package:cockpit/domain/contracts/worktree_manager.dart';
import 'package:cockpit/domain/validators/worktree_name_validator.dart';
import 'package:cockpit/ui/core/themes/themes.dart';
import 'package:flutter/material.dart';

/// Dialog de criar worktree. Valida o nome **ao vivo** (decisões 10, 11) contra
/// o [namespace] (branches locais + worktrees existentes); Criar só acende com
/// nome válido. Ao confirmar, trava com spinner e chama [onCreate] (que roda o
/// `git worktree add` real): se devolver uma mensagem de erro, mostra inline e
/// reabre; `null` = sucesso → fecha (decisão 21).
Future<void> showWorktreeCreateDialog(
  BuildContext context, {
  required String rootName,
  required WorktreeNamespace namespace,
  required Future<String?> Function(String name) onCreate,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _WorktreeCreateDialog(
      rootName: rootName,
      namespace: namespace,
      onCreate: onCreate,
    ),
  );
}

class _WorktreeCreateDialog extends StatefulWidget {
  const _WorktreeCreateDialog({
    required this.rootName,
    required this.namespace,
    required this.onCreate,
  });

  final String rootName;
  final WorktreeNamespace namespace;
  final Future<String?> Function(String name) onCreate;

  @override
  State<_WorktreeCreateDialog> createState() => _WorktreeCreateDialogState();
}

class _WorktreeCreateDialogState extends State<_WorktreeCreateDialog> {
  static const _validator = WorktreeNameValidator();
  final TextEditingController _name = TextEditingController();
  bool _submitting = false;
  String? _gitError; // erro do git no último submit

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  WorktreeNameCheck get _check => _validator.validate(
    _name.text,
    existingBranches: widget.namespace.branches,
    existingWorktreeNames: widget.namespace.worktreeNames,
  );

  bool get _canCreate => _name.text.isNotEmpty && _check.isValid && !_submitting;

  /// Mensagem por causa de validação (null quando válido ou campo intacto).
  String? _reason(WorktreeNameCheck check) => switch (check.error) {
    null || WorktreeNameError.empty => null,
    WorktreeNameError.whitespace => 'No spaces in the name.',
    WorktreeNameError.invalidChar =>
      'Invalid character for a branch name.',
    WorktreeNameError.invalidSequence =>
      'Invalid sequence (e.g. "..", "//", starting/ending with "/").',
    WorktreeNameError.reserved =>
      'Reserved position (do not start with "-"/"." or end with ".lock").',
    WorktreeNameError.duplicateBranch => 'A branch with that name already exists.',
    WorktreeNameError.duplicateWorktree =>
      'A worktree with that name already exists.',
  };

  Future<void> _submit() async {
    if (!_canCreate) return;
    setState(() {
      _submitting = true;
      _gitError = null;
    });
    final error = await widget.onCreate(_name.text);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _submitting = false;
      _gitError = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final check = _check;
    final reason = _gitError ?? _reason(check);
    final showError = reason != null;

    return Dialog(
      backgroundColor: colors.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: colors.border2),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Create worktree',
                style: context.typo.title.copyWith(
                  fontSize: 15,
                  color: colors.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'New feature in ${widget.rootName} — new branch from the '
                'current HEAD.',
                style: context.typo.label.copyWith(color: colors.text3),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _name,
                autofocus: true,
                enabled: !_submitting,
                onChanged: (_) => setState(() => _gitError = null),
                onSubmitted: (_) => _submit(),
                style: context.typo.mono.copyWith(
                  fontSize: 13,
                  color: colors.text,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'feat/minha-feature',
                  hintStyle: context.typo.mono.copyWith(
                    color: colors.text3,
                    fontSize: 13,
                  ),
                  filled: true,
                  fillColor: colors.panel2,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(7),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(7),
                    borderSide: BorderSide(
                      color: showError ? colors.error : colors.border,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(7),
                    borderSide: BorderSide(
                      color: showError ? colors.error : colors.accent,
                    ),
                  ),
                ),
              ),
              if (showError) ...[
                const SizedBox(height: 8),
                Text(
                  reason,
                  style: context.typo.label.copyWith(color: colors.error),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.accent,
                    ),
                    onPressed: _canCreate ? _submit : null,
                    child: _submitting
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Create'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
