import 'package:cockpit/app/cockpit/domain/entities/db_connection.dart';
import 'package:cockpit/app/cockpit/domain/entities/db_result.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/database_viewmodel.dart';
import 'package:cockpit/app/cockpit/ui/widgets/confirm_dialog.dart';
import 'package:cockpit/app/cockpit/ui/widgets/db_connection_dialog.dart';
import 'package:cockpit/app/cockpit/ui/widgets/db_engine_icon.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/app_menu.dart';
import 'package:cockpit/app/core/ui/widgets/app_tooltip.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Corpo da aba **Database** do painel direito (plano 51, decisão E): conexões
/// do workspace — registradas (`.cockpit/databases.json`), locais e sqlites
/// detectados. "+" abre o popup de engine → dialog; clicar numa conexão edita
/// (o mesmo dialog).
class DbPanel extends StatefulWidget {
  const DbPanel({
    super.key,
    required this.workspaceId,
    required this.workspaceRoot,
  });

  final String workspaceId;
  final String workspaceRoot;

  @override
  State<DbPanel> createState() => _DbPanelState();
}

class _DbPanelState extends State<DbPanel> {
  @override
  void initState() {
    super.initState();
    _syncWorkspace();
  }

  @override
  void didUpdateWidget(DbPanel old) {
    super.didUpdateWidget(old);
    if (old.workspaceId != widget.workspaceId ||
        old.workspaceRoot != widget.workspaceRoot) {
      _syncWorkspace();
    }
  }

  void _syncWorkspace() {
    // Fora do build: setWorkspace notifica listeners ao terminar o load.
    final vm = context.read<DatabaseViewModel>();
    Future.microtask(
      () => vm.setWorkspace(
        widget.workspaceId,
        widget.workspaceRoot,
        force: true,
      ),
    );
  }

  Future<void> _add(BuildContext anchor) async {
    final vm = context.read<DatabaseViewModel>();
    final engine = await showAppMenu<DbEngine>(
      anchor,
      items: [
        for (final e in DbEngine.values)
          AppMenuItem(
            value: e,
            label: e.label,
            leading: DbEngineIcon(e, size: 15),
          ),
      ],
    );
    if (engine == null || !mounted) return;
    final result = await showDialog<DbConnectionDialogResult>(
      context: context,
      builder: (context) => DbConnectionDialog(engine: engine, viewModel: vm),
    );
    if (result?.connection == null) return;
    await vm.upsert(result!.connection!, password: result.password);
  }

  /// Conexões expandidas (schema visível). Estado local do painel.
  final _expanded = <String>{};

  void _toggle(String name) => setState(() {
    if (!_expanded.remove(name)) _expanded.add(name);
  });

  /// Menu de contexto de uma conexão: Edit · New .dbq · Delete (confirmado).
  Future<void> _contextMenu(BuildContext anchor, DbConnection conn) async {
    final action = await showAppMenu<String>(
      anchor,
      items: [
        const AppMenuItem(value: 'edit', label: 'Edit…', icon: Icons.edit),
        // "New query" só faz sentido pros SQL (abre tab `.dbq`). Redis abre a
        // tabela de chaves (plano 52); Mongo segue CLI-only.
        if (conn.engine.isSql)
          const AppMenuItem(value: 'dbq', label: 'New query', icon: Icons.add),
        if (conn.engine == DbEngine.redis)
          const AppMenuItem(
            value: 'redis',
            label: 'Browse keys',
            icon: Icons.grid_on_outlined,
          ),
        const AppMenuItem.divider(),
        const AppMenuItem(
          value: 'delete',
          label: 'Delete',
          icon: Icons.delete_outline,
          danger: true,
        ),
      ],
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'edit':
        await _edit(conn);
      case 'dbq':
        _newDbq(conn);
      case 'redis':
        context.read<CockpitViewModel>().openRedisBrowser(conn.name);
      case 'delete':
        await _delete(conn);
    }
  }

  Future<void> _edit(DbConnection conn) async {
    final vm = context.read<DatabaseViewModel>();
    final result = await showDialog<DbConnectionDialogResult>(
      context: context,
      builder: (context) =>
          DbConnectionDialog(engine: conn.engine, viewModel: vm, initial: conn),
    );
    if (result == null) return;
    if (result.deleted) {
      if (conn.origin == DbConnectionOrigin.registered) await vm.remove(conn);
      return;
    }
    if (result.connection != null) {
      // Editar uma "detected"/"local" salva como registrada (promoção).
      await vm.upsert(
        result.connection!,
        password: result.password,
        previousName: conn.name,
      );
    }
  }

