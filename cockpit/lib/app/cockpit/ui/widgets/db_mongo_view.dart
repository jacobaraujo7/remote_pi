import 'dart:convert';

import 'package:cockpit/app/cockpit/domain/entities/db_connection.dart';
import 'package:cockpit/app/cockpit/domain/entities/db_result.dart';
import 'package:cockpit/app/cockpit/domain/services/mongo_browse_service.dart';
import 'package:cockpit/app/cockpit/ui/session/mongo_browser_session.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/database_viewmodel.dart';
import 'package:cockpit/app/cockpit/ui/widgets/confirm_dialog.dart';
import 'package:cockpit/app/cockpit/ui/widgets/db_engine_icon.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/app_tooltip.dart';
import 'package:cockpit/app/core/ui/widgets/code_editing_controller.dart';
import 'package:cockpit/app/core/ui/widgets/code_highlight.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:flutter/services.dart' show KeyDownEvent, LogicalKeyboardKey;
import 'package:flutter_modular/flutter_modular.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Tab do **collection browser Mongo** (plano 53): filter bar + documentos
/// como cards JSON (relaxed extended JSON íntegro — `{"$oid":…}` round-trip
/// lossless) + CRUD por documento ancorado no `_id`.
class MongoCollectionView extends StatefulWidget {
  const MongoCollectionView({
    super.key,
    required this.session,
    required this.active,
    required this.focused,
    required this.workspaceRoot,
  });

  final MongoBrowserSession session;
  final bool active;
  final bool focused;
  final String workspaceRoot;

  @override
  State<MongoCollectionView> createState() => _MongoCollectionViewState();
}

class _MongoCollectionViewState extends State<MongoCollectionView> {
  late final MongoTabState _view;
  late final CodeEditingController _filter;

  bool _loading = false;

  /// Índice do documento em edição + controller/erro do editor.
  int? _editingIx;
  CodeEditingController? _editingCtrl;
  String? _editingError;

  /// Editor de documento novo (via "+"), null quando fechado.
  CodeEditingController? _draftCtrl;
  String? _draftError;

  static const _encoder = JsonEncoder.withIndent('  ');

