import 'dart:convert';
import 'dart:typed_data';

import 'package:app/protocol/signed_inner.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> main() async {
  group('signed_inner_v1', () {
    test('canonicalSignedInnerV1 is deterministic and excludes sig', () {
      final canonical = canonicalSignedInnerV1({
        'type': 'signed_inner_v1',
        'sender_pk': 'sender',
        'recipient_pk': 'recipient',
        'room_id': 'room-1',
        'msg_id': 'msg-1',
        'issued_at': 1,
        'payload_type': 'tool_request',
        'payload': {
          'z': 1,
          'type': 'tool_request',
          'args': {'b': true, 'a': false},
        },
        'sig': 'ignored',
      });
      expect(
        canonical,
        '{"type":"signed_inner_v1","sender_pk":"sender","recipient_pk":"recipient",'
        '"room_id":"room-1","msg_id":"msg-1","issued_at":1,"payload_type":"tool_request",'
        '"payload":{"args":{"a":false,"b":true},"type":"tool_request","z":1}}',
      );
    });

    test('cross-runtime vector stays stable and verifies', () async {
      const senderPk = 'ebVWLo/mVPlAeLES6KmLp5AfhTrmlb7X4OORC60ElmQ=';
      const recipientPk = 'ZWZnaGlqa2xtbm9wcXJzdHV2d3h5ent8fX5/gIGCg4Q=';
      final frame = <String, dynamic>{
        'type': 'signed_inner_v1',
        'sender_pk': senderPk,
        'recipient_pk': recipientPk,
        'room_id': 'room-vector',
        'msg_id': 'msg-vector',
        'issued_at': 1700000000123,
        'payload_type': 'user_message',
        'payload': {
          'type': 'user_message',
          'id': 'u-vector',
          'text': 'hello',
          'nested': {'b': 2, 'a': 1},
        },
        'sig': 'GxWRHj92N2l5IW1ApzmyE+5cfeWJAoLRoaqRhC5M40aV1rW13GYQ4pLI0ZMcIvbgOsfQwvwpMyQ4F/A972LxCA==',
      };

      expect(
        canonicalSignedInnerV1(frame),
        '{"type":"signed_inner_v1","sender_pk":"ebVWLo/mVPlAeLES6KmLp5AfhTrmlb7X4OORC60ElmQ=",'
        '"recipient_pk":"ZWZnaGlqa2xtbm9wcXJzdHV2d3h5ent8fX5/gIGCg4Q=","room_id":"room-vector",'
        '"msg_id":"msg-vector","issued_at":1700000000123,"payload_type":"user_message",'
        '"payload":{"id":"u-vector","nested":{"a":1,"b":2},"text":"hello","type":"user_message"}}',
      );
      expect(
        await verifyInnerV1(
          frame: frame,
          expectedSenderPk: senderPk,
          expectedRecipientPk: recipientPk,
          expectedRoomId: 'room-vector',
          replay: SignedInnerReplayCache(),
          now: 1700000000200,
        ),
        {
          'type': 'user_message',
          'id': 'u-vector',
          'text': 'hello',
          'nested': {'b': 2, 'a': 1},
        },
      );
    });

    test('signs and verifies payload and rejects replay/tamper/wrong room', () async {
      final sender = await Ed25519().newKeyPairFromSeed(Uint8List(32)..[0] = 1);
      final recipient = await Ed25519().newKeyPairFromSeed(Uint8List(32)..[0] = 2);
      final recipientPk = base64.encode((await recipient.extractPublicKey()).bytes);
      final senderPk = base64.encode((await sender.extractPublicKey()).bytes);
      final frame = await signInnerV1(
        payload: {'type': 'ping', 'id': 'p1'},
        senderKey: sender,
        recipientPk: recipientPk,
        roomId: 'room-1',
        now: 1700000000000,
        msgId: 'msg-1',
      );

      final replay = SignedInnerReplayCache();
      expect(
        await verifyInnerV1(
          frame: frame,
          expectedSenderPk: senderPk,
          expectedRecipientPk: recipientPk,
          expectedRoomId: 'room-1',
          replay: replay,
          now: 1700000000100,
        ),
        {'type': 'ping', 'id': 'p1'},
      );
      expect(
        await verifyInnerV1(
          frame: frame,
          expectedSenderPk: senderPk,
          expectedRecipientPk: recipientPk,
          expectedRoomId: 'room-1',
          replay: replay,
          now: 1700000000100,
        ),
        isNull,
      );
      expect(
        await verifyInnerV1(
          frame: {...frame, 'payload': {'type': 'ping', 'id': 'p2'}},
          expectedSenderPk: senderPk,
          expectedRecipientPk: recipientPk,
          expectedRoomId: 'room-1',
          replay: SignedInnerReplayCache(),
          now: 1700000000100,
        ),
        isNull,
      );
      expect(
        await verifyInnerV1(
          frame: frame,
          expectedSenderPk: senderPk,
          expectedRecipientPk: recipientPk,
          expectedRoomId: 'room-2',
          replay: SignedInnerReplayCache(),
          now: 1700000000100,
        ),
        isNull,
      );
    });
  });
}
