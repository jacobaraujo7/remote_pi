import 'package:cockpit/app/cockpit/ui/widgets/editor_comment.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

TextEditingValue v(String text, int base, [int? extent]) => TextEditingValue(
  text: text,
  selection: TextSelection(baseOffset: base, extentOffset: extent ?? base),
);

void main() {
  const dart = CommentSyntax.line('//');
  const sql = CommentSyntax.line('--');
  const html = CommentSyntax.block('<!--', '-->');

  group('commentSyntaxFor', () {
    test('resolve pelo id/extensão', () {
      expect(commentSyntaxFor('dart')!.line, '//');
      expect(commentSyntaxFor('py')!.line, '#');
      expect(commentSyntaxFor('sql')!.line, '--');
      expect(commentSyntaxFor('dbq')!.line, '--');
      expect(commentSyntaxFor('http')!.line, '#');
      expect(commentSyntaxFor('yml')!.line, '#');
      expect(commentSyntaxFor('html')!.isBlock, isTrue);
      expect(commentSyntaxFor('css')!.blockStart, '/*');
    });

    test('desconhecida → null (atalho não faz nada)', () {
      expect(commentSyntaxFor('xyz'), isNull);
      expect(commentSyntaxFor(null), isNull);
    });
  });

  group('addLineComment', () {
    test('linha única, cursor desloca', () {
      final r = addLineComment(v('int a = 1;', 4), dart);
      expect(r.text, '// int a = 1;');
      expect(r.selection.baseOffset, 7);
    });

    test('bloco: token na menor indentação, vazia pulada', () {
      final r = addLineComment(v('  a\n\n    b\n', 0, 10), dart);
      expect(r.text, '  // a\n\n  //   b\n');
    });

    test('comentada ganha outra camada (VS Code)', () {
      final r = addLineComment(v('// a', 0), dart);
      expect(r.text, '// // a');
    });

    test('sql no .dbq usa --', () {
      final r = addLineComment(v('select 1', 0), sql);
      expect(r.text, '-- select 1');
    });

    test('html embrulha a linha', () {
      final r = addLineComment(v('<p>x</p>', 0), html);
      expect(r.text, '<!-- <p>x</p> -->');
    });
  });

  group('removeLineComment', () {
    test('remove token e um espaço', () {
      final r = removeLineComment(v('  // a', 6), dart);
      expect(r.text, '  a');
      expect(r.selection.baseOffset, 3);
    });

    test('linha sem comentário fica igual', () {
      final r = removeLineComment(v('a\n// b\n', 0, 7), dart);
      expect(r.text, 'a\nb\n');
    });

    test('html desembrulha', () {
      final r = removeLineComment(v('<!-- <p>x</p> -->', 0), html);
      expect(r.text, '<p>x</p>');
    });
  });

  group('toggleLineComment', () {
    test('todas comentadas → descomenta', () {
      final r = toggleLineComment(v('// a\n// b', 0, 9), dart);
      expect(r.text, 'a\nb');
    });

    test('mista → comenta todas', () {
      final r = toggleLineComment(v('// a\nb', 0, 6), dart);
      expect(r.text, '// // a\n// b');
    });

    test('seleção que termina na coluna 0 não pega a linha seguinte', () {
      final r = toggleLineComment(v('a\nb\n', 0, 2), dart);
      expect(r.text, '// a\nb\n');
    });
  });
}
