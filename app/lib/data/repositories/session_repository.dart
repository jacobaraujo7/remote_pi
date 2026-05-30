// SessionRepository — orchestrates ConnectionManager + PeerChannel.
//
// Exposes a Stream<SessionState> that combines:
//   • connection status changes
//   • incoming ServerMessages (agent chunks, tool requests, etc.)
//
// Provides action methods (sendMessage, cancel, approveTool) that the
// ChatViewModel calls. Also owns the per-peer chat history cache and the
// `session_sync` lifecycle (see plan/11-session-sync.md).

import 'dart:async';

import 'package:app/data/repositories/i_session_repository.dart';
import 'package:app/data/repositories/session_history_store.dart';
import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/domain/contracts/repository.dart';
import 'package:app/domain/session_state.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/protocol/uuid7.dart';
import 'package:flutter/foundation.dart';

class SessionRepository extends Repository implements ISessionRepository {
  final ConnectionManager _conn;
  final SessionHistoryStore _store;

  final _stateController = StreamController<SessionState>.broadcast();
  final _eventController = StreamController<SessionEvent>.broadcast();
  SessionState _state = const SessionState();

  StreamSubscription? _connSub;
  StreamSubscription? _msgSub;

  // 16ms streaming buffer — coalesces AgentChunk deltas per video frame (Q2).
  final StringBuffer _chunkBuffer = StringBuffer();
  String _chunkReplyTo = '';
  Timer? _flushTimer;

  // Cache + sync bookkeeping per active (peer, room). The cache is
  // partitioned by both since plan 17 (multi-cwd per Mac).
  String? _activeEpk;
  String _activeRoomId = kDefaultRoomId;
  int? _lastSyncedTs;
  int? _lastSessionStartedAt;
  Timer? _syncDebounce;

  /// Plan/24-fix-app-source-of-truth: outstanding `UserMessage`s
  /// awaiting the Pi-side rebroadcast. Keyed by message id. The
  /// timer fires after [_echoTimeout] and marks the matching UserMsg
  /// as `failed` so the user can retry. The timer is cancelled
  /// either by the Pi's echo arriving via [_onServerMessage] or by
  /// the channel falling offline.
  final Map<String, Timer> _pendingEchoTimers = {};
  final Duration _echoTimeout;

  /// Plan/24-fix-session-sync: set when [requestSync] is invoked but
  /// the channel / active peer are not yet ready (early-return path).
  /// The next StatusOnline → [_onlineActivated] transition checks this
  /// and fires the deferred sync. Without it, the chat opens with
  /// stale cache and never asks the Pi for the latest history (Bug 1).
  bool _pendingSyncRequest = false;

  SessionRepository(
    this._conn,
    this._store, {
    Duration echoTimeout = const Duration(seconds: 15),
  }) : _echoTimeout = echoTimeout {
    _connSub = _conn.statusStream.listen(_onStatusChange);
    // The status stream is a plain broadcast (no replay). If the
    // ConnectionManager already emitted `StatusOnline` BEFORE this repo
    // was constructed (e.g. boot-time WS opens before the user enters
    // `/chat` — `SessionRepository` is lazy-constructed via injector),
    // the listener above would miss it and `_state.connection` would
    // stay at the initial `StatusNoPeer`. ChatViewModel would then sit
    // on `ChatConnecting` forever (`_bootstrapping=true + NoPeer`).
    //
    // Replay-via-seed: invoke the handler synchronously with the
    // manager's current status so the repo picks up where things are.
    _onStatusChange(_conn.status);
  }

  @override
  SessionState get current => _state;
  @override
  Stream<SessionState> get sessionStream => _stateController.stream;
  @override
  Stream<SessionEvent> get eventStream => _eventController.stream;

  @override
  Future<void> boot() => _conn.boot();

  @override
  Future<void> connectTo(PeerRecord peer) => _conn.connectTo(peer);

  @override
  Future<void> openSession(PeerRecord peer) => _conn.switchTo(peer);

  @override
  Stream<Map<String, PresenceState>> get presenceStream =>
      _conn.presenceStream;

  @override
  PresenceState presenceFor(String epk) => _conn.presenceFor(epk);

  @override
  PeerRecord? get activePeer => _conn.activePeer;

