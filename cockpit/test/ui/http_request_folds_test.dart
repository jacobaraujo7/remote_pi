import 'package:cockpit/app/cockpit/ui/widgets/http_request_folds.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const source = '''### first
GET https://example.com/a
Accept: application/json

### second
GET https://example.com/b
?page=1

''';

  test('recolhe só o conteúdo da chamada e mantém os números originais', () {
    final projection = HttpRequestFolds.build(source, {1, 5});
    expect(projection.foldEnds, {1: 3, 5: 7});
    expect(projection.lineNumbers, [1, 2, 4, 5, 6, 8, 9]);
    expect(projection.visibleBySource[5], 4);
    expect(projection.text, contains('GET https://example.com/a\n'));
    expect(projection.text, isNot(contains('Accept: application/json')));
    expect(projection.text, contains('GET https://example.com/b    ?page=1'));
    expect(source, contains('Accept: application/json\n\n### second'));
  });

  test('sem fold projeta o arquivo sem alterações', () {
    final projection = HttpRequestFolds.build(source, {});
    expect(projection.text, source);
    expect(projection.lineNumbers.last, source.split('\n').length);
  });

  test('header não aparece no resumo de URL já completa', () {
    const text =
        'GET https://example.com/get?show_env=1\nAccept: application/json\n';
    final projection = HttpRequestFolds.build(text, {0});
    expect(projection.text, 'GET https://example.com/get?show_env=1\n');
  });

  test(
    'fold de script mostra só delimitadores e preserva linhas do gutter',
    () {
      const text = '''### Login
< {%
  request.variables.set('id', '1');
%}
POST https://example.com/login

> {%
  client.global.set('token', response.body.token);
%}
''';
      final open = HttpRequestFolds.build(text, {});
      expect(open.foldEnds[1], 4);
      expect(open.foldEnds[6], 9);
      final folded = HttpRequestFolds.build(text, {1, 6});
      expect(folded.text, contains('< {% ... %}'));
      expect(folded.text, contains('> {% ... %}'));
      expect(folded.text, isNot(contains('client.global.set')));
      expect(folded.lineNumbers, [1, 2, 5, 6, 7, 10]);
    },
  );
}
