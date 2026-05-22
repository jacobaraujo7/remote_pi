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
import 'dart:math';
import 'dart:typed_data';

import 'package:app/data/transport/relay_config.dart';

import 'qr_scanner.dart';
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
// performPairing
// ---------------------------------------------------------------------------

Future<PeerRecord> performPairing({
  required QrPairPayload qr,
  required PeerTransport transport,
  required PairingStorage storage,
  required String deviceName,
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
  if (qr.relayUrl != null && qr.relayUrl != currentRelayUrl) {
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

  final id = _uuid7();
  final req = {
    'type': 'pair_request',
    'id': id,
    'token': qr.token,
    'device_name': deviceName,
  };
  await transport.send(Uint8List.fromList(utf8.encode(jsonEncode(req))));

  final raw = await transport.receive();
  final inner = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
  final type = inner['type'] as String?;

  if (type == 'pair_ok' && inner['in_reply_to'] == id) {
    // Plan 17 fix — persist the Pi-confirmed room_id (or fall back to
    // the one carried by the QR, then to 'main'). Stored on the
    // PeerRecord so subsequent reconnects address (peer, room)
    // correctly from the very first frame.
    final piRoomId = (inner['room_id'] as String?) ??
        qr.roomId ??
        'main';
    final peer = PeerRecord(
      remoteEpk: qr.epk,
      sessionName: inner['session_name'] as String,
      // Persist whichever relay we just paired on. For legacy QRs
      // this equals qr.relayUrl (we'd have thrown above otherwise);
      // for new QRs (no `r`) it's the currently configured relay.
      relayUrl: qr.relayUrl ?? currentRelayUrl,
      pairedAt: DateTime.now().toUtc().toIso8601String(),
      roomId: piRoomId,
    );
    await storage.savePeer(peer);
    return peer;
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
Future<PeerRecord> performPairingWithRelay(
  String currentRelayUrl, {
  required QrPairPayload qr,
  required PeerTransport transport,
  required PairingStorage storage,
  required String deviceName,
}) =>
    performPairing(
      qr: qr,
      transport: transport,
      storage: storage,
      deviceName: deviceName,
      currentRelayUrl: currentRelayUrl,
    );

// Silence "unused" once we wire helpers from caller-side; relay_config
// is intentionally imported because PairingViewModel and tests may
// resolve currentRelayUrl via it.
// ignore: unused_element
void _keepRelayConfigImport() => resolveRelayUrl;

// ---------------------------------------------------------------------------
// UUIDv7 — random-based, sufficient for inner correlation IDs.
// Layout: 48-bit unix_ts_ms | ver=7 | 12-bit rand_a | variant=10 | 62-bit rand_b
// ---------------------------------------------------------------------------

final _rng = Random.secure();

String _uuid7() {
  final ms = DateTime.now().millisecondsSinceEpoch;
  final bytes = Uint8List(16);

  bytes[0] = (ms >> 40) & 0xff;
  bytes[1] = (ms >> 32) & 0xff;
  bytes[2] = (ms >> 24) & 0xff;
  bytes[3] = (ms >> 16) & 0xff;
  bytes[4] = (ms >> 8) & 0xff;
  bytes[5] = ms & 0xff;

  for (var i = 6; i < 16; i++) {
    bytes[i] = _rng.nextInt(256);
  }
  bytes[6] = (bytes[6] & 0x0f) | 0x70; // version 7
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC 4122 variant

  String hex(int b) => b.toRadixString(16).padLeft(2, '0');
  final h = bytes.map(hex).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
      '${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}
