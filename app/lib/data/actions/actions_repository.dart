// ActionsRepository — Plan/28 typed app actions.
//
// Wraps the active `IChannel` exposed by [ConnectionManager] and turns
// the per-action wire dance into a typed Future<void> /
// Future<ModelsCatalogue>. Each call:
//   1. mints a UUIDv7 request id
//   2. registers a Completer in the pending map
//   3. sends the ClientMessage
//   4. resolves the Completer when the matching `action_ok` /
//      `action_error` / `models_list` arrives (or fails with
//      [ActionFailure] on disconnect / timeout)
//
// `list_models` results are cached per active (peer, room) for the
// session. Three cache-invalidation paths:
//
//   1. Local `setModel` — caller knows the cache is stale, drops it.
//   2. External `room_meta_updated` carrying a different model than
//      we last knew (Wave D: another app paired with this Pi, or the
//      TUI's `/model` switched it). Detected by listening to the
//      ConnectionManager's `roomsStream`.
//   3. Manual `forceRefresh: true` from the picker's pull-to-refresh.
//
// The repository also exposes [activeRoomMeta] — a typed snapshot of
// `(model, thinking)` for the active room — so the QuickActions
// ViewModel can hydrate the segmented control on first open instead
// of starting null.

import 'dart:async';

import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/domain/contracts/repository.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/protocol/uuid7.dart';

/// Reply for [ActionsRepository.listModels]. Captures both the catalogue
/// and the model the Pi reports as active right now.
class ModelsCatalogue {
  final List<WireModel> models;
  final WireModel? current;
  const ModelsCatalogue({required this.models, this.current});
}

/// Plan/28 Wave D — snapshot of the active room's meta, as broadcast
/// by the relay. Forwarded by [ActionsRepository.activeRoomMeta] so
/// the QuickActions ViewModel can hydrate its current model / thinking
/// without a round-trip.
class ActiveRoomMeta {
  /// Standard-b64 epk of the active peer, or `null` when no peer is
  /// active (offline, between switches, etc.). Helps a consumer ignore
  /// transient empty snapshots vs. honest "we're not paired" state.
  final String? peerEpk;
  /// Pi-side room id this snapshot describes — defaults to `'main'`.
  final String roomId;
  /// Display model name from `meta.model` (e.g. "Claude Opus 4.7").
  /// `null` until the Pi publishes it (or while disconnected).
  final String? model;
  /// Current thinking level from `meta.thinking`. Forward-compat — the
  /// relay does not yet flatten this field, so until the relay update
  /// ships this is always `null` in production. Kept on the API
  /// surface so the app stack lights up the moment the relay catches
  /// up, no further app changes required.
  final ThinkingLevel? thinking;
  const ActiveRoomMeta({
    this.peerEpk,
    this.roomId = 'main',
    this.model,
    this.thinking,
  });

  @override
  bool operator ==(Object other) =>
      other is ActiveRoomMeta &&
      other.peerEpk == peerEpk &&
      other.roomId == roomId &&
      other.model == model &&
      other.thinking == thinking;

  @override
  int get hashCode => Object.hash(peerEpk, roomId, model, thinking);
}

/// Typed failure thrown by [ActionsRepository] when an action cannot
/// complete. UI layer renders [message] as a snackbar.
class ActionFailure implements Exception {
  final String message;
  const ActionFailure(this.message);

  @override
  String toString() => 'ActionFailure: $message';
}

abstract class IActionsRepository extends Repository {
  Future<void> compact();
  Future<void> newSession();
  Future<void> setModel(String provider, String modelId);
  Future<void> setThinking(ThinkingLevel level);

  /// Register (and start) a supervisor daemon for the directory [path].
  /// Throws [ActionFailure] with the exact error string
  /// `'directory_missing'` when the path is absent and [createIfMissing]
  /// is false — the caller offers a create-anyway confirm on that.
  Future<void> createRoom(String path, {bool createIfMissing = false});

  /// Unregister the daemon behind the directory [path] (stops the agent
  /// process + removes the room from the supervisor registry).
  Future<void> deleteRoom(String path);

