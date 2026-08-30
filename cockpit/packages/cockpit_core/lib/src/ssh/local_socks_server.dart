import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'ssh_log.dart';

/// Abre um canal até `host:port` do outro lado do túnel. É o `forwardLocal` do
/// cliente SSH, injetado assim pra este servidor não depender do `dartssh2`.
typedef SocksDial = Future<SocksChannel> Function(String host, int port);

/// Canal duplex já aberto no destino (adapta o `SSHForwardChannel`).
abstract interface class SocksChannel {
  Stream<List<int>> get stream;
  StreamSink<List<int>> get sink;
  void destroy();
}

/// Servidor **SOCKS5 CONNECT** local (`ssh -D`) sobre um túnel SSH.
///
/// Existe em vez do `forwardDynamic` do `dartssh2` por causa do tratamento de
/// erro: lá o `ServerSocket` é escutado sem `onError`, então um reset no accept
/// vira erro não tratado na zona **e** derruba a assinatura — o proxy fica de
/// pé (`isClosed == false`) mas não aceita mais ninguém, e todo comando de
/// banco seguinte pendura até estourar timeout. Isso aparecia como "o painel
/// fica carregando pra sempre" e enchia `~/.cockpit/logs` de
/// `SocketException: Connection reset by peer` — um por teardown de pool do
/// driver Mongo, que fecha as conexões em background depois de responder.
///
/// Aqui: erro de accept é logado e **não** derruba o servidor; erro de conexão
/// derruba só aquela conexão; e [isAlive] reflete a verdade (vira `false` se o
/// listener morrer de fato), pra o cache de túneis reabrir em vez de servir um
/// proxy zumbi.
///
/// SOCKS5 sem autenticação de propósito: escuta só no loopback, e o único
/// cliente é o driver rodando no nosso processo.
class LocalSocksServer {
  LocalSocksServer._(this._server, this._dial) {
    _sub = _server.listen(
      _accept,
      // A diferença que motiva esta classe.
      onError: (Object e) => sshLog('[socks] accept falhou: $e'),
      cancelOnError: false,
      onDone: () => _listening = false,
    );
  }

  /// Sobe o proxy numa porta efêmera do loopback.
  static Future<LocalSocksServer> start(SocksDial dial) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    return LocalSocksServer._(server, dial);
  }

  final ServerSocket _server;
  final SocksDial _dial;
  late final StreamSubscription<Socket> _sub;

  bool _listening = true;
  bool _closed = false;

  String get host => _server.address.address;
  int get port => _server.port;
  bool get isAlive => !_closed && _listening;

  final _live = <Socket>{};

  void _accept(Socket client) {
    if (_closed) {
      client.destroy();
      return;
    }
    _live.add(client);
    unawaited(
      _serve(client).whenComplete(() {
        _live.remove(client);
        client.destroy();
      }),
    );
  }

  /// Handshake + repasse de uma conexão. Qualquer erro derruba só ela.
  Future<void> _serve(Socket client) async {
    final reader = _SocketReader(client);
    try {
      await _greet(client, reader);
      final target = await _readRequest(reader);

      final SocksChannel channel;
      try {
        channel = await _dial(target.host, target.port);
      } on Object catch (e) {
        sshLog('[socks] destino ${target.host}:${target.port} recusou: $e');
        _reply(client, _replyHostUnreachable);
        return;
      }

      _reply(client, _replySucceeded);

      // Bytes que chegaram junto do request (o cliente pode pipelinar).
      final pending = reader.takePending();
      if (pending.isNotEmpty) channel.sink.add(pending);

      await _pump(reader, client, channel);
    } on Object catch (e) {
      sshLog('[socks] conexão abortada: $e');
    }
  }

  /// Negocia o método de autenticação (só aceitamos "sem autenticação").
  Future<void> _greet(Socket client, _SocketReader reader) async {
    final head = await reader.read(2);
    if (head[0] != _version) {
      throw const FormatException('versão SOCKS não suportada');
    }
    final methods = await reader.read(head[1]);
    if (!methods.contains(_noAuth)) {
      client.add([_version, 0xFF]);
      throw const FormatException('nenhum método de autenticação em comum');
    }
    client.add([_version, _noAuth]);
  }

  Future<({String host, int port})> _readRequest(_SocketReader reader) async {
    final head = await reader.read(4); // VER CMD RSV ATYP
    if (head[0] != _version) {
      throw const FormatException('versão SOCKS não suportada');
    }
    if (head[1] != _cmdConnect) {
      throw const FormatException('só CONNECT é suportado');
    }
    final String host;
    switch (head[3]) {
      case _atypIpv4:
        host = (await reader.read(4)).join('.');
      case _atypDomain:
        final len = (await reader.read(1))[0];
        host = utf8.decode(await reader.read(len), allowMalformed: true);
      case _atypIpv6:
        final raw = await reader.read(16);
        host = InternetAddress.fromRawAddress(
          Uint8List.fromList(raw),
          type: InternetAddressType.IPv6,
        ).address;
      default:
        throw const FormatException('tipo de endereço não suportado');
    }
    final portBytes = await reader.read(2);
    return (host: host, port: (portBytes[0] << 8) | portBytes[1]);
  }

  /// Reply com BND.ADDR zerado: o cliente SOCKS não usa esse campo pra CONNECT.
  void _reply(Socket client, int code) => client.add([
    _version, code, 0x00, _atypIpv4, 0, 0, 0, 0, 0, 0, //
  ]);

  /// Repassa bytes nos dois sentidos até uma das pontas terminar.
  Future<void> _pump(
    _SocketReader reader,
    Socket client,
    SocksChannel channel,
  ) async {
    final done = Completer<void>();
    void finish() {
      if (!done.isCompleted) done.complete();
    }

    reader.resume(
      onData: channel.sink.add,
      onDone: () {
        channel.sink.close().catchError((_) {});
        finish();
      },
      onError: (_) => finish(),
    );
    final fromRemote = channel.stream.listen(
      (data) {
        try {
          client.add(data);
        } on Object {
          finish();
        }
      },
      onDone: finish,
      onError: (Object _) => finish(),
      cancelOnError: true,
    );

    try {
      await done.future;
    } finally {
      await fromRemote.cancel().catchError((_) {});
      channel.destroy();
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _listening = false;
    await _sub.cancel().catchError((_) {});
    try {
      await _server.close();
    } on Object {
      /* já fechado */
    }
    for (final socket in _live.toList()) {
      socket.destroy();
    }
    _live.clear();
  }

  static const _version = 0x05;
  static const _noAuth = 0x00;
  static const _cmdConnect = 0x01;
  static const _atypIpv4 = 0x01;
  static const _atypDomain = 0x03;
  static const _atypIpv6 = 0x04;
  static const _replySucceeded = 0x00;
  static const _replyHostUnreachable = 0x04;
}

