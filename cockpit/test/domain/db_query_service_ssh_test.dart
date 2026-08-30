import 'package:cockpit_core/cockpit_core.dart';
import 'package:cockpit/app/cockpit/domain/contracts/db_connection_store.dart';
import 'package:cockpit/app/cockpit/domain/contracts/db_driver.dart';
import 'package:cockpit/app/cockpit/domain/contracts/nosql_runner.dart';
import 'package:cockpit/app/cockpit/domain/entities/db_connection.dart';
import 'package:cockpit/app/cockpit/domain/entities/db_result.dart';
import 'package:cockpit/app/cockpit/domain/services/db_query_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/mongo_database_store_fake.dart';
import 'fakes/ssh_fakes.dart';

/// Prova o **chokepoint** do plano 54: todo caminho público do serviço recebe
/// a conexão já redirecionada pra ponta local do túnel — sem que driver,
/// runner ou chamador saibam que existe SSH.
void main() {
  const ssh = SshTunnelConfig(
    host: 'bastion',
    user: 'deploy',
    keyPath: '~/.ssh/id_ed25519',
  );

  DbConnection pg({SshTunnelConfig? tunnel}) => DbConnection.network(
    name: 'prod',
    engine: DbEngine.postgres,
    host: 'db.internal',
    database: 'app',
    user: 'postgres',
    ssh: tunnel,
  );

  DbConnection redis({SshTunnelConfig? tunnel}) => DbConnection.network(
    name: 'cache',
    engine: DbEngine.redis,
    host: 'redis.internal',
    database: '0',
    ssh: tunnel,
  );

  DbConnection mongo({SshTunnelConfig? tunnel}) => DbConnection.network(
    name: 'docs',
    engine: DbEngine.mongo,
    host: 'mongo.internal',
    database: 'app',
    ssh: tunnel,
  );

  ({
    DbQueryService service,
    _SpyDriver driver,
    _SpyRunner runner,
    FakeSshTunnel tunnel,
  })
  build(
    List<DbConnection> conns, {
    bool encryptedKey = false,
    SshTunnelException? failure,
    Map<String, String> vault = const {},
  }) {
    final driver = _SpyDriver();
    final runner = _SpyRunner();
    final tunnel = FakeSshTunnel(failure: failure);
    final service = DbQueryService(
      _FakeStore(conns),
      _MapSecrets(vault),
      _FixedRegistry(driver),
      runner,
      tunnel,
      FakeSshKeyInspector(encrypted: encryptedKey),
      FakeMongoDatabaseStore(),
    );
    return (service: service, driver: driver, runner: runner, tunnel: tunnel);
  }

  group('sem túnel: nada muda', () {
    test('driver recebe o host real e o túnel nunca é acionado', () async {
      final f = build([pg()]);
      await f.service.query(
        workspaceRoot: '/ws',
        workspaceId: 'w1',
        connName: 'prod',
        sql: 'SELECT 1',
      );
      expect(f.driver.seen.single.host, 'db.internal');
      expect(f.driver.seen.single.port, 5432);
      expect(f.tunnel.opens, 0);
    });
  });

  group('com túnel: os 6 caminhos recebem a ponta local', () {
    test('query', () async {
      final f = build([pg(tunnel: ssh)]);
      await f.service.query(
        workspaceRoot: '/ws',
        workspaceId: 'w1',
        connName: 'prod',
        sql: 'SELECT 1',
      );
      expect(f.driver.seen.single.host, '127.0.0.1');
      expect(f.driver.seen.single.port, 55432);
      // O túnel foi pedido pro alvo REAL, não pro endereço reescrito.
      expect(f.tunnel.requests.single, 'deploy@bastion:22->db.internal:5432');
    });

    test('query dml (execute)', () async {
      final f = build([pg(tunnel: ssh)]);
      await f.service.query(
        workspaceRoot: '/ws',
        workspaceId: 'w1',
        connName: 'prod',
        sql: 'UPDATE t SET a=1',
        dml: true,
      );
      expect(f.driver.seen.single.host, '127.0.0.1');
    });

    test('schema', () async {
      final f = build([pg(tunnel: ssh)]);
      await f.service.schema(
        workspaceRoot: '/ws',
        workspaceId: 'w1',
        connName: 'prod',
      );
      expect(f.driver.seen.single.host, '127.0.0.1');
    });

    test('runStatements', () async {
      final f = build([pg(tunnel: ssh)]);
      await f.service.runStatements(
        workspaceRoot: '/ws',
        workspaceId: 'w1',
        connName: 'prod',
        statements: ['SELECT 1', 'SELECT 2'],
      );
      expect(f.driver.seen.map((c) => c.host), ['127.0.0.1', '127.0.0.1']);
    });

    test('redisCommand', () async {
      final f = build([redis(tunnel: ssh)]);
      await f.service.redisCommand(
        workspaceRoot: '/ws',
        workspaceId: 'w1',
        connName: 'cache',
        parts: ['GET', 'k'],
      );
      expect(f.runner.seen.single.host, '127.0.0.1');
      expect(
        f.tunnel.requests.single,
        'deploy@bastion:22->redis.internal:6379',
      );
    });

    test('redisBatch', () async {
      final f = build([redis(tunnel: ssh)]);
      await f.service.redisBatch(
        workspaceRoot: '/ws',
        workspaceId: 'w1',
        connName: 'cache',
        commands: [
          ['GET', 'k'],
        ],
      );
      expect(f.runner.seen.single.host, '127.0.0.1');
    });

    test('mongoCommand vai por SOCKS, não por port-forward', () async {
      // O driver do Mongo descobre os membros do replica set pelo `hello` e
      // passa a discar os hostnames anunciados — uma porta local fixa só
      // alcançaria o primeiro nó. Com proxy, quem escolhe o destino é o
      // driver, e o host da URL fica intacto.
      final f = build([mongo(tunnel: ssh)]);
      await f.service.mongoCommand(
        workspaceRoot: '/ws',
        workspaceId: 'w1',
        connName: 'docs',
        command: {'ping': 1},
      );
      final used = f.runner.seen.single;
      expect(used.host, 'mongo.internal', reason: 'host preservado');
      final params = Uri.parse(used.url).queryParameters;
      expect(params['proxyHost'], '127.0.0.1');
      expect(params['proxyPort'], '51080');
      expect(f.tunnel.socksRequests.single, 'deploy@bastion:22');
      expect(f.tunnel.requests, isEmpty, reason: 'nenhum port-forward');
    });
  });

  group('passphrase', () {
    test('chave sem passphrase não toca no cofre nem no prompt', () async {
      final f = build([pg(tunnel: ssh)]);
      // Sem passphrasePrompt setado (caminho CLI) e sem cofre: ainda assim
      // conecta, porque a chave é limpa.
      await f.service.query(
        workspaceRoot: '/ws',
        workspaceId: 'w1',
        connName: 'prod',
        sql: 'SELECT 1',
      );
      expect(f.driver.seen.single.host, '127.0.0.1');
    });

    test(
      'CLI + chave encriptada sem cofre falha honesto (não pendura)',
      () async {
        final f = build([
          pg(tunnel: ssh.copyWith(savePassphrase: true)),
        ], encryptedKey: true);
        // passphrasePrompt nulo = caminho do agente.
        await expectLater(
          f.service.query(
            workspaceRoot: '/ws',
            workspaceId: 'w1',
            connName: 'prod',
            sql: 'SELECT 1',
          ),
          throwsA(
            isA<DbQueryException>().having(
              (e) => e.kind,
              'kind',
              'ssh_credential_required',
            ),
          ),
        );
        expect(f.tunnel.opens, 0, reason: 'nem tentou abrir o túnel');
      },
    );

    test('passphrase salva no cofre serve o caminho CLI', () async {
      final f = build(
        [pg(tunnel: ssh.copyWith(savePassphrase: true))],
        encryptedKey: true,
        vault: {DbQueryService.sshSecretKey('/ws', 'prod'): 'hunter2'},
      );
      await f.service.query(
        workspaceRoot: '/ws',
        workspaceId: 'w1',
        connName: 'prod',
        sql: 'SELECT 1',
      );
      expect(f.driver.seen.single.host, '127.0.0.1');
    });

    test('GUI: prompt uma vez, cacheia pro resto da sessão', () async {
      final f = build([pg(tunnel: ssh)], encryptedKey: true);
      var prompts = 0;
      f.service.passphrasePrompt = (name, keyPath) async {
        prompts++;
        return 'hunter2';
      };
      for (var i = 0; i < 3; i++) {
        await f.service.query(
          workspaceRoot: '/ws',
          workspaceId: 'w1',
          connName: 'prod',
          sql: 'SELECT 1',
        );
      }
      expect(prompts, 1);
      expect(f.tunnel.opens, 3, reason: 'ensure é chamado; o cache é dele');
    });

    test('cancelar o prompt vira erro, não conexão silenciosa', () async {
      final f = build([pg(tunnel: ssh)], encryptedKey: true);
      f.service.passphrasePrompt = (name, keyPath) async => null;
      await expectLater(
        f.service.query(
          workspaceRoot: '/ws',
          workspaceId: 'w1',
          connName: 'prod',
          sql: 'SELECT 1',
        ),
        throwsA(isA<DbQueryException>()),
      );
      expect(f.tunnel.opens, 0);
    });
  });

  group('ping (botão Test do dialog)', () {
    test('conexão não-salva também passa pelo túnel', () async {
      // Regressão: o Test chamava o driver direto e furava o túnel — validava
      // um host que a query real nunca usaria.
      final f = build(const []); // nem está no store: é a conexão do dialog
      await f.service.ping(pg(tunnel: ssh), workspaceId: 'w1', workspaceRoot: '/ws');
      expect(f.driver.seen.single.host, '127.0.0.1');
      expect(f.tunnel.requests.single, 'deploy@bastion:22->db.internal:5432');
    });

    test('Redis e Mongo são testáveis (não só os engines SQL)', () async {
      final f = build(const []);
      await f.service.ping(redis(tunnel: ssh), workspaceId: 'w1', workspaceRoot: '/ws');
      await f.service.ping(mongo(tunnel: ssh), workspaceId: 'w1', workspaceRoot: '/ws');
      // Redis por port-forward (endereço único), Mongo por SOCKS.
      expect(f.runner.seen.first.host, '127.0.0.1');
      expect(f.runner.seen.last.host, 'mongo.internal');
      expect(
        Uri.parse(f.runner.seen.last.url).queryParameters['proxyHost'],
        '127.0.0.1',
      );
      expect(f.driver.seen, isEmpty, reason: 'NoSQL não passa pelo DbDriver');
    });

    test('passphrase digitada tem precedência sobre a do cofre', () async {
      final f = build(
        const [],
        encryptedKey: true,
        vault: {DbQueryService.sshSecretKey('/ws', 'prod'): 'velha'},
      );
      // Sem prompt setado: se o override não valesse, cairia no cofre — e o
      // usuário nunca conseguiria testar uma passphrase nova.
      await f.service.ping(
        pg(tunnel: ssh.copyWith(savePassphrase: true)),
        workspaceId: 'w1',
        workspaceRoot: '/ws',
        sshPassphrase: 'nova',
      );
      expect(f.tunnel.opens, 1);
    });
  });

  group('erros do túnel viram DbQueryException com o kind preservado', () {
    test('host key desconhecida', () async {
      final f = build([
        pg(tunnel: ssh),
      ], failure: const SshTunnelException('ssh_host_key_unknown', 'nope'));
      await expectLater(
        f.service.query(
          workspaceRoot: '/ws',
          workspaceId: 'w1',
          connName: 'prod',
          sql: 'SELECT 1',
        ),
        throwsA(
          isA<DbQueryException>().having(
            (e) => e.kind,
            'kind',
            'ssh_host_key_unknown',
          ),
        ),
      );
    });

    test('mongodb+srv (Atlas) é suportado via SOCKS', () async {
      // Era recusado enquanto o túnel só sabia port-forward. Com proxy, a seed
      // list resolve normalmente e cada nó é alcançado pelo mesmo túnel.
      final srv = DbConnection.network(
        name: 'atlas',
        engine: DbEngine.mongo,
        host: 'cluster.mongodb.net',
        database: 'app',
        srv: true,
        ssh: ssh,
      );
      final f = build([srv]);
      await f.service.mongoCommand(
        workspaceRoot: '/ws',
        workspaceId: 'w1',
        connName: 'atlas',
        command: {'ping': 1},
      );
      final used = f.runner.seen.single;
      expect(used.isSrv, isTrue, reason: 'SRV preservado');
      expect(Uri.parse(used.url).queryParameters['proxyHost'], '127.0.0.1');
    });
  });
}

