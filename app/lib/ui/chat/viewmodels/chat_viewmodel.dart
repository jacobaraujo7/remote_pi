import 'dart:async';

import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/repositories/i_session_repository.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/domain/session_state.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/ui/chat/states/chat_state.dart';
import 'package:app/ui/core/viewmodel/viewmodel.dart';

/// ChatViewModel — owns the chat connection lifecycle.
///
/// Connection rule (after plano 12): the WS is opened by the
/// ConnectionManager at app boot and stays alive across navigation. Chat
/// observes the existing connection and asks the manager to switch the
/// "active peer" when it mounts. Presence (relay-driven) drives the
/// banner / input state independently of the WS-to-relay status.
class ChatViewModel extends ViewModel<ChatState> {
  final ISessionRepository _repo;
  final Preferences _prefs;
  final PairingStorage _storage;
  StreamSubscription? _sub;
  StreamSubscription? _eventSub;
  // Plan-17 follow-up — presence per-peer was replaced by "is this
  // specific room currently live?". Subscribed to roomsStream below.
  StreamSubscription<Map<String, List<RoomInfo>>>? _roomsSub;
  bool _pairingRevoked = false;
  String? _peerOfflineReason;
  PeerRecord? _activePeer;
  String _activeRoomId = 'main';
  bool _roomLive = false;
  bool _bootstrapping = true;
  bool _disposed = false;
  /// Plan/24-fix-session-sync: tracks whether we've asked the Pi for
  /// session_history during the current StatusOnline window. We reset
  /// it whenever the channel drops so a fresh reconnect always
  /// re-syncs. Belt-and-suspenders for the case where `_bootstrap`'s
  /// own requestSync raced the channel coming up — `_onSession` will
  /// fire one as soon as it sees StatusOnline for the first time.
  bool _didRequestSync = false;
  ConnectionStatus? _lastSeenConnection;

  /// Active room metadata (name, cwd, etc) for the AppBar title.
  /// Refreshed on every rooms snapshot. `null` until first snapshot.
  RoomInfo? get activeRoom {
    final epk = _activePeer?.remoteEpk;
    if (epk == null) return null;
    final list = _repo.roomsFor(epk);
    for (final r in list) {
      if (r.roomId == _activeRoomId) return r;
    }
    return null;
  }

  /// Currently-bound peer, exposed for the AppBar.
  PeerRecord? get activePeer => _activePeer;

  /// Whether the active room is announced LIVE on the relay.
  bool get isRoomLive => _roomLive;

  /// Plan-18 follow-up — `true` when the agent is mid-response
  /// (state.streaming != null). Drives the "working…" pill in the
  /// chat AppBar.
  bool get isWorking {
    final s = state;
    return s is ChatReady && s.streaming != null;
  }

  ChatViewModel(this._repo, this._prefs, this._storage)
    : super(const ChatConnecting()) {
    // Seed _activeRoomId from prefs synchronously so the very first
    // _onSession (seeded below) and _onRooms emissions can already
    // evaluate isRoomLive against the room the user actually picked,
    // not the default 'main'. _activePeer follows in _bootstrap once
    // we've loaded the PeerRecord from storage.
    final seedRoomId = _prefs.selectedRoomId;
    if (seedRoomId != null && seedRoomId.isNotEmpty) {
      _activeRoomId = seedRoomId;
    }
    _sub = _repo.sessionStream.listen(_onSession);
    _eventSub = _repo.eventStream.listen(_onEvent);
    _roomsSub = _repo.roomsStream.listen(_onRooms);
    // Seed the chat surface from the repo's CURRENT state before
    // `_bootstrap` runs. `SessionRepository` is instantiated lazily
    // by the injector — typically when /home builds its
    // HomeViewModel, which is well before /chat opens. By the time
    // ChatViewModel is constructed the repo's `_state.connection` is
    // often already `StatusOnline`, but the broadcast emit happened
    // before this listener was attached, so the listener would never
    // see it. Reading `_repo.current` synchronously here closes that
    // gap — the user no longer sees a "Connecting…" splash on /chat
    // entry while the WS is in fact alive.
    _onSession(_repo.current);
    // ignore: unawaited_futures
    _bootstrap();
  }

