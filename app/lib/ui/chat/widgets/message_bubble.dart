import 'package:app/domain/session_state.dart';
import 'package:app/ui/app_theme.dart';
import 'package:app/ui/chat/widgets/agent_markdown.dart';
import 'package:app/ui/chat/widgets/image_bubble.dart';
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
    // Plan/30 — when an image is attached the bubble becomes an ImageBubble
    // (thumbnail + caption); otherwise the existing text card.
    final image = message.image;
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Opacity(
              opacity: isPending ? 0.6 : 1.0,
              child: image != null
                  ? ImageBubble(
                      image: image,
                      caption: message.text,
                      isFailed: isFailed,
                    )
                  : Container(
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
                        style: kSansBody.copyWith(color: kMuted, fontSize: 11),
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
    // Plan/32b — agent output is rendered as Markdown (GFM + code blocks),
    // spanning the FULL content width (the message list already pads 16px on
    // each side) — unlike the user's right-aligned chat bubble, which stays
    // capped. Selectable so prose/code can be copied.
    return SizedBox(
      width: double.infinity,
      child: AgentMarkdown(message.text, selectable: true),
    );
  }
}
