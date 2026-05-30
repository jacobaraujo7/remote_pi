import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class SignedInnerReplayCache {
  final Duration maxAge;
  final int maxEntries;
  final _seen = <String, int>{};

  SignedInnerReplayCache({
    this.maxAge = const Duration(minutes: 5),
    this.maxEntries = 2048,
  });

  bool accept({
    required String senderPk,
    required String roomId,
    required String msgId,
    required int issuedAt,
    int? now,
  }) {
    final current = now ?? DateTime.now().millisecondsSinceEpoch;
    _prune(current);
    if ((current - issuedAt).abs() > maxAge.inMilliseconds) return false;
    final key = '$senderPk\u0000$roomId\u0000$msgId';
    if (_seen.containsKey(key)) return false;
    _seen[key] = issuedAt;
    if (_seen.length > maxEntries) _seen.remove(_seen.keys.first);
    return true;
  }

  void _prune(int now) {
    _seen.removeWhere((_, issuedAt) => (now - issuedAt).abs() > maxAge.inMilliseconds);
  }
}

String _stableJson(Object? value) {
  if (value == null || value is num || value is bool || value is String) {
    return jsonEncode(value);
  }
  if (value is List) return '[${value.map(_stableJson).join(',')}]';
  final map = (value as Map).cast<String, Object?>();
  final keys = map.keys.toList()..sort();
  return '{${keys.map((k) => '${jsonEncode(k)}:${_stableJson(map[k])}').join(',')}}';
}

Map<String, dynamic> _orderedUnsigned(Map<String, dynamic> frame) => {
      'type': 'signed_inner_v1',
      'sender_pk': frame['sender_pk'],
      'recipient_pk': frame['recipient_pk'],
      'room_id': frame['room_id'],
      'msg_id': frame['msg_id'],
      'issued_at': frame['issued_at'],
      'payload_type': frame['payload_type'],
      'payload': jsonDecode(_stableJson(frame['payload'])),
    };

String canonicalSignedInnerV1(Map<String, dynamic> unsigned) => jsonEncode(_orderedUnsigned(unsigned));

String _randomMsgId() {
  final rnd = Random.secure();
  final bytes = Uint8List.fromList(List<int>.generate(16, (_) => rnd.nextInt(256)));
  return base64.encode(bytes);
}

Future<Map<String, dynamic>> signInnerV1({
  required Map<String, dynamic> payload,
  required SimpleKeyPair senderKey,
  required String recipientPk,
  required String roomId,
  int? now,
  String? msgId,
}) async {
  final senderPk = base64.encode((await senderKey.extractPublicKey()).bytes);
  final unsigned = <String, dynamic>{
    'type': 'signed_inner_v1',
    'sender_pk': senderPk,
    'recipient_pk': recipientPk,
    'room_id': roomId,
    'msg_id': msgId ?? _randomMsgId(),
    'issued_at': now ?? DateTime.now().millisecondsSinceEpoch,
    'payload_type': payload['type'],
    'payload': payload,
  };
  final sig = await Ed25519().sign(utf8.encode(canonicalSignedInnerV1(unsigned)), keyPair: senderKey);
  return {...unsigned, 'sig': base64.encode(sig.bytes)};
}

Future<Map<String, dynamic>?> verifyInnerV1({
  required Map<String, dynamic> frame,
  required String expectedSenderPk,
  required String expectedRecipientPk,
  required String expectedRoomId,
  required SignedInnerReplayCache replay,
  int? now,
}) async {
  if (frame['type'] != 'signed_inner_v1') return null;
  if (frame['sender_pk'] != expectedSenderPk) return null;
  if (frame['recipient_pk'] != expectedRecipientPk) return null;
  if (frame['room_id'] != expectedRoomId) return null;
  final payload = (frame['payload'] as Map).cast<String, dynamic>();
  if (frame['payload_type'] != payload['type']) return null;
  final senderPk = SimplePublicKey(base64.decode(frame['sender_pk'] as String), type: KeyPairType.ed25519);
  final sig = Signature(base64.decode(frame['sig'] as String), publicKey: senderPk);
  final unsigned = Map<String, dynamic>.from(frame)..remove('sig');
  final ok = await Ed25519().verify(utf8.encode(canonicalSignedInnerV1(unsigned)), signature: sig);
  if (!ok) return null;
  final accepted = replay.accept(
    senderPk: frame['sender_pk'] as String,
    roomId: frame['room_id'] as String,
    msgId: frame['msg_id'] as String,
    issuedAt: (frame['issued_at'] as num).toInt(),
    now: now,
  );
  return accepted ? payload : null;
}

bool isSignedInnerV1(Map<String, dynamic> json) => json['type'] == 'signed_inner_v1';
