// PairRequest flow — replaces the Noise XX handshake removed by plan 06.
//
// Sequence (over a connected PeerTransport):
//   1. App sends inner JSON {type:"pair_request", id, token, device_name}
//   2. Pi validates token, persists peer, replies pair_ok | pair_error
//   3. App persists PeerRecord on success
//
// No cipher, no safety number — the outer envelope's `ct` is base64 of
// the JSON in plaintext (transparent to PeerTransport implementations).

import 'dart:convert';
import 'dart:typed_data';

import 'package:app/data/transport/relay_config.dart';
import 'package:app/protocol/protocol.dart' show PairOk;
import 'package:app/protocol/uuid7.dart';
import 'package:cryptography/cryptography.dart';

import 'qr_scanner.dart';
import 'signed_pairing.dart';
import 'storage.dart';

// ---------------------------------------------------------------------------
// PeerTransport — minimal byte-level interface (was NoiseTransport pre-rollback)
// ---------------------------------------------------------------------------

abstract class PeerTransport {
  Future<void> send(Uint8List data);
  Future<Uint8List> receive();
  Future<void> close();
}

// ---------------------------------------------------------------------------
// PairingError
// ---------------------------------------------------------------------------

class PairingError implements Exception {
  final String code;
  final String message;
  const PairingError({required this.code, required this.message});

  @override
  String toString() => 'PairingError($code): $message';
}

// ---------------------------------------------------------------------------
// PairingResult — output of [performPairing]
// ---------------------------------------------------------------------------

/// Wraps the persisted [PeerRecord] plus side hints the post-pair UI
/// (nickname modal) needs but that don't belong on the PeerRecord
/// itself. Plan/27 Wave A added [hostnameHint] so the modal can
/// pre-fill "Mac do Jacob" instead of the generic "Pi"; legacy Pis
/// that don't emit `hostname` leave it null and the modal falls back
/// to `peer.sessionName`.
class PairingResult {
  final PeerRecord peer;
  final String? hostnameHint;
  const PairingResult({required this.peer, this.hostnameHint});
}

// ---------------------------------------------------------------------------
// performPairing
// ---------------------------------------------------------------------------

