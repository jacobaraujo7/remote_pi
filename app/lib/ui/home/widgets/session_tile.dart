import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/ui/app_theme.dart';
import 'package:flutter/material.dart';

/// A row in the Home list.
///
/// Renders an inline presence dot (plano 12) driven by
/// [ConnectionManager.presenceStream]: green = online, grey = offline,
/// no dot = relay hasn't reported yet.
class SessionTile extends StatelessWidget {
  final PeerRecord peer;
  /// `true` when the room is announced live on the relay AND the
  /// relay itself is reachable. Drives the green dot.
  final bool isLive;
  /// `true` when the WS to the relay is currently retrying / down.
  /// Overrides `isLive` and renders an amber "reconnecting" dot —
  /// the app has no fresh signal on any room right now.
  final bool isReconnecting;
  /// Plan-18 follow-up — `true` when the agent in this room is
  /// currently producing a response. Highest-priority colour (blue).
  final bool isWorking;
  final RoomInfo? room;
  final VoidCallback onOpen;
  /// Plan/tablet — `true` when this is the session shown in the tablet's
  /// detail pane. Paints the accent left-bar + faint fill from the mock.
  /// Always `false` on phone (no persistent selection there).
  final bool isSelected;
  /// Plan-17 follow-up — long-press context menu. Caller wires the
  /// dialog (rename + delete-offline). Optional; when null the tile
  /// only responds to tap.
  final VoidCallback? onLongPress;

  const SessionTile({
    super.key,
    required this.peer,
    required this.isLive,
    required this.onOpen,
    this.room,
    this.isReconnecting = false,
    this.isWorking = false,
    this.isSelected = false,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kBg,
      child: InkWell(
        onTap: onOpen,
        onLongPress: onLongPress,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isSelected ? kAccent.withValues(alpha: 0.06) : kBg,
            border: Border(
              left: BorderSide(
                color: isSelected ? kAccent : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Padding(
            // Trim the left inset by the 3px accent bar so content stays
            // aligned whether selected or not.
            padding: EdgeInsets.fromLTRB(isSelected ? 15 : 18, 14, 18, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _Avatar(name: _avatarName()),
                const SizedBox(width: 14),
                Expanded(
                  child: _TitleBlock(peer: peer, room: room),
                ),
                _PresenceDot(
                  isLive: isLive,
                  isReconnecting: isReconnecting,
                  isWorking: isWorking,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _avatarName() {
    final r = room;
    if (r != null) {
      if (r.name != null && r.name!.isNotEmpty) return r.name!;
      final cwd = r.cwd;
      if (cwd != null && cwd.isNotEmpty) {
        final segs = cwd.split('/').where((s) => s.isNotEmpty).toList();
        if (segs.isNotEmpty) return segs.last;
      }
    }
    if (peer.nickname?.isNotEmpty == true) return peer.nickname!;
    return peer.sessionName;
  }
}

class _PresenceDot extends StatelessWidget {
  final bool isLive;
  final bool isReconnecting;
  final bool isWorking;
  const _PresenceDot({
    required this.isLive,
    required this.isReconnecting,
    this.isWorking = false,
  });

  @override
  Widget build(BuildContext context) {
    // Plan-18 follow-up — 4-state dot. Priority high → low:
    //   working (agent streaming)   → blue
    //   reconnecting (relay down)   → amber
    //   live (relay up + announced) → green
    //   else (cached / offline)     → grey
    const kWorking = Color(0xFF3FA9F5);
    final Color color = isWorking
        ? kWorking
        : isReconnecting
            ? Colors.amber.shade600
            : isLive
                ? kSuccess
                : kMuted;
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

class _TitleBlock extends StatelessWidget {
  final PeerRecord peer;
  final RoomInfo? room;
  const _TitleBlock({required this.peer, required this.room});

  @override
  Widget build(BuildContext context) {
    final r = room;
    // Title preference: explicit room.name → cwd basename → peer
    // nickname → session name. The cwd path line was dropped on purpose
    // — the tile now shows just title + subtitle (model / paired date).
    final String title;
    if (r != null) {
      if (r.name != null && r.name!.isNotEmpty) {
        title = r.name!;
      } else if (r.cwd != null && r.cwd!.isNotEmpty) {
        final segs = r.cwd!.split('/').where((s) => s.isNotEmpty).toList();
        title = segs.isNotEmpty ? segs.last : r.cwd!;
      } else if (peer.nickname?.isNotEmpty == true) {
        title = peer.nickname!;
      } else {
        title = peer.sessionName;
      }
    } else {
      title =
          peer.nickname?.isNotEmpty == true ? peer.nickname! : peer.sessionName;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: kText,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 3),
        // Subtitle = the Pi-extension's model (when surfaced via
        // `room_announced` / `room_meta_updated`), else the legacy
        // "Last paired" timestamp so the row keeps a stable height.
        Builder(builder: (_) {
          final model = room?.model;
          final hasModel = model != null && model.isNotEmpty;
          return Text(
            hasModel
                ? _truncateModel(model)
                : 'Last paired: ${_relativeTime(peer.pairedAt)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: hasModel ? kAccent : kMuted,
              fontSize: 12,
              fontFamily: kMono,
            ),
          );
        }),
      ],
    );
  }
}

String _truncateModel(String name) =>
    name.length <= 24 ? name : '${name.substring(0, 21)}…';

class _Avatar extends StatelessWidget {
  final String name;
  const _Avatar({required this.name});

  @override
  Widget build(BuildContext context) {
    final initial = _initial(name);
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: kSurface,
        border: Border.all(color: kBorder),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          color: kAccent,
          fontFamily: kMono,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

String _initial(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '?';
  return trimmed.characters.first.toUpperCase();
}

String _relativeTime(String isoUtc) {
  final parsed = DateTime.tryParse(isoUtc);
  if (parsed == null) return isoUtc;
  final now = DateTime.now().toUtc();
  final diff = now.difference(parsed);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 30) return '${diff.inDays}d ago';
  return isoUtc.substring(0, 10);
}
