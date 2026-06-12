import 'package:app/domain/session_state.dart';

/// Plan/31 — one persisted chat message (row-granular SSOT). Stored in the
/// per-session `msgs:<epk>:<roomId>` box, keyed by [seq]. Maps to the domain
/// [ChatMessage] the UI widgets already render.
enum MsgRole { user, assistant, tool, compaction, askUser }

class MessageRecord {
  /// Protocol id — the dedupe key (optimistic send ↔ Pi echo share it).
  final String id;

  /// Monotonic order within the session (the box key).
  final int seq;
  final MsgRole role;
  final String text;

  /// Plan/30 — attached image (user messages only).
  final MessageImage? image;

  /// Tool request+result collapsed into one row (tool messages only).
  final ToolEventData? tool;

  /// Ask-user prompt card persisted as an inline row.
  final AskUserPromptData? askUser;
  final DateTime ts;

  /// Optimistic: sent locally, not yet echoed by the Pi.
  final bool pending;

  /// Plan/32 — tokens reclaimed by a compaction (compaction rows only).
  final int? tokensBefore;

  const MessageRecord({
    required this.id,
    required this.seq,
    required this.role,
    this.text = '',
    this.image,
    this.tool,
    this.askUser,
    required this.ts,
    this.pending = false,
    this.tokensBefore,
  });

  MessageRecord copyWith({
    int? seq,
    String? text,
    MessageImage? image,
    ToolEventData? tool,
    AskUserPromptData? askUser,
    bool? pending,
  }) => MessageRecord(
    id: id,
    seq: seq ?? this.seq,
    role: role,
    text: text ?? this.text,
    image: image ?? this.image,
    tool: tool ?? this.tool,
    askUser: askUser ?? this.askUser,
    ts: ts,
    pending: pending ?? this.pending,
    tokensBefore: tokensBefore,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'seq': seq,
    'role': role.name,
    'text': text,
    if (image != null) 'image': {'data': image!.data, 'mime': image!.mime},
    if (tool != null) 'tool': tool!.toJson(),
    if (askUser != null) 'ask_user': askUser!.toJson(),
    'ts': ts.millisecondsSinceEpoch,
    'pending': pending,
    if (tokensBefore != null) 'tokens_before': tokensBefore,
  };

  factory MessageRecord.fromJson(Map<String, dynamic> j) {
    final imageRaw = j['image'];
    final toolRaw = j['tool'];
    final askUserRaw = j['ask_user'];
    return MessageRecord(
      id: j['id'] as String,
      seq: (j['seq'] as num).toInt(),
      role: MsgRole.values.firstWhere(
        (r) => r.name == j['role'],
        orElse: () => MsgRole.assistant,
      ),
      text: (j['text'] as String?) ?? '',
      image: imageRaw is Map
          ? MessageImage(
              data: imageRaw['data'] as String,
              mime: imageRaw['mime'] as String,
            )
          : null,
      tool: toolRaw is Map
          ? ToolEventData.fromJson(toolRaw.cast<String, dynamic>())
          : null,
      askUser: askUserRaw is Map
          ? AskUserPromptData.fromJson(askUserRaw.cast<String, dynamic>())
          : null,
      ts: DateTime.fromMillisecondsSinceEpoch((j['ts'] as num).toInt()),
      pending: (j['pending'] as bool?) ?? false,
      tokensBefore: (j['tokens_before'] as num?)?.toInt(),
    );
  }

  /// Project to the domain [ChatMessage] the chat widgets render.
  ChatMessage toChatMessage() {
    switch (role) {
      case MsgRole.user:
        return UserMsg(
          id: id,
          text: text,
          status: pending ? UserMsgStatus.pending : UserMsgStatus.confirmed,
          image: image,
        );
      case MsgRole.assistant:
        return AssistantMsg(id: id, text: text);
      case MsgRole.tool:
        final t = tool;
        return ToolEvent(
          id: id,
          toolCallId: t?.toolCallId ?? id,
          tool: t?.tool ?? 'unknown',
          args: t?.args,
          status: t?.status ?? ToolEventStatus.pending,
          result: t?.result,
          error: t?.error,
        );
      case MsgRole.compaction:
        return CompactionMsg(id: id, summary: text, tokensBefore: tokensBefore);
      case MsgRole.askUser:
        final p = askUser;
        return AskUserPromptMsg(
          id: id,
          question: p?.question ?? '',
          context: p?.context ?? '',
          options: p?.options ?? const [],
          allowMultiple: p?.allowMultiple ?? false,
          allowFreeform: p?.allowFreeform ?? false,
          allowComment: p?.allowComment ?? false,
          resolved: p?.resolved ?? false,
          cancelled: p?.cancelled ?? false,
          answerLabel: p?.answerLabel,
        );
    }
  }
}

