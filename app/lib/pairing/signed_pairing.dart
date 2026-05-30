import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

Map<String, dynamic> pairRequestV2UnsignedFields({
  required String id,
  required String token,
  required String deviceName,
  required String ownerPk,
  required String appPeerPk,
  required String piPk,
  required String roomId,
  required String pairNonce,
  required int expiresAt,
}) => {
      'type': 'pair_request_v2',
      'id': id,
      'token': token,
      'device_name': deviceName,
      'owner_pk': ownerPk,
      'app_peer_pk': appPeerPk,
      'pi_pk': piPk,
      'room_id': roomId,
      'pair_nonce': pairNonce,
      'expires_at': expiresAt,
    };

String canonicalPairRequestV2(Map<String, dynamic> unsigned) => jsonEncode({
      'type': unsigned['type'],
      'id': unsigned['id'],
      'token': unsigned['token'],
      'device_name': unsigned['device_name'],
      'owner_pk': unsigned['owner_pk'],
      'app_peer_pk': unsigned['app_peer_pk'],
      'pi_pk': unsigned['pi_pk'],
      'room_id': unsigned['room_id'],
      'pair_nonce': unsigned['pair_nonce'],
      'expires_at': unsigned['expires_at'],
    });

Future<Map<String, dynamic>> buildSignedPairRequestV2({
  required String id,
  required String token,
  required String deviceName,
  required SimpleKeyPair ownerKey,
  required String piPk,
  required String roomId,
  required String pairNonce,
  required int expiresAt,
}) async {
  final ownerPub = await ownerKey.extractPublicKey();
  final ownerPk = base64.encode(ownerPub.bytes);
  // Current app challenge-response also authenticates with the Owner key, so
  // the relay-authenticated app peer key is the Owner public key. Keeping the
  // field explicit binds the signature to the relay peer and leaves room for a
  // future per-device app key without changing the canonical payload shape.
  final appPeerPk = ownerPk;
  final unsigned = pairRequestV2UnsignedFields(
    id: id,
    token: token,
    deviceName: deviceName,
    ownerPk: ownerPk,
    appPeerPk: appPeerPk,
    piPk: piPk,
    roomId: roomId,
    pairNonce: pairNonce,
    expiresAt: expiresAt,
  );
  final canonical = canonicalPairRequestV2(unsigned);
  final sig = await Ed25519().sign(
    Uint8List.fromList(utf8.encode(canonical)),
    keyPair: ownerKey,
  );
  return {
    ...unsigned,
    'sig': base64.encode(sig.bytes),
  };
}
