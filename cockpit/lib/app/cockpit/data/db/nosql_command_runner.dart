import 'dart:async';
import 'dart:isolate';

import 'package:anaki_mongodb/anaki_mongodb.dart';
import 'package:anaki_redis/anaki_redis.dart';
import 'package:cockpit/app/cockpit/domain/contracts/nosql_runner.dart';
import 'package:cockpit/app/cockpit/domain/entities/db_connection.dart';
import 'package:cockpit/app/cockpit/domain/entities/db_result.dart';

/// Executor **CLI-only** de comandos NoSQL/cache via anakiORM (Redis, Mongo).
/// Não passa pelo contrato SQL `DbDriver` — devolve o reply cru, normalizado
/// pra JSON. Roda num Isolate (a FFI bloqueia), modelo efêmero (open→run→close).
class NoSqlRunnerImpl implements NoSqlRunner {
  const NoSqlRunnerImpl();

  static const _timeout = Duration(seconds: 30);

  /// Redis: envia `parts` (`['GET','foo']`) e devolve o reply decodificado
  /// (null | int | String | List | Map), já JSON-serializável.
  @override
  Future<Object?> redis(
    DbConnection conn,
    List<String> parts, {
    String? password,
  }) async {
    if (parts.isEmpty) {
      throw const DbQueryException('query_failed', 'Empty Redis command.');
    }
    final host = conn.host;
    final port = conn.port;
    final user = conn.user.isEmpty ? null : conn.user;
    final db = int.tryParse(conn.database) ?? 0;
    return _guard(
      () => Isolate.run(() async {
        final client = AnakiRedis(
          host: host,
          port: port,
          username: user,
          password: password,
          db: db,
        );
        await client.open();
        try {
          return _jsonable(await client.command(parts));
        } finally {
          await client.close();
        }
      }),
    );
  }

  /// Redis em lote: mesma conexão pra todos os [commands] (plano 52 — a
  /// tabela dispara TYPE/TTL/preview por chave; efêmero por comando não dá).
  @override
  Future<List<Object?>> redisMany(
    DbConnection conn,
    List<List<String>> commands, {
    String? password,
  }) async {
    if (commands.isEmpty) return const [];
    for (final parts in commands) {
      if (parts.isEmpty) {
        throw const DbQueryException('query_failed', 'Empty Redis command.');
      }
    }
    final host = conn.host;
    final port = conn.port;
    final user = conn.user.isEmpty ? null : conn.user;
    final db = int.tryParse(conn.database) ?? 0;
    final result = await _guard(
      () => Isolate.run(() async {
        final client = AnakiRedis(
          host: host,
          port: port,
          username: user,
          password: password,
          db: db,
        );
        await client.open();
        try {
          final replies = <Object?>[];
          for (final parts in commands) {
            replies.add(_jsonable(await client.command(parts)));
          }
          return replies;
        } finally {
          await client.close();
        }
      }),
    );
    return (result as List).cast<Object?>();
  }

  /// Mongo: roda um comando (`{find: 'users', filter: {...}}`) via `runCommand`
  /// e devolve o documento de resposta, normalizado pra JSON.
  @override
  Future<Object?> mongo(
    DbConnection conn,
    Map<String, dynamic> command, {
    String? password,
  }) async {
    final host = conn.host;
    final port = conn.port;
    final user = conn.user.isEmpty ? null : conn.user;
    final database = conn.database;
    return _guard(
      () => Isolate.run(() async {
        // extendedJsonCodec OFF (plano 53, decisão C): replies mantêm
        // `{"$oid":…}`/`{"$date":…}` como JSON puro — round-trip lossless pro
        // collection browser e saída canônica no CLI (ObjectId como hex cru
        // era ambíguo). Comandos de entrada já são extended JSON do chamador.
        final mongo = AnakiMongoDb(
          MongoDriver(
            host: host,
            port: port,
            username: user,
            password: password,
            database: database,
          ),
          extendedJsonCodec: false,
        );
        await mongo.open();
        try {
          return _jsonable(await mongo.runCommand(command));
        } finally {
          await mongo.close();
        }
      }),
    );
  }

  Future<Object?> _guard(Future<Object?> Function() run) async {
    try {
      return await run().timeout(_timeout);
    } on DbQueryException {
      rethrow;
    } on TimeoutException {
      throw DbQueryException(
        'timeout',
        'Command exceeded ${_timeout.inSeconds}s',
      );
    } on Object catch (e) {
      // O reply do anaki embrulha erros de conexão/comando; sem tipo estável
      // aqui, classifica pela mensagem.
      final msg = e.toString();
      final kind = msg.toLowerCase().contains('connect')
          ? 'connection_failed'
          : 'query_failed';
      throw DbQueryException(kind, msg);
    }
  }

  /// Normaliza o reply pra JSON: tipos não-primitivos (ObjectId, DateTime…)
  /// viram String; mapas/listas são percorridos recursivamente.
  static Object? _jsonable(Object? v) => switch (v) {
    null || int() || double() || bool() || String() => v,
    final Map m => {for (final e in m.entries) '${e.key}': _jsonable(e.value)},
    final List l => [for (final e in l) _jsonable(e)],
    _ => v.toString(),
  };
}