  /// Fetches the model catalogue. When [forceRefresh] is `false`
  /// (default) returns the cached catalogue for the current
  /// (peer, room) session if one exists; otherwise hits the Pi.
  Future<ModelsCatalogue> listModels({bool forceRefresh = false});

  /// Snapshot of the active room's meta. Recomputed on every rooms
  /// snapshot and on every connection-status change.
  ActiveRoomMeta get activeRoomMeta;

  /// Stream of [activeRoomMeta] snapshots — deduplicated by equality
  /// so consumers don't rebuild on no-op emits.
  Stream<ActiveRoomMeta> get activeRoomMetaStream;
}

class ActionsRepository extends Repository implements IActionsRepository {
  final ConnectionManager _conn;
  final Duration _timeout;

  StreamSubscription<ConnectionStatus>? _statusSub;
  StreamSubscription<ServerMessage>? _msgSub;
  StreamSubscription<Map<String, List<RoomInfo>>>? _roomsSub;
  IChannel? _channel;

  final Map<String, _Pending> _pending = {};
  final Map<String, ModelsCatalogue> _modelsCache = {};

  /// Plan/28 Wave D — last model name we observed via `roomsStream`
  /// per session key. Lets us detect "the model changed externally"
  /// without invalidating the cache on the local round-trip we just
  /// initiated (which has already cleared the cache directly).
  final Map<String, String?> _lastKnownModelName = {};

  ActiveRoomMeta _activeRoomMeta = const ActiveRoomMeta();
  final _activeRoomMetaController =
      StreamController<ActiveRoomMeta>.broadcast();

  ActionsRepository(
    this._conn, {
    Duration timeout = const Duration(seconds: 15),
  }) : _timeout = timeout {
    _statusSub = _conn.statusStream.listen(_onStatus);
    _roomsSub = _conn.roomsStream.listen(_onRooms);
    _onStatus(_conn.status);
    // Seed the meta snapshot synchronously so an early caller sees
    // whatever the ConnectionManager already cached at construction.
    _refreshActiveRoomMeta();
  }

  // ---------------------------------------------------------------------------
  // Wire glue
  // ---------------------------------------------------------------------------

  void _onStatus(ConnectionStatus s) {
    _msgSub?.cancel();
    _msgSub = null;
    if (s is StatusOnline) {
      _channel = s.channel;
      _msgSub = s.channel.serverMessages.listen(
        _onMessage,
        onError: (Object _, StackTrace _) {},
      );
    } else {
      _channel = null;
      _failAllPending('disconnected');
    }
    _refreshActiveRoomMeta();
  }

  void _onRooms(Map<String, List<RoomInfo>> _) {
    _refreshActiveRoomMeta();
  }

  void _onMessage(ServerMessage msg) {
    switch (msg) {
      case ActionOk(:final inReplyTo):
        final p = _pending.remove(inReplyTo);
        if (p == null) return;
        p.timeout.cancel();
        if (!p.completer.isCompleted) p.completer.complete(null);
      case ActionError(:final inReplyTo, :final error):
        final p = _pending.remove(inReplyTo);
        if (p == null) return;
        p.timeout.cancel();
        if (!p.completer.isCompleted) {
          p.completer.completeError(
            ActionFailure(error.isEmpty ? 'action failed' : error),
          );
        }
      case ModelsList(:final inReplyTo, :final models, :final current):
        final p = _pending.remove(inReplyTo);
        if (p == null) return;
        p.timeout.cancel();
        if (!p.completer.isCompleted) {
          p.completer.complete(
            ModelsCatalogue(models: models, current: current),
          );
        }
      default:
        // All other ServerMessages are owned by SessionRepository.
        break;
    }
  }

