import 'package:cockpit/app/cockpit/domain/contracts/db_connection_store.dart';
import 'package:cockpit/app/cockpit/domain/contracts/db_driver.dart';
import 'package:cockpit/app/cockpit/domain/contracts/nosql_runner.dart';
import 'package:cockpit/app/cockpit/domain/entities/db_connection.dart';
import 'package:cockpit/app/cockpit/domain/entities/db_result.dart';
import 'package:cockpit/app/cockpit/domain/entities/redis_key.dart';
import 'package:cockpit/app/cockpit/domain/services/db_query_service.dart';
import 'package:cockpit/app/cockpit/domain/services/redis_browse_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runner fake: grava os lotes enviados e devolve replies roteirizados por
/// comando (chave = primeiro token, ex.: 'SCAN', 'TYPE').
class _FakeRunner implements NoSqlRunner {
  final batches = <List<List<String>>>[];
  final replies = <String, List<Object?>>{};
  final _consumed = <String, int>{};

  Object? _replyFor(List<String> parts) {
    final cmd = parts.first;
    final list = replies[cmd];
    if (list == null) return null;
    final ix = _consumed[cmd] ?? 0;
    _consumed[cmd] = ix + 1;
    return ix < list.length ? list[ix] : list.last;
  }

  @override
  Future<List<Object?>> redisMany(
    DbConnection conn,
    List<List<String>> commands, {
    String? password,
  }) async {
    batches.add(commands);
    return [for (final c in commands) _replyFor(c)];
  }

  @override
  Future<Object?> redis(
    DbConnection conn,
    List<String> parts, {
    String? password,
  }) async => _replyFor(parts);

  @override
  Future<Object?> mongo(
    DbConnection conn,
    Map<String, dynamic> command, {
    String? password,
  }) async => null;
}

class _FakeStore implements DbConnectionStore {
  _FakeStore(this.conns);
  final List<DbConnection> conns;
  @override
  Future<List<DbConnection>> load(String workspaceRoot) async => conns;
  @override
  Future<void> save(String root, List<DbConnection> connections) async {}
}

class _NoSecrets implements DbSecrets {
  @override
  Future<void> write(String key, String value) async {}
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> delete(String key) async {}
}

class _NoRegistry implements DbDriverRegistry {
  @override
  DbDriver? forEngine(DbEngine engine) => null;
}

