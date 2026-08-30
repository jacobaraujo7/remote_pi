import 'package:cockpit_core/cockpit_core.dart';
import 'dart:io';

import 'package:cockpit/app/cockpit/domain/services/db_query_service.dart';
import 'package:cockpit/app/cockpit/domain/entities/redis_key.dart';
import 'package:cockpit/app/cockpit/domain/services/mongo_browse_service.dart';
import 'package:cockpit/app/cockpit/domain/services/redis_browse_service.dart';
import 'package:cockpit/app/cockpit/domain/contracts/db_connection_store.dart';
import 'package:cockpit/app/cockpit/domain/contracts/remote_db_writer.dart';
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
  DatabaseViewModel(
    this._store,
    this._secrets,
    this.service,
    this._sshKeys,
    this._hostKeys,
  );

  final DbConnectionStore _store;
  final DbSecrets _secrets;
  final SshKeyInspector _sshKeys;
  final SshHostKeyStore _hostKeys;

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
  ///
  /// Chave inclui o database escolhido: trocar de database no seletor precisa
  /// listar as collections do novo, não devolver as do anterior.
  final _collectionsCache = <String, List<String>>{};

  /// [database] lista as collections daquele database específico (o painel
  /// mostra todos os databases expansíveis); omitido, usa o database efetivo
  /// da conexão.
  Future<List<String>> collections(
    DbConnection conn, {
    String? database,
  }) async {
    final root = _workspaceRoot;
    final wsId = _workspaceId;
    if (root == null || wsId == null) return const [];
    final db = database ?? service.mongoDatabase(wsId, conn);
    final key = '${conn.name}@${db ?? ''}';
    final cached = _collectionsCache[key];
    if (cached != null) return cached;
    final svc = MongoBrowseService(service)
      ..target(workspaceRoot: root, workspaceId: wsId, connName: conn.name);
    final names = await svc.listCollections(database: database);
    _collectionsCache[key] = names;
    return names;
  }

  /// Database em uso pela conexão Mongo (URL, ou escolha salva). `null` = ainda
  /// não escolhido → o painel pede a escolha antes de listar collections.
  String? mongoDatabase(DbConnection conn) {
    final wsId = _workspaceId;
    return wsId == null ? null : service.mongoDatabase(wsId, conn);
  }

  /// `true` quando a URL não traz database e o seletor é necessário.
  bool mongoNeedsDatabase(DbConnection conn) =>
      service.mongoNeedsDatabase(conn);

  /// Databases disponíveis no deployment (para o seletor).
  Future<List<String>> mongoDatabases(DbConnection conn) async {
    final root = _workspaceRoot;
    final wsId = _workspaceId;
    if (root == null || wsId == null) return const [];
    final svc = MongoBrowseService(service)
      ..target(workspaceRoot: root, workspaceId: wsId, connName: conn.name);
    return svc.listDatabases();
  }

  /// Fixa o database da conexão e invalida as collections cacheadas.
  Future<void> selectMongoDatabase(DbConnection conn, String database) async {
    final wsId = _workspaceId;
    if (wsId == null) return;
    await service.selectMongoDatabase(wsId, conn.name, database);
    _collectionsCache.removeWhere((k, _) => k.startsWith('${conn.name}@'));
    if (!_disposed) notifyListeners();
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

  /// Loader remoto de conexões (plano 58, Wave 4): quando setado e devolve
  /// não-nulo pro workspace ativo, substitui a leitura local — o
  /// `.cockpit/databases.json` de um workspace remoto vive no host. O app o
  /// seta; workspaces locais devolvem `null`.
  Future<List<DbConnection>>? Function(String workspaceId, String root)?
  remoteConnectionsFor;

  /// Escrita da config de banco quando o workspace é REMOTO (plano 62).
  /// `null` = workspace local, e vale o `_store` + cofre desta máquina.
  /// Plugado pela página, junto do [remoteConnectionsFor].
  RemoteDbWriter? Function(String workspaceId)? remoteDbWriterFor;

  /// O workspace ativo é remoto? A UI usa para dizer ONDE a senha vai parar —
  /// as garantias diferem (arquivo protegido no host vs cofre do SO daqui) e
  /// quem digita tem o direito de saber.
  bool get isRemoteWorkspace =>
      remoteDbWriterFor?.call(_workspaceId ?? '') != null;

  Future<void> reload() async {
    final root = _workspaceRoot;
    if (root == null) return;
    final remote = remoteConnectionsFor?.call(_workspaceId ?? '', root);
    final loaded = await (remote ?? _store.load(root));
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
    String? sshPassphrase,
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

    // Workspace remoto: definição e segredo vão pro HOST (plano 62). Sem este
    // ramo, o `_store.save` abaixo tentava criar a raiz do host no disco do
    // cliente e estourava — salvar conexão remota era simplesmente impossível.
    final remote = remoteDbWriterFor?.call(wsId);
    if (remote != null) {
      await remote.saveConnections(root, [...registered, conn]);
      await _syncRemoteSecret(
        remote,
        root,
        conn,
        password,
        previousName: previousName,
        wsId: wsId,
      );
      service.forgetPassword(root, previousName ?? conn.name);
      service.forgetPassword(root, conn.name);
      // Passphrase da chave SSH também vai pro cofre do HOST (onda 2): quem
      // abre o bastion é ele, com a chave privada de lá.
      await _syncRemoteSshPassphrase(
        remote,
        root,
        conn,
        sshPassphrase,
        wsId: wsId,
        previousName: previousName,
      );
      await reload();
      return;
    }

    await _store.save(root, [...registered, conn]);

    final oldKey = DbQueryService.secretKey(root, previousName ?? conn.name);
    final newKey = DbQueryService.secretKey(root, conn.name);
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
    // A senha mudou/migrou de chave: invalida o cache de sessão pra próxima
    // query reler o valor atual (evita usar a senha antiga após uma edição).
    if (previousName != null) service.forgetPassword(root, previousName);
    service.forgetPassword(root, conn.name);
    await _syncSshPassphrase(
      conn,
      root,
      wsId,
      sshPassphrase,
      previousName: previousName,
    );
    await reload();
  }

  Future<void> remove(DbConnection conn) async {
    final root = _workspaceRoot;
    final wsId = _workspaceId;
    if (root == null || wsId == null) return;
    final registered = [
      ..._connections.where(
        (c) => c.origin == DbConnectionOrigin.registered && c.name != conn.name,
      ),
    ];
    final remote = remoteDbWriterFor?.call(wsId);
    if (remote != null) {
      await remote.saveConnections(root, registered);
      await remote.deleteSecret(root, conn.name);
      // O cofre LOCAL pode ainda ter a senha legada desta conexão (cadastrada
      // antes do plano 62): apagar aqui evita deixar segredo órfão de uma
      // conexão que não existe mais.
      await _secrets.delete(DbQueryService.secretKey(root, conn.name));
      await _secrets.delete(DbQueryService.sshSecretKey(root, conn.name));
      service.forgetPassword(root, conn.name);
      service.forgetSshPassphrase(root, conn.name);
      await reload();
      return;
    }
    await _store.save(root, registered);
    await _secrets.delete(DbQueryService.secretKey(root, conn.name));
    await _secrets.delete(DbQueryService.sshSecretKey(root, conn.name));
    service.forgetSshPassphrase(root, conn.name);
    service.forgetPassword(root, conn.name);
    // A host key confiada some junto: manter o fingerprint de um bastion que
    // ninguém mais usa só acumula lixo com aparência de decisão de segurança.
    final endpoint = conn.ssh?.endpoint;
    if (endpoint != null) await _hostKeys.forget(endpoint);
    await reload();
  }

  /// Senha de uma conexão REMOTA: espelha a regra do caminho local (rename
  /// migra, desligar o switch apaga, campo vazio mantém), só que o destino é o
  /// cofre do host.
  ///
  /// Faz também a **migração** de quem cadastrou a conexão antes do plano 62: a
  /// senha ficou no cofre desta máquina, sob a chave derivada do `workspaceId`
  /// local. Se o usuário não digitou senha nova mas há uma legada aqui, ela é
  /// empurrada pro host e apagada daqui — a conexão volta a funcionar sem
  /// ninguém redigitar nada, e de qualquer cliente. Quem nunca editar a
  /// conexão recebe `password_required` na primeira query, que é uma mensagem
  /// dizendo exatamente o que fazer.
  Future<void> _syncRemoteSecret(
    RemoteDbWriter remote,
    String root,
    DbConnection conn,
    String? password, {
    required String wsId,
    String? previousName,
  }) async {
    final legacyKey = DbQueryService.secretKey(root, previousName ?? conn.name);

    // Renome: MOVE a chave no host em vez de apagar e torcer. Apagar antes de
    // saber se dá para regravar perdia a senha sempre que o usuário só mudava
    // o nome — e, sem leitura de volta, não havia como reconstruí-la daqui.
    if (previousName != null && previousName != conn.name) {
      await remote.renameSecret(root, previousName, conn.name);
    }
    if (!conn.savePassword) {
      await remote.deleteSecret(root, conn.name);
      await _secrets.delete(legacyKey);
      return;
    }
    if (password != null && password.isNotEmpty) {
      await remote.setSecret(root, conn.name, password);
      await _secrets.delete(legacyKey);
      return;
    }
    // Sem senha digitada: o renome acima já moveu o que havia no host, então
    // aqui só resta a MIGRAÇÃO de quem ainda tinha a senha no cofre desta
    // máquina (cadastro anterior ao cofre único).
    final legacy = await _secrets.read(legacyKey);
    if (legacy != null && legacy.isNotEmpty) {
      await remote.setSecret(root, conn.name, legacy);
      await _secrets.delete(legacyKey);
    }
  }

  /// Passphrase da chave SSH de uma conexão REMOTA: mesma regra da senha —
  /// desligar o switch apaga, campo vazio mantém, e o que ficou no cofre desta
  /// máquina migra.
  Future<void> _syncRemoteSshPassphrase(
    RemoteDbWriter remote,
    String root,
    DbConnection conn,
    String? passphrase, {
    required String wsId,
    String? previousName,
  }) async {
    final save = conn.ssh?.savePassphrase ?? false;
    if (!save) {
      await remote.setSshPassphrase(root, conn.name, null);
      return;
    }
    if (passphrase != null && passphrase.isNotEmpty) {
      await remote.setSshPassphrase(root, conn.name, passphrase);
      await _secrets.delete(
        DbQueryService.sshSecretKey(root, previousName ?? conn.name),
      );
      return;
    }
    final legacy = await _secrets.read(
      DbQueryService.sshSecretKey(root, previousName ?? conn.name),
      legacyKey: DbQueryService.legacySshSecretKey(wsId, previousName ?? conn.name),
    );
    if (legacy != null && legacy.isNotEmpty) {
      await remote.setSshPassphrase(root, conn.name, legacy);
    }
  }

  /// Espelha a regra da senha de banco pra passphrase da chave SSH: rename
  /// migra o segredo, desligar o switch apaga, e campo vazio mantém o atual.
  Future<void> _syncSshPassphrase(
    DbConnection conn,
    String root,
    String wsId,
    String? passphrase, {
    String? previousName,
  }) async {
    final oldKey = DbQueryService.sshSecretKey(root, previousName ?? conn.name);
    final newKey = DbQueryService.sshSecretKey(root, conn.name);
    final save = conn.ssh?.savePassphrase ?? false;
    if (previousName != null && previousName != conn.name) {
      final existing = await _secrets.read(
        oldKey,
        legacyKey: DbQueryService.legacySshSecretKey(wsId, previousName),
      );
      if (save &&
          existing != null &&
          (passphrase == null || passphrase.isEmpty)) {
        await _secrets.write(newKey, existing);
      }
      await _secrets.delete(oldKey);
      service.forgetSshPassphrase(root, previousName);
    }
    if (!save) {
      await _secrets.delete(newKey);
    } else if (passphrase != null && passphrase.isNotEmpty) {
      await _secrets.write(newKey, passphrase);
    }
    // Config mudou (chave nova, host novo): a passphrase de sessão pode não
    // valer mais.
    service.forgetSshPassphrase(root, conn.name);
  }

  /// Repassa a classificação de chave pro dialog — a UI não fala com `data/`.
  Future<bool> sshKeyNeedsPassphrase(String keyPath) =>
      _sshKeys.needsPassphrase(keyPath);

  /// Sugestão de chave padrão pro dialog (`~/.ssh/id_ed25519`…).
  Future<String?> defaultSshKeyPath() => _sshKeys.defaultKeyPath();

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
    String? sshPassphrase,
    String? storedPasswordName,
  }) async {
    final wsId = _workspaceId;
    final root = _workspaceRoot;
    if (wsId == null || root == null) return 'No workspace is open.';
    var effective = (password == null || password.isEmpty) ? null : password;
    if (effective == null && storedPasswordName != null) {
      effective = await _secrets.read(
        DbQueryService.secretKey(root, storedPasswordName),
        legacyKey: DbQueryService.legacySecretKey(wsId, storedPasswordName),
      );
    }
    effective ??= conn.urlPassword;
    var target = conn;
    if (conn.engine == DbEngine.sqlite) {
      final p = conn.sqlitePath;
      final absolute =
          p.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(p);
      if (!absolute) target = conn.copyWith(url: 'sqlite:$root/$p');
    }
    try {
      // Delegado ao serviço (e não ao driver direto) porque testar precisa
      // exercitar o MESMO caminho da execução real — inclusive o túnel SSH.
      // Testar por fora do túnel validava um host que a query nunca usaria.
      await service.ping(
        target,
        workspaceId: wsId,
        workspaceRoot: root,
        password: effective,
        sshPassphrase: sshPassphrase,
      );
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
