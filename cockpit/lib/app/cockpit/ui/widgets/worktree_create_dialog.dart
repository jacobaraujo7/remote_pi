import 'dart:async';

import 'package:cockpit/app/cockpit/domain/contracts/worktree_manager.dart';
import 'package:cockpit/app/cockpit/domain/entities/project.dart';
import 'package:cockpit/app/cockpit/domain/validators/worktree_name_validator.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Dialog de criar worktree. Valida o nome **ao vivo** (decisões 10, 11) contra
/// o [namespace] (branches locais + worktrees existentes); Criar só acende com
/// nome válido. Ao confirmar, mostra o stream do `git worktree add` (incluindo
/// post-checkout, se houver): sucesso → fecha; falha → mantém logs + erro
/// (decisão 21).
Future<void> showWorktreeCreateDialog(
  BuildContext context, {
  required String rootName,
  required WorktreeNamespace namespace,
  required WorktreeAddRun<Project> Function(
    String name, {
    bool copyIgnored,
    bool copyUntracked,
  })
  onCreate,
  // "Fork Worktree": mesmo dialog, copy própria — a base é a branch do fork
  // ([rootName]), não o HEAD do pai.
  bool fork = false,
  bool hasPostCheckout = false,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: const Color(0x99000000),
    builder: (context) => _WorktreeCreateDialog(
      rootName: rootName,
      namespace: namespace,
      onCreate: onCreate,
      fork: fork,
      hasPostCheckout: hasPostCheckout,
    ),
  );
}

class _WorktreeCreateDialog extends StatefulWidget {
  const _WorktreeCreateDialog({
    required this.rootName,
    required this.namespace,
    required this.onCreate,
    required this.fork,
    required this.hasPostCheckout,
  });

  final String rootName;
  final bool fork;
  final bool hasPostCheckout;
  final WorktreeNamespace namespace;
  final WorktreeAddRun<Project> Function(
    String name, {
    bool copyIgnored,
    bool copyUntracked,
  })
  onCreate;

  @override
  State<_WorktreeCreateDialog> createState() => _WorktreeCreateDialogState();
}

class _WorktreeCreateDialogState extends State<_WorktreeCreateDialog> {
  static const _validator = WorktreeNameValidator();
  final TextEditingController _name = TextEditingController();
  final ScrollController _logScroll = ScrollController();
  final List<String> _logLines = [];
  StreamSubscription<String>? _logSub;
  bool _submitting = false;
  String? _gitError; // erro do git no último submit
  bool _advancedExpanded = false;
  bool _copyIgnored = false;
  bool _copyUntracked = false;

  @override
  void dispose() {
    _logSub?.cancel();
    _name.dispose();
    _logScroll.dispose();
    super.dispose();
  }

  WorktreeNameCheck get _check => _validator.validate(
    _name.text,
    existingBranches: widget.namespace.branches,
    existingWorktreeNames: widget.namespace.worktreeNames,
  );

  bool get _canCreate =>
      _name.text.isNotEmpty && _check.isValid && !_submitting;

  /// Mensagem por causa de validação (null quando válido ou campo intacto).
  String? _reason(WorktreeNameCheck check) {
    final tr = context.t.cockpit.worktreeCreateDialog;
    return switch (check.error) {
      null || WorktreeNameError.empty => null,
      WorktreeNameError.whitespace => tr.errorWhitespace,
      WorktreeNameError.invalidChar => tr.errorInvalidChar,
      WorktreeNameError.invalidSequence => tr.errorInvalidSequence,
      WorktreeNameError.reserved => tr.errorReserved,
      WorktreeNameError.duplicateBranch => tr.errorDuplicateBranch,
      WorktreeNameError.duplicateWorktree => tr.errorDuplicateWorktree,
    };
  }

