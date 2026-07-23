import 'dart:async';
import 'dart:isolate';

import 'package:anaki_mssql/anaki_mssql.dart';
import 'package:anaki_mysql/anaki_mysql.dart';
import 'package:anaki_orm/anaki_orm.dart';
import 'package:anaki_postgres/anaki_postgres.dart';
import 'package:anaki_sqlite/anaki_sqlite.dart';
import 'package:cockpit/app/cockpit/domain/contracts/db_driver.dart';
import 'package:cockpit/app/cockpit/domain/entities/db_connection.dart';
import 'package:cockpit/app/cockpit/domain/entities/db_result.dart';

/// Driver único sobre o **anakiORM** (conectores Rust via FFI) — SQLite,
/// Postgres e MySQL atrás do mesmo contrato [DbDriver].
///
/// A FFI do anaki é **bloqueante** (`block_on` no Rust + call direto no Dart),
/// então cada chamada roda inteira num `Isolate.run` (construir driver → open
/// → query → close). O slot de conexão é global por dylib — seguro porque o
/// `DbQueryService` serializa todas as execuções. Panics do Rust viram erro
/// normal (`ffi_guard`/catch_unwind — anakiORM#2, resolvido).
///
/// Caveats herdados (v1):
/// - `rawQuery` materializa todas as linhas antes do corte de `limit`;
/// - as colunas voltam em **ordem alfabética** (serde_json sem
///   `preserve_order`) — issue aberta upstream;
/// - timeout abandona o Isolate (não cancela o statement).
class AnakiDbDriver implements DbDriver {
  const AnakiDbDriver();

  static const _defaultTimeout = Duration(seconds: 30);

  @override
  Future<DbResult> query(
    DbConnection conn,
    String sql, {
    required int limit,
    Duration timeout = _defaultTimeout,
    String? password,
  }) => _run(conn, password, timeout, (driver, watch) async {
    final rows = await driver.rawQuery(sql, null);
    return _toResult(rows, limit: limit, watch: watch);
  });

  @override
  Future<DbResult> execute(
    DbConnection conn,
    String sql, {
    Duration timeout = _defaultTimeout,
    String? password,
  }) => _run(conn, password, timeout, (driver, watch) async {
    final affected = await driver.rawExecute(sql, null);
    return DbResult(
      columns: const [],
      rows: const [],
      elapsed: watch.elapsed,
      affectedRows: affected,
    );
  });

  @override
  Future<DbResult> schema(
    DbConnection conn, {
    String? table,
    String? schema,
    Duration timeout = _defaultTimeout,
    String? password,
  }) {
    final sql = _schemaSql(conn.engine, table, schema);
    return _run(conn, password, timeout, (driver, watch) async {
      final rows = await driver.rawQuery(sql, null);
      return _toResult(rows, limit: 10000, watch: watch);
    });
  }

  /// Roda [body] num Isolate (a FFI bloqueia a thread): constrói o driver do
  /// engine lá dentro (bindings/FFI não são sendable), abre, executa, fecha.
  Future<DbResult> _run(
    DbConnection conn,
    String? password,
    Duration timeout,
    Future<DbResult> Function(AnakiDriver driver, Stopwatch watch) body,
  ) async {
    // Captura só valores sendable (o DbConnection é imutável e simples).
    try {
      return await Isolate.run(() async {
        final watch = Stopwatch()..start();
        final driver = _buildDriver(conn, password);
        try {
          await driver.rawOpen();
        } on AnakiException catch (e) {
          throw DbQueryException('connection_failed', _message(e));
        }
        try {
          return await body(driver, watch);
        } on ConnectionException catch (e) {
          throw DbQueryException('connection_failed', _message(e));
        } on AnakiException catch (e) {
          throw DbQueryException('query_failed', _message(e));
        } finally {
          try {
            await driver.rawClose();
          } on AnakiException {
            // Fechar falhou depois do resultado — nada útil a fazer.
          }
        }
      }).timeout(timeout);
    } on DbQueryException {
      rethrow;
    } on TimeoutException {
      throw DbQueryException('timeout', 'Query exceeded ${timeout.inSeconds}s');
    }
  }

