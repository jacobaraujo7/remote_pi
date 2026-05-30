import 'dart:convert';

// QR URI format:
//   remotepi://pair?t=<base64url>&epk=<base64url>&n=<name>[&r=<url>][&rm=<roomId>][&si=1]
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
//   si  — when "1", the Pi supports and requires signed_inner_v1 after
//         pairing; app rejects pair_ok if the relay strips negotiation.

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
  final bool signedInnerRequired;

  const QrPairPayload({
    required this.token,
    required this.epk,
    required this.sessionName,
    this.relayUrl,
    this.roomId,
    this.signedInnerRequired = false,
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
      final si = uri.queryParameters['si'];
      // r is no longer required — plan 14 dropped it from the canonical
      // contract. Legacy QRs continue to include it; we capture it for
      // mismatch detection but don't reject when absent.
      // rm is optional too — legacy pi-extension didn't emit it, and
      // the app falls back to 'main' / discovery in that case.
      if (t == null || epk == null || n == null) return null;
      if (base64Url.decode(_pad(t)).length != 16) return null;
      if (base64Url.decode(_pad(epk)).length != 32) return null;
      return QrPairPayload(
        token: t,
        epk: epk,
        sessionName: n,
        relayUrl: (r != null && r.isNotEmpty) ? r : null,
        roomId: (rm != null && rm.isNotEmpty) ? rm : null,
        signedInnerRequired: si == '1',
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
