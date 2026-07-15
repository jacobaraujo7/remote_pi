import 'dart:async';

import 'package:app/data/local/records/message_record.dart';
import 'package:app/data/local/records/runtime_record.dart';
import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/repositories/session_read_repository.dart';
import 'package:app/data/sync/sync_events.dart';
import 'package:app/data/sync/sync_service.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/domain/session_state.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/ui/chat/states/chat_state.dart';
import 'package:app/ui/core/viewmodel/viewmodel.dart';

/// Plan/31 — ChatViewModel is now a thin composer over the local SSOT.
///
/// It reads messages + runtime from [SessionReadRepository] (the DB), composes
/// the in-memory streaming buffer from [SyncService] (#7), and issues commands
/// (send/cancel/approve) through [SyncService]. Connection lifecycle +
/// presence/rooms queries (AppBar) stay on [ConnectionManager]. It NEVER
/// subscribes to the channel directly — that's the SyncService's job.
class ChatViewModel extends ViewModel<ChatState> {
  final SessionReadRepository _read;
  final SyncService _sync;
  final ConnectionManager _conn;
  final Preferences _prefs;
  final PairingStorage _storage;

  StreamSubscription<List<MessageRecord>>? _msgsSub;
  StreamSubscription<RuntimeRecord>? _runtimeSub;
  StreamSubscription<StreamingMessage?>? _streamingSub;
  StreamSubscription<bool>? _workingSub;
  StreamSubscription<String?>? _queuedSub;
  StreamSubscription<SessionEvent>? _eventSub;
  StreamSubscription<Map<String, List<RoomInfo>>>? _roomsSub;
  StreamSubscription<ConnectionStatus>? _statusSub;

  PeerRecord? _activePeer;
  String _activeRoomId = 'main';
  bool _bootstrapping = true;
  bool _disposed = false;

  List<ChatMessage> _messages = const [];
  StreamingMessage? _streaming;
  bool _working = false;
  String? _queuedText;
  RuntimeRecord _runtime = const RuntimeRecord();
  bool _pairingRevoked = false;
  String? _peerOfflineReason;
  ConnectionStatus? _lastStatus;

  ChatViewModel(this._read, this._sync, this._conn, this._prefs, this._storage)
    : super(const ChatReady(messages: [])) {
    // Plan/32f — do NOT seed _streaming/_working from the shared SyncService
    // here: it may still be bound to the PREVIOUS chat (this VM is recreated
    // on session switch, before _bootstrap rebinds via activate). Seeding now
    // would briefly paint the old chat's streaming bubble / working pill. We
    // seed AFTER activate() in _bootstrap, when the sync owns THIS session.
    _streamingSub = _sync.streamingStream.listen(_onStreaming);
    _workingSub = _sync.workingStream.listen(_onWorking);
    _queuedSub = _sync.queuedStream.listen(_onQueued);
    _eventSub = _sync.events.listen(_onEvent);
    _roomsSub = _conn.roomsStream.listen((_) => _recompute());
    _statusSub = _conn.statusStream.listen(_onStatus);
    // ignore: discarded_futures
    _bootstrap();
  }

  // --- AppBar-facing getters (relay/connection queries, not message data) ---

  PeerRecord? get activePeer => _activePeer;

  RoomInfo? get activeRoom {
    final epk = _activePeer?.remoteEpk;
    if (epk == null) return null;
    for (final r in _conn.roomsFor(epk)) {
      if (r.roomId == _activeRoomId) return r;
    }
    return null;
  }

  bool get isRoomLive {
    final epk = _activePeer?.remoteEpk;
    if (epk == null) return false;
    return _conn.isRoomLive(epk, _activeRoomId);
  }

  /// Whole-turn working signal for the room THIS chat is viewing — the
  /// same mechanism as the Home dot. The relay broadcasts `meta.working`
  /// per-room (turn_start/turn_end), so switching to another chat never
  /// inherits the previous one's working state (previously `_working`
  /// was a single global flag that leaked across sessions).
  ///
  /// OR'd with the local SyncService signals for the CONNECTED session:
  /// `_working` is set optimistically on send (before the relay's
  /// turn_start round-trips) and `_streaming != null` keeps the pill blue
  /// during token flow — both are reset by [SyncService.activate] on a
  /// session switch, so they only ever refer to the current chat.
  bool get isWorking {
    final epk = _activePeer?.remoteEpk;
    final roomWorking = epk != null && _conn.isRoomWorking(epk, _activeRoomId);
    return roomWorking || _working || _streaming != null;
  }

  /// The id to `cancel` to stop the in-flight reply (the user message the
  /// agent is answering). Null when idle. Prefers the live streaming target,
  /// falls back to the SyncService's tracked turn id.
  String? get cancelTargetId => _streaming?.inReplyTo ?? _sync.workingReplyTo;

  String? get queuedText => _queuedText;

  void setQueuedMessage(String text) {
    unawaited(_sync.setQueuedMessage(text));
  }

  void clearQueuedMessage() {
    unawaited(_sync.clearQueuedMessage());
  }

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
    final sessionPeer = peer.copyWith(roomId: roomId);
    _activePeer = sessionPeer;
    _activeRoomId = roomId;

