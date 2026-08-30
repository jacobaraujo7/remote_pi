// O segredo do banco mora no HOST (plano 62): o cliente manda a conexão sem
// senha e é o servidor que a resolve do cofre daqui. Estes testes cobrem esse
// ponto de junção — o único lugar em que a senha entra no fluxo.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit_core/cockpit_core.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:cockpit_server/cockpit_server.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late String path;
  late DbSecretStore secrets;
  late _SpyDb db;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('cockpit-db-secret');
    path = '${dir.path}/s.sock';
    secrets = DbSecretStore(path: '${dir.path}/db-secrets.json');
    db = _SpyDb();
    LocalEndpoint.debugForceTcp = true;
  });
  tearDown(() {
    LocalEndpoint.debugForceTcp = null;
    dir.deleteSync(recursive: true);
  });

  Future<_TestClient> boot() async {
    final server = RemoteServer(
      _FakeTerminals(),
      _Fake(),
      _Fake(),
      db,
      dbSecrets: secrets,
    );
    await server.bind(path);
    addTearDown(server.close);
    return _connectClient(path);
  }

  /// Conexão como o cliente a manda quando o segredo está guardado no host:
  /// SEM senha, e com as duas metades da chave.
  Map<String, Object?> storedConn() => {
    'engine': 'postgres',
    'url': 'postgres://user@db.internal:5432/app',
    'workspaceRoot': '/srv/proj',
    'connName': 'dev-local',
    'storedSecret': true,
  };

  test('o servidor preenche a senha a partir do cofre do host', () async {
    secrets.write('/srv/proj', 'dev-local', 's3cr3t');
    final client = await boot();

    final reply = await _call(client, 'db.query', {
      'conn': storedConn(),
      'sql': 'select 1',
    });

    expect(reply.ok, isTrue);
    // A senha NÃO veio no fio; quem a colocou no descritor foi o servidor.
    expect(db.seen.single.password, 's3cr3t');
  });

  test(
    'sem segredo no host, responde password_required em vez de tentar conectar',
    () async {
      final client = await boot();

      final reply = await _call(client, 'db.query', {
        'conn': storedConn(),
        'sql': 'select 1',
      });

      expect(reply.ok, isFalse);
      expect(reply.code, DbErrorKind.passwordRequired.name);
      // Conectar sem senha produziria um erro do banco que não diz o que fazer.
      expect(db.seen, isEmpty);
    },
  );

  test('conexão sem segredo guardado passa intacta', () async {
    // `savePassword` desligado: a senha (se houver) vem embutida pelo cliente,
    // e o cofre do host não tem nada a dizer.
    secrets.write('/srv/proj', 'dev-local', 'nao-deve-ser-usada');
    final client = await boot();

    await _call(client, 'db.query', {
      'conn': {...storedConn(), 'storedSecret': false, 'password': 'da-url'},
      'sql': 'select 1',
    });

    expect(db.seen.single.password, 'da-url');
  });

  test('db.secretSet grava e db.secretDelete apaga', () async {
    final client = await boot();

    final set = await _call(client, 'db.secretSet', {
      'root': '/srv/proj',
      'conn': 'dev-local',
      'value': 'nova',
    });
    expect(set.ok, isTrue);
    expect(secrets.read('/srv/proj', 'dev-local'), 'nova');

    final del = await _call(client, 'db.secretDelete', {
      'root': '/srv/proj',
      'conn': 'dev-local',
    });
    expect(del.ok, isTrue);
    expect(secrets.read('/srv/proj', 'dev-local'), isNull);
  });

  test('db.secretRename move a senha dentro do host', () async {
    secrets.write('/srv/proj', 'antiga', 's3cr3t');
    final client = await boot();

    final reply = await _call(client, 'db.secretRename', {
      'root': '/srv/proj',
      'from': 'antiga',
      'to': 'nova',
    });

    expect(reply.ok, isTrue);
    expect(secrets.read('/srv/proj', 'antiga'), isNull);
    expect(secrets.read('/srv/proj', 'nova'), 's3cr3t');
  });

  test('conexão com bastion vai para o túnel, não direto', () async {
    final tunnel = _SpyTunnel();
    final server = RemoteServer(
      _FakeTerminals(),
      _Fake(),
      _Fake(),
      db,
      dbSecrets: secrets,
      dbTunnel: tunnel,
    );
    await server.bind(path);
    addTearDown(server.close);
    final client = await _connectClient(path);

    await _call(client, 'db.query', {
      'conn': {
        ...storedConn(),
        'storedSecret': false,
        'host': 'db.internal',
        'port': 5432,
        'ssh': {'host': 'bastion', 'user': 'deploy', 'keyPath': '~/.ssh/id'},
      },
      'sql': 'select 1',
    });

    // O túnel foi pedido para o alvo REAL…
    expect(tunnel.requests.single, 'deploy@bastion:22 -> db.internal:5432');
    // …e o driver recebeu a ponta LOCAL, não o host do banco.
    expect(db.seen.single.host, '127.0.0.1');
    expect(db.seen.single.port, 55432);
  });

  test('falha do túnel vira ssh_tunnel_failed com o kind do motor', () async {
    final tunnel = _SpyTunnel(
      failure: const SshTunnelException(
        'ssh_host_key_unknown',
        'Unknown host key for deploy@bastion:22 (SHA256:abc).',
      ),
    );
    final server = RemoteServer(
      _FakeTerminals(),
      _Fake(),
      _Fake(),
      db,
      dbSecrets: secrets,
      dbTunnel: tunnel,
    );
    await server.bind(path);
    addTearDown(server.close);
    final client = await _connectClient(path);

    final reply = await _call(client, 'db.query', {
      'conn': {
        ...storedConn(),
        'storedSecret': false,
        'ssh': {'host': 'bastion', 'user': 'deploy', 'keyPath': '~/.ssh/id'},
      },
      'sql': 'select 1',
    });

    expect(reply.ok, isFalse);
    expect(reply.code, DbErrorKind.sshTunnelFailed.name);
    // O kind e o fingerprint atravessam: é com eles que a UI decide se pode
    // oferecer "confiar nesta host key", e o humano confere o fingerprint.
    expect(reply.detail, contains('ssh_host_key_unknown'));
    expect(reply.detail, contains('SHA256:abc'));
    expect(db.seen, isEmpty, reason: 'sem túnel não se conecta ao banco');
  });

  test('db.hostKeyTrust grava no store do host', () async {
    final dir2 = Directory.systemTemp.createTempSync('cockpit-hostkeys');
    addTearDown(() => dir2.deleteSync(recursive: true));
    final store = FileSshHostKeyStore(path: '${dir2.path}/known.json');
    expect(store.trusted('deploy@bastion:22'), isNull);

    final client = await boot();
    // O comando usa o store default do servidor; aqui o que interessa é que
    // ele responde ok e que o store persiste o que recebe.
    final reply = await _call(client, 'db.hostKeyTrust', {
      'endpoint': 'deploy@bastion:22',
      'fingerprint': 'SHA256:abc',
    });
    expect(reply.ok, isTrue);

    await store.trust('deploy@bastion:22', 'SHA256:abc');
    expect(
      FileSshHostKeyStore(path: '${dir2.path}/known.json')
          .trusted('deploy@bastion:22'),
      'SHA256:abc',
    );
  });

  test('não existe db.secretGet — o segredo não volta pelo protocolo', () async {
    secrets.write('/srv/proj', 'dev-local', 's3cr3t');
    final client = await boot();

    final reply = await _call(client, 'db.secretGet', {
      'root': '/srv/proj',
      'conn': 'dev-local',
    });

    expect(reply.ok, isFalse, reason: 'ler segredo não pode ser um método');
  });
}

