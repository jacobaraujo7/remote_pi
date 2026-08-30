import 'ssh_tunnel_config.dart';

/// Ponta local de um túnel ativo: onde o driver de banco deve conectar.
/// Sempre em `127.0.0.1` — o listener é do nosso processo e nunca é exposto na
/// rede.
class TunnelEndpoint {
  const TunnelEndpoint(this.host, this.port);

  final String host;
  final int port;
}

/// Veredito do usuário sobre uma host key ainda desconhecida (TOFU).
enum HostKeyVerdict { trust, reject }

/// Pergunta ao humano se confia numa host key nova. `null` no chamador (o
/// caminho CLI) = ninguém pra perguntar → a conexão falha com
/// `ssh_host_key_unknown` em vez de pendurar ou de confiar cego.
typedef HostKeyPrompt =
    Future<HostKeyVerdict> Function(String endpoint, String fingerprint);

/// Pede a passphrase da chave privada ao humano. Devolve `null` se ele
/// cancelar. `null` no chamador (CLI) = ninguém pra perguntar → falha com
/// `ssh_credential_required`.
typedef SshPassphrasePrompt =
    Future<String?> Function(String connectionName, String keyPath);

/// Abre (e reusa) túneis SSH com port-forward local.
///
/// **Mora no isolate principal** (decisão B do plano 54): os drivers rodam
/// dentro de `Isolate.run` e sockets não são sendable, então o isolate só
/// enxerga `127.0.0.1:<porta>`. É também o que permite o túnel sobreviver ao
/// modelo efêmero (`open→query→close`) dos drivers.
abstract interface class SshTunnel {
  /// Garante um túnel de [config] até `[targetHost]:[targetPort]` (o banco,
  /// resolvido **a partir do bastion**) e devolve a ponta local.
  ///
  /// Reusa o túnel já aberto pra mesma (config, alvo) — handshake por query
  /// custaria ~1s cada. Erros viram [SshTunnelException]; kinds:
  /// `ssh_key_missing`, `ssh_credential_required`, `ssh_auth_failed`,
  /// `ssh_host_key_unknown`, `ssh_host_key_changed`, `ssh_connect_failed`.
  Future<TunnelEndpoint> ensure(
    SshTunnelConfig config, {
    required String targetHost,
    required int targetPort,
    String? passphrase,
    HostKeyPrompt? onUnknownHostKey,
  });

  /// Garante um **proxy SOCKS5** local sobre a mesma conexão SSH e devolve a
  /// ponta local.
  ///
  /// É o que port-forward não consegue fazer: num replica set, o driver
  /// pergunta ao servidor quem são os membros e passa a conectar nos
  /// **hostnames reais** que ele responder — furando qualquer porta fixa que
  /// tenhamos aberto. Com SOCKS o driver escolhe o destino a cada conexão e o
  /// túnel só roteia, então SRV (`mongodb+srv://`) e replica set funcionam sem
  /// que o Cockpit precise conhecer a topologia.
  ///
  /// O proxy é por **config**, não por alvo: uma instância serve todos os nós.
  Future<TunnelEndpoint> ensureSocks(
    SshTunnelConfig config, {
    String? passphrase,
    HostKeyPrompt? onUnknownHostKey,
  });

  /// Derruba todos os túneis (troca de workspace / dispose do app).
  Future<void> closeAll();
}

/// Falha na abertura ou no uso do túnel. [kind] é estável e serve de contrato
/// pro chamador decidir (o `ssh_credential_required`, em especial, é o que a
/// GUI converte em prompt e a CLI em erro honesto).
class SshTunnelException implements Exception {
  const SshTunnelException(
    this.kind,
    this.message, {
    this.endpoint,
    this.fingerprint,
  });

  final String kind;
  final String message;

  /// `user@host:port` do bastion, nos kinds de host key. Preenchido para que
  /// quem recebe a falha **do outro lado do fio** possa oferecer "confiar"
  /// sem ter que extrair isso da prosa da mensagem.
  final String? endpoint;

  /// Fingerprint visto no servidor, nos kinds de host key. É o que o humano
  /// compara antes de confiar — sem ele, o diálogo não tem o que mostrar.
  final String? fingerprint;

  @override
  String toString() => message;
}

/// Classifica a chave privada sem expor o PEM ao domínio. Existe pra que a
/// pergunta "essa chave pede passphrase?" — que decide se o dialog mostra o
/// campo e se o serviço precisa de segredo — não obrigue `domain/` a conhecer
/// formato de chave nem o sistema de arquivos.
abstract interface class SshKeyInspector {
  /// `true` se a chave em [keyPath] é encriptada. Arquivo ausente/ilegível
  /// devolve `false`: o erro acionável vem depois, no connect.
  Future<bool> needsPassphrase(String keyPath);

  /// Sugestão de chave pro dialog: a primeira chave padrão que **existe** no
  /// disco (`~/.ssh/id_ed25519`, depois `id_rsa`), ou `null`. Devolve o path
  /// com `~` literal — é o que queremos versionar.
  Future<String?> defaultKeyPath();
}

/// Host keys já confiadas (TOFU do plano 54, decisão G). Não é `known_hosts`
/// do sistema — o `dartssh2` não lê aquele arquivo, então mantemos o nosso.
abstract interface class SshHostKeyStore {
  /// Fingerprint confiado pra [endpoint] (`user@host:port`), ou `null` se
  /// nunca vimos esse endpoint.
  String? trusted(String endpoint);

  Future<void> trust(String endpoint, String fingerprint);

  /// Esquece o endpoint — usado quando a conexão é apagada.
  Future<void> forget(String endpoint);
}
