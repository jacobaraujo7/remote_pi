/// Configuração do túnel SSH de uma conexão de banco (plano 54).
///
/// Vive como bloco **irmão** da `url` no `databases.json` — não como query
/// param: a URL descreve o destino final e o túnel é ortogonal a ele. Ausente
/// (`null` na [DbConnection]) = conexão TCP direta, comportamento pré-plano 54.
///
/// **Nunca carrega segredo.** [keyPath] é referência a um arquivo (versionável
/// num repo de time); a passphrase, quando a chave é encriptada, mora no cofre
/// do SO — aqui só o flag [savePassphrase]. O conteúdo da chave nunca é
/// copiado pra dentro do Cockpit.
///
/// Autenticação é **só por chave** na v1 (decisão D): bastion sério costuma ter
/// `PasswordAuthentication no`, e cortar password auth remove um segmented
/// control inteiro do dialog.
class SshTunnelConfig {
  const SshTunnelConfig({
    required this.host,
    required this.user,
    required this.keyPath,
    this.port = defaultPort,
    this.savePassphrase = false,
  });

  static const defaultPort = 22;

  /// Reconstrói do bloco `ssh` do `databases.json`. Bloco malformado (sem
  /// host/user/key) devolve `null` — o store pula a entrada em vez de subir
  /// exceção, mesma cortesia da URL inválida.
  static SshTunnelConfig? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final host = (raw['host'] as String? ?? '').trim();
    final user = (raw['user'] as String? ?? '').trim();
    final keyPath = (raw['keyPath'] as String? ?? '').trim();
    if (host.isEmpty || user.isEmpty || keyPath.isEmpty) return null;
    final port = raw['port'];
    return SshTunnelConfig(
      host: host,
      user: user,
      keyPath: keyPath,
      port: port is int && port > 0 ? port : defaultPort,
      savePassphrase: raw['savePassphrase'] as bool? ?? false,
    );
  }

  /// Host do servidor SSH (bastion). **Não** é o host do banco — este último
  /// segue na URL e é resolvido *a partir* do bastion.
  final String host;
  final int port;
  final String user;

  /// Path da chave privada (`~` expandido na hora de ler, não aqui — o `~`
  /// literal é o que queremos versionar).
  final String keyPath;

  /// `true` = a passphrase está (ou deve ficar) no cofre do SO. Chave sem
  /// passphrase mantém `false` e a conexão fica sem segredo nenhum.
  final bool savePassphrase;

  /// Identidade do endpoint SSH — chave de cache de túnel e de host key.
  String get endpoint => '$user@$host:$port';

  /// Rótulo curto do chip no dialog/painel.
  String get label => port == defaultPort ? '$user@$host' : '$user@$host:$port';

  Map<String, Object?> toJson() => {
    'host': host,
    'port': port,
    'user': user,
    'keyPath': keyPath,
    // Sempre explícito: omitir no false deixava o `true` antigo no arquivo
    // quando o usuário desligava o switch (mesma lição do savePassword).
    'savePassphrase': savePassphrase,
  };

  SshTunnelConfig copyWith({
    String? host,
    int? port,
    String? user,
    String? keyPath,
    bool? savePassphrase,
  }) => SshTunnelConfig(
    host: host ?? this.host,
    port: port ?? this.port,
    user: user ?? this.user,
    keyPath: keyPath ?? this.keyPath,
    savePassphrase: savePassphrase ?? this.savePassphrase,
  );

  @override
  bool operator ==(Object other) =>
      other is SshTunnelConfig &&
      other.host == host &&
      other.port == port &&
      other.user == user &&
      other.keyPath == keyPath &&
      other.savePassphrase == savePassphrase;

  @override
  int get hashCode => Object.hash(host, port, user, keyPath, savePassphrase);
}
