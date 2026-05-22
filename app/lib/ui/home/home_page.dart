import 'package:app/data/transport/epk_encoding.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/ui/app_theme.dart';
import 'package:app/ui/home/states/home_state.dart';
import 'package:app/ui/home/viewmodels/home_viewmodel.dart';
import 'package:app/ui/home/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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
          icon: const Icon(Icons.settings_outlined, color: kMuted2),
          onPressed: () => context.push('/settings'),
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

  /// Subtitle line under "Remote Pi": ● Relay · [Connected|Offline].
  /// Reflects the app→relay WS state (not per-Pi presence) so the
  /// user always knows whether the app itself is reachable.
  Widget _subtitleFor(HomeViewModel vm, HomeState state) {
    final connected = vm.isRelayConnected;
    final dotColor = connected ? kSuccess : Colors.amber.shade600;
    final statusLabel = connected ? 'Connected' : 'Offline';
    final statusColor = connected ? kMuted : Colors.amber.shade600;
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
        children.add(_PeerSectionHeader(peer: it.peer));
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SessionTile(
          peer: it.peer,
          isLive: isLive,
          isReconnecting: isReconnecting,
          isWorking: isWorking,
          room: it.room,
          onOpen: () => _open(context, vm, it.peer.remoteEpk, it.room.roomId),
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
                leading: const Icon(Icons.edit_outlined, color: kAccent),
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
                  Icons.delete_outline,
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
      BuildContext context, HomeViewModel vm, String epk, String roomId) async {
    await vm.openSession(epk, roomId: roomId);
    if (!context.mounted) return;
    context.push('/chat');
  }
}

class _PeerSectionHeader extends StatelessWidget {
  final PeerRecord peer;
  const _PeerSectionHeader({required this.peer});

  @override
  Widget build(BuildContext context) {
    final label = (peer.nickname?.isNotEmpty ?? false)
        ? peer.nickname!
        : peer.sessionName.isNotEmpty
            ? peer.sessionName
            : peer.remoteEpk.substring(0, 8);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontFamily: kMono,
          fontSize: 11,
          color: kMuted,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

/// Plan-17 follow-up — soft empty state for paired-but-no-rooms.
class _LonelyEmptyState extends StatelessWidget {
  const _LonelyEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Opacity(
        opacity: 0.35,
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.bedtime_outlined, color: kMuted, size: 56),
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
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.qr_code_scanner, color: kMuted, size: 48),
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
              icon: const Icon(Icons.qr_code_scanner, size: 18),
              label: const Text('Scan QR'),
            ),
          ],
        ),
      ),
    );
  }
}
