import 'dart:async';

import 'package:cockpit/app/cockpit/domain/entities/db_result.dart';
import 'package:cockpit/app/cockpit/domain/entities/redis_key.dart';
import 'package:cockpit/app/cockpit/ui/session/redis_browser_session.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/database_viewmodel.dart';
import 'package:cockpit/app/cockpit/ui/widgets/confirm_dialog.dart';
import 'package:cockpit/app/cockpit/ui/widgets/db_engine_icon.dart';
import 'package:cockpit/app/cockpit/domain/entities/db_connection.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/app_menu.dart';
import 'package:cockpit/app/core/ui/widgets/app_tooltip.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:flutter/services.dart' show KeyDownEvent, LogicalKeyboardKey;
import 'package:flutter_modular/flutter_modular.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Tab da **tabela Redis** (plano 52): a tabela editável é a interface única —
/// sem editor de comando. Toolbar (pattern/refresh/+/contador) + linhas
/// key/value/type/ttl com commit imediato por célula:
/// - STRING e TTL editam inline (Enter/blur commita, Esc cancela);
/// - compostos (HASH/LIST/SET/ZSET) expandem com o valor **completo** antes de
///   permitir salvar (decisão C — nunca editar sobre preview truncado);
/// - paginação por SCAN (decisão E), "Load more" enquanto houver cursor.
class RedisTableView extends StatefulWidget {
  const RedisTableView({
    super.key,
    required this.session,
    required this.active,
    required this.focused,
    required this.workspaceRoot,
  });

  final RedisBrowserSession session;
  final bool active;
  final bool focused;
  final String workspaceRoot;

  @override
  State<RedisTableView> createState() => _RedisTableViewState();
}

const double _kKeyWidth = 170;
const double _kTypeWidth = 78;
const double _kTtlWidth = 64;
const double _kRowHeight = 27;

class _RedisTableViewState extends State<RedisTableView> {
  late final RedisTabState _view;
  late final TextEditingController _pattern;

  bool _loading = false;

  /// Chave em edição inline (STRING) + controller do campo.
  String? _editingKey;
  TextEditingController? _editingCtrl;
  bool _editingBusy = false;

  /// Chave com TTL em edição.
  String? _ttlKey;
  TextEditingController? _ttlCtrl;

  /// Chave em rename (edição da célula key).
  String? _renameKey;
  TextEditingController? _renameCtrl;

  /// Chave expandida (composto) + controller/erro do editor JSON.
  String? _expandedKey;
  TextEditingController? _expandedCtrl;
  String? _expandedError;
  bool _expandedLoading = false;

  /// Linha nova (via "+"), null quando fechada.
  _NewKeyDraft? _draft;

  /// Feedback de escrita: chave que "pisca" confirmação.
  String? _flashKey;
  Timer? _flashTimer;

  @override
  void initState() {
    super.initState();
    final vm = context.read<DatabaseViewModel>();
    _view = vm.redisStateFor(widget.session.id);
    _pattern = TextEditingController(text: _view.pattern)
      ..addListener(_onPatternCleared);
    _view.service.target(
      workspaceRoot: widget.workspaceRoot,
      workspaceId: widget.session.projectId,
      connName: widget.session.connName,
    );
    // Registro de conexões carregado mesmo sem o painel aberto.
    Future.microtask(
      () => vm.setWorkspace(widget.session.projectId, widget.workspaceRoot),
    );
    widget.session.addListener(_onSessionSeed);
    // Pattern semeado pelo CLI (`cockpit redis browse`) vence o estado salvo.
    final seed = widget.session.takeSeedPattern();
    if (seed != null) {
      _view.pattern = seed;
      _pattern.text = seed;
      _refresh();
    } else if (!_view.loaded) {
      _refresh();
    }
  }

