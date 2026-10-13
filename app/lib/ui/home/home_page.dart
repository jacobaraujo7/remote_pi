import 'package:app/data/actions/actions_repository.dart';
import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/transport/connection_manager.dart' show StatusOnline;
import 'package:app/data/transport/epk_encoding.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart' show RoomInfo;
import 'package:app/routing/adaptive.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:app/ui/home/states/home_state.dart';
import 'package:app/ui/settings/settings_sheet.dart';
import 'package:app/ui/home/viewmodels/home_viewmodel.dart';
import 'package:app/ui/home/widgets/widgets.dart';
import 'package:app/ui/update/widgets/update_banner.dart';
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
    final colors = context.colors;
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
      backgroundColor: colors.bg,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            _buildLargeTitleBar(context, vm, state),
            // Plan 44 — Android-only update notice. Sits at the top of the
            // scroll content (below the title, above the list); shrinks to
            // zero height when there's nothing to announce, so it's invisible
            // on iOS and when no newer version exists.
            const SliverToBoxAdapter(child: UpdateBanner()),
            switch (state) {
              HomeLoading() => SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: CircularProgressIndicator(color: colors.accent),
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
    final colors = context.colors;
    final subtitle = _subtitleFor(context, vm, state);
    const maxExpanded = 124.0;
    return SliverAppBar(
      backgroundColor: colors.bg,
      surfaceTintColor: colors.bg,
      elevation: 0,
      scrolledUnderElevation: 0,
      pinned: true,
      stretch: false,
      expandedHeight: maxExpanded,
      collapsedHeight: 56,
      toolbarHeight: 56,
      automaticallyImplyLeading: false,
      actions: [
        // Room management needs the actions channel; a harness that builds the
        // HomeViewModel without one gets no entry point (see `vm.actions`).
        if (vm.actions != null)
          IconButton(
            key: const Key('home-new-room'),
            tooltip: 'New room',
            // Lucide's set here has no home-plus variant — Material's
            // add_home stays close enough to the 'new room' semantics.
            icon: Icon(Icons.add_home_outlined, color: colors.muted2),
            onPressed: () => _promptNewRoom(context, vm),
          ),
        IconButton(
          tooltip: 'Settings',
          icon: Icon(LucideIcons.settings, color: colors.muted2),
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
          final t = ((maxH - minH) / (maxExpanded - minH)).clamp(0.0, 1.0);
          return Stack(
            fit: StackFit.expand,
            children: [
              Container(color: colors.bg),
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
                        Text(
                          'Remote Pi',
                          style: brandTextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                            color: colors.text,
                            letterSpacing: -0.5,
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
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Remote Pi',
                        style: brandTextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: colors.text,
                          letterSpacing: -0.2,
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
                  child: Divider(color: colors.border, height: 1, thickness: 1),
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
  Widget _subtitleFor(BuildContext context, HomeViewModel vm, HomeState state) {
    final colors = context.colors;
    final connected = vm.isRelayConnected;
    final awaitingPairing = state is HomeNoPeer;
    final Color dotColor;
    final String statusLabel;
    final Color statusColor;
    if (connected) {
      dotColor = colors.success;
      statusLabel = 'Connected';
      statusColor = colors.muted;
    } else if (awaitingPairing) {
      dotColor = colors.muted;
      statusLabel = 'Awaiting pairing';
      statusColor = colors.muted;
    } else {
      dotColor = colors.warning;
      statusLabel = 'Offline';
      statusColor = colors.warning;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
        ),
        const SizedBox(width: 8),
        Text(
          'Relay',
          style: TextStyle(
            fontFamily: kMonoFamily,
            color: colors.text,
            fontSize: 13,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '·',
          style: TextStyle(
            fontFamily: kMonoFamily,
            color: colors.muted,
            fontSize: 13,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          statusLabel,
          style: TextStyle(
            fontFamily: kMonoFamily,
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
    final counts = vm.counts;
    // Globally empty (paired Pi, no rooms at all): keep the original lonely
    // state and DON'T show the tabs — there's nothing to filter.
    if (counts.all == 0) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: _LonelyEmptyState(),
      );
    }

    // Plan-38 Fase 3 — presence filter at the top of the list. Pure view:
    // tapping a tab only swaps `state.filter` → `vm.visibleItems` re-derives.
    final tabs = SliverToBoxAdapter(
      child: HomeFilterTabs(
        filter: state.filter,
        counts: counts,
        onSelected: vm.setFilter,
      ),
    );

    final visible = vm.visibleItems;
    if (visible.isEmpty) {
      // Items exist, but none match this tab → per-tab empty state beneath
      // the tabs (which stay visible so the user can switch back).
      return SliverMainAxisGroup(
        slivers: [
          tabs,
          SliverFillRemaining(
            hasScrollBody: false,
            child: HomeFilterEmptyState(filter: state.filter),
          ),
        ],
      );
    }

    // Build the per-peer groups over the VISIBLE items: each group is
    // [header, tile, tile, …]. Plan-18 follow-up — always include a header
    // even when there's a single Mac, per the mock. A peer with no visible
    // item in this filter contributes no header (the `lastEpk` cursor only
    // advances on rows we actually render).
    final children = <Widget>[];
    String? lastEpk;
    for (final it in visible) {
      if (it.peer.remoteEpk != lastEpk) {
        children.add(PeerSectionHeader(peer: it.peer));
        lastEpk = it.peer.remoteEpk;
      }
      children.add(_buildItemRowAt(context, vm, state, it));
    }
    return SliverMainAxisGroup(
      slivers: [
        tabs,
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) => children[i],
              childCount: children.length,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildItemRowAt(
    BuildContext context,
    HomeViewModel vm,
    HomeList state,
    HomeItem it,
  ) {
    final colors = context.colors;
    final isLive = vm.isRoomLive(it.peer.remoteEpk, it.room.roomId);
    final isReconnecting = !vm.isRelayConnected;
    final isWorking = vm.isRoomWorking(it.peer.remoteEpk, it.room.roomId);
    // Plan/tablet — highlight the open session, but only in the two-pane
    // layout (on phone the list is covered by the pushed chat, so a
    // persistent highlight would be meaningless).
    final isSelected =
        isWideLayout(context) &&
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
          onOpen: () => _open(context, vm, it.peer, it.room),
          onLongPress: () => _showSessionMenu(context, vm, it, isLive: isLive),
        ),
        Divider(color: colors.border, height: 1),
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
      backgroundColor: context.colors.bg,
      builder: (sheetCtx) {
        final colors = sheetCtx.colors;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(LucideIcons.pencil, color: colors.accent),
                title: Text(
                  'Rename session',
                  style: TextStyle(color: colors.text),
                ),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  _promptRename(context, vm, it);
                },
              ),
              ListTile(
                leading: Icon(
                  LucideIcons.trash2,
                  color: isLive ? colors.muted : colors.error,
                ),
                enabled: !isLive,
                title: Text(
                  'Delete session (local only)',
                  style: TextStyle(color: isLive ? colors.muted : colors.text),
                ),
                subtitle: isLive
                    ? Text(
                        'Only available when the room is offline',
                        style: TextStyle(color: colors.muted, fontSize: 11),
                      )
                    : null,
                onTap: isLive
                    ? null
                    : () {
                        Navigator.of(sheetCtx).pop();
                        _confirmDelete(context, vm, it);
                      },
              ),
              if (vm.actions != null)
                ListTile(
                  leading: Icon(LucideIcons.unplug, color: colors.error),
                  title: Text(
                    'Delete room (on the Pi)',
                    style: TextStyle(color: colors.text),
                  ),
                  subtitle: Text(
                    'Stops the agent process for this directory',
                    style: TextStyle(color: colors.muted, fontSize: 11),
                  ),
                  onTap: () {
                    Navigator.of(sheetCtx).pop();
                    _confirmDeleteRoom(context, vm, it);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _promptRename(
    BuildContext context,
    HomeViewModel vm,
    HomeItem it,
  ) async {
    final controller = TextEditingController(text: it.room.name ?? '');
    final result = await showDialog<String?>(
      context: context,
      builder: (dCtx) {
        final colors = dCtx.colors;
        return AlertDialog(
          backgroundColor: colors.bg,
          title: Text('Rename session', style: TextStyle(color: colors.text)),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: TextStyle(color: colors.text, fontFamily: kMonoFamily),
            decoration: InputDecoration(
              hintText: it.room.cwd ?? 'Session',
              hintStyle: TextStyle(color: colors.muted),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: colors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: colors.accent),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dCtx).pop(null),
              child: Text('Cancel', style: TextStyle(color: colors.muted)),
            ),
            TextButton(
              onPressed: () => Navigator.of(dCtx).pop(controller.text.trim()),
              child: Text('Save', style: TextStyle(color: colors.accent)),
            ),
          ],
        );
      },
    );
    if (result == null) return;
    await vm.renameRoom(it.peer.remoteEpk, it.room.roomId, result);
  }

  // ---------------------------------------------------------------------------
  // Room management (Pi-side create / delete)
  // ---------------------------------------------------------------------------

  /// 'New room' button — ask for a directory, then drive the Pi's
  /// `room_create` action through one of the peer's LIVE rooms (the
  /// create frame must ride an already-open room channel; the new room
  /// announces itself on the relay afterwards and the tile appears
  /// automatically via `roomsStream`).
  Future<void> _promptNewRoom(BuildContext context, HomeViewModel vm) async {
    final messenger = ScaffoldMessenger.of(context);
    final controller = TextEditingController();
    final path = await showDialog<String?>(
      context: context,
      builder: (dCtx) {
        final colors = dCtx.colors;
        return AlertDialog(
          backgroundColor: colors.bg,
          title: Text(
            'New room',
            style: TextStyle(
              fontFamily: kMonoFamily,
              color: colors.text,
              fontSize: 14,
            ),
          ),
          content: TextField(
            key: const Key('new-room-path'),
            controller: controller,
            autofocus: true,
            style: TextStyle(color: colors.text, fontFamily: kMonoFamily),
            decoration: InputDecoration(
              hintText: 'Directory path, e.g. ~/projects/foo',
              hintStyle: TextStyle(color: colors.muted),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: colors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: colors.accent),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dCtx).pop(null),
              child: Text(
                'Cancel',
                style: TextStyle(color: colors.muted, fontFamily: kMonoFamily),
              ),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(dCtx).pop(controller.text.trim()),
              child: Text(
                'Create',
                style: TextStyle(
                  color: colors.accent,
                  fontFamily: kMonoFamily,
                ),
              ),
            ),
          ],
        );
      },
    );
    final trimmed = path?.trim() ?? '';
    if (trimmed.isEmpty) return;
    if (!context.mounted) return;
    await _runRoomCreate(context, vm, trimmed, messenger);
  }

  Future<void> _runRoomCreate(
    BuildContext context,
    HomeViewModel vm,
    String path,
    ScaffoldMessengerState messenger,
  ) async {
    final actions = vm.actions;
    if (actions == null) return;
    final conn = vm.conn;
    final prefs = context.read<Preferences>();
    if (conn.status is! StatusOnline) {
      messenger.showSnackBar(const SnackBar(content: Text('Relay offline — try again later')));
      return;
    }
    // Which peer to target: the one the user last selected (if it is
    // the connected one); otherwise the active connection's peer.
    final activeEpk = conn.activePeer?.remoteEpk;
    final selectedEpk = prefs.selectedPeerEpk;
    final targetEpk =
        selectedEpk != null && selectedEpk == activeEpk ? selectedEpk : activeEpk;
    final liveRoom = targetEpk == null ? null : vm.firstLiveRoom(targetEpk);
    if (liveRoom == null) {
      messenger.showSnackBar(const SnackBar(content: Text('Open a room first')));
      return;
    }
    final previousRoom = conn.activeRoomId;
    conn.switchRoom(liveRoom);
    try {
      try {
        await actions.createRoom(path);
        messenger.showSnackBar(const SnackBar(content: Text('Room created')));
      } on ActionFailure catch (e) {
        // Exact error string the Pi sends when the directory is absent
        // and `create_if_missing` is off — offer a create-anyway retry.
        if (e.message == 'directory_missing' && context.mounted) {
          final confirm = await _confirmCreateDirectory(context);
          if (confirm) {
            try {
              await actions.createRoom(path, createIfMissing: true);
              messenger.showSnackBar(const SnackBar(content: Text('Room created')));
            } on ActionFailure catch (e2) {
              messenger.showSnackBar(SnackBar(content: Text(e2.message)));
            }
          }
        } else {
          messenger.showSnackBar(SnackBar(content: Text(e.message)));
        }
      }
    } finally {
      // Restore the room the UI was addressing before the round-trip —
      // the create frame only needed ONE live room to ride on.
      conn.switchRoom(previousRoom);
    }
  }

  /// 'Delete room (on the Pi)' — confirm, drive `room_delete` through a
  /// live room of the SAME peer (the frame targets the room's OWN cwd,
  /// not the channel's), then drop the room from the local cache so the
  /// tile leaves Home.
  Future<void> _confirmDeleteRoom(
    BuildContext context,
    HomeViewModel vm,
    HomeItem it,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dCtx) {
        final colors = dCtx.colors;
        return AlertDialog(
          backgroundColor: colors.bg,
          title: Text(
            'Delete room?',
            style: TextStyle(
              fontFamily: kMonoFamily,
              color: colors.text,
              fontSize: 14,
            ),
          ),
          content: Text(
            'This stops the agent process for ${it.room.cwd ?? 'this directory'} '
            'and removes the room on the Pi.',
            style: TextStyle(
              fontFamily: kMonoFamily,
              color: colors.muted,
              fontSize: 12,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dCtx).pop(false),
              child: Text(
                'Cancel',
                style: TextStyle(color: colors.muted, fontFamily: kMonoFamily),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(dCtx).pop(true),
              child: Text(
                'Delete',
                style: TextStyle(
                  color: colors.error,
                  fontFamily: kMonoFamily,
                ),
              ),
            ),
          ],
        );
      },
    );
    if (ok != true) return;

    final actions = vm.actions;
    if (actions == null) return;
    final conn = vm.conn;
    if (conn.status is! StatusOnline) {
      messenger.showSnackBar(const SnackBar(content: Text('Relay offline — try again later')));
      return;
    }
    final cwd = it.room.cwd;
    if (cwd == null || cwd.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Room has no directory')));
      return;
    }
    final epk = it.peer.remoteEpk;
    final liveRoom = vm.firstLiveRoom(epk);
    if (liveRoom == null) {
      messenger.showSnackBar(const SnackBar(content: Text('Open a room first')));
      return;
    }
    final previousRoom = conn.activeRoomId;
    conn.switchRoom(liveRoom);
    try {
      try {
        await actions.deleteRoom(cwd);
        // Removed on the Pi — drop it locally too so the tile leaves Home
        // immediately instead of waiting for the relay's RoomEnded.
        await vm.deleteRoom(epk, it.room.roomId);
        messenger.showSnackBar(const SnackBar(content: Text('Room deleted')));
      } on ActionFailure catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      conn.switchRoom(previousRoom);
    }
  }

  Future<bool> _confirmCreateDirectory(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dCtx) {
        final colors = dCtx.colors;
        return AlertDialog(
          backgroundColor: colors.bg,
          title: Text(
            'Create directory?',
            style: TextStyle(
              fontFamily: kMonoFamily,
              color: colors.text,
              fontSize: 14,
            ),
          ),
          content: Text(
            'The directory does not exist yet. Create it?',
            style: TextStyle(
              fontFamily: kMonoFamily,
              color: colors.muted,
              fontSize: 12,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dCtx).pop(false),
              child: Text(
                'Cancel',
                style: TextStyle(color: colors.muted, fontFamily: kMonoFamily),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(dCtx).pop(true),
              child: Text(
                'Create',
                style: TextStyle(
                  color: colors.accent,
                  fontFamily: kMonoFamily,
                ),
              ),
            ),
          ],
        );
      },
    );
    return result == true;
  }

  Future<void> _confirmDelete(
    BuildContext context,
    HomeViewModel vm,
    HomeItem it,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dCtx) {
        final colors = dCtx.colors;
        return AlertDialog(
          backgroundColor: colors.bg,
          title: Text('Delete session?', style: TextStyle(color: colors.text)),
          content: Text(
            'Removes locally only. If the session comes back online on '
            'the Pi, it reappears in the list.',
            style: TextStyle(color: colors.muted, fontSize: 12),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dCtx).pop(false),
              child: Text('Cancel', style: TextStyle(color: colors.muted)),
            ),
            TextButton(
              onPressed: () => Navigator.of(dCtx).pop(true),
              child: Text('Delete', style: TextStyle(color: colors.error)),
            ),
          ],
        );
      },
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
    // Plan/32g — the device (Mac) name we already know here. The Chat AppBar's
    // line 2 renders this immediately instead of flickering empty/room-title
    // until the PeerRecord loads async.
    final device = _deviceFor(peer);
    // Plan/32g — the live state of this tile (the green dot). Passed so the
    // Chat AppBar's status dot starts correct instead of flashing
    // "reconnecting" before the runtime is read.
    final online = vm.isRoomLive(peer.remoteEpk, room.roomId);
    // Mark the UI selection — drives the tablet detail pane AND the
    // highlighted tile. Set AFTER openSession so the detail's fresh
    // ChatViewModel reads the already-updated prefs.
    context.read<SessionSelection>().select(
      peer.remoteEpk,
      room.roomId,
      title,
      device,
      online,
    );
    // Phone: full-screen chat (root push → native back/swipe). Tablet:
    // the detail pane reacts to the selection above — no nav needed.
    if (!isWideLayout(context)) {
      context.push(
        '/chat',
        extra: {'title': title, 'device': device, 'online': online},
      );
    }
  }

  /// Plan/32g — the paired-device label for the Chat AppBar's line 2
  /// (nickname → sessionName → epk prefix). Mirrors [ChatPage]'s own peer
  /// resolution so there's no change when the PeerRecord finishes loading.
  static String _deviceFor(PeerRecord peer) =>
      (peer.nickname?.isNotEmpty ?? false)
      ? peer.nickname!
      : peer.sessionName.isNotEmpty
      ? peer.sessionName
      : peer.remoteEpk.substring(0, 8);

  /// Plan/24-fix-title: the peer/room label we already know here, so the
  /// Chat AppBar doesn't show '—' / 'Remote Pi' until the ChatViewModel
  /// loads the PeerRecord + the first room_meta_updated arrives. Prefers
  /// room.name (per-cwd title) → cwd tail → nickname → sessionName.
  static String _titleFor(PeerRecord peer, RoomInfo room) {
    final roomCwdTail = room.cwd
        ?.split('/')
        .where((s) => s.isNotEmpty)
        .lastOrNull;
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
    final colors = context.colors;
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
                Icon(LucideIcons.moon, color: colors.muted, size: 56),
                const SizedBox(height: 18),
                Text(
                  'Nothing here…',
                  style: TextStyle(
                    fontFamily: kMonoFamily,
                    color: colors.muted2,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'When a paired Pi opens a session, it shows up here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: kMonoFamily,
                    color: colors.muted,
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
    final colors = context.colors;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.scanQrCode, color: colors.muted, size: 48),
              const SizedBox(height: 16),
              Text(
                'No pairings yet',
                style: TextStyle(color: colors.muted2, fontSize: 14),
              ),
              const SizedBox(height: 6),
              Text(
                'Scan a QR from your Mac to start.',
                style: TextStyle(color: colors.muted, fontSize: 12),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => context.push('/pair'),
                style: FilledButton.styleFrom(
                  backgroundColor: colors.accent,
                  foregroundColor: colors.onAccent,
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
