import 'package:cockpit/app/cockpit/domain/entities/realm.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart';
import 'package:cockpit/app/cockpit/ui/widgets/confirm_dialog.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

const Color _barrier = Color(0x99000000);

/// Dialog de nome de realm (criar/renomear). Valida ao vivo: não-vazio e único
/// entre [takenNames] (case-insensitive; o nome atual em rename fica de fora).
/// Devolve o nome confirmado (trim) ou `null` se cancelar.
Future<String?> showRealmNameDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  required Set<String> takenNames,
  String? initial,
}) {
  return showDialog<String>(
    context: context,
    barrierColor: _barrier,
    builder: (context) => _RealmNameDialog(
      title: title,
      confirmLabel: confirmLabel,
      takenNames: takenNames.map((n) => n.toLowerCase()).toSet(),
      initial: initial,
    ),
  );
}

class _RealmNameDialog extends StatefulWidget {
  const _RealmNameDialog({
    required this.title,
    required this.confirmLabel,
    required this.takenNames,
    this.initial,
  });

  final String title;
  final String confirmLabel;
  final Set<String> takenNames;
  final String? initial;

  @override
  State<_RealmNameDialog> createState() => _RealmNameDialogState();
}

class _RealmNameDialogState extends State<_RealmNameDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initial ?? '',
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String get _trimmed => _name.text.trim();

  bool get _valid =>
      _trimmed.isNotEmpty &&
      !widget.takenNames.contains(_trimmed.toLowerCase());

  void _submit() {
    if (_valid) Navigator.of(context).pop(_trimmed);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AlertDialog(
      title: Text(
        widget.title,
        style: context.typo.title.copyWith(fontSize: 15, color: colors.text),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              placeholder: const Text('Realm name'),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
            ),
            if (_trimmed.isNotEmpty && !_valid) ...[
              const SizedBox(height: 8),
              Text(
                'A realm with this name already exists.',
                style: context.typo.label.copyWith(color: colors.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        OutlineButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        PrimaryButton(
          onPressed: _valid ? _submit : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// Dialog "Manage realms": lista com renomear/excluir + criar. Recebe o
/// [CockpitViewModel] por construtor (dialogs vivem no overlay do navigator,
/// fora do escopo de providers da rota — padrão do pairing dialog) e escuta
/// via [ListenableBuilder] pra refletir mutações ao vivo.
Future<void> showRealmManagerDialog(
  BuildContext context, {
  required CockpitViewModel vm,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: _barrier,
    builder: (context) => _RealmManagerDialog(vm: vm),
  );
}

class _RealmManagerDialog extends StatelessWidget {
  const _RealmManagerDialog({required this.vm});

  final CockpitViewModel vm;

  Future<void> _create(BuildContext context) async {
    final name = await showRealmNameDialog(
      context,
      title: 'New realm',
      confirmLabel: 'Create',
      takenNames: vm.realms.map((r) => r.name).toSet(),
    );
    if (name == null) return;
    await vm.createRealm(name);
  }

  Future<void> _rename(BuildContext context, Realm realm) async {
    final name = await showRealmNameDialog(
      context,
      title: 'Rename realm',
      confirmLabel: 'Rename',
      initial: realm.name,
      takenNames: vm.realms
          .where((r) => r.id != realm.id)
          .map((r) => r.name)
          .toSet(),
    );
    if (name == null || name == realm.name) return;
    await vm.renameRealm(realm.id, name);
  }

  Future<void> _delete(BuildContext context, Realm realm) async {
    final count = vm.workspaceCountInRealm(realm.id);
    final suffix = count == 0
        ? ''
        : count == 1
        ? ' Its workspace will move to Default.'
        : ' Its $count workspaces will move to Default.';
    final ok = await showConfirmDialog(
      context,
      title: 'Delete realm',
      message:
          'Delete "${realm.name}"? No workspace is deleted — the folder list '
          'just changes.$suffix',
      confirmLabel: 'Delete',
      danger: true,
    );
    if (!ok) return;
    await vm.deleteRealm(realm.id);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AlertDialog(
      title: Text(
        'Manage realms',
        style: context.typo.title.copyWith(fontSize: 15, color: colors.text),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 380),
        child: ListenableBuilder(
          listenable: vm,
          builder: (context, _) {
            final realms = vm.realms;
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final realm in realms)
                    _RealmRow(
                      realm: realm,
                      active: realm.id == vm.activeRealmId,
                      count: vm.workspaceCountInRealm(realm.id),
                      onRename: () => _rename(context, realm),
                      onDelete: realm.isDefault
                          ? null
                          : () => _delete(context, realm),
                    ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        OutlineButton(
          onPressed: () => _create(context),
          child: const Text('New realm'),
        ),
        PrimaryButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _RealmRow extends StatelessWidget {
  const _RealmRow({
    required this.realm,
    required this.active,
    required this.count,
    required this.onRename,
    required this.onDelete,
  });

  final Realm realm;
  final bool active;
  final int count;
  final VoidCallback onRename;

  /// `null` = indelével (Default) → botão de excluir desabilitado.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            active ? Icons.circle : Icons.circle_outlined,
            size: 8,
            color: active ? colors.online : colors.text4,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  realm.name,
                  overflow: TextOverflow.ellipsis,
                  style: context.typo.body.copyWith(
                    fontSize: 13.5,
                    color: colors.text,
                  ),
                ),
                Text(
                  count == 1 ? '1 workspace' : '$count workspaces',
                  style: context.typo.label.copyWith(color: colors.text3),
                ),
              ],
            ),
          ),
          IconButton.ghost(
            onPressed: onRename,
            icon: Icon(Icons.edit_outlined, size: 15, color: colors.text3),
          ),
          IconButton.ghost(
            onPressed: onDelete,
            icon: Icon(
              Icons.delete_outline,
              size: 15,
              color: onDelete == null ? colors.text4 : colors.error,
            ),
          ),
        ],
      ),
    );
  }
}
