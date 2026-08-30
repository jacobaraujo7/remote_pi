import 'dart:async';
import 'dart:isolate';

import 'package:anaki_mongodb/anaki_mongodb.dart';
import 'package:anaki_mssql/anaki_mssql.dart';
import 'package:anaki_mysql/anaki_mysql.dart';
import 'package:anaki_orm/anaki_orm.dart';
import 'package:anaki_postgres/anaki_postgres.dart';
import 'package:anaki_redis/anaki_redis.dart';
import 'package:anaki_sqlite/anaki_sqlite.dart';
import 'package:cockpit_core/cockpit_core.dart';

/// Executa queries SQL no host via anaki (plano 58, Wave 4). Roda cada query
/// num Isolate (a FFI bloqueia a thread), constrói o driver do engine lá
/// dentro, abre, executa e fecha — mesmo modelo do `AnakiDbDriver` do app.
class NativeDbService implements DbService {
  const NativeDbService({this.timeout = const Duration(seconds: 30)});

  final Duration timeout;

  @override
  Future<Map<String, Object?>> query(
    RemoteDbConnDescriptor conn,
    String sql, {
    int limit = 200,
    bool dml = false,
  }) async {
    try {
      return await Isolate.run(
        () => _runInIsolate(conn, sql, limit, dml),
      ).timeout(timeout);
    } on DbServiceException {
      rethrow;
    } on TimeoutException {
      throw DbServiceException(
        DbErrorKind.timeout,
        'Query exceeded ${timeout.inSeconds}s',
      );
    }
  }

  @override
  Future<Object?> redis(RemoteDbConnDescriptor conn, List<String> parts) async {
    if (parts.isEmpty) {
      throw const DbServiceException(DbErrorKind.queryFailed, 'Empty command.');
    }
    return _guardNoSql(
      () => Isolate.run(() async {
        final client = _redisClient(conn);
        await client.open();
        try {
          return _jsonable(await client.command(parts));
        } finally {
          await client.close();
        }
      }),
    );
  }

