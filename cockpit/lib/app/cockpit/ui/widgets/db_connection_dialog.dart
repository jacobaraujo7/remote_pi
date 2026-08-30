import 'package:cockpit_core/cockpit_core.dart';
import 'dart:async';
import 'dart:io';

import 'package:cockpit/app/cockpit/domain/entities/db_connection.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/database_viewmodel.dart';
import 'package:cockpit/app/cockpit/ui/widgets/db_engine_icon.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:cockpit/app/core/utils/path_utils.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Resultado do [DbConnectionDialog]: salvo (com senha opcional pro cofre),
/// excluído, ou `null` (cancelado).
class DbConnectionDialogResult {
  const DbConnectionDialogResult.saved(
    this.connection,
    this.password, {
    this.sshPassphrase,
  }) : deleted = false;
  const DbConnectionDialogResult.deleted()
    : connection = null,
      password = null,
      sshPassphrase = null,
      deleted = true;

  final DbConnection? connection;

  /// Senha digitada (vai pro cofre via VM). `null` = não mexer na guardada.
  final String? password;

  /// Passphrase da chave SSH digitada (plano 54). Mesma semântica do
  /// [password]: `null` = não mexer na guardada.
  final String? sshPassphrase;
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

  /// Guardrails do caminho dos agentes (CLI): escrita opt-in + visibilidade.
  /// GUI nunca é gated. Defaults seguros: read-only e visível.
  late bool _allowWrites = widget.initial?.access == DbAccess.readwrite;
  late bool _visibleToAgents = widget.initial?.agents ?? true;
  bool? _testOk;
  String? _testMessage;
  bool _testing = false;

  final _name = TextEditingController();
  final _file = TextEditingController();
  final _pass = TextEditingController();

  // --- Túnel SSH (plano 54) ---------------------------------------------
  /// Seção expandida no dialog. Não implica ter túnel: o túnel só existe se
  /// host/user/key estiverem preenchidos ([_buildSsh]).
  bool _sshOpen = false;
  late bool _saveSshPassphrase = widget.initial?.ssh?.savePassphrase ?? false;

  /// `true` quando a chave escolhida é encriptada — é o que decide se o campo
  /// de passphrase aparece. Chave limpa = conexão sem segredo nenhum.
  bool _sshKeyEncrypted = false;

  final _sshHost = TextEditingController();
  final _sshPort = TextEditingController();
  final _sshUser = TextEditingController();
  final _sshKey = TextEditingController();
  final _sshPassphrase = TextEditingController();

  /// Connection string — a **única** forma de editar conexão de rede.
  ///
  /// A `DbConnection` já guarda URL como forma canônica, então um formulário
  /// decomposto seria a camada com perda: ele não expressa `mongodb+srv://`,
  /// params proprietários de driver, múltiplos hosts nem nada que não tenhamos
  /// modelado. Colar a URL inteira é o caminho sem perda — e é o que as
  /// pessoas já têm em mãos.
  final _uri = TextEditingController();

  /// Altura do campo de connection string, arrastável pelo canto.
  double _uriHeight = _uriDefaultHeight;

