import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/transport/relay_config.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_key_value_store.dart';

void main() {
  group('relay_config — isValidRelayUrl', () {
    test('accepts http:// and https:// with non-empty host', () {
      expect(isValidRelayUrl('http://localhost'), isTrue);
      expect(isValidRelayUrl('http://127.0.0.1:8080'), isTrue);
      expect(isValidRelayUrl('https://relay.example.com'), isTrue);
      expect(isValidRelayUrl('https://relay-rp1.jacobmoura.work'), isTrue);
    });

    test('rejects ws:// and wss:// — those are conversions only', () {
      expect(isValidRelayUrl('ws://localhost'), isFalse);
      expect(isValidRelayUrl('wss://relay.example.com'), isFalse);
    });

    test('rejects empty, unsupported schemes, missing host', () {
      expect(isValidRelayUrl(''), isFalse);
      expect(isValidRelayUrl('ftp://example.com'), isFalse);
      expect(isValidRelayUrl('foo'), isFalse);
      expect(isValidRelayUrl('https://'), isFalse,
          reason: 'no host segment');
      expect(isValidRelayUrl('http://'), isFalse,
          reason: 'no host segment');
    });
  });

  group('relay_config — relayUrlValidationMessage', () {
    test('returns null for valid http(s) URLs', () {
      expect(relayUrlValidationMessage('https://relay.example.com'), isNull);
      expect(relayUrlValidationMessage('http://localhost:3000'), isNull);
    });

    test('returns ws-specific hint for ws:// and wss://', () {
      final ws = relayUrlValidationMessage('ws://localhost');
      expect(ws, kRelayUrlInvalidScheme);
      expect(ws, contains('http://'));
      expect(ws, contains('ws://'));

      final wss = relayUrlValidationMessage('wss://relay.example.com');
      expect(wss, kRelayUrlInvalidScheme);
    });

    test('returns generic message for empty / malformed input', () {
      expect(relayUrlValidationMessage(''), kRelayUrlInvalidGeneric);
      expect(relayUrlValidationMessage('foo'), kRelayUrlInvalidGeneric);
      expect(relayUrlValidationMessage('ftp://x.com'), kRelayUrlInvalidGeneric);
      expect(relayUrlValidationMessage('https://'), kRelayUrlInvalidGeneric);
    });
  });

  group('relay_config — toWsRelayUrl', () {
    test('translates http(s) to ws(s)', () {
      expect(toWsRelayUrl('https://relay.example.com'),
          'wss://relay.example.com');
      expect(toWsRelayUrl('http://localhost:8080'),
          'ws://localhost:8080');
    });

    test('passes ws(s) through unchanged (legacy QR / PeerRecord)', () {
      expect(toWsRelayUrl('wss://relay.example.com'),
          'wss://relay.example.com');
      expect(toWsRelayUrl('ws://localhost'), 'ws://localhost');
    });
  });

  group('relay_config — resolveRelayUrl', () {
    test('returns prefs.relayUrl when set', () async {
      final p = Preferences(FakeKeyValueStore());
      await p.setRelayUrl('https://custom.example.com');
      expect(resolveRelayUrl(p), 'https://custom.example.com');
    });

    test('falls back to kDefaultRelayUrl when override is null', () async {
      final p = Preferences(FakeKeyValueStore());
      expect(p.relayUrl, isNull);
      expect(resolveRelayUrl(p), kDefaultRelayUrl);
    });

    test('kDefaultRelayUrl is https://', () {
      expect(kDefaultRelayUrl, startsWith('https://'));
    });
  });
}
