import 'package:app/ui/app_theme.dart';
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
    backgroundColor: kSurface,
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
              color: kBorder,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Text(
            'Nickname',
            style: TextStyle(
              color: kText,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Local only — the Mac is not notified.',
            style: const TextStyle(color: kMuted, fontSize: 12),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            autofocus: true,
            maxLength: 40,
            style: const TextStyle(color: kText, fontSize: 15),
            cursorColor: kAccent,
            decoration: InputDecoration(
              labelText: 'Nickname',
              labelStyle: const TextStyle(color: kMuted),
              helperText: 'Default: ${widget.defaultName}',
              helperStyle: const TextStyle(color: kMuted, fontSize: 11),
              counterStyle: const TextStyle(color: kMuted, fontSize: 11),
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 12),
          if (hasCurrent) ...[
            TextButton.icon(
              onPressed: _remove,
              style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
              icon: const Icon(LucideIcons.trash2, size: 16),
              label: const Text('Remove nickname'),
            ),
            const SizedBox(height: 4),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _cancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kMuted2,
                    side: const BorderSide(color: kBorder),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: kAccent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text(
                    'Save',
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
