import 'package:cockpit/app/core/ui/clamping_scroll_behavior.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/app_menu.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Mockup navegável da **tab de base de dados** (estudo do plano file-tabs,
/// fase SQLite viewer). NÃO faz parte do app: entrypoint separado, dados 100%
/// fake, nenhum banco é aberto. Usa o tema real do Cockpit pra avaliar o visual
/// como ele ficaria de verdade.
///
/// Rodar: `flutter run -d macos -t lib/mockups/db_tab_mockup.dart`
void main() => runApp(const DbTabMockupApp());

class DbTabMockupApp extends StatelessWidget {
  const DbTabMockupApp({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = buildTokens(brightness: Brightness.dark);
    return ShadcnApp(
      title: 'Cockpit — DB Tab (mockup)',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const ClampingScrollBehavior(),
      theme: buildTheme(brightness: Brightness.dark),
      builder: (context, child) => CockpitTheme(
        colors: tokens.colors,
        typo: tokens.typo,
        syntax: tokens.syntax,
        child: child ?? const SizedBox(),
      ),
      home: const _MockupShell(),
    );
  }
}

/// Simula o pane central do Cockpit: uma tab strip fake com a tab `app.db`
/// ativa, e o corpo da tab de banco embaixo.
class _MockupShell extends StatelessWidget {
  const _MockupShell();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ColoredBox(
      color: colors.bg,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Column(
              children: [
                const _FakeTabStrip(),
                Expanded(child: _DbTab()),
              ],
            ),
          ),
          Container(width: 1, color: colors.border),
          const _DbPanel(),
        ],
      ),
    );
  }
}

class _FakeTabStrip extends StatelessWidget {
  const _FakeTabStrip();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: colors.panel,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: const [
          _FakeTab(icon: Icons.auto_awesome, label: 'Agent', active: false),
          _FakeTab(
            icon: Icons.storage,
            label: 'orders-analysis.dbq',
            active: true,
          ),
        ],
      ),
    );
  }
}