  void _failAllPending(String reason) {
    if (_pending.isEmpty) return;
    final snapshot = List<_Pending>.of(_pending.values);
    _pending.clear();
    for (final p in snapshot) {
      p.timeout.cancel();
      if (!p.completer.isCompleted) {
        p.completer.completeError(ActionFailure(reason));
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Active room meta + cache invalidation
  // ---------------------------------------------------------------------------

  void _refreshActiveRoomMeta() {
    final peer = _conn.activePeer;
    final epk = peer?.remoteEpk;
    final roomId = _conn.activeRoomId;

    RoomInfo? active;
    if (epk != null) {
      final rooms = _conn.roomsFor(epk);
      for (final r in rooms) {
        if (r.roomId == roomId) {
          active = r;
          break;
        }
      }
    }

    final next = ActiveRoomMeta(
      peerEpk: epk,
      roomId: roomId,
      model: active?.model,
      thinking: active?.thinking,
    );

    // Plan/28 Wave D — detect external model changes. The local
    // `setModel` path already drops the cache directly; here we only
    // care about transitions of model name learned via room broadcasts.
    final key = '$epk|$roomId';
    final previousModel = _lastKnownModelName[key];
    final hadPreviousKnowledge = _lastKnownModelName.containsKey(key);
    if (hadPreviousKnowledge && previousModel != next.model) {
      _modelsCache.remove(key);
    }
    _lastKnownModelName[key] = next.model;

    if (next == _activeRoomMeta) return;
    _activeRoomMeta = next;
    if (!_activeRoomMetaController.isClosed) {
      _activeRoomMetaController.add(next);
    }
  }

  @override
  ActiveRoomMeta get activeRoomMeta => _activeRoomMeta;

  @override
  Stream<ActiveRoomMeta> get activeRoomMetaStream =>
      _activeRoomMetaController.stream;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  @override
  Future<void> compact() async {
    await _dispatch<void>((id) => SessionCompact(id: id));
  }

  @override
  Future<void> newSession() async {
    await _dispatch<void>((id) => SessionNew(id: id));
  }

  @override
  Future<void> setModel(String provider, String modelId) async {
    await _dispatch<void>(
      (id) => ModelSet(id: id, provider: provider, modelId: modelId),
    );
    // Invalidate the cached catalogue so the next picker open reflects
    // the new `current` highlight.
    _modelsCache.remove(_sessionKey());
  }

  @override
  Future<void> setThinking(ThinkingLevel level) async {
    await _dispatch<void>((id) => ThinkingSet(id: id, level: level));
  }

  @override
  Future<void> createRoom(String path, {bool createIfMissing = false}) async {
    await _dispatch<void>((id) => RoomCreate(
          id: id,
          path: path,
          createIfMissing: createIfMissing,
        ));
  }

  @override
  Future<void> deleteRoom(String path) async {
    await _dispatch<void>((id) => RoomDelete(id: id, path: path));
  }

  @override
  Future<ModelsCatalogue> listModels({bool forceRefresh = false}) async {
    final key = _sessionKey();
    if (!forceRefresh) {
      final cached = _modelsCache[key];
      if (cached != null) return cached;
    }
    final result =
        await _dispatch<ModelsCatalogue>((id) => ListModels(id: id));
    // Re-evaluate the session key — the user may have switched rooms
    // mid-flight. We only cache against the key the *response* belongs
    // to, which is the live one when it resolves.
    _modelsCache[_sessionKey()] = result;
    return result;
  }

  Future<T> _dispatch<T>(ClientMessage Function(String id) builder) async {
    final ch = _channel;
    if (ch == null) {
      throw const ActionFailure('offline');
    }
    final id = 'act_${uuid7()}';
    final completer = Completer<dynamic>();
    final timer = Timer(_timeout, () {
      final p = _pending.remove(id);
      if (p == null) return;
      if (!p.completer.isCompleted) {
        p.completer.completeError(const ActionFailure('timeout'));
      }
    });
    _pending[id] = _Pending(completer: completer, timeout: timer);

    try {
      await ch.send(builder(id));
    } catch (e) {
      timer.cancel();
      _pending.remove(id);
      throw ActionFailure(e.toString());
    }
    final value = await completer.future;
    return value as T;
  }

  String _sessionKey() {
    final epk = _conn.activePeer?.remoteEpk ?? '';
    final room = _conn.activeRoomId;
    return '$epk|$room';
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _msgSub?.cancel();
    _roomsSub?.cancel();
    _failAllPending('disposed');
    _modelsCache.clear();
    _lastKnownModelName.clear();
    _activeRoomMetaController.close();
    super.dispose();
  }
}

class _Pending {
  final Completer<dynamic> completer;
  final Timer timeout;
  _Pending({required this.completer, required this.timeout});
}
