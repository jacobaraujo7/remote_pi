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
  _T({required this.sent, required this.recv});

  @override
  Future<void> send(Uint8List data) async => sent.add(data);

  @override
  Future<Uint8List> receive() => recv.next();

  @override
  Future<void> close() async {}
}

Future<void> main() async {
  group('PlainPeerChannel signed_inner_v1', () {
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

      final frame = jsonDecode(utf8.decode(await sent.next())) as Map<String, dynamic>;
      expect(frame['type'], 'signed_inner_v1');
      expect(frame['recipient_pk'], piPk);
      expect(frame['room_id'], 'room-1');
      expect(frame['payload_type'], 'ping');
      expect(frame['payload'], {'type': 'ping', 'id': 'p1'});
    });

    test('unwraps signed inbound and drops unsigned/replayed frames in strict mode', () async {
      final appKey = await Ed25519().newKeyPairFromSeed(Uint8List(32)..[0] = 3);
      final piKey = await Ed25519().newKeyPairFromSeed(Uint8List(32)..[0] = 4);
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
      final sub = channel.serverMessages.listen(messages.add);

      recv.add(Uint8List.fromList(utf8.encode(jsonEncode({'type': 'pong', 'in_reply_to': 'unsigned'}))));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(messages, isEmpty);

      final signed = await signInnerV1(
        payload: {'type': 'pong', 'in_reply_to': 'p1'},
        senderKey: piKey,
        recipientPk: appPk,
        roomId: 'room-1',
        now: DateTime.now().millisecondsSinceEpoch,
        msgId: 'msg-1',
      );
      recv.add(Uint8List.fromList(utf8.encode(jsonEncode(signed))));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(messages.single, isA<Pong>());
      expect((messages.single as Pong).inReplyTo, 'p1');

      recv.add(Uint8List.fromList(utf8.encode(jsonEncode(signed))));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(messages, hasLength(1), reason: 'replay is dropped');

      await sub.cancel();
      await channel.close();
    });
  });
}
