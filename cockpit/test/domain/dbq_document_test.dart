import 'package:cockpit/app/cockpit/domain/entities/dbq_document.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DbqDocument.parse', () {
    test('frontmatter completo + corpo', () {
      final d = DbqDocument.parse(
        '-- db: dev-local\n-- limit: 100\n\nSELECT * FROM orders;',
      );
      expect(d.db, 'dev-local');
      expect(d.limit, 100);
      expect(d.sql, 'SELECT * FROM orders;');
    });

    test('sem frontmatter — arquivo é só SQL', () {
      final d = DbqDocument.parse('SELECT 1;');
      expect(d.db, isNull);
      expect(d.limit, isNull);
      expect(d.sql, 'SELECT 1;');
    });

    test('comentário SQL comum no topo NÃO é frontmatter', () {
      final d = DbqDocument.parse('-- investigação de pedidos\nSELECT 1;');
      expect(d.db, isNull);
      expect(d.sql, '-- investigação de pedidos\nSELECT 1;');
    });

    test('chave desconhecida em forma key:value fica no corpo', () {
      final d = DbqDocument.parse('-- author: ana\nSELECT 1;');
      expect(d.db, isNull);
      expect(d.sql, startsWith('-- author: ana'));
    });

    test('frontmatter para no primeiro não-match', () {
      final d = DbqDocument.parse(
        '-- db: x\n-- nota solta\n-- limit: 5\nSELECT 1;',
      );
      expect(d.db, 'x');
      expect(d.limit, isNull);
      expect(d.sql, '-- nota solta\n-- limit: 5\nSELECT 1;');
    });

    test('limit inválido vira null', () {
      final d = DbqDocument.parse('-- limit: muitos\nSELECT 1;');
      expect(d.limit, isNull);
    });
  });

  group('round-trip', () {
    test('parse(serialize(d)) == d', () {
      const d = DbqDocument(db: 'staging', limit: 50, sql: 'SELECT 1;\n');
      expect(DbqDocument.parse(d.serialize()), d);
    });

    test('sem frontmatter serializa só o SQL', () {
      const d = DbqDocument(sql: 'SELECT 1;');
      expect(d.serialize(), 'SELECT 1;');
    });

    test('trocar conexão preserva o SQL byte a byte', () {
      const original = 'SELECT *\nFROM t -- comment\nWHERE a = 1;';
      final d = DbqDocument.parse(
        const DbqDocument(sql: original).serialize(),
      ).copyWith(db: 'nova');
      expect(DbqDocument.parse(d.serialize()).sql, original);
    });
  });
}
