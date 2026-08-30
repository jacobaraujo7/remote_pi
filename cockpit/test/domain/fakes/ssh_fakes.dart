import 'package:cockpit_core/cockpit_core.dart';

/// Túnel de mentira: registra o que foi pedido e devolve uma ponta local fixa.
/// Deixa os testes provarem a **reescrita de endpoint** sem servidor SSH.
class FakeSshTunnel implements SshTunnel {
  FakeSshTunnel({this.port = 55432, this.socksPort = 51080, this.failure});

  final int port;

  /// Porta do proxy SOCKS (caminho do Mongo — replica set/SRV).
  final int socksPort;

  /// Quando setado, todo [ensure] lança — usado pra provar a tradução de
  /// erro do serviço (`ssh_credential_required` etc.).
  final SshTunnelException? failure;

  final List<String> requests = [];
  int opens = 0;

  @override
  Future<TunnelEndpoint> ensure(
    SshTunnelConfig config, {
    required String targetHost,
    required int targetPort,
    String? passphrase,
    HostKeyPrompt? onUnknownHostKey,
  }) async {
    requests.add('${config.endpoint}->$targetHost:$targetPort');
    opens++;
    if (failure != null) throw failure!;
    return TunnelEndpoint('127.0.0.1', port);
  }

  /// Endpoints SOCKS pedidos (o caminho do Mongo).
  final List<String> socksRequests = [];

  @override
  Future<TunnelEndpoint> ensureSocks(
    SshTunnelConfig config, {
    String? passphrase,
    HostKeyPrompt? onUnknownHostKey,
  }) async {
    socksRequests.add(config.endpoint);
    opens++;
    if (failure != null) throw failure!;
    return TunnelEndpoint('127.0.0.1', socksPort);
  }

  @override
  Future<void> closeAll() async {}
}

/// Classificador de chave configurável — evita tocar em disco nos testes.
class FakeSshKeyInspector implements SshKeyInspector {
  FakeSshKeyInspector({this.encrypted = false});

  final bool encrypted;

  @override
  Future<bool> needsPassphrase(String keyPath) async => encrypted;

  @override
  Future<String?> defaultKeyPath() async => null;
}

/// Host key store em memória.
class FakeSshHostKeyStore implements SshHostKeyStore {
  final Map<String, String> keys = {};

  @override
  String? trusted(String endpoint) => keys[endpoint];

  @override
  Future<void> trust(String endpoint, String fingerprint) async =>
      keys[endpoint] = fingerprint;

  @override
  Future<void> forget(String endpoint) async => keys.remove(endpoint);
}
