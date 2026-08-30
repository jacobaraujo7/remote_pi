import 'package:cockpit/app/cockpit/domain/contracts/db_connection_store.dart';
import 'package:cockpit/app/cockpit/domain/contracts/db_driver.dart';
import 'package:cockpit/app/cockpit/domain/contracts/nosql_runner.dart';
import 'package:cockpit/app/cockpit/domain/entities/db_connection.dart';
import 'package:cockpit/app/cockpit/domain/services/db_query_service.dart';
import 'package:cockpit/app/cockpit/domain/services/mongo_browse_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/mongo_database_store_fake.dart';
import 'fakes/ssh_fakes.dart';

/// URL de Atlas como o dialog salva: SRV, **sem** path de database (o
/// `authSource` viaja no TXT do DNS, não na URL).
const _atlasUrl =
    'mongodb+srv://user:pw@cluster0.example.mongodb.net/'
    '?retryWrites=true&w=majority';

class _Runner implements NoSqlRunner {
  /// Database recebido em cada chamada, na ordem.
  final targets = <String?>[];
  Object? reply;

  @override
  Future<Object?> mongo(
    DbConnection conn,
    Map<String, dynamic> command, {
    String? password,
    String? database,
  String workspaceRoot = '',
  }) async {
    targets.add(database);
    return reply ?? {'ok': 1};
  }

  @override
  Future<Object?> redis(
    DbConnection conn,
    List<String> parts, {
    String? password,
  String workspaceRoot = '',
  }) async => null;

  @override
  Future<List<Object?>> redisMany(
    DbConnection conn,
    List<List<String>> cmds, {
    String? password,
  String workspaceRoot = '',
  }) async => const [];
}

class _Store implements DbConnectionStore {
  _Store(this.conns);
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
  Future<String?> read(String key, {String? legacyKey}) async => null;
  @override
  Future<void> delete(String key) async {}
}

class _NoRegistry implements DbDriverRegistry {
  @override
  DbDriver? forEngine(DbEngine engine) => null;
}

void main() {
  late _Runner runner;

  DbQueryService build(DbConnection conn, {FakeMongoDatabaseStore? choices}) {
    runner = _Runner();
    return DbQueryService(
      _Store([conn]),
      _NoSecrets(),
      _NoRegistry(),
      runner,
      FakeSshTunnel(),
      FakeSshKeyInspector(),
      choices ?? FakeMongoDatabaseStore(),
    );
  }

  DbConnection atlas() =>
      const DbConnection(name: 'atlas', engine: DbEngine.mongo, url: _atlasUrl);

  DbConnection withPath() => const DbConnection(
    name: 'atlas',
    engine: DbEngine.mongo,
    url: 'mongodb+srv://user:pw@cluster0.example.mongodb.net/Shop?w=majority',
  );

  Future<void> run(DbQueryService db) => db.mongoCommand(
    workspaceRoot: '/ws',
    workspaceId: 'ws1',
    connName: 'atlas',
    command: const {'listCollections': 1},
  );

  test('URL sem database e sem escolha: runner decide o fallback', () async {
    final db = build(atlas());
    await run(db);
    expect(runner.targets, [null]);
  });

  test('escolha salva vira o database do comando', () async {
    final db = build(
      atlas(),
      choices: FakeMongoDatabaseStore({'ws1::atlas': 'Shop'}),
    );
    await run(db);
    expect(runner.targets, ['Shop']);
  });

  test('database na URL vence a escolha salva', () async {
    final db = build(
      withPath(),
      choices: FakeMongoDatabaseStore({'ws1::atlas': 'Other'}),
    );
    await run(db);
    expect(runner.targets, ['Shop']);
    expect(db.mongoNeedsDatabase(withPath()), isFalse);
  });

  test('selectMongoDatabase persiste e passa a valer', () async {
    final db = build(atlas());
    await db.selectMongoDatabase('ws1', 'atlas', 'Shop');
    await run(db);
    expect(runner.targets, ['Shop']);
    expect(db.mongoNeedsDatabase(atlas()), isTrue);
  });

  test('escolha é por workspace: outro workspace não herda', () async {
    final db = build(
      atlas(),
      choices: FakeMongoDatabaseStore({'ws1::atlas': 'Shop'}),
    );
    await db.mongoCommand(
      workspaceRoot: '/ws',
      workspaceId: 'ws2',
      connName: 'atlas',
      command: const {'listCollections': 1},
    );
    expect(runner.targets, [null]);
  });

  test('listCollections(database:) não depende da escolha corrente', () async {
    final db = build(
      atlas(),
      choices: FakeMongoDatabaseStore({'ws1::atlas': 'Shop'}),
    );
    final service = MongoBrowseService(db)
      ..target(workspaceRoot: '/ws', workspaceId: 'ws1', connName: 'atlas');

    await service.listCollections(database: 'Analytics');
    // A árvore do painel expande N databases; cada ramo lista o seu, sem
    // trocar o database corrente da conexão.
    expect(runner.targets, ['Analytics']);
  });

  test('listDatabases roda no admin e esconde os de sistema', () async {
    final db = build(atlas());
    runner.reply = {
      'ok': 1,
      'databases': [
        {'name': 'local'},
        {'name': 'Shop'},
        {'name': 'admin'},
        {'name': 'Analytics'},
        {'name': 'config'},
      ],
    };
    final service = MongoBrowseService(db)
      ..target(workspaceRoot: '/ws', workspaceId: 'ws1', connName: 'atlas');

    expect(await service.listDatabases(), ['Analytics', 'Shop']);
    // Forçado, senão dependeria da escolha que ele existe pra permitir.
    expect(runner.targets, ['admin']);
  });
}