/// Tool request + result collapsed into a single persisted shape.
class ToolEventData {
  final String toolCallId;
  final String tool;
  final dynamic args;
  final ToolEventStatus status;
  final dynamic result;
  final String? error;

  const ToolEventData({
    required this.toolCallId,
    required this.tool,
    this.args,
    this.status = ToolEventStatus.pending,
    this.result,
    this.error,
  });

  ToolEventData copyWith({
    ToolEventStatus? status,
    dynamic result,
    String? error,
  }) => ToolEventData(
    toolCallId: toolCallId,
    tool: tool,
    args: args,
    status: status ?? this.status,
    result: result ?? this.result,
    error: error ?? this.error,
  );

  Map<String, dynamic> toJson() => {
    'tool_call_id': toolCallId,
    'tool': tool,
    'args': args,
    'status': status.name,
    'result': result,
    'error': error,
  };

  factory ToolEventData.fromJson(Map<String, dynamic> j) => ToolEventData(
    toolCallId: j['tool_call_id'] as String,
    tool: (j['tool'] as String?) ?? 'unknown',
    args: j['args'],
    status: ToolEventStatus.values.firstWhere(
      (s) => s.name == j['status'],
      orElse: () => ToolEventStatus.completed,
    ),
    result: j['result'],
    error: j['error'] as String?,
  );
}

class AskUserPromptData {
  final String question;
  final String context;
  final List<AskUserPromptChoice> options;
  final bool allowMultiple;
  final bool allowFreeform;
  final bool allowComment;
  final bool resolved;
  final bool cancelled;
  final String? answerLabel;

  const AskUserPromptData({
    required this.question,
    required this.context,
    required this.options,
    required this.allowMultiple,
    required this.allowFreeform,
    required this.allowComment,
    this.resolved = false,
    this.cancelled = false,
    this.answerLabel,
  });

  AskUserPromptData copyWith({
    String? question,
    String? context,
    List<AskUserPromptChoice>? options,
    bool? allowMultiple,
    bool? allowFreeform,
    bool? allowComment,
    bool? resolved,
    bool? cancelled,
    Object? answerLabel = _askUserUnset,
  }) => AskUserPromptData(
    question: question ?? this.question,
    context: context ?? this.context,
    options: options ?? this.options,
    allowMultiple: allowMultiple ?? this.allowMultiple,
    allowFreeform: allowFreeform ?? this.allowFreeform,
    allowComment: allowComment ?? this.allowComment,
    resolved: resolved ?? this.resolved,
    cancelled: cancelled ?? this.cancelled,
    answerLabel: identical(answerLabel, _askUserUnset)
        ? this.answerLabel
        : answerLabel as String?,
  );

  Map<String, dynamic> toJson() => {
    'question': question,
    'context': context,
    'options': [
      for (final option in options)
        {
          'title': option.title,
          if (option.description != null) 'description': option.description,
        },
    ],
    'allow_multiple': allowMultiple,
    'allow_freeform': allowFreeform,
    'allow_comment': allowComment,
    'resolved': resolved,
    'cancelled': cancelled,
    if (answerLabel != null) 'answer_label': answerLabel,
  };

  factory AskUserPromptData.fromJson(Map<String, dynamic> j) {
    final rawOptions = j['options'];
    final opts = <AskUserPromptChoice>[];
    if (rawOptions is List) {
      for (final raw in rawOptions) {
        if (raw is Map<String, dynamic>) {
          opts.add(
            AskUserPromptChoice(
              title: (raw['title'] as String?) ?? '',
              description: raw['description'] as String?,
            ),
          );
        }
      }
    }

    return AskUserPromptData(
      question: (j['question'] as String?) ?? '',
      context: (j['context'] as String?) ?? '',
      options: opts,
      allowMultiple: j['allow_multiple'] == true,
      allowFreeform: j['allow_freeform'] == true,
      allowComment: j['allow_comment'] == true,
      resolved: j['resolved'] == true,
      cancelled: j['cancelled'] == true,
      answerLabel: j['answer_label'] as String?,
    );
  }

  static const _askUserUnset = Object();
}
