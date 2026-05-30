import 'dart:async';

import 'package:app/config/dependencies.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/ui/app_theme.dart';
import 'package:app/ui/chat/quick_actions/states/quick_actions_state.dart';
import 'package:app/ui/chat/quick_actions/viewmodels/quick_actions_viewmodel.dart';
import 'package:app/ui/chat/quick_actions/widgets/model_picker_sheet.dart';
import 'package:app/ui/chat/viewmodels/chat_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

/// Plan/28 Wave C — entry point for the Quick Actions sheet from the
/// chat input bar. Provides a fresh [QuickActionsViewModel] scoped to
/// this sheet (and any sub-sheets it pushes) and wires the SnackBar
/// error stream from the chat scaffold's messenger so failures stay
/// visible after the sheet is dismissed.
///
/// Both the messenger and the `session_new` reset callback are captured
/// from the *page* context here, before the sheet pushes its own route —
/// the modal's builder context lives above the chat page's providers, so
/// `context.read<ChatViewModel>()` inside the sheet would not resolve.
Future<void> showQuickActionsSheet(BuildContext context) {
  final messenger = ScaffoldMessenger.of(context);
  final chat = context.read<ChatViewModel>();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: kBg,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    isScrollControlled: true,
    showDragHandle: false,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return ChangeNotifierProvider<QuickActionsViewModel>(
        create: (_) => injector.get<QuickActionsViewModel>(),
        child: QuickActionsSheetBody(
          messenger: messenger,
          onSessionReset: chat.clearActiveSession,
        ),
      );
    },
  );
}

/// Body of the Quick Actions sheet. Public so widget tests can drive the
/// real action handlers (close-on-success, toasts, session reset) with a
/// fake ViewModel instead of the replica harness they used before.
class QuickActionsSheetBody extends StatefulWidget {
  final ScaffoldMessengerState messenger;

  /// Invoked after the Pi acks a `session_new`, to wipe the local chat
  /// mirror. Optional so tests can omit it; in the app it is wired to
  /// [ChatViewModel.clearActiveSession].
  final Future<void> Function()? onSessionReset;

  const QuickActionsSheetBody({
    super.key,
    required this.messenger,
    this.onSessionReset,
  });

  @override
  State<QuickActionsSheetBody> createState() => _QuickActionsSheetBodyState();
}

class _QuickActionsSheetBodyState extends State<QuickActionsSheetBody> {
  StreamSubscription<String>? _errorSub;

  @override
  void initState() {
    super.initState();
    // Listener is attached in didChangeDependencies so we have a vm.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final vm = context.read<QuickActionsViewModel>();
      _errorSub = vm.errors.listen(_showError);
    });
  }

  void _showError(String message) => _toast(message, Colors.redAccent);

  void _showSuccess(String message) => _toast(message, kAccent);

  /// Toasts go through the chat scaffold's messenger (captured before the
  /// sheet opened) so success/failure feedback survives the sheet being
  /// popped on success.
  void _toast(String message, Color color) {
    widget.messenger.showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF1A1A1A),
        behavior: SnackBarBehavior.floating,
        content: Text(
          message,
          style: TextStyle(
            fontFamily: kMono,
            fontSize: 12,
            color: color,
          ),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  void dispose() {
    _errorSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<QuickActionsViewModel>();
    final state = vm.state;
    final busyAction =
        state is QuickActionsBusy ? state.action : null;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            _DragHandle(),
            const SizedBox(height: 6),
            const _SheetTitle(text: 'Quick actions'),
            const _Divider(),
            _ActionTile(
              key: const Key('qa-compact'),
              icon: LucideIcons.shrink,
              label: 'Compact context',
              subtitle: 'Summarize old turns to free room.',
              busy: busyAction == ActionName.sessionCompact,
              onTap: () => _onCompact(vm),
            ),
            const _Divider(),
            _ActionTile(
              key: const Key('qa-new-session'),
              icon: LucideIcons.sparkles,
              label: 'New session',
              subtitle: 'Clears the conversation on the Pi.',
              busy: busyAction == ActionName.sessionNew,
              onTap: () => _onNewSession(vm),
            ),
            const _Divider(),
            _ModelRow(
              currentLabel:
                  vm.currentModel?.name ?? vm.currentModelName,
              busy: busyAction == ActionName.modelSet,
              onTap: () => _openModelPicker(vm),
            ),
            const _Divider(),
            _ThinkingRow(
              current: vm.currentThinking,
              busy: busyAction == ActionName.thinkingSet,
              onPick: (level) => _onThinking(vm, level),
            ),
            const SizedBox(height: 18),
          ],
        ),
      ),
    );
  }

  Future<void> _onCompact(QuickActionsViewModel vm) async {
    try {
      await vm.compact();
    } catch (_) {
      // Failure already surfaced as an error toast via `vm.errors`; leave
      // the sheet open so the user can retry.
      return;
    }
    // action_ok — close the sheet and confirm with a toast.
    if (!mounted) return;
    Navigator.of(context).pop();
    _showSuccess('Context compacted');
  }

  Future<void> _onNewSession(QuickActionsViewModel vm) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: kBorder),
        ),
        title: const Text(
          'Start a new session?',
          style: TextStyle(fontFamily: kMono, fontSize: 14, color: kText),
        ),
        content: const Text(
          'This clears the Pi-side conversation history. The current '
          'thread cannot be resumed.',
          style: TextStyle(fontFamily: kMono, fontSize: 12, color: kMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(fontFamily: kMono, color: kMuted),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: kAccent,
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Start new',
              style: TextStyle(fontFamily: kMono),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await vm.newSession();
    } catch (_) {
      // Failure already surfaced as an error toast via `vm.errors`; leave
      // the sheet open so the user can retry.
      return;
    }
    // action_ok — wipe the local chat mirror so the UI reflects the fresh
    // session, then close the sheet and confirm with a toast.
    await widget.onSessionReset?.call();
    if (!mounted) return;
    Navigator.of(context).pop();
    _showSuccess('New session started');
  }

  Future<void> _onThinking(
    QuickActionsViewModel vm,
    ThinkingLevel level,
  ) async {
    try {
      await vm.setThinking(level);
    } catch (_) {/* surfaced via vm.errors */}
  }

  Future<void> _openModelPicker(QuickActionsViewModel vm) async {
    await showModelPickerSheet(context, vm: vm);
  }
}

