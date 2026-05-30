import 'package:app/data/transport/channel.dart';
import 'package:app/domain/contracts/repository.dart';
import 'package:app/domain/session_state.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';

/// Out-of-band signals that don't fit the conversational SessionState but
/// drive UI affordances (banners, redirects).
sealed class SessionEvent {
  const SessionEvent();
}

/// The Mac has dropped this device from its `peers.json` — the chat is
/// effectively dead and the user must re-pair.
class PairingRevoked extends SessionEvent {
  const PairingRevoked();
}

/// The Pi sent a `bye` and closed the channel gracefully. The retry loop
/// is stopped; the user must reconnect manually. `rawReason` is the wire
/// value (e.g. `peer_stop`, `session_replaced`, `shutdown`).
class PeerWentOffline extends SessionEvent {
  final String rawReason;
  const PeerWentOffline(this.rawReason);
}

/// Abstract session repository — injectable for tests.
abstract class ISessionRepository extends Repository {
  SessionState get current;
  Stream<SessionState> get sessionStream;

  /// One-shot signals (revoke detected, etc) for the UI to react to.
  Stream<SessionEvent> get eventStream;

  Future<void> boot();
  Future<void> connectTo(PeerRecord peer);
  Future<void> sendMessage(String text);
  Future<void> cancel(String targetId);
  Future<void> approveTool(String toolCallId, ApproveDecision decision);

  /// Plan/28 — a `session_new` was acknowledged by the Pi. Drop the local
  /// mirror of the active (peer, room) so the chat reflects the fresh
  /// session immediately, and hard-wipe its Hive cache so a cold restart
  /// doesn't resurrect the old thread. Note: this only resets THIS device's
  /// view — until the Pi clears its own event buffer, a later `session_sync`
  /// can still backfill the stale history (see the repo impl note).
  Future<void> clearActiveSession();
  @override
  void dispose();

  /// Transfer a live channel established by the pairing flow so the
  /// ConnectionManager can adopt it without going through the factory again.
  void adoptChannel(IChannel channel, PeerRecord peer);

  /// Close the active connection (if any). Used before re-pairing so the
  /// new pairing handshake does not collide in the relay's peer registry.
  Future<void> disconnect();

  /// Tell the repo which peer is now driving the session — loads its local
  /// history cache and emits it immediately. Called automatically when the
  /// underlying [ConnectionManager] transitions to `StatusOnline` with a new
  /// peer, but also exposed for tests.
  ///
  /// Plan 17 — [roomId] selects which (peer, room) partition of the
  /// Hive cache to load. Omit (or pass null) to default to 'main',
  /// which matches single-cwd Pis and the pre-plan-17 layout.
  Future<void> setActivePeer(PeerRecord peer, {String? roomId});

  /// Send a `session_sync` over the active channel asking the Pi to
  /// backfill anything newer than the locally-cached high-water mark.
  /// No-op when offline / no active peer.
  void requestSync();

  /// Idempotent: if already online to [peer], no-op; otherwise disconnects
  /// the current peer (if any) and connects to this one. Used by
  /// [ChatViewModel] on mount so the connection lifecycle follows the
  /// chat screen, not the home tap.
  Future<void> openSession(PeerRecord peer);

  /// Per-peer presence snapshot stream (forwarded from ConnectionManager).
  Stream<Map<String, PresenceState>> get presenceStream;

  /// Current presence for [epk] (defaults to [PresenceUnknown]).
  PresenceState presenceFor(String epk);

  /// Peer currently being driven by the connection layer, or null. Used
  /// by `ChatViewModel._bootstrap` to fast-path when the WS already
  /// matches the requested peer (plano 13).
  PeerRecord? get activePeer;

  /// Plan 17 — change the destination room (Pi-side cwd session)
  /// without renegotiating the WS. Forwards to ConnectionManager.
  void switchRoom(String roomId);

  /// Plan-17 follow-up — stream of per-peer room lists (cached ∪ live).
  /// Same shape as ConnectionManager.roomsStream.
  Stream<Map<String, List<RoomInfo>>> get roomsStream;

  /// Snapshot of currently-known rooms for [epk] (live + cached).
  List<RoomInfo> roomsFor(String epk);

  /// `true` if [roomId] for [epk] is currently LIVE (announced in the
  /// last relay snapshot). Drives the chat AppBar online dot.
  bool isRoomLive(String epk, String roomId);

  /// Plan-18 follow-up — `(epk, roomId)` of the room whose agent is
  /// currently streaming a response (state.streaming != null). Null
  /// when no stream is active. Limited to the room the connection
  /// is currently addressing (`ConnectionManager.activeRoomId`),
  /// because room-demux drops AgentChunks for non-active rooms.
  String? get workingEpk;
  String? get workingRoomId;

  /// Emits whenever the working room changes (start/stop streaming
  /// or active room switch).
  Stream<({String? epk, String? roomId})> get workingStream;
}
