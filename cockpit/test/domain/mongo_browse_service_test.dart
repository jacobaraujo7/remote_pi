import 'package:cockpit/app/cockpit/domain/contracts/db_connection_store.dart';
import 'package:cockpit/app/cockpit/domain/contracts/db_driver.dart';
import 'package:cockpit/app/cockpit/domain/contracts/nosql_runner.dart';
import 'package:cockpit/app/cockpit/domain/entities/db_connection.dart';
import 'package:cockpit/app/cockpit/domain/entities/db_result.dart';
import 'package:cockpit/app/cockpit/domain/services/db_query_service.dart';
import 'package:cockpit/app/cockpit/domain/services/mongo_browse_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runner fake: grava os runCommand enviados e devolve replies roteirizados
/// pela chave-comando (primeiro campo do documento: 'find', 'update'…).
class _FakeRunner implements NoSqlRunner {
  final commands = <Map<String, dynamic>>[];
  final replies = <String, Object?>{};

  @override
  Future<Object?> mongo(
    DbConnection conn,
    Map<String, dynamic> command, {
    String? password,
  }) async {
    commands.add(command);
    return replies[command.keys.first] ?? {'ok': 1};
  }

  @override
  Future<Object?> redis(
    DbConnection conn,
    List<String> parts, {
    String? password,
  }) async => null;

  @override
  Future<List<Object?>> redisMany(
    DbConnection conn,
    List<List<String>> cmds, {
    String? password,
  }) async => const [];
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
  late MongoBrowseService service;

  setUp(() {
    runner = _FakeRunner();
    final db = DbQueryService(
      _FakeStore([
        DbConnection.network(
          name: 'app',
          engine: DbEngine.mongo,
          host: 'localhost',
          database: 'appdb',
        ),
      ]),
      _NoSecrets(),
      _NoRegistry(),
      runner,
    );
    service = MongoBrowseService(db)
      ..target(workspaceRoot: '/ws', workspaceId: 'ws1', connName: 'app');
  });

  test('listCollections ordena os nomes do cursor', () async {
    runner.replies['listCollections'] = {
      'ok': 1,
      'cursor': {
        'firstBatch': [
          {'name': 'users'},
          {'name': 'events'},
        ],
      },
    };
    expect(await service.listCollections(), ['events', 'users']);
  });

  test('find monta o comando com filtro validado e singleBatch', () async {
    runner.replies['find'] = {
      'ok': 1,
      'cursor': {
        'firstBatch': [
          {
            '_id': {r'$oid': 'abc123'},
            'name': 'Lara',
          },
        ],
      },
    };
    final docs = await service.find(
      'users',
      filterJson: '{"active": true}',
      skip: 50,
    );
    expect(docs.single['_id'], {r'$oid': 'abc123'});
    final cmd = runner.commands.single;
    expect(cmd['find'], 'users');
    expect(cmd['filter'], {'active': true});
    expect(cmd['skip'], 50);
    expect(cmd['singleBatch'], true);
  });

  test('filtro JSON inválido lança ANTES de tocar o servidor', () async {
    await expectLater(
      service.find('users', filterJson: '{oops'),
      throwsA(isA<DbQueryException>()),
    );
    expect(runner.commands, isEmpty);
  });

  test('replaceOne ancora no _id do documento editado', () async {
    runner.replies['update'] = {'ok': 1, 'n': 1};
    await service.replaceOne(
      'users',
      '{"_id": {"\$oid": "abc"}, "name": "Marco"}',
    );
    final update = runner.commands.single;
    final entry = (update['updates'] as List).single as Map;
    expect(entry['q'], {
      '_id': {r'$oid': 'abc'},
    });
    expect((entry['u'] as Map)['name'], 'Marco');
  });

  test('replaceOne recusa documento sem _id', () async {
    await expectLater(
      service.replaceOne('users', '{"name": "Marco"}'),
      throwsA(
        isA<DbQueryException>().having(
          (e) => e.message,
          'message',
          contains('_id'),
        ),
      ),
    );
    expect(runner.commands, isEmpty);
  });

  test('erro do servidor (ok: 0 / writeErrors) vira exceção', () async {
    runner.replies['insert'] = {
      'ok': 1,
      'writeErrors': [
        {'errmsg': 'duplicate key'},
      ],
    };
    await expectLater(
      service.insertOne('users', '{"x": 1}'),
      throwsA(
        isA<DbQueryException>().having(
          (e) => e.message,
          'message',
          contains('duplicate key'),
        ),
      ),
    );
  });

  test('deleteOne monta o delete por _id com limit 1', () async {
    await service.deleteOne('users', {r'$oid': 'abc'});
    final del = runner.commands.single;
    final entry = (del['deletes'] as List).single as Map;
    expect(entry['q'], {
      '_id': {r'$oid': 'abc'},
    });
    expect(entry['limit'], 1);
  });
}
