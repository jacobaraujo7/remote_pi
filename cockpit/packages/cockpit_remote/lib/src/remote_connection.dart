import 'dart:async';
import 'dart:convert';

import 'package:cockpit_core/cockpit_core.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:cockpit_remote/src/remote_duplex.dart';

/// Erro de uma chamada RPC (fs.*/git.*). `code` é estável; `detail` é texto
/// cru (stderr do git, errno) — traduzido só na borda da UI.
class RemoteRpcException implements Exception {
  const RemoteRpcException(this.code, [this.detail]);
  final String code;
  final String? detail;

  @override
  String toString() => 'RemoteRpcException($code: $detail)';
}

/// Conexão de cliente com um cockpit-server (Wave 0: socket UDS local;
/// o túnel SSH da Wave 2 entrega exatamente o mesmo socket).
class RemoteConnection {
  RemoteConnection._(
    this._duplex,
    this.serverVersion,
    this._messages, {
    this.serverExecutable,
    this.serverPid,
  });

  static const _codec = RemoteMessageCodec();

  final RemoteDuplex _duplex;

  /// Versão reportada pelo servidor no handshake.
  final String serverVersion;

  /// Executável e pid do servidor, quando ele os informa (ver [HelloAck]).
  /// O cliente LOCAL usa para decidir se adota um servidor já de pé.
  final String? serverExecutable;
  final int? serverPid;

  final StreamController<RemoteMessage> _messages;
  bool _open = true;

  /// Stream broadcast de todas as mensagens do servidor.
  Stream<RemoteMessage> get messages => _messages.stream;

  /// Falso após queda do socket ou [close].
  bool get isOpen => _open;

  /// Conecta ao endpoint local anunciado em [socketPath] e faz o handshake —
  /// o transporte histórico (sidecar local / ponta do `ssh -L`). Socket UNIX no
  /// POSIX; no Windows, TCP de loopback com token, resolvido pelo
  /// [LocalEndpoint] a partir do mesmo caminho.
  /// [local] marca "servidor na mesma máquina" (sidecar). Não é derivável do
  /// transporte: a ponta de um `ssh -L` também é um socket local, e ali o
  /// servidor É remoto. Ver [Hello.local].
  ///
  /// [transport] escolhe o transporte do anúncio; sem valor usa o default da
  /// plataforma (UDS no POSIX, TCP no Windows). Testes e ferramentas que
  /// precisam exercitar o caminho TCP no POSIX passam
  /// [LocalEndpointTransport.tcp] explicitamente.
  static Future<RemoteConnection> connect(
    String socketPath, {
    String clientName = 'cockpit',
    bool local = false,
    LocalEndpointTransport? transport,
  }) async {
    final endpoint = await LocalEndpoint.connect(
      socketPath,
      transport: transport,
    );
    return connectOn(
      SocketRemoteDuplex(endpoint.socket),
      clientName: clientName,
      token: endpoint.token,
      local: local,
    );
  }

  /// Faz o handshake sobre um [RemoteDuplex] já aberto e devolve a conexão
  /// pronta. É o ponto único do protocolo — serve `Socket` (desktop) e canal
  /// `dartssh2` (mobile/`forwardLocalUnix`) sem duplicar o handshake.
  static Future<RemoteConnection> connectOn(
    RemoteDuplex duplex, {
    String clientName = 'cockpit',
    String? token,
    bool local = false,
  }) async {
    // Erros de escrita chegam async pelo done do canal (ex.: EPIPE quando um
    // forward SSH aceita localmente mas o lado remoto recusa) — sem este
    // guard, derrubam o processo por fora de qualquer try/catch.
    unawaited(duplex.done.catchError((Object _) {}));

    // Uma única subscription do canal, alimentando um broadcast; o
    // handshake é apenas a primeira mensagem desse stream.
    final messages = StreamController<RemoteMessage>.broadcast();
    _codec
        .decodeStream(duplex.input)
        .listen(
          messages.add,
          onError: (Object e) {
            messages.addError(
              TerminalException(TerminalErrorKind.transport, '$e'),
            );
            messages.close();
          },
          onDone: messages.close,
        );

    final firstReply = messages.stream.first;
    duplex.add(
      utf8.encode(
        _codec.encode(
          Hello(
            version: protocolVersion,
            client: clientName,
            token: token,
            local: local,
          ),
        ),
      ),
    );

    final ack = await firstReply.timeout(const Duration(seconds: 10));
    if (ack is RemoteError) {
      duplex.destroy();
      throw TerminalException(TerminalErrorKind.protocol, ack.code);
    }
    if (ack is! HelloAck) {
      duplex.destroy();
      throw const TerminalException(
        TerminalErrorKind.protocol,
        'unexpected handshake reply',
      );
    }
    final connection = RemoteConnection._(
      duplex,
      ack.server,
      messages,
      serverExecutable: ack.executable,
      serverPid: ack.pid,
    );
    unawaited(messages.done.then((_) => connection._open = false));
    return connection;
  }

  void send(RemoteMessage message) {
    if (!_open) return;
    _duplex.add(utf8.encode(_codec.encode(message)));
  }

  int _nextRid = 0;

  /// Chamada RPC request/response (domínios fs.*/git.* da Wave 3). Correlaciona
  /// pela `rid`; devolve o `data` em sucesso, lança [RemoteRpcException] no
  /// `ok:false`. Concorrência livre: N chamadas in-flight, cada uma espera a
  /// sua rid.
  Future<Object?> call(
    String method, [
    Map<String, Object?> params = const {},
  ]) {
    if (!_open) {
      throw const RemoteRpcException('transport', 'connection closed');
    }
    final rid = _nextRid++;
    final completer = Completer<Object?>();
    late StreamSubscription<RemoteMessage> sub;
    sub = messages.listen(
      (m) {
        if (m is RpcResponse && m.rid == rid) {
          sub.cancel();
          if (m.ok) {
            completer.complete(m.data);
          } else {
            completer.completeError(
              RemoteRpcException(m.code ?? 'error', m.detail),
            );
          }
        }
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.completeError(
            const RemoteRpcException('transport', 'connection closed'),
          );
        }
      },
    );
    send(RpcRequest(rid: rid, method: method, params: params));
    return completer.future;
  }

  Future<void> close() async {
    _open = false;
    _duplex.destroy();
  }
}