  @override
  Future<List<Object?>> redisMany(
    RemoteDbConnDescriptor conn,
    List<List<String>> commands,
  ) async {
    if (commands.isEmpty) return const [];
    for (final parts in commands) {
      if (parts.isEmpty) {
        throw const DbServiceException(
          DbErrorKind.queryFailed,
          'Empty command.',
        );
      }
    }
    final result = await _guardNoSql(
      () => Isolate.run(() async {
        final client = _redisClient(conn);
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

  @override
  Future<Object?> mongo(
    RemoteDbConnDescriptor conn,
    Map<String, Object?> command, {
    String? database,
  }) async {
    // A URI é a definitiva, com uma ressalva: quando o segredo mora no cofre
    // DESTE host (plano 62), o cliente manda a URL sem credencial e a senha
    // chega resolvida em `conn.password` — o construtor por URI do driver não
    // aceita credencial em parâmetro separado, então ela é injetada no
    // userinfo aqui. `extendedJsonCodec` OFF: replies mantêm
    // `{"$oid":…}`/`{"$date":…}` lossless (plano 53).
    final uri = _mongoUriWithPassword(conn);
    final target = (database != null && database.isNotEmpty)
        ? database
        : _mongoDatabase(conn);
    return _guardNoSql(
      () => Isolate.run(() async {
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

  /// URL do Mongo com [RemoteDbConnDescriptor.password] embutida no userinfo,
  /// quando houver. Espelha o `mongoUriFor` do cliente — inclusive em não
  /// mexer numa URL que já traz a senha. A string vive só dentro da chamada.
  static String _mongoUriWithPassword(RemoteDbConnDescriptor conn) {
    final password = conn.password;
    if (password == null || password.isEmpty) return conn.url;
    if (conn.url.isEmpty) return conn.url;
    final uri = Uri.parse(conn.url);
    if (uri.userInfo.contains(':')) return conn.url;
    final user = Uri.encodeComponent(
      uri.userInfo.isNotEmpty ? uri.userInfo : conn.user,
    );
    return uri
        .replace(userInfo: '$user:${Uri.encodeComponent(password)}')
        .toString();
  }

  /// Banco alvo do Mongo quando o cliente não fixou um: o da URL, senão o
  /// `authSource` (onde o usuário existe), senão `admin` (presente em qualquer
  /// deployment — mantém `ping`/`listDatabases`). Mesma regra do runner local.
  static String _mongoDatabase(RemoteDbConnDescriptor conn) {
    if (conn.database.isNotEmpty) return conn.database;
    final authSource = conn.url.isEmpty
        ? null
        : Uri.parse(conn.url).queryParameters['authSource'];
    return (authSource != null && authSource.isNotEmpty) ? authSource : 'admin';
  }

  static AnakiRedis _redisClient(RemoteDbConnDescriptor conn) => AnakiRedis(
    host: conn.host,
    port: conn.port ?? 6379,
    username: conn.user.isEmpty ? null : conn.user,
    password: conn.password,
    db: int.tryParse(conn.database) ?? 0,
    tls: conn.useTls,
  );

  /// Envelope de erro dos comandos NoSQL: reusa o timeout e a classificação
  /// por mensagem (o reply do anaki não tem tipo estável de conexão vs comando).
  Future<Object?> _guardNoSql(Future<Object?> Function() run) async {
    try {
      return await run().timeout(timeout);
    } on DbServiceException {
      rethrow;
    } on TimeoutException {
      throw DbServiceException(
        DbErrorKind.timeout,
        'Command exceeded ${timeout.inSeconds}s',
      );
    } on Object catch (e) {
      final msg = e.toString();
      final kind = msg.toLowerCase().contains('connect')
          ? DbErrorKind.connectionFailed
          : DbErrorKind.queryFailed;
      throw DbServiceException(kind, msg);
    }
  }

  /// Normaliza replies NoSQL pro fio: primitivos passam, ObjectId/DateTime/etc
  /// viram String, mapas/listas recursivos.
  static Object? _jsonable(Object? v) => switch (v) {
    null || int() || double() || bool() || String() => v,
    final Map m => {for (final e in m.entries) '${e.key}': _jsonable(e.value)},
    final List l => [for (final e in l) _jsonable(e)],
    _ => v.toString(),
  };

  static Future<Map<String, Object?>> _runInIsolate(
    RemoteDbConnDescriptor conn,
    String sql,
    int limit,
    bool dml,
  ) async {
    final watch = Stopwatch()..start();
    final driver = _buildDriver(conn);
    try {
      await driver.rawOpen();
    } on AnakiException catch (e) {
      throw DbServiceException(DbErrorKind.connectionFailed, '$e');
    }
    try {
      if (dml) {
        final affected = await driver.rawExecute(sql, null);
        return {
          'columns': const [],
          'rows': const [],
          'rowCount': 0,
          'truncated': false,
          'elapsedMs': watch.elapsedMilliseconds,
          'affectedRows': affected,
        };
      }
      final rows = await driver.rawQuery(sql, null);
      return _toResultJson(rows, limit, watch);
    } on ConnectionException catch (e) {
      throw DbServiceException(DbErrorKind.connectionFailed, '$e');
    } on AnakiException catch (e) {
      throw DbServiceException(DbErrorKind.queryFailed, '$e');
    } finally {
      try {
        await driver.rawClose();
      } on AnakiException {
        // fechar falhou após o resultado — nada útil a fazer.
      }
    }
  }

  static Map<String, Object?> _toResultJson(
    List<Map<String, dynamic>> rows,
    int limit,
    Stopwatch watch,
  ) {
    if (rows.isEmpty) {
      return {
        'columns': const [],
        'rows': const [],
        'rowCount': 0,
        'truncated': false,
        'elapsedMs': watch.elapsedMilliseconds,
      };
    }
    final columns = rows.first.keys.toList();
    final truncated = rows.length > limit;
    final data = [
      for (final row in truncated ? rows.take(limit) : rows)
        [for (final c in columns) _cell(row[c])],
    ];
    return {
      'columns': [
        for (final c in columns) {'name': c, 'type': ''},
      ],
      'rows': data,
      'rowCount': data.length,
      'truncated': truncated,
      'elapsedMs': watch.elapsedMilliseconds,
    };
  }

  /// Normaliza a célula pro JSON do fio (mesma política do DbResult do app:
  /// DateTime→ISO, blob→marcador de tamanho).
  static Object? _cell(Object? v) => switch (v) {
    null || int() || double() || bool() || String() => v,
    DateTime() => v.toIso8601String(),
    List<int>() => {'blob': v.length},
    _ => v.toString(),
  };

  static AnakiDriver _buildDriver(RemoteDbConnDescriptor conn) {
    final params = conn.url.isEmpty
        ? const <String, String>{}
        : Uri.parse(conn.url).queryParameters;
    switch (conn.engine) {
      case 'sqlite':
        return SqliteDriver(conn.sqlitePath);
      case 'postgres':
        return PostgresDriver(
          host: conn.host,
          port: conn.port ?? 5432,
          username: conn.user,
          password: conn.password ?? '',
          database: conn.database,
          sslMode: params['sslmode'],
        );
      case 'mysql':
        return MysqlDriver(
          host: conn.host,
          port: conn.port ?? 3306,
          username: conn.user,
          password: conn.password ?? '',
          database: conn.database,
          sslMode: params['ssl-mode']?.toLowerCase(),
        );
      case 'mssql':
        return MssqlDriver(
          host: conn.host,
          port: conn.port ?? 1433,
          username: conn.user,
          password: conn.password ?? '',
          database: conn.database,
          trustCert: params['trustcert'] == 'true',
          encrypt: switch (params['encrypt']) {
            'true' => true,
            'false' => false,
            _ => null,
          },
        );
      default:
        throw DbServiceException(
          DbErrorKind.unsupportedEngine,
          '${conn.engine} is not a supported SQL engine',
        );
    }
  }
}
