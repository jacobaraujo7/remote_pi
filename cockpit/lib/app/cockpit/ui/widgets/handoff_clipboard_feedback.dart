import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/utils/text_clipboard.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Completes a handoff that already created its destination session.
/// A non-copy outcome must never hide the session or discard its summary.
Future<void> showHandoffClipboardFeedback(
  BuildContext context, {
  required String sessionId,
  required String summary,
  required String operation,
  bool confirmCopied = true,
  TextClipboardService? clipboard,
}) async {
  final result = await (clipboard ?? TextClipboardService.instance).write(
    summary,
    operation: operation,
  );
  if (!context.mounted) return;
  final copied = result == TextClipboardResult.copied;
  // The owned-terminal menu historically continued without a success dialog.
  if (copied && !confirmCopied) return;
  await showDialog<void>(
    context: context,
    barrierColor: context.colors.scrim,
    builder: (context) {
      final tr = context.t.workspaceView;
      return AlertDialog(
        title: Text(tr.handoffSessionReady, style: context.typo.title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(copied ? tr.handoffReady : tr.handoffCopyUnavailable),
              if (!copied) ...[
                const SizedBox(height: 12),
                Text(tr.handoffSessionLabel, style: context.typo.label),
                SelectableText(sessionId),
                const SizedBox(height: 12),
                Text(tr.handoffSummary, style: context.typo.label),
                const SizedBox(height: 6),
                Flexible(
                  child: SingleChildScrollView(
                    child: SelectableText(summary, style: context.typo.body),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          PrimaryButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.t.common.gotIt),
          ),
        ],
      );
    },
  );
}
