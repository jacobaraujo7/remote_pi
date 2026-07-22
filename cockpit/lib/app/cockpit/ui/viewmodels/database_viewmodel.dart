import 'dart:io';

import 'package:cockpit/app/cockpit/domain/services/db_query_service.dart';
import 'package:cockpit/app/cockpit/domain/entities/redis_key.dart';
import 'package:cockpit/app/cockpit/domain/services/mongo_browse_service.dart';
import 'package:cockpit/app/cockpit/domain/services/redis_browse_service.dart';
import 'package:cockpit/app/cockpit/domain/contracts/db_connection_store.dart';
import 'package:cockpit/app/cockpit/domain/contracts/db_driver.dart';
import 'package:cockpit/app/cockpit/domain/entities/db_connection.dart';
import 'package:cockpit/app/cockpit/domain/entities/db_result.dart';
import 'package:flutter/foundation.dart';

/// Uma coluna de tabela na árvore de schema do painel.
class SchemaColumn {
  const SchemaColumn(this.name, this.type, {this.primaryKey = false});
  final String name;
  final String type;
  final bool primaryKey;
}

/// Uma tabela (ou view) na árvore de schema. [schema] é o namespace do engine
/// (`public`/`dbo`/database) — nulo em SQLite, que não tem schemas. A UI
/// agrupa por [schema] quando há mais de um distinto.
class SchemaTable {
  const SchemaTable(this.name, {this.schema, this.isView = false});
  final String name;
  final String? schema;
  final bool isView;
}

/// Estado de VISUALIZAÇÃO de uma tab `.dbq` que precisa sobreviver ao
/// re-mount do widget (mover a tab pra outra pane destrói o State — mesma
/// razão do Terminal viver na session). Mutável; o widget lê/escreve direto.
class DbTabViewState {
  DbResult? result;
  DbQueryException? error;
  double split = 0.5;
  List<double> baseWidths = const [];
  List<double>? manualWidths;
  int? selectedRow;

  /// Resultado exibido como JSON (selecionável/copiável) em vez de tabela.
  /// Só estado de view — não vai pro frontmatter do `.dbq`.
  bool asJson = false;
}

/// Estado de VISUALIZAÇÃO de uma tab **Redis** (plano 52) — side-car pelo
/// mesmo motivo do [DbTabViewState]: sobreviver ao re-mount do widget. O
/// [service] é por-tab (guarda a conexão alvo — duas tabs Redis de conexões
/// diferentes não podem dividir um serviço com alvo mutável).
class RedisTabState {
  RedisTabState(this.service);

  final RedisBrowseService service;

  String pattern = '';
  List<RedisKeyEntry> entries = [];
  String cursor = '0';

  /// `true` após o primeiro scan bem-sucedido (evita re-scan a cada re-mount).
  bool loaded = false;

  String? error;
}

/// Estado de VISUALIZAÇÃO de uma tab **Mongo** (plano 53) — side-car pelo
/// mesmo motivo dos irmãos: sobreviver ao re-mount. [service] por-tab (alvo
/// mutável, ver [RedisTabState]).
class MongoTabState {
  MongoTabState(this.service);

  final MongoBrowseService service;

  String filter = '';
  List<Map<String, dynamic>> docs = [];

  /// `true` quando a última página veio cheia (provável haver mais).
  bool hasMore = false;

  bool loaded = false;
  String? error;
}

/// Estado do painel Database + serviço de execução pras tabs `.dbq` (plano
/// 51). Page-scoped (provido no `cockpit_module`); o workspace ativo entra
/// via [setWorkspace] (chamado pelo painel quando o projeto muda).
class DatabaseViewModel extends ChangeNotifier {
  DatabaseViewModel(this._store, this._secrets, this._registry, this.service);

  final DbConnectionStore _store;
  final DbSecrets _secrets;
  final DbDriverRegistry _registry;

  /// Motor compartilhado tab/CLI — exposto pras tabs `.dbq` executarem.
  final DbQueryService service;

  String? _workspaceId;
  String? _workspaceRoot;
  List<DbConnection> _connections = const [];
  bool _disposed = false;

  List<DbConnection> get connections => _connections;
  String? get workspaceRoot => _workspaceRoot;

  /// Side-car de estado de view por tab `.dbq` (chave = session id). Cap
  /// simples por inserção — tab fechada some do mapa quando ele gira.
  final _tabStates = <String, DbTabViewState>{};
  static const _maxTabStates = 24;

  DbTabViewState tabStateFor(String sessionId) {
    final existing = _tabStates.remove(sessionId);
    if (existing != null) {
      _tabStates[sessionId] = existing; // re-insere no fim (LRU barato)
      return existing;
    }
    final fresh = DbTabViewState();
    _tabStates[sessionId] = fresh;
    if (_tabStates.length > _maxTabStates) {
      _tabStates.remove(_tabStates.keys.first);
    }
    return fresh;
  }

  /// Side-car das tabs Redis (plano 52), mesmo esquema LRU das `.dbq`.
  final _redisStates = <String, RedisTabState>{};

