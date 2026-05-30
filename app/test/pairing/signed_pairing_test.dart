import 'dart:convert';
import 'dart:typed_data';

import 'package:app/pairing/signed_pairing.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> main() async {
  group('signed pairing helpers', () {
    test('canonicalPairRequestV2 is stable and excludes sig', () {
      final unsigned = pairRequestV2UnsignedFields(
        id: 'id-1',
        token: 'token-1',
        deviceName: 'phone',
        ownerPk: 'owner-pk',
        appPeerPk: 'app-peer-pk',
        piPk: 'pi-pk',
        roomId: 'room-1',
        pairNonce: 'nonce-1',
        expiresAt: 1700000000000,
      );

      expect(
        canonicalPairRequestV2({...unsigned, 'sig': 'must-not-appear'}),
        '{"type":"pair_request_v2","id":"id-1","token":"token-1","device_name":"phone",'
        '"owner_pk":"owner-pk","app_peer_pk":"app-peer-pk","pi_pk":"pi-pk",'
        '"room_id":"room-1","pair_nonce":"nonce-1","expires_at":1700000000000}',
      );
    });

    test('buildSignedPairRequestV2 signs the canonical payload', () async {
      final key = await Ed25519().newKeyPairFromSeed(Uint8List(32)..[31] = 7);
      final req = await buildSignedPairRequestV2(
        id: 'id-1',
        token: 'token-1',
        deviceName: 'phone',
        ownerKey: key,
        piPk: base64.encode(Uint8List(32)..[0] = 1),
        roomId: 'room-1',
        pairNonce: 'nonce-1',
        expiresAt: 1700000000000,
      );

      expect(req['type'], 'pair_request_v2');
      expect(req['owner_pk'], req['app_peer_pk']);
      final sig = Signature(base64.decode(req['sig'] as String), publicKey: await key.extractPublicKey());
      final ok = await Ed25519().verify(
        utf8.encode(canonicalPairRequestV2(req)),
        signature: sig,
      );
      expect(ok, isTrue);
    });
  });
}
