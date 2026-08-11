import 'dart:convert';

import 'package:cockpit/app/core/data/rpc/jsonl_line_splitter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preserva JSONL partido em muitos chunks e aceita CRLF', () async {
    final chunks = <List<int>>[
      utf8.encode('{"delta":"ol'),
      utf8.encode('á"}\r\n{"n":'),
      utf8.encode('2}\n'),
    ];

    expect(
      await Stream.fromIterable(
        chunks,
      ).transform(const JsonlLineSplitter()).toList(),
      ['{"delta":"olá"}', '{"n":2}'],
    );
  });

  test(
    'não trata separadores Unicode dentro do JSON como nova linha',
    () async {
      final input = '{"text":"a\u2028b\u2029c"}\n';
      expect(
        await Stream.value(
          utf8.encode(input),
        ).cast<List<int>>().transform(const JsonlLineSplitter()).toList(),
        ['{"text":"a\u2028b\u2029c"}'],
      );
    },
  );

  test('entrega tail sem LF no fechamento', () async {
    expect(
      await Stream.value(
        utf8.encode('{"done":true}\r'),
      ).cast<List<int>>().transform(const JsonlLineSplitter()).toList(),
      ['{"done":true}'],
    );
  });
}
