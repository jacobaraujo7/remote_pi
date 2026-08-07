import 'package:app/i18n/strings.g.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Bottom sheet to edit (or clear) a peer's local nickname.
///
/// Returns:
///  - a non-empty `String` when the user tapped **Save** with a value
///  - `''` (empty) when the user tapped **Remove nickname**
///  - `null` when the sheet was dismissed / canceled
Future<String?> showNicknameEditor(
  BuildContext context, {
  required String defaultName,
  String currentNickname = '',
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.colors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(ctx).viewInsets.bottom,
      ),
      child: _NicknameEditorSheet(
        currentNickname: currentNickname,
        defaultName: defaultName,
      ),
    ),
  );
}

class _NicknameEditorSheet extends StatefulWidget {
  final String currentNickname;
  final String defaultName;
  const _NicknameEditorSheet({
    required this.currentNickname,
    required this.defaultName,
  });

  @override
  State<_NicknameEditorSheet> createState() => _NicknameEditorSheetState();
}

class _NicknameEditorSheetState extends State<_NicknameEditorSheet> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.currentNickname);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _save() {
    final value = _ctrl.text.trim();
    Navigator.of(context).pop(value);
  }

  void _remove() {
    Navigator.of(context).pop('');
  }

  void _cancel() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasCurrent = widget.currentNickname.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: colors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Text(
            t.chat.nickname,
            style: TextStyle(
              color: colors.text,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            t.chat.nicknameLocalOnly,
            style: TextStyle(color: colors.muted, fontSize: 12),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            autofocus: true,
            maxLength: 40,
            style: TextStyle(color: colors.text, fontSize: 15),
            cursorColor: colors.accent,
            decoration: InputDecoration(
              labelText: t.chat.nickname,
              labelStyle: TextStyle(color: colors.muted),
              helperText: '${t.chat.default_}: ${widget.defaultName}',
              helperStyle: TextStyle(color: colors.muted, fontSize: 11),
              counterStyle: TextStyle(color: colors.muted, fontSize: 11),
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 12),
          if (hasCurrent) ...[
            TextButton.icon(
              onPressed: _remove,
              style: TextButton.styleFrom(foregroundColor: colors.error),
              icon: const Icon(LucideIcons.trash2, size: 16),
              label: Text(t.chat.removeNickname),
            ),
            const SizedBox(height: 4),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _cancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.muted2,
                    side: BorderSide(color: colors.border),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(t.common.cancel),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.accent,
                    foregroundColor: colors.onAccent,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(
                    t.common.save,
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
