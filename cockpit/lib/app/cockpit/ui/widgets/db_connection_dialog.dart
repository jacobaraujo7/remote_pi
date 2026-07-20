import 'package:cockpit/app/cockpit/domain/entities/db_connection.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/database_viewmodel.dart';
import 'package:cockpit/app/cockpit/ui/widgets/db_engine_icon.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Resultado do [DbConnectionDialog]: salvo (com senha opcional pro cofre),
/// excluído, ou `null` (cancelado).
class DbConnectionDialogResult {
  const DbConnectionDialogResult.saved(this.connection, this.password)
    : deleted = false;
  const DbConnectionDialogResult.deleted()
    : connection = null,
      password = null,
      deleted = true;

  final DbConnection? connection;

  /// Senha digitada (vai pro cofre via VM). `null` = não mexer na guardada.
  final String? password;
  final bool deleted;
}

/// Dialog único de conexão (plano 51, decisão E): criar (engine vem do popup
/// do "+") e editar (clicar na conexão — engine fixo). Test valida antes de
/// salvar; Delete (só em edição) fica na extrema esquerda.
class DbConnectionDialog extends StatefulWidget {
  const DbConnectionDialog({
    super.key,
    required this.engine,
    required this.viewModel,
    this.initial,
  });

  final DbEngine engine;
  final DatabaseViewModel viewModel;

  /// Presente = modo edição (campos pré-preenchidos, botão "Save").
  final DbConnection? initial;

  @override
  State<DbConnectionDialog> createState() => _DbConnectionDialogState();
}

class _DbConnectionDialogState extends State<DbConnectionDialog> {
  late bool _savePassword = widget.initial?.savePassword ?? false;

  /// Switch "Use SSL/TLS" — vira query param/scheme por engine na URL. SRV
  /// (Atlas) implica TLS: switch travado em ON.
  late bool _useTls = widget.initial?.useTls ?? false;
  bool get _isSrv => widget.initial?.isSrv ?? false;

  /// Guardrails do caminho dos agentes (CLI): escrita opt-in + visibilidade.
  /// GUI nunca é gated. Defaults seguros: read-only e visível.
  late bool _allowWrites = widget.initial?.access == DbAccess.readwrite;
  late bool _visibleToAgents = widget.initial?.agents ?? true;
  bool? _testOk;
  String? _testMessage;
  bool _testing = false;

  final _name = TextEditingController();
  final _file = TextEditingController();
  final _host = TextEditingController(text: 'localhost');
  final _port = TextEditingController();
  final _db = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();

