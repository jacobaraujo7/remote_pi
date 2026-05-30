import 'package:app/domain/session_state.dart';
import 'package:app/ui/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

// ---------------------------------------------------------------------------
// UserBubble — right-aligned dark card
// ---------------------------------------------------------------------------

class UserBubble extends StatelessWidget {
  final UserMsg message;
  const UserBubble(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    // Plan/24-fix-app-source-of-truth: render the lifecycle stage of
    // the bubble. `pending` (sent over WS, Pi hasn't echoed yet) gets
    // reduced opacity + a small spinner; `failed` (no echo in 15s) gets
    // a red exclamation badge so the user knows to retry.
    final isPending = message.status == UserMsgStatus.pending;
    final isFailed = message.status == UserMsgStatus.failed;
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Opacity(
              opacity: isPending ? 0.6 : 1.0,
              child: Container(
                decoration: BoxDecoration(
                  color: kUserBubble,
                  borderRadius: BorderRadius.circular(12),
                  border: isFailed
                      ? Border.all(color: Colors.redAccent, width: 1)
                      : null,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 10,
                ),
                child: Text(
                  message.text,
                  style: kSansBody.copyWith(color: kText),
                ),
              ),
            ),
            if (isPending || isFailed)
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isPending) ...[
                      const SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(
                          color: kMuted,
                          strokeWidth: 1.2,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'sending…',
                        style: kSansBody.copyWith(
                          color: kMuted,
                          fontSize: 11,
                        ),
                      ),
                    ] else ...[
                      const Icon(
                        LucideIcons.circleAlert,
                        size: 12,
                        color: Colors.redAccent,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'not delivered',
                        style: kSansBody.copyWith(
                          color: Colors.redAccent,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// AssistantBubble — left-aligned monospace text
// ---------------------------------------------------------------------------

class AssistantBubble extends StatelessWidget {
  final AssistantMsg message;
  const AssistantBubble(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: _renderText(message.text),
      ),
    );
  }

  Widget _renderText(String text) {
    // Simple highlight: file paths wrapped in backticks or containing /
    // are colored kHighlight. No full markdown in MVP.
    return Text.rich(
      _parseSpans(text),
      style: kMonoStyle,
    );
  }

  TextSpan _parseSpans(String text) {
    // Minimal inline highlight for file paths (word containing /)
    final spans = <InlineSpan>[];
    final words = text.split(' ');
    for (var i = 0; i < words.length; i++) {
      final w = words[i];
      final isPath = w.contains('/') || w.contains('.ts') || w.contains('.dart');
      spans.add(
        TextSpan(
          text: i < words.length - 1 ? '$w ' : w,
          style: isPath ? kMonoStyle.copyWith(color: kHighlight) : null,
        ),
      );
    }
    return TextSpan(children: spans);
  }
}
