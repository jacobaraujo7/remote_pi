import 'dart:async';
import 'dart:isolate';

import 'package:anaki_mongodb/anaki_mongodb.dart';
import 'package:anaki_redis/anaki_redis.dart';
import 'package:cockpit/app/cockpit/domain/contracts/nosql_runner.dart';
import 'package:cockpit/app/cockpit/domain/entities/db_connection.dart';
import 'package:cockpit/app/cockpit/domain/entities/db_result.dart';
import 'package:flutter/foundation.dart';

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
    // Só o runner REMOTO usa (chave do segredo no cofre do host, plano 62);
    // aqui a senha já vem resolvida do cofre desta máquina.
    String workspaceRoot = '',
  }) async {
    if (parts.isEmpty) {
      throw const DbQueryException('query_failed', 'Empty Redis command.');
    }
    final host = conn.host;
    final port = conn.port;
    final user = conn.user.isEmpty ? null : conn.user;
    final db = int.tryParse(conn.database) ?? 0;
    // `rediss://` liga TLS pelo scheme — sem repassar, a conexão "segura" ia
    // em claro silenciosamente.
    final tls = conn.useTls;
    return _guard(
      () => Isolate.run(() async {
        final client = AnakiRedis(
          host: host,
          port: port,
          username: user,
          password: password,
          db: db,
          tls: tls,
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
    String workspaceRoot = '',
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
    final tls = conn.useTls;
    final result = await _guard(
      () => Isolate.run(() async {
        final client = AnakiRedis(
          host: host,
          port: port,
          username: user,
          password: password,
          db: db,
          tls: tls,
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
    String? database,
    String workspaceRoot = '',
  }) async {
    // Conecta pela **URI**, não por campos soltos: só assim `mongodb+srv://`
    // (Atlas), TLS e query params como `authSource` sobrevivem. A forma antiga
    // (host/port/user/pass/db) descartava tudo isso — Atlas nunca conectava e
    // `?authSource=admin` autenticava contra o banco errado.
    final uri = _mongoUri(conn, password);
    // Escolha explícita do chamador (seletor de database do painel) vence a
    // URL; sem ela, o fallback histórico.
    final target = (database != null && database.isNotEmpty)
        ? database
        : _mongoDatabase(conn);
    return _guard(
      () => Isolate.run(() async {
        // extendedJsonCodec OFF (plano 53, decisão C): replies mantêm
        // `{"$oid":…}`/`{"$date":…}` como JSON puro — round-trip lossless pro
        // collection browser e saída canônica no CLI (ObjectId como hex cru
        // era ambíguo). Comandos de entrada já são extended JSON do chamador.
        final mongo = AnakiMongoDb(
          MongoDriver.uri(uri, database: target),
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

  /// URI de conexão do Mongo com a senha resolvida embutida. Público porque o
  /// caminho remoto (plano 58) monta a mesma URI antes de mandar ao host — a
  /// senha do cofre entra no userinfo do jeito idêntico ao runner local. Também
  /// é o ponto mais fácil de errar (senha com `@`/`:` quebrando a authority),
  /// então tem cobertura de teste dedicada.
  static String mongoUriFor(DbConnection conn, String? password) =>
      _mongoUri(conn, password);

  @visibleForTesting
  static String mongoDatabaseFor(DbConnection conn) => _mongoDatabase(conn);

  /// URI de conexão do Mongo com a senha resolvida embutida.
  ///
  /// A senha pode vir do cofre (fora da URL) e o construtor por URI não aceita
  /// credencial em parâmetro separado, então ela é injetada no userinfo aqui.
  /// Nunca é persistida: esta string vive só dentro da chamada.
  static String _mongoUri(DbConnection conn, String? password) {
    if (password == null || password.isEmpty) return conn.url;
    final uri = Uri.parse(conn.url);
    // Senha já embutida na própria URL: nada a fazer.
    if (uri.userInfo.contains(':')) return conn.url;
    final user = Uri.encodeComponent(conn.user);
    return uri
        .replace(userInfo: '$user:${Uri.encodeComponent(password)}')
        .toString();
  }

  /// Banco alvo. URLs de Atlas costumam vir sem path (`…mongodb.net/?retry…`)
  /// e o driver exige um banco explícito; nesse caso cai no `authSource` (que
  /// é onde o usuário existe) e, por último, em `admin` — presente em qualquer
  /// deployment, o que mantém `ping`/`listDatabases` funcionando.
  static String _mongoDatabase(DbConnection conn) {
    if (conn.database.isNotEmpty) return conn.database;
    final authSource = Uri.parse(conn.url).queryParameters['authSource'];
    return (authSource != null && authSource.isNotEmpty) ? authSource : 'admin';
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