/// Leitor de N bytes sobre um `Socket`, que depois **devolve a assinatura** pro
/// modo streaming. Um `StreamSubscription` só: trocar de listener no meio de um
/// socket vivo perderia os bytes que chegam entre um e outro.
class _SocketReader {
  _SocketReader(this._socket) {
    _sub = _socket.listen(
      (chunk) {
        _buffer.addAll(chunk);
        _pump();
      },
      onDone: () {
        _done = true;
        _onDone?.call();
        _failPending(const SocketException('conexão fechada no handshake'));
      },
      onError: (Object e) {
        _onError?.call(e);
        _failPending(e);
      },
    );
  }

  final Socket _socket;
  late final StreamSubscription<Uint8List> _sub;
  final _buffer = <int>[];

  bool _done = false;
  bool _streaming = false;
  int? _want;
  Completer<List<int>>? _pendingRead;

  void Function(List<int> data)? _onData;
  void Function()? _onDone;
  void Function(Object error)? _onError;

  /// Espera exatamente [count] bytes.
  Future<List<int>> read(int count) {
    if (count == 0) return Future.value(const []);
    if (_done && _buffer.length < count) {
      return Future.error(
        const SocketException('conexão fechada no handshake'),
      );
    }
    final completer = Completer<List<int>>();
    _want = count;
    _pendingRead = completer;
    _pump();
    return completer.future;
  }

  /// Bytes já recebidos além do handshake (pipelining do cliente).
  List<int> takePending() {
    final out = List<int>.of(_buffer);
    _buffer.clear();
    return out;
  }

  /// Passa a repassar tudo o que chegar — sem trocar de assinatura.
  void resume({
    required void Function(List<int> data) onData,
    required void Function() onDone,
    required void Function(Object error) onError,
  }) {
    _onData = onData;
    _onDone = onDone;
    _onError = onError;
    _streaming = true;
    if (_buffer.isNotEmpty) {
      onData(takePending());
    }
    if (_done) onDone();
  }

  void _pump() {
    if (_streaming) {
      if (_buffer.isNotEmpty) _onData?.call(takePending());
      return;
    }
    final want = _want;
    final pending = _pendingRead;
    if (want == null || pending == null || _buffer.length < want) return;
    final out = _buffer.sublist(0, want);
    _buffer.removeRange(0, want);
    _want = null;
    _pendingRead = null;
    pending.complete(out);
  }

  void _failPending(Object error) {
    final pending = _pendingRead;
    _pendingRead = null;
    _want = null;
    if (pending != null && !pending.isCompleted) pending.completeError(error);
  }

  Future<void> cancel() => _sub.cancel().catchError((_) {});
}
