import 'package:cockpit/app/cockpit/domain/contracts/db_connection_store.dart';
import 'package:cockpit/app/cockpit/domain/contracts/db_driver.dart';
import 'package:cockpit/app/cockpit/domain/contracts/nosql_runner.dart';
import 'package:cockpit/app/cockpit/domain/entities/db_connection.dart';
import 'package:cockpit/app/cockpit/domain/entities/db_result.dart';

/// Orquestra a execução de queries — o **mesmo** motor pra tab `.dbq` e pra
/// CLI `cockpit db` (decisão J do plano 51): resolve a conexão por nome no
/// store, resolve senha no cofre (nunca expõe pro chamador), escolhe o driver
/// e serializa execuções (pré-requisito do slot global do anaki na Wave 3).
class DbQueryService {
  DbQueryService(this._store, this._secrets, this._registry, this._nosql);

  final DbConnectionStore _store;
  final DbSecrets _secrets;
  final DbDriverRegistry _registry;
  final NoSqlRunner _nosql;

  /// Limite default de linhas quando nem chamada nem `.dbq` especificam.
  static const defaultLimit = 200;

  Future<void> _queue = Future.value();

  Future<List<DbConnection>> connections(String workspaceRoot) =>
      _store.load(workspaceRoot);

  /// Executa [sql] contra a conexão [connName] do workspace. [workspaceId]
  /// entra na chave do cofre (`cockpit.db.<workspaceId>.<nome>`).
  Future<DbResult> query({
    required String workspaceRoot,
    required String workspaceId,
    required String connName,
    required String sql,
    int? limit,
    bool dml = false,
  }) => _serialized(() async {
    final conn = await _resolve(workspaceRoot, connName);
    final driver = _driverFor(conn);
    final password = await _passwordFor(conn, workspaceId);
    final resolved = _resolvePaths(workspaceRoot, conn);
    if (dml) {
      return driver.execute(resolved, sql, password: password);
    }
    return driver.query(
      resolved,
      sql,
      limit: limit ?? defaultLimit,
      password: password,
    );
  });

  /// Introspecção normalizada (tabelas ou colunas de [table]).
  Future<DbResult> schema({
    required String workspaceRoot,
    required String workspaceId,
    required String connName,
    String? table,
    String? schema,
  }) => _serialized(() async {
    final conn = await _resolve(workspaceRoot, connName);
    final driver = _driverFor(conn);
    final password = await _passwordFor(conn, workspaceId);
    return driver.schema(
      _resolvePaths(workspaceRoot, conn),
      table: table,
      schema: schema,
      password: password,
    );
  });

  /// Executa [statements] **em sequência** (mesma conexão lógica, execuções
  /// serializadas) e devolve o resultado do **último** — semântica de "run
  /// script" dos clients (os intermediários preparam o terreno; o final é o
  /// resultado). Limitação v1 (modelo efêmero): cada statement abre/fecha a
  /// própria conexão — temp tables/transactions entre statements não
  /// sobrevivem.
  Future<DbResult> runStatements({
    required String workspaceRoot,
    required String workspaceId,
    required String connName,
    required List<String> statements,
    int? limit,
  }) => _serialized(() async {
    if (statements.isEmpty) {
      throw const DbQueryException('query_failed', 'Nothing to run.');
    }
    final conn = await _resolve(workspaceRoot, connName);
    final driver = _driverFor(conn);
    final password = await _passwordFor(conn, workspaceId);
    final resolved = _resolvePaths(workspaceRoot, conn);
    DbResult? last;
    for (final sql in statements) {
      last = await driver.query(
        resolved,
        sql,
        limit: limit ?? defaultLimit,
        password: password,
      );
    }
    return last!;
  });

  /// Redis (CLI-only): envia `parts` e devolve o reply JSON-serializável.
  Future<Object?> redisCommand({
    required String workspaceRoot,
    required String workspaceId,
    required String connName,
    required List<String> parts,
  }) => _serialized(() async {
    final conn = await _resolve(workspaceRoot, connName);
    if (conn.engine != DbEngine.redis) {
      throw DbQueryException(
        'unsupported_engine',
        '"$connName" is a ${conn.engine.label} connection, not Redis.',
      );
    }
    final password = await _passwordFor(conn, workspaceId);
    return _nosql.redis(conn, parts, password: password);
  });

  /// Redis em lote (tabela do plano 52): [commands] em sequência numa única
  /// conexão, replies na mesma ordem. Mesma resolução de conexão/senha do
  /// [redisCommand] — a UI executa exatamente o que o agente executaria.
  Future<List<Object?>> redisBatch({
    required String workspaceRoot,
    required String workspaceId,
    required String connName,
    required List<List<String>> commands,
  }) => _serialized(() async {
    final conn = await _resolve(workspaceRoot, connName);
    if (conn.engine != DbEngine.redis) {
      throw DbQueryException(
        'unsupported_engine',
        '"$connName" is a ${conn.engine.label} connection, not Redis.',
      );
    }
    final password = await _passwordFor(conn, workspaceId);
    return _nosql.redisMany(conn, commands, password: password);
  });

  /// Mongo (CLI-only): roda `command` (runCommand) e devolve o doc JSON.
  Future<Object?> mongoCommand({
    required String workspaceRoot,
    required String workspaceId,
    required String connName,
    required Map<String, dynamic> command,
  }) => _serialized(() async {
    final conn = await _resolve(workspaceRoot, connName);
    if (conn.engine != DbEngine.mongo) {
      throw DbQueryException(
        'unsupported_engine',
        '"$connName" is a ${conn.engine.label} connection, not MongoDB.',
      );
    }
    final password = await _passwordFor(conn, workspaceId);
    return _nosql.mongo(conn, command, password: password);
  });

  /// Chave do cofre pra senha da conexão — única por workspace+nome.
  static String secretKey(String workspaceId, String connName) =>
      'cockpit.db.$workspaceId.$connName';

  Future<DbConnection> _resolve(String root, String name) async {
    final all = await _store.load(root);
    for (final c in all) {
      if (c.name == name) return c;
    }
    final available = all.map((c) => c.name).join(', ');
    throw DbQueryException(
      'unknown_connection',
      'No connection named "$name" in this workspace. '
          'Available: ${available.isEmpty ? '(none)' : available}',
    );
  }

  DbDriver _driverFor(DbConnection conn) {
    final driver = _registry.forEngine(conn.engine);
    if (driver == null) {
      throw DbQueryException(
        'unsupported_engine',
        '${conn.engine.label} support is not available yet '
            '(arrives with the anakiORM integration).',
      );
    }
    return driver;
  }

  Future<String?> _passwordFor(DbConnection conn, String workspaceId) async {
    if (conn.engine == DbEngine.sqlite) return null;
    if (conn.savePassword) {
      final saved = await _secrets.read(secretKey(workspaceId, conn.name));
      if (saved != null) return saved;
    }
    // Fallback: senha embutida na URL — o caminho de quem NÃO usa o cofre
    // (dialog com "Save Password" off grava `user:senha@` no databases.json)
    // ou json editado na mão.
    return conn.urlPassword;
  }

  /// Sqlite com path relativo é relativo à raiz do workspace.
  DbConnection _resolvePaths(String root, DbConnection conn) {
    if (conn.engine != DbEngine.sqlite) return conn;
    final path = conn.sqlitePath;
    final absolute =
        path.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);
    return absolute ? conn : conn.copyWith(url: 'sqlite:$root/$path');
  }

  /// Serializa execuções: uma por vez, na ordem de chegada. Erros não quebram
  /// a fila.
  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }
}