  void _newDbq(DbConnection conn, {SchemaTable? table}) {
    // Untitled (VSCode-style): abre um buffer scratch — o arquivo só nasce no
    // primeiro save. Tabela → já preenche o SELECT (qualificada por schema).
    context.read<CockpitViewModel>().openScratchDbq(
      connName: conn.name,
      sql: table == null
          ? null
          : 'SELECT * FROM '
                '${DatabaseViewModel.qualifiedIdent(conn.engine, table.schema, table.name)} '
                'LIMIT 100;',
    );
  }

  Future<void> _delete(DbConnection conn) async {
    if (conn.origin != DbConnectionOrigin.registered) {
      // detected/local não moram no databases.json → nada a excluir.
      return;
    }
    final ok = await showConfirmDialog(
      context,
      title: 'Delete connection',
      message:
          'Remove "${conn.name}" from this workspace? '
          'Any saved password is discarded. .dbq files that reference it '
          'are not touched.',
      confirmLabel: 'Delete',
      danger: true,
    );
    if (!ok || !mounted) return;
    await context.read<DatabaseViewModel>().remove(conn);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    final vm = context.watch<DatabaseViewModel>();
    final conns = vm.connections;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 4),
          child: Row(
            children: [
              Text(
                'DATABASE',
                style: typo.label.copyWith(
                  fontSize: 10,
                  letterSpacing: 1.1,
                  color: colors.text3,
                ),
              ),
              const Spacer(),
              HoverTap(
                onTap: () => context.read<DatabaseViewModel>().reload(),
                padding: const EdgeInsets.all(3),
                child: Icon(Icons.refresh, size: 14, color: colors.text3),
              ),
              const SizedBox(width: 2),
              Builder(
                builder: (anchor) => HoverTap(
                  onTap: () => _add(anchor),
                  padding: const EdgeInsets.all(3),
                  child: Icon(Icons.add, size: 14, color: colors.text3),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: conns.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No connections yet.',
                    style: typo.label.copyWith(
                      fontSize: 11.5,
                      color: colors.text3,
                      height: 1.5,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  itemCount: conns.length,
                  itemBuilder: (context, i) => _ConnectionTile(
                    conn: conns[i],
                    expanded: _expanded.contains(conns[i].name),
                    onToggle: () => _toggle(conns[i].name),
                    onContextMenu: _contextMenu,
                    onNewQuery: (table) => _newDbq(conns[i], table: table),
                  ),
                ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colors.border)),
          ),
          child: Text(
            '.cockpit/databases.json · ${conns.length} '
            'connection${conns.length == 1 ? '' : 's'}',
            style: typo.label.copyWith(fontSize: 10.5, color: colors.text4),
          ),
        ),
      ],
    );
  }
}

/// Linha da conexão + (quando expandida) a árvore de schema lazy embaixo.
class _ConnectionTile extends StatelessWidget {
  const _ConnectionTile({
    required this.conn,
    required this.expanded,
    required this.onToggle,
    required this.onContextMenu,
    required this.onNewQuery,
  });

  final DbConnection conn;
  final bool expanded;
  final VoidCallback onToggle;
  final Future<void> Function(BuildContext anchor, DbConnection conn)
  onContextMenu;

  /// Cria um "New query" com SELECT * FROM <table>.
  final void Function(SchemaTable table) onNewQuery;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    // SQL expande a árvore de schema; Mongo expande as collections (plano
    // 53); Redis abre a tabela de chaves direto (plano 52).
    final browsable = conn.engine.isSql;
    final isRedis = conn.engine == DbEngine.redis;
    final isMongo = conn.engine == DbEngine.mongo;
    final expandable = browsable || isMongo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: HoverTap(
            onTap: expandable
                ? onToggle
                : isRedis
                ? () => context.read<CockpitViewModel>().openRedisBrowser(
                    conn.name,
                  )
                : null,
            padding: const EdgeInsets.fromLTRB(4, 5, 6, 5),
            child: Row(
              children: [
                Icon(
                  expandable
                      ? (expanded ? Icons.expand_more : Icons.chevron_right)
                      : Icons.circle,
                  size: expandable ? 15 : 5,
                  color: colors.text4,
                ),
                SizedBox(width: expandable ? 2 : 7),
                DbEngineIcon(conn.engine, size: 13),
                const SizedBox(width: 7),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              conn.name,
                              overflow: TextOverflow.ellipsis,
                              style: typo.body.copyWith(
                                fontSize: 12.5,
                                color: colors.text2,
                              ),
                            ),
                          ),
                          if (conn.origin == DbConnectionOrigin.detected) ...[
                            const SizedBox(width: 6),
                            const _Chip('detected'),
                          ],
                          if (conn.origin == DbConnectionOrigin.local) ...[
                            const SizedBox(width: 6),
                            const _Chip('local'),
                          ],
                          // Desvios do default (read + visível): só eles
                          // ganham chip, senão vira ruído.
                          if (conn.access == DbAccess.readwrite) ...[
                            const SizedBox(width: 6),
                            const _Chip('rw'),
                          ],
                          if (!conn.agents) ...[
                            const SizedBox(width: 6),
                            const _Chip('no agents'),
                          ],
                        ],
                      ),
                      Text(
                        '${conn.engine.label} · ${conn.displayTarget}',
                        overflow: TextOverflow.ellipsis,
                        style: typo.mono.copyWith(
                          fontSize: 10,
                          color: colors.text4,
                        ),
                      ),
                    ],
                  ),
                ),
                Builder(
                  builder: (anchor) => HoverTap(
                    onTap: () => onContextMenu(anchor, conn),
                    padding: const EdgeInsets.all(3),
                    child: Icon(
                      Icons.more_horiz,
                      size: 14,
                      color: colors.text4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (expanded && browsable)
          _SchemaTree(conn: conn, onNewQuery: onNewQuery),
        if (expanded && isMongo) _MongoCollections(conn: conn),
      ],
    );
  }
}

