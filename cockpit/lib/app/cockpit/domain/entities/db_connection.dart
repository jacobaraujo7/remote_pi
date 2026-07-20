/// Engine de banco suportado pela DB tab (plano 51). A ordem é a do popup do
/// "+" no painel Database; novos engines (MSSQL…) entram aqui + no registry.
enum DbEngine {
  sqlite,
  postgres,
  mysql,
  mssql,
  redis,
  mongo;

  /// Label user-facing (inglês, regra do app).
  String get label => switch (this) {
    DbEngine.sqlite => 'SQLite',
    DbEngine.postgres => 'Postgres',
    DbEngine.mysql => 'MySQL',
    DbEngine.mssql => 'SQL Server',
    DbEngine.redis => 'Redis',
    DbEngine.mongo => 'MongoDB',
  };

  /// Porta default do engine (0 = não se aplica).
  int get defaultPort => switch (this) {
    DbEngine.sqlite => 0,
    DbEngine.postgres => 5432,
    DbEngine.mysql => 3306,
    DbEngine.mssql => 1433,
    DbEngine.redis => 6379,
    DbEngine.mongo => 27017,
  };

  /// Engines SQL (query tabular + `.dbq` + árvore de schema no painel). Os
  /// não-SQL (Redis/Mongo) são **CLI-only** por ora — sem tab nem browse.
  bool get isSql => switch (this) {
    DbEngine.sqlite ||
    DbEngine.postgres ||
    DbEngine.mysql ||
    DbEngine.mssql => true,
    DbEngine.redis || DbEngine.mongo => false,
  };

  /// Scheme da URL (difere do [name] no Mongo: `mongodb://`).
  String get scheme => this == DbEngine.mongo ? 'mongodb' : name;

  static DbEngine? fromScheme(String scheme) {
    for (final e in DbEngine.values) {
      if (e.scheme == scheme) return e;
    }
    return null;
  }
}

/// Modo de acesso da conexão pro caminho **dos agentes (CLI)** — a GUI não é
/// gated (humano clicando é intencional). `read` é o default: escrever via
/// `cockpit db execute` exige opt-in explícito no cadastro.
enum DbAccess {
  /// Só leitura via CLI: `db execute` recusado e `db query`/`db run` passam
  /// pelo gate de statement (SELECT-like apenas).
  read,

  /// Leitura e escrita liberadas via CLI.
  readwrite;

  static DbAccess fromName(String? name) =>
      name == 'readwrite' ? DbAccess.readwrite : DbAccess.read;
}

/// De onde a conexão veio — decide o que o `save()` do store persiste e os
/// chips do painel ("detected"/"local").
enum DbConnectionOrigin {
  /// `.cockpit/databases.json` (versionado).
  registered,

  /// `.cockpit/databases.local.json` (gitignored, merge por cima).
  local,

  /// Arquivo sqlite achado no workspace (magic header) — não persiste.
  detected,
}

/// Uma conexão de banco do workspace. A forma canônica de armazenamento é a
/// **URL** (`sqlite:./app.db`, `postgres://user@host:5432/db?sslmode=require`)
/// — particularidades por engine viajam como query params. **Nunca** carrega
/// senha: o valor mora no cofre do SO (`DbSecrets`), aqui só o flag
/// [savePassword].
class DbConnection {
  const DbConnection({
    required this.name,
    required this.engine,
    required this.url,
    this.savePassword = false,
    this.origin = DbConnectionOrigin.registered,
    this.access = DbAccess.read,
    this.agents = true,
  });

  /// Conexão sqlite a partir de um path (registrada ou detectada).
  factory DbConnection.sqlite(
    String name,
    String path, {
    DbConnectionOrigin origin = DbConnectionOrigin.registered,
    DbAccess access = DbAccess.read,
    bool agents = true,
  }) => DbConnection(
    name: name,
    engine: DbEngine.sqlite,
    url: 'sqlite:$path',
    origin: origin,
    access: access,
    agents: agents,
  );

