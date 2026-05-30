import 'package:app/data/preferences/preferences.dart';
import 'package:app/domain/session_state.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/ui/app_theme.dart';
import 'package:app/ui/chat/quick_actions/widgets/quick_actions_sheet.dart';
import 'package:app/ui/chat/states/chat_state.dart';
import 'package:app/ui/chat/viewmodels/chat_viewmodel.dart';
import 'package:app/ui/chat/widgets/input_bar.dart';
import 'package:app/ui/chat/widgets/message_bubble.dart';
import 'package:app/ui/chat/widgets/streaming_bubble.dart';
import 'package:app/ui/chat/widgets/tool_request_card.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

class ChatPage extends StatelessWidget {
  /// Plan/24-fix-title: optional title hint passed via `go_router`
  /// `extra` from the Home tile. Used as the peer-label fallback in
  /// the AppBar so the user sees the right name *immediately* on
  /// navigation, instead of "—" / "Remote Pi" until the PeerRecord
  /// is loaded by the ViewModel and the first `room_meta_updated`
  /// arrives.
  final String? initialTitle;

  /// Plan/tablet — `false` when the chat is embedded as the tablet's
  /// detail pane (no navigation stack to pop back to). Hides the back
  /// arrow; defaults to `true` for the phone full-screen route.
  final bool showBack;