  /// Cabe uma URL de Atlas com params sem precisar rolar.
  static const _uriDefaultHeight = 96.0;
  static const _uriMinHeight = 58.0;
  static const _uriMaxHeight = 260.0;

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
      _uri.text = c.url;
    }
    final ssh = c.ssh;
    if (ssh != null) {
      _sshOpen = true;
      _sshHost.text = ssh.host;
      _sshPort.text = '${ssh.port}';
      _sshUser.text = ssh.user;
      _sshKey.text = ssh.keyPath;
      unawaited(_refreshKeyEncryption());
    }
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _file,
      _pass,
      _uri,
      _sshHost,
      _sshPort,
      _sshUser,
      _sshKey,
      _sshPassphrase,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Reavalia se a chave atual pede passphrase. Chamado ao abrir a seção em
  /// modo edição e a cada troca de arquivo — é o que faz o campo aparecer/
  /// sumir sem o usuário precisar saber o formato da chave.
  Future<void> _refreshKeyEncryption() async {
    final path = _sshKey.text.trim();
    final encrypted = path.isEmpty
        ? false
        : await widget.viewModel.sshKeyNeedsPassphrase(path);
    if (!mounted || encrypted == _sshKeyEncrypted) return;
    setState(() => _sshKeyEncrypted = encrypted);
  }

  /// Abre a seção SSH. Na primeira abertura, semeia user e chave com defaults
  /// razoáveis — quem tunela quase sempre usa a chave padrão e o mesmo login
  /// do SO, e digitar isso à toa é atrito puro.
  Future<void> _openSshSection() async {
    setState(() => _sshOpen = true);
    if (_sshUser.text.isEmpty) {
      final me =
          Platform.environment['USER'] ?? Platform.environment['USERNAME'];
      if (me != null && me.isNotEmpty) _sshUser.text = me;
    }
    if (_sshKey.text.isEmpty) {
      final suggested = await widget.viewModel.defaultSshKeyPath();
      if (!mounted || suggested == null) return;
      _sshKey.text = suggested;
      await _refreshKeyEncryption();
      if (mounted) setState(() {});
    }
  }

  /// Escolhe a chave privada no picker nativo. Abre em `~/.ssh` quando existe
  /// e re-encurta pra `~/…`, que é a forma portável guardada no JSON.
  Future<void> _pickSshKey() async {
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    final sshDir = home == null ? null : '$home/.ssh';
    final result = await FilePicker.platform.pickFiles(
      dialogTitle:
          context.t.cockpit.dbConnectionDialog.choosePrivateKeyDialogTitle,
      // Nativo, não canônico: o diálogo do Windows rejeita `/` (ver
      // NativeFolderPicker) e não abre.
      initialDirectory: sshDir != null && Directory(sshDir).existsSync()
          ? toNativePath(sshDir)
          : null,
      type: FileType.any,
    );
    if (!mounted || result == null) return;
    final path = result.files.single.path;
    if (path == null) return;
    _sshKey.text = home != null && path.startsWith('$home/')
        ? '~${path.substring(home.length)}'
        : path;
    // Trocou de chave: a passphrase antiga não vale mais.
    _sshPassphrase.clear();
    await _refreshKeyEncryption();
    if (mounted) setState(() {});
  }

  /// Monta o túnel a partir dos campos — `null` quando a seção está fechada
  /// ou incompleta. Túnel pela metade não é salvo: viraria uma conexão que
  /// falha no uso sem explicar por quê.
  SshTunnelConfig? _buildSsh() {
    if (!_sshOpen || !_engine.supportsSshTunnel) return null;
    final host = _sshHost.text.trim();
    final user = _sshUser.text.trim();
    final key = _sshKey.text.trim();
    if (host.isEmpty || user.isEmpty || key.isEmpty) return null;
    return SshTunnelConfig(
      host: host,
      port: int.tryParse(_sshPort.text.trim()) ?? SshTunnelConfig.defaultPort,
      user: user,
      keyPath: key,
      // Chave limpa nunca marca o flag: não há segredo pra guardar.
      savePassphrase: _sshKeyEncrypted && _saveSshPassphrase,
    );
  }

  /// Conexão montada a partir do modo ativo, ou `null` se a connection string
  /// não parseia (Save/Test ficam desabilitados nesse caso).
  DbConnection? _tryBuild() {
    if (_engine == DbEngine.sqlite) return _build();
    final raw = _uri.text.trim();
    if (raw.isEmpty) return null;
    try {
      var url = raw;
      String? extracted;
      // "Save Password" ON com senha na URI: tira do texto e manda pro cofre —
      // mesma semântica do modo campos, sem senha em claro no databases.json.
      if (_savePassword) {
        final parsed = Uri.parse(url);
        final info = parsed.userInfo;
        final colon = info.indexOf(':');
        if (colon >= 0) {
          extracted = Uri.decodeComponent(info.substring(colon + 1));
          url = parsed.replace(userInfo: info.substring(0, colon)).toString();
        }
      }
      // Digitada no campo obscurecido ganha da que veio na URL.
      _uriPassword = _pass.text.isNotEmpty ? _pass.text : extracted;
      return DbConnection.fromJson({
        'name': _name.text.trim().isEmpty
            ? 'new-connection'
            : _name.text.trim(),
        'url': url,
        'savePassword': _savePassword,
        'access': (_allowWrites ? DbAccess.readwrite : DbAccess.read).name,
        'agents': _visibleToAgents,
        if (_buildSsh() != null) 'ssh': _buildSsh()!.toJson(),
      });
    } on Object {
      return null;
    }
  }

  /// Senha extraída da URI no último [_tryBuild] (só quando `savePassword`).
  String? _uriPassword;

  /// Senha a devolver pro cofre: a digitada no campo obscurecido ou a que foi
  /// extraída da URL.
  String? get _passwordResult =>
      _engine == DbEngine.sqlite ? null : _uriPassword;

  /// Só SQLite passa por aqui — rede é sempre connection string.
  DbConnection _build() => DbConnection.sqlite(
    _name.text.trim().isEmpty ? 'new-connection' : _name.text.trim(),
    _file.text.trim(),
    access: _allowWrites ? DbAccess.readwrite : DbAccess.read,
    agents: _visibleToAgents,
  );

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
      dialogTitle: context.t.cockpit.dbConnectionDialog.chooseFileTitle,
      initialDirectory: root == null ? null : toNativePath(root),
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
    final built = _tryBuild();
    if (built == null) {
      setState(() {
        _testing = false;
        _testOk = false;
        _testMessage = context.t.cockpit.dbConnectionDialog.invalidUrl;
      });
      return;
    }
    final error = await widget.viewModel.test(
      built,
      password: _pass.text.isEmpty ? null : _pass.text,
      // Passphrase digitada agora vale mais que a do cofre — senão "Test"
      // depois de trocar a chave validaria a passphrase antiga.
      sshPassphrase: _sshPassphrase.text.isEmpty ? null : _sshPassphrase.text,
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
            context.t.cockpit.dbConnectionDialog.file,
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
                    hasFile
                        ? _file.text
                        : context
                              .t
                              .cockpit
                              .dbConnectionDialog
                              .chooseFilePlaceholder,
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

  /// Campo da connection string: a URL inteira, do jeito que o driver a
  /// recebe. É o caminho sem perda — aceita `mongodb+srv://`, replica set,
  /// params proprietários e tudo que o formulário não modela.
  Widget _uriField(AppColors colors, AppTypography typo) {
    final invalid = _uri.text.trim().isNotEmpty && _tryBuild() == null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.t.cockpit.dbConnectionDialog.connectionString,
            style: typo.label.copyWith(fontSize: 11, color: colors.text3),
          ),
          const SizedBox(height: 4),
          // Altura arrastável: connection string de Atlas/replica set passa
          // fácil de 200 caracteres, e ler uma URL truncada é o jeito mais
          // rápido de colar errado.
          Stack(
            children: [
              SizedBox(
                height: _uriHeight,
                child: TextField(
                  controller: _uri,
                  // `expands` exige maxLines/minLines nulos — a altura passa a
                  // ser a do SizedBox.
                  maxLines: null,
                  minLines: null,
                  expands: true,
                  // Sem isto o texto fica centralizado verticalmente quando o
                  // campo cresce — com `expands` o default é center.
                  textAlignVertical: TextAlignVertical.top,
                  onChanged: (_) => setState(() {
                    _testOk = null;
                    _testMessage = null;
                  }),
                  style: typo.mono.copyWith(fontSize: 12, color: colors.text),
                  placeholder: Text(
                    '${_engine.scheme}://user:password@host:'
                    '${_engine.defaultPort}/database',
                    style: typo.mono.copyWith(
                      fontSize: 12,
                      color: colors.text4,
                    ),
                  ),
                  border: Border.all(
                    color: invalid ? colors.error : colors.border,
                  ),
                  borderRadius: BorderRadius.circular(6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                ),
              ),
              Positioned(right: 2, bottom: 2, child: _uriResizeHandle(colors)),
            ],
          ),
          if (invalid) ...[
            const SizedBox(height: 4),
            Text(
              context.t.cockpit.dbConnectionDialog.invalidUrl,
              style: typo.label.copyWith(fontSize: 10.5, color: colors.error),
            ),
          ],
        ],
      ),
    );
  }

  /// Alça de redimensionamento no canto do campo — mesmo gesto do `resize` de
  /// um `<textarea>`: arrasta pra baixo cresce, pra cima encolhe.
  Widget _uriResizeHandle(AppColors colors) => MouseRegion(
    cursor: SystemMouseCursors.resizeUpDown,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (d) => setState(() {
        _uriHeight = (_uriHeight + d.delta.dy).clamp(
          _uriMinHeight,
          _uriMaxHeight,
        );
      }),
      // Duplo clique volta ao tamanho padrão — desfazer sem mira.
      onDoubleTap: () => setState(() => _uriHeight = _uriDefaultHeight),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: CustomPaint(
          size: const Size(10, 10),
          painter: _ResizeGripPainter(colors.text4),
        ),
      ),
    ),
  );

  /// Seção "SSH Tunnel" (plano 54). **Inline, não sub-dialog**: o usuário
  /// precisa ver Host/Port do banco enquanto configura o túnel, porque com
  /// SSH o campo Host passa a significar "localhost *do servidor SSH*" — é a
  /// confusão nº 1 do recurso e a única defesa é a proximidade visual.
  Widget _sshSection(AppColors colors, AppTypography typo) {
    if (!_sshOpen) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: HoverTap(
          onTap: _openSshSection,
          border: Border.all(color: colors.border),
          borderRadius: const BorderRadius.all(Radius.circular(6)),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            children: [
              Icon(Icons.lock_outline, size: 13, color: colors.text3),
              const SizedBox(width: 8),
              Text(
                context.t.cockpit.dbConnectionDialog.sshTunnel,
                style: typo.label.copyWith(fontSize: 12, color: colors.text2),
              ),
              const Spacer(),
              Icon(Icons.expand_more, size: 14, color: colors.text3),
            ],
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 2),
      decoration: BoxDecoration(
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lock_outline, size: 13, color: colors.text3),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.t.cockpit.dbConnectionDialog.sshTunnel,
                  style: typo.label.copyWith(fontSize: 12, color: colors.text2),
                ),
              ),
              HoverTap(
                onTap: () => setState(() {
                  _sshOpen = false;
                  _sshHost.clear();
                  _sshPort.clear();
                  _sshUser.clear();
                  _sshKey.clear();
                  _sshPassphrase.clear();
                  _sshKeyEncrypted = false;
                }),
                padding: const EdgeInsets.all(2),
                child: Icon(Icons.close, size: 13, color: colors.text3),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _field(context.t.cockpit.dbConnectionDialog.sshHost, _sshHost),
          Row(
            children: [
              Expanded(
                child: _field(
                  context.t.cockpit.dbConnectionDialog.sshPort,
                  _sshPort,
                  hint: '${SshTunnelConfig.defaultPort}',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _field(
                  context.t.cockpit.dbConnectionDialog.sshUser,
                  _sshUser,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.t.cockpit.dbConnectionDialog.privateKey,
                  style: typo.label.copyWith(fontSize: 11, color: colors.text3),
                ),
                const SizedBox(height: 4),
                HoverTap(
                  onTap: _pickSshKey,
                  border: Border.all(color: colors.border),
                  borderRadius: const BorderRadius.all(Radius.circular(6)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _sshKey.text.isEmpty
                              ? context
                                    .t
                                    .cockpit
                                    .dbConnectionDialog
                                    .choosePrivateKeyPlaceholder
                              : _sshKey.text,
                          overflow: TextOverflow.ellipsis,
                          style: typo.mono.copyWith(
                            fontSize: 12.5,
                            color: _sshKey.text.isEmpty
                                ? colors.text4
                                : colors.text,
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
          ),
          // Só aparece quando a chave é de fato encriptada — chave limpa é o
          // caminho feliz e não deve nem sugerir que há segredo envolvido.
          if (_sshKeyEncrypted) ...[
            _field(
              context.t.cockpit.dbConnectionDialog.keyPassphrase,
              _sshPassphrase,
              obscure: true,
              hint: _editing && (widget.initial?.ssh?.savePassphrase ?? false)
                  ? '*******'
                  : null,
            ),
            _switchRow(
              context.t.cockpit.dbConnectionDialog.savePassphrase,
              _saveSshPassphrase,
              (v) => setState(() => _saveSshPassphrase = v),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    // Largura fixa: sem isso o `Spacer` da barra de ações (Delete à esquerda,
    // modo edição) esticaria o dialog até a largura da tela. Larga o bastante
    // pra uma connection string caber sem quebrar em três linhas — é o campo
    // que manda no dimensionamento agora.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 660),
        child: _dialog(colors, typo),
      ),
    );
  }

  Widget _dialog(AppColors colors, AppTypography typo) {
    final tr = context.t.cockpit.dbConnectionDialog;
    return AlertDialog(
      title: Row(
        children: [
          DbEngineIcon(_engine, size: 18),
          const SizedBox(width: 8),
          Text(
            _editing ? tr.editTitle : tr.newTitle,
            style: typo.title.copyWith(fontSize: 15, color: colors.text),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _field(tr.name, _name, hint: 'dev-local'),
            if (_engine == DbEngine.sqlite)
              _fileField()
            else ...[
              _uriField(colors, typo),
              _switchRow(
                tr.savePassword,
                _savePassword,
                (v) => setState(() => _savePassword = v),
              ),
              // Campo obscurecido quando a senha vai pro cofre: a caixa da
              // connection string mostra o texto na tela, e quem liga esse
              // switch está justamente evitando senha em claro. Preenchido,
              // tem precedência sobre a que estiver na URL.
              if (_savePassword) ...[
                _field(
                  context.t.cockpit.dbConnectionDialog.password,
                  _pass,
                  obscure: true,
                  hint: _editing && widget.initial!.savePassword
                      ? '*******'
                      : null,
                ),
                // Workspace remoto: o segredo vai pro cofre do HOST, não pro
                // desta máquina (plano 62). Dizer isso importa porque as
                // garantias são outras — e porque é o que faz a conexão
                // funcionar de qualquer cliente, que era a expectativa.
                if (widget.viewModel.isRemoteWorkspace)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      context.t.cockpit.dbConnectionDialog.passwordOnHost,
                      style: typo.label.copyWith(fontSize: 10.5, color: colors.text4),
                    ),
                  ),
              ],
              _sshSection(colors, typo),
            ],
            // Guardrails dos agentes (CLI). GUI nunca é bloqueada.
            _switchRow(
              tr.allowWrites,
              _allowWrites,
              (v) => setState(() => _allowWrites = v),
              hint: tr.allowWritesHint,
            ),
            _switchRow(
              tr.visibleToAgents,
              _visibleToAgents,
              (v) => setState(() => _visibleToAgents = v),
              hint: tr.visibleToAgentsHint,
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
                          ? tr.testing
                          : _testOk!
                          ? tr.connectionOk
                          : (_testMessage ?? tr.connectionFailed),
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
            child: Text(context.t.common.delete),
          ),
          const Spacer(),
        ],
        GhostButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.t.common.cancel),
        ),
        OutlineButton(
          // URI que não parseia: nada a testar nem a salvar.
          onPressed: _testing || _tryBuild() == null ? null : _test,
          child: Text(context.t.common.test),
        ),
        PrimaryButton(
          onPressed: _tryBuild() == null
              ? null
              : () {
                  final conn = _tryBuild()!;
                  Navigator.of(context).pop(
                    DbConnectionDialogResult.saved(
                      conn,
                      _passwordResult,
                      sshPassphrase: _sshPassphrase.text.isEmpty
                          ? null
                          : _sshPassphrase.text,
                    ),
                  );
                },
          child: Text(_editing ? context.t.common.save : context.t.common.add),
        ),
      ],
    );
  }
}

/// Duas riscas diagonais no canto — a convenção visual de "arrastável" que
/// navegador e editor usam em textarea.
class _ResizeGripPainter extends CustomPainter {
  const _ResizeGripPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    for (final inset in [0.0, 4.0]) {
      canvas.drawLine(
        Offset(size.width - inset, size.height),
        Offset(size.width, size.height - inset),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ResizeGripPainter old) => old.color != color;
}