/// Driver que só registra a conexão que recebeu.
class _SpyDriver implements DbDriver {
  final seen = <DbConnection>[];

  DbResult get _empty =>
      const DbResult(columns: [], rows: [], elapsed: Duration.zero);

  @override
  Future<DbResult> query(
    DbConnection conn,
    String sql, {
    required int limit,
    Duration timeout = const Duration(seconds: 30),
    String? password,
  }) async {
    seen.add(conn);
    return _empty;
  }

  @override
  Future<DbResult> execute(
    DbConnection conn,
    String sql, {
    Duration timeout = const Duration(seconds: 30),
    String? password,
  }) async {
    seen.add(conn);
    return _empty;
  }

  @override
  Future<DbResult> schema(
    DbConnection conn, {
    String? table,
    String? schema,
    Duration timeout = const Duration(seconds: 30),
    String? password,
  }) async {
    seen.add(conn);
    return _empty;
  }
}

class _SpyRunner implements NoSqlRunner {
  final seen = <DbConnection>[];

  @override
  Future<Object?> redis(
    DbConnection conn,
    List<String> parts, {
    String? password,
  String workspaceRoot = '',
  }) async {
    seen.add(conn);
    return null;
  }

  @override
  Future<List<Object?>> redisMany(
    DbConnection conn,
    List<List<String>> commands, {
    String? password,
  String workspaceRoot = '',
  }) async {
    seen.add(conn);
    return const [];
  }

  @override
  Future<Object?> mongo(
    DbConnection conn,
    Map<String, dynamic> command, {
    String? password,
    String? database,
  String workspaceRoot = '',
  }) async {
    seen.add(conn);
    return null;
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
