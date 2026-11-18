import 'package:cockpit/app/cockpit/ui/widgets/code_editor.dart';
import 'package:cockpit/app/cockpit/ui/widgets/http_body_editing.dart';
import 'package:cockpit/app/cockpit/ui/widgets/http_script_editing.dart';
import 'package:cockpit/app/cockpit/ui/widgets/http_variable_completion.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/code_editing_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

TextEditingValue _value(String source) {
  final caret = source.indexOf('|');
  return TextEditingValue(
    text: source.replaceFirst('|', ''),
    selection: TextSelection.collapsed(offset: caret),
  );
}

TextEditingValue _edit(TextEditingValue old, TextEditingValue next) {
  for (final formatter in const [
    HttpVariableBraceFormatter(),
    HttpScriptEditingFormatter(),
    HttpBodyEditingFormatter(),
  ]) {
    next = formatter.formatEditUpdate(old, next);
  }
  return next;
}

TextEditingValue _type(TextEditingValue old, String char) => _edit(
  old,
  TextEditingValue(
    text: old.text.replaceRange(old.selection.start, old.selection.end, char),
    selection: TextSelection.collapsed(
      offset: old.selection.start + char.length,
    ),
  ),
);

String _request(String type, String body) =>
    'POST https://example.test/users\nContent-Type: $type\n\n$body';

