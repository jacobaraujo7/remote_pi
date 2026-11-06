// Session domain model — chat message variants + streaming buffer.
// Lives in domain/ → no Flutter, no network, no storage.

// ---------------------------------------------------------------------------
// ChatMessage — sealed union of message variants in the conversation history
// ---------------------------------------------------------------------------

sealed class ChatMessage {
  final String id;
  const ChatMessage({required this.id});
}

/// Plan/24-fix-app-source-of-truth: every UserMsg is tagged with the
/// lifecycle stage of its rebroadcast. `pending` = sent over WS but Pi
/// hasn't echoed it back yet; `confirmed` = Pi rebroadcast it (or it
/// came from `session_history` / another device's echo); `failed` =
/// 15s elapsed without echo, user can retry.
///
/// Default is `confirmed` for back-compat — every persisted UserMsg
/// from before this fix was effectively confirmed (the Pi wasn't
/// rebroadcasting then, but the local cache treated it as
/// authoritative).
enum UserMsgStatus { pending, confirmed, failed }

/// Plan/30 — an image attached to a user message. Carries the JPEG bytes
/// base64-encoded plus its mime type, mirroring the SDK's `ImageContent`.
/// Bytes always travel inline (decision #8: history replays the image too),
/// so the bubble can render straight from [data] with no extra round-trip.
class MessageImage {
  /// Base64-encoded image bytes (no data-URI prefix).
  final String data;

  /// Mime type, e.g. `image/jpeg`.
  final String mime;

  const MessageImage({required this.data, required this.mime});

  @override
  bool operator ==(Object other) =>
      other is MessageImage && other.data == data && other.mime == mime;

  @override
  int get hashCode => Object.hash(data, mime);
}

/// Android-owned queued follow-up shown above the composer. Protocol-free
/// domain value; SyncService maps wire items into this shape.
class QueuedMsg {
  final String id;
  final String text;
  final bool editable;
  final DateTime createdAt;

  const QueuedMsg({
    required this.id,
    required this.text,
    required this.editable,
    required this.createdAt,
  });

  @override
  bool operator ==(Object other) =>
      other is QueuedMsg &&
      other.id == id &&
      other.text == text &&
      other.editable == editable &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, text, editable, createdAt);
}

class UserMsg extends ChatMessage {
  final String text;
  final UserMsgStatus status;
  final bool steering;

  /// Plan/30 — optional attached image (one max). `null` for text-only
  /// messages, which is every message before this feature.
  final MessageImage? image;

  const UserMsg({
    required super.id,
    required this.text,
    this.status = UserMsgStatus.confirmed,
    this.steering = false,
    this.image,
  });

  UserMsg copyWith({UserMsgStatus? status, bool? steering}) => UserMsg(
    id: id,
    text: text,
    status: status ?? this.status,
    steering: steering ?? this.steering,
    image: image,
  );

  @override
  bool operator ==(Object other) =>
      other is UserMsg &&
      other.id == id &&
      other.text == text &&
      other.status == status &&
      other.steering == steering &&
      other.image == image;

  @override
  int get hashCode => Object.hash(id, text, status, steering, image);
}

class AssistantMsg extends ChatMessage {
  final String text;
  const AssistantMsg({required super.id, required this.text});

  @override
  bool operator ==(Object other) =>
      other is AssistantMsg && other.id == id && other.text == text;

  @override
  int get hashCode => Object.hash(id, text);
}

class ToolEvent extends ChatMessage {
  final String toolCallId;
  final String tool;
  final dynamic args;
  final ToolEventStatus status;
  final dynamic result;
  final String? error;
  final Map<String, dynamic>? details;

  const ToolEvent({
    required super.id,
    required this.toolCallId,
    required this.tool,
    required this.args,
    this.status = ToolEventStatus.pending,
    this.result,
    this.error,
    this.details,
  });

  ToolEvent copyWith({
    ToolEventStatus? status,
    dynamic result,
    String? error,
    Map<String, dynamic>? details,
  }) => ToolEvent(
    id: id,
    toolCallId: toolCallId,
    tool: tool,
    args: args,
    status: status ?? this.status,
    result: result ?? this.result,
    error: error ?? this.error,
    details: details ?? this.details,
  );

  @override
  bool operator ==(Object other) =>
      other is ToolEvent &&
      other.id == id &&
      other.toolCallId == toolCallId &&
      other.status == status &&
      other.result == result &&
      other.error == error &&
      other.details == details;

  @override
  int get hashCode =>
      Object.hash(id, toolCallId, status, result, error, details);
}

/// Plan/32 — `denied` = the user/SDK declined the tool; `failed` = the tool
/// ran but errored (a distinct, red outcome). `expired` = approval timed out.
enum ToolEventStatus { pending, allowed, denied, expired, completed, failed }

/// Plan/32 — a context-compaction marker rendered as a system bubble
/// (distinct from user/assistant). [summary] is the Pi's recap of the
/// compacted thread; [tokensBefore] is the token count reclaimed (null when
/// the Pi didn't report it).
class CompactionMsg extends ChatMessage {
  final String summary;
  final int? tokensBefore;
  const CompactionMsg({
    required super.id,
    required this.summary,
    this.tokensBefore,
  });

  @override
  bool operator ==(Object other) =>
      other is CompactionMsg &&
      other.id == id &&
      other.summary == summary &&
      other.tokensBefore == tokensBefore;

  @override
  int get hashCode => Object.hash(id, summary, tokensBefore);
}

// ---------------------------------------------------------------------------
// StreamingMessage — accumulated deltas while the assistant is typing
// ---------------------------------------------------------------------------

class StreamingMessage {
  final String inReplyTo; // id of the UserMsg being answered
  final String buffer;

  const StreamingMessage({required this.inReplyTo, this.buffer = ''});

  StreamingMessage appendDelta(String delta) =>
      StreamingMessage(inReplyTo: inReplyTo, buffer: buffer + delta);

  @override
  bool operator ==(Object other) =>
      other is StreamingMessage &&
      other.inReplyTo == inReplyTo &&
      other.buffer == buffer;

  @override
  int get hashCode => Object.hash(inReplyTo, buffer);
}