// ---------------------------------------------------------------------------
// UI pieces
// ---------------------------------------------------------------------------

class _DragHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: kBorder,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _SheetTitle extends StatelessWidget {
  final String text;
  const _SheetTitle({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: const TextStyle(
            fontFamily: kMono,
            fontSize: 12,
            color: kMuted,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) => const Divider(
        color: kBorder,
        height: 1,
        thickness: 1,
      );
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool busy;
  final VoidCallback onTap;
  const _ActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: busy ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: kAccent, size: 18),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontFamily: kMono,
                      fontSize: 13,
                      color: kText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontFamily: kMono,
                      fontSize: 11,
                      color: kMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (busy)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 1.6,
                  color: kAccent,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ModelRow extends StatelessWidget {
  /// Display label — `WireModel.name` when the catalogue is loaded,
  /// otherwise the `room_meta.model` string. `null` falls back to the
  /// generic placeholder. Reads cheap so the picker can lazy-load.
  final String? currentLabel;
  final bool busy;
  final VoidCallback onTap;
  const _ModelRow({
    required this.currentLabel,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final label = currentLabel ?? (busy ? 'Switching…' : 'Choose a model');
    return InkWell(
      key: const Key('qa-model-row'),
      onTap: busy ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            const Icon(LucideIcons.memoryStick, color: kAccent, size: 18),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Model',
                    style: TextStyle(
                      fontFamily: kMono,
                      fontSize: 11,
                      color: kMuted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: const TextStyle(
                      fontFamily: kMono,
                      fontSize: 13,
                      color: kText,
                    ),
                  ),
                ],
              ),
            ),
            if (busy)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 1.6,
                  color: kAccent,
                ),
              )
            else
              const Icon(LucideIcons.chevronRight, color: kMuted, size: 18),
          ],
        ),
      ),
    );
  }
}

class _ThinkingRow extends StatelessWidget {
  final ThinkingLevel? current;
  final bool busy;
  final ValueChanged<ThinkingLevel> onPick;
  const _ThinkingRow({
    required this.current,
    required this.busy,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.brain,
                  color: kAccent, size: 18),
              const SizedBox(width: 14),
              const Text(
                'Thinking',
                style: TextStyle(
                  fontFamily: kMono,
                  fontSize: 11,
                  color: kMuted,
                ),
              ),
              const Spacer(),
              if (busy)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    color: kAccent,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _ThinkingSegmented(
            current: current,
            disabled: busy,
            onPick: onPick,
          ),
        ],
      ),
    );
  }
}

class _ThinkingSegmented extends StatelessWidget {
  final ThinkingLevel? current;
  final bool disabled;
  final ValueChanged<ThinkingLevel> onPick;
  const _ThinkingSegmented({
    required this.current,
    required this.disabled,
    required this.onPick,
  });

  // Short label shown in the segmented buttons. Matches the SDK's
  // ThinkingLevel order (off → xhigh).
  static const _labels = <ThinkingLevel, String>{
    ThinkingLevel.off: 'off',
    ThinkingLevel.minimal: 'min',
    ThinkingLevel.low: 'low',
    ThinkingLevel.medium: 'med',
    ThinkingLevel.high: 'high',
    ThinkingLevel.xhigh: 'x',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: kBorder),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          for (final level in ThinkingLevel.values)
            Expanded(
              child: _SegButton(
                key: Key('qa-thinking-${level.wire}'),
                label: _labels[level]!,
                selected: current == level,
                disabled: disabled,
                onTap: () => onPick(level),
              ),
            ),
        ],
      ),
    );
  }
}

class _SegButton extends StatelessWidget {
  final String label;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;
  const _SegButton({
    super.key,
    required this.label,
    required this.selected,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? kAccent.withValues(alpha: 0.15) : Colors.transparent,
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontFamily: kMono,
              fontSize: 11,
              color: disabled
                  ? kMuted.withValues(alpha: 0.5)
                  : selected
                      ? kAccent
                      : kText,
            ),
          ),
        ),
      ),
    );
  }
}
