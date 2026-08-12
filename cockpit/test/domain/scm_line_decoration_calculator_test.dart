import 'package:cockpit/app/cockpit/domain/entities/scm_line_decorations.dart';
import 'package:cockpit/app/cockpit/domain/services/scm_line_decoration_calculator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const calc = ScmLineDecorationCalculator();

  group('ScmLineDecorations value', () {
    test('empty e igualdade por valor', () {
      expect(ScmLineDecorations.empty.isEmpty, isTrue);
      final a = ScmLineDecorations(
        addedLines: {1, 2},
        modifiedLines: {3},
        removalBoundaries: {0, 4},
      );
      final b = ScmLineDecorations(
        addedLines: {2, 1},
        modifiedLines: {3},
        removalBoundaries: {4, 0},
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(ScmLineDecorations.empty)));
    });
  });

  group('cálculo', () {
    test('conteúdo igual → vazio', () {
      expect(
        calc.calculate(baseline: 'a\nb\n', current: 'a\nb\n'),
        ScmLineDecorations.empty,
      );
    });

    test('inserções puras → added', () {
      final result = calc.calculate(baseline: 'a\nc\n', current: 'a\nb\nc\n');
      expect(result.addedLines, {2});
      expect(result.modifiedLines, isEmpty);
      expect(result.removalBoundaries, isEmpty);
    });

    test('substituição 1:1 → modified', () {
      final result = calc.calculate(
        baseline: 'a\nold\nc\n',
        current: 'a\nnew\nc\n',
      );
      expect(result.modifiedLines, {2});
      expect(result.addedLines, isEmpty);
      expect(result.removalBoundaries, isEmpty);
    });

    test('bloco desbalanceado: mais inserts → modified + added', () {
      final result = calc.calculate(
        baseline: 'a\nx\nd\n',
        current: 'a\ny\nz\nd\n',
      );
      expect(result.modifiedLines, {2});
      expect(result.addedLines, {3});
      expect(result.removalBoundaries, isEmpty);
    });

    test('bloco desbalanceado: mais deletes → modified + removal', () {
      final result = calc.calculate(
        baseline: 'a\nx\ny\nd\n',
        current: 'a\nz\nd\n',
      );
      expect(result.modifiedLines, {2});
      expect(result.addedLines, isEmpty);
      // Sobras do baseline após o par → fronteira depois da linha modificada.
      expect(result.removalBoundaries, {2});
    });

    test('remoção no início → boundary 0', () {
      final result = calc.calculate(
        baseline: 'gone\na\nb\n',
        current: 'a\nb\n',
      );
      expect(result.removalBoundaries, {0});
      expect(result.addedLines, isEmpty);
      expect(result.modifiedLines, isEmpty);
    });

    test('remoção no meio → boundary antes da sobrevivente', () {
      final result = calc.calculate(
        baseline: 'a\ngone\nb\n',
        current: 'a\nb\n',
      );
      // Remoção antes da linha atual 2 ("b") → boundary 1.
      expect(result.removalBoundaries, {1});
    });

    test('remoção no fim → boundary após última linha sobrevivente', () {
      // Sem newline final comum: current ["a","b"] → lineCount 2.
      final result = calc.calculate(baseline: 'a\nb\ngone', current: 'a\nb');
      expect(result.removalBoundaries, {2});
    });

    test('remoção no fim com newline final alinhada', () {
      // Trailing "" casa nos dois lados; "gone" some antes dele → boundary 2.
      final result = calc.calculate(
        baseline: 'a\nb\ngone\n',
        current: 'a\nb\n',
      );
      expect(result.removalBoundaries, {2});
    });

    test('múltiplas linhas adjacentes removidas → uma fronteira', () {
      final result = calc.calculate(
        baseline: 'a\nx\ny\nz\nb\n',
        current: 'a\nb\n',
      );
      expect(result.removalBoundaries, {1});
      expect(result.removalBoundaries.length, 1);
    });

    test('arquivo vazio vs conteúdo → linhas novas added', () {
      // '' → [""]; 'a\nb\n' → ["a","b",""] — o "" final casa → added {1,2}.
      final result = calc.calculate(baseline: '', current: 'a\nb\n');
      expect(result.addedLines, {1, 2});
      expect(result.modifiedLines, isEmpty);
      expect(result.removalBoundaries, isEmpty);
    });

    test('conteúdo vs arquivo vazio → remoção', () {
      final result = calc.calculate(baseline: 'a\nb\n', current: '');
      expect(result.isEmpty, isFalse);
    });

    test('newline final preservada (ambos com \\n)', () {
      final result = calc.calculate(baseline: 'a\nb\n', current: 'a\nB\n');
      expect(result.modifiedLines, {2});
      expect(result.addedLines, isEmpty);
      expect(result.removalBoundaries, isEmpty);
    });

    test('múltiplos hunks independentes', () {
      final result = calc.calculate(
        baseline: 'a\nold1\nc\nold2\ne\n',
        current: 'a\nnew1\nc\nnew2\ne\n',
      );
      expect(result.modifiedLines, {2, 4});
      expect(result.addedLines, isEmpty);
      expect(result.removalBoundaries, isEmpty);
    });
  });

  test('arquivo grande: cálculo puro via compute, sem I/O', () async {
    final baseline = StringBuffer();
    final current = StringBuffer();
    for (var i = 0; i < 2000; i++) {
      baseline.writeln('line-$i');
      if (i == 100) {
        current.writeln('CHANGED');
      } else if (i == 500) {
        current.writeln('line-$i');
        current.writeln('INSERTED');
      } else if (i == 1500) {
        // omit — remoção
      } else {
        current.writeln('line-$i');
      }
    }

    final args = (baseline: baseline.toString(), current: current.toString());
    final result = await compute(_calcIsolate, args);

    expect(result.modifiedLines, contains(101));
    expect(result.addedLines, isNotEmpty);
    expect(result.removalBoundaries, isNotEmpty);
  });
}

ScmLineDecorations _calcIsolate(({String baseline, String current}) args) {
  const calc = ScmLineDecorationCalculator();
  return calc.calculate(baseline: args.baseline, current: args.current);
}
