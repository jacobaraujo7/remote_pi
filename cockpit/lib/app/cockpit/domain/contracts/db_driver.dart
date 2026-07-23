import '../entities/db_connection.dart';
import '../entities/db_result.dart';

/// Executor de queries de um engine. Modelo **efêmero** (decisão D do plano
/// 51): cada chamada abre a conexão, executa e fecha — sem pool, sem estado.
/// Implementações rodam o trabalho pesado fora da UI thread (Isolate).
abstract interface class DbDriver {
  /// Executa [sql] e devolve até [limit] linhas (corte de cursor; linhas a
  /// mais ⇒ `truncated: true`). [password] já resolvido pelo chamador
  /// (secrets/prompt) — drivers nunca resolvem credencial.
  ///
  /// Erros viram [DbQueryException] (kinds: `connection_failed`,
  /// `query_failed`, `timeout`).
  Future<DbResult> query(
    DbConnection conn,
    String sql, {
    required int limit,
    Duration timeout,
    String? password,
  });

  /// Executa DML/DDL e devolve `affectedRows` (em [DbResult.affectedRows]).
  Future<DbResult> execute(
    DbConnection conn,
    String sql, {
    Duration timeout,
    String? password,
  });

  /// Introspecção normalizada: sem [table], lista tabelas (colunas `table`,
  /// `schema`, `type`); com [table], lista colunas (`column`, `type`,
  /// `nullable`, `primaryKey`). Cada engine traduz seu dialeto (sqlite_master /
  /// information_schema) pra essa forma única.
  ///
  /// [schema] restringe a introspecção de colunas a um schema específico
  /// (Postgres/MSSQL têm tabelas homônimas em schemas distintos). Nulo = schema
  /// default do engine (`public`/`dbo`); ignorado por SQLite/MySQL.
  Future<DbResult> schema(
    DbConnection conn, {
    String? table,
    String? schema,
    Duration timeout,
    String? password,
  });
}

/// Resolve o driver de um engine. Engines ainda sem driver (Postgres/MySQL
/// até a Wave 3 do plano 51) devolvem null — o chamador converte em
/// [DbQueryException] `unsupported_engine` com mensagem honesta.
abstract interface class DbDriverRegistry {
  DbDriver? forEngine(DbEngine engine);
}
