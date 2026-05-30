// PlainPeerChannel — protocol message channel without E2E cipher.
//
// Wraps a connected PeerTransport. After pairing, use this to exchange
// ClientMessage / ServerMessage with the Pi extension.
//
//   send(ClientMessage)   → JSON          → transport.send()
//   serverMessages stream ← transport.receive() → JSON → ServerMessage

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/epk_encoding.dart';
import 'package:app/pairing/pair_request_flow.dart';
import 'package:app/protocol/signed_inner.dart';
// ControlInbound + IControlLink come from these.
import 'package:app/protocol/protocol.dart';
import 'package:cryptography/cryptography.dart';

class PeerChannelError implements Exception {
  final String message;
  const PeerChannelError(this.message);

  @override
  String toString() => 'PeerChannelError: $message';
}

class PlainPeerChannel implements IChannel, IControlLink {
  final PeerTransport _transport;

  final _controller = StreamController<ServerMessage>.broadcast();
  final SimpleKeyPair? _signingKey;
  final String? _expectedRemotePubkey;
  final bool _requireSigned;
  final SignedInnerReplayCache _replayCache;
  String? _activeRoomId;
  bool _started = false;
  bool _closed = false;

  PlainPeerChannel({
    required PeerTransport transport,
    SimpleKeyPair? signingKey,
    String? expectedRemotePubkey,
    String? roomId,
    bool requireSigned = true,
    SignedInnerReplayCache? replayCache,
  })  : _transport = transport,
        _signingKey = signingKey,
        _expectedRemotePubkey = expectedRemotePubkey == null
            ? null
            : toStandardB64(expectedRemotePubkey),
        _activeRoomId = roomId,
        _requireSigned = requireSigned,
        _replayCache = replayCache ?? SignedInnerReplayCache();

  // ---- IControlLink — forwards to the underlying transport when it
  //      supports raw control frames (production: WsTransport). For
  //      non-WS transports (tests / in-memory), returns an empty stream
  //      and silently drops outbound control frames.
  @override
  Stream<ControlInbound> get controlFrames {
    final t = _transport;
    if (t is IControlLink) return (t as IControlLink).controlFrames;
    return const Stream.empty();
  }

  @override
  void sendControl(Map<String, dynamic> json) {
    final t = _transport;
    if (t is IControlLink) (t as IControlLink).sendControl(json);
  }

  /// Plan 17 — propagate the active Pi-side room to the underlying
  /// transport so subsequent `send`s carry the right outer `room` field.
  /// No-op when the transport doesn't support it (in-memory test fakes).
  void setActiveRoom(String roomId) {
    _activeRoomId = roomId;
    final t = _transport;
    try {
      (t as dynamic).setActiveRoom(roomId);
    } catch (_) {
      // Non-WS transports don't track rooms — fine to ignore.
    }
  }

  @override
  Stream<ServerMessage> get serverMessages {
    if (!_started) {
      _started = true;
      _receiveLoop();
    }
    return _controller.stream;
  }

  @override
  Future<void> send(ClientMessage msg) async {
    final payload = msg.toJson();
    final signingKey = _signingKey;
    final expectedRemote = _expectedRemotePubkey;
    final roomId = _activeRoomId;
    final Object wire = signingKey != null && expectedRemote != null && roomId != null
        ? await signInnerV1(
            payload: payload,
            senderKey: signingKey,
            recipientPk: expectedRemote,
            roomId: roomId,
          )
        : payload;
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(wire)));
    await _transport.send(bytes);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _transport.close();
    if (!_controller.isClosed) await _controller.close();
  }

  Future<void> _receiveLoop() async {
    try {
      while (!_closed) {
        final bytes = await _transport.receive();
        await _handleFrame(bytes);
      }
    } catch (_) {
      if (!_controller.isClosed) await _controller.close();
    }
  }

  Future<void> _handleFrame(Uint8List bytes) async {
    try {
      final decoded = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      Map<String, dynamic> payload = decoded;
      if (isSignedInnerV1(decoded)) {
        final signingKey = _signingKey;
        final expectedRemote = _expectedRemotePubkey;
        final roomId = _activeRoomId;
        if (signingKey == null || expectedRemote == null || roomId == null) return;
        final localPk = base64.encode((await signingKey.extractPublicKey()).bytes);
        final verified = await verifyInnerV1(
          frame: decoded,
          expectedSenderPk: expectedRemote,
          expectedRecipientPk: localPk,
          expectedRoomId: roomId,
          replay: _replayCache,
        );
        if (verified == null) return;
        payload = verified;
      } else if (_signingKey != null && _requireSigned) {
        return;
      }
      final msg = ServerMessage.fromJson(payload);
      if (!_controller.isClosed) _controller.add(msg);
    } on UnsupportedTypeException {
      // Forward-compat: surface unknown server types as ErrorMessage.
      if (!_controller.isClosed) {
        _controller.add(
          ErrorMessage(code: 'unsupported_type', message: 'unknown server type'),
        );
      }
    } catch (_) {
      // Malformed frame — drop silently. Previous diagnostic logging
      // for cast / decode errors lived here; we trust upstream codecs
      // now that the channel pipeline is stable.
    }
  }
}