void main() {
  test('Content-Type seleciona pares JSON, incluindo sufixos e charset', () {
    for (final mime in [
      'application/json',
      'APPLICATION/JSON; charset=utf-8',
      'application/problem+json',
      'text/json',
    ]) {
      for (final pair in ['{}', '[]', '""']) {
        final old = _value(_request(mime, '|'));
        final paired = _type(old, pair[0]);
        expect(paired.text, _request(mime, pair));
        expect(paired.selection.start, old.selection.start + 1);
        final closed = _type(paired, pair[1]);
        expect(closed.text, paired.text);
        expect(closed.selection.start, paired.selection.start + 1);
      }
    }
  });

  test('JSON preserva strings e escapes e não insere pares de JavaScript', () {
    for (final char in ['{', '[', "'", '(', '`']) {
      final old = _value(_request('application/json', '{"text": "hello |"}'));
      expect(
        _type(old, char).text,
        _request('application/json', '{"text": "hello $char"}'),
      );
    }
    final escaped = _value(
      _request('application/json', '{"text": "hello \\|"}'),
    );
    expect(
      _type(escaped, '"').text,
      _request('application/json', '{"text": "hello \\""}'),
    );
    for (final char in ["'", '(', '`']) {
      final old = _value(_request('application/json', '|'));
      expect(_type(old, char).text, _request('application/json', char));
    }
  });

  test('JSON indenta blocos, remove pares vazios e envolve seleção', () {
    for (final pair in ['{}', '[]']) {
      final old = _value(_request('application/json', '${pair[0]}|${pair[1]}'));
      final entered = _type(old, '\n');
      expect(
        entered.text,
        _request('application/json', '${pair[0]}\n  \n${pair[1]}'),
      );
      expect(entered.selection.start, old.selection.start + 3);
      final deleted = _edit(
        old,
        TextEditingValue(
          text: old.text.replaceRange(
            old.selection.start - 1,
            old.selection.start,
            '',
          ),
          selection: TextSelection.collapsed(offset: old.selection.start - 1),
        ),
      );
      expect(deleted.text, _request('application/json', ''));
    }
    final selected = _value(_request('application/json', '|true'));
    final wrapped = _type(
      selected.copyWith(
        selection: TextSelection(
          baseOffset: selected.selection.start,
          extentOffset: selected.text.length,
        ),
      ),
      '[',
    );
    expect(wrapped.text, _request('application/json', '[true]'));
    expect(wrapped.selection.textInside(wrapped.text), 'true');
  });

  test('placeholders HTTP coexistem com autoclose de JSON', () {
    var value = _value(_request('application/json', '|'));
    value = _type(value, '{');
    value = _type(value, '{');
    expect(value.text, _request('application/json', '{{}}'));
    for (final char in 'userId'.split('')) {
      value = _type(value, char);
    }
    value = _type(value, '}');
    value = _type(value, '}');
    expect(value.text, _request('application/json', '{{userId}}'));
    final string = _value(_request('application/json', '{"name": "{|"}'));
    expect(
      _type(string, '{').text,
      _request('application/json', '{"name": "{{}}"}'),
    );
  });

  test(
    'XML e HTML fecham tags completas e atributos sem duplicar fechamento',
    () {
      for (final mime in [
        'application/xml',
        'text/xml; charset=utf-8',
        'application/soap+xml',
        'text/html',
      ]) {
        for (final tag in [
          'users',
          'ns:user',
          'user id="42"',
          "user label='a>b'",
        ]) {
          final name = tag.split(' ').first;
          final old = _value(_request(mime, '<$tag|'));
          final closed = _type(old, '>');
          expect(closed.text, _request(mime, '<$tag></$name>'));
          expect(closed.selection.start, old.selection.start + 1);
        }
        final existing = _value(_request(mime, '<users|></users>'));
        expect(_type(existing, '>').text, _request(mime, '<users></users>'));
        for (final quote in ['"', "'"]) {
          final old = _value(_request(mime, '<users name=|>'));
          final pair = _type(old, quote);
          expect(pair.text, _request(mime, '<users name=$quote$quote>'));
          expect(_type(pair, quote).text, pair.text);
        }
      }
    },
  );

  test(
    'XML e HTML indentam entre tags e preservam texto e valores de atributos',
    () {
      for (final mime in ['application/xml', 'text/html']) {
        final old = _value(_request(mime, '  <users>|</users>'));
        expect(
          _type(old, '\n').text,
          _request(mime, '  <users>\n    \n  </users>'),
        );
        final text = _value(_request(mime, '<users>hello |</users>'));
        expect(_type(text, '"').text, _request(mime, '<users>hello "</users>'));
        final attr = _value(_request(mime, '<users name="a|">'));
        expect(_type(attr, '>').text, _request(mime, '<users name="a>">'));
      }
    },
  );

  test(
    'tags vazias, fechamentos, comentários, CDATA e instruções ficam intactos',
    () {
      for (final mime in ['application/xml', 'text/html']) {
        for (final prefix in [
          '<users/',
          '</users',
          '<!DOCTYPE html',
          '<!-- <users',
          '<![CDATA[<users',
          '<?xml version="1.0"?',
        ]) {
          final old = _value(_request(mime, '$prefix|'));
          expect(_type(old, '>').text, _request(mime, '$prefix>'));
        }
      }
      for (final name in ['br', 'img', 'input', 'HR', 'meta', 'source']) {
        final old = _value(_request('text/html', '<$name|'));
        expect(_type(old, '>').text, _request('text/html', '<$name>'));
      }
      final xml = _value(_request('application/xml', '<br|'));
      expect(_type(xml, '>').text, _request('application/xml', '<br></br>'));
      final html = _value(_request('text/html', '<DIV|</div>'));
      expect(_type(html, '>').text, _request('text/html', '<DIV></div>'));
    },
  );

  test(
    'tags filhas não reutilizam o fechamento do ancestral com o mesmo nome',
    () {
      for (final mime in ['application/xml', 'text/html']) {
        final nested = _value(_request(mime, '<users><users|</users>'));
        expect(
          _type(nested, '>').text,
          _request(mime, '<users><users></users></users>'),
        );
        final complete = _value(
          _request(mime, '<users><users|</users></users>'),
        );
        expect(
          _type(complete, '>').text,
          _request(mime, '<users><users></users></users>'),
        );
      }
    },
  );

  test('Enter não duplica espaços ou linhas antes dos fechamentos', () {
    for (final pair in ['{}', '[]']) {
      final spaced = _value(
        _request('application/json', '  ${pair[0]}|  ${pair[1]}'),
      );
      expect(
        _type(spaced, '\n').text,
        _request('application/json', '  ${pair[0]}\n    \n  ${pair[1]}'),
      );
      final multiline = _value(
        _request('application/json', '${pair[0]}|\n${pair[1]}'),
      );
      expect(
        _type(multiline, '\n').text,
        _request('application/json', '${pair[0]}\n  \n${pair[1]}'),
      );
    }
    final xml = _value(_request('application/xml', '<users>|\n</users>'));
    expect(
      _type(xml, '\n').text,
      _request('application/xml', '<users>\n  \n</users>'),
    );
  });

  test('conteúdo literal de script e style HTML não gera tags', () {
    for (final tag in ['script', 'style', 'textarea', 'title']) {
      final old = _value(_request('text/html', '<$tag>"<users|"</$tag>'));
      expect(
        _type(old, '>').text,
        _request('text/html', '<$tag>"<users>"</$tag>'),
      );
    }
  });

  test('não interfere em URLs, headers, arquivos de body ou outros tipos', () {
    for (final source in [
      'POST https://example.test/|',
      'POST https://example.test\nContent-Type: application/json|',
      'POST https://example.test\nContent-Type: application/json\nX-Note: |',
      'POST https://example.test\nContent-Type: application/json\n< ./body.json\n\n|',
      'POST https://example.test\n\n|',
      _request('text/plain', '|'),
      _request('application/x-www-form-urlencoded', '|'),
    ]) {
      final old = _value(source);
      expect(
        _type(old, '{').text,
        old.text.replaceRange(old.selection.start, old.selection.start, '{'),
      );
    }
  });

  test(
    'Content-Type não vaza entre requests nem interfere em pré e pós-scripts',
    () {
      const first =
          'POST https://example.test\nContent-Type: application/json\n\n{}\n';
      final next = _value('$first### Next\nPOST https://example.test\n\n|');
      expect(_type(next, '{').text, '${next.text}{');
      final xml = _value(
        '$first### Next\n${_request('application/xml', '<users|')}',
      );
      expect(
        _type(xml, '>').text,
        '$first### Next\n${_request('application/xml', '<users></users>')}',
      );
      for (final marker in ['<', '>']) {
        final old = _value(
          '$first$marker {%\n  client.test("Listagem de users", function () |\n%}',
        );
        final result = _type(old, '{');
        expect(
          result.text,
          '$first$marker {%\n  client.test("Listagem de users", function () {}\n%}',
        );
        expect(result.selection.start, old.selection.start + 1);
        final quotes = _value('$first$marker {%\n  client.log(|);\n%}');
        expect(
          _type(quotes, "'").text,
          '$first$marker {%\n  client.log(\'\');\n%}',
        );
      }
    },
  );

  test('paste e composição não geram fechamentos', () {
    final old = _value(_request('application/json', '|'));
    final pasted = _type(old, '{"id":');
    expect(pasted.text, _request('application/json', '{"id":'));
    final composing = TextEditingValue(
      text: '${old.text}{',
      selection: TextSelection.collapsed(offset: old.text.length + 1),
      composing: TextRange(start: old.text.length, end: old.text.length + 1),
    );
    expect(_edit(old, composing), composing);
  });

  testWidgets(
    'CodeEditor aplica autoclose de body e atributos pelo pipeline real',
    (tester) async {
      final initial = _value(_request('application/xml', '<users name=|>'));
      final controller = CodeEditingController(
        text: initial.text,
        language: 'http',
      )..selection = initial.selection;
      final focus = FocusNode();
      addTearDown(() {
        controller.dispose();
        focus.dispose();
      });
      await tester.pumpWidget(
        ShadcnApp(
          theme: buildTheme(brightness: Brightness.dark),
          home: Scaffold(
            child: SizedBox(
              width: 500,
              height: 300,
              child: CodeEditor(
                controller: controller,
                focusNode: focus,
                autoCloseHttpVariables: true,
                autoEditHttpScripts: true,
                autoEditHttpBody: true,
              ),
            ),
          ),
        ),
      );
      focus.requestFocus();
      await tester.pump();
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: initial.text.replaceRange(
            initial.selection.start,
            initial.selection.start,
            '"',
          ),
          selection: TextSelection.collapsed(
            offset: initial.selection.start + 1,
          ),
        ),
      );
      await tester.pump();
      expect(controller.text, _request('application/xml', '<users name="">'));
      final empty = _value(_request('application/json', '|'));
      controller.value = empty;
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: '${empty.text}{',
          selection: TextSelection.collapsed(offset: empty.text.length + 1),
        ),
      );
      await tester.pump();
      expect(controller.text, _request('application/json', '{}'));
      expect(controller.selection.start, empty.text.length + 1);
    },
  );
}
