import 'package:app/pairing/qr_scanner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('QrPairPayload.tryParse', () {
    const goodToken = 'AAAAAAAAAAAAAAAAAAAAAA'; // 16 bytes base64url
    const goodEpk = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'; // 32 bytes
    const sessionName = 'test+session';

    test('parses legacy QR with relay (r=) param', () {
      final raw = 'remotepi://pair?t=$goodToken&epk=$goodEpk&'
          'r=ws%3A%2F%2Flocalhost&n=$sessionName';
      final qr = QrPairPayload.tryParse(raw);
      expect(qr, isNotNull);
      expect(qr!.token, goodToken);
      expect(qr.epk, goodEpk);
      expect(qr.sessionName, 'test session');
      expect(qr.relayUrl, 'ws://localhost',
          reason: 'legacy r= is parsed for mismatch detection');
    });

    test('parses new QR WITHOUT r= param — relayUrl is null', () {
      final raw =
          'remotepi://pair?t=$goodToken&epk=$goodEpk&n=$sessionName';
      final qr = QrPairPayload.tryParse(raw);
      expect(qr, isNotNull);
      expect(qr!.token, goodToken);
      expect(qr.epk, goodEpk);
      expect(qr.sessionName, 'test session');
      expect(qr.relayUrl, isNull,
          reason: 'no r= present — app uses its configured relay');
    });

    test('rejects when t is missing or wrong length', () {
      final missingT =
          'remotepi://pair?epk=$goodEpk&n=$sessionName';
      expect(QrPairPayload.tryParse(missingT), isNull);

      final badT = 'remotepi://pair?t=AAAA&epk=$goodEpk&n=$sessionName';
      expect(QrPairPayload.tryParse(badT), isNull);
    });

    test('rejects when epk has wrong byte length', () {
      final raw =
          'remotepi://pair?t=$goodToken&epk=AAAAAAAAA&n=$sessionName';
      expect(QrPairPayload.tryParse(raw), isNull);
    });

    test('rejects non-remotepi scheme', () {
      const raw =
          'https://example.com/pair?t=x&epk=y&n=z';
      expect(QrPairPayload.tryParse(raw), isNull);
    });

    test('empty r= is treated as null (not the empty string)', () {
      final raw = 'remotepi://pair?t=$goodToken&epk=$goodEpk&'
          'r=&n=$sessionName';
      final qr = QrPairPayload.tryParse(raw);
      expect(qr, isNotNull);
      expect(qr!.relayUrl, isNull);
    });

    test(
      'parses QR with `rm` (room id) — plan 17 fix lets the app target '
      'the Pi\'s cwd-session at pair_request time',
      () {
        final raw = 'remotepi://pair?t=$goodToken&epk=$goodEpk&'
            'rm=abc123def456&n=$sessionName';
        final qr = QrPairPayload.tryParse(raw);
        expect(qr, isNotNull);
        expect(qr!.roomId, 'abc123def456');
      },
    );

    test('QR without `rm` (legacy) leaves roomId null', () {
      final raw = 'remotepi://pair?t=$goodToken&epk=$goodEpk&n=$sessionName';
      final qr = QrPairPayload.tryParse(raw);
      expect(qr, isNotNull);
      expect(qr!.roomId, isNull);
    });

    test('empty rm= is treated as null', () {
      final raw = 'remotepi://pair?t=$goodToken&epk=$goodEpk&'
          'rm=&n=$sessionName';
      final qr = QrPairPayload.tryParse(raw);
      expect(qr, isNotNull);
      expect(qr!.roomId, isNull);
    });

    test('si=1 marks signed inner support as required by this QR', () {
      final raw = 'remotepi://pair?t=$goodToken&epk=$goodEpk&'
          'rm=abc123def456&si=1&n=$sessionName';
      final qr = QrPairPayload.tryParse(raw);
      expect(qr, isNotNull);
      expect(qr!.signedInnerRequired, isTrue);
    });

    test('QR without si leaves signed inner optional for legacy compatibility', () {
      final raw = 'remotepi://pair?t=$goodToken&epk=$goodEpk&n=$sessionName';
      final qr = QrPairPayload.tryParse(raw);
      expect(qr, isNotNull);
      expect(qr!.signedInnerRequired, isFalse);
    });
  });
}
