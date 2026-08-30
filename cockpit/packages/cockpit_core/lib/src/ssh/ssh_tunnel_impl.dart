import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'ssh_log.dart';

import 'local_socks_server.dart';
import 'ssh_key_pem.dart';
import 'ssh_tunnel.dart';
import 'ssh_tunnel_config.dart';
import 'package:dartssh2/dartssh2.dart';

/// Túnel SSH em Dart puro (`dartssh2`) com port-forward local.
///
/// Cada túnel é um `ServerSocket` em `127.0.0.1:<porta efêmera>` cujas conexões
/// aceitas viram canais `forwardLocal` no cliente SSH. O driver de banco —
/// rodando noutro Isolate, onde sockets não chegam — só vê um endereço TCP
/// normal.
///
/// **Cache por (config, alvo)**: um túnel serve N queries. Abrir por query
/// custaria um handshake SSH (~1s) em cada uma, e o modelo dos drivers é
/// efêmero de propósito. TTL ocioso derruba o que ninguém usa.
class SshTunnelImpl implements SshTunnel {
  SshTunnelImpl(this._hostKeys);

  final SshHostKeyStore _hostKeys;

  /// Túnel ocioso por mais que isso é derrubado. Longo o bastante pra cobrir
  /// uma sessão de trabalho na tab `.dbq`, curto o bastante pra não deixar
  /// conexão SSH pendurada a tarde toda.
  static const idleTtl = Duration(minutes: 5);

  static const _connectTimeout = Duration(seconds: 15);

  /// Teto do handshake+auth SSH. O `dartssh2` aceita os dois como parâmetro;
  /// sem eles não há limite algum.
  static const _handshakeTimeout = Duration(seconds: 20);

  /// Teto da abertura inteira (chave → TCP → handshake → listener). Rede que
  /// engole pacotes não gera erro em lugar nenhum — sem este teto, `ensure`
  /// simplesmente nunca completa.
  static const _openTimeout = Duration(seconds: 30);

  final Map<String, _ActiveTunnel> _active = {};

  /// Aberturas em voo, por chave — duas queries disparadas juntas na mesma
  /// conexão devem compartilhar **um** handshake, não correr duas vezes.
  final Map<String, Future<TunnelEndpoint>> _opening = {};

  @override
  Future<TunnelEndpoint> ensure(
    SshTunnelConfig config, {
    required String targetHost,
    required int targetPort,
    String? passphrase,
    HostKeyPrompt? onUnknownHostKey,
  }) {
    final key = '${config.endpoint}|${config.keyPath}|$targetHost:$targetPort';

    final live = _active[key];
    if (live != null && live.isAlive) return Future.value(live.touch());
    if (live != null) unawaited(_drop(key));

    return _opening[key] ??=
        _guardOpen(
          () => _open(
            key,
            config,
            targetHost,
            targetPort,
            passphrase,
            onUnknownHostKey,
          ),
          config,
          // Corpo em bloco, não arrow: `Map.remove` devolve o valor removido — que
          // aqui é ESTE future. Com arrow, o `whenComplete` passava a esperar o
          // future que ele mesmo completa e travava pra sempre; só o primeiro
          // chamador sofria (os seguintes achavam o túnel já no cache), o que fazia
          // parecer "a UI trava mas a CLI funciona".
        ).whenComplete(() {
          _opening.remove(key);
        });
  }

  /// Proxies SOCKS ativos, por endpoint SSH (um serve todos os nós).
  final Map<String, _ActiveSocks> _socks = {};
  final Map<String, Future<TunnelEndpoint>> _openingSocks = {};

  @override
  Future<TunnelEndpoint> ensureSocks(
    SshTunnelConfig config, {
    String? passphrase,
    HostKeyPrompt? onUnknownHostKey,
  }) {
    final key = '${config.endpoint}|${config.keyPath}';
    final live = _socks[key];
    if (live != null && live.isAlive) return Future.value(live.touch());
    if (live != null) unawaited(_dropSocks(key));

    return _openingSocks[key] ??=
        _guardOpen(
          () => _openSocks(key, config, passphrase, onUnknownHostKey),
          config,
          // Mesma armadilha do `_opening` acima: bloco, nunca arrow.
        ).whenComplete(() {
          _openingSocks.remove(key);
        });
  }

  Future<TunnelEndpoint> _openSocks(
    String key,
    SshTunnelConfig config,
    String? passphrase,
    HostKeyPrompt? onUnknownHostKey,
  ) async {
    final client = await _connect(config, passphrase, onUnknownHostKey);
    // SOCKS5 **nosso** (`LocalSocksServer`) em vez do `forwardDynamic` do
    // dartssh2: o de lá escuta o ServerSocket sem `onError`, então um reset no
    // accept — que o driver Mongo provoca a cada teardown de pool — derrubava o
    // proxy silenciosamente e pendurava todo comando seguinte. Ver o doc da
    // classe.
    final LocalSocksServer server;
    try {
      server = await LocalSocksServer.start(
        (host, port) async =>
            _ForwardedChannel(await client.forwardLocal(host, port)),
      );
    } on Object catch (e) {
      client.close();
      throw SshTunnelException(
        'ssh_connect_failed',
        'Cannot open local SOCKS proxy: $e',
      );
    }

    final socks = _ActiveSocks(
      client: client,
      server: server,
      onExpired: () => _dropSocks(key),
    );
    _socks[key] = socks;
    unawaited(client.done.whenComplete(() => _dropSocks(key)));
    return socks.touch();
  }

