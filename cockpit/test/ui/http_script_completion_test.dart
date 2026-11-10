import 'package:cockpit/app/cockpit/ui/widgets/http_script_completion.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

HttpScriptSlot _slot(String source) =>
    HttpScriptCompletion.slotAt(source, source.length)!;

List<String> _names(String source, {Object? body}) => [
  for (final option in HttpScriptCompletion.options(
    _slot(source),
    responseBody: body,
  ))
    option.name,
];

void main() {
  test('sugere todas as entradas da API conforme o contexto do script', () {
    expect(_names('< {%\n  '), containsAll(['request', 'client', 'console']));
    expect(_names('< {%\n  '), isNot(contains('response')));
    expect(_names('> {%\n  '), contains('response'));
    expect(_names('< {% request.'), ['variables', 'environment']);
    expect(_names('< {% request.variables.'), ['set', 'get']);
    expect(_names('< {% request.environment.'), ['get']);
    expect(_names('< {% client.'), ['global', 'test', 'assert', 'log']);
    expect(_names('> {% client.global.'), ['set', 'get']);
    expect(_names('> {% response.'), ['body', 'status', 'headers']);
    expect(_names('> {% response.headers.'), ['valueOf']);
    expect(_names('< {% console.'), ['log']);
  });

  test('filtra o prefixo e sugere campos aninhados do último JSON', () {
    expect(_names('> {% client.glo'), ['global']);
    final body = {
      'data': {'accessToken': 'abc', 'expiresIn': 3600},
      'items': [1, 2],
    };
    expect(_names('> {% response.body.', body: body), ['data', 'items']);
    expect(_names('> {% response.body.data.acc', body: body), ['accessToken']);
    expect(_names('> {% response.body.items.', body: body), ['length']);
    expect(_names('> {% response.body.data.', body: null), isEmpty);
  });

  test('não oferece opções fora do bloco, em strings ou comentários', () {
    expect(HttpScriptCompletion.slotAt('GET https://example.com', 10), isNull);
    const closed = '> {% client.log(1) %}\nGET https://example.com';
    expect(HttpScriptCompletion.slotAt(closed, closed.length), isNull);
    const quoted = '> {% client.log("response.body.");';
    final quoteCaret =
        quoted.indexOf('response.body.') + 'response.body.'.length;
    expect(HttpScriptCompletion.slotAt(quoted, quoteCaret), isNull);
    const comment = '> {% // client.global.';
    expect(HttpScriptCompletion.slotAt(comment, comment.length), isNull);
  });

  test('insere método com cursor nos parênteses sem duplicá-los', () {
    const source = '> {% client.global.se';
    final slot = _slot(source);
    final option = HttpScriptCompletion.options(slot).single;
    final completed = HttpScriptCompletion.complete(
      TextEditingValue(
        text: source,
        selection: TextSelection.collapsed(offset: source.length),
      ),
      slot,
      option,
    );
    expect(completed.text, '> {% client.global.set()');
    expect(completed.selection.baseOffset, completed.text.length - 1);

    const withParen = '> {% client.global.se(';
    final existing = HttpScriptCompletion.complete(
      TextEditingValue(
        text: withParen,
        selection: const TextSelection.collapsed(offset: withParen.length - 1),
      ),
      HttpScriptCompletion.slotAt(withParen, withParen.length - 1)!,
      option,
    );
    expect(existing.text, '> {% client.global.set(');
  });
}
