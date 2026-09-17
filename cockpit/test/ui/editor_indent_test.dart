import 'package:cockpit/app/cockpit/ui/widgets/editor_indent.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

TextEditingValue v(String text, int base, [int? extent]) => TextEditingValue(
  text: text,
  selection: TextSelection(baseOffset: base, extentOffset: extent ?? base),
);

void main() {
  group('detectIndentUnit', () {
    test('tabs when indented lines start with a tab', () {
      final unit = detectIndentUnit('a\n\tb\n\t\tc\n', path: 'x.go');
      expect(unit.useTabs, isTrue);
      expect(unit.text, '\t');
    });

    test('2 spaces from content', () {
      final unit = detectIndentUnit('a\n  b\n    c\n  d\n', path: 'x.py');
      expect(unit, const IndentUnit.spaces(2));
    });

    test('4 spaces from content', () {
      final unit = detectIndentUnit('a\n    b\n        c\n', path: 'x.dart');
      expect(unit, const IndentUnit.spaces(4));
    });

    test('fallback by extension when nothing is indented', () {
      expect(
        detectIndentUnit('a\nb\n', path: 'x.dart'),
        const IndentUnit.spaces(2),
      );
      expect(
        detectIndentUnit('a\nb\n', path: 'x.yml'),
        const IndentUnit.spaces(2),
      );
      expect(
        detectIndentUnit('a\nb\n', path: 'x.md'),
        const IndentUnit.spaces(2),
      );
      expect(
        detectIndentUnit('a\nb\n', path: 'x.py'),
        const IndentUnit.spaces(4),
      );
      expect(
        detectIndentUnit('', path: 'Makefile'),
        const IndentUnit.spaces(4),
      );
      expect(detectIndentUnit('', path: null), const IndentUnit.spaces(4));
    });

    test('empty text with tabs extension fallback', () {
      expect(
        detectIndentUnit('  \n\n', path: 'a/b.ts'),
        const IndentUnit.spaces(2),
      );
    });
  });

  group('applyIndent', () {
    test(
      'collapsed cursor mid-line inserts spaces up to the next tab stop',
      () {
        final out = applyIndent(v('abc', 3), const IndentUnit.spaces(4));
        expect(out.text, 'abc ');
        expect(out.selection.baseOffset, 4);

        final out2 = applyIndent(v('abc', 1), const IndentUnit.spaces(4));
        expect(out2.text, 'a   bc');
        expect(out2.selection.baseOffset, 4);
      },
    );

    test('collapsed cursor at column 0 inserts a full unit', () {
      final out = applyIndent(v('x\nabc', 2), const IndentUnit.spaces(2));
      expect(out.text, 'x\n  abc');
      expect(out.selection.baseOffset, 4);
    });

    test('tabs insert a real tab', () {
      final out = applyIndent(v('abc', 1), const IndentUnit.tabs());
      expect(out.text, 'a\tbc');
      expect(out.selection.baseOffset, 2);
    });

    test('single-line selection is replaced by the indentation', () {
      final out = applyIndent(v('abcdef', 2, 4), const IndentUnit.spaces(4));
      expect(out.text, 'ab  ef');
      expect(out.selection.isCollapsed, isTrue);
      expect(out.selection.baseOffset, 4);
    });

    test('multi-line selection indents every line and keeps coverage', () {
      const text = 'one\ntwo\nthree';
      final out = applyIndent(v(text, 1, 9), const IndentUnit.spaces(2));
      expect(out.text, '  one\n  two\n  three');
      // 'ne\n  two\n  t' continues to cover the same three lines.
      expect(out.selection.start, 3);
      expect(out.selection.end, 15);
      expect(
        out.text.substring(out.selection.start, out.selection.end),
        'ne\n  two\n  t',
      );
    });

    test('selection ending at column 0 does not indent that line', () {
      const text = 'one\ntwo\nthree';
      final out = applyIndent(v(text, 0, 8), const IndentUnit.spaces(2));
      expect(out.text, '  one\n  two\nthree');
      expect(out.selection.start, 0);
      expect(out.selection.end, 12);
    });

    test('backward selection keeps its direction', () {
      final out = applyIndent(v('a\nb', 3, 0), const IndentUnit.spaces(2));
      expect(out.selection.baseOffset, 7);
      expect(out.selection.extentOffset, 0);
    });
  });

  group('applyOutdent', () {
    test('collapsed cursor outdents the current line', () {
      final out = applyOutdent(v('    abc', 6), const IndentUnit.spaces(4));
      expect(out.text, 'abc');
      expect(out.selection.baseOffset, 2);
    });

    test('removes at most one unit and clamps the cursor to line start', () {
      final out = applyOutdent(v('      abc', 1), const IndentUnit.spaces(4));
      expect(out.text, '  abc');
      expect(out.selection.baseOffset, 0);
    });

    test('removes partial indentation smaller than the unit', () {
      final out = applyOutdent(v('  abc', 4), const IndentUnit.spaces(4));
      expect(out.text, 'abc');
      expect(out.selection.baseOffset, 2);
    });

    test('tabs remove a single tab', () {
      final out = applyOutdent(v('\t\tabc', 3), const IndentUnit.tabs());
      expect(out.text, '\tabc');
      expect(out.selection.baseOffset, 2);
    });

    test('multi-line selection outdents every line and keeps coverage', () {
      const text = '  one\n  two\nthree';
      final out = applyOutdent(v(text, 3, 14), const IndentUnit.spaces(2));
      expect(out.text, 'one\ntwo\nthree');
      expect(
        out.text.substring(out.selection.start, out.selection.end),
        'ne\ntwo\nth',
      );
    });

    test('unchanged value when nothing to remove', () {
      final value = v('abc\ndef', 1, 5);
      expect(applyOutdent(value, const IndentUnit.spaces(2)), same(value));
    });
  });
}