  @override
  void initState() {
    super.initState();
    final vm = context.read<DatabaseViewModel>();
    _view = vm.mongoStateFor(widget.session.id);
    // Highlight de JSON no filtro — mesmo controller do editor de código.
    _filter = CodeEditingController(text: _view.filter, language: 'json');
    _view.service.target(
      workspaceRoot: widget.workspaceRoot,
      workspaceId: widget.session.projectId,
      connName: widget.session.connName,
    );
    Future.microtask(
      () => vm.setWorkspace(widget.session.projectId, widget.workspaceRoot),
    );
    widget.session.addListener(_onSessionSeed);
    // Seed pendente do CLI (tab recém-criada) vence o estado salvo.
    final seed = widget.session.takeSeedFilter();
    if (seed != null) {
      _view.filter = seed;
      _filter.text = seed;
      _refresh();
    } else if (!_view.loaded) {
      _refresh();
    }
    _filter.addListener(_onFilterCleared);
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSessionSeed);
    _filter.dispose();
    _editingCtrl?.dispose();
    _draftCtrl?.dispose();
    super.dispose();
  }

  /// CLI semeou filtro com a tab já montada (decisão E: substitui e re-scaneia).
  void _onSessionSeed() {
    final seed = widget.session.takeSeedFilter();
    if (seed == null || !mounted) return;
    _view.filter = seed;
    _filter.text = seed;
    _refresh();
  }

  void _applyFilter() {
    _view.filter = _filter.text.trim();
    _refresh();
  }

  void _onFilterCleared() {
    if (_filter.text.isEmpty && _view.filter.isNotEmpty && !_loading) {
      _applyFilter();
    }
  }

  // ── dados ──────────────────────────────────────────────────────────────────

  Future<void> _refresh() async {
    setState(() {
      _view
        ..docs = []
        ..hasMore = false
        ..error = null;
      _closeEditors();
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final page = await _view.service.find(
        widget.session.collection,
        filterJson: _view.filter,
        skip: _view.docs.length,
      );
      if (!mounted) return;
      setState(() {
        _view
          ..docs = [..._view.docs, ...page]
          ..hasMore = page.length >= MongoBrowseService.pageSize
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

  void _closeEditors() {
    _editingIx = null;
    _editingCtrl?.dispose();
    _editingCtrl = null;
    _editingError = null;
    _draftCtrl?.dispose();
    _draftCtrl = null;
    _draftError = null;
  }

  // ── CRUD ───────────────────────────────────────────────────────────────────

  void _startEdit(int ix) {
    setState(() {
      _closeEditors();
      _editingIx = ix;
      _editingCtrl = CodeEditingController(
        text: _encoder.convert(_view.docs[ix]),
        language: 'json',
      );
    });
  }

  Future<void> _commitEdit() async {
    final ix = _editingIx;
    final text = _editingCtrl?.text ?? '';
    if (ix == null) return;
    final Map<String, dynamic> doc;
    try {
      doc = MongoBrowseService.parseDocument(text);
      await _view.service.replaceOne(widget.session.collection, text);
    } on DbQueryException catch (e) {
      // Erro fica no editor — o texto digitado não se perde.
      if (mounted) setState(() => _editingError = e.message);
      return;
    }
    if (!mounted) return;
    setState(() {
      _view.docs[ix] = doc;
      _closeEditors();
      _view.error = null;
    });
  }

  Future<void> _delete(int ix) async {
    final doc = _view.docs[ix];
    final id = doc['_id'];
    final ok = await showConfirmDialog(
      context,
      title: 'Delete document',
      message:
          'Delete the document with _id ${_idLabel(doc)} '
          'from "${widget.session.collection}"?',
      confirmLabel: 'Delete',
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      await _view.service.deleteOne(widget.session.collection, id);
      if (!mounted) return;
      setState(() {
        _view.docs.removeAt(ix);
        _view.error = null;
      });
    } on DbQueryException catch (e) {
      if (mounted) setState(() => _view.error = e.message);
    }
  }

  void _openDraft() {
    setState(() {
      _closeEditors();
      _draftCtrl = CodeEditingController(text: '{\n  \n}', language: 'json');
    });
  }

  Future<void> _commitDraft() async {
    final text = _draftCtrl?.text ?? '';
    try {
      await _view.service.insertOne(widget.session.collection, text);
    } on DbQueryException catch (e) {
      if (mounted) setState(() => _draftError = e.message);
      return;
    }
    if (!mounted) return;
    setState(() {
      _closeEditors();
      _view.error = null;
    });
    // Recarrega a página — o servidor pode ter gerado o `_id`.
    await _refresh();
  }

  /// `_id` curto pro cabeçalho do card (`{"$oid": "abc…"}` → `abc…`).
  static String _idLabel(Map<String, dynamic> doc) {
    final id = doc['_id'];
    if (id is Map && id.length == 1) return '${id.values.first}';
    return jsonEncode(id);
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
          Expanded(child: _list(context)),
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
          DbEngineIcon(DbEngine.mongo, size: 14),
          const SizedBox(width: 7),
          Text(
            '${widget.session.connName} / ${widget.session.collection}',
            style: typo.label.copyWith(fontSize: 12, color: colors.text2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: TextField(
                controller: _filter,
                style: typo.mono.copyWith(fontSize: 11.5, color: colors.text),
                placeholder: Text(
                  'Filter — JSON, e.g. {"status": "active"}',
                  style: typo.mono.copyWith(
                    fontSize: 11.5,
                    color: colors.text4,
                  ),
                ),
                features: [
                  InputFeature.leading(
                    HoverTap(
                      onTap: _applyFilter,
                      padding: const EdgeInsets.all(2),
                      child: Icon(Icons.search, size: 13, color: colors.text3),
                    ),
                  ),
                  const InputFeature.clear(),
                ],
                onSubmitted: (_) => _applyFilter(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${_view.docs.length} doc${_view.docs.length == 1 ? '' : 's'}'
            '${_view.hasMore ? '+' : ''}',
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
            message: 'Insert document',
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

  Widget _list(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    final docs = _view.docs;
    final showEmpty =
        docs.isEmpty && _view.loaded && !_loading && _draftCtrl == null;
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: (_draftCtrl == null ? 0 : 1) + docs.length + 1,
      itemBuilder: (context, i) {
        var ix = i;
        if (_draftCtrl != null) {
          if (ix == 0) return _draftCard(context);
          ix -= 1;
        }
        if (ix < docs.length) return _docCard(context, ix);
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
            padding: const EdgeInsets.all(8),
            child: Text(
              _view.filter.isEmpty
                  ? 'No documents in this collection.'
                  : 'No documents match this filter.',
              style: typo.label.copyWith(fontSize: 11.5, color: colors.text3),
            ),
          );
        }
        if (!_view.hasMore) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.all(8),
          child: Center(
            child: OutlineButton(
              onPressed: _loadMore,
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

  Widget _docCard(BuildContext context, int ix) {
    final colors = context.colors;
    final typo = context.typo;
    final doc = _view.docs[ix];
    final editing = _editingIx == ix;

    final Widget body;
    if (editing) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _escapable(
            onCancel: () => setState(_closeEditors),
            child: TextField(
              controller: _editingCtrl,
              maxLines: 20,
              minLines: 3,
              style: typo.mono.copyWith(fontSize: 12, color: colors.text),
            ),
          ),
          if (_editingError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _editingError!,
                style: typo.mono.copyWith(fontSize: 11, color: colors.error),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlineButton(
                onPressed: () => setState(_closeEditors),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 6),
              PrimaryButton(onPressed: _commitEdit, child: const Text('Save')),
            ],
          ),
        ],
      );
    } else {
      final json = _encoder.convert(doc);
      final style = typo.mono.copyWith(
        fontSize: 12,
        height: 1.4,
        color: colors.text2,
      );
      final span = buildCodeSpan(
        context,
        source: json,
        language: 'json',
        baseStyle: style,
      );
      body = span == null
          ? SelectableText(json, style: style)
          : SelectableText.rich(span, style: style);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: colors.panel2,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(10, 4, 6, 4),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '_id: ${_idLabel(doc)}',
                    overflow: TextOverflow.ellipsis,
                    style: typo.mono.copyWith(
                      fontSize: 10.5,
                      color: colors.text3,
                    ),
                  ),
                ),
                if (!editing) ...[
                  AppTooltip(
                    message: 'Edit',
                    child: HoverTap(
                      onTap: () => _startEdit(ix),
                      padding: const EdgeInsets.all(3),
                      child: Icon(
                        Icons.edit_outlined,
                        size: 13,
                        color: colors.text4,
                      ),
                    ),
                  ),
                  AppTooltip(
                    message: 'Delete',
                    child: HoverTap(
                      onTap: () => _delete(ix),
                      padding: const EdgeInsets.all(3),
                      child: Icon(
                        Icons.delete_outline,
                        size: 13,
                        color: colors.text4,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.all(10), child: body),
        ],
      ),
    );
  }

  Widget _draftCard(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.accentSoft.withValues(alpha: 0.25),
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(7),
      ),
      child: _escapable(
        onCancel: () => setState(_closeEditors),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _draftCtrl,
              maxLines: 20,
              minLines: 3,
              autofocus: true,
              style: typo.mono.copyWith(fontSize: 12, color: colors.text),
            ),
            if (_draftError != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _draftError!,
                  style: typo.mono.copyWith(fontSize: 11, color: colors.error),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlineButton(
                  onPressed: () => setState(_closeEditors),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 6),
                PrimaryButton(
                  onPressed: _commitDraft,
                  child: const Text('Insert'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

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
