import 'package:cockpit/app/cockpit/domain/contracts/db_connection_store.dart';
import 'package:cockpit/app/cockpit/domain/contracts/db_driver.dart';
import 'package:cockpit/app/cockpit/domain/contracts/nosql_runner.dart';
import 'package:cockpit/app/cockpit/domain/entities/db_connection.dart';
import 'package:cockpit/app/cockpit/domain/entities/db_result.dart';
import 'package:cockpit/app/cockpit/domain/services/db_query_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/mongo_database_store_fake.dart';
import 'fakes/ssh_fakes.dart';

/// Plano 62: num workspace REMOTO o segredo mora no cofre do host, e o cliente
/// deixa de mandá-lo pelo fio.
///
/// O bug que isto trava: a chave do cofre local era
/// `cockpit.db.<workspaceId>.<conn>`, e o `workspaceId` é derivado por
/// máquina. A senha cadastrada num cliente nunca era achada por outro — a
/// conexão só funcionava no computador que a criou.
void main() {
  DbConnection pg({bool savePassword = true}) => DbConnection.network(
    name: 'prod',
    engine: DbEngine.postgres,
    host: 'db.internal',
    database: 'app',
    user: 'postgres',
    savePassword: savePassword,
  );

  ({DbQueryService service, _RecordingRemote remote}) build(
    List<DbConnection> conns, {
    Map<String, String> vault = const {},
  }) {
    final remote = _RecordingRemote();
    final service = DbQueryService(
      _FakeStore(conns),
      _MapSecrets(Map.of(vault)),
      _FixedRegistry(_NullDriver()),
      _NullRunner(),
      FakeSshTunnel(),
      FakeSshKeyInspector(),
      FakeMongoDatabaseStore(),
    )..remoteConnectionsFor = (_, _) async => conns;
    service.remoteExecutorFor = (_) => remote.call;
    return (service: service, remote: remote);
  }

  test('com segredo guardado, a senha NÃO atravessa', () async {
    // O cofre local até tem a senha sob a chave antiga; ela não deve ser usada
    // — quem resolve agora é o host.
    final f = build(
      [pg()],
      vault: {DbQueryService.legacySecretKey('w1', 'prod'): 'senha-legada'},
    );

    await f.service.query(
      workspaceRoot: '/srv/proj',
      workspaceId: 'w1',
      connName: 'prod',
      sql: 'SELECT 1',
    );

    expect(f.remote.passwords.single, isNull);
  });

  test('a raiz do HOST vai junto — é metade da chave do segredo', () async {
    final f = build([pg()]);

    await f.service.query(
      workspaceRoot: '/srv/proj',
      workspaceId: 'w1',
      connName: 'prod',
      sql: 'SELECT 1',
    );

    expect(f.remote.roots.single, '/srv/proj');
  });

  test('sem segredo guardado, a senha da URL ainda atravessa', () async {
    // `savePassword` desligado = o usuário optou por não guardar em lugar
    // nenhum; a senha vive na URL e é isso que o host recebe.
    final conn = DbConnection(
      name: 'prod',
      engine: DbEngine.postgres,
      url: 'postgres://postgres:na-url@db.internal:5432/app',
    );
    final f = build([conn]);

    await f.service.query(
      workspaceRoot: '/srv/proj',
      workspaceId: 'w1',
      connName: 'prod',
      sql: 'SELECT 1',
    );

    expect(f.remote.passwords.single, 'na-url');
  });

  test('connections() de workspace remoto vem do HOST', () async {
    // `cockpit db list` numa aba remota respondia `{"ok":[]}` num workspace com
    // dez conexões: a função recebia só a raiz, não sabia que o workspace era
    // remoto e lia o store LOCAL — caminho que não existe no disco do cliente.
    final f = build([pg()]);

    final conns = await f.service.connections(
      '/srv/proj',
      workspaceId: 'w1',
    );

    expect(conns.single.name, 'prod');
  });

  test('connections() de workspace LOCAL segue lendo o store daqui', () async {
    final f = build([pg()]);
    // `remoteConnectionsFor` devolve null quando o workspace não é remoto — é
    // esse null que precisa levar ao store local, e não a uma lista vazia.
    f.service.remoteConnectionsFor = (_, _) => null;

    final conns = await f.service.connections('/local', workspaceId: 'w1');

    expect(conns.single.name, 'prod');
  });

  test('schema e runStatements seguem a mesma regra', () async {
    final f = build(
      [pg()],
      vault: {DbQueryService.legacySecretKey('w1', 'prod'): 'senha-legada'},
    );

    await f.service.schema(
      workspaceRoot: '/srv/proj',
      workspaceId: 'w1',
      connName: 'prod',
    );
    await f.service.runStatements(
      workspaceRoot: '/srv/proj',
      workspaceId: 'w1',
      connName: 'prod',
      statements: const ['SELECT 1'],
    );

    expect(f.remote.passwords, everyElement(isNull));
    expect(f.remote.roots, everyElement('/srv/proj'));
  });
}

/// Executor remoto que só anota o que o serviço lhe entregaria.
class _RecordingRemote {
  final passwords = <String?>[];
  final roots = <String>[];

  Future<DbResult> call(
    DbConnection conn,
    String sql, {
    required int limit,
    required bool dml,
    String? password,
    required String workspaceRoot,
  }) async {
    passwords.add(password);
    roots.add(workspaceRoot);
    return const DbResult(columns: [], rows: [], elapsed: Duration.zero);
  }
}

class _FakeStore implements DbConnectionStore {
  _FakeStore(this.conns);
  final List<DbConnection> conns;
  @override
  Future<List<DbConnection>> load(String workspaceRoot) async => conns;
  @override
  Future<void> save(String root, List<DbConnection> connections) async {}
}

class _MapSecrets implements DbSecrets {
  _MapSecrets(this.values);
  final Map<String, String> values;
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<String?> read(String key, {String? legacyKey}) async => values[key];
  @override
  Future<void> delete(String key) async => values.remove(key);
}

class _FixedRegistry implements DbDriverRegistry {
  _FixedRegistry(this.driver);
  final DbDriver driver;
  @override
  DbDriver? forEngine(DbEngine engine) => driver;
}

/// O caminho remoto nunca deve chegar no driver local; se chegar, o teste
/// falha aqui em vez de passar silenciosamente.
class _NullDriver implements DbDriver {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('driver local não deve ser usado num workspace remoto');
}

class _NullRunner implements NoSqlRunner {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('runner local não deve ser usado num workspace remoto');
}