/// Árvore de tabelas → colunas de uma conexão, carregada sob demanda.
class _SchemaTree extends StatefulWidget {
  const _SchemaTree({required this.conn, required this.onNewQuery});
  final DbConnection conn;
  final void Function(SchemaTable table) onNewQuery;

  @override
  State<_SchemaTree> createState() => _SchemaTreeState();
}

class _SchemaTreeState extends State<_SchemaTree> {
  late Future<List<SchemaTable>> _tables;

  /// Tabelas abertas (colunas expandidas), chaveadas por schema+nome — nomes
  /// homônimos em schemas distintos não colidem.
  final _openTables = <String>{};

  /// Schemas recolhidos (só relevante quando há mais de um). Ausente = aberto.
  final _collapsedSchemas = <String>{};

  static String _key(SchemaTable t) => '${t.schema ?? ''}.${t.name}';

  @override
  void initState() {
    super.initState();
    _tables = context.read<DatabaseViewModel>().tables(widget.conn);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, bottom: 4),
      child: FutureBuilder<List<SchemaTable>>(
        future: _tables,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return _hint('Loading…');
          }
          if (snap.hasError) {
            return _hint(_errorMessage(snap.error), error: true);
          }
          final tables = snap.data ?? const [];
          if (tables.isEmpty) return _hint('No tables.');

