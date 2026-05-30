import 'package:app/data/transport/epk_encoding.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart' show RoomInfo;
import 'package:app/routing/adaptive.dart';
import 'package:app/ui/app_theme.dart';
import 'package:app/ui/home/states/home_state.dart';
import 'package:app/ui/settings/settings_sheet.dart';
import 'package:app/ui/home/viewmodels/home_viewmodel.dart';
import 'package:app/ui/home/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

/// Plan-18 follow-up — iOS-style large title that collapses into a
/// compact bar when scrolled. Built with `SliverAppBar +
/// FlexibleSpaceBar`. Subtitle shows the first paired Mac + relay
/// status. Body is sectioned by pairing always (single peer also
/// gets the pairing header, per the mock).
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<HomeViewModel>();
    final state = vm.state;

    // Plan/tablet — tell the adaptive shell whether Home has anything to
    // list. On a zero-state (no Pi paired / empty list) the shell drops
    // the two-pane split and shows this page full-width + centered. Done
    // post-frame so we never notify mid-build.
    final isZeroState = switch (state) {
      HomeLoading() => false,
      HomeNoPeer() => true,
      HomeList() => state.items(normalizeEpk: toStandardB64).isEmpty,
    };
    final shell = context.read<ShellLayout>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      shell.setZeroState(isZeroState);
    });

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            _buildLargeTitleBar(context, vm, state),
            switch (state) {
              HomeLoading() => const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: CircularProgressIndicator(color: kAccent),
                  ),
                ),
              HomeNoPeer() => const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyState(),
                ),
              HomeList() => _buildListSlivers(context, vm, state),
            },
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Large title (iOS-style)
  // ---------------------------------------------------------------------------

  Widget _buildLargeTitleBar(
    BuildContext context,
    HomeViewModel vm,
    HomeState state,
  ) {
    final subtitle = _subtitleFor(vm, state);
    const maxExpanded = 124.0;
    return SliverAppBar(
      backgroundColor: kBg,
      surfaceTintColor: kBg,
      elevation: 0,
      scrolledUnderElevation: 0,
      pinned: true,
      stretch: false,
      expandedHeight: maxExpanded,
      collapsedHeight: 56,
      toolbarHeight: 56,
      automaticallyImplyLeading: false,
      actions: [
        IconButton(
          tooltip: 'Settings',
          icon: const Icon(LucideIcons.settings, color: kMuted2),
          // Tablet → bottom sheet (keeps the chat in context); phone →
          // full-screen push. See openSettings.
          onPressed: () => openSettings(context),
        ),
        const SizedBox(width: 4),
      ],
      // Title rendering happens entirely inside flexibleSpace so we
      // can cross-fade between the large form (expanded) and the
      // compact form (collapsed). Using `SliverAppBar.title` here
      // would overlay the compact title on top of the large one
      // while expanded — that was the "two app bars" bug.
      flexibleSpace: LayoutBuilder(
        builder: (ctx, constraints) {
          final maxH = constraints.maxHeight;
          const minH = 56.0;
          // t=1 → fully expanded; t=0 → fully collapsed.
          final t =
              ((maxH - minH) / (maxExpanded - minH)).clamp(0.0, 1.0);
          return Stack(
            fit: StackFit.expand,
            children: [
              Container(color: kBg),
              // Large title block — fades OUT as we collapse.
              Positioned(
                left: 20,
                right: 20,
                bottom: 8,
                child: IgnorePointer(
                  ignoring: t < 0.05,
                  child: Opacity(
                    opacity: t,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Remote Pi',
                          style: TextStyle(
                            fontFamily: kMono,
                            color: kText,
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.8,
                            height: 1.05,
                          ),
                        ),
                        const SizedBox(height: 6),
                        subtitle,
                      ],
                    ),
                  ),
                ),
              ),
              // Compact title — fades IN as we collapse.
              Positioned(
                left: 20,
                right: 64, // leave space for the actions icon
                top: 0,
                height: 56,
                child: IgnorePointer(
                  ignoring: t > 0.95,
                  child: Opacity(
                    opacity: 1 - t,
                    child: const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Remote Pi',
                        style: TextStyle(
                          fontFamily: kMono,
                          color: kText,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Bottom divider — only shows once collapsed.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Opacity(
                  opacity: 1 - t,
                  child: const Divider(
                    color: kBorder,
                    height: 1,
                    thickness: 1,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Subtitle line under "Remote Pi": ● Relay · [Connected|Awaiting pairing|Offline].
  /// Reflects the app→relay WS state (not per-Pi presence) so the
  /// user always knows whether the app itself is reachable.
  ///
  /// `HomeNoPeer` is the special case where no peer is paired yet —
  /// the WS is never opened (its URL embeds the destination peer's
  /// pubkey), so `isRelayConnected` is false but that doesn't mean
  /// the relay is down. Render a neutral "Awaiting pairing" instead
  /// of the alarming amber "Offline".
  Widget _subtitleFor(HomeViewModel vm, HomeState state) {
    final connected = vm.isRelayConnected;
    final awaitingPairing = state is HomeNoPeer;
    final Color dotColor;
    final String statusLabel;
    final Color statusColor;
    if (connected) {
      dotColor = kSuccess;
      statusLabel = 'Connected';
      statusColor = kMuted;
    } else if (awaitingPairing) {
      dotColor = kMuted;
      statusLabel = 'Awaiting pairing';
      statusColor = kMuted;
    } else {
      dotColor = Colors.amber.shade600;
      statusLabel = 'Offline';
      statusColor = Colors.amber.shade600;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: dotColor,
          ),
        ),
        const SizedBox(width: 8),
        const Text(
          'Relay',
          style: TextStyle(
            fontFamily: kMono,
            color: kText,
            fontSize: 13,
          ),
        ),
        const SizedBox(width: 6),
        const Text(
          '·',
          style: TextStyle(fontFamily: kMono, color: kMuted, fontSize: 13),
        ),
        const SizedBox(width: 6),
        Text(
          statusLabel,
          style: TextStyle(
            fontFamily: kMono,
            color: statusColor,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // List body
  // ---------------------------------------------------------------------------

  Widget _buildListSlivers(
    BuildContext context,
    HomeViewModel vm,
    HomeList state,
  ) {
    final items = state.items(normalizeEpk: toStandardB64);
    if (items.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: _LonelyEmptyState(),
      );
    }
    // Build the per-peer groups: each group is [header, tile, tile, …].
    // Plan-18 follow-up — always include a header even when there's a
    // single Mac, per the mock ("SESSIONS"-style header per pairing).
    final children = <Widget>[];
    String? lastEpk;
    for (final it in items) {
      if (it.peer.remoteEpk != lastEpk) {
        children.add(PeerSectionHeader(peer: it.peer));
        lastEpk = it.peer.remoteEpk;
      }
      children.add(_buildItemRowAt(context, vm, state, it));
    }
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (ctx, i) => children[i],
          childCount: children.length,
        ),
      ),
    );
  }

  Widget _buildItemRowAt(
    BuildContext context,
    HomeViewModel vm,
    HomeList state,
    HomeItem it,
  ) {
    final isLive = vm.isRoomLive(it.peer.remoteEpk, it.room.roomId);
    final isReconnecting = !vm.isRelayConnected;
    final isWorking = vm.isRoomWorking(it.peer.remoteEpk, it.room.roomId);
    // Plan/tablet — highlight the open session, but only in the two-pane
    // layout (on phone the list is covered by the pushed chat, so a
    // persistent highlight would be meaningless).
    final isSelected = isWideLayout(context) &&
        context.watch<SessionSelection>().matches(
              it.peer.remoteEpk,
              it.room.roomId,
            );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SessionTile(
          peer: it.peer,
          isLive: isLive,
          isReconnecting: isReconnecting,
          isWorking: isWorking,
          isSelected: isSelected,
          room: it.room,
          onOpen: () =>
              _open(context, vm, it.peer, it.room),
          onLongPress: () =>
              _showSessionMenu(context, vm, it, isLive: isLive),
        ),
        const Divider(color: kBorder, height: 1),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Long-press menu (preserved from prior plan-17 wiring)
  // ---------------------------------------------------------------------------

  void _showSessionMenu(
    BuildContext context,
    HomeViewModel vm,
    HomeItem it, {
    required bool isLive,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kBg,
      builder: (sheetCtx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(LucideIcons.pencil, color: kAccent),
                title: const Text(
                  'Rename session',
                  style: TextStyle(color: kText),
                ),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  _promptRename(context, vm, it);
                },
              ),
              ListTile(
                leading: Icon(
                  LucideIcons.trash2,
                  color: isLive ? kMuted : Colors.redAccent,
                ),
                enabled: !isLive,
                title: Text(
                  'Delete session (local only)',
                  style: TextStyle(color: isLive ? kMuted : kText),
                ),
                subtitle: isLive
                    ? const Text(
                        'Only available when the room is offline',
                        style: TextStyle(color: kMuted, fontSize: 11),
                      )
                    : null,
                onTap: isLive
                    ? null
                    : () {
                        Navigator.of(sheetCtx).pop();
                        _confirmDelete(context, vm, it);
                      },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _promptRename(
      BuildContext context, HomeViewModel vm, HomeItem it) async {
    final controller = TextEditingController(text: it.room.name ?? '');
    final result = await showDialog<String?>(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: kBg,
        title:
            const Text('Rename session', style: TextStyle(color: kText)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: kText, fontFamily: kMono),
          decoration: InputDecoration(
            hintText: it.room.cwd ?? 'Session',
            hintStyle: const TextStyle(color: kMuted),
            enabledBorder:
                const OutlineInputBorder(borderSide: BorderSide(color: kBorder)),
            focusedBorder:
                const OutlineInputBorder(borderSide: BorderSide(color: kAccent)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(null),
            child: const Text('Cancel', style: TextStyle(color: kMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(controller.text.trim()),
            child: const Text('Save', style: TextStyle(color: kAccent)),
          ),
        ],
      ),
    );
    if (result == null) return;
    await vm.renameRoom(it.peer.remoteEpk, it.room.roomId, result);
  }

  Future<void> _confirmDelete(
      BuildContext context, HomeViewModel vm, HomeItem it) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: kBg,
        title: const Text('Delete session?', style: TextStyle(color: kText)),
        content: const Text(
          'Removes locally only. If the session comes back online on '
          'the Pi, it reappears in the list.',
          style: TextStyle(color: kMuted, fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: kMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(true),
            child:
                const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await vm.deleteRoom(it.peer.remoteEpk, it.room.roomId);
  }

  static Future<void> _open(
    BuildContext context,
    HomeViewModel vm,
    PeerRecord peer,
    RoomInfo room,
  ) async {
    // Sets prefs (selectedPeerEpk + room) + switchRoom so a fresh
    // ChatViewModel binds to this session.
    await vm.openSession(peer.remoteEpk, roomId: room.roomId);
    if (!context.mounted) return;
    final title = _titleFor(peer, room);
    // Mark the UI selection — drives the tablet detail pane AND the
    // highlighted tile. Set AFTER openSession so the detail's fresh
    // ChatViewModel reads the already-updated prefs.
    context.read<SessionSelection>().select(peer.remoteEpk, room.roomId, title);
    // Phone: full-screen chat (root push → native back/swipe). Tablet:
    // the detail pane reacts to the selection above — no nav needed.
    if (!isWideLayout(context)) {
      context.push('/chat', extra: {'title': title});
    }
  }

  /// Plan/24-fix-title: the peer/room label we already know here, so the
  /// Chat AppBar doesn't show '—' / 'Remote Pi' until the ChatViewModel
  /// loads the PeerRecord + the first room_meta_updated arrives. Prefers
  /// room.name (per-cwd title) → cwd tail → nickname → sessionName.
  static String _titleFor(PeerRecord peer, RoomInfo room) {
    final roomCwdTail =
        room.cwd?.split('/').where((s) => s.isNotEmpty).lastOrNull;
    return (room.name?.isNotEmpty ?? false)
        ? room.name!
        : (roomCwdTail != null && roomCwdTail.isNotEmpty)
            ? roomCwdTail
            : (peer.nickname?.isNotEmpty ?? false)
                ? peer.nickname!
                : peer.sessionName.isNotEmpty
                    ? peer.sessionName
                    : peer.remoteEpk.substring(0, 8);
  }
}


/// Plan-17 follow-up — soft empty state for paired-but-no-rooms.
class _LonelyEmptyState extends StatelessWidget {
  const _LonelyEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
        child: Opacity(
          opacity: 0.35,
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.moon, color: kMuted, size: 56),
                const SizedBox(height: 18),
                const Text(
                  'Nothing here…',
                  style: TextStyle(
                    fontFamily: kMono,
                    color: kMuted2,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'When a paired Pi opens a session, it shows up here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: kMono,
                    color: kMuted,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.scanQrCode, color: kMuted, size: 48),
              const SizedBox(height: 16),
              const Text(
                'No pairings yet',
                style: TextStyle(color: kMuted2, fontSize: 14),
              ),
              const SizedBox(height: 6),
              const Text(
                'Scan a QR from your Mac to start.',
                style: TextStyle(color: kMuted, fontSize: 12),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => context.push('/pair'),
                style: FilledButton.styleFrom(
                  backgroundColor: kAccent,
                  foregroundColor: Colors.black,
                ),
                icon: const Icon(LucideIcons.scanQrCode, size: 18),
                label: const Text('Scan QR'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