void main() {
  late _FakeRunner runner;
  late RedisBrowseService service;

  setUp(() {
    runner = _FakeRunner();
    final db = DbQueryService(
      _FakeStore([
        DbConnection.network(
          name: 'cache',
          engine: DbEngine.redis,
          host: 'localhost',
          database: '0',
        ),
      ]),
      _NoSecrets(),
      _NoRegistry(),
      runner,
    );
    service = RedisBrowseService(db)
      ..target(workspaceRoot: '/ws', workspaceId: 'ws1', connName: 'cache');
  });

  /// Todos os comandos enviados, achatados na ordem.
  List<List<String>> sent() => [for (final b in runner.batches) ...b];

  group('scan', () {
    test('monta a página com TYPE/TTL/preview e nunca usa KEYS', () async {
      runner.replies['SCAN'] = [
        [
          '17',
          ['counter', 'user:1'],
        ],
      ];
      runner.replies['TYPE'] = ['string', 'hash'];
      runner.replies['TTL'] = [-1, 120];
      runner.replies['GETRANGE'] = ['43'];
      runner.replies['HGETALL'] = [
        {'name': 'Lara'},
      ];

      final page = await service.scan(pattern: 'user:*');

      expect(page.cursor, '17');
      expect(page.done, isFalse);
      expect(page.entries, hasLength(2));
      expect(page.entries[0].kind, RedisValueKind.string);
      expect(page.entries[0].ttl, -1);
      expect(page.entries[0].preview, '43');
      expect(page.entries[1].kind, RedisValueKind.hash);
      expect(page.entries[1].ttl, 120);
      expect(page.entries[1].preview, '{"name":"Lara"}');

      final all = sent();
      expect(all.first, ['SCAN', '0', 'MATCH', 'user:*', 'COUNT', '100']);
      expect(all.any((c) => c.first == 'KEYS'), isFalse);
    });

    test('zset com reply plano WITHSCORES vira {value, score}', () async {
      runner.replies['SCAN'] = [
        [
          '0',
          ['scores'],
        ],
      ];
      runner.replies['TYPE'] = ['zset'];
      runner.replies['TTL'] = [-1];
      runner.replies['ZRANGE'] = [
        ['Marco', '85', 'Lara', '92'],
      ];

      final page = await service.scan();
      expect(
        page.entries.single.preview,
        '[{"value":"Marco","score":"85"},{"value":"Lara","score":"92"}]',
      );
    });
  });

  group('escrita', () {
    test('writeString usa SET … KEEPTTL (preserva expiração)', () async {
      await service.writeString('greeting', 'hello');
      expect(sent().single, ['SET', 'greeting', 'hello', 'KEEPTTL']);
    });

    test('writeComposite valida JSON ANTES de tocar o servidor', () async {
      await expectLater(
        service.writeComposite('user:1', RedisValueKind.hash, '{invalid'),
        throwsA(isA<DbQueryException>()),
      );
      expect(runner.batches, isEmpty);
    });

    test('writeComposite = DEL + recria + re-aplica TTL vigente', () async {
      runner.replies['TTL'] = [300];
      await service.writeComposite(
        'user:1',
        RedisValueKind.hash,
        '{"name": "Marco", "age": 40}',
      );
      final all = sent();
      expect(all[0], ['TTL', 'user:1']);
      expect(all[1], ['DEL', 'user:1']);
      expect(all[2], ['HSET', 'user:1', 'name', 'Marco', 'age', '40']);
      expect(all[3], ['EXPIRE', 'user:1', '300']);
    });

    test('setTtl: segundos → EXPIRE; null → PERSIST', () async {
      await service.setTtl('k', 60);
      await service.setTtl('k', null);
      expect(sent(), [
        ['EXPIRE', 'k', '60'],
        ['PERSIST', 'k'],
      ]);
    });

    test('create recusa chave existente', () async {
      runner.replies['EXISTS'] = [1];
      await expectLater(
        service.create('counter', RedisValueKind.string, '1'),
        throwsA(
          isA<DbQueryException>().having(
            (e) => e.message,
            'message',
            contains('already exists'),
          ),
        ),
      );
      // Só o EXISTS chegou ao servidor.
      expect(sent(), [
        ['EXISTS', 'counter'],
      ]);
    });

    test('rename usa RENAMENX e recusa destino existente', () async {
      runner.replies['RENAMENX'] = [1, 0];
      await service.rename('old', 'new');
      expect(sent().single, ['RENAMENX', 'old', 'new']);

      await expectLater(
        service.rename('a', 'taken'),
        throwsA(
          isA<DbQueryException>().having(
            (e) => e.message,
            'message',
            contains('already exists'),
          ),
        ),
      );
    });

    test('rename pra mesma chave é no-op (nada vai ao servidor)', () async {
      await service.rename('same', 'same');
      expect(runner.batches, isEmpty);
    });

    test('create de zset monta ZADD score member', () async {
      runner.replies['EXISTS'] = [0];
      await service.create(
        'ranks',
        RedisValueKind.zset,
        '[{"value": "Marco", "score": 85}]',
        ttl: 30,
      );
      final all = sent();
      expect(all[1], ['ZADD', 'ranks', '85', 'Marco']);
      expect(all[2], ['EXPIRE', 'ranks', '30']);
    });
  });

  group('refreshEntry', () {
    test('chave que sumiu devolve null', () async {
      runner.replies['TYPE'] = ['none'];
      runner.replies['TTL'] = [-2];
      expect(await service.refreshEntry('gone'), isNull);
    });
  });
}
