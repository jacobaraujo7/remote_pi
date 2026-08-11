import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:flutter/foundation.dart' show listEquals, mapEquals;

sealed class HomeState {
  const HomeState();
}

/// Plan-38 Fase 3 — which presence slice of the Home list is shown.
/// Pure view filter over the existing (peer → room) list; the tabs never
/// reload or regroup data. Default is [online] (see [HomeList.filter]).
///
///   - [all]     — every known session (live + cached/offline).
///   - [online]  — only sessions live on the relay right now.
///   - [offline] — only cached sessions that aren't live.
enum HomeFilter { all, online, offline }

class HomeLoading extends HomeState {
  const HomeLoading();
}

class HomeNoPeer extends HomeState {
  const HomeNoPeer();
}

/// Plan 17 — single row on Home: a Pi room (per-cwd session) bound to
/// a paired Mac. Multiple HomeItems per peer when the Mac runs more
/// than one Pi session. When `roomId == 'main'` (the only room from a
/// legacy/single-cwd Pi), the UI may collapse the cwd subtitle.
class HomeItem {
  final PeerRecord peer;
  final RoomInfo room;

  const HomeItem({required this.peer, required this.room});

  /// Display name preference: mobile alias → Pi `/name` → mesh agent name →
  /// cwd basename → peer nickname → pairing fallback.
  String get displayName {
    final preferred = room.preferredDisplayName;
    if (preferred != null) return preferred;
    final cwd = room.cwd;
    if (cwd != null && cwd.isNotEmpty) {
      final last = cwd.split('/').where((s) => s.isNotEmpty).toList();
      if (last.isNotEmpty) return last.last;
    }
    if (peer.nickname != null && peer.nickname!.isNotEmpty) {
      return peer.nickname!;
    }
    return peer.sessionName;
  }

  @override
  bool operator ==(Object other) =>
      other is HomeItem &&
      other.peer.remoteEpk == peer.remoteEpk &&
      other.room == room;

  @override
  int get hashCode => Object.hash(peer.remoteEpk, room);
}

/// Paired peers + their live rooms + presence. Items are derived from
/// `roomsByPeer`: a peer with no announced rooms yet still gets one
/// synthetic item (`roomId='main'`) so the user can enter chat — that
/// covers legacy Pis and the pre-room-announce window after reconnect.
class HomeList extends HomeState {
  final List<PeerRecord> peers;
  final Map<String, PresenceState> statusByEpk;
  final Map<String, List<RoomInfo>> roomsByPeer;

  /// Plan-38 Fase 3 — the selected presence tab. Part of the immutable
  /// state (per the `ViewModel<T>` pattern) so the choice is reactive and
  /// survives presence/rooms/status re-emits. Default [HomeFilter.online].
  final HomeFilter filter;

  const HomeList({
    required this.peers,
    this.statusByEpk = const {},
    this.roomsByPeer = const {},
    this.filter = HomeFilter.online,
  });

  HomeList copyWith({
    List<PeerRecord>? peers,
    Map<String, PresenceState>? statusByEpk,
    Map<String, List<RoomInfo>>? roomsByPeer,
    HomeFilter? filter,
  }) => HomeList(
    peers: peers ?? this.peers,
    statusByEpk: statusByEpk ?? this.statusByEpk,
    roomsByPeer: roomsByPeer ?? this.roomsByPeer,
    filter: filter ?? this.filter,
  );

  /// Flatten to a single ordered list of items: one row per (peer, room).
  /// **Plan-17 follow-up**: peers without any currently-announced rooms
  /// produce ZERO items. Earlier behaviour created a synthetic 'main'
  /// tile for legacy compatibility, but that tile pointed at a (peer,
  /// 'main') destination the Pi was no longer listening on — sending
  /// there got dropped by the relay AND the row felt like a ghost. The
  /// user only wants live rooms in the list.
  ///
  /// Ordering: peers are sorted by display name (nickname → sessionName
  /// → epk prefix), case-insensitive. Within each peer, rooms are
  /// sorted by their display name (room.name → cwd basename → roomId),
  /// also case-insensitive. Keeps the list stable and predictable as
  /// the relay reorders its push payloads.
  List<HomeItem> items({String Function(String)? normalizeEpk}) {
    final sortedPeers = [...peers]
      ..sort(
        (a, b) =>
            _peerLabel(a).toLowerCase().compareTo(_peerLabel(b).toLowerCase()),
      );
    final out = <HomeItem>[];
    for (final p in sortedPeers) {
      final key = normalizeEpk != null
          ? normalizeEpk(p.remoteEpk)
          : p.remoteEpk;
      final rooms = roomsByPeer[key];
      if (rooms == null || rooms.isEmpty) continue;
      final sortedRooms = [...rooms]
        ..sort(
          (a, b) => _roomLabel(
            a,
          ).toLowerCase().compareTo(_roomLabel(b).toLowerCase()),
        );
      for (final r in sortedRooms) {
        out.add(HomeItem(peer: p, room: r));
      }
    }
    return out;
  }

  static String _peerLabel(PeerRecord p) {
    if (p.nickname != null && p.nickname!.isNotEmpty) return p.nickname!;
    if (p.sessionName.isNotEmpty) return p.sessionName;
    return p.remoteEpk;
  }

  static String _roomLabel(RoomInfo r) {
    final preferred = r.preferredDisplayName;
    if (preferred != null) return preferred;
    final cwd = r.cwd;
    if (cwd != null && cwd.isNotEmpty) {
      final segs = cwd.split('/').where((s) => s.isNotEmpty).toList();
      if (segs.isNotEmpty) return segs.last;
    }
    return r.roomId;
  }

  @override
  bool operator ==(Object other) =>
      other is HomeList &&
      other.filter == filter &&
      listEquals(other.peers, peers) &&
      mapEquals(other.statusByEpk, statusByEpk) &&
      mapEquals(other.roomsByPeer, roomsByPeer);

  @override
  int get hashCode => Object.hash(
    filter,
    Object.hashAll(peers),
    Object.hashAllUnordered(
      statusByEpk.entries.map((e) => '${e.key}:${e.value.runtimeType}'),
    ),
    Object.hashAllUnordered(
      roomsByPeer.entries.map((e) => '${e.key}:${e.value.length}'),
    ),
  );
}
