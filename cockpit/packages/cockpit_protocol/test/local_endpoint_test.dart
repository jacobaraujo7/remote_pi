import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:test/test.dart';

/// O transporte local precisa funcionar nas duas formas: socket UNIX no POSIX e
/// TCP loopback + token no Windows, onde o `dart:io` não tem UDS — foi o bind
/// estourando lá que deixava todo terminal do Windows no fallback in-process.
void main() {
  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('cockpit-endpoint');
    path = '${dir.path}/cockpit-server.sock';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('anuncia, aceita conexão e devolve os mesmos bytes', () async {
    final mode = LocalEndpoint.platformTransport;
    final endpoint = await LocalEndpoint.bind(path, transport: mode);
    addTearDown(endpoint.close);
    endpoint.listener.listen((socket) {
      socket.add([1, 2, 3]);
      socket.close();
    });

    expect(LocalEndpoint.announcedAt(path), isTrue);

    final client = await LocalEndpoint.connect(path, transport: mode);
    expect(await client.socket.first, [1, 2, 3]);
    // O token existe exatamente onde o transporte é TCP compartilhado.
    expect(
      client.token,
      mode == LocalEndpointTransport.tcp ? isNotEmpty : isNull,
    );
    expect(client.token, endpoint.token);
  });

  test('transporte TCP explícito funciona também no POSIX', () async {
    const tcp = LocalEndpointTransport.tcp;
    final endpoint = await LocalEndpoint.bind(path, transport: tcp);
    addTearDown(endpoint.close);
    endpoint.listener.listen((socket) {
      socket.add([4, 5, 6]);
      socket.close();
    });

    expect(endpoint.transport, tcp);
    expect(endpoint.token, isNotEmpty);

    final client = await LocalEndpoint.connect(path, transport: tcp);
    addTearDown(client.socket.destroy);
    expect(await client.socket.first, [4, 5, 6]);
    expect(client.token, endpoint.token);
  });

  test('TCP grava o rendezvous 0600 ANTES do token', () async {
    final endpoint = await LocalEndpoint.bind(
      path,
      transport: LocalEndpointTransport.tcp,
    );
    addTearDown(endpoint.close);

    if (!Platform.isWindows) {
      // 0x1FF isola os bits de permissão do restante do modo (tipo do inode).
      expect(File(path).statSync().mode & 0x1FF, 0x180); // 0600
    }
  }, testOn: '!windows');

  test(
    'close remove o anúncio (senão a próxima descoberta se engana)',
    () async {
      final endpoint = await LocalEndpoint.bind(path);
      await endpoint.close();

      expect(LocalEndpoint.announcedAt(path), isFalse);
    },
  );

  test('bind por cima de um anúncio órfão funciona', () async {
    File(path).writeAsStringSync('lixo do ciclo anterior');

    final endpoint = await LocalEndpoint.bind(path);
    addTearDown(endpoint.close);
    endpoint.listener.listen((s) => s.close());

    final client = await LocalEndpoint.connect(path);
    addTearDown(client.socket.destroy);
    expect(client.socket, isNotNull);
  });

  test('connect sem servidor algum falha', () async {
    await expectLater(LocalEndpoint.connect(path), throwsA(anything));
  });

  ownershipTests();

  test('HelloAck leva a identidade do servidor (adoção do sidecar)', () {
    const ack = HelloAck(
      version: protocolVersion,
      server: '0.1.0',
      executable: r'C:\Program Files\Cockpit\cockpit-server.exe',
      pid: 4242,
    );
    final json = ack.toJson();
    expect(json['exe'], r'C:\Program Files\Cockpit\cockpit-server.exe');
    expect(json['pid'], 4242);

    final back = HelloAck.fromJson(json);
    expect(back.executable, ack.executable);
    expect(back.pid, 4242);

    // Servidor de versão anterior não informa nada disso. O cliente trata a
    // ausência como "não é o meu binário" e sobe o próprio — é justamente o
    // caso que fez um app novo seguir falando com uma build antiga.
    final antigo = HelloAck.fromJson({
      't': 'hello.ack',
      'v': protocolVersion,
      'server': '0.1.0',
    });
    expect(antigo.executable, isNull);
    expect(antigo.pid, isNull);
  });

  test('Hello leva token e flag local no wire', () {
    const hello = Hello(
      version: protocolVersion,
      client: 'cockpit-gui',
      token: 'abc',
      local: true,
    );
    final json = hello.toJson();
    expect(json['tok'], 'abc');
    expect(json['loc'], true);

    final back = Hello.fromJson(json);
    expect(back.token, 'abc');
    expect(back.local, isTrue);

    // Compatibilidade: cliente antigo não manda os campos novos.
    final old = Hello.fromJson({
      't': 'hello',
      'v': protocolVersion,
      'client': 'legacy',
    });
    expect(old.token, isNull);
    expect(old.local, isFalse);
  });
}

/// Posse do caminho anunciado: um Cockpit novo bindando por cima deixa o
/// servidor antigo órfão — vivo, mas inalcançável. Sem esta checagem ele fica
/// para sempre (foi o que aconteceu em produção, com dois apps abertos).
void ownershipTests() {
  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('cockpit-owner');
    path = '${dir.path}/cockpit-server.sock';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('recém-bindado, o caminho é nosso', () async {
    final endpoint = await LocalEndpoint.bind(path);
    addTearDown(endpoint.close);
    expect(endpoint.stillOwned(), isTrue);
  });

  test('outro servidor bindando por cima tira a posse', () async {
    final first = await LocalEndpoint.bind(path);
    // Um segundo de diferença: no POSIX a impressão digital é o mtime do
    // inode, e dois binds no mesmo segundo seriam indistinguíveis.
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    final second = await LocalEndpoint.bind(path);
    addTearDown(second.close);

    expect(second.stillOwned(), isTrue);
    expect(first.stillOwned(), isFalse);
  });

  test('anúncio apagado também tira a posse', () async {
    final endpoint = await LocalEndpoint.bind(path);
    addTearDown(endpoint.close);
    File(path).deleteSync();

    expect(endpoint.stillOwned(), isFalse);
  });
}
