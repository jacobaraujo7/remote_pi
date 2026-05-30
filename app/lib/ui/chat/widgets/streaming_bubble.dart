import 'package:app/domain/session_state.dart';
import 'package:app/ui/app_theme.dart';
import 'package:app/ui/chat/widgets/agent_markdown.dart';
import 'package:flutter/material.dart';

// StreamingBubble — shows the assistant's growing response + blinking cursor.
// The buffer is already batched with 16ms debounce in SessionRepository.

class StreamingBubble extends StatefulWidget {
  final StreamingMessage streaming;
  const StreamingBubble(this.streaming, {super.key});

  @override
  State<StreamingBubble> createState() => _StreamingBubbleState();
}

class _StreamingBubbleState extends State<StreamingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink;

  @override
  void initState() {
    super.initState();
    _blink = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasText = widget.streaming.buffer.isNotEmpty;
    // Full content width (matches AssistantBubble). Cursor lives on its OWN
    // line directly below the response (never inline beside wrapped text,
    // which made it float toward the middle). No text yet → just the cursor.
    return SizedBox(
      width: double.infinity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Render partial markdown live (gpt_markdown tolerates incomplete
          // syntax); not selectable while it's still changing.
          if (hasText) AgentMarkdown(widget.streaming.buffer),
          _BlinkingCursor(controller: _blink),
        ],
      ),
    );
  }
}

class _BlinkingCursor extends AnimatedWidget {
  const _BlinkingCursor({required AnimationController controller})
    : super(listenable: controller);

  @override
  Widget build(BuildContext context) {
    final controller = listenable as AnimationController;
    final visible = controller.value < 0.5;
    return Container(
      key: const Key('streaming-cursor'),
      width: 7,
      height: 14,
      margin: const EdgeInsets.only(left: 3, bottom: 1),
      color: visible ? kAccent : Colors.transparent,
    );
  }
}
