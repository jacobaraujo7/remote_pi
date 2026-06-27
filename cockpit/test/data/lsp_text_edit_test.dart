import 'package:cockpit/app/core/data/lsp/lsp_text_edit.dart';
import 'package:cockpit/app/core/domain/entities/lsp_diagnostic.dart';
import 'package:flutter_test/flutter_test.dart';

LspTextEdit edit(int sl, int sc, int el, int ec, String newText) => LspTextEdit(
  range: LspRange(LspPosition(sl, sc), LspPosition(el, ec)),
  newText: newText,
);

void main() {
  group('parseTextEdits', () {
    test('parseia lista do wire', () {
      final r = parseTextEdits([
        {
          'range': {
            'start': {'line': 0, 'character': 0},
            'end': {'line': 0, 'character': 1},
          },
          'newText': 'X',
        },
      ]);
      expect(r, hasLength(1));
      expect(r.first.newText, 'X');
    });

    test('não-lista vira vazio', () {
      expect(parseTextEdits(null), isEmpty);
      expect(parseTextEdits('nope'), isEmpty);
    });
  });

  group('applyTextEdits', () {
    test('substitui um trecho numa linha', () {
      const text = 'int x=1;';
      // troca '=' (col 5..6) por ' = '
      final out = applyTextEdits(text, [edit(0, 5, 0, 6, ' = ')]);
      expect(out, 'int x = 1;');
    });

    test(
      'múltiplos edits não-sobrepostos aplicam todos (ordem indiferente)',
      () {
        const text = 'a=1;b=2;';
        final out = applyTextEdits(text, [
          edit(0, 1, 0, 2, ' = '), // primeiro '='
          edit(0, 5, 0, 6, ' = '), // segundo '='
        ]);
        expect(out, 'a = 1;b = 2;');
      },
    );

    test('edit que cruza linhas (reformatação multi-linha)', () {
      const text = 'a{\n  x\n}';
      // substitui tudo por versão formatada
      final out = applyTextEdits(text, [edit(0, 0, 2, 1, 'a {\n  x\n}')]);
      expect(out, 'a {\n  x\n}');
    });

    test('lista vazia devolve o texto intacto', () {
      expect(applyTextEdits('abc', const []), 'abc');
    });

    test('clampa range defasado sem crashar', () {
      const text = 'abc';
      final out = applyTextEdits(text, [edit(99, 0, 99, 5, 'Z')]);
      // posição além do fim → no-op efetivo (inserção no fim)
      expect(out, anyOf('abc', 'abcZ'));
    });
  });
}
