import 'package:cockpit/app/cockpit/domain/entities/db_connection.dart';
import 'package:cockpit/app/cockpit/domain/services/db_access_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sqlReadViolation', () {
    test('leitura passa', () {
      expect(sqlReadViolation('SELECT * FROM users'), isNull);
      expect(sqlReadViolation('  select 1;  '), isNull);
      expect(sqlReadViolation('EXPLAIN SELECT * FROM t'), isNull);
      expect(sqlReadViolation('SHOW TABLES'), isNull);
      expect(sqlReadViolation('SHOW CREATE TABLE users'), isNull);
      expect(sqlReadViolation('DESCRIBE users'), isNull);
      expect(sqlReadViolation('PRAGMA table_info(users)'), isNull);
      expect(
        sqlReadViolation('WITH x AS (SELECT 1) SELECT * FROM x'),
        isNull,
      );
      expect(
        sqlReadViolation('SELECT updated_at, created_by FROM t'),
        isNull,
      );
    });

    test('escrita é recusada', () {
      expect(sqlReadViolation('DELETE FROM users'), isNotNull);
      expect(sqlReadViolation('DROP TABLE users'), isNotNull);
      expect(sqlReadViolation('INSERT INTO t VALUES (1)'), isNotNull);
      expect(sqlReadViolation('UPDATE t SET a = 1'), isNotNull);
      expect(sqlReadViolation('TRUNCATE t'), isNotNull);
      expect(sqlReadViolation('CREATE TABLE t (a int)'), isNotNull);
    });

    test('escrita escondida em script ou CTE é recusada', () {
      expect(
        sqlReadViolation('SELECT 1; DELETE FROM users'),
        isNotNull,
      );
      expect(
        sqlReadViolation('WITH x AS (SELECT 1) INSERT INTO t SELECT * FROM x'),
        isNotNull,
      );
      expect(
        sqlReadViolation('EXPLAIN ANALYZE DELETE FROM t'),
        isNotNull,
      );
    });

    test('pragma com atribuição é recusado; comentários não enganam', () {
      expect(sqlReadViolation('PRAGMA journal_mode = WAL'), isNotNull);
      expect(
        sqlReadViolation('-- DELETE FROM t\nSELECT 1'),
        isNull,
      );
    });
  });

  group('redisReadViolation', () {
    test('leitura passa, escrita não', () {
      expect(redisReadViolation(['GET', 'k']), isNull);
      expect(redisReadViolation(['SCAN', '0']), isNull);
      expect(redisReadViolation(['HGETALL', 'h']), isNull);
      expect(redisReadViolation(['CONFIG', 'GET', 'maxmemory']), isNull);
      expect(redisReadViolation(['SET', 'k', 'v']), isNotNull);
      expect(redisReadViolation(['DEL', 'k']), isNotNull);
      expect(redisReadViolation(['FLUSHALL']), isNotNull);
      expect(redisReadViolation(['CONFIG', 'SET', 'x', 'y']), isNotNull);
    });
  });

  group('mongoReadViolation', () {
    test('leitura passa, escrita não', () {
      expect(mongoReadViolation({'find': 'users'}), isNull);
      expect(mongoReadViolation({'count': 'users'}), isNull);
      expect(
        mongoReadViolation({
          'aggregate': 'users',
          'pipeline': [
            {r'$match': {}},
          ],
        }),
        isNull,
      );
      expect(mongoReadViolation({'insert': 'users'}), isNotNull);
      expect(mongoReadViolation({'delete': 'users'}), isNotNull);
      expect(mongoReadViolation({'drop': 'users'}), isNotNull);
      expect(
        mongoReadViolation({
          'aggregate': 'users',
          'pipeline': [
            {r'$out': 'other'},
          ],
        }),
        isNotNull,
      );
    });
  });

  group('DbConnection access/agents', () {
    test('JSON legado (sem campos) → read + visível', () {
      final conn = DbConnection.fromJson({
        'name': 'legacy',
        'url': 'sqlite:./app.db',
      });
      expect(conn.access, DbAccess.read);
      expect(conn.agents, isTrue);
    });

    test('roundtrip persiste access e agents', () {
      final conn = DbConnection.fromJson({
        'name': 'prod',
        'url': 'postgres://u@h:5432/db',
        'access': 'readwrite',
        'agents': false,
      });
      expect(conn.access, DbAccess.readwrite);
      expect(conn.agents, isFalse);
      final json = conn.toJson();
      expect(json['access'], 'readwrite');
      expect(json['agents'], false);
    });
  });
}
