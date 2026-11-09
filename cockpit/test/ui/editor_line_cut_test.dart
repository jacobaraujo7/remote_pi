import 'package:cockpit/app/cockpit/ui/widgets/editor_line_cut.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

TextEditingValue v(String text, int base, [int? extent]) => TextEditingValue(
  text: text,
  selection: TextSelection(baseOffset: base, extentOffset: extent ?? base),
);

void main() {
  group('cutLine', () {
    test('linha do meio sai com a quebra e o cursor fica na mesma coluna', () {
      final r = cutLine(v('aaa\nbbb\nccc', 5))!;
      expect(r.clipboard, 'bbb\n');
      expect(r.value.text, 'aaa\nccc');
      expect(r.value.selection, const TextSelection.collapsed(offset: 5));
    });

    test('primeira linha', () {
      final r = cutLine(v('aaa\nbbb\nccc', 2))!;
      expect(r.clipboard, 'aaa\n');
      expect(r.value.text, 'bbb\nccc');
      expect(r.value.selection.baseOffset, 2);
    });

    test('cursor no fim da linha cai no fim da linha seguinte', () {
      final r = cutLine(v('aaa\nbbb', 3))!;
      expect(r.value.text, 'bbb');
      expect(r.value.selection.baseOffset, 3);
    });

    test('coluna maior que a linha seguinte é limitada ao fim dela', () {
      final r = cutLine(v('abcdef\nxy\nz', 5))!;
      expect(r.clipboard, 'abcdef\n');
      expect(r.value.text, 'xy\nz');
      expect(r.value.selection.baseOffset, 2);
    });

    test('última linha sem quebra leva a quebra de antes', () {
      final r = cutLine(v('aaa\nbbb', 6))!;
      expect(r.clipboard, 'bbb\n');
      expect(r.value.text, 'aaa');
      expect(r.value.selection.baseOffset, 3);
    });

    test('última linha com quebra no fim deixa a linha vazia final', () {
      final r = cutLine(v('aaa\nbbb\n', 5))!;
      expect(r.clipboard, 'bbb\n');
      expect(r.value.text, 'aaa\n');
      expect(r.value.selection.baseOffset, 4);
    });

    test('linha vazia final (depois do último \\n)', () {
      final r = cutLine(v('aaa\n', 4))!;
      expect(r.clipboard, '\n');
      expect(r.value.text, 'aaa');
      expect(r.value.selection.baseOffset, 3);
    });

    test('linha vazia no meio', () {
      final r = cutLine(v('a\n\nb', 2))!;
      expect(r.clipboard, '\n');
      expect(r.value.text, 'a\nb');
      expect(r.value.selection.baseOffset, 2);
    });

    test('arquivo de uma linha esvazia o texto sem inventar quebra', () {
      final r = cutLine(v('hello', 2))!;
      expect(r.clipboard, 'hello');
      expect(r.value.text, '');
      expect(r.value.selection.baseOffset, 0);
    });

    test('arquivo vazio não recorta', () {
      expect(cutLine(v('', 0)), isNull);
    });

    test('com seleção devolve null (recorte normal)', () {
      expect(cutLine(v('aaa\nbbb', 0, 2)), isNull);
      expect(cutLine(v('aaa\nbbb', 5, 1)), isNull);
    });

    test('seleção inválida devolve null', () {
      expect(
        cutLine(
          const TextEditingValue(
            text: 'a',
            selection: TextSelection.collapsed(offset: -1),
          ),
        ),
        isNull,
      );
    });

    group('\\r\\n', () {
      test('linha do meio leva o \\r\\n inteiro', () {
        final r = cutLine(v('aa\r\nbb\r\ncc', 5))!;
        expect(r.clipboard, 'bb\r\n');
        expect(r.value.text, 'aa\r\ncc');
        expect(r.value.selection.baseOffset, 5);
      });

      test('coluna limitada não para entre o \\r e o \\n', () {
        final r = cutLine(v('abcdef\r\nxy\r\nz', 6))!;
        expect(r.value.text, 'xy\r\nz');
        expect(r.value.selection.baseOffset, 2);
      });

      test('última linha sem quebra leva o \\r\\n de antes', () {
        final r = cutLine(v('aa\r\nbb', 5))!;
        expect(r.clipboard, 'bb\r\n');
        expect(r.value.text, 'aa');
        expect(r.value.selection.baseOffset, 2);
      });

      test('linha vazia final leva só o \\r\\n de antes', () {
        final r = cutLine(v('aa\r\n', 4))!;
        expect(r.clipboard, '\r\n');
        expect(r.value.text, 'aa');
      });
    });

    test('recortes seguidos removem uma linha por vez', () {
      var value = v('1\n2\n3\n4', 2);
      final clips = <String>[];
      for (var i = 0; i < 3; i++) {
        final r = cutLine(value)!;
        clips.add(r.clipboard);
        value = r.value;
      }
      expect(clips, ['2\n', '3\n', '4\n']);
      expect(value.text, '1');
      expect(value.selection.baseOffset, 1);
    });
  });

  group('pasteLineAbove', () {
    test('insere acima da linha do cursor e o cursor desce junto', () {
      final r = pasteLineAbove(v('aaa\nbbb', 6), 'xx\n');
      expect(r.text, 'aaa\nxx\nbbb');
      expect(r.selection, const TextSelection.collapsed(offset: 9));
    });

    test('na primeira linha', () {
      final r = pasteLineAbove(v('aaa', 1), 'xx\n');
      expect(r.text, 'xx\naaa');
      expect(r.selection.baseOffset, 4);
    });

    test('na linha vazia final', () {
      final r = pasteLineAbove(v('aaa\n', 4), 'xx\n');
      expect(r.text, 'aaa\nxx\n');
      expect(r.selection.baseOffset, 7);
    });

    test('texto sem quebra ganha \\n', () {
      final r = pasteLineAbove(v('aaa', 0), 'hello');
      expect(r.text, 'hello\naaa');
      expect(r.selection.baseOffset, 6);
    });

    test('texto sem quebra ganha \\r\\n num documento \\r\\n', () {
      final r = pasteLineAbove(v('aa\r\nbb', 4), 'hello');
      expect(r.text, 'aa\r\nhello\r\nbb');
    });

    test('documento vazio', () {
      final r = pasteLineAbove(v('', 0), 'hello');
      expect(r.text, 'hello\n');
      expect(r.selection.baseOffset, 6);
    });

    test('com seleção devolve o valor intacto', () {
      final value = v('aaa\nbbb', 0, 2);
      expect(pasteLineAbove(value, 'xx\n'), same(value));
    });

    test('recortar e colar devolve o texto original', () {
      const text = 'a\r\nbb\r\nccc';
      final cut = cutLine(v(text, 4))!;
      final back = pasteLineAbove(cut.value, cut.clipboard);
      expect(back.text, text);
    });
  });
}
