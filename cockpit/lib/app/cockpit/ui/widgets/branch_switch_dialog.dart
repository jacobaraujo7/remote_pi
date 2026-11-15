import 'package:cockpit/app/cockpit/domain/contracts/worktree_manager.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Escolha feita no dialog de troca de branch.
///
/// [name] é o nome **local** da branch (o que vai pro `git checkout`). [remote]
/// só é preenchido quando a branch existe apenas no remoto: aí o checkout cria
/// a local acompanhando o ref (`checkout -b <name> --track <remote>`).
class BranchSwitchSelection {
  const BranchSwitchSelection({required this.name, this.remote});

  final String name;
  final String? remote;
}

/// Dialog de troca de branch de um workspace raiz local.
///
/// Lista as branches locais e as remotas que ainda não têm local homônima, com
/// busca e a branch atual marcada. Devolve `null` se o usuário cancelar.
Future<BranchSwitchSelection?> showBranchSwitchDialog(
  BuildContext context, {
  required String rootName,
  required String? currentBranch,
  required WorktreeNamespace namespace,
}) {
  return showDialog<BranchSwitchSelection>(
    context: context,
    barrierColor: context.colors.scrim,
    builder: (context) => _BranchSwitchDialog(
      rootName: rootName,
      currentBranch: currentBranch,
      namespace: namespace,
    ),
  );
}

class _BranchSwitchDialog extends StatefulWidget {
  const _BranchSwitchDialog({
    required this.rootName,
    required this.currentBranch,
    required this.namespace,
  });

  final String rootName;
  final String? currentBranch;
  final WorktreeNamespace namespace;

  @override
  State<_BranchSwitchDialog> createState() => _BranchSwitchDialogState();
}

class _BranchSwitchDialogState extends State<_BranchSwitchDialog> {
  String _query = '';
  BranchSwitchSelection? _selected;

  /// Branches remotas que ainda não existem localmente, já com o nome curto
  /// (`origin/foo` → `foo`). Ignora `origin/HEAD` e refs sem `/`.
  List<BranchSwitchSelection> get _remoteOnly {
    final locals = widget.namespace.branches;
    final seen = <String>{};
    final out = <BranchSwitchSelection>[];
    for (final ref in widget.namespace.remoteBranches) {
      final slash = ref.indexOf('/');
      if (slash <= 0 || slash == ref.length - 1) continue;
      final short = ref.substring(slash + 1);
      if (short == 'HEAD' || locals.contains(short) || !seen.add(short)) {
        continue;
      }
      out.add(BranchSwitchSelection(name: short, remote: ref));
    }
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  bool _matches(String name) {
    final q = _query.toLowerCase().trim();
    return q.isEmpty || name.toLowerCase().contains(q);
  }

  void _pick(BranchSwitchSelection selection) {
    setState(() => _selected = selection);
  }

  void _submit() {
    final selected = _selected;
    if (selected == null) return;
    Navigator.of(context).pop(selected);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    final tr = context.t.cockpit.branchSwitchDialog;

    final locals = widget.namespace.branches.where(_matches).toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final remotes = _remoteOnly.where((b) => _matches(b.name)).toList();
    final empty = locals.isEmpty && remotes.isEmpty;

    return AlertDialog(
      title: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr.title(label: widget.rootName),
            style: typo.title.copyWith(fontSize: 15, color: colors.text),
          ),
          const SizedBox(height: 4),
          Text(
            tr.subtitle(current: widget.currentBranch ?? 'HEAD'),
            style: typo.label.copyWith(color: colors.text3),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              autofocus: true,
              style: typo.body.copyWith(color: colors.text, fontSize: 13),
              placeholder: Text(tr.search),
              onChanged: (v) => setState(() => _query = v),
              borderRadius: BorderRadius.circular(6),
              features: const [
                InputFeature.leading(Icon(Icons.search, size: 14)),
              ],
            ),
            const SizedBox(height: 10),
            Flexible(
              child: empty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: Text(
                        tr.empty,
                        textAlign: TextAlign.center,
                        style: typo.label.copyWith(color: colors.text3),
                      ),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        if (locals.isNotEmpty) ...[
                          _SectionLabel(label: tr.local),
                          for (final branch in locals)
                            _BranchRow(
                              label: branch,
                              icon: Icons.call_split,
                              current: branch == widget.currentBranch,
                              selected:
                                  _selected?.remote == null &&
                                  _selected?.name == branch,
                              onTap: branch == widget.currentBranch
                                  ? null
                                  : () => _pick(
                                      BranchSwitchSelection(name: branch),
                                    ),
                            ),
                        ],
                        if (remotes.isNotEmpty) ...[
                          if (locals.isNotEmpty) const SizedBox(height: 8),
                          _SectionLabel(label: tr.remote),
                          for (final branch in remotes)
                            _BranchRow(
                              label: branch.name,
                              icon: Icons.cloud_outlined,
                              current: false,
                              selected: _selected?.remote == branch.remote,
                              onTap: () => _pick(branch),
                            ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [
        OutlineButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.t.common.cancel),
        ),
        PrimaryButton(
          onPressed: _selected == null ? null : _submit,
          child: Text(tr.switchAction),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 6),
      child: Text(
        label.toUpperCase(),
        style: context.typo.label.copyWith(
          fontSize: 10,
          letterSpacing: 0.6,
          color: context.colors.text4,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _BranchRow extends StatelessWidget {
  const _BranchRow({
    required this.label,
    required this.icon,
    required this.current,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool current;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    final tr = context.t.cockpit.branchSwitchDialog;
    return HoverTap(
      onTap: onTap,
      color: selected ? colors.panel2 : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          Icon(
            icon,
            size: 14,
            color: current ? colors.accentText : colors.text3,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: typo.mono.copyWith(
                fontSize: 12,
                color: current ? colors.accentText : colors.text,
                fontWeight: selected || current
                    ? FontWeight.w600
                    : FontWeight.w400,
              ),
            ),
          ),
          if (current) ...[
            const SizedBox(width: 6),
            Text(
              tr.current,
              style: typo.label.copyWith(
                fontSize: 10,
                color: colors.accentText,
              ),
            ),
          ] else if (selected)
            Icon(Icons.check, size: 14, color: colors.accent),
        ],
      ),
    );
  }
}
