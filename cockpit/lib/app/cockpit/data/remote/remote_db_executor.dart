import 'dart:convert';

import 'package:cockpit/app/cockpit/data/db/db_connection_store_impl.dart';
import 'package:cockpit/app/cockpit/data/db/nosql_command_runner.dart';
import 'package:cockpit/app/cockpit/domain/contracts/nosql_runner.dart';
import 'package:cockpit/app/cockpit/domain/entities/db_connection.dart';
import 'package:cockpit/app/cockpit/domain/entities/db_result.dart';
import 'package:cockpit/app/cockpit/domain/services/db_query_service.dart';
import 'package:cockpit_core/cockpit_core.dart';
import 'package:cockpit_remote/cockpit_remote.dart';

/// Lê as conexões de DB de um workspace REMOTO: o `.cockpit/databases.json`
/// (+ `.local.json`) vive no host, lido via `fs.read` (plano 58, Wave 4).
/// SQLite auto-detectado fica de fora (o usuário registra explícito no host).
Future<List<DbConnection>> loadRemoteConnections(
  Future<RemoteFileService> Function() fileServiceProvider,
  String workspaceRoot,
) async {
  final fs = await fileServiceProvider();
  Future<List<DbConnection>> read(
    String name,
    DbConnectionOrigin origin,
  ) async {
    try {
      final bytes = await fs.read('$workspaceRoot/.cockpit/$name');
      return DbConnectionStoreImpl.parseDatabasesJson(
        utf8.decode(bytes, allowMalformed: true),
        origin,
      );
    } catch (_) {
      return const []; // arquivo ausente/ilegível → sem conexões.
    }
  }

  final registered = await read(
    'databases.json',
    DbConnectionOrigin.registered,
  );
  final local = await read('databases.local.json', DbConnectionOrigin.local);
  final byName = <String, DbConnection>{
    for (final c in registered) c.name: c,
    for (final c in local) c.name: c, // local sobrepõe registrado.
  };
  // Mesma ordem do caminho local (ver DbConnection.compareByName): o painel
  // não pode mudar de comportamento por o workspace ser remoto.
  return byName.values.toList()..sort(DbConnection.compareByName);
}

/// Constrói o [RemoteDbExecutor] que roda uma query SQL no host via o
/// `cockpit-server` (plano 58, Wave 4). [dbServiceProvider] resolve o serviço
/// remoto do host (conectando por SSH se preciso).
RemoteDbExecutor buildRemoteDbExecutor(
  Future<RemoteDbService> Function() dbServiceProvider,
) {
  return (
    DbConnection conn,
    String sql, {
    required int limit,
    required bool dml,
    String? password,
    required String workspaceRoot,
  }) async {
    final service = await dbServiceProvider();
    final Map<String, Object?> json;
    try {
      json = await service.query(
        _descriptor(conn, password, workspaceRoot),
        sql,
        limit: limit,
        dml: dml,
      );
    } on DbServiceException catch (e) {
      // Reidrata como o erro que a tab/CLI já conhece.
      throw _mapped(e);
    }
    return _fromJson(json);
  };
}

/// [NoSqlRunner] que roda Redis/Mongo no host via `cockpit-server` (plano 58,
/// Wave 4). Mesmo contrato do runner local — o `DbQueryService` troca só o
/// destino quando o workspace é remoto. [dbServiceProvider] resolve o serviço
/// do host (conecta por SSH se preciso).
NoSqlRunner buildRemoteNoSqlRunner(
  Future<RemoteDbService> Function() dbServiceProvider,
) => _RemoteNoSqlRunner(dbServiceProvider);

class _RemoteNoSqlRunner implements NoSqlRunner {
  _RemoteNoSqlRunner(this._provider);

  final Future<RemoteDbService> Function() _provider;

  @override
  Future<Object?> redis(
    DbConnection conn,
    List<String> parts, {
    String? password,
    String workspaceRoot = '',
  }) async {
    final service = await _provider();
    try {
      return await service.redis(
        _descriptor(conn, password, workspaceRoot),
        parts,
      );
    } on DbServiceException catch (e) {
      throw _mapped(e);
    }
  }