Future<PairingResult> performPairing({
  required QrPairPayload qr,
  required PeerTransport transport,
  required PairingStorage storage,
  required String deviceName,
  /// Owner key used to sign pair_request_v2. Required for QR codes that
  /// carry signed-pairing fields; omitted only for legacy tests/old Pis.
  SimpleKeyPair? ownerKey,
  /// Effective relay URL the app is currently connected to. Used to
  /// detect mismatch vs `qr.relayUrl` for legacy QRs. Passed in by
  /// the caller (PairingViewModel reads it from Preferences).
  required String currentRelayUrl,
}) async {
  // Plan 14: legacy QRs may carry `r=<url>`. If that URL does not
  // match the app's configured relay, the device would attempt to
  // pair on the WRONG relay (or, after we centralised the connect
  // factory on resolveRelayUrl, would silently pair against the
  // user's relay while the Pi is waiting on another). Detect and
  // surface — UI (PairingViewModel) can show "trocar relay?" modal.
  if (qr.relayUrl != null &&
      toWsRelayUrl(qr.relayUrl!) != toWsRelayUrl(currentRelayUrl)) {
    throw PairingError(
      code: 'relay_mismatch',
      message: 'QR points to "${qr.relayUrl}", '
          'but the app is configured for "$currentRelayUrl". '
          'Update the relay in settings or ask the Pi to generate '
          'a new QR.',
    );
  }

  // Plan 17 fix — set the outer envelope's `room` BEFORE sending
  // pair_request. Without this the relay would route to
  // (peer=Pi, room='main') which usually doesn't exist (Pi-ext is in
  // room=<hashOfCwd>) and drop with "dest not found". For legacy QRs
  // that don't carry `rm`, falls back to 'main' — the new
  // ConnectionManager discovery flow patches it up afterwards.
  final pairingRoomId = qr.roomId ?? 'main';
  try {
    (transport as dynamic).setActiveRoom(pairingRoomId);
  } catch (_) {
    // Non-WS transports (tests with in-memory pipes) don't track room —
    // routing is symbolic there, so no harm done.
  }

  final id = uuid7();
  final Map<String, dynamic> req;
  String? ownerPk;
  String? appPeerPk;
  if (qr.supportsSignedPairing) {
    final key = ownerKey;
    if (key == null) {
      throw const PairingError(
        code: 'owner_identity_required',
        message: 'Signed pairing requires the synced Owner identity.',
      );
    }
    req = await buildSignedPairRequestV2(
      id: id,
      token: qr.token,
      deviceName: deviceName,
      ownerKey: key,
      piPk: base64.encode(qr.epkBytes),
      roomId: pairingRoomId,
      pairNonce: qr.pairNonce!,
      expiresAt: qr.expiresAt!,
    );
    ownerPk = req['owner_pk'] as String;
    appPeerPk = req['app_peer_pk'] as String;
  } else {
    req = {
      'type': 'pair_request',
      'id': id,
      'token': qr.token,
      'device_name': deviceName,
    };
  }
  await transport.send(Uint8List.fromList(utf8.encode(jsonEncode(req))));

  final raw = await transport.receive();
  final inner = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
  final type = inner['type'] as String?;

  if (type == 'pair_ok' && inner['in_reply_to'] == id) {
    // Parse via the canonical decoder so PairOk schema evolutions
    // (plan/27 Wave A: `harness`, `hostname`) land in one place.
    final pairOk = PairOk.fromJson(inner);
    // Plan 17 fix — persist the Pi-confirmed room_id (or fall back to
    // the one carried by the QR, then to 'main'). Stored on the
    // PeerRecord so subsequent reconnects address (peer, room)
    // correctly from the very first frame.
    //
    // `PairOk.roomId` defaults to 'main' when the Pi omits the field
    // (plan-17 contract codified in tests). We peek at the raw map to
    // tell "Pi explicitly said main" from "Pi didn't send a room" —
    // only in the latter case do we want to fall back to qr.roomId.
    final rawRoom = inner['room_id'];
    final piEchoedRoom = rawRoom is String && rawRoom.isNotEmpty;
    final piRoomId = piEchoedRoom
        ? pairOk.roomId
        : (qr.roomId ?? 'main');
    final peer = PeerRecord(
      remoteEpk: qr.epk,
      sessionName: pairOk.sessionName,
      // Persist whichever relay we just paired on. For legacy QRs
      // this equals qr.relayUrl (we'd have thrown above otherwise);
      // for new QRs (no `r`) it's the currently configured relay.
      relayUrl: qr.relayUrl ?? currentRelayUrl,
      pairedAt: DateTime.now().toUtc().toIso8601String(),
      roomId: piRoomId,
      // Plan/27 Wave A — null when pi-extension hasn't been upgraded
      // yet to publish `harness` in pair_ok.
      harness: pairOk.harness,
      ownerPk: ownerPk,
      appPeerPk: appPeerPk,
    );
    await storage.savePeer(peer);
    return PairingResult(peer: peer, hostnameHint: pairOk.hostname);
  }

  if (type == 'pair_error') {
    throw PairingError(
      code: inner['code'] as String,
      message: inner['message'] as String? ?? '',
    );
  }

  throw PairingError(
    code: 'unexpected_response',
    message: 'Unknown response type: $type',
  );
}

/// Convenience overload that derives `currentRelayUrl` from a
/// [Preferences]-aware caller. Use directly from production code; tests
/// can still call [performPairing] with an explicit URL.
Future<PairingResult> performPairingWithRelay(
  String currentRelayUrl, {
  required QrPairPayload qr,
  required PeerTransport transport,
  required PairingStorage storage,
  required String deviceName,
  SimpleKeyPair? ownerKey,
}) =>
    performPairing(
      qr: qr,
      transport: transport,
      storage: storage,
      deviceName: deviceName,
      ownerKey: ownerKey,
      currentRelayUrl: currentRelayUrl,
    );

// Silence "unused" once we wire helpers from caller-side; relay_config
// is intentionally imported because PairingViewModel and tests may
// resolve currentRelayUrl via it.
// ignore: unused_element
void _keepRelayConfigImport() => resolveRelayUrl;

