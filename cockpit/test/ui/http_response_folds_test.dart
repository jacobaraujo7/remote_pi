import 'dart:convert';

import 'package:cockpit/app/cockpit/ui/widgets/http_response_folds.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'JSON recolhe objetos e listas sem confundir chaves dentro de strings',
    () {
      const source = '''{
  "data": {
    "text": "} [",
    "items": [
      1,
      2
    ]
  },
  "ok": true
}''';
      final open = HttpResponseFolds.build(
        source,
        HttpResponseFoldSyntax.json,
        {},
      );
      expect(open.foldEnds, {0: 10, 1: 8, 3: 7});

      final folded = HttpResponseFolds.build(
        source,
        HttpResponseFoldSyntax.json,
        {1, 3},
      );
      expect(folded.text, contains('"data": {},'));
      expect(folded.text, isNot(contains('"items"')));
      expect(folded.lineNumbers, [1, 2, 9, 10]);
      expect(() => jsonDecode(folded.text), returnsNormally);

      final inner = HttpResponseFolds.build(
        source,
        HttpResponseFoldSyntax.json,
        {3},
      );
      expect(inner.text, contains('"items": []'));
      expect(inner.text, contains('"data": {'));
      expect(() => jsonDecode(inner.text), returnsNormally);
    },
  );

  test('XML recolhe elementos, ignora declaração e tags vazias', () {
    const source = '''<?xml version="1.0"?>
<root>
  <!-- <fake> -->
  <item id="1">
    <name>One</name>
  </item>
  <empty />
</root>''';
    final open = HttpResponseFolds.build(
      source,
      HttpResponseFoldSyntax.xml,
      {},
    );
    expect(open.foldEnds, {1: 8, 3: 6});
    final folded = HttpResponseFolds.build(source, HttpResponseFoldSyntax.xml, {
      3,
    });
    expect(folded.text, contains('<item id="1"> … </item>'));
    expect(folded.lineNumbers, [1, 2, 3, 4, 7, 8]);
  });

  test('HTML ignora tags void e conteúdo de script', () {
    const source = '''<div>
  <img src="x.png">
  <script>
    const value = "<fake>";
  </script>
</div>''';
    final open = HttpResponseFolds.build(
      source,
      HttpResponseFoldSyntax.html,
      {},
    );
    expect(open.foldEnds, {0: 6, 2: 5});
    final folded = HttpResponseFolds.build(
      source,
      HttpResponseFoldSyntax.html,
      {2},
    );
    expect(folded.text, contains('<script> … </script>'));
    expect(folded.text, contains('<img src="x.png">'));
  });

  test('texto bruto preserva linhas sem oferecer folds', () {
    const source = 'one\ntwo\nthree';
    final projection = HttpResponseFolds.build(source, null, {});
    expect(projection.text, source);
    expect(projection.lineNumbers, [1, 2, 3]);
    expect(projection.foldEnds, isEmpty);
  });
}