  DbEngine get _engine => widget.engine;
  bool get _editing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final c = widget.initial;
    if (c == null) return;
    _name.text = c.name;
    if (_engine == DbEngine.sqlite) {
      _file.text = c.sqlitePath;
    } else {
      _host.text = c.host;
      _port.text = '${c.port}';
      _db.text = c.database;
      _user.text = c.user;
      // Senha guardada na URL (savePassword off) é recuperável — prefill.
      // A do cofre nunca aparece (placeholder `*******`).
      if (!c.savePassword) _pass.text = c.urlPassword ?? '';
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _file, _host, _port, _db, _user, _pass]) {
      c.dispose();
    }
    super.dispose();
  }

  DbConnection _build() {
    final name = _name.text.trim().isEmpty
        ? 'new-connection'
        : _name.text.trim();
    final access = _allowWrites ? DbAccess.readwrite : DbAccess.read;
    if (_engine == DbEngine.sqlite) {
      return DbConnection.sqlite(
        name,
        _file.text.trim(),
        access: access,
        agents: _visibleToAgents,
      );
    }
    return DbConnection.network(
      name: name,
      engine: _engine,
      host: _host.text.trim(),
      port: int.tryParse(_port.text.trim()),
      database: _db.text.trim(),
      user: _user.text.trim(),
      // Destino da senha pelo switch: OFF → embutida na URL (texto plano no
      // databases.json, recuperável); ON → só no cofre (URL limpa).
      password: _savePassword ? null : _pass.text,
      savePassword: _savePassword,
      access: access,
      agents: _visibleToAgents,
      // Edição de conexão Atlas: preserva o formato SRV e os query params da
      // URL original (o form não os expõe; reescrever pra mongodb://host:port
      // quebraria a conexão).
      srv: _isSrv,
      query: widget.initial?.urlQuery ?? '',
      tls: _useTls,
    );
  }

  /// Linha switch + rótulo (+ hint à direita) — padrão do "Save Password".
  Widget _switchRow(
    String label,
    bool value,
    ValueChanged<bool> onChanged, {
    String? hint,
  }) {
    final colors = context.colors;
    final typo = context.typo;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Switch(value: value, onChanged: onChanged),
          const SizedBox(width: 8),
          Text(
            label,
            style: typo.label.copyWith(fontSize: 12, color: colors.text2),
          ),
          if (hint != null) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                hint,
                overflow: TextOverflow.ellipsis,
                style: typo.label.copyWith(fontSize: 10.5, color: colors.text4),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Seleciona o arquivo sqlite no picker nativo (em vez de digitar o path).
  /// Abre na raiz do workspace; dentro dela, guarda o path **relativo**
  /// (portável entre máquinas do time).
  Future<void> _pickFile() async {
    final root = widget.viewModel.workspaceRoot;
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Choose SQLite database',
      initialDirectory: root,
      type: FileType.any,
    );
    if (!mounted || result == null) return;
    final path = result.files.single.path;
    if (path == null) return;
    final rel = root != null && path.startsWith('$root/')
        ? path.substring(root.length + 1)
        : path;
    setState(() {
      _file.text = rel;
      if (_name.text.trim().isEmpty) {
        _name.text = rel.split('/').last;
      }
    });
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testOk = null;
      _testMessage = null;
    });
    final initial = widget.initial;
    final error = await widget.viewModel.test(
      _build(),
      password: _pass.text.isEmpty ? null : _pass.text,
      // Edição com senha no cofre: o teste usa a guardada quando o campo está
      // vazio (o placeholder `*******` já diz que ela existe). Chave = nome
      // ORIGINAL — rename só migra a senha ao salvar.
      storedPasswordName: initial != null && initial.savePassword
          ? initial.name
          : null,
    );
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testOk = error == null;
      _testMessage = error;
    });
  }

  /// Campo File do SQLite: não se digita — clique abre o picker nativo
  /// ([_pickFile]).
  Widget _fileField() {
    final colors = context.colors;
    final typo = context.typo;
    final hasFile = _file.text.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'File',
            style: typo.label.copyWith(fontSize: 11, color: colors.text3),
          ),
          const SizedBox(height: 4),
          HoverTap(
            onTap: _pickFile,
            border: Border.all(color: colors.border),
            borderRadius: const BorderRadius.all(Radius.circular(6)),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    hasFile ? _file.text : 'Choose a SQLite file…',
                    overflow: TextOverflow.ellipsis,
                    style: typo.mono.copyWith(
                      fontSize: 12.5,
                      color: hasFile ? colors.text : colors.text4,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.folder_open, size: 14, color: colors.text3),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController ctrl, {
    String? hint,
    bool enabled = true,
    bool obscure = false,
  }) {
    final colors = context.colors;
    final typo = context.typo;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: typo.label.copyWith(fontSize: 11, color: colors.text3),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: ctrl,
            enabled: enabled,
            obscureText: obscure,
            style: typo.mono.copyWith(
              fontSize: 12.5,
              color: enabled ? colors.text : colors.text4,
            ),
            placeholder: hint == null
                ? null
                : Text(
                    hint,
                    style: typo.mono.copyWith(
                      fontSize: 12.5,
                      color: colors.text4,
                    ),
                  ),
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    // Largura fixa: sem isso o `Spacer` da barra de ações (Delete à esquerda,
    // modo edição) esticaria o dialog até a largura da tela.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: _dialog(colors, typo),
      ),
    );
  }

  Widget _dialog(AppColors colors, AppTypography typo) {
    return AlertDialog(
      title: Row(
        children: [
          DbEngineIcon(_engine, size: 18),
          const SizedBox(width: 8),
          Text(
            _editing ? 'Edit connection' : 'New connection',
            style: typo.title.copyWith(fontSize: 15, color: colors.text),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _field('Name', _name, hint: 'dev-local'),
            if (_engine == DbEngine.sqlite)
              _fileField()
            else ...[
              _field('Host', _host),
              Row(
                children: [
                  Expanded(
                    child: _field(
                      'Port',
                      _port,
                      hint: '${_engine.defaultPort}',
                    ),
                  ),
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
              // Sempre habilitado: com "Save Password" OFF a senha vai
              // embutida na URL (databases.json, texto plano, recuperável);
              // ON, vai pro cofre — placeholder `*******` sinaliza que existe
              // senha guardada e campo vazio ao salvar MANTÉM a atual.
              _field(
                'Password',
                _pass,
                obscure: true,
                hint: _editing && widget.initial!.savePassword
                    ? '*******'
                    : null,
              ),
              _switchRow(
                'Use SSL/TLS',
                _isSrv || _useTls,
                (v) {
                  if (!_isSrv) setState(() => _useTls = v);
                },
                hint: _isSrv
                    ? 'implied by mongodb+srv'
                    : 'managed DBs (RDS, Atlas…) usually require it',
              ),
            ],
            // Guardrails dos agentes (CLI). GUI nunca é bloqueada.
            _switchRow(
              'Allow writes (agents)',
              _allowWrites,
              (v) => setState(() => _allowWrites = v),
              hint: 'off = agents can only read via CLI',
            ),
            _switchRow(
              'Visible to agents',
              _visibleToAgents,
              (v) => setState(() => _visibleToAgents = v),
              hint: 'off = hidden from the CLI, GUI only',
            ),
            if (_testing || _testOk != null) ...[
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                  Expanded(
                    child: Text(
                      _testing
                          ? 'Testing connection…'
                          : _testOk!
                          ? 'Connection OK'
                          : (_testMessage ?? 'Connection failed'),
                      style: typo.label.copyWith(
                        fontSize: 11.5,
                        color: _testing
                            ? colors.text3
                            : _testOk!
                            ? colors.online
                            : colors.error,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (_editing) ...[
          DestructiveButton(
            onPressed: () => Navigator.of(
              context,
            ).pop(const DbConnectionDialogResult.deleted()),
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
          onPressed: () => Navigator.of(context).pop(
            DbConnectionDialogResult.saved(
              _build(),
              _pass.text.isEmpty ? null : _pass.text,
            ),
          ),
          child: Text(_editing ? 'Save' : 'Add'),
        ),
      ],
    );
  }
}