  @override
  Stream<Map<String, List<RoomInfo>>> get roomsStream => _conn.roomsStream;

  @override
  List<RoomInfo> roomsFor(String epk) => _conn.roomsFor(epk);

  @override
  bool isRoomLive(String epk, String roomId) =>
      _conn.isRoomLive(epk, roomId);

  // --- Plan-18 follow-up: per-active-room "working" signal ---

  final _workingController =
      StreamController<({String? epk, String? roomId})>.broadcast();
  bool _lastWorkingFlag = false;

  @override
  String? get workingEpk =>
      _state.streaming != null ? _activeEpk : null;
  @override
  String? get workingRoomId =>
      _state.streaming != null ? _activeRoomId : null;
  @override
  Stream<({String? epk, String? roomId})> get workingStream =>
      _workingController.stream;

  void _maybeEmitWorking() {
    final on = _state.streaming != null && _activeEpk != null;
    if (on == _lastWorkingFlag) return;
    _lastWorkingFlag = on;
    if (_workingController.isClosed) return;
    _workingController.add((
      epk: on ? _activeEpk : null,
      roomId: on ? _activeRoomId : null,
    ));
  }

  @override
  void switchRoom(String roomId) {
    final effective = roomId.isEmpty ? kDefaultRoomId : roomId;
    _conn.switchRoom(effective);
    // Plan 17 — when the user crosses rooms (e.g. taps a different
    // cwd on Home), the cache lives in a different partitioned box.
    // Hot-swap state.messages from the new room's cache so the chat
    // re-renders without a Pi round-trip. session_sync will refresh
    // shortly via the normal mirror flow.
    if (effective == _activeRoomId) return;
    final epk = _activeEpk;
    if (epk == null) return;
    // ignore: unawaited_futures
    _hotSwapRoomCache(epk, effective);
  }

  Future<void> _hotSwapRoomCache(String epk, String roomId) async {
    final cached = await _store.loadFor(epk, roomId: roomId);
    _activeRoomId = roomId;
    _lastSyncedTs = cached.lastTs;
    _lastSessionStartedAt = cached.sessionStartedAt;
    _emit(_state.copyWith(
      messages: cached.messages,
      clearStreaming: true,
    ));
  }

  @override
  void adoptChannel(IChannel channel, PeerRecord peer) =>
      _conn.adopt(channel, peer);

  @override
  Future<void> disconnect() => _conn.disconnect();

  // ---------------------------------------------------------------------------
  // Cache + sync
  // ---------------------------------------------------------------------------

  @override
  Future<void> setActivePeer(PeerRecord peer, {String? roomId}) async {
    final effectiveRoom = (roomId == null || roomId.isEmpty)
        ? kDefaultRoomId
        : roomId;
    final cached = await _store.loadFor(
      peer.remoteEpk,
      roomId: effectiveRoom,
    );
    _activeEpk = peer.remoteEpk;
    _activeRoomId = effectiveRoom;
    _lastSyncedTs = cached.lastTs;
    _lastSessionStartedAt = cached.sessionStartedAt;
    _emit(_state.copyWith(
      messages: cached.messages,
      clearStreaming: true,
    ));
  }

