// ignore_for_file: lines_longer_than_80_chars

// ---------------------------------------------------------------------------
// Control frames (plano 12 — presence)
//
// These travel raw over the WS (no outer envelope) and are routed by the
// relay itself, not the Pi. They never enter the inner-message switch.
// ---------------------------------------------------------------------------

/// Inbound control frame (relay → app).
sealed class ControlInbound {
  const ControlInbound();

  /// Parses a top-level JSON map into a control inbound. Returns null when
  /// the `type` is unknown (forward-compat).
  static ControlInbound? tryFromJson(Map<String, dynamic> j) {
    return switch (j['type']) {
      'peer_online' => PeerOnline(peer: j['peer'] as String),
      'peer_offline' => PeerOffline(
          peer: j['peer'] as String,
          sinceTs: (j['since_ts'] as num).toInt(),
        ),
      'presence' => PresenceSnapshot(
          states: (j['states'] as List<dynamic>)
              .map((e) => PeerPresence.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
      'room_announced' => () {
          // Plan/28 Wave D — thinking arrives either as a top-level
          // field (post-relay-flatten) or nested under `meta.thinking`
          // (pre-flatten relay forwarding the Pi's room_meta verbatim).
          // Read both so the app stays forward-compat with either side.
          final metaJson = j['meta'] as Map<String, dynamic>?;
          final rawThinking = (j['thinking'] as String?) ??
              (metaJson?['thinking'] as String?);
          return RoomAnnounced(
            peer: j['peer'] as String,
            roomId: j['room_id'] as String,
            name: j['name'] as String?,
            cwd: j['cwd'] as String?,
            startedAt: (j['started_at'] as num).toInt(),
            model: j['model'] as String?,
            thinking:
                rawThinking != null ? ThinkingLevel.fromWire(rawThinking) : null,
          );
        }(),
      'room_ended' => RoomEnded(
          peer: j['peer'] as String,
          roomId: j['room_id'] as String,
          sinceTs: (j['since_ts'] as num).toInt(),
        ),
      'rooms' => RoomsSnapshot(
          peer: j['peer'] as String,
          rooms: (j['rooms'] as List<dynamic>)
              .map((e) => RoomInfo.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
      'room_meta_updated' => () {
          final meta = j['meta'] as Map<String, dynamic>?;
          final hasModel = meta?.containsKey('model') ?? false;
          final hasThinking = meta?.containsKey('thinking') ?? false;
          final rawThinking = meta?['thinking'] as String?;
          return RoomMetaUpdated(
            peer: j['peer'] as String,
            roomId: j['room_id'] as String,
            model: meta?['model'] as String?,
            thinking:
                rawThinking != null ? ThinkingLevel.fromWire(rawThinking) : null,
            hasModel: hasModel,
            hasThinking: hasThinking,
          );
        }(),
      _ => null,
    };
  }
}

class PeerOnline extends ControlInbound {
  final String peer;
  const PeerOnline({required this.peer});
}

class PeerOffline extends ControlInbound {
  final String peer;
  final int sinceTs;
  const PeerOffline({required this.peer, required this.sinceTs});
}

class PresenceSnapshot extends ControlInbound {
  final List<PeerPresence> states;
  const PresenceSnapshot({required this.states});
}

class PeerPresence {
  final String peer;
  final bool online;
  final int? sinceTs;
  const PeerPresence({
    required this.peer,
    required this.online,
    required this.sinceTs,
  });

  factory PeerPresence.fromJson(Map<String, dynamic> j) => PeerPresence(
    peer: j['peer'] as String,
    online: j['online'] as bool,
    sinceTs: (j['since_ts'] as num?)?.toInt(),
  );
}

// --- Outbound control frames (helpers; the wire shape is just a Map) ---

Map<String, dynamic> subscribePresenceFrame(List<String> peers) => {
  'type': 'subscribe_presence',
  'peers': peers,
};

Map<String, dynamic> unsubscribePresenceFrame(List<String> peers) => {
  'type': 'unsubscribe_presence',
  'peers': peers,
};

Map<String, dynamic> presenceCheckFrame(List<String> peers) => {
  'type': 'presence_check',
  'peers': peers,
};

Map<String, dynamic> subscribeRoomsFrame(List<String> peers) => {
  'type': 'subscribe_rooms',
  'peers': peers,
};

Map<String, dynamic> unsubscribeRoomsFrame(List<String> peers) => {
  'type': 'unsubscribe_rooms',
  'peers': peers,
};

Map<String, dynamic> roomsCheckFrame(List<String> peers) => {
  'type': 'rooms_check',
  'peers': peers,
};

// ---------------------------------------------------------------------------
// Rooms (plan 17 — multi-cwd per Mac)
//
// Each Pi-extension instance opens one room per active session (cwd).
// The relay tracks room metadata per peer and pushes:
//   - room_announced: a new room came online for a peer
//   - room_ended: a room closed (Pi exited or stopped that cwd)
//   - rooms (snapshot): full list for a peer (sent after subscribe_rooms
//     or rooms_check).
// The app subscribes via `subscribe_rooms(peers)` and renders them as
// tiles grouped by Mac.
// ---------------------------------------------------------------------------

// Sentinel for nullable copyWith parameters that need to distinguish
// "keep current" (omit) from "set to null" (pass `null` explicitly).
const Object _kRoomInfoUnset = Object();

/// Snapshot of a single Pi room (one cwd / session).
class RoomInfo {
  final String roomId;
  final String? name;
  final String? cwd;
  final int startedAt;
  /// Plan 18 — display model the Pi-extension is running with (e.g.
  /// `claude-sonnet-4.5`, `gpt-4o`). Optional; Pi-ext may omit and
  /// the app falls back to `last paired` in the subtitle.
  final String? model;
  /// Plan/28 Wave D — current thinking level the Pi-extension session
  /// is running with. Optional; Pi-ext may omit when it cannot resolve
  /// it from the SDK, and legacy Pis don't publish this field at all.
  /// Drives the initial highlight of the Quick Actions thinking
  /// segmented control.
  final ThinkingLevel? thinking;

  const RoomInfo({
    required this.roomId,
    required this.startedAt,
    this.name,
    this.cwd,
    this.model,
    this.thinking,
  });

  factory RoomInfo.fromJson(Map<String, dynamic> j) {
    final rawThinking = j['thinking'] as String?;
    return RoomInfo(
      roomId: j['room_id'] as String,
      name: j['name'] as String?,
      cwd: j['cwd'] as String?,
      startedAt: (j['started_at'] as num).toInt(),
      model: j['model'] as String?,
      thinking:
          rawThinking != null ? ThinkingLevel.fromWire(rawThinking) : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'room_id': roomId,
    'name': name,
    'cwd': cwd,
    'started_at': startedAt,
    'model': model,
    if (thinking != null) 'thinking': thinking!.wire,
  };

  RoomInfo copyWith({
    String? name,
    String? cwd,
    int? startedAt,
    Object? model = _kRoomInfoUnset,
    Object? thinking = _kRoomInfoUnset,
  }) => RoomInfo(
    roomId: roomId,
    name: name ?? this.name,
    cwd: cwd ?? this.cwd,
    startedAt: startedAt ?? this.startedAt,
    model: identical(model, _kRoomInfoUnset)
        ? this.model
        : model as String?,
    thinking: identical(thinking, _kRoomInfoUnset)
        ? this.thinking
        : thinking as ThinkingLevel?,
  );

  @override
  bool operator ==(Object other) =>
      other is RoomInfo &&
      other.roomId == roomId &&
      other.name == name &&
      other.cwd == cwd &&
      other.startedAt == startedAt &&
      other.model == model &&
      other.thinking == thinking;

  @override
  int get hashCode =>
      Object.hash(roomId, name, cwd, startedAt, model, thinking);
}

class RoomAnnounced extends ControlInbound {
  final String peer;
  final String roomId;
  final String? name;
  final String? cwd;
  final int startedAt;
  /// Plan 18 — display model the Pi-extension is running with.
  final String? model;
  /// Plan/28 Wave D — current thinking level the Pi seeds at
  /// session start. Parsed from `meta.thinking` or top-level
  /// `thinking` depending on whether the relay flattens metadata.
  final ThinkingLevel? thinking;
  const RoomAnnounced({
    required this.peer,
    required this.roomId,
    required this.startedAt,
    this.name,
    this.cwd,
    this.model,
    this.thinking,
  });
}

class RoomEnded extends ControlInbound {
  final String peer;
  final String roomId;
  final int sinceTs;
  const RoomEnded({
    required this.peer,
    required this.roomId,
    required this.sinceTs,
  });
}

class RoomsSnapshot extends ControlInbound {
  final String peer;
  final List<RoomInfo> rooms;
  const RoomsSnapshot({required this.peer, required this.rooms});
}

/// Plan 18 — incremental update to a room's metadata (model is the
/// only field for now, but the `meta` envelope is open-ended). The
/// relay pushes this when the Pi-extension swaps its model
/// mid-session.
class RoomMetaUpdated extends ControlInbound {
  final String peer;
  final String roomId;
  final String? model;
  /// Plan/28 Wave D — current thinking level, parsed from
  /// `meta.thinking`. Null when the Pi only published a model change.
  /// The app treats both fields as independently optional so an update
  /// for only one of them doesn't clobber the other on the cache side.
  final ThinkingLevel? thinking;
  /// Plan/28 Wave D — `true` when the `meta` envelope carried a `model`
  /// key (even if value is null). Lets the ConnectionManager handler
  /// distinguish "model was not part of this update" from "model was
  /// explicitly cleared", which matters now that updates can be
  /// thinking-only.
  ///
  /// Defaults to `true` for ergonomic programmatic construction
  /// (callers / tests can pass `model: x` without also remembering
  /// the boolean). [RoomMetaUpdated.fromJson] passes the precise
  /// presence-of-key boolean instead.
  final bool hasModel;
  /// Plan/28 Wave D — same convention for `thinking`.
  final bool hasThinking;
  const RoomMetaUpdated({
    required this.peer,
    required this.roomId,
    this.model,
    this.thinking,
    this.hasModel = true,
    this.hasThinking = true,
  });
}

// ---------------------------------------------------------------------------
// PresenceState — per-peer summary kept by ConnectionManager.
// ---------------------------------------------------------------------------

sealed class PresenceState {
  const PresenceState();
}

class PresenceUnknown extends PresenceState {
  const PresenceUnknown();
}

class PresenceOnline extends PresenceState {
  final int? sinceTs;
  const PresenceOnline({this.sinceTs});
}

class PresenceOffline extends PresenceState {
  final int? sinceTs;
  const PresenceOffline({this.sinceTs});
}

// --- Supporting types ---

class Usage {
  final int inputTokens;
  final int outputTokens;

  const Usage({required this.inputTokens, required this.outputTokens});

  factory Usage.fromJson(Map<String, dynamic> j) => Usage(
    inputTokens: j['input_tokens'] as int,
    outputTokens: j['output_tokens'] as int,
  );
}

enum ApproveDecision { allow, deny }

class UnsupportedTypeException implements Exception {
  final String type;
  const UnsupportedTypeException(this.type);

  @override
  String toString() => 'UnsupportedTypeException: unknown type "$type"';
}

// --- ClientMessage (app → extension) ---
// MVP: 1 pairing = 1 Pi session — no session management messages.

sealed class ClientMessage {
  Map<String, dynamic> toJson();
}

class UserMessage extends ClientMessage {
  final String id;
  final String text;
  UserMessage({required this.id, required this.text});

  @override
  Map<String, dynamic> toJson() => {
    'type': 'user_message',
    'id': id,
    'text': text,
  };
}

class ApproveTool extends ClientMessage {
  final String id;
  final String toolCallId;
  final ApproveDecision decision;
  ApproveTool({
    required this.id,
    required this.toolCallId,
    required this.decision,
  });

  @override
  Map<String, dynamic> toJson() => {
    'type': 'approve_tool',
    'id': id,
    'tool_call_id': toolCallId,
    'decision': decision.name,
  };
}

class Cancel extends ClientMessage {
  final String id;
  final String targetId;
  Cancel({required this.id, required this.targetId});

  @override
  Map<String, dynamic> toJson() => {
    'type': 'cancel',
    'id': id,
    'target_id': targetId,
  };
}

class Ping extends ClientMessage {
  final String id;
  Ping({required this.id});

  @override
  Map<String, dynamic> toJson() => {'type': 'ping', 'id': id};
}

class PairRequest extends ClientMessage {
  final String id;
  final String token;
  final String deviceName;
  PairRequest({
    required this.id,
    required this.token,
    required this.deviceName,
  });

  @override
  Map<String, dynamic> toJson() => {
    'type': 'pair_request',
    'id': id,
    'token': token,
    'device_name': deviceName,
  };
}

/// Sent on reconnect / re-entry to request the current view of Pi's
/// session. With the mirror-cache strategy (plan/16) the app no longer
/// negotiates incremental since_ts; it just asks for the latest N
/// events and replaces local state with whatever Pi returns.
class SessionSync extends ClientMessage {
  final String id;
  final int? limit;
  SessionSync({required this.id, this.limit});

  @override
  Map<String, dynamic> toJson() => {
    'type': 'session_sync',
    'id': id,
    if (limit != null) 'limit': limit,
  };
}

// ---------------------------------------------------------------------------
// Plan/28 — Typed app actions
// ---------------------------------------------------------------------------

/// Plan/28 — Curated catalogue of actions the app can dispatch on the
/// Pi-side session. Each value matches an `action_ok`/`action_error`
/// reply emitted by the pi-extension handlers in
/// `pi-extension/src/actions/handlers.ts`.
enum ActionName {
  sessionNew('session_new'),
  sessionCompact('session_compact'),
  modelSet('model_set'),
  thinkingSet('thinking_set');

  final String wire;
  const ActionName(this.wire);

  static ActionName? fromWire(String s) {
    for (final a in values) {
      if (a.wire == s) return a;
    }
    return null;
  }
}

/// Plan/28 — Mirror of the SDK's `ThinkingLevel`. Six fixed values; the
/// wire format is the lower-case string. `xhigh` is honored only by
/// select models — the app surfaces every level and the SDK falls back
/// when the active model doesn't support the requested one.
enum ThinkingLevel {
  off('off'),
  minimal('minimal'),
  low('low'),
  medium('medium'),
  high('high'),
  xhigh('xhigh');

  final String wire;
  const ThinkingLevel(this.wire);

  static ThinkingLevel? fromWire(String s) {
    for (final l in values) {
      if (l.wire == s) return l;
    }
    return null;
  }
}

/// Plan/28 — Wire shape for one entry in the model picker. Subset of
/// the SDK's `Model` interface; matches the `WireModel` declared in
/// `pi-extension/src/protocol/types.ts`.
class WireModel {
  /// Stable id inside the provider's catalog (e.g. `claude-opus-4-7`).
  final String id;
  /// Display name shown in the picker (e.g. `Claude Opus 4.7`).
  final String name;
  /// Provider slug (e.g. `anthropic`, `openai`).
  final String provider;
  /// Whether this model exposes the thinking surface. Drives the
  /// thinking segmented control's enabled state on the picker side.
  final bool reasoning;
  /// Context window in tokens — surfaced as picker subtitle.
  final int contextWindow;

  const WireModel({
    required this.id,
    required this.name,
    required this.provider,
    required this.reasoning,
    required this.contextWindow,
  });

  factory WireModel.fromJson(Map<String, dynamic> j) => WireModel(
    id: j['id'] as String,
    name: j['name'] as String,
    provider: j['provider'] as String,
    reasoning: (j['reasoning'] as bool?) ?? false,
    contextWindow: (j['context_window'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'provider': provider,
    'reasoning': reasoning,
    'context_window': contextWindow,
  };

  @override
  bool operator ==(Object other) =>
      other is WireModel &&
      other.id == id &&
      other.provider == provider &&
      other.name == name &&
      other.reasoning == reasoning &&
      other.contextWindow == contextWindow;

  @override
  int get hashCode =>
      Object.hash(id, provider, name, reasoning, contextWindow);
}

class SessionCompact extends ClientMessage {
  final String id;
  SessionCompact({required this.id});

  @override
  Map<String, dynamic> toJson() => {'type': 'session_compact', 'id': id};
}

class SessionNew extends ClientMessage {
  final String id;
  SessionNew({required this.id});

  @override
  Map<String, dynamic> toJson() => {'type': 'session_new', 'id': id};
}

class ModelSet extends ClientMessage {
  final String id;
  final String provider;
  final String modelId;
  ModelSet({required this.id, required this.provider, required this.modelId});

  @override
  Map<String, dynamic> toJson() => {
    'type': 'model_set',
    'id': id,
    'provider': provider,
    'model_id': modelId,
  };
}

class ThinkingSet extends ClientMessage {
  final String id;
  final ThinkingLevel level;
  ThinkingSet({required this.id, required this.level});

  @override
  Map<String, dynamic> toJson() => {
    'type': 'thinking_set',
    'id': id,
    'level': level.wire,
  };
}

class ListModels extends ClientMessage {
  final String id;
  ListModels({required this.id});

  @override
  Map<String, dynamic> toJson() => {'type': 'list_models', 'id': id};
}

// --- ServerMessage (extension → app) ---
// 1 pairing = 1 session: no session_id on any message.
// Sealed: all subtypes in this file — switch exhaustiveness enforced by compiler.

sealed class ServerMessage {
  const ServerMessage();

  factory ServerMessage.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    return switch (type) {
      'agent_chunk' => AgentChunk.fromJson(json),
      'agent_done' => AgentDone.fromJson(json),
      'tool_request' => ToolRequest.fromJson(json),
      'tool_result' => ToolResult.fromJson(json),
      'error' => ErrorMessage.fromJson(json),
      'cancelled' => Cancelled.fromJson(json),
      'pong' => Pong.fromJson(json),
      'pair_ok' => PairOk.fromJson(json),
      'pair_error' => PairError.fromJson(json),
      // Plan/24-fix-app-source-of-truth + follow-up: Pi rebroadcasts
      // every accepted user_message via this stream. Some Pi-extension
      // versions emit `type: "user_input"` (mirror of a terminal-side
      // input), others reuse the original `user_message` type when
      // echoing back. Treat both as the same payload — `UserInput`
      // here is the "user-text-arrived" event regardless of origin.
      'user_input' || 'user_message' => UserInput.fromJson(json),
      'agent_message' => AgentMessage.fromJson(json),
      'session_history' => SessionHistory.fromJson(json),
      'bye' => Bye.fromJson(json),
      'action_ok' => ActionOk.fromJson(json),
      'action_error' => ActionError.fromJson(json),
      'models_list' => ModelsList.fromJson(json),
      // forward-compat: unknown types are not fatal — callers catch and log
      _ => throw UnsupportedTypeException(type ?? ''),
    };
  }
}

class AgentChunk extends ServerMessage {
  final String inReplyTo;
  final String delta;
  AgentChunk({required this.inReplyTo, required this.delta});

  factory AgentChunk.fromJson(Map<String, dynamic> j) => AgentChunk(
    inReplyTo: j['in_reply_to'] as String,
    delta: j['delta'] as String,
  );
}

class AgentDone extends ServerMessage {
  final String inReplyTo;
  final Usage? usage;
  AgentDone({required this.inReplyTo, this.usage});

  factory AgentDone.fromJson(Map<String, dynamic> j) => AgentDone(
    inReplyTo: j['in_reply_to'] as String,
    usage:
        j['usage'] != null
            ? Usage.fromJson(j['usage'] as Map<String, dynamic>)
            : null,
  );
}

class ToolRequest extends ServerMessage {
  final String toolCallId;
  final String tool;
  final dynamic args;
  ToolRequest({required this.toolCallId, required this.tool, required this.args});

  factory ToolRequest.fromJson(Map<String, dynamic> j) => ToolRequest(
    toolCallId: j['tool_call_id'] as String,
    tool: j['tool'] as String,
    args: j['args'],
  );
}

class ToolResult extends ServerMessage {
  final String toolCallId;
  final dynamic result;
  final String? error;
  ToolResult({required this.toolCallId, this.result, this.error});

  factory ToolResult.fromJson(Map<String, dynamic> j) => ToolResult(
    toolCallId: j['tool_call_id'] as String,
    result: j['result'],
    error: j['error'] as String?,
  );
}

class ErrorMessage extends ServerMessage {
  final String? inReplyTo;
  final String code;
  final String message;
  ErrorMessage({this.inReplyTo, required this.code, required this.message});

  factory ErrorMessage.fromJson(Map<String, dynamic> j) => ErrorMessage(
    inReplyTo: j['in_reply_to'] as String?,
    code: j['code'] as String,
    message: j['message'] as String,
  );
}

class Cancelled extends ServerMessage {
  final String inReplyTo;
  final String targetId;
  Cancelled({required this.inReplyTo, required this.targetId});

  factory Cancelled.fromJson(Map<String, dynamic> j) => Cancelled(
    inReplyTo: j['in_reply_to'] as String,
    targetId: j['target_id'] as String,
  );
}

class Pong extends ServerMessage {
  final String inReplyTo;
  Pong({required this.inReplyTo});

  factory Pong.fromJson(Map<String, dynamic> j) =>
      Pong(inReplyTo: j['in_reply_to'] as String);
}

/// Plan/27 Wave A — identifies the agent harness the paired PC is
/// running. Surfaced as a subtitle on the PiCard ("via Pi coding
/// agent"). Pi-extension is expected to publish this in `pair_ok`
/// (contract for the next pi-extension dispatch); the app falls back
/// to a sensible default when the field is absent so legacy Pis keep
/// working.
class PiHarness {
  final String name;
  final String version;
  const PiHarness({required this.name, required this.version});

  /// Default used when `pair_ok` omits `harness` (current
  /// pi-extension behaviour) and when migrating legacy PeerRecords.
  static const PiHarness piCodingAgentUnknown =
      PiHarness(name: 'Pi coding agent', version: '—');

  Map<String, dynamic> toJson() => {'name': name, 'version': version};

  static PiHarness fromJson(Map<String, dynamic> j) => PiHarness(
        name: (j['name'] as String?) ?? piCodingAgentUnknown.name,
        version: (j['version'] as String?) ?? piCodingAgentUnknown.version,
      );

  @override
  bool operator ==(Object other) =>
      other is PiHarness && other.name == name && other.version == version;

  @override
  int get hashCode => Object.hash(name, version);
}

class PairOk extends ServerMessage {
  final String inReplyTo;
  final String sessionName;
  /// Epoch-ms timestamp when the Pi started this session. The app caches
  /// it locally so a future `session_sync` can detect a Pi restart (value
  /// changed) and replace the cache instead of appending stale events.
  final int sessionStartedAt;
  /// Plan 17 fix — Pi-side room id (cwd-session) that confirmed this
  /// pair. The app persists this on the PeerRecord so subsequent
  /// reconnects can address the right (peer, room) directly without
  /// having to wait for subscribe_rooms / discovery. Legacy Pis that
  /// don't emit `room_id` fall back to `'main'`.
  final String roomId;
  /// Plan/27 Wave A — agent harness identification. `null` when the
  /// pi-extension hasn't been upgraded to publish it; consumers fall
  /// back to [PiHarness.piCodingAgentUnknown] so the UI never renders
  /// an empty subtitle.
  final PiHarness? harness;
  /// Plan/27 Wave A — hostname hint for the post-pair nickname modal.
  /// The pi-extension reports its OS hostname so the modal can
  /// pre-fill a sensible placeholder ("Mac do Jacob") instead of a
  /// generic "Pi". `null` on legacy Pis.
  final String? hostname;
  final List<String> capabilities;
  bool get supportsSignedInnerV1 => capabilities.contains('signed_inner_v1');
  PairOk({
    required this.inReplyTo,
    required this.sessionName,
    required this.sessionStartedAt,
    required this.roomId,
    this.harness,
    this.hostname,
    this.capabilities = const [],
  });

  factory PairOk.fromJson(Map<String, dynamic> j) {
    final harnessJson = j['harness'];
    final hostname = j['hostname'];
    final capabilitiesJson = j['capabilities'];
    final startedAt = j['session_started_at'];
    return PairOk(
      inReplyTo: j['in_reply_to'] as String,
      sessionName: j['session_name'] as String,
      // Legacy Pis (pre-session_sync) don't emit session_started_at.
      // The downstream caller treats `0` as "unknown" and skips the
      // restart-detection branch.
      sessionStartedAt: startedAt is num ? startedAt.toInt() : 0,
      // Backward-compat: pre-fix Pis don't emit room_id → use 'main'.
      // Callers that need to distinguish "Pi said main" from "Pi
      // omitted room" should peek at the raw JSON instead.
      roomId: (j['room_id'] as String?) ?? 'main',
      harness: harnessJson is Map<String, dynamic>
          ? PiHarness.fromJson(harnessJson)
          : null,
      hostname: hostname is String && hostname.isNotEmpty ? hostname : null,
      capabilities: capabilitiesJson is List
          ? capabilitiesJson.whereType<String>().toList(growable: false)
          : const [],
    );
  }
}

/// Mirror of user input typed directly in the Pi's terminal (or injected via
/// RPC). The Pi emits this so the app can show what was sent even though it
/// did not originate from the app's own [UserMessage] flow.
class UserInput extends ServerMessage {
  final String id;
  final String text;
  UserInput({required this.id, required this.text});

  factory UserInput.fromJson(Map<String, dynamic> j) => UserInput(
    id: j['id'] as String,
    text: j['text'] as String,
  );
}

/// Consolidated assistant reply, used only inside `session_history` events
/// (history dumps); real-time replies still flow as `agent_chunk` +
/// `agent_done`. May also arrive standalone for backfill — treated as a
/// final assistant message for the given `inReplyTo`.
class AgentMessage extends ServerMessage {
  final String inReplyTo;
  final String text;
  final Usage? usage;
  AgentMessage({required this.inReplyTo, required this.text, this.usage});

  factory AgentMessage.fromJson(Map<String, dynamic> j) => AgentMessage(
    inReplyTo: j['in_reply_to'] as String,
    text: j['text'] as String,
    usage: j['usage'] != null
        ? Usage.fromJson(j['usage'] as Map<String, dynamic>)
        : null,
  );
}

// ---------------------------------------------------------------------------
// SessionHistory + embedded event types
// ---------------------------------------------------------------------------

/// Reply to a `session_sync`. May arrive in batches; the final batch
/// sets `eos: true`. `truncated: true` indicates Pi had more events
/// than the requested `limit` and dropped the oldest — surfaced to
/// logs only (no UI affordance per plan/16 D1=B).
class SessionHistory extends ServerMessage {
  final String inReplyTo;
  final int sessionStartedAt;
  final List<SessionHistoryEvent> events;
  final bool eos;
  final bool truncated;
  SessionHistory({
    required this.inReplyTo,
    required this.sessionStartedAt,
    required this.events,
    required this.eos,
    this.truncated = false,
  });

  factory SessionHistory.fromJson(Map<String, dynamic> j) => SessionHistory(
    inReplyTo: j['in_reply_to'] as String,
    sessionStartedAt: (j['session_started_at'] as num).toInt(),
    events: (j['events'] as List<dynamic>)
        .map((e) => SessionHistoryEvent.fromJson(e as Map<String, dynamic>))
        .toList(),
    eos: j['eos'] as bool,
    // Tolerate absence during the protocol transition window.
    truncated: (j['truncated'] as bool?) ?? false,
  );
}

sealed class SessionHistoryEvent {
  final int ts;
  const SessionHistoryEvent({required this.ts});

  factory SessionHistoryEvent.fromJson(Map<String, dynamic> j) {
    final ts = (j['ts'] as num).toInt();
    return switch (j['type'] as String?) {
      'user_input' => UserInputEvt(
          ts: ts,
          id: j['id'] as String,
          text: j['text'] as String,
        ),
      'tool_request' => ToolRequestEvt(
          ts: ts,
          toolCallId: j['tool_call_id'] as String,
          tool: j['tool'] as String,
          args: j['args'],
        ),
      'tool_result' => ToolResultEvt(
          ts: ts,
          toolCallId: j['tool_call_id'] as String,
          result: j['result'],
          error: j['error'] as String?,
        ),
      'agent_message' => AgentMessageEvt(
          ts: ts,
          inReplyTo: j['in_reply_to'] as String,
          text: j['text'] as String,
        ),
      final t => throw UnsupportedTypeException(t ?? ''),
    };
  }
}

class UserInputEvt extends SessionHistoryEvent {
  final String id;
  final String text;
  const UserInputEvt({required super.ts, required this.id, required this.text});
}

class ToolRequestEvt extends SessionHistoryEvent {
  final String toolCallId;
  final String tool;
  final dynamic args;
  const ToolRequestEvt({
    required super.ts,
    required this.toolCallId,
    required this.tool,
    required this.args,
  });
}

class ToolResultEvt extends SessionHistoryEvent {
  final String toolCallId;
  final dynamic result;
  final String? error;
  const ToolResultEvt({
    required super.ts,
    required this.toolCallId,
    this.result,
    this.error,
  });
}

class AgentMessageEvt extends SessionHistoryEvent {
  final String inReplyTo;
  final String text;
  const AgentMessageEvt({
    required super.ts,
    required this.inReplyTo,
    required this.text,
  });
}

class PairError extends ServerMessage {
  final String inReplyTo;
  final String code;
  final String message;
  PairError({
    required this.inReplyTo,
    required this.code,
    required this.message,
  });

  factory PairError.fromJson(Map<String, dynamic> j) => PairError(
    inReplyTo: j['in_reply_to'] as String,
    code: j['code'] as String,
    message: j['message'] as String,
  );
}

/// Graceful disconnect notice sent by the Pi right before it closes the
/// channel (e.g. `/remote-pi stop`, session replaced, shutdown). The app
/// treats this as a terminal "Pi went offline" signal, stops the retry
/// loop, and surfaces a banner. Reconnect is manual.
enum ByeReason { peerStop, sessionReplaced, shutdown, unknown }

// ---------------------------------------------------------------------------
// Plan/28 — Replies for typed app actions.
//
// `action_ok` / `action_error` use the original `ActionName` so the app
// can demultiplex by intended action (no need to remember every
// in-flight request id). `models_list` is the reply to `list_models`
// and optionally echoes the model the Pi is using right now so the
// picker highlights the right row immediately.
// ---------------------------------------------------------------------------

class ActionOk extends ServerMessage {
  final String inReplyTo;
  final ActionName action;
  /// Raw wire string for `action` kept verbatim so a future Pi adds
  /// a new action without us silently dropping the ack.
  final String rawAction;
  ActionOk({
    required this.inReplyTo,
    required this.action,
    required this.rawAction,
  });

  factory ActionOk.fromJson(Map<String, dynamic> j) {
    final raw = (j['action'] as String?) ?? '';
    final parsed = ActionName.fromWire(raw);
    return ActionOk(
      inReplyTo: j['in_reply_to'] as String,
      action: parsed ?? ActionName.sessionCompact,
      rawAction: raw,
    );
  }
}

class ActionError extends ServerMessage {
  final String inReplyTo;
  final ActionName action;
  final String rawAction;
  final String error;
  ActionError({
    required this.inReplyTo,
    required this.action,
    required this.rawAction,
    required this.error,
  });

  factory ActionError.fromJson(Map<String, dynamic> j) {
    final raw = (j['action'] as String?) ?? '';
    final parsed = ActionName.fromWire(raw);
    return ActionError(
      inReplyTo: j['in_reply_to'] as String,
      action: parsed ?? ActionName.sessionCompact,
      rawAction: raw,
      error: (j['error'] as String?) ?? '',
    );
  }
}

class ModelsList extends ServerMessage {
  final String inReplyTo;
  final List<WireModel> models;
  /// Echoes the model the Pi is using right now (if it can be
  /// resolved). `null` is honest absence — the UI should fall back to
  /// the cached `model_select` event from the rooms layer.
  final WireModel? current;
  ModelsList({
    required this.inReplyTo,
    required this.models,
    this.current,
  });

  factory ModelsList.fromJson(Map<String, dynamic> j) {
    final list = (j['models'] as List<dynamic>? ?? const <dynamic>[])
        .map((e) => WireModel.fromJson(e as Map<String, dynamic>))
        .toList();
    final cur = j['current'];
    return ModelsList(
      inReplyTo: j['in_reply_to'] as String,
      models: list,
      current: cur is Map<String, dynamic> ? WireModel.fromJson(cur) : null,
    );
  }
}

class Bye extends ServerMessage {
  final ByeReason reason;
  /// Raw wire value (kept for logging/debugging if the enum mapping turns
  /// it into [ByeReason.unknown]).
  final String rawReason;
  Bye({required this.reason, required this.rawReason});

  factory Bye.fromJson(Map<String, dynamic> j) {
    final raw = (j['reason'] as String?) ?? '';
    return Bye(reason: _parseReason(raw), rawReason: raw);
  }

  static ByeReason _parseReason(String s) => switch (s) {
    'peer_stop' => ByeReason.peerStop,
    'session_replaced' => ByeReason.sessionReplaced,
    'shutdown' => ByeReason.shutdown,
    _ => ByeReason.unknown,
  };
}
