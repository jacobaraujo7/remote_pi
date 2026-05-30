import 'dart:convert';

// QR URI format:
//   remotepi://pair?t=<base64url>&epk=<base64url>&n=<name>[&r=<url>][&rm=<roomId>]
//
// Fields:
//   t   — token efêmero (16 bytes, base64url), single-use, valid 60s
//   epk — Ed25519 pubkey do Pi (32 bytes) — único peer ID no relay
//   n   — session name (max 80 chars)
//   r   — relay WebSocket URL (OPTIONAL since plan 14: app uses its own
//         configured relay; legacy QR codes that carry `r` are tolerated
//         and trigger a "trocar relay?" modal if the value mismatches
//         the user's configured relay).
//   rm  — Pi-side room id this QR was generated FROM (plan 17 fix —
//         lets the app address the right cwd-session on the very first
//         pair_request, otherwise the relay drops with
//         "dest (peer, room) not found"). Optional; legacy QRs without
//         `rm` make the app fall back to `'main'` during pair_request
//         and rely on subscribe_rooms-based discovery afterwards.
//   pn  — pair nonce for signed pair_request_v2.
//   exp — token/session expiry timestamp in milliseconds since epoch.

class QrPairPayload {
  final String token;
  final String epk; // base64url Ed25519 — relay peer ID
  /// Optional legacy relay URL embedded in the QR. `null` for new QRs.
  /// Use `pair_request_flow` to detect mismatch vs `Preferences.relayUrl`.
  final String? relayUrl;
  final String sessionName;
  /// Plan 17 fix: Pi-side room id (cwd-session). Used as the outer
  /// envelope's `room` on pair_request so the relay can route to the
  /// right Pi-WS. `null` for pre-plan-17 QRs — caller must fall back to
  /// `'main'` and discover the real room id via subscribe_rooms.
  final String? roomId;
  /// Pair nonce for pair_request_v2. Null for legacy QRs.
  final String? pairNonce;
  /// Expiry timestamp in milliseconds since epoch for pair_request_v2.
  final int? expiresAt;

  bool get supportsSignedPairing => pairNonce != null && expiresAt != null;

  const QrPairPayload({
    required this.token,
    required this.epk,
    required this.sessionName,
    this.relayUrl,
    this.roomId,
    this.pairNonce,
    this.expiresAt,
  });

  static QrPairPayload? tryParse(String raw) {
    try {
      final uri = Uri.parse(raw);
      if (uri.scheme != 'remotepi' || uri.host != 'pair') return null;
      final t = uri.queryParameters['t'];
      final epk = uri.queryParameters['epk'];
      final r = uri.queryParameters['r']; // legacy/optional
      final n = uri.queryParameters['n'];
      final rm = uri.queryParameters['rm']; // plan 17 — Pi-side room
      final pn = uri.queryParameters['pn']; // signed pairing nonce
      final expRaw = uri.queryParameters['exp']; // signed pairing expiry ms
      // r is no longer required — plan 14 dropped it from the canonical
      // contract. Legacy QRs continue to include it; we capture it for
      // mismatch detection but don't reject when absent.
      // rm is optional too — legacy pi-extension didn't emit it, and
      // the app falls back to 'main' / discovery in that case.
      if (t == null || epk == null || n == null) return null;
      if (base64Url.decode(_pad(t)).length != 16) return null;
      if (base64Url.decode(_pad(epk)).length != 32) return null;
      int? expiresAt;
      if (expRaw != null && expRaw.isNotEmpty) {
        expiresAt = int.tryParse(expRaw);
        if (expiresAt == null || expiresAt <= 0) return null;
      }
      if ((pn == null) != (expiresAt == null)) return null;
      if (pn != null && base64Url.decode(_pad(pn)).length != 16) return null;
      return QrPairPayload(
        token: t,
        epk: epk,
        sessionName: n,
        relayUrl: (r != null && r.isNotEmpty) ? r : null,
        roomId: (rm != null && rm.isNotEmpty) ? rm : null,
        pairNonce: (pn != null && pn.isNotEmpty) ? pn : null,
        expiresAt: expiresAt,
      );
    } catch (_) {
      return null;
    }
  }

  List<int> get epkBytes => base64Url.decode(_pad(epk));

  static String _pad(String s) {
    final p = (4 - s.length % 4) % 4;
    return s + '=' * p;
  }
}
