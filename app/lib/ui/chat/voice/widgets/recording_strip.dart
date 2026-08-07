import 'dart:collection';

import 'package:app/i18n/strings.g.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Plan 29 — the WhatsApp-style strip that replaces the input bar while
/// recording (decision #11): a pulsing red dot + running `MM:SS` timer +
/// amplitude waveform + a "‹ slide to cancel" hint.
///
/// Purely presentational. The hold + slide-to-cancel gesture is owned by the
/// [InputBar] (it must outlive the Row→strip swap to keep tracking the same
/// pointer), so this widget only renders the [level]/[elapsed]/[cancelArmed]
/// it's handed and never fires callbacks.
class RecordingStrip extends StatefulWidget {
  const RecordingStrip({
    super.key,
    required this.level,
    required this.elapsed,
    required this.maxDuration,
    this.cancelArmed = false,
  });

  /// `0..1` amplitude envelope (volume, not a spectrum).
  final double level;
  final Duration elapsed;
  final Duration maxDuration;

  /// True once the drag passed the cancel threshold — flips the hint to a
  /// "release to cancel" warning.
  final bool cancelArmed;

  /// Show a countdown emphasis once this close to the cap.
  static const Duration warnBefore = Duration(seconds: 10);

  /// Number of bars kept in the rolling waveform.
  static const int barCount = 28;

  @override
  State<RecordingStrip> createState() => _RecordingStripState();
}

class _RecordingStripState extends State<RecordingStrip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  /// Rolling buffer of recent amplitude samples (oldest → newest), one pushed
  /// per [level] change. Renders the scrolling waveform.
  final Queue<double> _samples = Queue<double>();

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pushSample(widget.level);
  }

  @override
  void didUpdateWidget(RecordingStrip old) {
    super.didUpdateWidget(old);
    if (old.level != widget.level) _pushSample(widget.level);
  }

  void _pushSample(double level) {
    _samples.addLast(level.clamp(0.0, 1.0));
    while (_samples.length > RecordingStrip.barCount) {
      _samples.removeFirst();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  bool get _isWarning =>
      widget.maxDuration - widget.elapsed <= RecordingStrip.warnBefore;

  String get _timer {
    final s = widget.elapsed.inSeconds;
    final mm = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final warn = _isWarning;
    final cancel = widget.cancelArmed;
    final timerColor = cancel
        ? colors.muted
        : warn
        ? colors.warning
        : colors.text;

    return Row(
      key: const Key('recording-strip'),
      children: [
        // Pulsing red dot.
        FadeTransition(
          opacity: Tween<double>(begin: 1, end: 0.25).animate(_pulse),
          child: Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.error,
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Running timer.
        Text(
          _timer,
          key: const Key('recording-strip-timer'),
          style: TextStyle(
            fontFamily: kMonoFamily,
            fontSize: 13,
            color: timerColor,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 12),
        // Waveform — collapses to the cancel hint once armed.
        Expanded(
          child: cancel
              ? _CancelHint()
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(child: _Waveform(samples: _samples.toList())),
                    const SizedBox(width: 10),
                    const _SlideToCancelHint(),
                  ],
                ),
        ),
      ],
    );
  }
}

class _Waveform extends StatelessWidget {
  const _Waveform({required this.samples});

  final List<double> samples;

  @override
  Widget build(BuildContext context) {
    // Right-align so the newest sample sits next to the hint and the wave
    // appears to scroll leftward as it fills. ClipRect + OverflowBox lets the
    // bar row keep its natural width on narrow composers (no overflow assert);
    // the oldest bars are clipped off the left, newest stay visible.
    final pad = RecordingStrip.barCount - samples.length;
    return SizedBox(
      height: 26,
      child: ClipRect(
        child: OverflowBox(
          maxWidth: double.infinity,
          alignment: Alignment.centerRight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var i = 0; i < pad; i++) const _Bar(level: 0),
              for (final s in samples) _Bar(level: s),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.level});

  final double level;

  @override
  Widget build(BuildContext context) {
    // Min nub so silence still reads as a flat line, not empty space.
    final height = 3.0 + (level.clamp(0.0, 1.0) * 21.0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1.5),
      child: Container(
        width: 3,
        height: height,
        decoration: BoxDecoration(
          color: context.colors.accent.withValues(
            alpha: 0.35 + level.clamp(0.0, 1.0) * 0.6,
          ),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _SlideToCancelHint extends StatelessWidget {
  const _SlideToCancelHint();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(LucideIcons.chevronLeft, size: 14, color: colors.muted),
        const SizedBox(width: 2),
        Text(
          t.chat.slideToCancel,
          style: TextStyle(
            fontFamily: kMonoFamily,
            fontSize: 11,
            color: colors.muted,
          ),
        ),
      ],
    );
  }
}

class _CancelHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(LucideIcons.trash2, size: 14, color: colors.error),
        const SizedBox(width: 6),
        Text(
          t.chat.releaseToCancel,
          style: TextStyle(
            fontFamily: kMonoFamily,
            fontSize: 12,
            color: colors.error,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