  /// Aplica o teto de [_openTimeout] à abertura e traduz o estouro num erro
  /// acionável em vez de deixar o chamador esperando indefinidamente.
  Future<TunnelEndpoint> _guardOpen(
    Future<TunnelEndpoint> Function() open,
    SshTunnelConfig config,
  ) async {
    try {
      return await open().timeout(_openTimeout);
    } on TimeoutException {
      throw SshTunnelException(
        'ssh_connect_failed',
        'Timed out opening the SSH tunnel to ${config.endpoint} after '
            '${_openTimeout.inSeconds}s.',
      );
    }
  }

  Future<void> _dropSocks(String key) async {
    final socks = _socks.remove(key);
    await socks?.close();
  }

  Future<TunnelEndpoint> _open(
    String key,
    SshTunnelConfig config,
    String targetHost,
    int targetPort,
    String? passphrase,
    HostKeyPrompt? onUnknownHostKey,
  ) async {
    final client = await _connect(config, passphrase, onUnknownHostKey);

    // Porta efêmera: o listener é **guardado**, nunca fechado-e-reaberto. A
    // variante ingênua (bind 0 → ler porta → fechar → rebind) abre janela pra
    // outro processo tomar a porta no meio.
    final ServerSocket server;
    try {
      server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    } on SocketException catch (e) {
      client.close();
      throw SshTunnelException(
        'ssh_connect_failed',
        'Cannot open local forwarding port: ${e.message}',
      );
    }

    final tunnel = _ActiveTunnel(
      client: client,
      server: server,
      onExpired: () => _drop(key),
    );
    _active[key] = tunnel;

    server.listen(
      (local) => tunnel.bridge(local, targetHost, targetPort),
      onError: (Object _) {},
      cancelOnError: false,
    );
    // Conexão SSH caiu (rede, timeout do servidor): evicta pra que o próximo
    // `ensure` reabra em vez de devolver um endpoint morto.
    unawaited(client.done.whenComplete(() => _drop(key)));

    return tunnel.touch();
  }

  /// Abre e autentica uma conexão SSH. Compartilhada por port-forward e SOCKS
  /// — a diferença entre os dois é só o que se pendura em cima dela.
  Future<SSHClient> _connect(
    SshTunnelConfig config,
    String? passphrase,
    HostKeyPrompt? onUnknownHostKey,
  ) async {
    final identities = SshKeyPem.parse(
      await SshKeyPem.read(config.keyPath),
      passphrase,
    );

    // O handler de host key só devolve bool; o *porquê* da recusa viaja aqui
    // pra virar mensagem honesta depois (dentro do handler não dá pra lançar
    // sem o dartssh2 traduzir tudo pra um erro de handshake genérico).
    String? rejection;
    String? rejectedEndpoint;
    String? rejectedFingerprint;

    final SSHClient client;
    try {
      final socket = await SSHSocket.connect(
        config.host,
        config.port,
        timeout: _connectTimeout,
      );
      client = SSHClient(
        socket,
        username: config.user,
        identities: identities,
        // Sem estes, `client.authenticated` espera pra sempre: um servidor que
        // aceita o TCP e trava no handshake pendura o túnel — e, com a fila
        // serializada do DbQueryService, pendura o app inteiro junto.
        handshakeTimeout: _handshakeTimeout,
        authTimeout: _handshakeTimeout,
        onVerifyHostKey: (type, fingerprint) async {
          final printed = utf8.decode(fingerprint);
          // Guardados para a exceção: são o que permite oferecer "confiar"
          // num cliente do outro lado do protocolo (plano 62, onda 2).
          rejectedEndpoint = config.endpoint;
          rejectedFingerprint = printed;
          final known = _hostKeys.trusted(config.endpoint);
          if (known == printed) return true;
          if (known != null) {
            // Chave mudou: recusa dura, sem opção de aceitar inline. Pode ser
            // reinstalação do servidor — ou MITM, que é exatamente o que o
            // túnel existe pra impedir.
            rejection =
                'ssh_host_key_changed|The host key for ${config.endpoint} '
                'changed. Expected $known, got $printed. If the server was '
                'rebuilt, remove the saved key in the connection dialog; '
                'otherwise this may be a machine-in-the-middle attack.';
            return false;
          }
          if (onUnknownHostKey == null) {
            rejection =
                'ssh_host_key_unknown|Unknown host key for ${config.endpoint} '
                '($printed). Open this connection in the Cockpit UI once to '
                'review and trust it.';
            return false;
          }
          final verdict = await onUnknownHostKey(config.endpoint, printed);
          if (verdict != HostKeyVerdict.trust) {
            rejection =
                'ssh_host_key_unknown|Host key for ${config.endpoint} was not '
                'trusted.';
            return false;
          }
          await _hostKeys.trust(config.endpoint, printed);
          return true;
        },
      );
      await client.authenticated;
    } on SshTunnelException {
      rethrow;
    } on Object catch (e) {
      final reason = rejection;
      if (reason != null) {
        final split = reason.indexOf('|');
        throw SshTunnelException(
          reason.substring(0, split),
          reason.substring(split + 1),
          endpoint: rejectedEndpoint,
          fingerprint: rejectedFingerprint,
        );
      }
      if (e is SSHAuthFailError || e is SSHAuthAbortError) {
        throw SshTunnelException(
          'ssh_auth_failed',
          'SSH authentication failed for ${config.endpoint}. Check the user '
              'and whether this key is authorized on the server.',
        );
      }
      throw SshTunnelException(
        'ssh_connect_failed',
        'Cannot reach SSH server ${config.host}:${config.port}: $e',
      );
    }

    return client;
  }

