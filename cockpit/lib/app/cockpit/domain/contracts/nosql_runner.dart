import '../entities/db_connection.dart';

/// Executor CLI-only de comandos NoSQL/cache (Redis, Mongo). Fora do contrato
/// SQL [DbDriver]: recebe o comando cru e devolve o reply já JSON-serializável
/// (null | num | bool | String | List | Map). Plano 51 (CLI-only).
abstract interface class NoSqlRunner {
  /// Redis: envia `parts` (`['GET','foo']`) → reply decodificado.
  Future<Object?> redis(
    DbConnection conn,
    List<String> parts, {
    String? password,
  });

  /// Mongo: roda `command` via `runCommand` → documento de resposta.
  Future<Object?> mongo(
    DbConnection conn,
    Map<String, dynamic> command, {
    String? password,
  });
}
