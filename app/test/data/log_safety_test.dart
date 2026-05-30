import 'dart:convert';

import 'package:app/data/log_safety.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('redactForLog removes frame payloads, tokens, and signatures', () {
    final redacted = redactForLog({
      'type': 'pair_request',
      'id': 'msg-1',
      'ct': 'base64-ciphertext',
      'token': 'pair-token-secret',
      'sig': 'auth-signature-secret',
      'body': {'type': 'user_message', 'text': 'please leak this prompt'},
      'payload': {'response': 'assistant reply secret'},
    });

    final rendered = jsonEncode(redacted);
    expect(rendered, contains('pair_request'));
    expect(rendered, contains('msg-1'));
    for (final secret in [
      'base64-ciphertext',
      'pair-token-secret',
      'auth-signature-secret',
      'please leak this prompt',
      'assistant reply secret',
    ]) {
      expect(rendered, isNot(contains(secret)));
    }
  });

  test('safeLogString redacts QR URIs and abbreviates long peer keys', () {
    expect(safeLogString('remotepi://pair?t=secret&epk=peer'), '[redacted-uri]');
    expect(
      safeLogString('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=='),
      'ABCDEFGH…(66 chars)',
    );
    expect(shortId('ABCDEFGHIJKLMNOPQRSTUVWXYZ', visible: 10), 'ABCDEFGHIJ…');
  });

  test('logTextStats exposes only size metadata', () {
    final line = logTextStats('sensitive prompt body');
    expect(line, contains('text.chars='));
    expect(line, contains('text.bytes='));
    expect(line, isNot(contains('sensitive prompt body')));
  });
}