  const ChatPage({super.key, this.initialTitle, this.showBack = true});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ChatViewModel>();
    final state = vm.state;

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context, state),
            // Pairing revocation is the only banner kept — it's a hard
            // failure (can't proceed without re-pairing), red, with an
            // explicit action. Plain offline / Pi-gone / presence-off
            // banners were removed: the AppBar status line already
            // surfaces those, and stacking duplicates noise the surface.
            if (state is ChatReady && state.pairingRevoked)
              _RevokedBanner(onRePair: () => context.go('/pair')),
            Expanded(child: _buildBody(context, state, vm)),
            _buildInput(context, state, vm),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, ChatState state) {
    // Plan-17 follow-up — two-line AppBar:
    //   Line 1: ROOM name (cwd basename / room.name / fallback).
    //   Line 2: peer (Mac nickname or sessionName) + presence dot.
    // The dot reads from the ChatReady.peerPresence flag (which the
    // ViewModel sources from `isRoomLive`).
    final vm = context.watch<ChatViewModel>();
    final peer = vm.activePeer;
    final room = vm.activeRoom;
    final isOnline = vm.isRoomLive;
    // Plan-18 follow-up — when the chat is "offline" (WS to relay
    // down or retrying), prefer a "reconectando" amber pill so the
    // user knows it's the relay, not the Pi cwd, that's gone.
    final isReconnecting = state is ChatReady && (state).isOffline;
    // Plan-18 follow-up — when the agent is currently producing a
    // response, show "working…" instead of online/offline.
    final isWorking = vm.isWorking;

    // Plan/24-fix-title: pass the navigation hint into the helpers so
    // either line of the AppBar (room or peer) shows it instead of
    // the generic placeholders when the ViewModel hasn't finished
    // bootstrapping yet.
    final roomName = _roomDisplayName(room, state, initialTitle);
    final peerLabel = _peerDisplayName(peer, initialTitle);

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: const BoxDecoration(
        color: kBg,
        border: Border(bottom: BorderSide(color: kBorder)),
      ),
      child: Row(
        children: [
          if (showBack)
            IconButton(
              icon:
                  const Icon(LucideIcons.chevronLeft, size: 18, color: kText),
              tooltip: 'Back',
              onPressed: () =>
                  context.canPop() ? context.pop() : context.go('/home'),
            )
          else
            const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _truncate(roomName, 28),
                  style: const TextStyle(
                    fontFamily: kMono,
                    fontSize: 13,
                    color: kText,
                    letterSpacing: -0.2,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _truncate(peerLabel, 24),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: kMono,
                          fontSize: 10,
                          color: kMuted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Builder(builder: (_) {
                      // Plan-18 follow-up — 4-state pill:
                      // working / reconnecting / online / offline.
                      // Priority: working > reconnecting > online > offline.
                      const kWorking = Color(0xFF3FA9F5);
                      final color = isWorking
                          ? kWorking
                          : isReconnecting
                              ? Colors.amber.shade600
                              : isOnline
                                  ? kSuccess
                                  : kMuted;
                      final label = isWorking
                          ? 'working…'
                          : isReconnecting
                              ? 'reconnecting…'
                              : isOnline
                                  ? 'online'
                                  : 'offline';
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: color,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            label,
                            style: TextStyle(
                              fontFamily: kMono,
                              fontSize: 10,
                              color: color,
                            ),
                          ),
                        ],
                      );
                    }),
                  ],
                ),
              ],
            ),
          ),
          if (peer != null)
            IconButton(
              icon: const Icon(LucideIcons.info, size: 18, color: kMuted2),
              tooltip: 'Session info',
              onPressed: () =>
                  _showSessionInfo(context, peer, room, roomName),
            ),
        ],
      ),
    );
  }

  /// Session details dialog — surfaced from the AppBar info action.
  /// Shows the human name, the Pi-side path (cwd), the owning device,
  /// plus model/room/paired-date when known.
  static Future<void> _showSessionInfo(
    BuildContext context,
    PeerRecord peer,
    RoomInfo? room,
    String name,
  ) {
    final owner = (peer.nickname?.isNotEmpty ?? false)
        ? peer.nickname!
        : peer.sessionName.isNotEmpty
            ? peer.sessionName
            : peer.remoteEpk.substring(0, 8);
    final model = room?.model;
    final paired = peer.pairedAt.contains('T')
        ? peer.pairedAt.split('T').first
        : peer.pairedAt;
    return showDialog<void>(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: kBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: kBorder),
        ),
        title: const Text(
          'Session info',
          style: TextStyle(fontFamily: kMono, fontSize: 15, color: kText),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _InfoRow(label: 'Name', value: name),
            _InfoRow(label: 'Path', value: room?.cwd ?? '—'),
            _InfoRow(label: 'Owner', value: owner),
            if (model != null && model.isNotEmpty)
              _InfoRow(label: 'Model', value: model),
            _InfoRow(label: 'Room', value: room?.roomId ?? '—'),
            _InfoRow(label: 'Paired', value: paired),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(),
            child: const Text(
              'Close',
              style: TextStyle(fontFamily: kMono, color: kAccent),
            ),
          ),
        ],
      ),
    );
  }

  static String _roomDisplayName(
    RoomInfo? room,
    ChatState state,
    String? initialTitle,
  ) {
    if (room != null) {
      if (room.name != null && room.name!.isNotEmpty) return room.name!;
      final cwd = room.cwd;
      if (cwd != null && cwd.isNotEmpty) {
        final segs = cwd.split('/').where((s) => s.isNotEmpty).toList();
        if (segs.isNotEmpty) return segs.last;
      }
    }
    if (state is ChatReady && state.messages.isNotEmpty) {
      return _inferSessionName(state.messages);
    }
    // Plan/24-fix-title: Home knows the peer label before /chat
    // mounts; use it instead of the generic 'Remote Pi' placeholder
    // while we wait for the first room_meta_updated to populate
    // `room.name`.
    if (initialTitle != null && initialTitle.isNotEmpty) return initialTitle;
    return 'Remote Pi';
  }

  static String _peerDisplayName(PeerRecord? peer, String? initialTitle) {
    if (peer == null) {
      // Plan/24-fix-title: while the ViewModel hasn't loaded the
      // PeerRecord yet, fall back to whatever Home passed us.
      if (initialTitle != null && initialTitle.isNotEmpty) return initialTitle;
      return '—';
    }
    if (peer.nickname != null && peer.nickname!.isNotEmpty) {
      return peer.nickname!;
    }
    if (peer.sessionName.isNotEmpty) return peer.sessionName;
    return peer.remoteEpk.substring(0, 8);
  }

  static String _truncate(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max - 1)}…';

  Widget _buildBody(BuildContext context, ChatState state, ChatViewModel vm) {
    final hideToolCalls = context.watch<Preferences>().hideToolCalls;
    return switch (state) {
      // Edge case: opened /chat without a peer (e.g. peer revoked while
      // user was here). The chat is not the place to pair — render
      // a minimal empty state without an action. User navigates back
      // and uses Home / Settings → pairing.
      ChatNoPeer() => const _EmptyState(
        icon: LucideIcons.messageCircle,
        message: 'No active device',
      ),
      ChatConnecting() => const _EmptyState(
        icon: LucideIcons.refreshCw,
        message: 'Connecting…',
      ),
      ChatFatalError(:final message) => _EmptyState(
        icon: LucideIcons.circleAlert,
        message: message,
        actionLabel: 'Re-pair',
        onAction: () => context.go('/pair'),
      ),
      ChatReady(:final messages, :final streaming) => _MessageList(
        messages: hideToolCalls
            ? messages.where((m) => m is! ToolEvent).toList()
            : messages,
        streaming: streaming,
        onDecide: (id, decision) => vm.approveTool(id, decision),
      ),
    };
  }

  Widget _buildInput(BuildContext context, ChatState state, ChatViewModel vm) {
    final isReady = state is ChatReady;
    final isOffline = isReady && state.isOffline;
    final isRevoked = isReady && state.pairingRevoked;
    final isPeerOffline = isReady && state.peerOfflineReason != null;
    // Live relay-reported offline (no `bye`): Pi is just not reachable.
    final isPresenceOffline = isReady && state.peerPresence is PresenceOffline;
    final isStreaming = isReady && state.streaming != null;
    final streamingId = isReady ? state.streaming?.inReplyTo : null;
    // Quick actions need an open channel to dispatch — only offer the
    // entry point when the chat input itself is enabled. Hiding the
    // ⚙ button on offline avoids a tap that would just throw inside
    // the sheet.
    final actionsEnabled = isReady
        && !isOffline
        && !isRevoked
        && !isPeerOffline
        && !isPresenceOffline;

    return InputBar(
      disabled: !isReady
          || isOffline
          || isRevoked
          || isPeerOffline
          || isPresenceOffline,
      streaming: isStreaming,
      onSend: (text) => vm.sendMessage(text),
      onCancel: streamingId != null ? () => vm.cancel(streamingId) : null,
      onOpenQuickActions:
          actionsEnabled ? () => showQuickActionsSheet(context) : null,
    );
  }

  static String _inferSessionName(List<ChatMessage> msgs) {
    for (final m in msgs) {
      if (m is UserMsg) return m.text.substring(0, m.text.length.clamp(0, 32));
    }
    return 'Remote Pi';
  }
}