  Future<void> _drop(String key) async {
    final tunnel = _active.remove(key);
    await tunnel?.close();
  }

  @override
  Future<void> closeAll() async {
    final all = _active.values.toList();
    _active.clear();
    for (final tunnel in all) {
      await tunnel.close();
    }
    final socks = _socks.values.toList();
    _socks.clear();
    for (final proxy in socks) {
      await proxy.close();
    }
  }
}

/// Um túnel vivo: cliente SSH + listener local + relógio de ociosidade.
class _ActiveTunnel {
  _ActiveTunnel({
    required this.client,
    required this.server,
    required this.onExpired,
  });

  final SSHClient client;
  final ServerSocket server;
  final Future<void> Function() onExpired;

  Timer? _idle;
  bool _closed = false;

  bool get isAlive => !_closed && !client.isClosed;

  TunnelEndpoint touch() {
    _idle?.cancel();
    _idle = Timer(SshTunnelImpl.idleTtl, () => unawaited(onExpired()));
    return TunnelEndpoint(server.address.address, server.port);
  }

  /// Liga um socket local a um canal `forwardLocal`. Cada conexão do driver
  /// (modelo efêmero: uma por query) vira um canal novo no mesmo cliente SSH.
  Future<void> bridge(Socket local, String targetHost, int targetPort) async {
    touch(); // uso real também adia o TTL, não só o `ensure`
    final SSHForwardChannel channel;
    try {
      channel = await client.forwardLocal(targetHost, targetPort);
    } on Object catch (e) {
      // Porta fechada do outro lado do bastion: derruba só esta conexão — o
      // driver reporta como falha de conexão, que é o que de fato houve.
      sshLog('SSH forward to $targetHost:$targetPort failed: $e');
      await local.close();
      return;
    }
    unawaited(
      local.cast<List<int>>().pipe(channel.sink).catchError((Object _) {}),
    );
    unawaited(
      channel.stream
          .cast<List<int>>()
          .pipe(local)
          .catchError((Object _) {})
          .whenComplete(() => local.destroy()),
    );
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _idle?.cancel();
    await server.close();
    client.close();
  }
}

/// Adapta o canal do `dartssh2` ao contrato mínimo do [LocalSocksServer] — é o
/// que mantém o servidor SOCKS ignorante sobre qual biblioteca SSH está embaixo.
class _ForwardedChannel implements SocksChannel {
  _ForwardedChannel(this._channel);

  final SSHForwardChannel _channel;

  @override
  Stream<List<int>> get stream => _channel.stream.cast<List<int>>();

  @override
  StreamSink<List<int>> get sink => _channel.sink;

  @override
  void destroy() {
    try {
      _channel.destroy();
    } on Object {
      /* já morto */
    }
  }
}

/// Proxy SOCKS5 vivo sobre uma conexão SSH. Diferente do [_ActiveTunnel], não
/// tem alvo fixo: o destino vem em cada requisição SOCKS, que é justamente o
/// que faz replica set e SRV funcionarem.
class _ActiveSocks {
  _ActiveSocks({
    required this.client,
    required this.server,
    required this.onExpired,
  });

  final SSHClient client;
  final LocalSocksServer server;
  final Future<void> Function() onExpired;

  Timer? _idle;
  bool _closed = false;

  /// `server.isAlive` é o que faltava no `forwardDynamic`: se o listener do
  /// proxy morreu, este túnel é lixo e o `ensureSocks` reabre.
  bool get isAlive => !_closed && !client.isClosed && server.isAlive;

  TunnelEndpoint touch() {
    _idle?.cancel();
    _idle = Timer(SshTunnelImpl.idleTtl, () => unawaited(onExpired()));
    return TunnelEndpoint(server.host, server.port);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _idle?.cancel();
    await server.close();
    client.close();
  }
}