  static AnakiDriver _buildDriver(DbConnection conn, String? password) {
    switch (conn.engine) {
      case DbEngine.sqlite:
        return SqliteDriver(conn.sqlitePath);
      case DbEngine.postgres:
        return PostgresDriver(
          host: conn.host,
          port: conn.port,
          username: conn.user,
          password: password ?? '',
          database: conn.database,
          // `?sslmode=` da URL; sem o param o Rust usa o default do sqlx.
          sslMode: Uri.parse(conn.url).queryParameters['sslmode'],
        );
      case DbEngine.mysql:
        return MysqlDriver(
          host: conn.host,
          port: conn.port,
          username: conn.user,
          password: password ?? '',
          database: conn.database,
          // `?ssl-mode=` da URL (REQUIRED etc); o driver espera minúsculo
          // (disabled/preferred/required/verify_ca/verify_identity).
          sslMode: Uri.parse(
            conn.url,
          ).queryParameters['ssl-mode']?.toLowerCase(),
        );
      case DbEngine.mssql:
        final params = Uri.parse(conn.url).queryParameters;
        return MssqlDriver(
          host: conn.host,
          port: conn.port,
          username: conn.user,
          password: password ?? '',
          database: conn.database,
          // `?trustcert=true` pra dev com cert self-signed.
          trustCert: params['trustcert'] == 'true',
          // `?encrypt=` do switch Use SSL/TLS; ausente = default do tiberius.
          encrypt: switch (params['encrypt']) {
            'true' => true,
            'false' => false,
            _ => null,
          },
        );
      case DbEngine.redis:
      case DbEngine.mongo:
        // Não-SQL: nunca chega aqui (registry devolve null; o CLI usa o
        // NoSqlCommandService). Fecha o switch exaustivo.
        throw DbQueryException(
          'unsupported_engine',
          '${conn.engine.label} is not a SQL engine.',
        );
    }
  }

  /// Converte as linhas-mapa do anaki no [DbResult] posicional do contrato.
  /// Ordem das colunas = ordem das chaves do JSON (alfabética por ora).
  static DbResult _toResult(
    List<Map<String, dynamic>> rows, {
    required int limit,
    required Stopwatch watch,
  }) {
    if (rows.isEmpty) {
      return DbResult(columns: const [], rows: const [], elapsed: watch.elapsed);
    }
    final columns = rows.first.keys.toList();
    final truncated = rows.length > limit;
    final data = <List<Object?>>[
      for (final row in truncated ? rows.take(limit) : rows)
        [for (final c in columns) row[c]],
    ];
    return DbResult(
      columns: [
        for (var i = 0; i < columns.length; i++)
          DbColumn(columns[i], _inferType(data, i)),
      ],
      rows: data,
      truncated: truncated,
      elapsed: watch.elapsed,
    );
  }