  void _autoScrollLog() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_logScroll.hasClients) return;
      _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
    });
  }

  Future<void> _submit() async {
    if (!_canCreate) return;
    await _logSub?.cancel();
    setState(() {
      _submitting = true;
      _gitError = null;
      _logLines.clear();
    });
    final run = widget.onCreate(
      _name.text,
      copyIgnored: _copyIgnored,
      copyUntracked: _copyUntracked,
    );
    _logSub = run.output.listen(
      (line) {
        if (!mounted) return;
        setState(() => _logLines.add(line));
        _autoScrollLog();
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() => _logLines.add('$e'));
        _autoScrollLog();
      },
    );
    final res = await run.result;
    if (!mounted) return;
    await _logSub?.cancel();
    _logSub = null;
    switch (res) {
      case Success():
        if (!mounted) return;
        Navigator.of(context).pop();
      case Failure(:final error):
        setState(() {
          _submitting = false;
          _gitError = error.message;
        });
    }
  }

  Widget _optionRow({
    required String title,
    required String description,
    required Widget trailing,
  }) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: context.typo.body.copyWith(
                    fontSize: 13.5,
                    color: colors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: context.typo.label.copyWith(
                    fontSize: 11,
                    color: colors.text4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final check = _check;
    final reason = _gitError ?? _reason(check);
    final showError = reason != null && !_submitting;
    final tr = context.t.cockpit.worktreeCreateDialog;
    final showLog = _submitting || _logLines.isNotEmpty;

    return AlertDialog(
      title: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.fork ? tr.forkTitle : tr.createTitle,
            style: context.typo.title.copyWith(
              fontSize: 15,
              color: colors.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.fork
                ? tr.forkSubtitle(root: widget.rootName)
                : tr.createSubtitle(root: widget.rootName),
            style: context.typo.label.copyWith(color: colors.text3),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: showLog ? 560 : 420,
          maxHeight: showLog ? 450 : 340,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              enabled: !_submitting,
              onChanged: (_) => setState(() => _gitError = null),
              onSubmitted: (_) => _submit(),
              placeholder: Text(tr.namePlaceholder),
              style: context.typo.mono.copyWith(
                fontSize: 13,
                color: colors.text,
              ),
              borderRadius: BorderRadius.circular(7),
              border: showError ? Border.all(color: colors.error) : null,
            ),

            if (!_submitting) ...[
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: colors.panel2,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.border),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HoverTap(
                      onTap: () => setState(
                        () => _advancedExpanded = !_advancedExpanded,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: Row(
                          spacing: 8.0,
                          children: [
                            Icon(
                              _advancedExpanded
                                  ? Icons.expand_more
                                  : Icons.chevron_right,
                              size: 18,
                              color: colors.text3,
                            ),
                            Text(
                              tr.advancedSettings,
                              style: context.typo.body.copyWith(
                                fontSize: 12.0,
                                color: colors.text,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_advancedExpanded) ...[
                      Divider(height: 1, thickness: 1, color: colors.border),
                      _optionRow(
                        title: tr.copyIgnored,
                        description: tr.copyIgnoredDesc,
                        trailing: Switch(
                          value: _copyIgnored,
                          onChanged: (val) =>
                              setState(() => _copyIgnored = val),
                        ),
                      ),
                      Divider(height: 1, thickness: 1, color: colors.border),
                      _optionRow(
                        title: tr.copyUntracked,
                        description: tr.copyUntrackedDesc,
                        trailing: Switch(
                          value: _copyUntracked,
                          onChanged: (val) =>
                              setState(() => _copyUntracked = val),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],

            if (widget.hasPostCheckout) ...[
              const SizedBox(height: 8),
              Text(
                tr.postCheckoutHint,
                style: context.typo.label.copyWith(color: colors.text3),
              ),
            ],
            if (showError) ...[
              const SizedBox(height: 8),
              Text(
                reason,
                style: context.typo.label.copyWith(color: colors.error),
              ),
            ],
            if (showLog) ...[
              const SizedBox(height: 12),
              if (_submitting)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(size: 14),
                      const SizedBox(width: 8),
                      Text(
                        tr.running,
                        style: context.typo.label.copyWith(
                          color: colors.text3,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              Container(
                width: double.infinity,
                height: 200,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colors.panel3,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: colors.border),
                ),
                child: SingleChildScrollView(
                  controller: _logScroll,
                  child: SelectableText(
                    _logLines.isEmpty ? ' ' : _logLines.join('\n'),
                    style: context.typo.mono.copyWith(
                      fontSize: 12,
                      color: colors.text2,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        OutlineButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: Text(context.t.common.cancel),
        ),
        PrimaryButton(
          onPressed: _canCreate ? _submit : null,
          child: _submitting
              ? const CircularProgressIndicator(size: 16, color: Colors.white)
              : Text(widget.fork ? tr.fork : context.t.common.create),
        ),
      ],
    );
  }
}