class _FakeTab extends StatelessWidget {
  const _FakeTab({
    required this.icon,
    required this.label,
    required this.active,
  });

  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: active ? colors.bg : null,
        border: Border(
          right: BorderSide(color: colors.border),
          bottom: BorderSide(
            color: active ? colors.accent : colors.border,
            width: active ? 2 : 1,
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: active ? colors.accent : colors.text4),
          const SizedBox(width: 6),
          Text(
            label,
            style: typo.tab.copyWith(
              color: active ? colors.text : colors.text3,
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────── painel Database ──

class _MockConn {
  const _MockConn(this.name, this.engine, this.target, this.online,
      {this.inUse = false, this.implicit = false});
  final String name;
  final String engine;
  final String target;
  final bool online;
  final bool inUse;
  final bool implicit;
}

/// Lista viva do mockup — o "+" do painel adiciona aqui.
final _conns = <_MockConn>[
  const _MockConn('dev-local', 'SQLite 3', 'app.db', true, inUse: true),
  const _MockConn('staging', 'Postgres 16', 'db.staging.acme.dev:5432', true),
  const _MockConn('analytics', 'MySQL 8', 'mysql.acme.dev:3306', true),
  const _MockConn('prod-readonly', 'Postgres 16', 'db.acme.com:5432', false),
  const _MockConn('cache.db', 'SQLite 3', '.dart_tool/cache.db', true,
      implicit: true),
];

/// Painel lateral direito, no lugar de Files/Search/Source Control: a aba
/// **Database** com as conexões do workspace (`.cockpit/databases.json` +
/// sqlites detectados no repo).
class _DbPanel extends StatefulWidget {
  const _DbPanel();

  @override
  State<_DbPanel> createState() => _DbPanelState();
}

class _DbPanelState extends State<_DbPanel> {
  /// "+" abre o popup de engines; escolhido, o dialog já vem naquele modo.
  Future<void> _add(BuildContext anchor) async {
    final e = await showAppMenu<_Engine>(
      anchor,
      items: [
        for (final e in _Engine.values)
          AppMenuItem(value: e, label: _engineLabel(e), icon: Icons.storage),
      ],
    );
    if (e == null || !mounted) return;
    final conn = await showDialog<_MockConn>(
      context: context,
      builder: (context) => _ConnDialog(engine: e),
    );
    if (conn == null || !mounted) return;
    setState(() => _conns.add(conn));
  }

  /// Clicar numa conexão reaproveita o MESMO dialog, pré-preenchido.
  Future<void> _edit(_MockConn c) async {
    final updated = await showDialog<_MockConn>(
      context: context,
      builder: (context) => _ConnDialog(engine: _engineOf(c), initial: c),
    );
    if (updated == null || !mounted) return;
    setState(() {
      if (updated == _ConnDialog.deleted) {
        _conns.remove(c);
      } else {
        _conns[_conns.indexOf(c)] = updated;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    return Container(
      width: 250,
      color: colors.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cabeçalho de abas do painel (fake): Files · Search · Database.
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
            child: Row(
              children: [
                Icon(Icons.folder_outlined, size: 14, color: colors.text4),
                const SizedBox(width: 14),
                Icon(Icons.search, size: 14, color: colors.text4),
                const SizedBox(width: 14),
                Icon(Icons.account_tree_outlined,
                    size: 14, color: colors.text4),
                const SizedBox(width: 14),
                Icon(Icons.storage, size: 14, color: colors.accent),
                const Spacer(),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Text(
              'DATABASE',
              style: typo.label.copyWith(
                fontSize: 10,
                letterSpacing: 1.1,
                color: colors.text3,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final c in _conns)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    child: HoverTap(
                      onTap: () => _edit(c),
                      color: c.inUse ? colors.panel3 : null,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Icon(
                              Icons.storage,
                              size: 12,
                              color: c.inUse ? colors.accent : colors.text4,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        c.name,
                                        overflow: TextOverflow.ellipsis,
                                        style: typo.body.copyWith(
                                          fontSize: 12.5,
                                          color: c.inUse
                                              ? colors.text
                                              : colors.text2,
                                        ),
                                      ),
                                    ),
                                    if (c.inUse) ...[
                                      const SizedBox(width: 6),
                                      const _Chip('in use'),
                                    ],
                                    if (c.implicit) ...[
                                      const SizedBox(width: 6),
                                      const _Chip('detected'),
                                    ],
                                  ],
                                ),
                                Text(
                                  '${c.engine} · ${c.target}',
                                  overflow: TextOverflow.ellipsis,
                                  style: typo.mono.copyWith(
                                    fontSize: 10,
                                    color: colors.text4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colors.border)),
            ),
            child: Text(
              '.cockpit/databases.json · 3 connections',
              style: typo.label.copyWith(fontSize: 10.5, color: colors.text4),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────── dialog de cadastro ──

enum _Engine { sqlite, postgres, mysql }

String _engineLabel(_Engine e) => switch (e) {
      _Engine.sqlite => 'SQLite',
      _Engine.postgres => 'Postgres',
      _Engine.mysql => 'MySQL',
    };

/// Engine de uma conexão existente (pelo label de display do mockup).
_Engine _engineOf(_MockConn c) {
  if (c.engine.startsWith('SQLite')) return _Engine.sqlite;
  if (c.engine.startsWith('Postgres')) return _Engine.postgres;
  return _Engine.mysql;
}


/// Cadastro de conexão: engine → campos (SQLite = só o arquivo; Postgres/MySQL
/// = host/porta/database/usuário + env da senha). Read-only default ON.
/// No app real isso persiste em `.cockpit/databases.json` como
/// `{name, url, passwordSource?}`.
class _ConnDialog extends StatefulWidget {
  const _ConnDialog({required this.engine, this.initial});

  /// Sentinela devolvida pelo botão Excluir do modo edição.
  static const deleted = _MockConn('__deleted__', '', '', false);

  final _Engine engine;

  /// Presente = modo edição (campos pré-preenchidos, botão "Salvar").
  final _MockConn? initial;

  @override
  State<_ConnDialog> createState() => _ConnDialogState();
}

class _ConnDialogState extends State<_ConnDialog> {
  _Engine get _engine => widget.engine;

  /// "Salvar Senha": campo sempre visível; desligado = desabilitado. O valor
  /// vai pro cofre do SO via flutter_secure_storage (nunca pro databases.json).
  bool _savePassword = false;

  /// null = ainda não testou; true/false = resultado do último teste.
  bool? _testOk;
  bool _testing = false;
  final _name = TextEditingController();
  final _file = TextEditingController(text: 'app.db');
  final _host = TextEditingController(text: 'localhost');
  final _port = TextEditingController();
  final _db = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();

  @override
  void initState() {
    super.initState();
    final c = widget.initial;
    if (c == null) return;
    _name.text = c.name;
    if (_engine == _Engine.sqlite) {
      _file.text = c.target;
    } else {
      final ix = c.target.lastIndexOf(':');
      _host.text = ix > 0 ? c.target.substring(0, ix) : c.target;
      _port.text = ix > 0 ? c.target.substring(ix + 1) : '';
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _file, _host, _port, _db, _user, _pass]) {
      c.dispose();
    }
    super.dispose();
  }

  String get _defaultPort =>
      _engine == _Engine.postgres ? '5432' : '3306';

  _MockConn _build() {
    final name = _name.text.trim().isEmpty ? 'nova-conexao' : _name.text.trim();
    switch (_engine) {
      case _Engine.sqlite:
        return _MockConn(name, 'SQLite 3', _file.text.trim(), true);
      case _Engine.postgres:
      case _Engine.mysql:
        final port =
            _port.text.trim().isEmpty ? _defaultPort : _port.text.trim();
        final engine =
            _engine == _Engine.postgres ? 'Postgres 16' : 'MySQL 8';
        return _MockConn(
            name, engine, '${_host.text.trim()}:$port', true);
    }
  }

  Widget _passwordField() {
    final colors = context.colors;
    final typo = context.typo;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Password',
              style: typo.label.copyWith(fontSize: 11, color: colors.text3)),
          const SizedBox(height: 4),
          TextField(
            controller: _pass,
            enabled: _savePassword,
            obscureText: true,
            style: typo.mono.copyWith(
              fontSize: 12.5,
              color: _savePassword ? colors.text : colors.text4,
            ),
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(6),
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          ),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, {String? hint}) {
    final colors = context.colors;
    final typo = context.typo;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: typo.label.copyWith(fontSize: 11, color: colors.text3)),
          const SizedBox(height: 4),
          TextField(
            controller: ctrl,
            style: typo.mono.copyWith(fontSize: 12.5, color: colors.text),
            placeholder: hint == null
                ? null
                : Text(hint,
                    style: typo.mono
                        .copyWith(fontSize: 12.5, color: colors.text4)),
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(6),
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          ),
        ],
      ),
    );
  }

  /// Teste fake: SQLite ok se o arquivo tem nome; rede ok se host não-vazio.
  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testOk = null;
    });
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    final ok = _engine == _Engine.sqlite
        ? _file.text.trim().isNotEmpty
        : _host.text.trim().isNotEmpty;
    setState(() {
      _testing = false;
      _testOk = ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    return AlertDialog(
      title: Text(
          widget.initial == null
              ? 'New connection — ${_engineLabel(_engine)}'
              : 'Edit connection — ${_engineLabel(_engine)}',
          style: typo.title.copyWith(fontSize: 15, color: colors.text)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Engine já foi escolhido no popup do "+" (ou vem da conexão
            // em edição) — aqui é só informativo.
            _Chip(_engineLabel(_engine)),
            const SizedBox(height: 14),
            _field('Name', _name, hint: 'dev-local'),
            if (_engine == _Engine.sqlite)
              _field('File', _file, hint: './app.db')
            else ...[
              _field('Host', _host),
              Row(
                children: [
                  Expanded(child: _field('Port', _port, hint: _defaultPort)),
                  const SizedBox(width: 10),
                  Expanded(child: _field('Database', _db, hint: 'app_dev')),
                ],
              ),
              _field('User', _user, hint: 'postgres'),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Switch(
                      value: _savePassword,
                      onChanged: (v) => setState(() => _savePassword = v),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Save Password',
                      style: typo.label.copyWith(
                        fontSize: 12,
                        color: colors.text2,
                      ),
                    ),
                  ],
                ),
              ),
              _passwordField(),
            ],
            if (_testing || _testOk != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    _testing
                        ? Icons.more_horiz
                        : _testOk!
                            ? Icons.check_circle
                            : Icons.error_outline,
                    size: 13,
                    color: _testing
                        ? colors.text3
                        : _testOk!
                            ? colors.online
                            : colors.error,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _testing
                        ? 'Testing connection…'
                        : _testOk!
                            ? 'Connection OK · 23 ms'
                            : 'Connection failed — check your settings',
                    style: typo.label.copyWith(
                      fontSize: 11.5,
                      color: _testing
                          ? colors.text3
                          : _testOk!
                              ? colors.online
                              : colors.error,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (widget.initial != null) ...[
          DestructiveButton(
            onPressed: () =>
                Navigator.of(context).pop(_ConnDialog.deleted),
            child: const Text('Delete'),
          ),
          const Spacer(),
        ],
        GhostButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        OutlineButton(
          onPressed: _testing ? null : _test,
          child: const Text('Test'),
        ),
        PrimaryButton(
          onPressed: () => Navigator.of(context).pop(_build()),
          child: Text(widget.initial == null ? 'Add' : 'Save'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────── dados fake ──

/// Marcador de célula BLOB (render `⟨blob · NN KB⟩`).
class _Blob {
  const _Blob(this.kb);
  final int kb;
}

/// Marcador de célula de status (render com dot colorido).
class _Status {
  const _Status(this.label);
  final String label;
}

class _MockCol {
  const _MockCol(this.name, this.type, this.width, {this.numeric = false});
  final String name;
  final String type;
  final double width;
  final bool numeric;
}

class _MockTable {
  const _MockTable(this.name, this.totalRows, this.columns);
  final String name;
  final int totalRows;
  final List<_MockCol> columns;

  int get pageCount => (totalRows + _pageSize - 1) ~/ _pageSize;
}

const int _pageSize = 100;

const _tables = <_MockTable>[
  _MockTable('orders', 4182, [
    _MockCol('id', 'INTEGER', 70, numeric: true),
    _MockCol('customer', 'TEXT', 180),
    _MockCol('status', 'TEXT', 120),
    _MockCol('total', 'REAL', 110, numeric: true),
    _MockCol('coupon', 'TEXT', 110),
    _MockCol('created_at', 'TEXT', 160),
  ]),
  _MockTable('users', 812, [
    _MockCol('id', 'INTEGER', 70, numeric: true),
    _MockCol('name', 'TEXT', 170),
    _MockCol('email', 'TEXT', 220),
    _MockCol('avatar', 'BLOB', 130),
    _MockCol('created_at', 'TEXT', 160),
  ]),
  _MockTable('products', 1246, [
    _MockCol('id', 'INTEGER', 70, numeric: true),
    _MockCol('sku', 'TEXT', 120),
    _MockCol('name', 'TEXT', 240),
    _MockCol('price', 'REAL', 100, numeric: true),
    _MockCol('stock', 'INTEGER', 90, numeric: true),
  ]),
  _MockTable('order_items', 9938, [
    _MockCol('id', 'INTEGER', 70, numeric: true),
    _MockCol('order_id', 'INTEGER', 100, numeric: true),
    _MockCol('product_id', 'INTEGER', 110, numeric: true),
    _MockCol('qty', 'INTEGER', 70, numeric: true),
    _MockCol('unit_price', 'REAL', 110, numeric: true),
  ]),
  _MockTable('migrations', 12, [
    _MockCol('id', 'INTEGER', 70, numeric: true),
    _MockCol('name', 'TEXT', 300),
    _MockCol('applied_at', 'TEXT', 160),
  ]),
  _MockTable('sqlite_sequence', 4, [
    _MockCol('name', 'TEXT', 180),
    _MockCol('seq', 'INTEGER', 100, numeric: true),
  ]),
];

const _customers = [
  'Ana Souza', 'Bruno Lima', 'Carla Mendes', 'Diego Rocha', 'Elisa Prado',
  'Fábio Nunes', 'Gabi Torres', 'Hugo Reis', 'Iara Campos', 'João Pedro',
  'Karen Dias', 'Léo Martins', 'Marina Alves', 'Nina Barros', 'Otávio Cruz',
];

const _statuses = ['paid', 'pending', 'shipped', 'canceled'];

const _productNames = [
  'Teclado mecânico TKL', 'Mouse vertical', 'Hub USB-C 7 portas',
  'Monitor 27" 4K', 'Webcam 1080p', 'Headset sem fio', 'Dock station',
  'SSD NVMe 2TB', 'Cabo Thunderbolt 2m', 'Suporte de notebook',
];

const _migrationNames = [
  '0001_create_users', '0002_create_products', '0003_create_orders',
  '0004_order_items', '0005_add_coupon_to_orders', '0006_index_orders_status',
  '0007_users_avatar_blob', '0008_soft_delete_products', '0009_orders_totals',
  '0010_backfill_skus', '0011_index_items_order_id', '0012_vacuum_marker',
];

/// Pseudo-hash determinístico — dá variedade estável sem Random.
int _h(int x) => (x * 2654435761) & 0x7fffffff;

/// Gera a página [page] da tabela [t]. Determinístico: mesma página, mesmos
/// dados — o que torna a paginação do mockup crível.
List<List<Object?>> _rowsFor(_MockTable t, int page) {
  final start = page * _pageSize;
  final count =
      (t.totalRows - start) < _pageSize ? (t.totalRows - start) : _pageSize;
  if (count <= 0) return const [];
  return List.generate(count, (i) {
    final id = start + i + 1;
    final r = _h(id);
    switch (t.name) {
      case 'orders':
        return <Object?>[
          id,
          _customers[r % _customers.length],
          _Status(_statuses[r % _statuses.length]),
          (r % 90000) / 100 + 19.9,
          r % 7 == 0 ? 'PROMO${(r % 90) + 10}' : null,
          _fakeDate(r),
        ];
      case 'users':
        final name = _customers[r % _customers.length];
        final mail =
            '${name.split(' ').first.toLowerCase()}$id@exemplo.com';
        return <Object?>[
          id,
          name,
          mail,
          r % 3 == 0 ? null : _Blob((r % 120) + 8),
          _fakeDate(r >> 3),
        ];
      case 'products':
        return <Object?>[
          id,
          'SKU-${(r % 9000) + 1000}',
          '${_productNames[r % _productNames.length]} v${(r % 4) + 1}',
          (r % 40000) / 100 + 9.9,
          r % 11 == 0 ? 0 : r % 340,
        ];
      case 'order_items':
        return <Object?>[
          id,
          (r % 4182) + 1,
          (_h(r) % 1246) + 1,
          (r % 5) + 1,
          (r % 20000) / 100 + 4.9,
        ];
      case 'migrations':
        return <Object?>[
          id,
          _migrationNames[(id - 1) % _migrationNames.length],
          _fakeDate(r),
        ];
      default: // sqlite_sequence
        const seqs = ['users', 'products', 'orders', 'order_items'];
        const vals = [812, 1246, 4182, 9938];
        return <Object?>[seqs[(id - 1) % 4], vals[(id - 1) % 4]];
    }
  });
}

String _fakeDate(int r) {
  final mo = (r % 6) + 1;
  final d = (r % 28) + 1;
  final hh = r % 24;
  final mi = (r >> 5) % 60;
  String p(int v) => v.toString().padLeft(2, '0');
  return '2026-${p(mo)}-${p(d)} ${p(hh)}:${p(mi)}';
}

/// 4182 → `4,182` (milhar com vírgula, en-US — app é em inglês).
String _fmtInt(int n) {
  final s = n.toString();
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
}

String _fmtMoney(double v) => v.toStringAsFixed(2).replaceAll('.', ',');

// ──────────────────────────────────────────────────────────────────── a tab ──

class _DbTab extends StatefulWidget {
  @override
  State<_DbTab> createState() => _DbTabState();
}

class _DbTabState extends State<_DbTab> {
  int _tableIx = 0;
  int _page = 0;
  int? _selectedRow;
  int _elapsedMs = 24;
  // O `.dbq` persiste `-- db:`/`-- limit:` como frontmatter, mas o editor
  // mostra SÓ o SQL — a conexão é escolhida no popup da top bar.
  int _connIx = 0;

  /// Fração da altura ocupada pelo editor SQL (divisor arrastável).
  double _split = 0.5;
  late final TextEditingController _sql = TextEditingController(
    text: 'SELECT *\nFROM orders\nWHERE status = \'paid\'\n'
        'ORDER BY created_at DESC;',
  );

  _MockTable get _table => _tables[_tableIx];

  @override
  void dispose() {
    _sql.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    final clamped = page.clamp(0, _table.pageCount - 1);
    if (clamped == _page) return;
    setState(() {
      _page = clamped;
      _selectedRow = null;
    });
  }

  /// "Roda" a query — com texto selecionado no editor, executa SÓ a seleção
  /// (padrão DataGrip/DBeaver). Se o SQL menciona outra tabela conhecida,
  /// troca pra ela; o resto é cosmético (mockup não tem engine).
  void _run() {
    final sel = _sql.selection;
    final sql = sel.isValid && !sel.isCollapsed
        ? sel.textInside(_sql.text)
        : _sql.text;
    final text = sql.toLowerCase();
    var target = _tableIx;
    for (var i = 0; i < _tables.length; i++) {
      if (text.contains(_tables[i].name)) target = i;
    }
    setState(() {
      _tableIx = target;
      _page = 0;
      _selectedRow = null;
      _elapsedMs = 3 + _h(text.length + _tableIx) % 90;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final rows = _rowsFor(_table, _page);
    return Column(
      children: [
        _TopBar(
          conn: _conns[_connIx],
          onPickConn: (ix) => setState(() => _connIx = ix),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              final editorH =
                  (box.maxHeight * _split).clamp(90.0, box.maxHeight - 120);
              return Column(
                children: [
                  SizedBox(
                    height: editorH,
                    child: _SqlEditor(controller: _sql, onRun: _run),
                  ),
                  // Divisor arrastável editor ↔ resultado.
                  MouseRegion(
                    cursor: SystemMouseCursors.resizeUpDown,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragUpdate: (d) => setState(() {
                        _split = ((editorH + d.delta.dy) / box.maxHeight)
                            .clamp(0.12, 0.85);
                      }),
                      child: SizedBox(
                        height: 7,
                        child: Center(
                          child:
                              Container(height: 1, color: colors.border2),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: _DataGrid(
                      table: _table,
                      rows: rows,
                      firstRowNumber: _page * _pageSize + 1,
                      selectedRow: _selectedRow,
                      onSelectRow: (i) =>
                          setState(() => _selectedRow = i),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        _GridFooter(
          table: _table,
          page: _page,
          shownRows: rows.length,
          elapsedMs: _elapsedMs,
          onPrev: () => _goTo(_page - 1),
          onNext: () => _goTo(_page + 1),
        ),
      ],
    );
  }
}


// ──────────────────────────────────────────────────────────────────── barra ──

class _TopBar extends StatelessWidget {
  const _TopBar({required this.conn, required this.onPickConn});

  final _MockConn conn;
  final ValueChanged<int> onPickConn;

  Future<void> _openPicker(BuildContext context) async {
    final ix = await showAppMenu<int>(
      context,
      items: [
        for (var i = 0; i < _conns.length; i++)
          AppMenuItem(
            value: i,
            label: '${_conns[i].name} · ${_conns[i].engine}',
            icon: Icons.storage,
            selected: _conns[i].name == conn.name,
          ),
      ],
    );
    if (ix != null) onPickConn(ix);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.panel,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          // Seletor de conexão: popup com as bases cadastradas; a escolha é
          // persistida no frontmatter do `.dbq` (invisível no editor).
          Builder(
            builder: (anchor) => HoverTap(
              onTap: () => _openPicker(anchor),
              color: colors.panel3,
              borderRadius: const BorderRadius.all(Radius.circular(4)),
              padding: const EdgeInsets.symmetric(
                horizontal: 7,
                vertical: 3,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.storage, size: 11, color: colors.text3),
                  const SizedBox(width: 5),
                  Text(
                    conn.name,
                    style: typo.label.copyWith(
                      fontSize: 10.5,
                      color: colors.text2,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.keyboard_arrow_down,
                    size: 12,
                    color: colors.text3,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          _Chip(conn.engine),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: colors.border2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: typo.label.copyWith(fontSize: 10, color: colors.text3),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────── grid ──

/// Largura do gutter de índice (numeração de linha da própria aplicação).
const double _indexColWidth = 44;

/// Grid responsivo: as colunas preenchem a largura disponível (sobra
/// distribuída proporcionalmente). Sem ordenação. O divisor entre headers é
/// arrastável — só pra AUMENTAR o espaçamento além do mínimo da coluna.
class _DataGrid extends StatefulWidget {
  const _DataGrid({
    required this.table,
    required this.rows,
    required this.firstRowNumber,
    required this.selectedRow,
    required this.onSelectRow,
  });

  final _MockTable table;
  final List<List<Object?>> rows;
  final int firstRowNumber;
  final int? selectedRow;
  final ValueChanged<int> onSelectRow;

  @override
  State<_DataGrid> createState() => _DataGridState();
}

class _DataGridState extends State<_DataGrid> {
  /// Largura extra por coluna (chave `tabela:ix`) — nunca negativa: o mínimo é
  /// a largura base da coluna.
  final Map<String, double> _extra = {};

  void _resize(int col, double delta) {
    final k = '${widget.table.name}:$col';
    setState(() {
      _extra[k] = ((_extra[k] ?? 0) + delta).clamp(0.0, 600.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cols = widget.table.columns;
    return LayoutBuilder(
      builder: (context, box) {
        final base = [
          for (var i = 0; i < cols.length; i++)
            cols[i].width + (_extra['${widget.table.name}:$i'] ?? 0),
        ];
        final avail = box.maxWidth - _indexColWidth;
        final sum = base.fold<double>(0, (a, b) => a + b);
        // Responsivo: cabe → estica proporcional; não cabe → scroll horizontal.
        final widths = sum < avail
            ? [for (final w in base) w * avail / sum]
            : base;
        final total =
            _indexColWidth + widths.fold<double>(0, (a, b) => a + b);
        final content = SizedBox(
          width: total,
          child: Column(
            children: [
              _HeaderRow(table: widget.table, widths: widths, onResize: _resize),
              Expanded(
                child: ListView.builder(
                  itemCount: widget.rows.length,
                  itemExtent: 28,
                  itemBuilder: (context, i) => _DataRow(
                    table: widget.table,
                    widths: widths,
                    number: widget.firstRowNumber + i,
                    cells: widget.rows[i],
                    selected: i == widget.selectedRow,
                    onTap: () => widget.onSelectRow(i),
                  ),
                ),
              ),
            ],
          ),
        );
        if (sum < avail) return content;
        return ScrollConfiguration(
          behavior:
              ScrollConfiguration.of(context).copyWith(scrollbars: true),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: content,
          ),
        );
      },
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({
    required this.table,
    required this.widths,
    required this.onResize,
  });

  final _MockTable table;
  final List<double> widths;
  final void Function(int col, double delta) onResize;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    return SizedBox(
      height: 38,
      child: Row(
        children: [
          // Canto do gutter de índice: sem header (fica no fundo do app).
          const SizedBox(width: _indexColWidth),
          for (var c = 0; c < table.columns.length; c++)
            Container(
              width: widths[c],
              decoration: BoxDecoration(
                color: colors.panel2,
                border: Border(bottom: BorderSide(color: colors.border2)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            table.columns[c].name,
                            overflow: TextOverflow.ellipsis,
                            style: typo.label.copyWith(
                              fontSize: 11.5,
                              color: colors.text2,
                            ),
                          ),
                          Text(
                            table.columns[c].type,
                            style: typo.mono.copyWith(
                              fontSize: 9,
                              color: colors.text4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Divisor arrastável: aumenta o espaçamento da coluna.
                  MouseRegion(
                    cursor: SystemMouseCursors.resizeColumn,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragUpdate: (d) => onResize(c, d.delta.dx),
                      child: SizedBox(
                        width: 9,
                        height: double.infinity,
                        child: Center(
                          child: Container(
                            width: 1,
                            color: colors.border2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DataRow extends StatelessWidget {
  const _DataRow({
    required this.table,
    required this.widths,
    required this.number,
    required this.cells,
    required this.selected,
    required this.onTap,
  });

  final _MockTable table;
  final List<double> widths;
  final int number;
  final List<Object?> cells;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    return HoverTap(
      onTap: onTap,
      borderRadius: BorderRadius.zero,
      color: selected ? colors.accentSoft : null,
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.border)),
        ),
        child: Row(
          children: [
            // Gutter de índice — numeração da aplicação, não do banco.
            Container(
              width: _indexColWidth,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.panel,
                border: Border(right: BorderSide(color: colors.border)),
              ),
              child: Text(
                '$number',
                style: typo.mono.copyWith(
                  fontSize: 10.5,
                  color: colors.text4,
                ),
              ),
            ),
            for (var c = 0; c < table.columns.length; c++)
              SizedBox(
                width: widths[c],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: _CellText(
                    value: cells[c],
                    numeric: table.columns[c].numeric,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CellText extends StatelessWidget {
  const _CellText({required this.value, required this.numeric});

  final Object? value;
  final bool numeric;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    final base = typo.mono.copyWith(fontSize: 11.5, color: colors.text2);
    final v = value;
    if (v == null) {
      return Text(
        'NULL',
        style: base.copyWith(
          color: colors.text4,
          fontStyle: FontStyle.italic,
        ),
      );
    }
    if (v is _Blob) {
      return Text(
        '⟨blob · ${v.kb} KB⟩',
        style: base.copyWith(color: colors.text4),
      );
    }
    if (v is _Status) {
      final dot = switch (v.label) {
        'paid' => colors.online,
        'pending' => colors.warn,
        'shipped' => colors.accent,
        _ => colors.error,
      };
      return Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(v.label, style: base),
        ],
      );
    }
    final text = switch (v) {
      final double d => _fmtMoney(d),
      final int n => n.toString(),
      _ => v.toString(),
    };
    return Text(
      text,
      overflow: TextOverflow.ellipsis,
      textAlign: numeric ? TextAlign.right : TextAlign.left,
      style: numeric ? base.copyWith(color: colors.text) : base,
    );
  }
}

class _GridFooter extends StatelessWidget {
  const _GridFooter({
    required this.table,
    required this.page,
    required this.shownRows,
    required this.elapsedMs,
    required this.onPrev,
    required this.onNext,
  });

  final _MockTable table;
  final int page;
  final int shownRows;
  final int elapsedMs;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    final first = page * _pageSize + 1;
    final last = page * _pageSize + shownRows;
    final info = typo.label.copyWith(fontSize: 11, color: colors.text3);
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: colors.panel,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Text(
            '${_fmtInt(first)}–${_fmtInt(last)} of ${_fmtInt(table.totalRows)}'
            ' · $elapsedMs ms',
            style: info,
          ),
          const Spacer(),
          HoverTap(
            onTap: page > 0 ? onPrev : null,
            padding: const EdgeInsets.all(3),
            child: Icon(
              Icons.chevron_left,
              size: 15,
              color: page > 0 ? colors.text2 : colors.text4,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              'Page ${page + 1} of ${table.pageCount}',
              style: info,
            ),
          ),
          HoverTap(
            onTap: page < table.pageCount - 1 ? onNext : null,
            padding: const EdgeInsets.all(3),
            child: Icon(
              Icons.chevron_right,
              size: 15,
              color:
                  page < table.pageCount - 1 ? colors.text2 : colors.text4,
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────── editor SQL ──

/// Metade de cima da tab: o **arquivo** `.sql` editável (multiline, mono).
/// No app real, isso é o conteúdo do arquivo salvo no repo — o agente escreve
/// aqui e o humano refina; Run executa contra a conexão da tab.
class _SqlEditor extends StatelessWidget {
  const _SqlEditor({required this.controller, required this.onRun});

  final TextEditingController controller;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      color: colors.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.enter, meta: true):
                    onRun,
              },
              child: TextField(
                controller: controller,
                maxLines: null,
                expands: true,
                style: typo.mono.copyWith(
                  fontSize: 12.5,
                  height: 1.5,
                  color: colors.text,
                ),
                placeholder: Text(
                  'SELECT …',
                  style: typo.mono.copyWith(
                    fontSize: 12.5,
                    color: colors.text4,
                  ),
                ),
                border: Border.all(color: colors.border),
                borderRadius: BorderRadius.circular(6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'saved · orders-analysis.dbq',
                style: typo.label.copyWith(
                  fontSize: 10.5,
                  color: colors.text4,
                ),
              ),
              const Spacer(),
              HoverTap(
                onTap: onRun,
                color: colors.accent,
                hoverColor: colors.accent.withValues(alpha: 0.85),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 5,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.play_arrow,
                      size: 13,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 5),
                    ListenableBuilder(
                      listenable: controller,
                      builder: (context, _) {
                        final sel = controller.selection;
                        final hasSel = sel.isValid && !sel.isCollapsed;
                        return Text(
                          hasSel ? 'Run selection' : 'Run',
                          style: typo.label.copyWith(
                            fontSize: 12,
                            color: Colors.white,
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 7),
                    Text(
                      '⌘↵',
                      style: typo.label.copyWith(
                        fontSize: 10,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
