import 'dart:io';

import 'package:cockpit/app/cockpit/data/db/anaki_db_driver.dart';
import 'package:cockpit/app/cockpit/domain/entities/db_connection.dart';
import 'package:cockpit/app/cockpit/domain/entities/db_result.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exercita o [AnakiDbDriver] contra um sqlite REAL em arquivo temporário —
/// via o conector Rust do anakiORM.
///
/// O binário nativo é responsabilidade do pacote `anaki_sqlite` (native
/// assets). Se o loader não encontrar a lib (pacote sem binário empacotado),
/// os testes são **pulados**, não quebrados — o problema, nesse caso, é do
/// pacote anaki (issue #4), não do Cockpit.
void main() {
  const driver = AnakiDbDriver();
  late Directory dir;
  late String dbPath;
  var libAvailable = false;

  DbConnection conn() => DbConnection.sqlite('test', dbPath);

  setUpAll(() async {
    try {
      // Toca o driver de leve. O loader do anaki embrulha "lib nativa não
      // encontrada" como DbQueryException(connection_failed, 'Failed to load
      // native library...') — só ISSO significa binário ausente; qualquer
      // outro erro é o driver de fato carregado.
      await driver.execute(
        DbConnection.sqlite('probe', '${Directory.systemTemp.path}/probe.db'),
        'SELECT 1',
      );
      libAvailable = true;
    } on DbQueryException catch (e) {
      libAvailable = !e.message.contains('Failed to load native library');
    } catch (_) {
      libAvailable = false;
    }
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('cockpit_anaki_test');
    dbPath = '${dir.path}/test.db';
    if (!libAvailable) return;
    // Seed via o próprio driver (o sqlx abre com mode=rwc — cria o arquivo).
    await driver.execute(
      conn(),
      'CREATE TABLE orders (id INTEGER PRIMARY KEY, customer TEXT, total REAL)',
    );
    for (var i = 1; i <= 10; i++) {
      await driver.execute(
        conn(),
        "INSERT INTO orders (customer, total) VALUES ('c$i', ${i * 1.5})",
      );
    }
  });

  tearDown(() => dir.delete(recursive: true));

  test('query devolve linhas', () async {
    if (!libAvailable) return markTestSkipped('libanaki_sqlite.dylib ausente');
    final r = await driver.query(
      conn(),
      'SELECT id, customer, total FROM orders ORDER BY id',
      limit: 100,
    );
    expect(r.columns.map((c) => c.name), containsAll(['id', 'customer', 'total']));
    expect(r.rows, hasLength(10));
    expect(r.truncated, isFalse);
    // Linha 1 por nome de coluna (ordem das colunas é a do JSON do anaki).
    final byName = Map.fromIterables(r.columns.map((c) => c.name), r.rows.first);
    expect(byName['id'], 1);
    expect(byName['customer'], 'c1');
    expect(byName['total'], 1.5);
  });

  test('limit corta e marca truncated', () async {
    if (!libAvailable) return markTestSkipped('libanaki_sqlite.dylib ausente');
    final r = await driver.query(conn(), 'SELECT * FROM orders', limit: 3);
    expect(r.rows, hasLength(3));
    expect(r.truncated, isTrue);
  });

  test('execute devolve affectedRows', () async {
    if (!libAvailable) return markTestSkipped('libanaki_sqlite.dylib ausente');
    final r = await driver.execute(
      conn(),
      "UPDATE orders SET customer = 'x' WHERE id <= 4",
    );
    expect(r.affectedRows, 4);
  });

  test('schema lista tabelas e colunas', () async {
    if (!libAvailable) return markTestSkipped('libanaki_sqlite.dylib ausente');
    final tables = await driver.schema(conn());
    final tIx = tables.columns.indexWhere((c) => c.name == 'table');
    expect(tables.rows.map((r) => r[tIx]), contains('orders'));

    final cols = await driver.schema(conn(), table: 'orders');
    final cIx = cols.columns.indexWhere((c) => c.name == 'column');
    expect(cols.rows.map((r) => r[cIx]), containsAll(['id', 'customer', 'total']));
  });

  test('erro de SQL vira DbQueryException query_failed', () async {
    if (!libAvailable) return markTestSkipped('libanaki_sqlite.dylib ausente');
    expect(
      () => driver.query(conn(), 'SELECT * FROM nada', limit: 10),
      throwsA(
        isA<DbQueryException>().having((e) => e.kind, 'kind', 'query_failed'),
      ),
    );
  });
}