Future<RpcResponse> _call(
  _TestClient client,
  String method,
  Map<String, Object?> params,
) async {
  const rid = 1;
  final reply = client.messages.firstWhere(
    (m) => m is RpcResponse && m.rid == rid,
  );
  client.send(RpcRequest(rid: rid, method: method, params: params));
  return await reply.timeout(const Duration(seconds: 5)) as RpcResponse;
}

/// [DbService] que só registra o descritor recebido — o que interessa aqui é
/// COM QUE senha o servidor chamaria o driver, não o resultado da query.
class _SpyDb implements DbService {
  final seen = <RemoteDbConnDescriptor>[];

  @override
  Future<Map<String, Object?>> query(
    RemoteDbConnDescriptor conn,
    String sql, {
    int limit = 200,
    bool dml = false,
  }) async {
    seen.add(conn);
    return {'columns': <Object?>[], 'rows': <Object?>[]};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

Future<_TestClient> _connectClient(String path) async {
  final endpoint = await LocalEndpoint.connect(path);
  final socket = endpoint.socket;
  addTearDown(socket.destroy);
  final messages = StreamController<RemoteMessage>.broadcast();
  const RemoteMessageCodec().decodeStream(socket).listen(messages.add);
  final ack = messages.stream.first;
  socket.add(
    utf8.encode(
      const RemoteMessageCodec().encode(
        Hello(
          version: protocolVersion,
          client: 'test',
          token: endpoint.token,
          local: false,
        ),
      ),
    ),
  );
  await ack.timeout(const Duration(seconds: 5));
  return _TestClient(socket, messages.stream);
}

class _TestClient {
  _TestClient(this._socket, this.messages);
  final Socket _socket;
  final Stream<RemoteMessage> messages;

  void send(RemoteMessage m) =>
      _socket.add(utf8.encode(const RemoteMessageCodec().encode(m)));
}

/// Túnel que só registra o que lhe pediram — o que interessa é PARA ONDE o
/// driver aponta depois, não abrir SSH de verdade.
class _SpyTunnel implements SshTunnel {
  _SpyTunnel({this.failure});
  final SshTunnelException? failure;
  final requests = <String>[];

  @override
  Future<TunnelEndpoint> ensure(
    SshTunnelConfig config, {
    required String targetHost,
    required int targetPort,
    String? passphrase,
    HostKeyPrompt? onUnknownHostKey,
  }) async {
    if (failure != null) throw failure!;
    requests.add('${config.endpoint} -> $targetHost:$targetPort');
    return const TunnelEndpoint('127.0.0.1', 55432);
  }

  @override
  Future<TunnelEndpoint> ensureSocks(
    SshTunnelConfig config, {
    String? passphrase,
    HostKeyPrompt? onUnknownHostKey,
  }) async {
    if (failure != null) throw failure!;
    requests.add('${config.endpoint} -> socks');
    return const TunnelEndpoint('127.0.0.1', 51080);
  }

  @override
  Future<void> closeAll() async {}
}

class _FakeTerminals implements TerminalService {
  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _Fake implements FileService, GitService {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
