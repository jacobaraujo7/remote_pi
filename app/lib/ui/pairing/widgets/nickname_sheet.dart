import 'package:app/i18n/strings.g.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:flutter/material.dart';

/// Post-pair nickname modal (plan/27 Wave A).
///
/// Asks the user for a friendly label for the just-paired PC. The
/// caller seeds [defaultName] with `pair_ok.hostname` when present
/// (e.g. "Mac do Jacob"), or the session name as a softer fallback,
/// or `null` so the field hints with the generic placeholder "Pi".
///
/// Returns the trimmed nickname string the user wants persisted:
/// - "Save" with non-empty input → returns the input.
/// - "Save" with empty input    → behaves as Skip (returns the default).
/// - "Skip"                     → returns [defaultName] ?? "Pi".
/// - Drag-down dismiss          → returns null (caller treats as Skip too).
///
/// Caller is responsible for calling `PeerRecord.copyWith(nickname:)`
/// and writing back to storage — the mesh-publish hook on
/// [PairingStorage] picks it up automatically.
Future<String?> showNicknameSheet(
  BuildContext context, {
  required String? defaultName,
}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: context.colors.bg,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _NicknameSheet(defaultName: defaultName),
  );
}

@visibleForTesting
class NicknameSheetForTest extends StatelessWidget {
  final String? defaultName;
  const NicknameSheetForTest({super.key, this.defaultName});

  @override
  Widget build(BuildContext context) => _NicknameSheet(defaultName: defaultName);
}

class _NicknameSheet extends StatefulWidget {
  final String? defaultName;
  const _NicknameSheet({required this.defaultName});

  @override
  State<_NicknameSheet> createState() => _NicknameSheetState();
}

class _NicknameSheetState extends State<_NicknameSheet> {
  late final TextEditingController _controller;
  static const _fallback = 'Pi';

  String get _placeholder {
    final d = widget.defaultName?.trim();
    return (d == null || d.isEmpty) ? _fallback : d;
  }

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final typed = _controller.text.trim();
    Navigator.of(context).pop(typed.isEmpty ? _placeholder : typed);
  }

  void _skip() {
    Navigator.of(context).pop(_placeholder);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final viewInsets = MediaQuery.of(context).viewInsets;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: colors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                t.pairing.nameThisPC,
                style: TextStyle(
                  color: colors.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                t.pairing.nameThisPCDesc,
                style: TextStyle(color: colors.muted2, fontSize: 13),
              ),
              const SizedBox(height: 20),
              TextField(
                key: const Key('nickname-sheet-field'),
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _save(),
                style: TextStyle(color: colors.text, fontFamily: kMonoFamily),
                decoration: InputDecoration(
                  hintText: _placeholder,
                  hintStyle: TextStyle(color: colors.muted),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: colors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: colors.accent),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      key: const Key('nickname-sheet-skip'),
                      onPressed: _skip,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        t.pairing.skip,
                        style: TextStyle(color: colors.muted),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      key: const Key('nickname-sheet-save'),
                      onPressed: _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: colors.accent,
                        foregroundColor: colors.onAccent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(t.common.save),
                    ),
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