    // Bind transport before the singleton writer. Otherwise a same-peer room
    // switch can briefly accept old-room frames while SyncService already
    // writes to the new room.
    _conn.switchRoom(roomId);
    if (_conn.activePeer?.remoteEpk != sessionPeer.remoteEpk) {
      await _conn.switchTo(sessionPeer);
      if (_disposed) return;
      _conn.switchRoom(roomId);
    }

    // Bind the writer + watch the DB for this (peer, room).
    await _sync.activate(epk, roomId);
    if (_disposed) return;
    // Plan/32f — now that the writer owns THIS session (activate reset the
    // turn state on a switch, or kept it when re-entering the same session),
    // seed the in-memory streaming/working from it. Doing this here instead of
    // the constructor avoids inheriting the previous chat's bubble/pill.
    _streaming = _sync.streaming;
    _working = _sync.isWorking;
    _queuedText = _sync.queuedText;
    _msgsSub = _read.watchMessages(epk, roomId).listen(_onMessages);
    _runtimeSub = _read.watchRuntime(epk, roomId).listen(_onRuntime);

    _bootstrapping = false;
    _sync.requestSync();
    _recompute();
  }

  void _onMessages(List<MessageRecord> rows) {
    _messages = [for (final r in rows) r.toChatMessage()];
    _recompute();
  }

  void _onStreaming(StreamingMessage? s) {
    _streaming = s;
    _recompute();
  }

  void _onWorking(bool working) {
    _working = working;
    _recompute();
  }

  void _onQueued(String? text) {
    _queuedText = text;
    _recompute();
  }

  /// Plan/32g — `true` once a real runtime (connection/presence) has been read
  /// from the box. Until then the AppBar trusts the `initialOnline` hint Home
  /// passed (the tile's live state) so the status dot doesn't flash
  /// "reconnecting" on the default runtime before the first read.
  bool get connectionResolved => _connectionResolved;
  bool _connectionResolved = false;

  void _onRuntime(RuntimeRecord r) {
    _runtime = r;
    _connectionResolved = true;
    _recompute();
  }

  void _onStatus(ConnectionStatus s) {
    final wasOnline = _lastStatus is StatusOnline;
    final nowOnline = s is StatusOnline;
    _lastStatus = s;
    // Auto re-sync on a fresh online edge so the chat catches up.
    if (nowOnline && !wasOnline) {
      // WS retry can snap ConnectionManager to a stale cwd — re-align
      // before SessionSync so history + sends target THIS chat.
      if (_conn.activeRoomId != _activeRoomId) {
        _conn.switchRoom(_activeRoomId);
      }
      _sync.requestSync();
    }
    _recompute();
  }

  void _onEvent(SessionEvent e) {
    if (e is PairingRevoked) {
      _pairingRevoked = true;
    } else if (e is PeerWentOffline) {
      _peerOfflineReason = e.rawReason;
    }
    _recompute();
  }

  void _recompute() {
    if (_disposed) return;
    emit(_compose());
  }

  ChatState _compose() {
    // No "loading"/connecting screen — once a peer is selected we always
    // render ChatReady (empty until the DB/stream delivers rows) and just
    // replace it as updates arrive. The connecting/offline status is shown
    // inline (banner + presence dot via isOffline/peerPresence), never as a
    // full-screen spinner, so entering the chat doesn't flicker.
    if (_activePeer == null) {
      return _bootstrapping
          ? const ChatReady(messages: [])
          : const ChatNoPeer();
    }
    final isOnline = _runtime.connection == RuntimeConnection.online;
    final isOffline = !isOnline;
    final peerPresence = _runtime.presence == RuntimePresence.alive
        ? const PresenceOnline() as PresenceState
        : const PresenceOffline(sinceTs: 0);

    return ChatReady(
      messages: _messages,
      streaming: _streaming,
      isOffline: isOffline,
      pairingRevoked: _pairingRevoked,
      peerOfflineReason: _peerOfflineReason,
      peerPresence: peerPresence,
      isWorking: isWorking,
      queuedText: _queuedText,
    );
  }

  // --- Commands (writer = SyncService; lifecycle = ConnectionManager) ---

  Future<void> sendMessage(String text, {MessageImage? image}) =>
      _sync.sendMessage(
        text,
        image: image,
        streamingBehavior: isWorking
            ? UserMessageStreamingBehavior.steer
            : null,
      );

  Future<void> cancel(String targetId) => _sync.cancel(targetId);

  Future<void> approveTool(String toolCallId, ApproveDecision decision) =>
      _sync.approveTool(toolCallId, decision);

  Future<void> clearActiveSession() async {
    _messages = const [];
    _streaming = null;
    _working = false;
    _queuedText = null;
    _recompute();
    await _sync.clearActiveSession();
  }

  Future<void> reconnect() async {
    final peer = _activePeer;
    if (peer == null) return;
    _peerOfflineReason = null;
    // No connecting spinner — keep the current messages on screen and let the
    // status update inline as the connection comes back.
    _recompute();
    await _conn.switchTo(peer);
  }

  @override
  void dispose() {
    _disposed = true;
    _msgsSub?.cancel();
    _runtimeSub?.cancel();
    _streamingSub?.cancel();
    _workingSub?.cancel();
    _queuedSub?.cancel();
    _eventSub?.cancel();
    _roomsSub?.cancel();
    _statusSub?.cancel();
    super.dispose();
  }
}
