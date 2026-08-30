import 'package:cockpit_core/cockpit_core.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Canal em memória ligado a um servidor TCP local — faz o papel do
/// `forwardLocal` do SSH sem precisar de SSH nenhum.
class _LoopbackChannel implements SocksChannel {
  _LoopbackChannel(this._socket);

  final Socket _socket;

  @override
  Stream<List<int>> get stream => _socket.cast<List<int>>();

  @override
  StreamSink<List<int>> get sink => _socket;

  @override
  void destroy() => _socket.destroy();
}

/// Conexão já negociada: o socket e um leitor que continua de onde o
/// handshake parou (uma assinatura só por socket).
typedef SocksConn = ({Socket socket, Future<String> Function() readText});

/// Cliente SOCKS5 mínimo, só o suficiente pra exercitar o servidor.
Future<SocksConn> socksConnect(
  LocalSocksServer proxy,
  String host,
  int port, {
  int atyp = 0x03,
}) async {
  final s = await Socket.connect(proxy.host, proxy.port);
  final reader = StreamIterator(s);

  Future<List<int>> read(int n) async {
    final out = <int>[];
    while (out.length < n) {
      if (!await reader.moveNext()) {
        throw StateError('proxy fechou no meio do handshake');
      }
      out.addAll(reader.current);
    }
    return out;
  }

  s.add([5, 1, 0]);
  final greeting = await read(2);
  expect(greeting, [5, 0]);

  s.add([
    5, 1, 0, atyp, //
    if (atyp == 0x03) ...[
      host.length,
      ...host.codeUnits,
    ] else
      ...host.split('.').map(int.parse),
    port >> 8, port & 0xff,
  ]);
  final reply = await read(10);
  expect(reply[0], 5, reason: 'versão na resposta');
  if (reply[1] != 0) {
    await reader.cancel();
    s.destroy();
    throw StateError('SOCKS recusou com código ${reply[1]}');
  }
  return (
    socket: s,
    readText: () async {
      if (!await reader.moveNext()) {
        throw StateError('sem resposta do destino');
      }
      return String.fromCharCodes(reader.current);
    },
  );
}

void main() {
  late ServerSocket echo;
  late LocalSocksServer proxy;
  var dials = 0;

  setUp(() async {
    // Servidor de eco: devolve em maiúsculas pra provar que o repasse é duplex.
    echo = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    echo.listen((c) {
      c.listen(
        (data) => c.add(String.fromCharCodes(data).toUpperCase().codeUnits),
        onError: (_) {},
      );
    }, onError: (_) {});

    proxy = await LocalSocksServer.start((host, port) async {
      dials++;
      return _LoopbackChannel(await Socket.connect(host, port));
    });
  });

  tearDown(() async {
    await proxy.close();
    await echo.close();
    dials = 0;
  });

  test('CONNECT por domínio repassa nos dois sentidos', () async {
    final c = await socksConnect(proxy, 'localhost', echo.port);
    c.socket.add('ping'.codeUnits);
    expect(await c.readText(), 'PING');
    c.socket.destroy();
  });

  test('CONNECT por IPv4 também é aceito', () async {
    final c = await socksConnect(proxy, '127.0.0.1', echo.port, atyp: 0x01);
    c.socket.add('ok'.codeUnits);
    expect(await c.readText(), 'OK');
    c.socket.destroy();
  });

  test('destino inalcançável responde erro sem derrubar o proxy', () async {
    // Porta livre: o dial falha e o servidor precisa responder, não travar.
    final free = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final deadPort = free.port;
    await free.close();

    await expectLater(
      socksConnect(proxy, '127.0.0.1', deadPort, atyp: 0x01),
      throwsA(isA<StateError>()),
    );

    // A prova real: o proxy segue servindo depois da falha.
    expect(proxy.isAlive, isTrue);
    final ok = await socksConnect(proxy, 'localhost', echo.port);
    ok.socket.add('depois'.codeUnits);
    expect(await ok.readText(), 'DEPOIS');
    ok.socket.destroy();
  });

  test('conexão abortada no meio do handshake não afeta as próximas', () async {
    // Fecha logo após o greeting — é o que o driver faz ao derrubar o pool.
    final rude = await Socket.connect(proxy.host, proxy.port);
    rude.add([5, 1, 0]);
    await rude.flush();
    rude.destroy();

    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(proxy.isAlive, isTrue);

    final ok = await socksConnect(proxy, 'localhost', echo.port);
    ok.socket.add('vivo'.codeUnits);
    expect(await ok.readText(), 'VIVO');
    ok.socket.destroy();
  });

  test('N conexões em sequência reusam o mesmo proxy', () async {
    for (var i = 0; i < 5; i++) {
      final c = await socksConnect(proxy, 'localhost', echo.port);
      c.socket.add('n$i'.codeUnits);
      expect(await c.readText(), 'N$i');
      c.socket.destroy();
    }
    expect(dials, 5);
    expect(proxy.isAlive, isTrue);
  });

  test('close derruba o proxy e ele se declara morto', () async {
    // Guarda antes: depois do close o próprio getter de porta lança.
    final host = proxy.host;
    final port = proxy.port;
    await proxy.close();
    expect(proxy.isAlive, isFalse);
    await expectLater(
      Socket.connect(host, port),
      throwsA(isA<SocketException>()),
    );
  });
}