  /// Conexão de rede (postgres/mysql) a partir dos campos do dialog.
  /// [password] embute `user:senha@` na URL — o caminho de quem NÃO usa o
  /// cofre (savePassword off): a senha vive em texto plano no
  /// `databases.json`, escolha consciente do usuário.
  factory DbConnection.network({
    required String name,
    required DbEngine engine,
    required String host,
    int? port,
    required String database,
    String user = '',
    String? password,
    bool savePassword = false,
    DbConnectionOrigin origin = DbConnectionOrigin.registered,
    DbAccess access = DbAccess.read,
    bool agents = true,
  }) {
    final p = port ?? engine.defaultPort;
    final hasPass = password != null && password.isNotEmpty;
    final auth = user.isEmpty && !hasPass
        ? ''
        : '${Uri.encodeComponent(user)}'
              '${hasPass ? ':${Uri.encodeComponent(password)}' : ''}@';
    return DbConnection(
      name: name,
      engine: engine,
      url: '${engine.scheme}://$auth$host:$p/${Uri.encodeComponent(database)}',
      savePassword: savePassword,
      origin: origin,
      access: access,
      agents: agents,
    );
  }

  /// Reconstrói do JSON do `databases.json` (`{name, url, savePassword?}`).
  /// Lança [FormatException] em URL de engine desconhecido.
  factory DbConnection.fromJson(
    Map<String, Object?> json, {
    DbConnectionOrigin origin = DbConnectionOrigin.registered,
  }) {
    final url = json['url'] as String? ?? '';
    return DbConnection(
      name: json['name'] as String? ?? '',
      engine: _engineFromUrl(url),
      url: url,
      savePassword: json['savePassword'] as bool? ?? false,
      origin: origin,
      // Ausente no JSON legado → read (seguro por padrão; escrever é opt-in).
      access: DbAccess.fromName(json['access'] as String?),
      agents: json['agents'] as bool? ?? true,
    );
  }

  final String name;
  final DbEngine engine;
  final String url;
  final bool savePassword;
  final DbConnectionOrigin origin;

  /// Modo de acesso do caminho dos agentes (CLI). Ver [DbAccess].
  final DbAccess access;

  /// `false` = invisível/recusada na CLI (`db list` omite, comandos falham);
  /// GUI (painel, tab `.dbq`, browsers) segue vendo normalmente.
  final bool agents;

  /// Path do arquivo sqlite (só [DbEngine.sqlite]); relativo à raiz do
  /// workspace quando registrado assim.
  String get sqlitePath =>
      url.startsWith('sqlite:') ? url.substring('sqlite:'.length) : url;

  Uri get _uri => Uri.parse(url);
  String get host => _uri.host;
  int get port => _uri.hasPort ? _uri.port : engine.defaultPort;
  String get database => _uri.pathSegments.isEmpty
      ? ''
      : Uri.decodeComponent(_uri.pathSegments.first);

  /// Só a parte de usuário do userinfo — NUNCA o trecho `:senha` (URLs
  /// editadas na mão podem trazê-lo; incluí-lo aqui gerava username com senha
  /// embutida e senha com `:` extra no wire — handoff 2026-07-18).
  String get user {
    final ui = _uri.userInfo;
    if (ui.isEmpty) return '';
    final ix = ui.indexOf(':');
    return Uri.decodeComponent(ix < 0 ? ui : ui.substring(0, ix));
  }

  /// Senha embutida na URL (`user:senha@`), se houver — fallback de resolução
  /// quando não há senha no cofre. Nunca escrita de volta pelo app.
  String? get urlPassword {
    final ui = _uri.userInfo;
    final ix = ui.indexOf(':');
    return ix < 0 ? null : Uri.decodeComponent(ui.substring(ix + 1));
  }

  /// Alvo curto pra exibição na lista do painel (path ou host:porta).
  String get displayTarget =>
      engine == DbEngine.sqlite ? sqlitePath : '$host:$port';

  Map<String, Object?> toJson() => {
    'name': name,
    'url': url,
    // Sempre explícito (true E false): omitir no false deixava o arquivo com
    // o `savePassword: true` antigo quando o usuário desligava o switch.
    // Mesma regra pra access/agents.
    'savePassword': savePassword,
    'access': access.name,
    'agents': agents,
  };

  DbConnection copyWith({
    String? name,
    String? url,
    bool? savePassword,
    DbAccess? access,
    bool? agents,
  }) => DbConnection(
    name: name ?? this.name,
    engine: url == null ? engine : _engineFromUrl(url),
    url: url ?? this.url,
    savePassword: savePassword ?? this.savePassword,
    origin: origin,
    access: access ?? this.access,
    agents: agents ?? this.agents,
  );

  static DbEngine _engineFromUrl(String url) {
    if (url.startsWith('sqlite:')) return DbEngine.sqlite;
    final engine = DbEngine.fromScheme(Uri.parse(url).scheme);
    if (engine == null) {
      throw FormatException('Unsupported database URL: $url');
    }
    return engine;
  }
}
