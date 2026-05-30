import 'package:app/ui/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Show a bottom sheet that lets the user paste the QR code payload as
/// text — useful when the device's camera can't read the on-screen QR
/// (low-end front cameras, scratched lenses, etc).
///
/// Submits via [onSubmit], which receives the raw `remotepi://pair?…`
/// string the user typed/pasted. The sheet closes automatically after
/// submit; if [onSubmit] throws or rejects the value, the sheet is
/// already gone — the caller surfaces the error through the same
/// pairing-error path the camera scan uses.
Future<void> showPasteQrSheet(
  BuildContext context, {
  required void Function(String raw) onSubmit,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: kBg,
    isScrollControlled: true,
    builder: (sheetCtx) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
        ),
        child: const _PasteQrSheetBody(),
      ).withOnSubmit(onSubmit);
    },
  );
}

/// Hook to wire the inner submit callback to the outer parameter. Kept
/// here so the body widget itself is `const`-able for the common case
/// of opening the sheet without nesting the closure inside the build.
extension _PasteQrSheetHook on Widget {
  Widget withOnSubmit(void Function(String raw) onSubmit) {
    return _OnSubmitScope(onSubmit: onSubmit, child: this);
  }
}

class _OnSubmitScope extends InheritedWidget {
  final void Function(String raw) onSubmit;
  const _OnSubmitScope({required this.onSubmit, required super.child});

  static void Function(String raw) of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<_OnSubmitScope>();
    assert(
      scope != null,
      '_PasteQrSheetBody must be wrapped in a _OnSubmitScope (use showPasteQrSheet).',
    );
    return scope!.onSubmit;
  }

  @override
  bool updateShouldNotify(_OnSubmitScope old) => old.onSubmit != onSubmit;
}

class _PasteQrSheetBody extends StatefulWidget {
  const _PasteQrSheetBody();

  @override
  State<_PasteQrSheetBody> createState() => _PasteQrSheetBodyState();
}

class _PasteQrSheetBodyState extends State<_PasteQrSheetBody> {
  final _controller = TextEditingController();
  bool _canSubmit = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  void _onChanged() {
    final next = _controller.text.trim().isNotEmpty;
    if (next != _canSubmit) {
      setState(() => _canSubmit = next);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    _controller.text = text.trim();
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
  }

  void _submit() {
    final raw = _controller.text.trim();
    if (raw.isEmpty) return;
    final onSubmit = _OnSubmitScope.of(context);
    Navigator.of(context).pop();
    onSubmit(raw);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: kBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              'Paste pairing code',
              style: TextStyle(
                fontFamily: kMono,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: kText,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              "Can't scan the QR? Paste the text from your Mac terminal "
              "below. It starts with remotepi://pair?…",
              style: TextStyle(
                fontFamily: kMono,
                fontSize: 11,
                color: kMuted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              minLines: 3,
              maxLines: 6,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.none,
              keyboardType: TextInputType.url,
              style: const TextStyle(
                fontFamily: kMono,
                fontSize: 12,
                color: kText,
              ),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'remotepi://pair?t=…',
                hintStyle: const TextStyle(fontFamily: kMono, color: kMuted),
                filled: true,
                fillColor: kSurface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                enabledBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: kBorder),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: kAccent),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pasteFromClipboard,
                    icon: const Icon(
                      LucideIcons.clipboardPaste,
                      size: 16,
                      color: kAccent,
                    ),
                    label: const Text(
                      'Paste from clipboard',
                      style: TextStyle(
                        fontFamily: kMono,
                        fontSize: 12,
                        color: kAccent,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: kBorder),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(Radius.circular(6)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _canSubmit ? _submit : null,
              style: FilledButton.styleFrom(
                backgroundColor: kAccent,
                foregroundColor: Colors.black,
                disabledBackgroundColor: kBorder,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(6)),
                ),
              ),
              child: const Text(
                'Pair',
                style: TextStyle(
                  fontFamily: kMono,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
