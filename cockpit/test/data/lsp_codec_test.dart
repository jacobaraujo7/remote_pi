import 'dart:async';
import 'dart:convert';

import 'package:cockpit/app/core/data/lsp/lsp_codec.dart';
import 'package:flutter_test/flutter_test.dart';

/// Bytes do framing LSP para uma mensagem JSON-RPC.
List<int> frame(Map<String, dynamic> json) => encodeLspMessage(json);

Future<List<Map<String, dynamic>>> decodeChunks(List<List<int>> chunks) {
  return Stream<List<int>>.fromIterable(
    chunks,
  ).transform(const LspMessageDecoder()).toList();
}

void main() {
  group('LspMessageDecoder', () {
    test('round-trip de uma mensagem', () async {
      final msg = {'jsonrpc': '2.0', 'id': 1, 'method': 'initialize'};
      final out = await decodeChunks([frame(msg)]);
      expect(out, hasLength(1));
      expect(out.first['method'], 'initialize');
      expect(out.first['id'], 1);
    });

    test('encode usa Content-Length em bytes UTF-8, não chars', () {
      final bytes = encodeLspMessage({'msg': 'café'}); // 'é' = 2 bytes UTF-8
      final all = ascii.decode(bytes, allowInvalid: true);
      final body = utf8.encode(jsonEncode({'msg': 'café'}));
      expect(all, contains('Content-Length: ${body.length}\r\n\r\n'));
    });

    test('duas mensagens num mesmo chunk', () async {
      final a = frame({'id': 1});
      final b = frame({'id': 2});
      final out = await decodeChunks([
        [...a, ...b],
      ]);
      expect(out.map((m) => m['id']), [1, 2]);
    });

    test('mensagem fragmentada em vários chunks', () async {
      final full = frame({'jsonrpc': '2.0', 'method': 'x', 'n': 42});
      // Quebra no meio do corpo.
      final cut = full.length - 3;
      final out = await decodeChunks([full.sublist(0, cut), full.sublist(cut)]);
      expect(out, hasLength(1));
      expect(out.first['n'], 42);
    });

    test('corpo com multibyte UTF-8 conta bytes corretos', () async {
      final msg = {'message': 'olá 世界 🚀'};
      final out = await decodeChunks([frame(msg)]);
      expect(out, hasLength(1));
      expect(out.first['message'], 'olá 世界 🚀');
    });

    test('header case-insensitive', () async {
      final body = utf8.encode(jsonEncode({'ok': true}));
      final raw = <int>[
        ...ascii.encode('content-length: ${body.length}\r\n\r\n'),
        ...body,
      ];
      final out = await decodeChunks([raw]);
      expect(out, hasLength(1));
      expect(out.first['ok'], true);
    });

    test('JSON inválido é descartado sem travar o stream', () async {
      final bad = utf8.encode('{not json');
      final raw = <int>[
        ...ascii.encode('Content-Length: ${bad.length}\r\n\r\n'),
        ...bad,
      ];
      final good = frame({'id': 9});
      final out = await decodeChunks([
        [...raw, ...good],
      ]);
      // O inválido some; o bom passa.
      expect(out.map((m) => m['id']), [9]);
    });
  });
}
