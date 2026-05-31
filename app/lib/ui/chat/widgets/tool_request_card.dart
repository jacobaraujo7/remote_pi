import 'package:app/domain/session_state.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/ui/app_theme.dart';
import 'package:flutter/material.dart';

// Inline tool execution card that appears in the chat flow.
//
// Historically this widget rendered Allow/Deny buttons + a 60s countdown
// assuming the Pi paused execution until the user decided. With the current
// Claude SDK integration the pi-extension emits `tool_request` AFTER the
// SDK has already accepted the tool (`tool_execution_start` fires post
// auto-approval), so the buttons could only blink for a few hundred
// milliseconds before `tool_result` arrived — confusing UX with no real
// gating. The card is now purely informational.
//
// `onDecide` is kept on the API for forward compat — when the Pi adds a
// real approval pause we can re-enable the controls. Today it is unused.

class ToolRequestCard extends StatelessWidget {
  final ToolEvent tool;
  final void Function(String toolCallId, ApproveDecision decision)? onDecide;

  const ToolRequestCard({super.key, required this.tool, this.onDecide});

  @override
  Widget build(BuildContext context) {
    final isRunning =
        tool.status == ToolEventStatus.pending ||
        tool.status == ToolEventStatus.allowed;
    final opacity = isRunning ? 1.0 : 0.65;

    return Opacity(
      opacity: opacity,
      child: Container(
        decoration: BoxDecoration(
          color: kSurface,
          border: Border.all(color: kAccent, width: 1),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: kAccent.withValues(alpha: 0.13),
              blurRadius: 20,
              spreadRadius: 1,
            ),
          ],
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(context),
            const SizedBox(height: 10),
            _buildCodeBlock(context),
            const SizedBox(height: 8),
            _buildOutcome(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final statusLabel = switch (tool.status) {
      ToolEventStatus.pending => 'RUNNING',
      ToolEventStatus.allowed => 'RUNNING',
      ToolEventStatus.denied => 'DENIED',
      ToolEventStatus.expired => 'EXPIRED',
      ToolEventStatus.completed => 'DONE',
    };

    return Row(
      children: [
        CustomPaint(
          size: const Size(14, 14),
          painter: _TerminalIconPainter(color: kAccent),
        ),
        const SizedBox(width: 8),
        Text(
          tool.tool.toUpperCase(),
          style: (Theme.of(context).textTheme.bodySmall ?? const TextStyle())
              .copyWith(fontSize: 11.5, color: kAccent, letterSpacing: 0.6),
        ),
        const Spacer(),
        Text(
          statusLabel,
          style: (Theme.of(context).textTheme.bodySmall ?? const TextStyle())
              .copyWith(fontSize: 10, color: kMuted, letterSpacing: 0.4),
        ),
      ],
    );
  }

  Widget _buildCodeBlock(BuildContext context) {
    final commandText = _formatArgs(tool.tool, tool.args);
    return Container(
      decoration: BoxDecoration(
        color: kCodeBg,
        border: Border.all(color: kBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            r'$ ',
            style: (Theme.of(context).textTheme.bodySmall ?? kMonoStyle)
                .copyWith(color: kMuted, fontSize: 12.5),
          ),
          Expanded(
            child: Text(
              commandText,
              style: (Theme.of(context).textTheme.bodySmall ?? kMonoStyle)
                  .copyWith(color: const Color(0xFFE6E6E6), fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOutcome(BuildContext context) {
    final text = switch (tool.status) {
      ToolEventStatus.pending || ToolEventStatus.allowed => '⏳ Running…',
      ToolEventStatus.completed => '✓ Done',
      ToolEventStatus.denied => '✗ ${tool.error ?? "Denied"}',
      ToolEventStatus.expired => '✗ Expired',
    };
    final color = switch (tool.status) {
      ToolEventStatus.denied || ToolEventStatus.expired => kMuted,
      _ => kSuccess,
    };
    return Text(
      text,
      style: (Theme.of(context).textTheme.bodySmall ?? const TextStyle())
          .copyWith(fontSize: 12, color: color),
    );
  }

  static String _formatArgs(String tool, dynamic args) {
    if (args == null) return '';
    if (args is Map) {
      return switch (tool) {
        'Bash' => (args['command'] as String?) ?? '',
        'Edit' || 'Write' => (args['file_path'] as String?) ?? '',
        _ => args.entries.map((e) => '${e.key}=${e.value}').join(' '),
      };
    }
    return args.toString();
  }
}

// Minimal terminal icon (rectangle + > and —)
class _TerminalIconPainter extends CustomPainter {
  final Color color;
  const _TerminalIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0.5, 1, size.width - 1, size.height - 2),
        const Radius.circular(1.6),
      ),
      paint,
    );
    final path = Path()
      ..moveTo(3, 4.5)
      ..lineTo(5.5, 7)
      ..lineTo(3, 9.5);
    canvas.drawPath(path, paint);
    canvas.drawLine(
      Offset(6.5, size.height / 2),
      Offset(size.width - 2, size.height / 2),
      paint,
    );
  }

  @override
  bool shouldRepaint(_TerminalIconPainter old) => old.color != color;
}