  RedisTabState redisStateFor(String sessionId) {
    final existing = _redisStates.remove(sessionId);
    if (existing != null) {
      _redisStates[sessionId] = existing;
      return existing;
    }
    final fresh = RedisTabState(RedisBrowseService(service));
    _redisStates[sessionId] = fresh;
    if (_redisStates.length > _maxTabStates) {
      _redisStates.remove(_redisStates.keys.first);
    }
    return fresh;
  }

  /// Side-car das tabs Mongo (plano 53), mesmo esquema LRU.
  final _mongoStates = <String, MongoTabState>{};

  MongoTabState mongoStateFor(String sessionId) {
    final existing = _mongoStates.remove(sessionId);
    if (existing != null) {
      _mongoStates[sessionId] = existing;
      return existing;
    }
    final fresh = MongoTabState(MongoBrowseService(service));
    _mongoStates[sessionId] = fresh;
    if (_mongoStates.length > _maxTabStates) {
      _mongoStates.remove(_mongoStates.keys.first);
    }
    return fresh;
  }

  /// Collections de uma conexão Mongo (lazy, cacheada até [reload] — análogo
  /// do [tables] SQL). O painel chama ao expandir.
  final _collectionsCache = <String, List<String>>{};

  Future<List<String>> collections(DbConnection conn) async {
    final cached = _collectionsCache[conn.name];
    if (cached != null) return cached;
    final root = _workspaceRoot;
    final wsId = _workspaceId;
    if (root == null || wsId == null) return const [];
    final svc = MongoBrowseService(service)
      ..target(workspaceRoot: root, workspaceId: wsId, connName: conn.name);
    final names = await svc.listCollections();
    _collectionsCache[conn.name] = names;
    return names;
  }

  /// Aponta pro workspace ativo; recarrega quando muda (ou em [force]).
  Future<void> setWorkspace(String id, String root, {bool force = false}) {
    if (!force && id == _workspaceId && root == _workspaceRoot) {
      return Future.value();
    }
    _workspaceId = id;
    _workspaceRoot = root;
    return reload();
  }

  Future<void> reload() async {
    final root = _workspaceRoot;
    if (root == null) return;
    final loaded = await _store.load(root);
    if (_disposed || root != _workspaceRoot) return;
    _connections = loaded;
    _tablesCache.clear();
    _columnsCache.clear();
    _collectionsCache.clear();
    notifyListeners();
  }

  /// Cria/atualiza uma conexão registrada. [previousName] identifica a antiga
  /// num rename; [password] só é gravado no cofre quando `savePassword` (e
  /// removido quando o flag desliga). Editar uma "detected" a promove a
  /// registrada.
  Future<void> upsert(
    DbConnection conn, {
    String? password,
    String? previousName,
  }) async {
    final root = _workspaceRoot;
    final wsId = _workspaceId;
    if (root == null || wsId == null) return;

    final registered = _connections
        .where(
          (c) =>
              c.origin == DbConnectionOrigin.registered &&
              c.name != (previousName ?? conn.name),
        )
        .toList();
    await _store.save(root, [...registered, conn]);

    final oldKey = DbQueryService.secretKey(wsId, previousName ?? conn.name);
    final newKey = DbQueryService.secretKey(wsId, conn.name);
    if (previousName != null && previousName != conn.name) {
      // Rename: migra a senha guardada pra chave nova antes de apagar a velha
      // — editar sem redigitar a senha NUNCA a perde.
      final existing = await _secrets.read(oldKey);
      if (conn.savePassword &&
          existing != null &&
          (password == null || password.isEmpty)) {
        await _secrets.write(newKey, existing);
      }
      await _secrets.delete(oldKey);
    }
    if (!conn.savePassword) {
      await _secrets.delete(newKey);
    } else if (password != null && password.isNotEmpty) {
      // Só sobrescreve quando o usuário digitou algo; vazio = mantém a atual.
      await _secrets.write(newKey, password);
    }
    await reload();
  }

  Future<void> remove(DbConnection conn) async {
    final root = _workspaceRoot;
    final wsId = _workspaceId;
    if (root == null || wsId == null) return;
    await _store.save(root, [
      ..._connections.where(
        (c) => c.origin == DbConnectionOrigin.registered && c.name != conn.name,
      ),
    ]);
    await _secrets.delete(DbQueryService.secretKey(wsId, conn.name));
    await reload();
  }

  /// Tabelas de uma conexão (introspecção normalizada, lazy — a árvore do
  /// painel chama ao expandir). Cacheado por nome de conexão até [reload].
  final _tablesCache = <String, List<SchemaTable>>{};
  final _columnsCache = <String, List<SchemaColumn>>{};

