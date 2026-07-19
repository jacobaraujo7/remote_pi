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
  });

  /// Conexão sqlite a partir de um path (registrada ou detectada).
  factory DbConnection.sqlite(
    String name,
    String path, {
    DbConnectionOrigin origin = DbConnectionOrigin.registered,
  }) => DbConnection(
    name: name,
    engine: DbEngine.sqlite,
    url: 'sqlite:$path',
    origin: origin,
  );

  /// Conexão de rede (postgres/mysql) a partir dos campos do dialog.
  factory DbConnection.network({
    required String name,
    required DbEngine engine,
    required String host,
    int? port,
    required String database,
    String user = '',
    bool savePassword = false,
    DbConnectionOrigin origin = DbConnectionOrigin.registered,
  }) {
    final p = port ?? engine.defaultPort;
    final auth = user.isEmpty ? '' : '${Uri.encodeComponent(user)}@';
    return DbConnection(
      name: name,
      engine: engine,
      url: '${engine.scheme}://$auth$host:$p/${Uri.encodeComponent(database)}',
      savePassword: savePassword,
      origin: origin,
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
    );
  }

  final String name;
  final DbEngine engine;
  final String url;
  final bool savePassword;
  final DbConnectionOrigin origin;

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
    'savePassword': savePassword,
  };

  DbConnection copyWith({String? name, String? url, bool? savePassword}) =>
      DbConnection(
        name: name ?? this.name,
        engine: url == null ? engine : _engineFromUrl(url),
        url: url ?? this.url,
        savePassword: savePassword ?? this.savePassword,
        origin: origin,
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