  /// CLI semeou pattern com a tab já montada (decisão E do plano 53:
  /// substitui o filtro atual e re-scaneia).
  void _onSessionSeed() {
    final seed = widget.session.takeSeedPattern();
    if (seed == null || !mounted) return;
    _view.pattern = seed;
    _pattern.text = seed;
    _refresh();
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSessionSeed);
    _flashTimer?.cancel();
    _pattern.dispose();
    _editingCtrl?.dispose();
    _ttlCtrl?.dispose();
    _renameCtrl?.dispose();
    _expandedCtrl?.dispose();
    _draft?.dispose();
    super.dispose();
  }

  /// Aplica o texto do campo como pattern e re-scaneia.
  void _applyPattern() {
    _view.pattern = _pattern.text.trim();
    _refresh();
  }

  /// O "X" do campo só limpa o texto — este listener detecta o esvaziamento
  /// com um filtro ativo e re-scaneia sem filtro.
  void _onPatternCleared() {
    if (_pattern.text.isEmpty && _view.pattern.isNotEmpty && !_loading) {
      _applyPattern();
    }
  }

  // ── dados ──────────────────────────────────────────────────────────────────

  Future<void> _refresh() async {
    setState(() {
      _view
        ..entries = []
        ..cursor = '0'
        ..error = null;
      _closeEditors();
    });
    await _loadMore(reset: true);
  }

  Future<void> _loadMore({bool reset = false}) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final page = await _view.service.scan(
        pattern: _view.pattern,
        cursor: reset ? '0' : _view.cursor,
      );
      if (!mounted) return;
      setState(() {
        _view
          ..entries = [..._view.entries, ...page.entries]
          ..cursor = page.cursor
          ..loaded = true
          ..error = null;
      });
    } on DbQueryException catch (e) {
      if (!mounted) return;
      setState(() => _view.error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Pós-escrita: re-lê a chave e substitui (ou remove) a linha.
  Future<void> _refreshEntry(String key) async {
    try {
      final fresh = await _view.service.refreshEntry(key);
      if (!mounted) return;
      setState(() {
        final ix = _view.entries.indexWhere((e) => e.key == key);
        if (ix < 0) return;
        if (fresh == null) {
          _view.entries.removeAt(ix);
        } else {
          _view.entries[ix] = fresh;
        }
      });
    } on DbQueryException catch (e) {
      if (mounted) setState(() => _view.error = e.message);
    }
  }

  void _flash(String key) {
    _flashTimer?.cancel();
    setState(() => _flashKey = key);
    _flashTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _flashKey = null);
    });
  }

  void _closeEditors() {
    _editingKey = null;
    _editingCtrl?.dispose();
    _editingCtrl = null;
    _editingBusy = false;
    _ttlKey = null;
    _ttlCtrl?.dispose();
    _ttlCtrl = null;
    _renameKey = null;
    _renameCtrl?.dispose();
    _renameCtrl = null;
    _expandedKey = null;
    _expandedCtrl?.dispose();
    _expandedCtrl = null;
    _expandedError = null;
    _expandedLoading = false;
  }

  /// Executa [write] com feedback: sucesso pisca a linha e re-lê a entrada;
  /// falha mostra o erro no banner (a linha volta ao valor do servidor).
  Future<bool> _commit(String key, Future<void> Function() write) async {
    try {
      await write();
      if (!mounted) return false;
      setState(() => _view.error = null);
      await _refreshEntry(key);
      if (mounted) _flash(key);
      return true;
    } on DbQueryException catch (e) {
      if (!mounted) return false;
      setState(() => _view.error = e.message);
      await _refreshEntry(key);
      return false;
    }
  }

  // ── edição STRING inline ───────────────────────────────────────────────────

  Future<void> _startStringEdit(RedisKeyEntry entry) async {
    // Preview pode estar truncado — edição parte SEMPRE do valor completo.
    setState(() {
      _closeEditors();
      _editingKey = entry.key;
      _editingBusy = true;
    });
    try {
      final full = await _view.service.readFull(entry.key, entry.kind);
      if (!mounted || _editingKey != entry.key) return;
      setState(() {
        _editingCtrl = TextEditingController(text: full);
        _editingBusy = false;
      });
    } on DbQueryException catch (e) {
      if (!mounted) return;
      setState(() {
        _view.error = e.message;
        _closeEditors();
      });
    }
  }

  Future<void> _commitStringEdit() async {
    final key = _editingKey;
    final ctrl = _editingCtrl;
    if (key == null || ctrl == null) return;
    final value = ctrl.text;
    setState(_closeEditors);
    await _commit(key, () => _view.service.writeString(key, value));
  }

  // ── rename da key ──────────────────────────────────────────────────────────

  void _startKeyEdit(RedisKeyEntry entry) {
    setState(() {
      _closeEditors();
      _renameKey = entry.key;
      _renameCtrl = TextEditingController(text: entry.key);
    });
  }

  Future<void> _commitKeyEdit() async {
    final oldKey = _renameKey;
    final newKey = _renameCtrl?.text.trim() ?? '';
    if (oldKey == null) return;
    setState(_closeEditors);
    if (newKey.isEmpty || newKey == oldKey) return;
    try {
      await _view.service.rename(oldKey, newKey);
    } on DbQueryException catch (e) {
      if (mounted) setState(() => _view.error = e.message);
      return;
    }
    if (!mounted) return;
    setState(() => _view.error = null);
    // Substitui a linha antiga pela chave nova, na mesma posição.
    try {
      final fresh = await _view.service.refreshEntry(newKey);
      if (!mounted) return;
      setState(() {
        final ix = _view.entries.indexWhere((e) => e.key == oldKey);
        if (ix < 0) return;
        if (fresh == null) {
          _view.entries.removeAt(ix);
        } else {
          _view.entries[ix] = fresh;
        }
      });
      _flash(newKey);
    } on DbQueryException catch (e) {
      if (mounted) setState(() => _view.error = e.message);
    }
  }

  // ── edição TTL ─────────────────────────────────────────────────────────────

  void _startTtlEdit(RedisKeyEntry entry) {
    setState(() {
      _closeEditors();
      _ttlKey = entry.key;
      _ttlCtrl = TextEditingController(
        text: entry.ttl < 0 ? '' : '${entry.ttl}',
      );
    });
  }

  Future<void> _commitTtlEdit() async {
    final key = _ttlKey;
    final raw = _ttlCtrl?.text.trim() ?? '';
    if (key == null) return;
    setState(_closeEditors);
    final seconds = raw.isEmpty || raw == '-1' ? null : int.tryParse(raw);
    if (raw.isNotEmpty && raw != '-1' && seconds == null) {
      setState(() => _view.error = 'TTL must be a number of seconds.');
      return;
    }
    await _commit(key, () => _view.service.setTtl(key, seconds));
  }

  // ── composto (expansão) ────────────────────────────────────────────────────

  Future<void> _toggleExpanded(RedisKeyEntry entry) async {
    if (_expandedKey == entry.key) {
      setState(_closeEditors);
      return;
    }
    setState(() {
      _closeEditors();
      _expandedKey = entry.key;
      _expandedLoading = true;
    });
    try {
      final full = await _view.service.readFull(entry.key, entry.kind);
      if (!mounted || _expandedKey != entry.key) return;
      setState(() {
        _expandedCtrl = TextEditingController(text: full);
        _expandedLoading = false;
      });
    } on DbQueryException catch (e) {
      if (!mounted) return;
      setState(() {
        _view.error = e.message;
        _closeEditors();
      });
    }
  }

  Future<void> _commitExpanded(RedisKeyEntry entry) async {
    final text = _expandedCtrl?.text ?? '';
    final ok = await _commitComposite(entry, text);
    if (ok && mounted) setState(_closeEditors);
  }

  Future<bool> _commitComposite(RedisKeyEntry entry, String text) async {
    try {
      await _view.service.writeComposite(entry.key, entry.kind, text);
    } on DbQueryException catch (e) {
      // Erro de validação/comando fica DENTRO da expansão (o valor digitado
      // não se perde); o banner é pros erros de página.
      if (mounted) setState(() => _expandedError = e.message);
      return false;
    }
    if (!mounted) return false;
    setState(() => _expandedError = null);
    await _refreshEntry(entry.key);
    if (mounted) _flash(entry.key);
    return true;
  }

  // ── delete / criar ─────────────────────────────────────────────────────────

  Future<void> _delete(RedisKeyEntry entry) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete key',
      message: 'Delete "${entry.key}" from this Redis database?',
      confirmLabel: 'Delete',
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      await _view.service.delete(entry.key);
      if (!mounted) return;
      setState(() {
        _view.entries.removeWhere((e) => e.key == entry.key);
        _view.error = null;
      });
    } on DbQueryException catch (e) {
      if (mounted) setState(() => _view.error = e.message);
    }
  }

  void _openDraft() {
    setState(() {
      _closeEditors();
      _draft?.dispose();
      _draft = _NewKeyDraft();
    });
  }

  Future<void> _commitDraft() async {
    final d = _draft;
    if (d == null) return;
    final key = d.key.text.trim();
    final ttl = int.tryParse(d.ttl.text.trim());
    try {
      await _view.service.create(key, d.kind, d.value.text, ttl: ttl);
    } on DbQueryException catch (e) {
      if (mounted) setState(() => d.error = e.message);
      return;
    }
    if (!mounted) return;
    setState(() {
      d.dispose();
      _draft = null;
      _view.error = null;
    });
    // Insere a chave nova no topo da tabela.
    try {
      final fresh = await _view.service.refreshEntry(key);
      if (!mounted || fresh == null) return;
      setState(() => _view.entries = [fresh, ..._view.entries]);
      _flash(key);
    } on DbQueryException catch (e) {
      if (mounted) setState(() => _view.error = e.message);
    }
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ColoredBox(
      color: colors.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _toolbar(context),
          if (_view.error != null) _errorBanner(context, _view.error!),
          _header(context),
          Expanded(child: _table(context)),
        ],
      ),
    );
  }

  Widget _toolbar(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: colors.panel2,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          DbEngineIcon(DbEngine.redis, size: 14),
          const SizedBox(width: 7),
          Text(
            widget.session.connName,
            style: typo.label.copyWith(fontSize: 12, color: colors.text2),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 240,
            child: TextField(
              controller: _pattern,
              style: typo.mono.copyWith(fontSize: 11.5, color: colors.text),
              placeholder: Text(
                'Search — pattern, e.g. user:*',
                style: typo.mono.copyWith(fontSize: 11.5, color: colors.text4),
              ),
              features: [
                // Lupa: aplica o pattern (mesmo efeito do Enter).
                InputFeature.leading(
                  HoverTap(
                    onTap: _applyPattern,
                    padding: const EdgeInsets.all(2),
                    child: Icon(Icons.search, size: 13, color: colors.text3),
                  ),
                ),
                // X: limpa o texto (o listener do controller re-scaneia).
                const InputFeature.clear(),
              ],
              onSubmitted: (_) => _applyPattern(),
            ),
          ),
          const Spacer(),
          Text(
            '${_view.entries.length} key${_view.entries.length == 1 ? '' : 's'}'
            '${_view.cursor == '0' ? '' : '+'}',
            style: typo.label.copyWith(fontSize: 11, color: colors.text3),
          ),
          const SizedBox(width: 8),
          AppTooltip(
            message: 'Refresh',
            child: HoverTap(
              onTap: _loading ? null : _refresh,
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.refresh, size: 15, color: colors.text3),
            ),
          ),
          AppTooltip(
            message: 'New key',
            child: HoverTap(
              onTap: _openDraft,
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.add, size: 15, color: colors.text3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorBanner(BuildContext context, String message) {
    final colors = context.colors;
    final typo = context.typo;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      color: colors.error.withValues(alpha: 0.12),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 13, color: colors.error),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: typo.mono.copyWith(fontSize: 11, color: colors.error),
            ),
          ),
          HoverTap(
            onTap: () => setState(() => _view.error = null),
            padding: const EdgeInsets.all(2),
            child: Icon(Icons.close, size: 13, color: colors.error),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    TextStyle style = typo.label.copyWith(
      fontSize: 10.5,
      letterSpacing: 0.6,
      color: colors.text3,
    );
    return Container(
      height: 26,
      decoration: BoxDecoration(
        color: colors.panel2,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 10),
          SizedBox(
            width: _kKeyWidth,
            child: Text('KEY', style: style),
          ),
          Expanded(child: Text('VALUE', style: style)),
          SizedBox(
            width: _kTypeWidth,
            child: Text('TYPE', style: style),
          ),
          SizedBox(
            width: _kTtlWidth,
            child: Text('TTL', style: style),
          ),
          const SizedBox(width: 30),
        ],
      ),
    );
  }

  Widget _table(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    final entries = _view.entries;
    final hasMore = _view.cursor != '0';
    final showEmpty =
        entries.isEmpty && _view.loaded && !_loading && _draft == null;
    return ListView.builder(
      // draft (0) + linhas + (load more / spinner / empty) footer
      itemCount: (_draft == null ? 0 : 1) + entries.length + 1,
      itemBuilder: (context, i) {
        var ix = i;
        if (_draft != null) {
          if (ix == 0) return _draftRow(context, _draft!);
          ix -= 1;
        }
        if (ix < entries.length) return _row(context, entries[ix], ix);
        // Footer.
        if (_loading) {
          return const Padding(
            padding: EdgeInsets.all(14),
            child: Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(),
              ),
            ),
          );
        }
        if (showEmpty) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _view.pattern.isEmpty
                  ? 'No keys in this database.'
                  : 'No keys match "${_view.pattern}".',
              style: typo.label.copyWith(fontSize: 11.5, color: colors.text3),
            ),
          );
        }
        if (!hasMore) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.all(8),
          child: Center(
            child: OutlineButton(
              onPressed: () => _loadMore(),
              child: Text(
                'Load more',
                style: typo.label.copyWith(fontSize: 11.5),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _row(BuildContext context, RedisKeyEntry entry, int index) {
    final colors = context.colors;
    final typo = context.typo;
    final mono = typo.mono.copyWith(fontSize: 12, color: colors.text2);
    final flashing = _flashKey == entry.key;
    final expanded = _expandedKey == entry.key;

    final Widget valueCell;
    if (_editingKey == entry.key) {
      valueCell = _editingBusy
          ? Text('…', style: mono)
          : _inlineField(
              context,
              controller: _editingCtrl!,
              onCommit: _commitStringEdit,
              onCancel: () => setState(_closeEditors),
            );
    } else {
      final canEdit = entry.kind.editable;
      valueCell = HoverTap(
        onTap: !canEdit
            ? null
            : entry.kind == RedisValueKind.string
            ? () => _startStringEdit(entry)
            : () => _toggleExpanded(entry),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Text(
          entry.preview.replaceAll('\n', '␤'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: mono,
        ),
      );
    }

    final Widget ttlCell;
    if (_ttlKey == entry.key) {
      ttlCell = _inlineField(
        context,
        controller: _ttlCtrl!,
        onCommit: _commitTtlEdit,
        onCancel: () => setState(_closeEditors),
      );
    } else {
      ttlCell = HoverTap(
        onTap: () => _startTtlEdit(entry),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Text(
          entry.ttl < 0 ? '∞' : '${entry.ttl}',
          style: mono.copyWith(
            color: entry.ttl < 0 ? colors.text4 : colors.text2,
          ),
        ),
      );
    }

    final row = Container(
      constraints: const BoxConstraints(minHeight: _kRowHeight),
      decoration: BoxDecoration(
        color: flashing
            ? colors.accent.withValues(alpha: 0.14)
            : index.isOdd
            ? colors.panel2.withValues(alpha: 0.35)
            : null,
        border: Border(
          bottom: BorderSide(color: colors.border.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 10),
          SizedBox(
            width: _kKeyWidth,
            child: _renameKey == entry.key
                ? _inlineField(
                    context,
                    controller: _renameCtrl!,
                    onCommit: _commitKeyEdit,
                    onCancel: () => setState(_closeEditors),
                  )
                : AppTooltip(
                    message: entry.key,
                    child: HoverTap(
                      onTap: () => _startKeyEdit(entry),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      child: Text(
                        entry.key,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: mono.copyWith(color: colors.text),
                      ),
                    ),
                  ),
          ),
          Expanded(child: valueCell),
          SizedBox(
            width: _kTypeWidth,
            child: Text(
              entry.kind.label,
              style: typo.label.copyWith(fontSize: 10.5, color: colors.text3),
            ),
          ),
          SizedBox(width: _kTtlWidth, child: ttlCell),
          SizedBox(
            width: 30,
            child: HoverTap(
              onTap: () => _delete(entry),
              padding: const EdgeInsets.all(3),
              child: Icon(Icons.delete_outline, size: 13, color: colors.text4),
            ),
          ),
        ],
      ),
    );

    if (!expanded) return row;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [row, _expandedEditor(context, entry)],
    );
  }

  /// Editor expandido de composto: valor completo em JSON + Save/Cancel.
  Widget _expandedEditor(BuildContext context, RedisKeyEntry entry) {
    final colors = context.colors;
    final typo = context.typo;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: colors.panel3,
        border: Border(
          bottom: BorderSide(color: colors.border.withValues(alpha: 0.5)),
        ),
      ),
      child: _expandedLoading
          ? Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'Loading full value…',
                style: typo.label.copyWith(fontSize: 11, color: colors.text3),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _escapable(
                  onCancel: () => setState(_closeEditors),
                  child: TextField(
                    controller: _expandedCtrl,
                    maxLines: 12,
                    minLines: 3,
                    style: typo.mono.copyWith(fontSize: 12, color: colors.text),
                  ),
                ),
                if (_expandedError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _expandedError!,
                      style: typo.mono.copyWith(
                        fontSize: 11,
                        color: colors.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Spacer(),
                    OutlineButton(
                      onPressed: () => setState(_closeEditors),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 6),
                    PrimaryButton(
                      onPressed: () => _commitExpanded(entry),
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  /// Linha de criação (via "+"): key + type + value + ttl + Add/Cancel.
  Widget _draftRow(BuildContext context, _NewKeyDraft d) {
    final colors = context.colors;
    final typo = context.typo;
    final mono = typo.mono.copyWith(fontSize: 12, color: colors.text);
    Widget field(TextEditingController ctrl, String hint, {int maxLines = 1}) =>
        TextField(
          controller: ctrl,
          maxLines: maxLines,
          style: mono,
          placeholder: Text(
            hint,
            style: typo.mono.copyWith(fontSize: 11.5, color: colors.text4),
          ),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: colors.accentSoft.withValues(alpha: 0.25),
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: _escapable(
        onCancel: () => setState(() {
          d.dispose();
          _draft = null;
        }),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SizedBox(width: _kKeyWidth + 30, child: field(d.key, 'key')),
                const SizedBox(width: 8),
                // Seletor de tipo — SÓ aqui (decisão D: type é imutável em
                // chave existente).
                Builder(
                  builder: (anchor) => OutlineButton(
                    onPressed: () async {
                      final kind = await showAppMenu<RedisValueKind>(
                        anchor,
                        items: [
                          for (final k in RedisValueKind.values)
                            if (k != RedisValueKind.other)
                              AppMenuItem(value: k, label: k.label),
                        ],
                      );
                      if (kind != null) setState(() => d.kind = kind);
                    },
                    child: Text(
                      d.kind.label,
                      style: typo.label.copyWith(fontSize: 11),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(width: 110, child: field(d.ttl, 'ttl (s, optional)')),
              ],
            ),
            const SizedBox(height: 6),
            field(
              d.value,
              d.kind == RedisValueKind.string
                  ? 'value'
                  : switch (d.kind) {
                      RedisValueKind.hash => '{"field": "value"}',
                      RedisValueKind.zset =>
                        '[{"value": "member", "score": 1}]',
                      _ => '["item1", "item2"]',
                    },
              maxLines: d.kind == RedisValueKind.string ? 1 : 6,
            ),
            if (d.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  d.error!,
                  style: typo.mono.copyWith(fontSize: 11, color: colors.error),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlineButton(
                  onPressed: () => setState(() {
                    d.dispose();
                    _draft = null;
                  }),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 6),
                PrimaryButton(
                  onPressed: _commitDraft,
                  child: const Text('Add key'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Campo inline de célula: Enter commita, Esc cancela, blur commita.
  Widget _inlineField(
    BuildContext context, {
    required TextEditingController controller,
    required VoidCallback onCommit,
    required VoidCallback onCancel,
  }) {
    final colors = context.colors;
    final typo = context.typo;
    return _escapable(
      onCancel: onCancel,
      child: Focus(
        onFocusChange: (has) {
          // Blur commita (padrão de tabela editável). O Esc já removeu o
          // editor antes do blur, então não colide.
          if (!has) onCommit();
        },
        child: TextField(
          controller: controller,
          autofocus: true,
          style: typo.mono.copyWith(fontSize: 12, color: colors.text),
          onSubmitted: (_) => onCommit(),
        ),
      ),
    );
  }

  /// Esc cancela a edição em qualquer campo descendente.
  Widget _escapable({required VoidCallback onCancel, required Widget child}) {
    return Focus(
      canRequestFocus: false,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          onCancel();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: child,
    );
  }
}

/// Rascunho da chave nova ("+" da toolbar).
class _NewKeyDraft {
  final key = TextEditingController();
  final value = TextEditingController();
  final ttl = TextEditingController();
  RedisValueKind kind = RedisValueKind.string;
  String? error;

  void dispose() {
    key.dispose();
    value.dispose();
    ttl.dispose();
  }
}
