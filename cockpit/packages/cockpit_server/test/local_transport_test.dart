// Transporte local do servidor. No Windows não existe socket UNIX no dart:io,
// então o servidor escuta em TCP de loopback — que qualquer processo da máquina
// alcança, daí o token no handshake. Estes testes pedem o transporte TCP
// explicitamente para exercitá-lo fora do Windows.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit_core/cockpit_core.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:cockpit_server/cockpit_server.dart';
import 'package:test/test.dart';

const _tcp = LocalEndpointTransport.tcp;

void main() {
  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('cockpit-transport');
    path = '${dir.path}/cockpit-server.sock';
  });
  tearDown(() {
    dir.deleteSync(recursive: true);
  });

  test('handshake com o token do anúncio é aceito', () async {
    final server = _server();
    await server.bind(path, transport: _tcp);
    addTearDown(server.close);

    final reply = await _handshake(path, withToken: true);
    expect(reply, isA<HelloAck>());
  });

  test('handshake sem token é recusado', () async {
    final server = _server();
    await server.bind(path, transport: _tcp);
    addTearDown(server.close);

    final reply = await _handshake(path, withToken: false);
    expect(reply, isA<RemoteError>());
    expect((reply as RemoteError).code, 'invalid_token');
  });

  test('cliente local mantém o env de status que mandou', () async {
    final terminals = _FakeTerminals();
    final server = _server(terminals);
    await server.bind(path, transport: _tcp);
    addTearDown(server.close);

    await _openPty(path, local: true);
    // O socket do app é a via da CLI interna (`cockpit send`) além do status;
    // sobrescrevê-lo num PTY local deixaria a CLI muda em toda aba.
    expect(terminals.lastEnv['COCKPIT_STATUS_SOCK'], '/from/client.sock');
  });

  test('cliente remoto tem o env de status trocado pelo do servidor', () async {
    final terminals = _FakeTerminals();
    final server = _server(terminals);
    await server.bind(path, transport: _tcp);
    addTearDown(server.close);

    await _openPty(path, local: false);
    // Do outro lado de um túnel, o socket do cliente é inalcançável pelo
    // agente: quem vale é o receptor do próprio servidor. E o endereço do
    // cliente some por inteiro — no transporte TCP o hook prefere um
    // COCKPIT_STATUS_SOCK herdado à porta+token, e o status se perderia.
    expect(terminals.lastEnv['COCKPIT_STATUS_SOCK'], isNull);
    expect(terminals.lastEnv['COCKPIT_STATUS_PORT'], isNotNull);
    expect(terminals.lastEnv['COCKPIT_STATUS_TOKEN'], isNotNull);
  });
}

RemoteServer _server([TerminalService? terminals]) =>
    RemoteServer(terminals ?? _FakeTerminals(), _Fake(), _Fake(), _Fake());

/// Conecta, manda o Hello e devolve a primeira resposta do servidor.
Future<RemoteMessage> _handshake(
  String path, {
  required bool withToken,
  bool local = false,
  Socket? reuse,
}) async {
  final endpoint = await LocalEndpoint.connect(path, transport: _tcp);
  final socket = endpoint.socket;
  final first = _messages(socket).first;
  socket.add(
    utf8.encode(
      const RemoteMessageCodec().encode(
        Hello(
          version: protocolVersion,
          client: 'test',
          token: withToken ? endpoint.token : null,
          local: local,
        ),
      ),
    ),
  );
  final reply = await first.timeout(const Duration(seconds: 5));
  if (reuse == null && !withToken) socket.destroy();
  return reply;
}

/// Handshake + PtyOpen numa conexão só; resolve quando o servidor responde.
Future<void> _openPty(String path, {required bool local}) async {
  final endpoint = await LocalEndpoint.connect(path, transport: _tcp);
  final socket = endpoint.socket;
  addTearDown(socket.destroy);
  final replies = StreamController<RemoteMessage>.broadcast();
  _messages(socket).listen(replies.add);
  const codec = RemoteMessageCodec();

  final ack = replies.stream.first;
  socket.add(
    utf8.encode(
      codec.encode(
        Hello(
          version: protocolVersion,
          client: 'test',
          token: endpoint.token,
          local: local,
        ),
      ),
    ),
  );
  await ack.timeout(const Duration(seconds: 5));

  final opened = replies.stream.first;
  socket.add(
    utf8.encode(
      codec.encode(
        const PtyOpen(
          executable: '/bin/zsh',
          environment: {'COCKPIT_STATUS_SOCK': '/from/client.sock'},
        ),
      ),
    ),
  );
  await opened.timeout(const Duration(seconds: 5));
}

Stream<RemoteMessage> _messages(Socket socket) =>
    const RemoteMessageCodec().decodeStream(socket);

class _FakeTerminals implements TerminalService {
  Map<String, String> lastEnv = const {};

  @override
  Future<PtySessionInfo> open(PtySpawnSpec spec) async {
    lastEnv = spec.environment;
    return const PtySessionInfo(
      id: 's1',
      pid: 1,
      executable: '/bin/zsh',
      rows: 25,
      columns: 80,
      scrollbackLength: 0,
    );
  }

  @override
  Stream<PtyEvent> attach(String id, {int fromOffset = 0}) =>
      const Stream<PtyEvent>.empty();

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _Fake implements FileService, GitService, DbService {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
