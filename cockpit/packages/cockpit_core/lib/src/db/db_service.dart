import '../ssh/ssh_tunnel_config.dart';

/// Descritor de conexão de DB no fio (plano 58, Wave 4; segredos no host,
/// plano 62). O cliente descreve a conexão e o servidor executa a query no
/// host. Campos derivados do `DbConnection` do app.
///
/// **Quem tem a senha depende do modo** (plano 62, decisão B):
///
/// - `savePassword` LIGADO na conexão → [storedSecret] é `true`, [password]
///   vai `null` no fio e o **servidor** resolve o segredo do cofre dele por
///   ([workspaceRoot], [connName]). A senha nunca atravessa.
/// - `savePassword` DESLIGADO → não há segredo guardado em lugar nenhum; o que
///   houver de senha vem embutido em [url] (ou em [password]) e atravessa, que
///   é o preço explícito de não guardar.
class RemoteDbConnDescriptor {
  const RemoteDbConnDescriptor({
    required this.engine,
    this.url = '',
    this.host = '',
    this.port,
    this.user = '',
    this.database = '',
    this.sqlitePath = '',
    this.password,
    this.useTls = false,
    this.workspaceRoot = '',
    this.connName = '',
    this.storedSecret = false,
    this.ssh,
  });

  /// `sqlite` | `postgres` | `mysql` | `mssql` | `redis` | `mongo`.
  final String engine;
  final String url;
  final String host;
  final int? port;
  final String user;
  final String database;
  final String sqlitePath;

  /// Senha em claro. `null` quando [storedSecret] é `true` — nesse modo quem
  /// preenche é o servidor, a partir do cofre do host.
  final String? password;

  /// Raiz do workspace **no host**: primeira metade da chave do segredo.
  final String workspaceRoot;

  /// Nome da conexão: segunda metade da chave do segredo.
  final String connName;

  /// A senha está guardada no host? Quando `true` e o cofre do host não tem
  /// nada para ([workspaceRoot], [connName]), o servidor responde
  /// [DbErrorKind.passwordRequired] em vez de tentar conectar sem senha — que
  /// falharia com um erro do banco sem relação aparente com senha.
  final bool storedSecret;

  /// Túnel SSH (bastion) da conexão, quando houver.
  ///
  /// Vai no fio para que **o host** o abra — é ele quem alcança o bastion e
  /// quem tem a chave privada. Antes o bloco ficava de fora e o host recebia
  /// `host:porta` cru, discando direto: conexão com bastion simplesmente não
  /// funcionava a partir de um cliente remoto.
  final SshTunnelConfig? ssh;

  /// TLS pro Redis (`rediss://`); ignorado pelos demais engines (Postgres/…
  /// derivam de query params na URL; Mongo, do scheme).
  final bool useTls;

  Map<String, Object?> toJson() => {
    'engine': engine,
    if (url.isNotEmpty) 'url': url,
    if (host.isNotEmpty) 'host': host,
    if (port != null) 'port': port,
    if (user.isNotEmpty) 'user': user,
    if (database.isNotEmpty) 'database': database,
    if (sqlitePath.isNotEmpty) 'sqlitePath': sqlitePath,
    if (password != null) 'password': password,
    if (useTls) 'useTls': useTls,
    if (workspaceRoot.isNotEmpty) 'workspaceRoot': workspaceRoot,
    if (connName.isNotEmpty) 'connName': connName,
    if (storedSecret) 'storedSecret': true,
    if (ssh != null) 'ssh': ssh!.toJson(),
  };

  /// Cópia com a senha resolvida — usada só pelo servidor, ao completar o
  /// descritor com o segredo do cofre do host.
  RemoteDbConnDescriptor withPassword(String? value) => RemoteDbConnDescriptor(
    engine: engine,
    url: url,
    host: host,
    port: port,
    user: user,
    database: database,
    sqlitePath: sqlitePath,
    password: value,
    useTls: useTls,
    workspaceRoot: workspaceRoot,
    connName: connName,
    storedSecret: storedSecret,
    ssh: ssh,
  );

  /// Cópia apontando para a ponta local do túnel (SQL e Redis, que leem
  /// [host]/[port]). A URL também é reescrita: o Postgres tira `sslmode` dela,
  /// e deixar host/porta divergindo entre os dois campos é armadilha.
  RemoteDbConnDescriptor withEndpoint(String newHost, int newPort) =>
      _copy(host: newHost, port: newPort, url: _urlWithEndpoint(newHost, newPort));