  /// SQL de introspecção normalizada por engine ([DbDriver.schema]). Nome da
  /// tabela e do schema são interpolados — sanitizados por [_safeIdent] (o
  /// binding de params do anaki é por `@nome` e reescreve o SQL; mais simples
  /// validar).
  ///
  /// **Listagem de tabelas** (sem [table]) devolve colunas `table`, `schema`,
  /// `type` — Postgres/MSSQL trazem TODOS os schemas de usuário (não só
  /// `public`/`dbo`), pra tabelas fora do schema default não sumirem. MySQL usa
  /// `DATABASE()` (schema = database) e SQLite não tem schema (`NULL`).
  ///
  /// **Listagem de colunas** (com [table]) restringe ao [schema] informado
  /// (default do engine se nulo) — Postgres/MSSQL têm tabelas homônimas em
  /// schemas distintos; sem o filtro elas se fundiriam.
  static String _schemaSql(DbEngine engine, String? table, String? schema) {
    final t = table == null ? null : _safeIdent(table);
    switch (engine) {
      case DbEngine.sqlite:
        return t == null
            ? 'SELECT name AS "table", NULL AS "schema", type '
                  'FROM sqlite_master '
                  "WHERE type IN ('table','view') AND name NOT LIKE 'sqlite_%' "
                  'ORDER BY name'
            : 'SELECT name AS "column", type, '
                  '(CASE "notnull" WHEN 0 THEN 1 ELSE 0 END) AS nullable, '
                  'pk AS "primaryKey" FROM pragma_table_info(\'$t\')';
      case DbEngine.postgres:
        final s = _safeIdent(schema ?? 'public');
        return t == null
            ? 'SELECT table_name AS "table", table_schema AS "schema", '
                  "CASE table_type WHEN 'VIEW' THEN 'view' ELSE 'table' END "
                  'AS type FROM information_schema.tables '
                  "WHERE table_schema NOT IN ('pg_catalog','information_schema')"
                  ' ORDER BY table_schema, table_name'
            : 'SELECT c.column_name AS "column", c.data_type AS type, '
                  "CASE WHEN c.is_nullable = 'YES' THEN 1 ELSE 0 END "
                  'AS nullable, '
                  'CASE WHEN pk.column_name IS NULL THEN 0 ELSE 1 END '
                  'AS "primaryKey" '
                  'FROM information_schema.columns c '
                  'LEFT JOIN ('
                  ' SELECT kcu.column_name '
                  ' FROM information_schema.table_constraints tc '
                  ' JOIN information_schema.key_column_usage kcu '
                  '   ON kcu.constraint_name = tc.constraint_name '
                  '  AND kcu.table_schema = tc.table_schema '
                  " WHERE tc.constraint_type = 'PRIMARY KEY' "
                  "  AND tc.table_schema = '$s' AND tc.table_name = '$t'"
                  ') pk ON pk.column_name = c.column_name '
                  "WHERE c.table_schema = '$s' AND c.table_name = '$t' "
                  'ORDER BY c.ordinal_position';
      case DbEngine.mysql:
        return t == null
            ? 'SELECT table_name AS `table`, table_schema AS `schema`, '
                  "CASE table_type WHEN 'VIEW' THEN 'view' ELSE 'table' END "
                  'AS type FROM information_schema.tables '
                  'WHERE table_schema = DATABASE() ORDER BY table_name'
            : 'SELECT column_name AS `column`, data_type AS type, '
                  "CASE is_nullable WHEN 'YES' THEN 1 ELSE 0 END AS nullable, "
                  "CASE column_key WHEN 'PRI' THEN 1 ELSE 0 END "
                  'AS `primaryKey` FROM information_schema.columns '
                  "WHERE table_schema = DATABASE() AND table_name = '$t' "
                  'ORDER BY ordinal_position';
      case DbEngine.mssql:
        final s = _safeIdent(schema ?? 'dbo');
        return t == null
            ? 'SELECT TABLE_NAME AS [table], TABLE_SCHEMA AS [schema], '
                  "CASE TABLE_TYPE WHEN 'VIEW' THEN 'view' ELSE 'table' END "
                  'AS type FROM INFORMATION_SCHEMA.TABLES '
                  'ORDER BY TABLE_SCHEMA, TABLE_NAME'
            : 'SELECT c.COLUMN_NAME AS [column], c.DATA_TYPE AS type, '
                  "CASE c.IS_NULLABLE WHEN 'YES' THEN 1 ELSE 0 END "
                  'AS nullable, '
                  'CASE WHEN pk.COLUMN_NAME IS NULL THEN 0 ELSE 1 END '
                  'AS [primaryKey] '
                  'FROM INFORMATION_SCHEMA.COLUMNS c '
                  'LEFT JOIN ('
                  ' SELECT ku.COLUMN_NAME '
                  ' FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc '
                  ' JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE ku '
                  '   ON ku.CONSTRAINT_NAME = tc.CONSTRAINT_NAME '
                  " WHERE tc.CONSTRAINT_TYPE = 'PRIMARY KEY' "
                  "  AND tc.TABLE_SCHEMA = '$s' AND tc.TABLE_NAME = '$t'"
                  ') pk ON pk.COLUMN_NAME = c.COLUMN_NAME '
                  "WHERE c.TABLE_SCHEMA = '$s' AND c.TABLE_NAME = '$t' "
                  'ORDER BY c.ORDINAL_POSITION';
      case DbEngine.redis:
      case DbEngine.mongo:
        throw const DbQueryException(
          'unsupported_engine',
          'Schema introspection is SQL-only.',
        );
    }
  }

  /// Identificador seguro pra interpolar (tabela/schema): só
  /// palavra/dígito/underscore.
  static String _safeIdent(String name) {
    if (!RegExp(r'^[A-Za-z0-9_.$]+$').hasMatch(name)) {
      throw DbQueryException('query_failed', 'Invalid table name: "$name"');
    }
    return name;
  }

  static String _message(AnakiException e) =>
      e.details == null ? e.message : '${e.message}\n${e.details}';

  static String _inferType(List<List<Object?>> rows, int col) {
    for (final row in rows) {
      final v = row[col];
      if (v == null) continue;
      return switch (v) {
        int() => 'INTEGER',
        double() => 'REAL',
        bool() => 'BOOL',
        String() => 'TEXT',
        _ => '',
      };
    }
    return '';
  }
}