  /// Recompute the room-live flag from the live `ConnectionManager`
  /// state. Called from every `_onSession` so a status transition
  /// (Connecting → Online) flips presence even when no `roomsStream`
  /// event accompanied it. Without this, the cached `_roomLive=false`
  /// from the initial seed survives the transition and the chat keeps
  /// rendering "offline" until the next `room_announced` from the Pi
  /// (which only happens spontaneously when the Pi reacts to a
  /// terminal command — exactly the symptom the user reported).
  void _refreshRoomLive() {
    final epk = _activePeer?.remoteEpk ?? _prefs.selectedPeerEpk;
    if (epk == null) return;
    _roomLive = _repo.isRoomLive(epk, _activeRoomId);
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  Future<void> _bootstrap() async {
    final epk = _prefs.selectedPeerEpk;
    final roomId = _prefs.selectedRoomId ?? 'main';
    if (epk == null) {
      _bootstrapping = false;
      emit(const ChatNoPeer());
      return;
    }
    final peer = await _storage.loadPeer(epk);
    if (_disposed) return;
    if (peer == null) {
      _bootstrapping = false;
      emit(const ChatNoPeer());
      return;
    }
    _activePeer = peer;
    _activeRoomId = roomId;
    _roomLive = _repo.isRoomLive(peer.remoteEpk, roomId);
    // Plan 17 — make sure the destination room id is propagated to
    // ConnectionManager / WS transport on cold start (Home's
    // openSession already does this when the user taps a tile; this
    // handles the case where the app re-launches directly into /chat).
    // Tell the connection layer which room to address on the Pi side.
    _repo.switchRoom(roomId);
    // setActivePeer below loads the (peer, room) partitioned cache.

    // Always load the per-peer history cache (plano 11) so the chat
    // surface has content even if the WS hasn't authenticated yet.
    await _repo.setActivePeer(peer, roomId: roomId);
    if (_disposed) return;

    // Plano 13 fast path: if the connection layer already settled on
    // this exact peer (boot opened it OR Home triggered switchTo before
    // navigating), don't ask for another openSession — that would just
    // be a no-op AND skip the event chain we'd otherwise rely on. Seed
    // the chat state synchronously from `_repo.current` and we're done.
    final cur = _repo.activePeer;
    final alreadyDriving = cur?.remoteEpk == peer.remoteEpk;
    if (!alreadyDriving) {
      await _repo.openSession(peer);
      if (_disposed) return;
    } else {
    }

    // Seed from the repo's current snapshot so the view leaves
    // `ChatConnecting` immediately — even when `openSession` was a
    // no-op (no stream events to wait for).
    _onSession(_repo.current);

    // Plano 11 normally fires session_sync from `_onlineActivated` on
    // a StatusOnline transition. With no transition (fast-path or
    // idempotent openSession), there is none — kick a one-shot sync.
    _repo.requestSync();
  }

  // ---------------------------------------------------------------------------
  // Actions — called from UI
  // ---------------------------------------------------------------------------

  Future<void> sendMessage(String text) {
    return _repo.sendMessage(text);
  }

  Future<void> cancel(String targetId) => _repo.cancel(targetId);

  Future<void> approveTool(String toolCallId, ApproveDecision decision) =>
      _repo.approveTool(toolCallId, decision);

  /// Plan/28 — invoked by the Quick Actions sheet once the Pi acks a
  /// `session_new`. Clears the local mirror so the chat reflects the
  /// fresh session without waiting for a round-trip. The cleared state
  /// flows back through `_repo.sessionStream` → `_onSession`, so the UI
  /// updates the same way any other state change does.
  Future<void> clearActiveSession() => _repo.clearActiveSession();

  /// Called from the offline (bye) banner. Clears the sticky `bye` flag
  /// and asks the repo to open the session again.
  Future<void> reconnect() async {
    final peer = _activePeer;
    if (peer == null) return;
    _peerOfflineReason = null;
    _bootstrapping = true;
    emit(const ChatConnecting());
    await _repo.openSession(peer);
  }

  // ---------------------------------------------------------------------------
  // Session → ChatState translation
  // ---------------------------------------------------------------------------

  void _onSession(SessionState s) {
    // Plan/24-fix-session-sync (follow-up): the SessionRepository's
    // own `_onlineActivated` debounce sometimes never reaches us —
    // the bootstrap race put `_activeEpk=null` at the moment of the
    // first StatusOnline emit (it gets set later by setActivePeer),
    // so `_onlineActivated` early-returned (`if (peer == null)`).
    // Belt-and-suspenders: every time the chat viewmodel observes a
    // Connecting/whatever → StatusOnline edge, ask for a sync
    // ourselves. `_didRequestSync` keeps it one-per-online-window;
    // a channel drop resets the flag so reconnects also re-sync.
    final prevConn = _lastSeenConnection;
    final isOnlineNow = s.connection is StatusOnline;
    final wasOnline = prevConn is StatusOnline;
    if (isOnlineNow && !wasOnline) {
      _didRequestSync = false; // fresh online window
    }
    if (!isOnlineNow && wasOnline) {
      _didRequestSync = false; // dropped — next online retriggers
    }
    if (isOnlineNow && !_didRequestSync) {
      _didRequestSync = true;
      _repo.requestSync();
    }
    _lastSeenConnection = s.connection;

    final cur = state;
    final wasStreaming =
        cur is ChatReady && cur.streaming != null;
    final isStreaming = s.streaming != null;
    if (wasStreaming != isStreaming) {
    }
    if (_bootstrapping && s.connection is! StatusNoPeer) {
      _bootstrapping = false;
    }
    // Re-check _roomLive against the connection manager's live view
    // every time we re-render. A Connecting→Online transition arrives
    // here via the session stream, but `isRoomLive` only flips its
    // own answer once status is Online — so the stale `_roomLive=false`
    // captured during bootstrap would otherwise survive the
    // transition and keep the chat "offline" until the next
    // room_announced. See `_refreshRoomLive` for the full rationale.
    _refreshRoomLive();
    final next = _toChat(
      s,
      _pairingRevoked,
      _peerOfflineReason,
      _roomLive,
      _bootstrapping,
    );
    emit(next);
  }

  void _onEvent(SessionEvent e) {
    if (e is PairingRevoked) {
      _pairingRevoked = true;
      emit(_toChat(
        _repo.current,
        true,
        _peerOfflineReason,
        _roomLive,
        _bootstrapping,
      ));
    } else if (e is PeerWentOffline) {
      _peerOfflineReason = e.rawReason;
      emit(_toChat(
        _repo.current,
        _pairingRevoked,
        e.rawReason,
        _roomLive,
        _bootstrapping,
      ));
    }
  }

  /// Plan-17 follow-up — replaces the old per-peer presence handler.
  /// Tracks whether the ACTIVE ROOM is live on the relay; flips
  /// online/offline at the room granularity (matches what the user
  /// sees per cwd-session on Home).
  void _onRooms(Map<String, List<RoomInfo>> _) {
    final epk = _activePeer?.remoteEpk;
    if (epk == null) return;
    final next = _repo.isRoomLive(epk, _activeRoomId);
    if (next == _roomLive) return;
    final wasLive = _roomLive;
    _roomLive = next;

    // Auto-recovery: room just came back online — clear the sticky
    // banner from a previous Bye and ask Pi for the latest history.
    if (next && !wasLive) {
      if (_peerOfflineReason != null) {
        _peerOfflineReason = null;
      }
      _repo.requestSync();
    }

    emit(_toChat(
      _repo.current,
      _pairingRevoked,
      _peerOfflineReason,
      _roomLive,
      _bootstrapping,
    ));
  }

  static ChatState _toChat(
    SessionState s,
    bool revoked,
    String? offlineReason,
    bool isRoomLive,
    bool bootstrapping,
  ) {
    // Plan-17 follow-up — translate the new bool flag back to the
    // existing PresenceState enum (PresenceOnline | PresenceOffline)
    // so the ChatReady contract stays stable.
    final peerPresence = isRoomLive
        ? const PresenceOnline() as PresenceState
        : const PresenceOffline(sinceTs: 0);
    final conn = s.connection;

    // Fingerprint mismatch / non-recoverable offline — short-circuit
    // before any content-based fallback so the user sees the re-pair
    // affordance even if there's stale cache lying around.
    if (conn is StatusOffline && !conn.canRetry) {
      return ChatFatalError(conn.reason);
    }

    // Content-first: if we have history (cached or live) OR are mid-
    // stream, always render the chat surface. The connection state only
    // drives the AppBar status line + input disable, never blocks the
    // history from being visible.
    final hasContent = s.messages.isNotEmpty || s.streaming != null;
    if (hasContent) {
      return ChatReady(
        messages: s.messages,
        streaming: s.streaming,
        isOffline: conn is! StatusOnline,
        pairingRevoked: revoked,
        peerOfflineReason: offlineReason,
        peerPresence: peerPresence,
      );
    }

    // No content yet — surface the lifecycle state as before.
    return switch (conn) {
      StatusNoPeer() when bootstrapping => const ChatConnecting(),
      StatusNoPeer() when offlineReason != null => ChatReady(
        messages: const [],
        pairingRevoked: revoked,
        peerOfflineReason: offlineReason,
        peerPresence: peerPresence,
      ),
      StatusNoPeer() => const ChatNoPeer(),
      StatusConnecting() => const ChatConnecting(),
      StatusOnline() => ChatReady(
        messages: const [],
        pairingRevoked: revoked,
        peerOfflineReason: offlineReason,
        peerPresence: peerPresence,
      ),
      StatusRetrying() => ChatReady(
        messages: const [],
        isOffline: true,
        pairingRevoked: revoked,
        peerOfflineReason: offlineReason,
        peerPresence: peerPresence,
      ),
      // Recoverable offline — show the chat surface with the
      // reconnecting banner instead of swallowing into ChatConnecting.
      StatusOffline() => ChatReady(
        messages: const [],
        isOffline: true,
        pairingRevoked: revoked,
        peerOfflineReason: offlineReason,
        peerPresence: peerPresence,
      ),
    };
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _eventSub?.cancel();
    _roomsSub?.cancel();
    // Connection persists from boot (plano 12). Chat is passive.
    super.dispose();
  }
}