  /// Cópia com proxy SOCKS5 na URL — o caminho do Mongo.
  ///
  /// Port-forward não serve lá: num replica set o driver pergunta ao servidor
  /// quem são os membros e passa a discar os hostnames reais, furando qualquer
  /// porta fixa. Com SOCKS quem escolhe o destino é o driver.
  RemoteDbConnDescriptor withSocksProxy(String proxyHost, int proxyPort) {
    if (url.isEmpty) return this;
    final uri = Uri.parse(url);
    final params = Map<String, String>.of(uri.queryParameters)
      ..['proxyHost'] = proxyHost
      ..['proxyPort'] = '$proxyPort';
    return _copy(url: uri.replace(queryParameters: params).toString());
  }

  String _urlWithEndpoint(String newHost, int newPort) {
    if (url.isEmpty) return url;
    try {
      return Uri.parse(url).replace(host: newHost, port: newPort).toString();
    } on FormatException {
      return url;
    }
  }

  RemoteDbConnDescriptor _copy({String? url, String? host, int? port}) =>
      RemoteDbConnDescriptor(
        engine: engine,
        url: url ?? this.url,
        host: host ?? this.host,
        port: port ?? this.port,
        user: user,
        database: database,
        sqlitePath: sqlitePath,
        password: password,
        useTls: useTls,
        workspaceRoot: workspaceRoot,
        connName: connName,
        storedSecret: storedSecret,
        ssh: ssh,
      );

  factory RemoteDbConnDescriptor.fromJson(Map<String, Object?> j) =>
      RemoteDbConnDescriptor(
        engine: j['engine'] as String,
        url: j['url'] as String? ?? '',
        host: j['host'] as String? ?? '',
        port: (j['port'] as num?)?.toInt(),
        user: j['user'] as String? ?? '',
        database: j['database'] as String? ?? '',
        sqlitePath: j['sqlitePath'] as String? ?? '',
        password: j['password'] as String?,
        useTls: j['useTls'] as bool? ?? false,
        workspaceRoot: j['workspaceRoot'] as String? ?? '',
        connName: j['connName'] as String? ?? '',
        storedSecret: j['storedSecret'] as bool? ?? false,
        ssh: SshTunnelConfig.fromJson(j['ssh']),
      );
}

enum DbErrorKind {
  connectionFailed,
  queryFailed,
  timeout,
  unsupportedEngine,

  /// A conexão diz ter senha guardada no host, mas o cofre de lá não tem
  /// nenhuma para ela (plano 62). Acontece com conexão configurada antes da
  /// migração: a senha ficou no cofre do CLIENTE que a cadastrou.
  passwordRequired,

  /// O túnel SSH da conexão não abriu. O `detail` traz o kind do motor
  /// (`ssh_key_missing`, `ssh_host_key_unknown`, …) e é o que a UI usa para
  /// decidir se dá para oferecer "confiar nesta host key".
  sshTunnelFailed,
}

class DbServiceException implements Exception {
  const DbServiceException(this.kind, [this.detail]);
  final DbErrorKind kind;
  final String? detail;

  @override
  String toString() => 'DbServiceException(${kind.name}: $detail)';
}

/// Executa queries SQL contra um DB, do lado do host (plano 58, Wave 4). O
/// resultado é o mapa já-JSON do `DbResult` do app (columns/rows/…), montado
/// no servidor e reidratado no cliente.
abstract interface class DbService {
  /// Roda [sql]. [dml] = execute (INSERT/UPDATE/…) em vez de query.
  Future<Map<String, Object?>> query(
    RemoteDbConnDescriptor conn,
    String sql, {
    int limit = 200,
    bool dml = false,
  });

  /// Redis: envia [parts] (`['GET','foo']`) e devolve o reply JSON-serializável.
  Future<Object?> redis(RemoteDbConnDescriptor conn, List<String> parts);

  /// Redis em lote: [commands] em sequência numa única conexão, replies na
  /// mesma ordem (tabela do plano 52).
  Future<List<Object?>> redisMany(
    RemoteDbConnDescriptor conn,
    List<List<String>> commands,
  );

  /// Mongo: roda [command] (`runCommand`) → documento de resposta. [database]
  /// força o alvo (seletor do painel); ausente = o da URL/fallback.
  Future<Object?> mongo(
    RemoteDbConnDescriptor conn,
    Map<String, Object?> command, {
    String? database,
  });
}