// ---------------------------------------------------------------------------

class _MessageList extends StatefulWidget {
  final List<ChatMessage> messages;
  final StreamingMessage? streaming;
  final void Function(String, ApproveDecision) onDecide;

  const _MessageList({
    required this.messages,
    required this.streaming,
    required this.onDecide,
  });

  @override
  State<_MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<_MessageList> {
  final _scroll = ScrollController();
  bool _userScrolled = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.userScrollDirection.name == 'reverse') {
        _userScrolled = true;
      }
      if (_scroll.position.pixels < 20) _userScrolled = false;
    });
  }

  @override
  void didUpdateWidget(_MessageList old) {
    super.didUpdateWidget(old);
    if (!_userScrolled) _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final itemCount =
        widget.messages.length + (widget.streaming != null ? 1 : 0);

    return ListView.separated(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
      itemCount: itemCount,
      separatorBuilder: (context, idx) => const SizedBox(height: 14),
      itemBuilder: (_, i) {
        // Index 0 = bottom = newest
        if (widget.streaming != null && i == 0) {
          return StreamingBubble(widget.streaming!);
        }
        final msgIdx =
            widget.messages.length -
            1 -
            (i - (widget.streaming != null ? 1 : 0));
        final msg = widget.messages[msgIdx];
        return switch (msg) {
          UserMsg() => UserBubble(msg),
          AssistantMsg() => AssistantBubble(msg),
          ToolEvent() => ToolRequestCard(tool: msg, onDecide: widget.onDecide),
        };
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _EmptyState({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: kMuted, size: 48),
          const SizedBox(height: 16),
          Text(message, style: const TextStyle(color: kMuted, fontSize: 14)),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 24),
            FilledButton(
              onPressed: onAction,
              style: FilledButton.styleFrom(
                backgroundColor: kAccent,
                foregroundColor: Colors.black,
              ),
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

class _RevokedBanner extends StatelessWidget {
  final VoidCallback onRePair;
  const _RevokedBanner({required this.onRePair});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.red.shade900.withValues(alpha: 0.85),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(LucideIcons.unlink, color: Colors.white, size: 15),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Pairing revoked by Mac — re-pair to continue',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          GestureDetector(
            onTap: onRePair,
            child: const Text(
              'Re-pair',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One labelled key/value row in the session-info dialog. The value is
/// selectable so the user can copy the path / device name.
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontFamily: kMono,
              fontSize: 10,
              color: kMuted,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 2),
          SelectableText(
            value,
            style: const TextStyle(
              fontFamily: kMono,
              fontSize: 13,
              color: kText,
            ),
          ),
        ],
      ),
    );
  }
}
