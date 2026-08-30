import 'dart:convert';

import 'package:cockpit/app/cockpit/domain/contracts/db_connection_store.dart';
import 'package:cockpit/app/cockpit/domain/contracts/db_driver.dart';
import 'package:cockpit/app/cockpit/domain/contracts/nosql_runner.dart';
import 'package:cockpit/app/cockpit/domain/entities/db_connection.dart';
import 'package:cockpit/app/cockpit/domain/entities/db_result.dart';
import 'package:cockpit/app/cockpit/domain/services/db_query_service.dart';
import 'package:cockpit_core/cockpit_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/mongo_database_store_fake.dart';
import 'fakes/ssh_fakes.dart';

/// Plano 62, onda 2: num workspace remoto quem abre o túnel do bastion é o
/// HOST, e o servidor **não pergunta nada a ninguém** — ele falha com o
/// fingerprint. A decisão fica aqui, onde existe um humano e um diálogo; o
/// estado vai para o host, que é onde o túnel abre.
void main() {
  DbConnection pg() => DbConnection.network(
    name: 'prod',
    engine: DbEngine.postgres,
    host: 'db.internal',
    database: 'app',
    user: 'postgres',
  );

  /// Falha como o servidor a manda: detail estruturado, não prosa.
  DbQueryException hostKeyUnknown() => DbQueryException(
    'ssh_tunnel_failed',
    jsonEncode({
      'kind': 'ssh_host_key_unknown',
      'message': 'Unknown host key for deploy@bastion:22 (SHA256:abc).',
      'endpoint': 'deploy@bastion:22',
      'fingerprint': 'SHA256:abc',
    }),
  );

  ({DbQueryService service, _Remote remote, List<String> trusted}) build({
    DbQueryException? failWith,
    HostKeyVerdict verdict = HostKeyVerdict.trust,
    bool withTrustHook = true,
  }) {
    final remote = _Remote(failWith);
    final trusted = <String>[];
    final service = DbQueryService(
      _FakeStore([pg()]),
      _NoSecrets(),
      _FixedRegistry(_NullDriver()),
      _NullRunner(),
      FakeSshTunnel(),
      FakeSshKeyInspector(),
      FakeMongoDatabaseStore(),
    )..remoteConnectionsFor = (_, _) async => [pg()];
    service.remoteExecutorFor = (_) => remote.call;
    service.hostKeyPrompt = (endpoint, fingerprint) async => verdict;
    if (withTrustHook) {
      service.remoteHostKeyTrustFor = (ws, endpoint, fingerprint) async =>
          trusted.add('$endpoint=$fingerprint');
    }
    return (service: service, remote: remote, trusted: trusted);
  }

  Future<DbResult> run(DbQueryService s) => s.query(
    workspaceRoot: '/srv/proj',
    workspaceId: 'w1',
    connName: 'prod',
    sql: 'SELECT 1',
  );

  test('host key desconhecida: pergunta, confia no HOST e repete', () async {
    final f = build(failWith: hostKeyUnknown());

    await run(f.service);

    expect(f.trusted.single, 'deploy@bastion:22=SHA256:abc');
    expect(f.remote.calls, 2, reason: 'uma falha + uma repetição');
  });

  test('usuário recusa: nada é confiado e o erro sobe', () async {
    final f = build(
      failWith: hostKeyUnknown(),
      verdict: HostKeyVerdict.reject,
    );

    await expectLater(run(f.service), throwsA(isA<DbQueryException>()));
    expect(f.trusted, isEmpty);
    expect(f.remote.calls, 1, reason: 'não repete o que não foi confiado');
  });

  test('chave TROCADA nunca é aceita inline', () async {
    // É exatamente o caso que o TOFU existe para pegar: pode ser reinstalação
    // do servidor — ou o ataque que o túnel deveria impedir.
    final f = build(
      failWith: DbQueryException(
        'ssh_tunnel_failed',
        jsonEncode({
          'kind': 'ssh_host_key_changed',
          'message': 'The host key changed.',
          'endpoint': 'deploy@bastion:22',
          'fingerprint': 'SHA256:outra',
        }),
      ),
    );

    await expectLater(run(f.service), throwsA(isA<DbQueryException>()));
    expect(f.trusted, isEmpty);
    expect(f.remote.calls, 1);
  });

  test('sem onde persistir a confiança, o erro sobe (caminho CLI)', () async {
    final f = build(failWith: hostKeyUnknown(), withTrustHook: false);

    await expectLater(run(f.service), throwsA(isA<DbQueryException>()));
    expect(f.remote.calls, 1);
  });

  test('outras falhas de túnel passam direto', () async {
    final f = build(
      failWith: DbQueryException(
        'ssh_tunnel_failed',
        jsonEncode({'kind': 'ssh_key_missing', 'message': 'no such key'}),
      ),
    );

    await expectLater(run(f.service), throwsA(isA<DbQueryException>()));
    expect(f.trusted, isEmpty);
    expect(f.remote.calls, 1);
  });
}

/// Executor remoto que falha [_failWith] na PRIMEIRA chamada e responde na
/// segunda — é assim que se prova que a repetição aconteceu.
class _Remote {
  _Remote(this._failWith);
  final DbQueryException? _failWith;
  int calls = 0;

  Future<DbResult> call(
    DbConnection conn,
    String sql, {
    required int limit,
    required bool dml,
    String? password,
    required String workspaceRoot,
  }) async {
    calls++;
    if (calls == 1 && _failWith != null) throw _failWith;
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

class _NoSecrets implements DbSecrets {
  @override
  Future<void> write(String key, String value) async {}
  @override
  Future<String?> read(String key, {String? legacyKey}) async => null;
  @override
  Future<void> delete(String key) async {}
}

class _FixedRegistry implements DbDriverRegistry {
  _FixedRegistry(this.driver);
  final DbDriver driver;
  @override
  DbDriver? forEngine(DbEngine engine) => driver;
}

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
