import 'dart:async';
import 'dart:io' show File, Platform;
import 'dart:typed_data';

import 'package:cockpit/app/cockpit/domain/entities/notebook_document.dart';
import 'package:cockpit/app/cockpit/ui/session/notebook_session.dart';
import 'package:cockpit/app/cockpit/ui/session/document_host.dart';
import 'package:cockpit/app/cockpit/ui/widgets/confirm_dialog.dart';
import 'package:cockpit/app/cockpit/ui/widgets/kanban_board_view.dart'
    show kanbanDisplayPath;
import 'package:cockpit/app/core/domain/result.dart';
import 'package:cockpit/app/core/ui/file_operation_error_message.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/app_menu.dart';
import 'package:cockpit/app/core/ui/widgets/app_tooltip.dart';
import 'package:cockpit/app/core/ui/widgets/markdown_editing_controller.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:cockpit/app/core/utils/path_utils.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:flutter/material.dart'
    as material
    show TextField, InputDecoration, InputBorder;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Tab de um caderno `nome.notebook/` (plano 62, passo 4). Protótipo visual:
/// três colunas — notas (busca, ordenadas por `updated`) | nota ativa (preview
/// markdown, com edição do fonte) | tags com contagem (clicar filtra).
///
/// Lê a pasta pelo VM (`listChildren` + `readTextAt`), então funciona local e
/// remoto. Estado de leitura mora aqui; a sessão só carrega a identidade.
class NotebookView extends StatefulWidget {
  const NotebookView({
    super.key,
    required this.session,
    required this.active,
    required this.focused,
    required this.workspaceRoot,
  });

  final NotebookSession session;

  /// Raiz do workspace — o cabeçalho mostra o caminho do caderno relativo a
  /// ela (mesma regra do `.kanban`).
  final String workspaceRoot;
  final bool active;
  final bool focused;

  @override
  State<NotebookView> createState() => _NotebookViewState();
}

class _NotebookViewState extends State<NotebookView> {
  List<NotebookNote> _notes = const [];
  bool _loading = true;
  String? _selectedPath;
  final Set<String> _collapsed = <String>{};
  final TextEditingController _tagInput = TextEditingController();
  final TextEditingController _titleCtrl = TextEditingController();
  final FocusNode _titleFocus = FocusNode(debugLabel: 'notebookTitle');
  String _query = '';

  bool _dirty = false;
  bool _saving = false;
  late final MarkdownEditingController _editor = MarkdownEditingController(
    imageBaseDir: widget.session.path,
  );
  final FocusNode _editorFocus = FocusNode(debugLabel: 'notebookEditor');
  final TextEditingController _search = TextEditingController();
  int _seenReload = 0;
  StreamSubscription<void>? _watch;
  Timer? _watchDebounce;

  /// Autosave: reinicia a cada tecla; grava quando o usuário para de digitar.
  Timer? _autosave;
  Timer? _titleAutosave;

  /// Texto após um `[[` aberto na linha do cursor (autocomplete de nota);
  /// `null` = sem sugestão aberta.
  String? _linkQuery;

  /// Coluna de notas recolhida (botão no cabeçalho, ao lado do caminho).
  bool _listCollapsed = false;
  static const _autosaveDelay = Duration(milliseconds: 1500);

  DocumentHost get _vm => documentHostOf(context);

  @override
  void initState() {
    super.initState();
    _seenReload = widget.session.reloadTick;
    widget.session.addListener(_onSession);
    _editor
      ..addListener(_onEdited)
      ..onWikiLink = _openLinkedNote;
    _titleCtrl.addListener(_onTitleEdited);
    // Filtro segue o controller (o botão limpar zera o texto sem onChanged).
    _search.addListener(_onSearchChanged);
    _load();
    // Nota escrita pelo agente (ou pelo Obsidian) aparece sozinha.
    _watch = _vm.watchFolder(widget.session.path).listen((_) {
      _watchDebounce?.cancel();
      _watchDebounce = Timer(const Duration(milliseconds: 200), _load);
    });
  }