  @override
  void requestSync() {
    final ch = _conn.channel;
    final epk = _activeEpk;
    if (ch == null || epk == null) {
      // Plan/24-fix-session-sync: don't drop sync requests silently.
      // Mark the intent so the next StatusOnline transition can fire
      // it for us. This was Bug 1: ChatViewModel's bootstrap called
      // requestSync while the channel was still in StatusConnecting
      // (post-reinstall cold-boot race) and the early return left the
      // chat with cache-only state forever.
      _pendingSyncRequest = true;
      return;
    }
    // Plan 16 mirror-cache: app does NOT cap the history. Pi decides
    // how many events to return based on its own env config; the app
    // just renders whatever arrives. Pi sets `truncated:true` if it
    // dropped events; we surface that to logs only (D1=B).
    final syncId = _newId();
    _pendingSyncRequest = false;
    ch.send(SessionSync(id: syncId));
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  @override
  Future<void> sendMessage(String text) async {
    final msg = UserMessage(id: _newId(), text: text);
    final ch = _conn.channel;

    // Plan/24-fix-app-source-of-truth (Option A): Pi is the
    // source-of-truth for the user_message stream. We still write a
    // local UserMsg synchronously — but it goes in as `pending`,
    // rendered with reduced opacity / a spinner, and is promoted to
    // `confirmed` only when Pi echoes the same id back via the
    // `user_input` (rebroadcast) frame. Mirrors how the chat already
    // treats `session_history` arrivals as authoritative.
    //
    // The bubble persists even when the channel is offline (Pi
    // stopped, app reconnecting); status stays `pending` and the
    // echo-timeout will eventually mark it `failed` so the user can
    // retry without typing again.
    final initial = UserMsg(
      id: msg.id,
      text: text,
      status: UserMsgStatus.pending,
    );
    final next = _state.copyWith(
      messages: [..._state.messages, initial],
      streaming: ch != null
          ? StreamingMessage(inReplyTo: msg.id)
          : _state.streaming,
    );
    _emit(next);
    unawaited(_persistSnapshot());
    if (ch != null) {
      _armEchoTimeout(msg.id);
      // The only outbound log we keep (alongside its echo counterpart
      // in `case UserInput`). Together they form the canonical send→
      // confirm cycle for the optimistic UI.
      debugPrint('[msg-send] id=${msg.id} text=${_preview(text)}');
      await ch.send(msg);
    } else {
      debugPrint(
        '[msg-send] id=${msg.id} text=${_preview(text)} (channel offline → held pending)',
      );
    }
  }

  static String _preview(String s) =>
      s.length <= 60 ? s : '${s.substring(0, 60)}…';

  /// Schedule the `pending → failed` transition for [id] if Pi's
  /// rebroadcast doesn't arrive within [_echoTimeout].
  /// Cancelled either by [_onServerMessage] receiving a matching
  /// `UserInput`, or by [_clearAllPending] (when the channel drops).
  void _armEchoTimeout(String id) {
    _pendingEchoTimers[id]?.cancel();
    _pendingEchoTimers[id] = Timer(_echoTimeout, () {
      _pendingEchoTimers.remove(id);
      final messages = _state.messages;
      var changed = false;
      final updated = [
        for (final m in messages)
          if (m is UserMsg && m.id == id && m.status == UserMsgStatus.pending)
            () {
              changed = true;
              return m.copyWith(status: UserMsgStatus.failed);
            }()
          else
            m,
      ];
      if (!changed) return;
      _emit(_state.copyWith(messages: updated));
      unawaited(_persistSnapshot());
    });
  }

  /// Cancel every outstanding echo timer WITHOUT touching state.
  /// Called when the channel drops so we don't fire spurious `failed`
  /// transitions while the app is just waiting for the Pi to come
  /// back; the pending bubbles stay in state as `pending` until either
  /// (a) the echo arrives via UserInput / SessionHistory, or (b)
  /// [_rearmPendingAfterReconnect] schedules a fresh timeout.
  void _clearAllPending() {
    if (_pendingEchoTimers.isEmpty) return;
    for (final t in _pendingEchoTimers.values) {
      t.cancel();
    }
    _pendingEchoTimers.clear();
  }

  /// Walk current state for `UserMsg(status: pending)` and arm a fresh
  /// echo timer for each. Invoked from [_onlineActivated] so a reconnect
  /// gives the Pi another window to rebroadcast the pending message
  /// before we surrender to `failed`. The bubble survives the reconnect
  /// visually (still in `pending`) because the user's WS state is the
  /// model's, not the timer's.
  void _rearmPendingAfterReconnect() {
    final pending = _state.messages
        .whereType<UserMsg>()
        .where((m) => m.status == UserMsgStatus.pending)
        .toList(growable: false);
    if (pending.isEmpty) return;
    for (final m in pending) {
      _armEchoTimeout(m.id);
    }
  }

  @override
  Future<void> cancel(String targetId) async {
    final ch = _conn.channel;
    if (ch == null) return;
    await ch.send(Cancel(id: _newId(), targetId: targetId));
  }

  @override
  Future<void> clearActiveSession() async {
    // Plan/28 — `session_new` was acked by the Pi. Reset the local mirror
    // so the chat shows the fresh (empty) thread immediately.
    //
    // Echo timers for any still-pending UserMsg are now meaningless (the
    // thread they belonged to is gone), so cancel them to avoid a stray
    // `pending → failed` flip after the wipe.
    _clearAllPending();
    // Drop the high-water marks: the next session_sync should be treated
    // as a fresh session, not a delta against the old thread.
    _lastSyncedTs = null;
    _lastSessionStartedAt = null;
    _emit(_state.copyWith(messages: const [], clearStreaming: true));
    final epk = _activeEpk;
    if (epk != null) {
      // Hard-wipe the persisted cache (partitioned + legacy box) so a
      // cold restart doesn't resurrect the old thread.
      //
      // NB: this is THIS device's view only. The Pi-extension keeps its
      // own event buffer that `session_new` does NOT clear today, so a
      // later session_sync can still backfill the old history. The
      // durable fix lives in pi-extension (see result file verdict).
      await _store.clearFor(epk, roomId: _activeRoomId);
    }
  }

  @override
  Future<void> approveTool(
    String toolCallId,
    ApproveDecision decision,
  ) async {
    final ch = _conn.channel;
    if (ch == null) return;
    await ch.send(
      ApproveTool(id: _newId(), toolCallId: toolCallId, decision: decision),
    );
    _updateTool(
      toolCallId,
      decision == ApproveDecision.allow
          ? ToolEventStatus.allowed
          : ToolEventStatus.denied,
    );
  }

  // ---------------------------------------------------------------------------
  // Internal event handlers
  // ---------------------------------------------------------------------------

  void _onStatusChange(ConnectionStatus s) {
    _msgSub?.cancel();
    _msgSub = null;

    if (s is StatusOnline) {
      _msgSub = s.channel.serverMessages.listen(
        _onServerMessage,
        onDone: () {
        },
        onError: (Object e, StackTrace st) {
        },
      );
      // ignore: unawaited_futures
      _onlineActivated();
    } else {
      // Plan/24-fix-app-source-of-truth: channel went away — cancel
      // any echo timers. Without this we'd race the disconnect:
      // pending UserMsgs would flip to `failed` while the Pi is
      // simply unreachable (and would echo on reconnect). Leaving
      // them as `pending` keeps the UI honest until reconnect.
      _clearAllPending();
    }
    _emit(_state.copyWith(connection: s));
  }

  Future<void> _onlineActivated() async {
    final peer = _conn.activePeer;
    if (peer == null) return;
    if (peer.remoteEpk != _activeEpk) {
      // Plan 17 — adopt whichever room the ConnectionManager is
      // currently addressing. Defaults to 'main' if nothing was set.
      await setActivePeer(peer, roomId: _conn.activeRoomId);
    }
    _syncDebounce?.cancel();
    _syncDebounce = Timer(const Duration(milliseconds: 200), requestSync);
    // Plan/24-fix-session-sync: if a deferred sync request is queued
    // (the ChatViewModel asked for it before the channel was open),
    // honour it now alongside the debounce-scheduled one. requestSync
    // clears the flag itself when it succeeds.
    if (_pendingSyncRequest) {
      requestSync();
    }
    // Plan/24-fix-pending: WS is back. Re-arm echo timers for any
    // UserMsg(pending) that survived the disconnect. Without this,
    // a transient reconnect leaves the bubble stuck in 'sending…'
    // forever — no timer to ever flip it to failed, no rebroadcast
    // expectation set up. The bubble will resolve naturally if the
    // Pi rebroadcasts during this fresh timeout window; otherwise it
    // flips to failed as in the no-reconnect path.
    _rearmPendingAfterReconnect();
  }

  void _onServerMessage(ServerMessage msg) {
    switch (msg) {
      case AgentChunk(:final inReplyTo, :final delta):
        _chunkBuffer.write(delta);
        _chunkReplyTo = inReplyTo;
        _flushTimer?.cancel();
        _flushTimer = Timer(const Duration(milliseconds: 16), _flushChunks);

      case AgentDone(:final inReplyTo):
        _flushTimer?.cancel();
        _flushTimer = null;
        final pendingDelta = _chunkBuffer.toString();
        _chunkBuffer.clear();
        _chunkReplyTo = '';

        final cur = _state.streaming;
        final streamedSoFar = cur?.buffer ?? '';
        final fullText = streamedSoFar + pendingDelta;

        if (fullText.isEmpty) {
          _emit(_state.copyWith(clearStreaming: true));
        } else {
          _emit(
            _state.copyWith(
              messages: [
                ..._state.messages,
                AssistantMsg(id: inReplyTo, text: fullText),
              ],
              clearStreaming: true,
            ),
          );
          unawaited(_persistSnapshot());
        }

      case AgentMessage(:final inReplyTo, :final text):
        // Consolidated reply (typically only inside session_history; rare
        // standalone). If the matching streaming bucket exists, finalize
        // it; otherwise append as a fresh AssistantMsg.
        if (_state.messages.any((m) => m is AssistantMsg && m.id == inReplyTo)) {
          break; // already present (dedupe)
        }
        _emit(
          _state.copyWith(
            messages: [..._state.messages, AssistantMsg(id: inReplyTo, text: text)],
            clearStreaming: _state.streaming?.inReplyTo == inReplyTo
                ? true
                : false,
          ),
        );
        unawaited(_persistSnapshot());

      case UserInput(:final id, :final text):
        // Plan/24-fix-app-source-of-truth: Pi rebroadcasts every
        // user_message it accepts (including ones the local device
        // sent). Three cases:
        //
        // 1. We have a `pending` UserMsg with the same id → this is
        //    the echo we were waiting for. Promote to `confirmed`,
        //    cancel the echo timer. Don't insert a duplicate.
        //
        // 2. We have a `confirmed` UserMsg with the same id (came in
        //    via session_history earlier) → idempotent skip.
        //
        // 3. We've never seen this id → message came from another
        //    device of the same Owner. Insert as `confirmed` and arm
        //    the streaming indicator (we expect the agent to reply).
        final pendingTimer = _pendingEchoTimers.remove(id);
        pendingTimer?.cancel();
        final existingIdx =
            _state.messages.indexWhere((m) => m is UserMsg && m.id == id);
        if (existingIdx >= 0) {
          final existing = _state.messages[existingIdx] as UserMsg;
          if (existing.status == UserMsgStatus.confirmed) {
            debugPrint('[msg-echo] id=$id source=local-confirmed (noop)');
            break;
          }
          final updated = [..._state.messages];
          updated[existingIdx] = existing.copyWith(
            status: UserMsgStatus.confirmed,
          );
          // The echo we were waiting for. Pair with the [msg-send]
          // log emitted in `sendMessage` to follow a single optimistic
          // bubble's lifecycle in the console.
          debugPrint('[msg-echo] id=$id source=local-pending → confirmed');
          _emit(_state.copyWith(messages: updated));
          unawaited(_persistSnapshot());
          break;
        }
        debugPrint(
          '[msg-echo] id=$id source=foreign-device (inserted as confirmed)',
        );
        _emit(
          _state.copyWith(
            messages: [
              ..._state.messages,
              UserMsg(id: id, text: text, status: UserMsgStatus.confirmed),
            ],
            streaming: StreamingMessage(inReplyTo: id),
          ),
        );
        unawaited(_persistSnapshot());

      case ToolRequest(:final toolCallId, :final tool, :final args):
        // Dedup against history: a previous `session_history` batch
        // may already contain this ToolEvent (same toolCallId).
        if (_state.messages
            .any((m) => m is ToolEvent && m.toolCallId == toolCallId)) {
          break;
        }
        final event = ToolEvent(
          id: toolCallId,
          toolCallId: toolCallId,
          tool: tool,
          args: args,
        );
        _emit(_state.copyWith(messages: [..._state.messages, event]));
        unawaited(_persistSnapshot());

      case ToolResult(:final toolCallId, :final result, :final error):
        _updateTool(
          toolCallId,
          error != null ? ToolEventStatus.denied : ToolEventStatus.completed,
          result: result,
          error: error,
        );
        unawaited(_persistSnapshot());

      case Cancelled(:final targetId):
        _emit(
          _state.copyWith(
            messages: [
              ..._state.messages.where((m) => m.id != targetId),
            ],
            clearStreaming: true,
          ),
        );
        unawaited(_persistSnapshot());

      case Pong():
        break;

      case PairOk():
      case PairError():
        break;

      // Plan/28 — Replies for typed app actions are handled by the
      // ActionsRepository's correlation map. The SessionRepository
      // doesn't own action state, so it just lets them pass through
      // (the underlying channel.serverMessages is a broadcast stream;
      // the ActionsRepository attaches its own listener).
      case ActionOk():
      case ActionError():
      case ModelsList():
        break;

      case Bye(:final rawReason):
        if (!_eventController.isClosed) {
          _eventController.add(PeerWentOffline(rawReason));
        }
        // Previously this called `_conn.disconnect()`, which tore down
        // the WS to relay entirely. That killed presence updates AND
        // meant the only way to learn Pi was back was a manual
        // Reconnect tap. Now we `switchTo` the same peer instead: it
        // closes the dead per-peer channel but immediately establishes
        // a fresh WS to relay with `subscribe_presence` replayed, so
        // when Pi reconnects the relay's `peer_online` flows through
        // and ChatViewModel can auto-clear the banner + sync.
        final peer = _conn.activePeer;
        if (peer != null) {
          // ignore: unawaited_futures
          _conn.switchTo(peer);
        }

      case SessionHistory():
        // ignore: unawaited_futures
        _applyHistory(msg);

      case ErrorMessage(:final code, :final message):
        if (code == 'unknown_peer' || code.contains('unknown_peer')) {
          if (!_eventController.isClosed) {
            _eventController.add(const PairingRevoked());
          }
          break;
        }
        _emit(
          _state.copyWith(
            messages: [
              ..._state.messages,
              AssistantMsg(id: _newId(), text: '⚠ $code: $message'),
            ],
          ),
        );
        unawaited(_persistSnapshot());
    }
  }

  // ---------------------------------------------------------------------------
  // session_history handling
  // ---------------------------------------------------------------------------

  Future<void> _applyHistory(SessionHistory h) async {
    final converted = _convertHistory(h.events);
    final maxTs = h.events.isEmpty
        ? null
        : h.events.map((e) => e.ts).reduce((a, b) => a > b ? a : b);
    _lastSessionStartedAt = h.sessionStartedAt;
    _lastSyncedTs = maxTs;

    // Plan/24-fix-pending: cancel echo timers for any pending UserMsg
    // whose id Pi has now acknowledged via history. The history's
    // copy of that message is `confirmed` by default (constructed by
    // _convertHistory), so the visual state flips automatically when
    // we emit the new messages list; we just need to release the
    // timer so it can't fire later and overwrite with `failed`.
    final convertedIds = <String>{
      for (final m in converted)
        if (m is UserMsg) m.id,
    };
    var resolvedFromHistory = 0;
    for (final id in convertedIds) {
      final t = _pendingEchoTimers.remove(id);
      if (t != null) {
        t.cancel();
        resolvedFromHistory++;
      }
    }
    // Plan/24-fix-pending: PRESERVE local pending UserMsgs whose ids
    // are NOT in Pi's history view. They were sent locally between
    // our last sync watermark and now; the Pi hasn't echoed them yet
    // (in-flight, transient disconnect, etc). Dropping them here used
    // to make the bubble vanish on every sync. Re-emit a merged list
    // (history first, then survivors in insertion order).
    final preservedPending = [
      for (final m in _state.messages)
        if (m is UserMsg &&
            m.status == UserMsgStatus.pending &&
            !convertedIds.contains(m.id))
          m,
    ];
    final merged = preservedPending.isEmpty
        ? converted
        : [...converted, ...preservedPending];

    // Plan 16 mirror-cache: state.messages = Pi's view exactly.
    // `truncated` is captured for logs only (D1=B).
    if (resolvedFromHistory > 0 || preservedPending.isNotEmpty) {
    }
    _emit(_state.copyWith(messages: merged, clearStreaming: false));

    final epk = _activeEpk;
    if (epk != null) {
      // Persist the merged view so a cold restart still shows pending
      // bubbles — they'll be re-armed in _onlineActivated as soon as
      // the WS comes back. UserMsgStatus is serialized
      // (session_history_store.dart) so `pending` round-trips.
      await _store.replaceFor(
        epk,
        merged,
        roomId: _activeRoomId,
        sessionStartedAt: h.sessionStartedAt,
        lastTs: _lastSyncedTs,
      );
    }

    if (h.eos) {
    }
  }

  /// Replay history events sequentially so a `tool_request` followed by a
  /// `tool_result` for the same call merges into a single ToolEvent (the
  /// same in-place merge `_updateTool` does for real-time).
  List<ChatMessage> _convertHistory(List<SessionHistoryEvent> events) {
    final out = <ChatMessage>[];
    for (final e in events) {
      switch (e) {
        case UserInputEvt(:final id, :final text):
          out.add(UserMsg(id: id, text: text));
        case AgentMessageEvt(:final inReplyTo, :final text):
          out.add(AssistantMsg(id: inReplyTo, text: text));
        case ToolRequestEvt(:final toolCallId, :final tool, :final args):
          out.add(ToolEvent(
            id: toolCallId,
            toolCallId: toolCallId,
            tool: tool,
            args: args,
          ));
        case ToolResultEvt(:final toolCallId, :final result, :final error):
          final idx = out.lastIndexWhere(
            (m) => m is ToolEvent && m.toolCallId == toolCallId,
          );
          final newStatus = error != null
              ? ToolEventStatus.denied
              : ToolEventStatus.completed;
          if (idx >= 0) {
            final existing = out[idx] as ToolEvent;
            out[idx] = existing.copyWith(
              status: newStatus,
              result: result,
              error: error,
            );
          } else {
            out.add(ToolEvent(
              id: toolCallId,
              toolCallId: toolCallId,
              tool: 'unknown',
              args: const <String, dynamic>{},
              status: newStatus,
              result: result,
              error: error,
            ));
          }
      }
    }
    return out;
  }

  // ---------------------------------------------------------------------------

  Future<void> _persistSnapshot() async {
    final epk = _activeEpk;
    if (epk == null) {
      return;
    }
    // Persist current state to Hive. Pointers (`_lastSessionStartedAt`,
    // `_lastSyncedTs`) are only advanced by `_applyHistory` when actual
    // events arrive; here we just snapshot the rendered message list
    // so a reload-from-cold shows the same view.
    await _store.replaceFor(
      epk,
      _state.messages,
      roomId: _activeRoomId,
      sessionStartedAt: _lastSessionStartedAt,
      lastTs: _lastSyncedTs,
    );
  }

  void _flushChunks() {
    if (_chunkBuffer.isEmpty) return;
    final delta = _chunkBuffer.toString();
    _chunkBuffer.clear();
    final cur = _state.streaming;
    if (cur != null && cur.inReplyTo == _chunkReplyTo) {
      _emit(_state.copyWith(streaming: cur.appendDelta(delta)));
    } else {
      _emit(
        _state.copyWith(
          streaming: StreamingMessage(inReplyTo: _chunkReplyTo, buffer: delta),
        ),
      );
    }
  }

  void _updateTool(
    String toolCallId,
    ToolEventStatus status, {
    dynamic result,
    String? error,
  }) {
    var found = false;
    final updated = _state.messages.map((m) {
      if (m is ToolEvent && m.toolCallId == toolCallId) {
        found = true;
        return m.copyWith(status: status, result: result, error: error);
      }
      return m;
    }).toList();

    if (!found) {
      updated.add(ToolEvent(
        id: toolCallId,
        toolCallId: toolCallId,
        tool: 'unknown',
        args: const <String, dynamic>{},
        status: status,
        result: result,
        error: error,
      ));
    }

    _emit(_state.copyWith(messages: updated));
  }

  void _emit(SessionState s) {
    _state = s;
    if (!_stateController.isClosed) _stateController.add(s);
    _maybeEmitWorking();
  }

  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    _flushTimer?.cancel();
    _syncDebounce?.cancel();
    _connSub?.cancel();
    _msgSub?.cancel();
    _clearAllPending();
    _conn.dispose();
    _stateController.close();
    _eventController.close();
    _workingController.close();
  }

  /// Generate a globally-unique client message id. Prefix `cli_`
  /// preserved for back-compat with existing tests / consumers that
  /// distinguish app-originated ids from Pi-side ones; the UUIDv7
  /// tail makes the id collision-free across devices of the same
  /// Owner (was: per-instance counter, which collided when iPhone
  /// and Android both produced `cli_4` independently — the Pi
  /// rebroadcast would prematurely confirm the wrong device's
  /// pending bubble).
  static String _newId() => 'cli_${uuid7()}';
}