  @override
  Future<List<Object?>> redisMany(
    DbConnection conn,
    List<List<String>> commands, {
    String? password,
    String workspaceRoot = '',
  }) async {
    final service = await _provider();
    try {
      return await service.redisMany(
        _descriptor(conn, password, workspaceRoot),
        commands,
      );
    } on DbServiceException catch (e) {
      throw _mapped(e);
    }
  }

  @override
  Future<Object?> mongo(
    DbConnection conn,
    Map<String, dynamic> command, {
    String? password,
    String? database,
    String workspaceRoot = '',
  }) async {
    final service = await _provider();
    // Mongo conecta pela URI (Atlas/TLS/authSource). Sem segredo guardado, a
    // senha entra no userinfo aqui, igual ao runner local; COM segredo no host
    // (plano 62) a URL vai sem credencial e quem injeta é o servidor, que é o
    // único lado que conhece a senha.
    final url = NoSqlRunnerImpl.mongoUriFor(conn, password);
    final descriptor = RemoteDbConnDescriptor(
      engine: conn.engine.name,
      url: url,
      user: conn.user,
      database: conn.database,
      workspaceRoot: workspaceRoot,
      connName: conn.name,
      storedSecret: conn.savePassword,
      ssh: conn.ssh,
    );
    try {
      return await service.mongo(
        descriptor,
        command.cast<String, Object?>(),
        database: database,
      );
    } on DbServiceException catch (e) {
      throw _mapped(e);
    }
  }
}

RemoteDbConnDescriptor _descriptor(
  DbConnection conn,
  String? password,
  String workspaceRoot,
) => RemoteDbConnDescriptor(
  engine: conn.engine.name,
  url: conn.url,
  host: conn.host,
  port: conn.port,
  user: conn.user,
  database: conn.database,
  sqlitePath: conn.engine == DbEngine.sqlite ? conn.sqlitePath : '',
  password: password,
  useTls: conn.useTls, // Redis: `rediss://` liga TLS no host.
  // Chave do segredo no cofre do HOST (plano 62). Com `savePassword` ligado,
  // `password` acima vai null e é o servidor que resolve por estes dois campos.
  workspaceRoot: workspaceRoot,
  connName: conn.name,
  storedSecret: conn.savePassword,
  // Túnel SSH: vai no fio para o HOST abrir (onda 2). O cliente não tenta —
  // ele não alcança o bastion nem tem a chave privada de lá.
  ssh: conn.ssh,
);

/// Traduz o erro do serviço remoto pro `kind` que a tab e a CLI conhecem.
///
/// `e.kind.name` é camelCase (`connectionFailed`), mas todo o resto do app —
/// e a lista de kinds da CLI — fala snake_case (`connection_failed`). Sem a
/// tradução, erro de banco remoto caía sempre no kind genérico da CLI.
DbQueryException _mapped(DbServiceException e) {
  final kind = switch (e.kind) {
    DbErrorKind.connectionFailed => 'connection_failed',
    DbErrorKind.queryFailed => 'query_failed',
    DbErrorKind.timeout => 'timeout',
    DbErrorKind.unsupportedEngine => 'unsupported_engine',
    DbErrorKind.passwordRequired => 'password_required',
    DbErrorKind.sshTunnelFailed => 'ssh_tunnel_failed',
  };
  return DbQueryException(kind, e.detail ?? kind);
}

/// Reidrata o `DbResult` a partir do JSON do servidor. Células chegam
/// normalizadas (int/double/bool/string, ISO-date como string, blob como
/// `{blob: N}`); o grid exibe como está — só o blob vira marcador legível.
DbResult _fromJson(Map<String, Object?> json) {
  final cols = (json['columns'] as List? ?? const [])
      .cast<Map>()
      .map((c) => DbColumn(c['name'] as String, c['type'] as String? ?? ''))
      .toList();
  final rows = <List<Object?>>[
    for (final r in (json['rows'] as List? ?? const []).cast<List>())
      [for (final cell in r) _cell(cell)],
  ];
  return DbResult(
    columns: cols,
    rows: rows,
    elapsed: Duration(milliseconds: (json['elapsedMs'] as num?)?.toInt() ?? 0),
    truncated: json['truncated'] as bool? ?? false,
    affectedRows: (json['affectedRows'] as num?)?.toInt(),
  );
}

Object? _cell(Object? cell) {
  if (cell is Map && cell['blob'] is num) {
    return '[blob ${cell['blob']} bytes]';
  }
  return cell;
}
