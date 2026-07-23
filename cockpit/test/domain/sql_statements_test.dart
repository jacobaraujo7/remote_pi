import 'package:cockpit/app/cockpit/domain/entities/sql_statements.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('splitSqlStatements', () {
    test('divide por ; e descarta o vazio final', () {
      final s = splitSqlStatements('SELECT 1;\nSELECT 2;\n');
      expect(s.map((e) => e.text), ['SELECT 1', 'SELECT 2']);
    });

    test('último statement sem ; conta', () {
      final s = splitSqlStatements('SELECT 1;\nSELECT 2');
      expect(s.map((e) => e.text), ['SELECT 1', 'SELECT 2']);
    });

    test('; dentro de string não divide (incl. escape duplicado)', () {
      final s = splitSqlStatements(
        "SELECT 'a;b';\nSELECT 'it''s;fine';\nSELECT \"x;y\"",
      );
      expect(s, hasLength(3));
      expect(s[1].text, "SELECT 'it''s;fine'");
    });

    test('; em comentário de linha e de bloco não divide', () {
      final s = splitSqlStatements(
        'SELECT 1 -- tem ; aqui\n;\nSELECT /* a;b */ 2;',
      );
      expect(s.map((e) => e.text), [
        'SELECT 1 -- tem ; aqui',
        'SELECT /* a;b */ 2',
      ]);
    });

    test('chunk só de comentário é descartado', () {
      final s = splitSqlStatements('-- cabeçalho\n;\nSELECT 1;');
      expect(s.map((e) => e.text), ['SELECT 1']);
    });

    test('offsets cobrem o buffer original', () {
      const src = 'SELECT 1;\nSELECT 2;';
      final s = splitSqlStatements(src);
      expect(src.substring(s[0].start, s[0].end), 'SELECT 1;');
      expect(src.substring(s[1].start, s[1].end).trim(), 'SELECT 2;');
    });
  });

  group('statementAt', () {
    const src = 'SELECT 1;\n\nSELECT 2;\n';
    final stmts = splitSqlStatements(src);

    test('cursor dentro do statement', () {
      expect(statementAt(stmts, 3)!.text, 'SELECT 1');
      expect(statementAt(stmts, 14)!.text, 'SELECT 2');
    });

    test('cursor no whitespace após ; pega o anterior', () {
      expect(statementAt(stmts, 9)!.text, 'SELECT 1');
    });

    test('cursor no fim do buffer pega o último', () {
      expect(statementAt(stmts, src.length)!.text, 'SELECT 2');
    });
  });

  group('statementsInRange', () {
    const src = 'SELECT 1;\nSELECT 2;\nSELECT 3;';
    final stmts = splitSqlStatements(src);

    test('seleção parcial expande pros statements tocados', () {
      // Do meio do 1º ao começo do 2º.
      final hit = statementsInRange(stmts, 4, 12);
      expect(hit.map((e) => e.text), ['SELECT 1', 'SELECT 2']);
    });

    test('seleção dentro de um só statement', () {
      final hit = statementsInRange(stmts, 11, 15);
      expect(hit.map((e) => e.text), ['SELECT 2']);
    });
  });
}
