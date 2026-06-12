import 'dart:io';

import 'package:cockpit/ui/core/themes/themes.dart';
import 'package:flutter/material.dart';

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

/// Dialog de configurações do workspace: nome + cor do avatar. Devolve
/// `(name, colorValue)` ou `null` se cancelar.
Future<({String name, int colorValue})?> showWorkspaceSettingsDialog(
  BuildContext context, {
  required String name,
  required int colorValue,
  required String path,
}) {
  return showDialog<({String name, int colorValue})>(
    context: context,
    builder: (context) => _WorkspaceSettingsDialog(
      name: name,
      colorValue: colorValue,
      path: path,
    ),
  );
}

class _WorkspaceSettingsDialog extends StatefulWidget {
  const _WorkspaceSettingsDialog({
    required this.name,
    required this.colorValue,
    required this.path,
  });

  final String name;
  final int colorValue;
  final String path;

  @override
  State<_WorkspaceSettingsDialog> createState() =>
      _WorkspaceSettingsDialogState();
}

class _WorkspaceSettingsDialogState extends State<_WorkspaceSettingsDialog> {
  late final TextEditingController _name;
  final FocusNode _nameFocus = FocusNode();
  late int _color;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.name);
    _color = widget.colorValue;
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
    Navigator.of(context).pop((name: name, colorValue: _color));
    _trace('save:after-pop');
  }

  @override
  Widget build(BuildContext context) {
    _trace('dlg:build');
    final colors = context.colors;
    final initial = _name.text.trim().isEmpty
        ? '?'
        : _name.text.trim()[0].toUpperCase();

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
                'Workspace settings',
                style: context.typo.title.copyWith(
                  fontSize: 15,
                  color: colors.text,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Color(_color),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      initial,
                      style: context.typo.title.copyWith(
                        fontSize: 18,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: TextField(
                      controller: _name,
                      focusNode: _nameFocus,
                      onChanged: (_) => setState(() {}),
                      style: context.typo.body.copyWith(
                        fontSize: 14,
                        color: colors.text,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Workspace name',
                        hintStyle: context.typo.body.copyWith(
                          color: colors.text3,
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
                          borderSide: BorderSide(color: colors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(7),
                          borderSide: BorderSide(color: colors.accent),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                'Color',
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
                'Folder',
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
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      _trace('cancel:before-pop');
                      Navigator.of(context).pop();
                      _trace('cancel:after-pop');
                    },
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.accent,
                    ),
                    onPressed: _save,
                    child: const Text('Save'),
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
          border: selected
              ? Border.all(color: Colors.white, width: 2)
              : Border.all(color: Colors.transparent, width: 2),
        ),
        child: selected
            ? const Icon(Icons.check, size: 15, color: Colors.white)
            : null,
      ),
    );
  }
}
