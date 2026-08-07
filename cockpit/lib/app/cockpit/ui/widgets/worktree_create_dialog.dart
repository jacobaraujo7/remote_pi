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
    String? baseRef,
    bool copyIgnored,
    bool copyUntracked,
    bool fetchRemote,
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
    String? baseRef,
    bool copyIgnored,
    bool copyUntracked,
    bool fetchRemote,
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
  bool _fetchRemote = true;
  String? _selectedBaseBranch;

  @override
  void initState() {
    super.initState();
    _selectedBaseBranch = widget.fork
        ? widget.rootName
        : (widget.namespace.defaultBranch ??
              (widget.namespace.branches.isNotEmpty
                  ? widget.namespace.branches.first
                  : 'HEAD'));
  }

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
      WorktreeNameError.branchHierarchicalConflict =>
        tr.errorBranchHierarchicalConflictGeneral,
    };
  }

  String _explainGitError(BuildContext context, String rawError) {
    final tr = context.t.cockpit.worktreeCreateDialog;
    // 1. Detect fatal: 'refs/heads/existing' exists; cannot create 'refs/heads/target'
    final dfRegExp = RegExp(
      r"fatal:\s+'refs/heads/([^']+)'\s+exists;\s+cannot\s+create\s+'refs/heads/([^']+)'",
      caseSensitive: false,
    );
    final match = dfRegExp.firstMatch(rawError);
    if (match != null) {
      final existing = match.group(1);
      final target = match.group(2);
      return tr.errorBranchHierarchyConflict(
        existing: existing ?? '',
        target: target ?? '',
      );
    }

    // 2. Detect fatal: cannot lock ref 'refs/heads/target': 'refs/heads/existing' exists; cannot create 'refs/heads/target'
    final dfRegExp2 = RegExp(
      r"cannot\s+lock\s+ref\s+'refs/heads/([^']+)':\s+'refs/heads/([^']+)'\s+exists",
      caseSensitive: false,
    );
    final match2 = dfRegExp2.firstMatch(rawError);
    if (match2 != null) {
      final target = match2.group(1);
      final existing = match2.group(2);
      return tr.errorBranchHierarchyConflict(
        existing: existing ?? '',
        target: target ?? '',
      );
    }

    if (rawError.contains('already exists') ||
        rawError.contains('already checked out')) {
      return tr.errorDuplicateBranch;
    }

    return rawError;
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
      baseRef: _selectedBaseBranch,
      copyIgnored: _copyIgnored,
      copyUntracked: _copyUntracked,
      fetchRemote: _fetchRemote,
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

  void _showBranchSelector(BuildContext context) {
    final allBranches = {
      ...widget.namespace.branches,
      ...widget.namespace.remoteBranches,
    }.toList();

    showPopover<void>(
      context: context,
      alignment: Alignment.topLeft,
      anchorAlignment: Alignment.bottomLeft,
      offset: const Offset(0, 4),
      builder: (popupContext) => ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 240, maxWidth: 300),
        child: _BranchSelectorPopover(
          branches: allBranches,
          current: _selectedBaseBranch,
          onSelected: (branch) {
            setState(() => _selectedBaseBranch = branch);
          },
        ),
      ),
    );
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
    final reason = _gitError != null ? _explainGitError(context, _gitError!) : _reason(check);
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
          maxHeight: showLog
              ? 450
              : (_advancedExpanded ? 460 : 340),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!showLog) ...[
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

              if (showError) ...[
                const SizedBox(height: 8),
                Text(
                  reason,
                  style: context.typo.label.copyWith(color: colors.error),
                ),
              ],

              if (widget.hasPostCheckout) ...[
                const SizedBox(height: 8),
                Text(
                  tr.postCheckoutHint,
                  style: context.typo.label.copyWith(color: colors.text3),
                ),
              ],
            ],

            if (!_submitting && !showLog) ...[
              const SizedBox(height: 24.0),
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
                      if (!widget.fork) ...[
                        Divider(height: 1, thickness: 1, color: colors.border),
                        _optionRow(
                          title: tr.baseBranch,
                          description: tr.baseBranchDesc,
                          trailing: Builder(
                            builder: (chipContext) => HoverTap(
                              color: colors.panel3,
                              borderRadius: BorderRadius.circular(7),
                              onTap: () => _showBranchSelector(chipContext),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 11,
                                vertical: 8,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _selectedBaseBranch?.startsWith(
                                              'origin/',
                                            ) ==
                                            true
                                        ? Icons.cloud_outlined
                                        : Icons.call_split,
                                    size: 14,
                                    color: colors.text2,
                                  ),
                                  const SizedBox(width: 7),
                                  Text(
                                    _selectedBaseBranch ?? 'HEAD',
                                    style: context.typo.body.copyWith(
                                      fontSize: 13,
                                      color: colors.text,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Icon(
                                    Icons.keyboard_arrow_down,
                                    size: 16,
                                    color: colors.text3,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Divider(height: 1, thickness: 1, color: colors.border),
                        _optionRow(
                          title: tr.fetchRemote,
                          description: tr.fetchRemoteDesc,
                          trailing: Switch(
                            value: _fetchRemote,
                            onChanged: (val) =>
                                setState(() => _fetchRemote = val),
                          ),
                        ),
                      ],
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
          onPressed: showLog && !_submitting
              ? () => setState(() => _logLines.clear())
              : (_canCreate ? _submit : null),
          child: _submitting
              ? const CircularProgressIndicator(size: 16, color: Colors.white)
              : Text(
                  showLog && !_submitting
                      ? tr.back
                      : (widget.fork ? tr.fork : context.t.common.create),
                ),
        ),
      ],
    );
  }
}

class _BranchSelectorPopover extends StatefulWidget {
  const _BranchSelectorPopover({
    required this.branches,
    required this.current,
    required this.onSelected,
  });

  final List<String> branches;
  final String? current;
  final ValueChanged<String> onSelected;

  @override
  State<_BranchSelectorPopover> createState() => _BranchSelectorPopoverState();
}

class _BranchSelectorPopoverState extends State<_BranchSelectorPopover> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    final tr = context.t.cockpit.worktreeCreateDialog;

    final q = _query.toLowerCase().trim();
    final filtered = widget.branches
        .where((b) => q.isEmpty || b.toLowerCase().contains(q))
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: colors.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              autofocus: true,
              style: typo.body.copyWith(color: colors.text, fontSize: 13),
              placeholder: Text(tr.searchBranch),
              onChanged: (v) => setState(() => _query = v),
              borderRadius: BorderRadius.circular(6),
              features: const [
                InputFeature.leading(Icon(Icons.search, size: 14)),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: colors.border),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: filtered.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 16,
                      horizontal: 12,
                    ),
                    child: Text(
                      'No branches found',
                      style: typo.label.copyWith(color: colors.text3),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final branch = filtered[index];
                      final isSelected = branch == widget.current;
                      final isRemote = branch.startsWith('origin/');
                      return HoverTap(
                        onTap: () {
                          widget.onSelected(branch);
                          closeOverlay(context);
                        },
                        borderRadius: BorderRadius.circular(4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isRemote
                                  ? Icons.cloud_outlined
                                  : Icons.call_split,
                              size: 14,
                              color: isRemote
                                  ? colors.text3
                                  : colors.accentText,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                branch,
                                overflow: TextOverflow.ellipsis,
                                style: typo.mono.copyWith(
                                  fontSize: 12,
                                  color: isSelected
                                      ? colors.accentText
                                      : colors.text,
                                ),
                              ),
                            ),
                            if (isSelected)
                              Icon(Icons.check, size: 14, color: colors.accent),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