  @override
  void dispose() {
    _flush();
    _watchDebounce?.cancel();
    _watch?.cancel();
    widget.session.removeListener(_onSession);
    _editor
      ..removeListener(_onEdited)
      ..dispose();
    _editorFocus.dispose();
    _search
      ..removeListener(_onSearchChanged)
      ..dispose();
    _tagInput.dispose();
    _titleAutosave?.cancel();
    _titleCtrl
      ..removeListener(_onTitleEdited)
      ..dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  void _onSession() {
    if (widget.session.reloadTick != _seenReload) {
      _seenReload = widget.session.reloadTick;
      _load();
    }
  }

  void _onEdited() {
    final sel = _selected;
    final dirty = sel != null && _editor.text != sel.body;
    if (dirty != _dirty) setState(() => _dirty = dirty);
    _autosave?.cancel();
    if (dirty) _autosave = Timer(_autosaveDelay, _save);
    // Autocomplete de [[link]]: `[[` aberto antes do cursor, sem `]]` ainda.
    final selNow = _editor.selection;
    String? q;
    if (selNow.isValid && selNow.isCollapsed) {
      final before = _editor.text.substring(0, selNow.baseOffset);
      final m = RegExp(r'\[\[([^\]\n]*)$').firstMatch(before);
      if (m != null) q = m.group(1)!;
    }
    if (q != _linkQuery) setState(() => _linkQuery = q);
  }

  /// Sugestões pro `[[` aberto: títulos que contêm o texto digitado (a nota
  /// atual fora), no máximo 8.
  List<NotebookNote> get _linkSuggestions {
    final q = _linkQuery;
    if (q == null) return const [];
    final lower = q.toLowerCase();
    return _notes
        .where(
          (n) =>
              n.path != _selectedPath &&
              (lower.isEmpty || n.title.toLowerCase().contains(lower)),
        )
        .take(8)
        .toList();
  }

  /// Completa o `[[` aberto com [title] e fecha o link.
  void _completeLink(String title) {
    final sel = _editor.selection;
    if (!sel.isValid) return;
    final before = _editor.text.substring(0, sel.baseOffset);
    final open = before.lastIndexOf('[[');
    if (open < 0) return;
    final ins = '[[${_singleLine(title)}]] ';
    _editor.value = TextEditingValue(
      text: _editor.text.replaceRange(open, sel.baseOffset, ins),
      selection: TextSelection.collapsed(offset: open + ins.length),
    );
    setState(() => _linkQuery = null);
    _editorFocus.requestFocus();
  }

  static String _singleLine(String t) => t.replaceAll('\n', ' ').trim();

  NotebookNote? _noteByTitle(String title) {
    final t = _singleLine(title).toLowerCase();
    for (final n in _notes) {
      if (_singleLine(n.title).toLowerCase() == t) return n;
    }
    return null;
  }

  /// Clique num `[[Título]]`: abre a nota; se não existe, cria com esse título.
  Future<void> _openLinkedNote(String title) async {
    final existing = _noteByTitle(title);
    if (existing != null) {
      await _select(existing);
      return;
    }
    final now = DateTime.now();
    final clean = _singleLine(title);
    var path = joinPath(
      widget.session.path,
      NotebookNote.fileNameFor(clean, now),
    );
    final taken = _notes.map((n) => n.path).toSet();
    var i = 2;
    while (taken.contains(path)) {
      path = joinPath(
        widget.session.path,
        NotebookNote.fileNameFor('$clean $i', now),
      );
      i++;
    }
    final ok = await _vm.writeTextAt(
      path,
      NotebookNote.template(title: clean, tags: const [], now: now),
    );
    if (!mounted || !ok) return;
    _selectedPath = path;
    await _load();
    if (mounted) _editorFocus.requestFocus();
  }

  /// Notas que apontam pra [n] via `[[título]]`.
  List<NotebookNote> _backlinksOf(NotebookNote n) {
    final t = _singleLine(n.title).toLowerCase();
    return _notes.where((o) {
      if (o.path == n.path) return false;
      for (final m in MarkdownEditingController.wikiLink.allMatches(o.body)) {
        if (_singleLine(m.group(1)!).toLowerCase() == t) return true;
      }
      return false;
    }).toList();
  }

  /// Botão "link pra nota" da barra: menu com busca; insere `[[Título]]`.
  Future<void> _pickNoteLink(Offset at) async {
    final others = _notes.where((n) => n.path != _selectedPath).toList();
    if (others.isEmpty) return;
    final choice = await showAppMenu<String>(
      context,
      globalPosition: at,
      searchHint: context.t.cockpit.notebook.format.noteLinkSearch,
      searchThreshold: 6,
      items: [
        for (final n in others)
          AppMenuItem(
            value: n.path,
            label: _singleLine(n.title),
            icon: Icons.description_outlined,
          ),
      ],
    );
    if (!mounted || choice == null) return;
    final n = _notes.firstWhere((x) => x.path == choice);
    _insertInline('[[${_singleLine(n.title)}]] ');
  }

  /// Insere [snippet] no cursor sem forçar quebra de linha antes.
  void _insertInline(String snippet) {
    final t = _editor.text;
    var sel = _editor.selection;
    if (!sel.isValid) sel = TextSelection.collapsed(offset: t.length);
    _editor.value = TextEditingValue(
      text: t.substring(0, sel.start) + snippet + t.substring(sel.end),
      selection: TextSelection.collapsed(offset: sel.start + snippet.length),
    );
    _editorFocus.requestFocus();
  }

  /// Botão "imagem" da barra: file picker → `_assets/` + `![]()`.
  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _imageExts.toList(),
      allowMultiple: true,
    );
    if (!mounted || result == null) return;
    for (final f in result.files) {
      final path = f.path;
      if (path != null) await _addImageFile(path);
    }
  }

  void _onSearchChanged() {
    if (_search.text != _query) setState(() => _query = _search.text);
  }

  /// Título: mesmo debounce do corpo; grava quando parar de digitar.
  void _onTitleEdited() {
    final sel = _selected;
    if (sel == null || !_titleFocus.hasFocus) return;
    _titleAutosave?.cancel();
    if (_titleCtrl.text.trim() != sel.title) {
      _titleAutosave = Timer(_autosaveDelay, _commitTitle);
    }
  }

  /// Grava agora o que estiver pendente (troca de nota, fechar a aba).
  void _flush() {
    _autosave?.cancel();
    _titleAutosave?.cancel();
    if (_dirty && !_saving) _save();
    if (_selected != null && _titleCtrl.text.trim() != _selected!.title) {
      _commitTitle();
    }
  }

  NotebookNote? get _selected {
    for (final n in _notes) {
      if (n.path == _selectedPath) return n;
    }
    return null;
  }

  Future<void> _load() async {
    final vm = _vm;
    final children = await vm.listChildren(widget.session.path);
    final notes = <NotebookNote>[];
    for (final c in children) {
      if (c.isDirectory || !c.name.toLowerCase().endsWith('.md')) continue;
      final raw = await vm.readTextAt(c.path);
      if (raw == null) continue;
      notes.add(NotebookNote.parse(c.path, raw));
    }
    notes.sort((a, b) {
      final da = a.sortDate, db = b.sortDate;
      if (da == null && db == null) return a.title.compareTo(b.title);
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });
    if (!mounted) return;
    // O corpo em que o editor se baseou, ANTES de adotar a leitura nova. É a
    // comparação com ele (e não a flag `_dirty`) que diz se há edição
    // pendente: o `_save` chama este `_load` com a flag ainda ligada, e ela
    // ficava presa, então a nota aberta nunca mais adotava o disco.
    final base = _selected?.body;
    setState(() {
      _notes = notes;
      _loading = false;
      if (_selected == null && notes.isNotEmpty) {
        _selectedPath = notes.first.path;
      }
      if (base == null || _editor.text == base) {
        _syncEditor(); // nada pendente: adota o disco
      } else {
        // Edição em curso não é sobrescrita por um reload do disco; só
        // realinha a flag (o save que acabou de gravar a deixa limpa).
        final sel = _selected;
        _dirty = sel != null && _editor.text != sel.body;
      }
    });
  }

  void _syncEditor() {
    final sel = _selected;
    final body = sel?.body ?? '';
    if (_editor.text != body) _editor.text = body;
    _dirty = false;
    // O título é sempre um campo; só realinha com o disco quando o usuário
    // não está digitando nele.
    if (!_titleFocus.hasFocus) _titleCtrl.text = sel?.title ?? '';
  }

  Future<void> _select(NotebookNote n) async {
    if (n.path == _selectedPath) return;
    // Autosave: o que estiver pendente vai pro disco antes de trocar.
    if (_dirty) {
      _autosave?.cancel();
      await _save();
      if (!mounted) return;
    }
    if (_selected != null && _titleCtrl.text.trim() != _selected!.title) {
      await _commitTitle();
      if (!mounted) return;
    }
    setState(() {
      _selectedPath = n.path;
      _syncEditor();
    });
  }

  List<NotebookNote> get _visible {
    final q = _query.trim().toLowerCase();
    return _notes.where((n) {
      if (q.isEmpty) return true;
      return n.title.toLowerCase().contains(q) ||
          n.body.toLowerCase().contains(q) ||
          n.tags.any((t) => t.contains(q));
    }).toList();
  }

  /// Agrupa as notas visíveis por tag (uma nota com N tags aparece em N
  /// grupos, como os smart folders do Apple Notes). Sem tag vem primeiro;
  /// depois `agent`; o resto por ordem alfabética.
  List<(String, List<NotebookNote>)> get _groups {
    final m = <String, List<NotebookNote>>{};
    for (final n in _visible) {
      for (final t in n.tags) {
        (m[t] ??= []).add(n);
      }
    }
    final keys = m.keys.toList()
      ..sort((a, b) {
        int rank(String t) => t == kUntagged ? 0 : (t == kAgentTag ? 1 : 2);
        final r = rank(a).compareTo(rank(b));
        return r != 0 ? r : a.compareTo(b);
      });
    return [for (final k in keys) (k, m[k]!)];
  }

  Future<void> _setTags(List<String> tags) async {
    final sel = _selected;
    if (sel == null || _saving) return;
    final base = NotebookNote.replaceBody(sel.raw, _editor.text);
    setState(() => _saving = true);
    final content = NotebookNote.touchUpdated(
      NotebookNote.setTags(base, tags),
      DateTime.now(),
    );
    final ok = await _vm.writeTextAt(sel.path, content);
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) {
      await showConfirmDialog(
        context,
        title: context.t.cockpit.notebook.saveFailed,
        message: sel.fileName,
        confirmLabel: context.t.common.ok,
      );
      return;
    }
    await _load();
  }

  /// Botão direito / toque longo no cabeçalho de um grupo: renomear ou
  /// apagar a tag em **todas** as notas que a têm. "Sem tag" não tem menu.
  Future<void> _tagMenu(String tag, Offset position) async {
    if (tag == kUntagged) return;
    final tr = context.t.cockpit.notebook;
    final choice = await showAppMenu<String>(
      context,
      globalPosition: position,
      items: [
        AppMenuItem(
          value: 'rename',
          label: tr.renameTag,
          icon: Icons.drive_file_rename_outline,
        ),
        AppMenuItem(
          value: 'delete',
          label: tr.deleteTag,
          icon: Icons.delete_outline,
          danger: true,
        ),
      ],
    );
    if (!mounted || choice == null) return;
    if (choice == 'rename') {
      final ctrl = TextEditingController(text: tag);
      final next = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr.renameTag),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: TextField(
              controller: ctrl,
              autofocus: true,
              onSubmitted: (v) => Navigator.of(ctx).pop(v),
            ),
          ),
          actions: [
            GhostButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(ctx.t.common.cancel),
            ),
            PrimaryButton(
              onPressed: () => Navigator.of(ctx).pop(ctrl.text),
              child: Text(ctx.t.common.save),
            ),
          ],
        ),
      );
      if (!mounted || next == null) return;
      final clean = next.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '-');
      if (clean.isEmpty || clean == tag) return;
      await _retagAll(tag, clean);
    } else {
      final ok = await showConfirmDialog(
        context,
        title: tr.deleteTag,
        message: tr.deleteTagConfirm(
          name: tag,
          count: _notes.where((n) => n.tags.contains(tag)).length,
        ),
        confirmLabel: context.t.common.delete,
        danger: true,
      );
      if (!ok || !mounted) return;
      await _retagAll(tag, null);
    }
  }

  /// Troca [from] por [to] (ou remove, se `null`) em todas as notas.
  Future<void> _retagAll(String from, String? to) async {
    _flush();
    for (final n in _notes) {
      if (!n.tags.contains(from)) continue;
      final tags = <String>[
        for (final t in n.tags)
          if (t == from) ?to else if (t != kUntagged) t,
      ];
      final content = NotebookNote.touchUpdated(
        NotebookNote.setTags(n.raw, tags),
        DateTime.now(),
      );
      await _vm.writeTextAt(n.path, content);
      if (!mounted) return;
    }
    _collapsed.remove(from);
    await _load();
  }

  Future<void> _noteMenu(NotebookNote n, Offset position) async {
    final tr = context.t.cockpit.notebook;
    final choice = await showAppMenu<String>(
      context,
      globalPosition: position,
      items: [
        AppMenuItem(
          value: 'delete',
          label: tr.deleteNote,
          icon: Icons.delete_outline,
          danger: true,
        ),
      ],
    );
    if (!mounted || choice != 'delete') return;
    final ok = await showConfirmDialog(
      context,
      title: tr.deleteNote,
      message: tr.deleteConfirm(name: n.title),
      confirmLabel: context.t.common.delete,
      danger: true,
    );
    if (!ok || !mounted) return;
    final r = await _vm.deletePath(n.path);
    if (!mounted) return;
    if (r case Failure(:final error)) {
      await showConfirmDialog(
        context,
        title: tr.deleteNote,
        message: fileOperationErrorMessage(context, error),
        confirmLabel: context.t.common.ok,
      );
      return;
    }
    if (_selectedPath == n.path) _selectedPath = null;
    await _load();
  }

  /// Foca o título com tudo selecionado (nota nova: digita por cima de
  /// "Untitled").
  void _focusTitle() {
    final sel = _selected;
    if (sel == null) return;
    _titleCtrl.text = sel.title;
    _titleCtrl.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _titleCtrl.text.length,
    );
    _titleFocus.requestFocus();
  }

  /// Grava o título (autosave, perder o foco ou troca de nota).
  Future<void> _commitTitle() async {
    _titleAutosave?.cancel();
    final sel = _selected;
    final title = _titleCtrl.text.trim();
    if (sel == null || _saving) return;
    if (title.isEmpty) {
      if (!_titleFocus.hasFocus) _titleCtrl.text = sel.title;
      return;
    }
    if (title == sel.title) return;
    final base = NotebookNote.replaceBody(sel.raw, _editor.text);
    setState(() => _saving = true);
    final content = NotebookNote.touchUpdated(
      NotebookNote.setTitle(base, title),
      DateTime.now(),
    );
    final ok = await _vm.writeTextAt(sel.path, content);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) await _load();
  }

  void _addTag(String raw) {
    final sel = _selected;
    final t = raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '-');
    if (sel == null || t.isEmpty) return;
    _tagInput.clear();
    final tags = sel.tags.where((x) => x != kUntagged).toList();
    if (tags.contains(t)) return;
    _setTags([...tags, t]);
  }

  void _removeTag(String t) {
    final sel = _selected;
    if (sel == null) return;
    _setTags(sel.tags.where((x) => x != t && x != kUntagged).toList());
  }

  Future<void> _save() async {
    _autosave?.cancel();
    final sel = _selected;
    if (sel == null || _saving || !_dirty) return;
    setState(() => _saving = true);
    final content = NotebookNote.touchUpdated(
      NotebookNote.replaceBody(sel.raw, _editor.text),
      DateTime.now(),
    );
    final ok = await _vm.writeTextAt(sel.path, content);
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) {
      await showConfirmDialog(
        context,
        title: context.t.cockpit.notebook.saveFailed,
        message: sel.fileName,
        confirmLabel: context.t.common.ok,
      );
      return;
    }
    await _load();
  }

  /// Cria "Untitled" direto (sem diálogo), seleciona e já abre o título pra
  /// edição — o usuário renomeia ali mesmo.
  Future<void> _newNote() async {
    final title = context.t.cockpit.notebook.untitled;
    final now = DateTime.now();
    var path = joinPath(
      widget.session.path,
      NotebookNote.fileNameFor(title, now),
    );
    var i = 2;
    final taken = _notes.map((n) => n.path).toSet();
    while (taken.contains(path)) {
      path = joinPath(
        widget.session.path,
        NotebookNote.fileNameFor('$title $i', now),
      );
      i++;
    }
    final ok = await _vm.writeTextAt(
      path,
      NotebookNote.template(title: title, tags: const [], now: now),
    );
    if (!mounted) return;
    if (!ok) {
      await showConfirmDialog(
        context,
        title: context.t.cockpit.notebook.createFailed,
        message: path,
        confirmLabel: context.t.common.ok,
      );
      return;
    }
    _selectedPath = path;
    await _load();
    if (mounted) _focusTitle();
  }

  // ---- formatação markdown no editor -------------------------------------

  /// Envolve a seleção com [left]/[right] (ou insere o par e deixa o cursor
  /// no meio). Já envolvida → remove (toggle).
  void _wrap(String left, [String? right]) {
    right ??= left;
    final t = _editor.text;
    var sel = _editor.selection;
    if (!sel.isValid) sel = TextSelection.collapsed(offset: t.length);
    final a = sel.start, b = sel.end;
    final inner = t.substring(a, b);
    final before = t.substring(0, a), after = t.substring(b);
    if (before.endsWith(left) && after.startsWith(right)) {
      _editor.value = TextEditingValue(
        text:
            before.substring(0, before.length - left.length) +
            inner +
            after.substring(right.length),
        selection: TextSelection(
          baseOffset: a - left.length,
          extentOffset: b - left.length,
        ),
      );
    } else if (inner.startsWith(left) &&
        inner.endsWith(right) &&
        inner.length >= left.length + right.length) {
      final stripped = inner.substring(
        left.length,
        inner.length - right.length,
      );
      _editor.value = TextEditingValue(
        text: before + stripped + after,
        selection: TextSelection(
          baseOffset: a,
          extentOffset: a + stripped.length,
        ),
      );
    } else {
      _editor.value = TextEditingValue(
        text: '$before$left$inner$right$after',
        selection: TextSelection(
          baseOffset: a + left.length,
          extentOffset: b + left.length,
        ),
      );
    }
    _editorFocus.requestFocus();
  }

  /// Prefixa cada linha da seleção com [prefix] (títulos, listas, citação).
  /// Linhas já prefixadas perdem o prefixo (toggle). [numbered] gera `1. 2.`.
  void _prefixLines(String prefix, {bool numbered = false}) {
    final t = _editor.text;
    var sel = _editor.selection;
    if (!sel.isValid) sel = TextSelection.collapsed(offset: t.length);
    final start =
        t.lastIndexOf('\n', sel.start - 1 < 0 ? 0 : sel.start - 1) + 1;
    var end = t.indexOf('\n', sel.end);
    if (end < 0) end = t.length;
    final block = t.substring(start, end);
    final lines = block.split('\n');
    final allPrefixed = lines.every(
      (l) => numbered ? RegExp(r'^\d+\. ').hasMatch(l) : l.startsWith(prefix),
    );
    final out = <String>[];
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      if (allPrefixed) {
        out.add(
          numbered
              ? l.replaceFirst(RegExp(r'^\d+\. '), '')
              : l.substring(prefix.length),
        );
      } else {
        final clean = l.replaceFirst(
          RegExp(r'^(#{1,6} |[-*] \[[ x]\] |[-*] |\d+\. |> )'),
          '',
        );
        out.add(numbered ? '${i + 1}. $clean' : '$prefix$clean');
      }
    }
    final replaced = out.join('\n');
    // Uma linha só (caso comum: começar uma lista numa linha vazia) → cursor
    // no fim dela, pronto pra digitar. Bloco de várias linhas → fica
    // selecionado pra encadear outra ação.
    final selection = lines.length == 1
        ? TextSelection.collapsed(offset: start + replaced.length)
        : TextSelection(
            baseOffset: start,
            extentOffset: start + replaced.length,
          );
    _editor.value = TextEditingValue(
      text: t.substring(0, start) + replaced + t.substring(end),
      selection: selection,
    );
    _editorFocus.requestFocus();
  }

  void _insertAtCursor(String snippet) {
    final t = _editor.text;
    var sel = _editor.selection;
    if (!sel.isValid) sel = TextSelection.collapsed(offset: t.length);
    final before = t.substring(0, sel.start);
    final needsNl = before.isNotEmpty && !before.endsWith('\n');
    final ins = '${needsNl ? '\n' : ''}$snippet';
    _editor.value = TextEditingValue(
      text: before + ins + t.substring(sel.end),
      selection: TextSelection.collapsed(offset: sel.start + ins.length),
    );
    _editorFocus.requestFocus();
  }

  void _link() => _wrap('[', '](url)');

  // ---- imagens: colar / arrastar → _assets/ ------------------------------

  static const _imageExts = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'svg', 'bmp'};

  String get _assetsDir => joinPath(widget.session.path, '_assets');

  /// Cola: imagem do clipboard vira arquivo em `_assets/` + `![]()`; texto
  /// cola normal no cursor.
  Future<void> _pasteIntoEditor() async {
    final image = await Pasteboard.image;
    if (image != null && image.isNotEmpty) {
      await _addImageBytes(image, 'pasted-${_stampNow()}.png');
      return;
    }
    final files = await Pasteboard.files();
    if (files.isNotEmpty) {
      for (final f in files) {
        await _addImageFile(f);
      }
      return;
    }
    final text = await Pasteboard.text;
    if (text == null || text.isEmpty) return;
    final t = _editor.text;
    var sel = _editor.selection;
    if (!sel.isValid) sel = TextSelection.collapsed(offset: t.length);
    _editor.value = TextEditingValue(
      text: t.substring(0, sel.start) + text + t.substring(sel.end),
      selection: TextSelection.collapsed(offset: sel.start + text.length),
    );
  }

  Future<void> _onDropFiles(List<DropItem> items) async {
    for (final it in items) {
      await _addImageFile(it.path);
    }
  }

  Future<void> _addImageFile(String srcPath) async {
    final name = srcPath.split(Platform.pathSeparator).last;
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    if (!_imageExts.contains(ext)) return;
    Uint8List bytes;
    try {
      bytes = await File(srcPath).readAsBytes();
    } catch (_) {
      return;
    }
    await _addImageBytes(bytes, name);
  }

  Future<void> _addImageBytes(Uint8List bytes, String preferredName) async {
    if (_selected == null) return;
    var name = preferredName.replaceAll(RegExp(r'[^\w.\-]+'), '-');
    var path = joinPath(_assetsDir, name);
    var i = 2;
    while (await File(path).exists()) {
      final dot = name.lastIndexOf('.');
      final stem = dot > 0 ? name.substring(0, dot) : name;
      final ext = dot > 0 ? name.substring(dot) : '';
      path = joinPath(_assetsDir, '$stem-$i$ext');
      i++;
    }
    final ok = await _vm.writeBytesAt(path, bytes);
    if (!mounted) return;
    if (!ok) {
      await showConfirmDialog(
        context,
        title: context.t.cockpit.notebook.imageFailed,
        message: path,
        confirmLabel: context.t.common.ok,
      );
      return;
    }
    final rel = '_assets/${path.split('/').last}';
    _insertAtCursor('![]($rel)\n');
  }

  static String _stampNow() {
    final d = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}${two(d.month)}${two(d.day)}-${two(d.hour)}${two(d.minute)}${two(d.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _save,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
        const SingleActivator(LogicalKeyboardKey.keyB, meta: true): () =>
            _wrap('**'),
        const SingleActivator(LogicalKeyboardKey.keyB, control: true): () =>
            _wrap('**'),
        const SingleActivator(LogicalKeyboardKey.keyI, meta: true): () =>
            _wrap('_'),
        const SingleActivator(LogicalKeyboardKey.keyI, control: true): () =>
            _wrap('_'),
        const SingleActivator(LogicalKeyboardKey.keyE, meta: true): () =>
            _wrap('`'),
        const SingleActivator(LogicalKeyboardKey.keyE, control: true): () =>
            _wrap('`'),
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): _link,
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): _link,
      },
      child: Container(
        color: colors.bg,
        child: Column(
          children: [
            _Header(
              path: kanbanDisplayPath(
                widget.session.path,
                widget.workspaceRoot,
              ),
              onNew: _newNote,
              onReload: _load,
              listCollapsed: _listCollapsed,
              onToggleList: () =>
                  setState(() => _listCollapsed = !_listCollapsed),
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!_listCollapsed)
                    SizedBox(
                      width: 210,
                      child: _NotesColumn(
                        groups: _groups,
                        loading: _loading,
                        hasAny: _notes.isNotEmpty,
                        selectedPath: _selectedPath,
                        collapsed: _collapsed,
                        onToggleGroup: (t) => setState(() {
                          if (!_collapsed.remove(t)) _collapsed.add(t);
                        }),
                        onSelect: _select,
                        onMenu: _noteMenu,
                        onTagMenu: _tagMenu,
                        search: _search,
                      ),
                    ),
                  if (!_listCollapsed)
                    VerticalDivider(width: 1, color: colors.border),
                  Expanded(
                    child: _NoteColumn(
                      note: _selected,
                      dirty: _dirty,
                      saving: _saving,
                      editor: _editor,
                      editorFocus: _editorFocus,
                      tagInput: _tagInput,
                      titleCtrl: _titleCtrl,
                      titleFocus: _titleFocus,
                      onCommitTitle: _commitTitle,
                      onSave: _save,
                      onAddTag: _addTag,
                      onRemoveTag: _removeTag,
                      onDrop: _onDropFiles,
                      onPaste: _pasteIntoEditor,
                      onWrap: _wrap,
                      onPrefix: _prefixLines,
                      onInsert: _insertAtCursor,
                      onLink: _link,
                      onNoteLink: _pickNoteLink,
                      onPickImage: _pickImage,
                      linkSuggestions: _linkSuggestions,
                      onCompleteLink: _completeLink,
                      backlinks: _selected == null
                          ? const []
                          : _backlinksOf(_selected!),
                      onOpenNote: _select,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({
    required this.path,
    required this.listCollapsed,
    required this.onToggleList,
    required this.onNew,
    required this.onReload,
  });

  /// Caminho do caderno relativo ao workspace (ou `~/…`, ou absoluto).
  final String path;
  final bool listCollapsed;
  final VoidCallback onToggleList;
  final VoidCallback onNew;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tr = context.t.cockpit.notebook;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          // Caminho relativo ao workspace, como a barra do `.kanban`. Expanded
          // (não Spacer) pra absorver a sobra e empurrar busca/botões à borda.
          _IconAction(
            icon: listCollapsed
                ? Icons.view_sidebar_outlined
                : Icons.view_sidebar,
            tooltip: listCollapsed ? tr.showList : tr.hideList,
            onTap: onToggleList,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              path,
              overflow: TextOverflow.ellipsis,
              style: context.typo.mono.copyWith(
                fontSize: 10.5,
                color: colors.text3,
              ),
            ),
          ),
          const SizedBox(width: 12),
          const SizedBox(width: 8),
          _IconAction(icon: Icons.refresh, tooltip: tr.reload, onTap: onReload),
          const SizedBox(width: 4),
          HoverTap(
            color: colors.panel2,
            borderRadius: BorderRadius.circular(6),
            onTap: onNew,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  Icon(Icons.add, size: 14, color: colors.text),
                  const SizedBox(width: 6),
                  Text(
                    tr.newNote,
                    style: context.typo.label.copyWith(color: colors.text),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.onTapAt,
  }) : assert(onTap != null || onTapAt != null);
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  /// Variante que recebe a posição global do canto inferior-esquerdo do
  /// botão — pra ancorar um menu nele.
  final ValueChanged<Offset>? onTapAt;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppTooltip(
      message: tooltip,
      child: HoverTap(
        borderRadius: BorderRadius.circular(5),
        onTap: () {
          if (onTapAt != null) {
            final box = context.findRenderObject() as RenderBox?;
            final pos = box == null
                ? Offset.zero
                : box.localToGlobal(Offset(0, box.size.height));
            onTapAt!(pos);
          } else {
            onTap!();
          }
        },
        child: SizedBox(
          width: 28,
          height: 28,
          child: Icon(icon, size: 15, color: colors.text3),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _NotesColumn extends StatelessWidget {
  const _NotesColumn({
    required this.groups,
    required this.loading,
    required this.hasAny,
    required this.selectedPath,
    required this.collapsed,
    required this.onToggleGroup,
    required this.onSelect,
    required this.onMenu,
    required this.onTagMenu,
    required this.search,
  });

  final List<(String, List<NotebookNote>)> groups;
  final bool loading;
  final bool hasAny;
  final String? selectedPath;
  final Set<String> collapsed;
  final ValueChanged<String> onToggleGroup;
  final ValueChanged<NotebookNote> onSelect;
  final void Function(NotebookNote, Offset) onMenu;
  final void Function(String, Offset) onTagMenu;
  final TextEditingController search;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tr = context.t.cockpit.notebook;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Busca no topo da lista: filtra os grupos abaixo.
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: SizedBox(
            height: 28,
            child: TextField(
              controller: search,
              placeholder: Text(tr.searchPlaceholder),
              features: const [
                InputFeature.leading(Icon(Icons.search, size: 14)),
                InputFeature.clear(
                  visibility: InputFeatureVisibility.textNotEmpty,
                ),
              ],
              style: context.typo.label.copyWith(color: colors.text),
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
          ),
        ),
        Expanded(child: _body(context, colors, tr)),
      ],
    );
  }

  Widget _body(
    BuildContext context,
    AppColors colors,
    Translations$cockpit$notebook$en tr,
  ) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (groups.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(14),
        child: Text(
          hasAny ? tr.noMatch : tr.empty,
          style: context.typo.label.copyWith(color: colors.text3),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        for (final (tag, notes) in groups) ...[
          GestureDetector(
            key: ValueKey('group-$tag'),
            onSecondaryTapUp: (d) => onTagMenu(tag, d.globalPosition),
            onLongPressStart: (d) => onTagMenu(tag, d.globalPosition),
            child: HoverTap(
              onTap: () => onToggleGroup(tag),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 10, 4),
                child: Row(
                  children: [
                    Icon(
                      collapsed.contains(tag)
                          ? Icons.chevron_right
                          : Icons.expand_more,
                      size: 14,
                      color: colors.text3,
                    ),
                    const SizedBox(width: 2),
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _tagColor(tag, colors),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        tag == kUntagged ? tr.untagged : tag,
                        overflow: TextOverflow.ellipsis,
                        style: context.typo.label.copyWith(
                          fontSize: 10.5,
                          letterSpacing: 0.6,
                          fontWeight: FontWeight.w600,
                          color: colors.text2,
                        ),
                      ),
                    ),
                    Text(
                      '${notes.length}',
                      style: context.typo.label.copyWith(
                        fontSize: 10,
                        color: colors.text3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (!collapsed.contains(tag))
            for (final n in notes)
              _NoteRow(
                key: ValueKey('note-$tag-${n.path}'),
                note: n,
                selected: n.path == selectedPath,
                onTap: () => onSelect(n),
                onMenu: (pos) => onMenu(n, pos),
              ),
        ],
      ],
    );
  }
}

class _NoteRow extends StatelessWidget {
  const _NoteRow({
    super.key,
    required this.note,
    required this.selected,
    required this.onTap,
    required this.onMenu,
  });
  final NotebookNote note;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<Offset> onMenu;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final n = note;
    return GestureDetector(
      onSecondaryTapUp: (d) => onMenu(d.globalPosition),
      child: HoverTap(
        color: selected ? colors.panel2 : Colors.transparent,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 5, 10, 5),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                width: 2,
                color: selected ? colors.accent : Colors.transparent,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (n.fromAgent) ...[
                    Icon(Icons.auto_awesome, size: 10, color: colors.accent),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Text(
                      n.title.replaceAll('\n', ' '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.typo.label.copyWith(
                        fontSize: 12,
                        color: colors.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 1),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _excerpt(n.body),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.typo.label.copyWith(
                        fontSize: 10.5,
                        color: colors.text3,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _excerpt(String body) {
    final line = body
        .split('\n')
        .map((l) => l.trim())
        .firstWhere(
          (l) => l.isNotEmpty && !l.startsWith('#'),
          orElse: () => '',
        );
    return line.replaceAll(RegExp(r'[*_`>#\[\]]'), '');
  }
}

// ---------------------------------------------------------------------------

class _NoteColumn extends StatelessWidget {
  const _NoteColumn({
    required this.note,
    required this.dirty,
    required this.saving,
    required this.editor,
    required this.editorFocus,
    required this.tagInput,
    required this.titleCtrl,
    required this.titleFocus,
    required this.onCommitTitle,
    required this.onSave,
    required this.onAddTag,
    required this.onRemoveTag,
    required this.onDrop,
    required this.onPaste,
    required this.onWrap,
    required this.onPrefix,
    required this.onInsert,
    required this.onLink,
    required this.onNoteLink,
    required this.onPickImage,
    required this.linkSuggestions,
    required this.onCompleteLink,
    required this.backlinks,
    required this.onOpenNote,
  });

  final NotebookNote? note;
  final bool dirty;
  final bool saving;
  final MarkdownEditingController editor;
  final FocusNode editorFocus;
  final TextEditingController tagInput;
  final TextEditingController titleCtrl;
  final FocusNode titleFocus;
  final VoidCallback onCommitTitle;
  final VoidCallback onSave;
  final ValueChanged<String> onAddTag;
  final ValueChanged<String> onRemoveTag;
  final ValueChanged<List<DropItem>> onDrop;
  final VoidCallback onPaste;
  final void Function(String left, [String? right]) onWrap;
  final void Function(String prefix, {bool numbered}) onPrefix;
  final ValueChanged<String> onInsert;
  final VoidCallback onLink;
  final ValueChanged<Offset> onNoteLink;
  final VoidCallback onPickImage;
  final List<NotebookNote> linkSuggestions;
  final ValueChanged<String> onCompleteLink;
  final List<NotebookNote> backlinks;
  final ValueChanged<NotebookNote> onOpenNote;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tr = context.t.cockpit.notebook;
    final n = note;
    if (n == null) {
      return Center(
        child: Text(
          tr.selectNote,
          style: context.typo.label.copyWith(color: colors.text3),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Cabeçalho da nota: título, tags, ações.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Focus(
                      onFocusChange: (has) {
                        if (!has) onCommitTitle();
                      },
                      // Sempre um campo (sem alternar texto ↔ campo). Material
                      // sem decoração: o TextField do shadcn sempre desenha
                      // anel de foco + fundo. Multilinha de verdade: Enter
                      // quebra e o campo cresce; no frontmatter a quebra vai
                      // como `\n` dentro de aspas.
                      child: material.TextField(
                        controller: titleCtrl,
                        focusNode: titleFocus,
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                        cursorColor: colors.text,
                        style: context.typo.label.copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: colors.text,
                        ),
                        decoration: const material.InputDecoration(
                          isCollapsed: true,
                          border: material.InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onSubmitted: (_) => onCommitTitle(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: colors.border),
        _FormatBar(
          onWrap: onWrap,
          onPrefix: onPrefix,
          onInsert: onInsert,
          onLink: onLink,
          onNoteLink: onNoteLink,
          onPickImage: onPickImage,
        ),
        if (linkSuggestions.isNotEmpty)
          _LinkSuggestions(notes: linkSuggestions, onPick: onCompleteLink),
        Expanded(
          child: DropTarget(
            onDragDone: (d) => onDrop(d.files),
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.keyV, meta: true):
                    onPaste,
                const SingleActivator(LogicalKeyboardKey.keyV, control: true):
                    onPaste,
              },
              // Material sem decoração (mesma razão do título). O controller
              // pinta o markdown ao vivo — um só modo, sem preview separado.
              // O campo cresce com o conteúdo e quem rola é o scroll view de
              // fora: com `expands: true` o scroll interno do EditableText
              // não contava a altura dos WidgetSpans altos (imagem) e a
              // primeira linha ficava fora da tela sem ter como rolar.
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                child: material.TextField(
                  controller: editor,
                  focusNode: editorFocus,
                  maxLines: null,
                  minLines: 8,
                  // O TextField do Material força altura de linha fixa via
                  // StrutStyle → títulos maiores e a caixa da imagem não
                  // entravam na medida do campo (a imagem "vazava" por cima
                  // e a 1ª linha sumia sem scroll). Sem strut, cada linha
                  // mede o que contém.
                  strutStyle: StrutStyle.disabled,
                  textAlignVertical: TextAlignVertical.top,
                  keyboardType: TextInputType.multiline,
                  cursorColor: colors.text,
                  style: context.typo.body.copyWith(
                    color: colors.text,
                    height: 1.55,
                  ),
                  decoration: const material.InputDecoration(
                    isCollapsed: true,
                    border: material.InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),
          ),
        ),
        // Referências: notas que linkam pra esta ([[título]]).
        if (backlinks.isNotEmpty)
          Container(
            padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colors.border)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Icon(
                    Icons.call_received,
                    size: 13,
                    color: colors.text3,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  tr.backlinks,
                  style: context.typo.label.copyWith(
                    fontSize: 11,
                    color: colors.text3,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final b in backlinks)
                        HoverTap(
                          borderRadius: BorderRadius.circular(5),
                          onTap: () => onOpenNote(b),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: colors.accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              b.title.replaceAll('\n', ' '),
                              style: context.typo.label.copyWith(
                                fontSize: 11,
                                color: colors.accent,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        // Rodapé: tags da nota (múltiplas), com remover e adicionar inline.
        Container(
          padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colors.border)),
          ),
          child: Row(
            children: [
              Icon(Icons.sell_outlined, size: 13, color: colors.text3),
              const SizedBox(width: 8),
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final t in n.tags.where((t) => t != kUntagged))
                      _TagChip(t, onRemove: () => onRemoveTag(t)),
                    SizedBox(
                      width: 140,
                      height: 24,
                      child: TextField(
                        controller: tagInput,
                        placeholder: Text(tr.addTag),
                        style: context.typo.label.copyWith(
                          fontSize: 11,
                          color: colors.text,
                        ),
                        border: Border.all(color: Colors.transparent),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        onSubmitted: onAddTag,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

/// Barra de formatação do editor: negrito, itálico, riscado, títulos, listas,
/// checklist, citação, código, link, imagem. Cada botão opera sobre a seleção
/// do editor de fonte (markdown) — a nota continua sendo texto puro no disco.
class _FormatBar extends StatelessWidget {
  const _FormatBar({
    required this.onWrap,
    required this.onPrefix,
    required this.onInsert,
    required this.onLink,
    required this.onNoteLink,
    required this.onPickImage,
  });
  final void Function(String left, [String? right]) onWrap;
  final void Function(String prefix, {bool numbered}) onPrefix;
  final ValueChanged<String> onInsert;
  final VoidCallback onLink;
  final ValueChanged<Offset> onNoteLink;
  final VoidCallback onPickImage;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tr = context.t.cockpit.notebook.format;
    Widget sep() => Container(
      width: 1,
      height: 16,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: colors.border,
    );
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          _IconAction(
            icon: Icons.format_bold,
            tooltip: tr.bold,
            onTap: () => onWrap('**'),
          ),
          _IconAction(
            icon: Icons.format_italic,
            tooltip: tr.italic,
            onTap: () => onWrap('_'),
          ),
          _IconAction(
            icon: Icons.strikethrough_s,
            tooltip: tr.strike,
            onTap: () => onWrap('~~'),
          ),
          sep(),
          _IconAction(
            icon: Icons.title,
            tooltip: tr.heading1,
            onTap: () => onPrefix('# '),
          ),
          _TextAction(
            label: 'H2',
            tooltip: tr.heading2,
            onTap: () => onPrefix('## '),
          ),
          _TextAction(
            label: 'H3',
            tooltip: tr.heading3,
            onTap: () => onPrefix('### '),
          ),
          sep(),
          _IconAction(
            icon: Icons.format_list_bulleted,
            tooltip: tr.bullets,
            onTap: () => onPrefix('- '),
          ),
          _IconAction(
            icon: Icons.format_list_numbered,
            tooltip: tr.numbered,
            onTap: () => onPrefix('', numbered: true),
          ),
          _IconAction(
            icon: Icons.checklist,
            tooltip: tr.checklist,
            onTap: () => onPrefix('- [ ] '),
          ),
          _IconAction(
            icon: Icons.format_quote,
            tooltip: tr.quote,
            onTap: () => onPrefix('> '),
          ),
          sep(),
          _IconAction(
            icon: Icons.code,
            tooltip: tr.code,
            onTap: () => onWrap('`'),
          ),
          _IconAction(
            icon: Icons.data_object,
            tooltip: tr.codeBlock,
            onTap: () => onInsert('```\n\n```\n'),
          ),
          _IconAction(icon: Icons.link, tooltip: tr.link, onTap: onLink),
          _IconAction(
            icon: Icons.horizontal_rule,
            tooltip: tr.rule,
            onTap: () => onInsert('---\n'),
          ),
          sep(),
          _IconAction(
            icon: Icons.description_outlined,
            tooltip: tr.noteLink,
            onTapAt: onNoteLink,
          ),
          _IconAction(
            icon: Icons.image_outlined,
            tooltip: tr.image,
            onTap: onPickImage,
          ),
        ],
      ),
    );
  }
}

/// Faixa de sugestões do `[[`: aparece sob a barra enquanto há um link
/// aberto na linha do cursor; clicar completa. Digitar filtra; `]]` fecha.
class _LinkSuggestions extends StatelessWidget {
  const _LinkSuggestions({required this.notes, required this.onPick});
  final List<NotebookNote> notes;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colors.panel2,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Icon(Icons.description_outlined, size: 13, color: colors.text3),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final n in notes)
                  HoverTap(
                    key: ValueKey('suggest-${n.path}'),
                    borderRadius: BorderRadius.circular(5),
                    onTap: () => onPick(n.title),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: colors.border),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        n.title.replaceAll('\n', ' '),
                        style: context.typo.label.copyWith(
                          fontSize: 11.5,
                          color: colors.text,
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

class _TextAction extends StatelessWidget {
  const _TextAction({
    required this.label,
    required this.tooltip,
    required this.onTap,
  });
  final String label;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppTooltip(
      message: tooltip,
      child: HoverTap(
        borderRadius: BorderRadius.circular(5),
        onTap: onTap,
        child: SizedBox(
          width: 28,
          height: 28,
          child: Center(
            child: Text(
              label,
              style: context.typo.label.copyWith(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: colors.text3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip(this.tag, {this.onRemove});
  final String tag;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final c = _tagColor(tag, context.colors);
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 2, 6, 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(tag, style: context.typo.label.copyWith(fontSize: 11, color: c)),
          if (onRemove != null) ...[
            const SizedBox(width: 4),
            HoverTap(
              borderRadius: BorderRadius.circular(8),
              onTap: onRemove!,
              child: Icon(Icons.close, size: 11, color: c),
            ),
          ],
        ],
      ),
    );
  }
}

/// Cor estável por tag (hash do nome sobre uma paleta de tokens do tema).
Color _tagColor(String tag, AppColors colors) {
  if (tag == kUntagged) return colors.text3;
  if (tag == kAgentTag) return colors.accent;
  // Mesma paleta do kanban (tokens do tema, não hex).
  final palette = [
    colors.gitConflict,
    colors.edited,
    colors.error,
    colors.online,
    colors.warn,
    colors.gitUntracked,
  ];
  var h = 0;
  for (final u in tag.codeUnits) {
    h = (h * 31 + u) & 0x7fffffff;
  }
  return palette[h % palette.length];
}
