import 'package:app/ui/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

// InputBar — bottom message composer.
// - Disabled (grayed) when offline or streaming.
// - Send button turns to Cancel icon during streaming.
// - Plan/28 — quick actions (⚙) icon sits to the left of the attach
//   button and is visible only while the field is empty (so it never
//   competes with the send affordance).

class InputBar extends StatefulWidget {
  final bool disabled; // offline or no peer
  final bool streaming; // show cancel instead of send
  final void Function(String text) onSend;
  final VoidCallback? onCancel;
  final VoidCallback? onOpenQuickActions;
  final VoidCallback? onStartAudio;

  const InputBar({
    super.key,
    required this.onSend,
    this.onCancel,
    this.onOpenQuickActions,
    this.onStartAudio,
    this.disabled = false,
    this.streaming = false,
  });

  @override
  State<InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<InputBar> {
  final _controller = TextEditingController();
  bool _empty = true;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChange);
  }

  void _onTextChange() {
    final next = _controller.text.isEmpty;
    if (next == _empty) return;
    setState(() {
      _empty = next;
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChange);
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    widget.onSend(text);
  }

  @override
  Widget build(BuildContext context) {
    final canInteract = !widget.disabled;
    final hasQuickActions = widget.onOpenQuickActions != null;
    final showQuickActions = _empty && canInteract && !widget.streaming;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 22),
      decoration: const BoxDecoration(
        color: kBg,
        border: Border(top: BorderSide(color: kBorder)),
      ),
      child: Row(
        children: [
          if (hasQuickActions)
            _QuickActionsButton(
              show: showQuickActions,
              onPressed: widget.onOpenQuickActions,
            ),
          // Attachment placeholder
          const SizedBox(
            width: 32,
            height: 32,
            child: Icon(LucideIcons.paperclip, color: kMuted, size: 18),
          ),
          const SizedBox(width: 10),
          // Text field
          Expanded(
            child: TextField(
              controller: _controller,
              enabled: canInteract && !widget.streaming,
              onSubmitted: canInteract && !widget.streaming
                  ? (_) => _submit()
                  : null,
              style: const TextStyle(
                fontFamily: kMono,
                fontSize: 13,
                color: kText,
              ),
              cursorColor: kAccent,
              decoration: InputDecoration(
                hintText: widget.disabled
                    ? 'Offline…'
                    : widget.streaming
                    ? 'Waiting for response…'
                    : 'Send a message…',
                hintStyle: const TextStyle(color: kMuted, fontFamily: kMono),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                filled: true,
                fillColor: const Color(0xFF0E0E0E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(19),
                  borderSide: const BorderSide(color: kBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(19),
                  borderSide: const BorderSide(color: kBorder),
                ),
                disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(19),
                  borderSide: BorderSide(color: kBorder.withValues(alpha: 0.5)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(19),
                  borderSide: const BorderSide(color: kAccent, width: 1.2),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _ComposerActionButton(
            streaming: widget.streaming,
            hasText: !_empty,
            disabled: widget.disabled,
            onSendText: _submit,
            onCancel: widget.onCancel,
            onStartAudio: widget.onStartAudio,
          ),
        ],
      ),
    );
  }
}

class _QuickActionsButton extends StatefulWidget {
  const _QuickActionsButton({required this.show, required this.onPressed});

  final bool show;
  final VoidCallback? onPressed;

  @override
  State<_QuickActionsButton> createState() => _QuickActionsButtonState();
}

class _QuickActionsButtonState extends State<_QuickActionsButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _sizeFactor;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      value: widget.show ? 1.0 : 0.0,
    );
    // Timeline (forward = appear): first grow [0.0–0.5], then fade in [0.5–1.0].
    // On reverse (disappear) the order flips → fade out first, then shrink.
    _sizeFactor = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.5, curve: Curves.easeInOut),
    );
    _fade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.5, 1.0, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(covariant _QuickActionsButton old) {
    super.didUpdateWidget(old);
    if (widget.show == old.show) return;
    if (widget.show) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizeTransition(
      sizeFactor: _sizeFactor,
      axis: Axis.horizontal,
      axisAlignment: -1.0,
      child: FadeTransition(
        opacity: _fade,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: IconButton(
                key: const Key('input-bar-quick-actions'),
                padding: EdgeInsets.zero,
                iconSize: 18,
                splashRadius: 18,
                tooltip: 'Quick actions',
                icon: const Icon(LucideIcons.slidersHorizontal, color: kMuted),
                onPressed: widget.onPressed,
              ),
            ),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}

enum _ComposerMode { sendAudio, sendText, cancel }

class _ComposerActionButton extends StatelessWidget {
  const _ComposerActionButton({
    required this.streaming,
    required this.hasText,
    required this.disabled,
    required this.onSendText,
    required this.onCancel,
    required this.onStartAudio,
  });

  final bool streaming;
  final bool hasText;
  final bool disabled;
  final VoidCallback onSendText;
  final VoidCallback? onCancel;
  final VoidCallback? onStartAudio;

  _ComposerMode get _mode {
    if (streaming) return _ComposerMode.cancel;
    if (hasText) return _ComposerMode.sendText;
    return _ComposerMode.sendAudio;
  }

  IconData get _icon {
    switch (_mode) {
      case _ComposerMode.cancel:
        return LucideIcons.square;
      case _ComposerMode.sendText:
        return LucideIcons.send;
      case _ComposerMode.sendAudio:
        return LucideIcons.mic;
    }
  }

  VoidCallback? _resolveTap() {
    switch (_mode) {
      case _ComposerMode.cancel:
        return onCancel;
      case _ComposerMode.sendText:
        return disabled ? null : onSendText;
      case _ComposerMode.sendAudio:
        return disabled ? null : onStartAudio;
    }
  }

  @override
  Widget build(BuildContext context) {
    final visualEnabled = !disabled;
    return GestureDetector(
      onTap: _resolveTap(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: visualEnabled ? kAccent : kMuted.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(19),
          boxShadow: visualEnabled
              ? [
                  BoxShadow(
                    color: kAccent.withValues(alpha: 0.33),
                    blurRadius: 16,
                  ),
                ]
              : null,
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: ScaleTransition(scale: anim, child: child),
          ),
          child: Icon(
            _icon,
            key: ValueKey(_mode),
            color: visualEnabled ? Colors.black : kMuted,
            size: 20,
          ),
        ),
      ),
    );
  }
}
