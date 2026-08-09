import 'dart:io';

import 'package:cockpit/app/cockpit/ui/widgets/workspace_avatar.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:shadcn_flutter/shadcn_flutter.dart';

// DEBUG temporário: marcadores síncronos pra localizar o segfault no Windows ARM.
void _trace(String m) {
  try {
    File(
      '${Directory.systemTemp.path}/ck_trace.log',
    ).writeAsStringSync('$m\n', mode: FileMode.append, flush: true);
  } catch (_) {}
}

/// Paleta de cores do avatar de workspace.
const List<int> kWorkspacePalette = <int>[
  0xFF6E56CF,
  0xFF2F6FF0,
  0xFF1AA5A0,
  0xFF3FB868,
  0xFFE0A33A,
  0xFFE5484D,
  0xFFD6409F,
  0xFF8E8E96,
];

/// Dialog de configurações do workspace: nome, cor e foto do avatar. Devolve
/// `(name, colorValue, imagePath)` ou `null` se cancelar. `imagePath` null no
/// retorno = sem imagem (nunca teve ou foi removida).
Future<({String name, int colorValue, String? imagePath})?>
showWorkspaceSettingsDialog(
  BuildContext context, {
  required String name,
  required int colorValue,
  required String path,
  String? imagePath,
}) {
  return showDialog<({String name, int colorValue, String? imagePath})>(
    context: context,
    barrierColor: context.colors.scrim,
    builder: (context) => _WorkspaceSettingsDialog(
      name: name,
      colorValue: colorValue,
      path: path,
      imagePath: imagePath,
    ),
  );
}

class _WorkspaceSettingsDialog extends StatefulWidget {
  const _WorkspaceSettingsDialog({
    required this.name,
    required this.colorValue,
    required this.path,
    required this.imagePath,
  });

  final String name;
  final int colorValue;
  final String path;
  final String? imagePath;

  @override
  State<_WorkspaceSettingsDialog> createState() =>
      _WorkspaceSettingsDialogState();
}

class _WorkspaceSettingsDialogState extends State<_WorkspaceSettingsDialog> {
  late final TextEditingController _name;
  final FocusNode _nameFocus = FocusNode();
  late int _color;
  late String? _imagePath;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.name);
    _color = widget.colorValue;
    _imagePath = widget.imagePath;
    _trace('dlg:initState');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _trace('dlg:postframe-before-focus');
      if (mounted) _nameFocus.requestFocus();
      _trace('dlg:postframe-after-focus');
    });
  }

  @override
  void dispose() {
    _nameFocus.dispose();
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    _trace('save:before-pop');
    Navigator.of(
      context,
    ).pop((name: name, colorValue: _color, imagePath: _imagePath));
    _trace('save:after-pop');
  }

  /// Pasta em que o seletor abre: a da imagem atual (se ainda existir) ou a
  /// raiz do workspace. `null` quando nenhuma das duas serve (ex.: workspace de
  /// sistema, que tem path vazio) — aí o SO decide.
  String? get _pickerInitialDirectory {
    final current = _imagePath;
    if (current != null && current.isNotEmpty) {
      final dir = _nativeDirIfExists(p.dirname(current));
      if (dir != null) return dir;
    }
    return _nativeDirIfExists(widget.path);
  }

  /// Normaliza para o separador nativo e confirma que a pasta existe. O diálogo
  /// nativo do Windows ignora `initialDirectory` silenciosamente se o caminho
  /// vier com `/` (nossos paths circulam com barra normal em layouts `.ckp`,
  /// CLI e estado JSON) — então `\` é obrigatório lá.
  String? _nativeDirIfExists(String dir) {
    if (dir.isEmpty) return null;
    final normalized = p.normalize(
      Platform.isWindows ? dir.replaceAll('/', r'\') : dir,
    );
    return Directory(normalized).existsSync() ? normalized : null;
  }

  /// Escolhe um PNG/JPG para o avatar do workspace. Guarda só o caminho — se o
  /// arquivo sumir depois, o `WorkspaceAvatar` mostra o placeholder de erro.
  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'svg'],
      dialogTitle: context.t.cockpit.workspaceSettingsDialog.choosePhotoTitle,
      initialDirectory: _pickerInitialDirectory,
    );
    if (!mounted || result == null) return;
    final path = result.files.single.path;
    if (path == null) return;
    setState(() => _imagePath = path);
  }

  @override
  Widget build(BuildContext context) {
    _trace('dlg:build');
    final colors = context.colors;
    final initial = _name.text.trim().isEmpty
        ? '?'
        : _name.text.trim()[0].toUpperCase();

    final tr = context.t.cockpit.workspaceSettingsDialog;
    return AlertDialog(
      title: Text(
        tr.title,
        style: context.typo.title.copyWith(fontSize: 15, color: colors.text),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                WorkspaceAvatar(
                  imagePath: _imagePath,
                  colorValue: _color,
                  initial: initial,
                  size: 40,
                  radius: 9,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: TextField(
                    controller: _name,
                    focusNode: _nameFocus,
                    onChanged: (_) => setState(() {}),
                    placeholder: Text(tr.namePlaceholder),
                    style: context.typo.body.copyWith(
                      fontSize: 14,
                      color: colors.text,
                    ),
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _PhotoButton(
                  icon: Icons.image_outlined,
                  label: _imagePath == null ? tr.addPhoto : tr.changePhoto,
                  onTap: _pickImage,
                ),
                if (_imagePath != null) ...[
                  const SizedBox(width: 8),
                  _PhotoButton(
                    icon: Icons.delete_outline,
                    label: tr.remove,
                    danger: true,
                    onTap: () => setState(() => _imagePath = null),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 18),
            Text(
              tr.color,
              style: context.typo.label.copyWith(color: colors.text2),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final swatch in kWorkspacePalette)
                  _Swatch(
                    color: swatch,
                    selected: swatch == _color,
                    onTap: () => setState(() => _color = swatch),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              tr.folder,
              style: context.typo.label.copyWith(color: colors.text2),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: colors.panel2,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: colors.border),
              ),
              child: Text(
                widget.path,
                style: context.typo.mono.copyWith(
                  fontSize: 12,
                  color: colors.text2,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        OutlineButton(
          onPressed: () {
            _trace('cancel:before-pop');
            Navigator.of(context).pop();
            _trace('cancel:after-pop');
          },
          child: Text(context.t.common.cancel),
        ),
        PrimaryButton(onPressed: _save, child: Text(context.t.common.save)),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final int color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: Color(color),
          borderRadius: BorderRadius.circular(7),
          // O anel de seleção contrasta com a SUPERFÍCIE do dialog (branco
          // sobre dialog claro era invisível); o check contrasta com o swatch.
          border: Border.all(
            color: selected ? context.colors.text : Colors.transparent,
            width: 2,
          ),
        ),
        child: selected
            ? Icon(Icons.check, size: 15, color: onColor(Color(color)))
            : null,
      ),
    );
  }
}

/// Botão compacto da seção de foto (Add/Change/Remove).
class _PhotoButton extends StatelessWidget {
  const _PhotoButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fg = danger ? colors.error : colors.text2;
    return HoverTap(
      onTap: onTap,
      color: colors.panel2,
      hoverColor: colors.panel3,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: fg),
          const SizedBox(width: 7),
          Text(label, style: context.typo.label.copyWith(color: fg)),
        ],
      ),
    );
  }
}