          // Agrupa por schema só quando há mais de um distinto — caso comum
          // (public/dbo/database único, ou SQLite) segue lista plana como antes.
          final schemas = <String>{
            for (final t in tables)
              if (t.schema != null) t.schema!,
          };
          if (schemas.length <= 1) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [for (final t in tables) ..._tableRow(t)],
            );
          }

          final bySchema = <String, List<SchemaTable>>{};
          for (final t in tables) {
            bySchema.putIfAbsent(t.schema ?? '', () => []).add(t);
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final entry in bySchema.entries) ...[
                _schemaHeader(entry.key, entry.value.length),
                if (!_collapsedSchemas.contains(entry.key))
                  for (final t in entry.value) ..._tableRow(t, indent: true),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _schemaHeader(String schema, int count) {
    final colors = context.colors;
    final typo = context.typo;
    final collapsed = _collapsedSchemas.contains(schema);
    return HoverTap(
      onTap: () => setState(() {
        if (!_collapsedSchemas.remove(schema)) _collapsedSchemas.add(schema);
      }),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: Row(
        children: [
          Icon(
            collapsed ? Icons.chevron_right : Icons.expand_more,
            size: 13,
            color: colors.text4,
          ),
          const SizedBox(width: 3),
          Icon(Icons.folder_outlined, size: 11, color: colors.text4),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              schema.isEmpty ? '(default)' : schema,
              overflow: TextOverflow.ellipsis,
              style: typo.mono.copyWith(
                fontSize: 11,
                color: colors.text3,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: typo.label.copyWith(fontSize: 10, color: colors.text4),
          ),
        ],
      ),
    );
  }

  List<Widget> _tableRow(SchemaTable t, {bool indent = false}) {
    final colors = context.colors;
    final typo = context.typo;
    final key = _key(t);
    final open = _openTables.contains(key);
    return [
      Padding(
        padding: EdgeInsets.only(left: indent ? 16 : 0),
        child: HoverTap(
          onTap: () => setState(() {
            if (!_openTables.remove(key)) _openTables.add(key);
          }),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          child: Row(
            children: [
              Icon(
                open ? Icons.expand_more : Icons.chevron_right,
                size: 13,
                color: colors.text4,
              ),
              const SizedBox(width: 3),
              Icon(
                t.isView ? Icons.visibility_outlined : Icons.table_chart,
                size: 11,
                color: colors.text4,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  t.name,
                  overflow: TextOverflow.ellipsis,
                  style: typo.mono.copyWith(
                    fontSize: 11.5,
                    color: colors.text2,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              AppTooltip(
                message: 'New query',
                child: HoverTap(
                  onTap: () => widget.onNewQuery(t),
                  padding: const EdgeInsets.all(2),
                  child: Icon(Icons.add, size: 12, color: colors.text4),
                ),
              ),
            ],
          ),
        ),
      ),
      if (open)
        Padding(
          padding: EdgeInsets.only(left: indent ? 16 : 0),
          child: _ColumnList(
            conn: widget.conn,
            table: t.name,
            schema: t.schema,
          ),
        ),
    ];
  }

  Widget _hint(String text, {bool error = false}) => Padding(
    padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
    child: Text(
      text,
      style: context.typo.label.copyWith(
        fontSize: 10.5,
        color: error ? context.colors.error : context.colors.text4,
      ),
    ),
  );
}

/// Collections de uma conexão Mongo (plano 53), carregadas sob demanda —
/// análogo do `_SchemaTree` SQL. Clique abre o collection browser.
class _MongoCollections extends StatefulWidget {
  const _MongoCollections({required this.conn});
  final DbConnection conn;

  @override
  State<_MongoCollections> createState() => _MongoCollectionsState();
}

class _MongoCollectionsState extends State<_MongoCollections> {
  late final Future<List<String>> _collections;

  @override
  void initState() {
    super.initState();
    _collections = context.read<DatabaseViewModel>().collections(widget.conn);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    return Padding(
      padding: const EdgeInsets.only(left: 20, bottom: 4),
      child: FutureBuilder<List<String>>(
        future: _collections,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return _hint('Loading…');
          }
          if (snap.hasError) {
            return _hint(_errorMessage(snap.error), error: true);
          }
          final names = snap.data ?? const [];
          if (names.isEmpty) return _hint('No collections.');
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final name in names)
                HoverTap(
                  onTap: () => context
                      .read<CockpitViewModel>()
                      .openMongoBrowser(widget.conn.name, name),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 3,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.data_object, size: 11, color: colors.text4),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          name,
                          overflow: TextOverflow.ellipsis,
                          style: typo.mono.copyWith(
                            fontSize: 11.5,
                            color: colors.text2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _hint(String text, {bool error = false}) => Padding(
    padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
    child: Text(
      text,
      style: context.typo.label.copyWith(
        fontSize: 10.5,
        color: error ? context.colors.error : context.colors.text4,
      ),
    ),
  );
}

class _ColumnList extends StatefulWidget {
  const _ColumnList({required this.conn, required this.table, this.schema});
  final DbConnection conn;
  final String table;
  final String? schema;

  @override
  State<_ColumnList> createState() => _ColumnListState();
}

class _ColumnListState extends State<_ColumnList> {
  late final Future<List<SchemaColumn>> _cols;

  @override
  void initState() {
    super.initState();
    _cols = context.read<DatabaseViewModel>().columns(
      widget.conn,
      widget.table,
      schema: widget.schema,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    return Padding(
      padding: const EdgeInsets.only(left: 22),
      child: FutureBuilder<List<SchemaColumn>>(
        future: _cols,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 6),
              child: Text(
                'Loading…',
                style: typo.label.copyWith(fontSize: 10, color: colors.text4),
              ),
            );
          }
          final cols = snap.data ?? const [];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final c in cols)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 1.5,
                    horizontal: 6,
                  ),
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          c.name,
                          overflow: TextOverflow.ellipsis,
                          style: typo.mono.copyWith(
                            fontSize: 11,
                            color: colors.text2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        c.type,
                        style: typo.mono.copyWith(
                          fontSize: 9.5,
                          color: colors.text4,
                        ),
                      ),
                      if (c.primaryKey) ...[
                        const SizedBox(width: 5),
                        Text(
                          'PK',
                          style: typo.label.copyWith(
                            fontSize: 8.5,
                            color: colors.accent,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

String _errorMessage(Object? e) =>
    e is DbQueryException ? e.message : e.toString();

class _Chip extends StatelessWidget {
  const _Chip(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: colors.border2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: context.typo.label.copyWith(fontSize: 9.5, color: colors.text3),
      ),
    );
  }
}
