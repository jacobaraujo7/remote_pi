import 'package:app/routing/adaptive.dart';
import 'package:app/ui/chat/quick_actions/widgets/dismiss_on_session_change.dart';
import 'package:app/i18n/strings.g.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

/// Plan/30 — which source the user picked from the attach sheet (#2).
enum AttachSource { camera, gallery }

/// Bottom sheet offering Camera / Gallery (decision #2, interpreted as an
/// action sheet to match the quick-actions sheet idiom). Returns the chosen
/// [AttachSource], or null if dismissed. Pure UI — the caller drives the
/// picker ViewModel with the result.
Future<AttachSource?> showAttachSheet(BuildContext context) {
  // Auto-close if the tablet's selected session changes out from under the
  // sheet (same fix as the Quick Actions sheet — the modal lives on the
  // detail-pane navigator and would otherwise orphan over a different chat).
  final selection = context.read<SessionSelection>();
  return showModalBottomSheet<AttachSource>(
    context: context,
    backgroundColor: context.colors.bg,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    isScrollControlled: true,
    showDragHandle: false,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => DismissOnSessionChange(
      selection: selection,
      child: const _AttachSheetBody(),
    ),
  );
}

class _AttachSheetBody extends StatelessWidget {
  const _AttachSheetBody();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: context.colors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            _AttachOption(
              key: const Key('attach-camera'),
              icon: LucideIcons.camera,
              label: t.chat.camera,
              onTap: () => Navigator.of(context).pop(AttachSource.camera),
            ),
            _AttachOption(
              key: const Key('attach-gallery'),
              icon: LucideIcons.image,
              label: t.chat.photoLibrary,
              onTap: () => Navigator.of(context).pop(AttachSource.gallery),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachOption extends StatelessWidget {
  const _AttachOption({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: colors.accent, size: 20),
      title: Text(
        label,
        style: TextStyle(
          fontFamily: kMonoFamily,
          fontSize: 14,
          color: colors.text,
        ),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
  }
}
