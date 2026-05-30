import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app/data/transport/epk_encoding.dart';
import 'package:app/data/transport/peer_channel.dart';
import 'package:app/pairing/pair_request_flow.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/protocol/signed_inner.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

class _Q {
  final items = <Uint8List>[];
  final waiters = <Completer<Uint8List>>[];

  void add(Uint8List data) {
    if (waiters.isNotEmpty) {
      waiters.removeAt(0).complete(data);
    } else {
      items.add(data);
    }
  }

  Future<Uint8List> next() {
    if (items.isNotEmpty) return Future.value(items.removeAt(0));
    final c = Completer<Uint8List>();
    waiters.add(c);
    return c.future;
  }
}

class _T implements PeerTransport {
  final _Q sent;
  final _Q recv;
  String activeRoom = 'main';
  _T({required this.sent, required this.recv});

  void setActiveRoom(String roomId) {
    activeRoom = roomId;
  }

  @override
  Future<void> send(Uint8List data) async => sent.add(data);

  @override
  Future<Uint8List> receive() => recv.next();

  @override
  Future<void> close() async {}
}

Future<void> main() async {
  group('PlainPeerChannel signed_inner_v1', () {
    test('propagates initial room into transport', () async {
      final appKey = await Ed25519().newKeyPairFromSeed(Uint8List(32)..[0] = 9);
      final piKey = await Ed25519().newKeyPairFromSeed(Uint8List(32)..[0] = 10);
      final piPk = base64.encode((await piKey.extractPublicKey()).bytes);
      final transport = _T(sent: _Q(), recv: _Q());

      final channel = PlainPeerChannel(
        transport: transport,
        signingKey: appKey,
        expectedRemotePubkey: piPk,
        roomId: 'room-ctor',
        requireSigned: true,
      );

      expect(transport.activeRoom, 'room-ctor');
      await channel.close();
    });

    test('wraps outbound ClientMessage when negotiated', () async {
      final appKey = await Ed25519().newKeyPairFromSeed(Uint8List(32)..[0] = 1);
      final piKey = await Ed25519().newKeyPairFromSeed(Uint8List(32)..[0] = 2);
      final piPk = base64.encode((await piKey.extractPublicKey()).bytes);
      final sent = _Q();
      final recv = _Q();
      final channel = PlainPeerChannel(
        transport: _T(sent: sent, recv: recv),
        signingKey: appKey,
        expectedRemotePubkey: toAppEpk(piPk),
        roomId: 'room-1',
        requireSigned: true,
      );

      await channel.send(Ping(id: 'p1'));

      final frame =
          jsonDecode(utf8.decode(await sent.next())) as Map<String, dynamic>;
      expect(frame['type'], 'signed_inner_v1');
      expect(frame['recipient_pk'], piPk);
      expect(frame['room_id'], 'room-1');
      expect(frame['payload_type'], 'ping');
      expect(frame['payload'], {'type': 'ping', 'id': 'p1'});
    });

    test(
      'unwraps signed inbound and drops unsigned/replayed frames in strict mode',
      () async {
        final appKey = await Ed25519().newKeyPairFromSeed(
          Uint8List(32)..[0] = 3,
        );
        final piKey = await Ed25519().newKeyPairFromSeed(
          Uint8List(32)..[0] = 4,
        );
        final appPk = base64.encode((await appKey.extractPublicKey()).bytes);
        final piPk = base64.encode((await piKey.extractPublicKey()).bytes);
        final sent = _Q();
        final recv = _Q();
        final channel = PlainPeerChannel(
          transport: _T(sent: sent, recv: recv),
          signingKey: appKey,
          expectedRemotePubkey: piPk,
          roomId: 'room-1',
          requireSigned: true,
        );
        final messages = <ServerMessage>[];
        Completer<ServerMessage>? nextMessage;
        final sub = channel.serverMessages.listen((msg) {
          messages.add(msg);
          nextMessage?.complete(msg);
          nextMessage = null;
        });
        Future<ServerMessage> waitNextMessage() {
          final c = Completer<ServerMessage>();
          nextMessage = c;
          return c.future.timeout(const Duration(seconds: 1));
        }

        final signed = await signInnerV1(
          payload: {'type': 'pong', 'in_reply_to': 'p1'},
          senderKey: piKey,
          recipientPk: appPk,
          roomId: 'room-1',
          now: DateTime.now().millisecondsSinceEpoch,
          msgId: 'msg-1',
        );
        final first = waitNextMessage();
        recv.add(
          Uint8List.fromList(
            utf8.encode(
              jsonEncode({'type': 'pong', 'in_reply_to': 'unsigned'}),
            ),
          ),
        );
        recv.add(Uint8List.fromList(utf8.encode(jsonEncode(signed))));
        final firstMsg = await first;
        expect(firstMsg, isA<Pong>());
        expect((firstMsg as Pong).inReplyTo, 'p1');
        expect(messages, hasLength(1), reason: 'unsigned frame is dropped');

        final signed2 = await signInnerV1(
          payload: {'type': 'pong', 'in_reply_to': 'p2'},
          senderKey: piKey,
          recipientPk: appPk,
          roomId: 'room-1',
          now: DateTime.now().millisecondsSinceEpoch,
          msgId: 'msg-2',
        );
        final second = waitNextMessage();
        recv.add(Uint8List.fromList(utf8.encode(jsonEncode(signed))));
        recv.add(Uint8List.fromList(utf8.encode(jsonEncode(signed2))));
        final secondMsg = await second;
        expect(secondMsg, isA<Pong>());
        expect((secondMsg as Pong).inReplyTo, 'p2');
        expect(messages, hasLength(2), reason: 'replay is dropped');

        await sub.cancel();
        await channel.close();
      },
    );
  });
}