  Future<List<SchemaTable>> tables(DbConnection conn) async {
    final cached = _tablesCache[conn.name];
    if (cached != null) return cached;
    final root = _workspaceRoot;
    final wsId = _workspaceId;
    if (root == null || wsId == null) return const [];
    final rs = await service.schema(
      workspaceRoot: root,
      workspaceId: wsId,
      connName: conn.name,
    );
    // A 1ª coluna do schema() é o nome ('table').
    final ix = {
      for (var i = 0; i < rs.columns.length; i++) rs.columns[i].name: i,
    };
    final iTable = ix['table'] ?? 0;
    final iSchema = ix['schema'];
    final iType = ix['type'];
    final result = [
      for (final row in rs.rows)
        SchemaTable(
          '${row[iTable]}',
          schema: iSchema == null || row[iSchema] == null
              ? null
              : '${row[iSchema]}',
          isView: iType != null && '${row[iType]}' == 'view',
        ),
    ];
    _tablesCache[conn.name] = result;
    return result;
  }

  Future<List<SchemaColumn>> columns(
    DbConnection conn,
    String table, {
    String? schema,
  }) async {
    final key = '${conn.name} ${schema ?? ''} $table';
    final cached = _columnsCache[key];
    if (cached != null) return cached;
    final root = _workspaceRoot;
    final wsId = _workspaceId;
    if (root == null || wsId == null) return const [];
    final rs = await service.schema(
      workspaceRoot: root,
      workspaceId: wsId,
      connName: conn.name,
      table: table,
      schema: schema,
    );
    final ix = {
      for (var i = 0; i < rs.columns.length; i++) rs.columns[i].name: i,
    };
    final cols = [
      for (final row in rs.rows)
        SchemaColumn(
          '${row[ix['column'] ?? 0]}',
          '${row[ix['type'] ?? 1]}',
          primaryKey: '${row[ix['primaryKey'] ?? -1]}' == '1',
        ),
    ];
    _columnsCache[key] = cols;
    return cols;
  }

  /// Cita um identificador na sintaxe do engine — tabela CamelCase (ex.
  /// nopCommerce no Postgres) quebra sem aspas, porque o servidor normaliza
  /// identificador não-citado pra minúsculo. Citar é inócuo pros demais.
  static String quoteIdent(DbEngine engine, String ident) => switch (engine) {
    DbEngine.mysql => '`${ident.replaceAll('`', '``')}`',
    DbEngine.mssql => '[${ident.replaceAll(']', ']]')}]',
    _ => '"${ident.replaceAll('"', '""')}"',
  };

  /// Nome de tabela citado, prefixado pelo [schema] quando houver — tabela num
  /// schema não-default (Postgres/MSSQL) só resolve qualificada.
  static String qualifiedIdent(DbEngine engine, String? schema, String table) =>
      schema == null || schema.isEmpty
      ? quoteIdent(engine, table)
      : '${quoteIdent(engine, schema)}.${quoteIdent(engine, table)}';

  /// Cria um `.dbq` já apontado pra [conn] na raiz do workspace e devolve o
  /// caminho absoluto (o painel abre via CockpitViewModel). [table] preenche
  /// `SELECT * FROM <table>` e nomeia o arquivo pela tabela. Escolhe um nome
  /// livre `<base>-query[-N].dbq`.
  Future<String?> createDbq(DbConnection conn, {String? table}) async {
    final root = _workspaceRoot;
    if (root == null) return null;
    final rawBase = table ?? conn.name;
    final base = rawBase.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    var path = '$root/$base-query.dbq';
    for (var n = 2; File(path).existsSync(); n++) {
      path = '$root/$base-query-$n.dbq';
    }
    final sql = table == null
        ? 'SELECT 1;'
        : 'SELECT * FROM ${quoteIdent(conn.engine, table)} LIMIT 100;';
    await File(path).writeAsString('-- db: ${conn.name}\n$sql\n');
    return path;
  }

  /// Testa uma conexão (inclusive não-salva, do dialog). `null` = OK; senão a
  /// mensagem de erro user-facing.
  ///
  /// [password] é a digitada no dialog; vazia/nula, o teste cai pra senha já
  /// guardada no cofre sob [storedPasswordName] (o nome ORIGINAL da conexão em
  /// edição — a chave do cofre não muda até salvar um rename) e, por último,
  /// pra senha embutida na URL — mesma cadeia da execução real.
  Future<String?> test(
    DbConnection conn, {
    String? password,
    String? storedPasswordName,
  }) async {
    final driver = _registry.forEngine(conn.engine);
    if (driver == null) {
      return '${conn.engine.label} support arrives with the anakiORM '
          'integration.';
    }
    var effective = (password == null || password.isEmpty) ? null : password;
    final wsId = _workspaceId;
    if (effective == null && storedPasswordName != null && wsId != null) {
      effective = await _secrets.read(
        DbQueryService.secretKey(wsId, storedPasswordName),
      );
    }
    effective ??= conn.urlPassword;
    var target = conn;
    final root = _workspaceRoot;
    if (conn.engine == DbEngine.sqlite && root != null) {
      final p = conn.sqlitePath;
      final absolute =
          p.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(p);
      if (!absolute) target = conn.copyWith(url: 'sqlite:$root/$p');
    }
    try {
      await driver.query(target, 'SELECT 1', limit: 1, password: effective);
      return null;
    } on DbQueryException catch (e) {
      return e.message;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
