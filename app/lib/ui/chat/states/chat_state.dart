import 'package:app/domain/session_state.dart';
import 'package:app/protocol/protocol.dart';

// Sealed state for ChatViewModel.
// Switch exhaustively in ChatPage.build().

sealed class ChatState {
  const ChatState();
}

// No peer paired yet — show QR scanner redirect.
class ChatNoPeer extends ChatState {
  const ChatNoPeer();
}

// Establishing connection after boot or reconnect.
class ChatConnecting extends ChatState {
  const ChatConnecting();
}

// Connected and ready.
class ChatReady extends ChatState {
  final List<ChatMessage> messages;
  final StreamingMessage? streaming;
  final bool isOffline; // true → input disabled, banner visible
  // True once the Mac signalled this device is no longer in peers.json
  // (relay returned an `unknown_peer` error). Stays true until the user
  // re-pairs or revokes; suppresses input and surfaces a re-pair banner.
  final bool pairingRevoked;
  // Set when the Pi sent a `bye` (graceful disconnect). Stops retry,
  // shows banner offering manual reconnect. `peerOfflineReason` is the
  // raw wire reason (peer_stop / session_replaced / shutdown / …).
  final String? peerOfflineReason;
  /// Live relay-reported presence of the active peer. When the peer is
  /// [PresenceOffline] the chat enters read-only mode (history visible,
  /// input disabled). Defaults to [PresenceUnknown] until the relay
  /// reports.
  final PresenceState peerPresence;

  /// Plan/32 — whether the room this chat is viewing has an in-flight
  /// agent turn (drives the working pill + input-lock + stop button).
  /// Part of the state identity so a relay `meta.working` flip (which is
  /// per-room, like Home) actually triggers a rebuild even when nothing
  /// else changed. See [ChatViewModel.isWorking].
  final bool isWorking;
  final List<QueuedMsg> queuedMessages;

  /// Plan/51 — an interactive extension_ui_request (ask_user via pi-ask)
  /// awaiting an answer. Non-null → the chat renders a full-screen modal.
  /// Cleared on submit/cancel/completed. Identity compared (the ViewModel
  /// reuses the same instance across recomputes until it changes).
  final ExtensionUiRequest? pendingUiRequest;

  /// Plan/51 — last submit-result error for [pendingUiRequest] (null when none
  /// or resolved). Shown in the modal so the user can retry instead of hitting a
  /// dead end when pi-ask rejects an answer.
  final String? pendingUiError;

  String? get queuedText =>
      queuedMessages.isEmpty ? null : queuedMessages.first.text;

  const ChatReady({
    required this.messages,
    this.streaming,
    this.isOffline = false,
    this.pairingRevoked = false,
    this.peerOfflineReason,
    this.peerPresence = const PresenceUnknown(),
    this.isWorking = false,
    this.queuedMessages = const [],
    this.pendingUiRequest,
    this.pendingUiError,
  });

  ChatReady copyWith({
    List<ChatMessage>? messages,
    StreamingMessage? streaming,
    bool? isOffline,
    bool? pairingRevoked,
    String? peerOfflineReason,
    PresenceState? peerPresence,
    bool? isWorking,
    List<QueuedMsg>? queuedMessages,
    bool clearStreaming = false,
    bool clearPeerOffline = false,
    bool clearQueuedMessages = false,
    ExtensionUiRequest? pendingUiRequest,
    bool clearPendingUiRequest = false,
    String? pendingUiError,
    bool clearPendingUiError = false,
  }) =>
      ChatReady(
        messages: messages ?? this.messages,
        streaming: clearStreaming ? null : (streaming ?? this.streaming),
        isOffline: isOffline ?? this.isOffline,
        pairingRevoked: pairingRevoked ?? this.pairingRevoked,
        peerOfflineReason: clearPeerOffline
            ? null
            : (peerOfflineReason ?? this.peerOfflineReason),
        peerPresence: peerPresence ?? this.peerPresence,
        isWorking: isWorking ?? this.isWorking,
        queuedMessages: clearQueuedMessages
            ? const []
            : (queuedMessages ?? this.queuedMessages),
        pendingUiRequest: clearPendingUiRequest
            ? null
            : (pendingUiRequest ?? this.pendingUiRequest),
        pendingUiError: clearPendingUiError
            ? null
            : (pendingUiError ?? this.pendingUiError),
      );

  @override
  bool operator ==(Object other) =>
      other is ChatReady &&
      other.messages == messages &&
      other.streaming == streaming &&
      other.isOffline == isOffline &&
      other.pairingRevoked == pairingRevoked &&
      other.peerOfflineReason == peerOfflineReason &&
      other.peerPresence.runtimeType == peerPresence.runtimeType &&
      other.isWorking == isWorking &&
      other.queuedMessages == queuedMessages &&
      other.pendingUiRequest == pendingUiRequest &&
      other.pendingUiError == pendingUiError;

  @override
  int get hashCode => Object.hash(
        messages,
        streaming,
        isOffline,
        pairingRevoked,
        peerOfflineReason,
        peerPresence.runtimeType,
        isWorking,
        queuedMessages,
        pendingUiRequest,
        pendingUiError,
      );
}

// Permanent offline — must re-pair.
class ChatFatalError extends ChatState {
  final String message;
  const ChatFatalError(this.message);

  @override
  bool operator ==(Object other) =>
      other is ChatFatalError && other.message == message;

  @override
  int get hashCode => message.hashCode;
}
