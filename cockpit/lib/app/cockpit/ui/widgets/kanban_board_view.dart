import 'package:cockpit/app/cockpit/domain/entities/file_view.dart';
import 'package:cockpit/app/cockpit/domain/entities/kanban_document.dart';
import 'package:cockpit/app/cockpit/domain/services/kanban_editor.dart';
import 'package:cockpit/app/cockpit/ui/session/file_viewer_session.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/app_menu.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:cockpit/app/core/utils/path_utils.dart';
import 'package:cockpit/app/core/utils/user_home.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter/gestures.dart'
    show
        DelayedMultiDragGestureRecognizer,
        GestureMultiDragStartCallback,
        ImmediateMultiDragGestureRecognizer,
        MultiDragGestureRecognizer,
        PointerDeviceKind;
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Tab de um arquivo `.kanban`: quadro de colunas e cards, ou a mesma coisa em
/// lista. Reusa a [FileViewerSession] pelo mesmo motivo da `.dbq`/`.http`
/// (preview/dirty/watch/persistência de graça); só o render diverge.
///
/// O arquivo **é** a fonte de verdade. Toda ação vira uma emenda de linhas
/// ([KanbanEditor]) gravada na hora — não há buffer de edição escondido, então
/// não há "salvar": mover um card *é* escrever no arquivo. A escrita é
/// otimista (a tela aplica antes da confirmação) e **reverte visivelmente** se
/// o disco recusar; em workspace remoto isso é o que impede o quadro de travar
/// a cada clique enquanto o host responde.
class KanbanBoardView extends StatefulWidget {
  const KanbanBoardView({
    super.key,
    required this.session,
    required this.active,
    required this.focused,
    required this.onSave,
    required this.onReload,
    required this.workspaceRoot,
    required this.onViewModeChanged,
  });

  final FileViewerSession session;
  final bool active;
  final bool focused;

  /// Grava o conteúdo novo do arquivo. `false` = não gravou (a UI reverte).
  final Future<bool> Function(String content) onSave;

  /// Relê o arquivo do disco/host. É a rede de segurança de workspace remoto,
  /// onde o aviso de mudança pode não chegar.
  final Future<void> Function() onReload;

  /// Raiz do workspace, para encurtar o caminho exibido na barra.
  final String workspaceRoot;

  /// Avisa a escolha entre quadro e lista, para a VM persistir no layout.
  final void Function(bool asList) onViewModeChanged;

  @override
  State<KanbanBoardView> createState() => _KanbanBoardViewState();
}

class _KanbanBoardViewState extends State<KanbanBoardView> {
  static const double _columnWidth = 268;

  late KanbanDocument _doc;
  bool _reloading = false;

  /// A escolha entre quadro e lista mora na SESSÃO, não aqui: o State morre
  /// quando a aba muda de pane, e a preferência precisa sobreviver a isso — e
  /// ao fechar o app, via layout.
  bool get _asList => widget.session.boardAsList;

  /// Card aberto no painel de detalhe (chave estável, ver [_keyOf]).
  String? _selectedKey;

  /// Filtro do quadro: texto (no título, sem case) e marcadores (qualquer um
  /// dos escolhidos). É estado de TELA, não do arquivo: nada disso vai pro
  /// `.kanban`, e um reload do disco não o limpa.
  String _filterText = '';
  final Set<String> _filterLabels = <String>{};

  /// `null` = tanto faz; `true` = só bloqueados; `false` = só prontos (sem
  /// bloqueio pendente). Derivado do `blockedBy` na hora, nunca gravado.
  bool? _filterBlocked;

  bool get _filterActive =>
      _filterText.isNotEmpty ||
      _filterLabels.isNotEmpty ||
      _filterBlocked != null;

  bool _matchesFilter(KanbanCard card) {
    if (_filterText.isNotEmpty &&
        !card.title.toLowerCase().contains(_filterText.toLowerCase())) {
      return false;
    }
    if (_filterLabels.isNotEmpty && !card.labels.any(_filterLabels.contains)) {
      return false;
    }
    if (_filterBlocked case final wantBlocked?) {
      if (_doc.isBlocked(card) != wantBlocked) return false;
    }
    return true;
  }

  /// Cards visíveis de uma coluna com o índice ORIGINAL preservado: o drop
  /// insere por posição na lista completa, então filtrar não pode renumerar.
  Iterable<(int, KanbanCard)> _visibleCards(KanbanColumn column) =>
      column.cards.indexed.where((e) => _matchesFilter(e.$2));

  /// Card com o título em edição inline.
  String? _editingKey;
  final TextEditingController _titleCtrl = TextEditingController();
  final FocusNode _titleFocus = FocusNode();

  /// Rascunho do painel de detalhe. Mora aqui, e não no painel, porque quem
  /// fecha o painel precisa poder gravar o que estava sendo escrito — ver a
  /// nota em [_DetailPanel].
  final TextEditingController _notesCtrl = TextEditingController();
  final FocusNode _notesFocus = FocusNode();
  final TextEditingController _detailTitleCtrl = TextEditingController();
  bool _editingDetailTitle = false;

  /// Compositor de comentário: aberto sob demanda pelo `+`, some ao adicionar.
  final TextEditingController _commentCtrl = TextEditingController();
  bool _composingComment = false;

  /// Grupo do [TapRegion] do painel. O dialog de marcadores entra no MESMO
  /// grupo: sem isso, tocar dentro dele contaria como "fora do painel" e
  /// fecharia o detalhe por baixo — ao sair do dialog não haveria mais painel.
  final Object _detailTapGroup = Object();

  @override
  void initState() {
    super.initState();
    _doc = KanbanDocument.parse(_diskText());
    widget.session.addListener(_onSession);
    // Título editado e abandonado com um clique noutro lugar tem de ser
    // gravado. Sem isto o texto ficava na tela, fora do arquivo — pior que
    // perder a edição, porque parecia salvo.
    _titleFocus.addListener(() {
      if (!_titleFocus.hasFocus && _editingKey != null) _commitTitle();
    });
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSession);
    _titleCtrl.dispose();
    _titleFocus.dispose();
    _notesCtrl.dispose();
    _notesFocus.dispose();
    _detailTitleCtrl.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  String _diskText() => switch (widget.session.view) {
    FileViewText(:final text) => text,
    FileViewMarkdown(:final text) => text,
    _ => '',
  };

  /// O disco mudou (watcher, agente, ou o nosso próprio save): adota o
  /// conteúdo novo. Não há buffer local pra proteger — o que está na tela já
  /// foi gravado —, então reparsear é sempre seguro.
  void _onSession() {
    final text = _diskText();
    if (text == _doc.content) return;
    setState(() {
      _doc = KanbanDocument.parse(text);
      _editingKey = null;
    });
  }

  /// Chave estável de um card entre reparses. O id é a identidade real; sem
  /// ele (card escrito à mão) caímos no título, que é o que o usuário vê.
  String _keyOf(KanbanCard card) => card.id ?? 'title:${card.title}';

  KanbanCard? _cardByKey(String? key) {
    if (key == null) return null;
    for (final column in _doc.columns) {
      for (final card in column.cards) {
        if (_keyOf(card) == key) return card;
      }
    }
    return null;
  }

  int _columnOfKey(String key) {
    for (var i = 0; i < _doc.columns.length; i++) {
      if (_doc.columns[i].cards.any((c) => _keyOf(c) == key)) return i;
    }
    return -1;
  }

  /// Abre [key] no painel (ou fecha, com `null`), gravando antes o que
  /// estivesse em edição no card anterior. Todo caminho que muda a seleção
  /// passa por aqui — é o único lugar que sabe fechar sem perder rascunho.
  Future<void> _selectDetail(String? key) async {
    await _flushDetail();
    if (!mounted) return;
    setState(() {
      _selectedKey = key;
      _editingDetailTitle = false;
      _composingComment = false;
      _commentCtrl.clear();
      final card = _cardByKey(key);
      _notesCtrl.text = card?.notes ?? '';
      _detailTitleCtrl.text = card?.title ?? '';
    });
  }

  /// Grava título e nota pendentes do card aberto. O título vai primeiro e o
  /// documento é reparseado no meio, senão a nota escreveria por cima usando
  /// posições de linha antigas.
  Future<void> _flushDetail() async {
    var card = _cardByKey(_selectedKey);
    if (card == null || !card.recognized) return;
    var doc = _doc;
    var content = doc.content;

    if (_editingDetailTitle) {
      final title = _detailTitleCtrl.text.trim();
      if (title.isNotEmpty && title != card.title) {
        content = KanbanEditor.setCardTitle(doc, card, title);
        doc = KanbanDocument.parse(content);
        final id = card.id;
        final again = doc.columns
            .expand((c) => c.cards)
            .where((c) => id != null && c.id == id)
            .firstOrNull;
        if (again != null) card = again;
      }
    }
    if (_notesCtrl.text.trim() != card.notes.trim()) {
      content = KanbanEditor.setCardNotes(doc, card, _notesCtrl.text);
    }
    if (content != _doc.content) await _apply(content);
  }

  /// Aplica [content] na tela e grava. Otimista: se a gravação falhar, o
  /// documento anterior volta — a tela nunca fica mostrando um estado que não
  /// existe no arquivo.
  Future<void> _apply(String content) async {
    if (content == _doc.content) return;
    final previous = _doc;
    setState(() => _doc = KanbanDocument.parse(content));
    final ok = await widget.onSave(content);
    if (!mounted || ok) return;
    setState(() {
      _doc = previous;
      _editingKey = null;
    });
    _showError(context.t.cockpit.kanbanView.couldNotSave);
  }

  Future<void> _reload() async {
    setState(() => _reloading = true);
    await widget.onReload();
    if (!mounted) return;
    setState(() => _reloading = false);
    _onSession();
  }

  // ------------------------------------------------------------- ações -----

  void _advance(KanbanCard card) =>
      _apply(KanbanEditor.advanceCard(_doc, card));

  void _moveCard(KanbanCard card, int toColumn, {int? atIndex}) =>
      _apply(KanbanEditor.moveCard(_doc, card, toColumn, atIndex: atIndex));

  Future<void> _addCard(int column) async {
    final title = context.t.cockpit.kanbanView.newCardTitle;
    await _apply(KanbanEditor.addCard(_doc, column, title));
    if (!mounted || column >= _doc.columns.length) return;
    final created = _doc.columns[column].cards.lastOrNull;
    if (created == null) return;
    // Nasce em edição com o texto padrão selecionado: digitar substitui, Esc
    // mantém um card legítimo em vez de deixar linha vazia no arquivo.
    setState(() => _startEditing(created, selectAll: true));
  }

  /// Entra em edição do título. [selectAll] só no card recém-criado, onde o
  /// texto padrão existe pra ser substituído; ao clicar num card que já tem
  /// título, selecionar tudo transformaria um clique distraído em perda do
  /// texto — o cursor vai pro fim e nada fica marcado.
  void _startEditing(KanbanCard card, {bool selectAll = false}) {
    _editingKey = _keyOf(card);
    _titleCtrl.text = card.title;
    _titleCtrl.selection = selectAll
        ? TextSelection(baseOffset: 0, extentOffset: card.title.length)
        : TextSelection.collapsed(offset: card.title.length);
    _titleFocus.requestFocus();
  }

  void _commitTitle() {
    final key = _editingKey;
    if (key == null) return;
    final card = _cardByKey(key);
    setState(() => _editingKey = null);
    if (card == null) return;
    final text = _titleCtrl.text.trim();
    if (text.isEmpty || text == card.title) return;
    _apply(KanbanEditor.setCardTitle(_doc, card, text));
  }

  Future<void> _showCardMenu(
    BuildContext context,
    KanbanCard card,
    int column,
    Offset position,
  ) async {
    final tr = context.t.cockpit.kanbanView;
    final labels = _doc.allLabels;
    final choice = await showAppMenu<String>(
      context,
      globalPosition: position,
      items: [
        AppMenuItem(value: 'new', label: tr.newCardHere, icon: Icons.add),
        if (card.recognized)
          AppMenuItem(
            value: 'duplicate',
            label: tr.duplicateCard,
            icon: Icons.copy_outlined,
          ),
        if (card.recognized && labels.isNotEmpty)
          AppMenuItem(
            value: 'labels',
            label: tr.cardLabels,
            icon: Icons.label_outline,
            children: [
              for (final label in labels)
                AppMenuItem(
                  value: 'label:$label',
                  label: label,
                  selected: card.labels.contains(label),
                  leading: _LabelDot(color: _doc.colorOf(label)),
                ),
            ],
          ),
        const AppMenuItem<String>.divider(),
        AppMenuItem(
          value: 'delete',
          label: tr.deleteCard,
          icon: Icons.delete_outline,
          danger: true,
        ),
      ],
    );
    if (!mounted || choice == null) return;
    if (choice == 'new') {
      await _addCard(column);
    } else if (choice == 'duplicate') {
      await _apply(KanbanEditor.duplicateCard(_doc, card));
    } else if (choice == 'delete') {
      if (_selectedKey == _keyOf(card)) await _selectDetail(null);
      await _apply(KanbanEditor.deleteCard(_doc, card));
    } else if (choice.startsWith('label:')) {
      await _apply(KanbanEditor.toggleLabel(_doc, card, choice.substring(6)));
    }
  }

  Future<void> _showColumnMenu(
    BuildContext context,
    int index,
    Offset at,
  ) async {
    final tr = context.t.cockpit.kanbanView;
    final choice = await showAppMenu<String>(
      context,
      globalPosition: at,
      items: [
        AppMenuItem(
          value: 'rename',
          label: tr.renameColumn,
          icon: Icons.edit_outlined,
        ),
        AppMenuItem(
          value: 'left',
          label: tr.moveColumnLeft,
          icon: Icons.arrow_back,
          enabled: index > 0,
        ),
        AppMenuItem(
          value: 'right',
          label: tr.moveColumnRight,
          icon: Icons.arrow_forward,
          enabled: index < _doc.columns.length - 1,
        ),
        const AppMenuItem<String>.divider(),
        AppMenuItem(
          value: 'delete',
          label: tr.deleteColumn,
          icon: Icons.delete_outline,
          danger: true,
        ),
      ],
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'rename':
        final name = await _promptText(
          tr.columnNameTitle,
          _doc.columns[index].name,
        );
        if (name != null && mounted) {
          await _apply(KanbanEditor.renameColumn(_doc, index, name));
        }
      case 'left':
        await _apply(KanbanEditor.moveColumn(_doc, index, -1));
      case 'right':
        await _apply(KanbanEditor.moveColumn(_doc, index, 1));
      case 'delete':
        await _deleteColumn(index);
    }
  }

  /// Apagar coluna com cards dentro nunca é decidido pelo menu: a confirmação
  /// nomeia o destino dos cards e o usuário escolhe.
  Future<void> _deleteColumn(int index) async {
    final tr = context.t.cockpit.kanbanView;
    final column = _doc.columns[index];
    final hasCards = column.cards.isNotEmpty;
    final canMove = hasCards && index > 0;

    final choice = await showDialog<String>(
      context: context,
      builder: (context) {
        final colors = context.colors;
        return AlertDialog(
          title: Text(
            tr.deleteColumnDialog.title(name: column.name),
            style: context.typo.title.copyWith(
              fontSize: 15,
              color: colors.text,
            ),
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Text(
              hasCards
                  ? tr.deleteColumnDialog.message(
                      count: tr.cardCount(n: column.cards.length),
                    )
                  : tr.deleteColumnDialog.emptyMessage,
              style: context.typo.body.copyWith(
                fontSize: 13,
                color: colors.text2,
              ),
            ),
          ),
          actions: [
            GhostButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.t.common.cancel),
            ),
            if (canMove)
              SecondaryButton(
                onPressed: () => Navigator.of(context).pop('move'),
                child: Text(tr.deleteColumnDialog.moveCards),
              ),
            DestructiveButton(
              onPressed: () => Navigator.of(context).pop('delete'),
              child: Text(
                hasCards ? tr.deleteColumnDialog.deleteAll : tr.deleteColumn,
              ),
            ),
          ],
        );
      },
    );
    if (!mounted || choice == null) return;
    await _apply(
      KanbanEditor.deleteColumn(
        _doc,
        index,
        moveCardsToPrevious: choice == 'move',
      ),
    );
  }

  Future<String?> _promptText(String title, String initial) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) {
        final colors = context.colors;
        return AlertDialog(
          title: Text(
            title,
            style: context.typo.title.copyWith(
              fontSize: 15,
              color: colors.text,
            ),
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: TextField(
              controller: ctrl,
              autofocus: true,
              style: context.typo.body.copyWith(
                fontSize: 13,
                color: colors.text,
              ),
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              onSubmitted: (v) => Navigator.of(context).pop(v),
            ),
          ),
          actions: [
            GhostButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.t.common.cancel),
            ),
            PrimaryButton(
              onPressed: () => Navigator.of(context).pop(ctrl.text),
              child: Text(context.t.common.save),
            ),
          ],
        );
      },
    );
  }

  void _showError(String message) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          message,
          style: context.typo.title.copyWith(
            fontSize: 15,
            color: context.colors.text,
          ),
        ),
        actions: [
          PrimaryButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.t.common.ok),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------- build ----

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final selected = _cardByKey(_selectedKey);
    return ColoredBox(
      color: colors.panel,
      child: Column(
        children: [
          _toolbar(context),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _body(context)),
                if (selected != null)
                  // Fecha ao tocar em qualquer coisa fora dele. `TapRegion` é
                  // feito exatamente pra isso e evita espalhar handler de
                  // dispensa pelo quadro inteiro.
                  //
                  // Deliberadamente NÃO é rota/dialog: um barrier — mesmo
                  // invisível — cobriria o quadro e engoliria o clique, então
                  // trocar de card custaria dois toques (um pra fechar, outro
                  // pra abrir) e o quadro deixaria de ficar operável com a nota
                  // aberta, que é a razão de isto ser painel e não modal.
                  //
                  // A ordem funciona a favor: `onTapOutside` corre no pointer
                  // DOWN e o `onTap` do card no UP, então clicar noutro card
                  // fecha e reabre no card novo num gesto só.
                  TapRegion(
                    groupId: _detailTapGroup,
                    onTapOutside: (_) {
                      setState(() => _editingKey = null);
                      _selectDetail(null);
                    },
                    child: _DetailPanel(
                      card: selected,
                      doc: _doc,
                      column: _columnOfKey(_keyOf(selected)),
                      notesController: _notesCtrl,
                      notesFocus: _notesFocus,
                      titleController: _detailTitleCtrl,
                      editingTitle: _editingDetailTitle,
                      onStartTitleEdit: () => setState(() {
                        _detailTitleCtrl.text = selected.title;
                        _detailTitleCtrl.selection = TextSelection.collapsed(
                          offset: selected.title.length,
                        );
                        _editingDetailTitle = true;
                      }),
                      onCommitTitle: _flushDetail,
                      onClose: () => _selectDetail(null),
                      onToggleLabel: (label) => _apply(
                        KanbanEditor.toggleLabel(_doc, selected, label),
                      ),
                      onManageLabels: () => _showLabelsDialog(context),
                      onSetBlockedBy: (blockers) => _apply(
                        KanbanEditor.setBlockedBy(_doc, selected, blockers),
                      ),
                      commentController: _commentCtrl,
                      composingComment: _composingComment,
                      onStartComment: () =>
                          setState(() => _composingComment = true),
                      onCancelComment: () => setState(() {
                        _composingComment = false;
                        _commentCtrl.clear();
                      }),
                      onAddComment: () {
                        final text = _commentCtrl.text;
                        if (text.trim().isEmpty) return;
                        setState(() {
                          _composingComment = false;
                          _commentCtrl.clear();
                        });
                        _apply(KanbanEditor.addComment(_doc, selected, text));
                      },
                      onDeleteComment: (comment) => _apply(
                        KanbanEditor.deleteComment(_doc, selected, comment),
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

  Widget _toolbar(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    final tr = context.t.cockpit.kanbanView;
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: colors.panel,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          // `Expanded` e NÃO `Flexible` + `Spacer`: os dois teriam flex 1 e
          // dividiriam o espaço livre pela metade, deixando os botões parados
          // no meio da barra. Aqui o caminho absorve toda a sobra e empurra os
          // botões para a borda.
          Expanded(
            child: Text(
              kanbanDisplayPath(widget.session.path, widget.workspaceRoot),
              overflow: TextOverflow.ellipsis,
              style: typo.mono.copyWith(fontSize: 10.5, color: colors.text3),
            ),
          ),
          const SizedBox(width: 12),
          _IconAction(
            icon: Icons.refresh,
            tooltip: tr.refresh,
            busy: _reloading,
            onTap: _reload,
          ),
          const SizedBox(width: 4),
          _IconAction(
            icon: Icons.label_outline,
            tooltip: tr.manageLabels,
            onTap: () => _showLabelsDialog(context),
          ),
          const SizedBox(width: 4),
          // O filtro fica atrás de um botão, não numa barra fixa: a toolbar
          // do quadro é curta e quem filtra o faz de vez em quando.
          Builder(
            builder: (anchor) => _IconAction(
              icon: _filterActive
                  ? Icons.filter_alt
                  : Icons.filter_alt_outlined,
              tooltip: tr.filter,
              active: _filterActive,
              onTap: () => _showFilterPopup(anchor),
            ),
          ),
          const SizedBox(width: 8),
          _ViewToggle(
            asList: _asList,
            onChanged: (v) => setState(() {
              widget.session.setBoardAsList(v);
              widget.onViewModeChanged(v);
            }),
          ),
        ],
      ),
    );
  }

  /// Popover de filtro ancorado no botão da toolbar. O estado vive aqui no
  /// quadro (pra sobreviver ao fechar do popover); o popover só edita e avisa.
  void _showFilterPopup(BuildContext anchor) {
    final overlay = showPopover<void>(
      context: anchor,
      alignment: Alignment.topRight,
      anchorAlignment: Alignment.bottomRight,
      offset: const Offset(0, 4),
      builder: (popupContext) => TapRegion(
        groupId: _detailTapGroup,
        child: _FilterPopup(
          labels: _doc.allLabels,
          labelColors: _doc.labelColors,
          text: _filterText,
          selected: _filterLabels,
          blocked: _filterBlocked,
          onChanged: (text, labels, blocked) => setState(() {
            _filterText = text;
            _filterLabels
              ..clear()
              ..addAll(labels);
            _filterBlocked = blocked;
          }),
        ),
      ),
    );
    trackMenuOverlay(overlay);
  }

  Future<void> _showLabelsDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => TapRegion(
        groupId: _detailTapGroup,
        child: _LabelsDialog(
          doc: _doc,
          onUpsert: (name, color) async {
            await _apply(KanbanEditor.upsertLabel(_doc, name, color));
            return _doc;
          },
          onDelete: (name) async {
            await _apply(KanbanEditor.deleteLabel(_doc, name));
            return _doc;
          },
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (!_doc.isBoard) return _emptyState(context);
    return _asList ? _listBody(context) : _boardBody(context);
  }

  /// Arquivo sem colunas: não é erro, é markdown comum. Oferecemos começar um
  /// quadro em vez de mostrar uma tela vazia sem saída.
  Widget _emptyState(BuildContext context) {
    final colors = context.colors;
    final tr = context.t.cockpit.kanbanView;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Text(
              tr.notABoard,
              textAlign: TextAlign.center,
              style: context.typo.body.copyWith(
                fontSize: 13,
                color: colors.text3,
              ),
            ),
          ),
          const SizedBox(height: 12),
          PrimaryButton(
            onPressed: () async {
              var content = KanbanEditor.addColumn(_doc, 'Backlog');
              content = KanbanEditor.addColumn(
                KanbanDocument.parse(content),
                'Done',
              );
              await _apply(content);
            },
            child: Text(tr.startBoard),
          ),
        ],
      ),
    );
  }

  Widget _boardBody(BuildContext context) {
    final tr = context.t.cockpit.kanbanView;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < _doc.columns.length; i++)
              SizedBox(width: _columnWidth, child: _column(context, i)),
            _AddColumnRail(
              tooltip: tr.newColumn,
              onTap: () async {
                final name = await _promptText(tr.columnNameTitle, '');
                if (name != null && name.trim().isNotEmpty && mounted) {
                  await _apply(KanbanEditor.addColumn(_doc, name));
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _column(BuildContext context, int index) {
    final colors = context.colors;
    final column = _doc.columns[index];
    final isLast = index == _doc.columns.length - 1;

    return DragTarget<_CardDrag>(
      onWillAcceptWithDetails: (details) => details.data.column != index,
      onAcceptWithDetails: (details) => _moveCard(details.data.card, index),
      builder: (context, candidate, _) => Container(
        decoration: BoxDecoration(
          color: candidate.isEmpty ? null : colors.accentSoft,
          border: Border(right: BorderSide(color: colors.border)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ColumnHeader(
              name: column.name,
              count: _filterActive
                  ? _visibleCards(column).length
                  : column.cards.length,
              index: index,
              onMenu: (at) => _showColumnMenu(context, index, at),
              onReorder: (from) => _reorderColumn(from, index),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                children: [
                  for (final (c, card) in _visibleCards(column))
                    _cardSlot(context, card, index, c, isLast),
                  // Coluna vazia: só um ícone apagado. A frase "sem cards"
                  // ocupava a largura toda pra dizer o que a ausência de cards
                  // já diz. O texto continua existindo como tooltip, que é o
                  // que um leitor de tela lê.
                  if (column.cards.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Tooltip(
                        tooltip: TooltipContainer(
                          child: Text(context.t.cockpit.kanbanView.emptyColumn),
                        ).call,
                        child: Icon(
                          Icons.inbox_outlined,
                          size: 20,
                          color: colors.text4,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: _AddCardButton(onTap: () => _addCard(index)),
            ),
          ],
        ),
      ),
    );
  }

  /// Um card mais a zona de soltar logo acima dele (inserção por posição).
  Widget _cardSlot(
    BuildContext context,
    KanbanCard card,
    int column,
    int index,
    bool isLastColumn,
  ) {
    return DragTarget<_CardDrag>(
      onWillAcceptWithDetails: (details) =>
          details.data.card.startLine != card.startLine,
      onAcceptWithDetails: (details) =>
          _moveCard(details.data.card, column, atIndex: index),
      builder: (context, candidate, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (candidate.isNotEmpty) const _DropIndicator(),
          _cardTile(context, card, column, isLastColumn),
        ],
      ),
    );
  }

  Widget _cardTile(
    BuildContext context,
    KanbanCard card,
    int column,
    bool isLastColumn,
  ) {
    final key = _keyOf(card);
    final tile = _CardTile(
      card: card,
      doc: _doc,
      isLastColumn: isLastColumn,
      selected: _selectedKey == key,
      editing: _editingKey == key,
      titleController: _titleCtrl,
      titleFocus: _titleFocus,
      onAdvance: () => _advance(card),
      onOpen: () => _selectDetail(_selectedKey == key ? null : key),
      // Clicar no título faz as duas coisas: abre o card no painel E entra em
      // edição do texto. Antes o título (que ocupa quase todo o card) era o
      // único ponto que NÃO abria o detalhe — clicar no card quase sempre caía
      // nele e o painel parecia não responder. Aqui não alterna: quem clica no
      // texto quer editá-lo, e fechar o painel embaixo seria surpresa.
      onEditTitle: card.recognized
          ? () {
              _selectDetail(key);
              setState(() => _startEditing(card));
            }
          : null,
      onCommitTitle: _commitTitle,
      onMenu: (position) => _showCardMenu(context, card, column, position),
    );

    // Mouse arrasta na hora; dedo precisa segurar ~280ms — no touch o toque
    // longo também é o gesto de menu, então ele arma os dois e quem decide é
    // o que a mão faz depois: moveu vira arraste, soltou parado vira menu.
    return _MouseDraggable<_CardDrag>(
      data: _CardDrag(card: card, column: column),
      feedback: _DragFeedback(child: tile),
      childWhenDragging: Opacity(opacity: 0.35, child: tile),
      child: _TouchDraggable<_CardDrag>(
        data: _CardDrag(card: card, column: column),
        feedback: _DragFeedback(child: tile),
        childWhenDragging: Opacity(opacity: 0.35, child: tile),
        onDragStarted: HapticFeedback.selectionClick,
        child: tile,
      ),
    );
  }

  /// Reordena colunas por arraste da alça: move de um em um até a posição.
  Future<void> _reorderColumn(int from, int to) async {
    if (from == to) return;
    var content = _doc.content;
    var doc = _doc;
    final step = from < to ? 1 : -1;
    for (var i = from; i != to; i += step) {
      content = KanbanEditor.moveColumn(doc, i, step);
      doc = KanbanDocument.parse(content);
    }
    await _apply(content);
  }

  Widget _listBody(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    return ListView(
      padding: const EdgeInsets.only(bottom: 12),
      children: [
        for (var i = 0; i < _doc.columns.length; i++) ...[
          // Cabeçalho da seção também é alvo: soltar nele manda pro FIM da
          // coluna (mesmo contrato da coluna no modo quadro).
          DragTarget<_CardDrag>(
            onWillAcceptWithDetails: (d) => d.data.column != i,
            onAcceptWithDetails: (d) => _moveCard(d.data.card, i),
            builder: (context, candidate, _) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              color: candidate.isEmpty ? colors.panel2 : colors.accentSoft,
              child: Row(
                children: [
                  Text(
                    _doc.columns[i].name.toUpperCase(),
                    style: typo.mono.copyWith(
                      fontSize: 10.5,
                      letterSpacing: 0.9,
                      color: colors.text2,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    '${_filterActive ? _visibleCards(_doc.columns[i]).length : _doc.columns[i].cards.length}',
                    style: typo.mono.copyWith(
                      fontSize: 10.5,
                      color: colors.text4,
                    ),
                  ),
                ],
              ),
            ),
          ),
          for (final (index, card) in _visibleCards(_doc.columns[i]))
            _listSlot(context, card, i, index),
        ],
      ],
    );
  }

  /// Linha da lista + zona de soltar acima dela (inserção por posição), e a
  /// própria linha arrastável — mesmo par mouse/toque do modo quadro.
  Widget _listSlot(
    BuildContext context,
    KanbanCard card,
    int column,
    int index,
  ) {
    final row = _ListRow(
      card: card,
      doc: _doc,
      isLastColumn: column == _doc.columns.length - 1,
      selected: _selectedKey == _keyOf(card),
      onAdvance: () => _advance(card),
      onOpen: () {
        final key = _keyOf(card);
        _selectDetail(_selectedKey == key ? null : key);
      },
      onMenu: (position) => _showCardMenu(context, card, column, position),
    );
    final data = _CardDrag(card: card, column: column);
    final draggable = _MouseDraggable<_CardDrag>(
      data: data,
      feedback: _DragFeedback(child: SizedBox(width: 360, child: row)),
      childWhenDragging: Opacity(opacity: 0.35, child: row),
      child: _TouchDraggable<_CardDrag>(
        data: data,
        feedback: _DragFeedback(child: SizedBox(width: 360, child: row)),
        childWhenDragging: Opacity(opacity: 0.35, child: row),
        onDragStarted: HapticFeedback.selectionClick,
        child: row,
      ),
    );
    return DragTarget<_CardDrag>(
      onWillAcceptWithDetails: (d) => d.data.card.startLine != card.startLine,
      onAcceptWithDetails: (d) =>
          _moveCard(d.data.card, column, atIndex: index),
      builder: (context, candidate, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [if (candidate.isNotEmpty) const _DropIndicator(), draggable],
      ),
    );
  }
}

/// O que viaja num arraste de card.
class _CardDrag {
  const _CardDrag({required this.card, required this.column});
  final KanbanCard card;
  final int column;
}

/// Arraste imediato, só para mouse/trackpad/caneta — o dedo é tratado pelo
/// [_TouchDraggable], que exige o toque longo.
class _MouseDraggable<T extends Object> extends Draggable<T> {
  const _MouseDraggable({
    required super.data,
    required super.child,
    required super.feedback,
    super.childWhenDragging,
  }) : super(dragAnchorStrategy: pointerDragAnchorStrategy);

  @override
  MultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) => ImmediateMultiDragGestureRecognizer(
    supportedDevices: const {
      PointerDeviceKind.mouse,
      PointerDeviceKind.stylus,
      PointerDeviceKind.invertedStylus,
      PointerDeviceKind.trackpad,
    },
  )..onStart = onStart;
}

/// Arraste com toque longo (~280 ms), só para dedo. Soltar sem mover não vira
/// arraste — o toque segue disponível para o menu de contexto.
class _TouchDraggable<T extends Object> extends LongPressDraggable<T> {
  const _TouchDraggable({
    required super.data,
    required super.child,
    required super.feedback,
    super.childWhenDragging,
    super.onDragStarted,
  }) : super(dragAnchorStrategy: pointerDragAnchorStrategy);

  @override
  DelayedMultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) => DelayedMultiDragGestureRecognizer(
    delay: const Duration(milliseconds: 280),
    supportedDevices: const {PointerDeviceKind.touch},
  )..onStart = onStart;
}

class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Transform.translate(
    offset: const Offset(-130, -22),
    child: SizedBox(
      width: 252,
      child: Opacity(
        opacity: 0.92,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                color: context.colors.shadow,
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: child,
        ),
      ),
    ),
  );
}

class _DropIndicator extends StatelessWidget {
  const _DropIndicator();

  @override
  Widget build(BuildContext context) => Container(
    height: 26,
    margin: const EdgeInsets.only(bottom: 6),
    decoration: BoxDecoration(
      color: context.colors.accentSoft,
      border: Border.all(color: context.colors.accent),
      borderRadius: BorderRadius.circular(5),
    ),
  );
}

class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader({
    required this.name,
    required this.count,
    required this.index,
    required this.onMenu,
    required this.onReorder,
  });

  final String name;
  final int count;
  final int index;
  final ValueChanged<Offset> onMenu;
  final void Function(int from) onReorder;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    final tr = context.t.cockpit.kanbanView;
    final label = Row(
      children: [
        Flexible(
          child: Text(
            name.toUpperCase(),
            overflow: TextOverflow.ellipsis,
            style: typo.mono.copyWith(
              fontSize: 11,
              letterSpacing: 0.9,
              fontWeight: FontWeight.w600,
              color: colors.text,
            ),
          ),
        ),
        const SizedBox(width: 7),
        Text(
          '$count',
          style: typo.mono.copyWith(fontSize: 10.5, color: colors.text4),
        ),
      ],
    );

    return DragTarget<int>(
      onWillAcceptWithDetails: (details) => details.data != index,
      onAcceptWithDetails: (details) => onReorder(details.data),
      builder: (context, candidate, _) => Container(
        height: 32,
        padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
        color: candidate.isEmpty ? null : colors.accentSoft,
        child: Row(
          children: [
            Expanded(child: label),
            Draggable<int>(
              data: index,
              feedback: Opacity(
                opacity: 0.9,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: colors.panel2,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: colors.accent),
                  ),
                  child: label,
                ),
              ),
              child: Tooltip(
                tooltip: TooltipContainer(child: Text(tr.dragColumn)).call,
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Icon(
                    Icons.drag_indicator,
                    size: 13,
                    color: colors.text4,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 2),
            // O menu ancora no BOTÃO (posição global do canto inferior
            // esquerdo), não no context do quadro — senão abria longe.
            Builder(
              builder: (btnCtx) => HoverTap(
                onTap: () {
                  final box = btnCtx.findRenderObject() as RenderBox?;
                  onMenu(
                    box == null
                        ? Offset.zero
                        : box.localToGlobal(Offset(0, box.size.height)),
                  );
                },
                padding: const EdgeInsets.all(3),
                borderRadius: BorderRadius.circular(4),
                child: Icon(Icons.more_horiz, size: 13, color: colors.text4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardTile extends StatelessWidget {
  const _CardTile({
    required this.card,
    required this.doc,
    required this.isLastColumn,
    required this.selected,
    required this.editing,
    required this.titleController,
    required this.titleFocus,
    required this.onAdvance,
    required this.onOpen,
    required this.onEditTitle,
    required this.onCommitTitle,
    required this.onMenu,
  });

  final KanbanCard card;
  final KanbanDocument doc;
  final bool isLastColumn;
  final bool selected;
  final bool editing;
  final TextEditingController titleController;
  final FocusNode titleFocus;
  final VoidCallback onAdvance;
  final VoidCallback onOpen;
  final VoidCallback? onEditTitle;
  final VoidCallback onCommitTitle;
  final void Function(Offset position) onMenu;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    final stripe = card.labels.isEmpty
        ? colors.border2
        : kanbanLabelColor(context, doc.colorOf(card.labels.first));

    final title = editing
        // Editar o título é o mesmo texto virando editável, não um campo
        // aparecendo por cima dele. São TRÊS coisas, porque o shadcn desenha
        // moldura em dois lugares diferentes:
        //  - `decoration` vazia + `padding` zero matam borda, fundo e raio da
        //    caixa do próprio TextField;
        //  - o anel de foco NÃO sai por aí: ele é um `FocusOutline` que o
        //    TextField embrulha por fora, sem parâmetro para desligar. Só o
        //    `FocusOutlineTheme` o alcança — daí a borda transparente;
        //  - `maxLines: null` deixa o texto quebrar em várias linhas como o
        //    [Text] faz. Sem isso, o título de dois renglones virava uma linha
        //    só ao entrar em edição e o card pulava de altura.
        // O `style` repete o do [Text], então o que muda entre ver e editar é
        // só o cursor.
        ? ComponentTheme<FocusOutlineTheme>(
            data: FocusOutlineTheme(
              border: Border.all(color: Colors.transparent),
            ),
            child: TextField(
              controller: titleController,
              focusNode: titleFocus,
              autofocus: true,
              maxLines: null,
              decoration: const BoxDecoration(),
              padding: EdgeInsets.zero,
              style: typo.body.copyWith(
                fontSize: 12.5,
                height: 1.35,
                color: colors.text,
              ),
              onSubmitted: (_) => onCommitTitle(),
              onEditingComplete: onCommitTitle,
            ),
          )
        : GestureDetector(
            onTap: onEditTitle,
            child: Text(
              card.title,
              style: typo.body.copyWith(
                fontSize: 12.5,
                height: 1.35,
                color: card.recognized ? colors.text : colors.text3,
                decoration: isLastColumn ? TextDecoration.lineThrough : null,
                decorationColor: colors.text3,
              ),
            ),
          );

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        onTap: onOpen,
        onSecondaryTapUp: (d) => onMenu(d.globalPosition),
        onLongPressStart: (d) => onMenu(d.globalPosition),
        child: Container(
          decoration: BoxDecoration(
            color: colors.panel2,
            borderRadius: BorderRadius.circular(5),
            // Borda uniforme: a faixa colorida do marcador é um filho, não um
            // `BorderSide` — o Flutter proíbe raio com borda não-uniforme.
            border: Border.all(color: selected ? colors.accent : colors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 3, color: stripe),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: title),
                            const SizedBox(width: 8),
                            // Card bloqueado não oferece o "avançar": é o
                            // sinal de que não deve seguir. Arrastar continua
                            // livre — é representação, não proibição.
                            if (!doc.isBlocked(card))
                              _AdvanceButton(
                                done: isLastColumn,
                                onTap: onAdvance,
                              ),
                          ],
                        ),
                        if (card.labels.isNotEmpty) ...[
                          const SizedBox(height: 7),
                          Wrap(
                            spacing: 5,
                            runSpacing: 4,
                            children: [
                              for (final label in card.labels)
                                _LabelChip(
                                  label: label,
                                  color: doc.colorOf(label),
                                ),
                            ],
                          ),
                        ],
                        if (!card.recognized) ...[
                          const SizedBox(height: 6),
                          Text(
                            context.t.cockpit.kanbanView.unrecognizedBlock,
                            style: typo.mono.copyWith(
                              fontSize: 9.5,
                              color: colors.text4,
                            ),
                          ),
                        ] else ...[
                          // Rodapé: número do card, comentários e dependência.
                          // A nota fica só no painel de detalhe — no card ela
                          // era uma linha cortada que não dizia nada.
                          const SizedBox(height: 7),
                          _CardFooter(card: card, doc: doc),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Rodapé do card: `#id`, ícone de comentários com a contagem (só se há
/// algum) e, se o card está bloqueado, o cadeado com a quantidade de
/// bloqueadores pendentes — só ícone e número, como os comentários. O card
/// que bloqueia outros não mostra nada: quem precisa saber é quem espera.
/// Tudo derivado do documento; nada aqui é editável.
class _CardFooter extends StatelessWidget {
  const _CardFooter({required this.card, required this.doc});

  final KanbanCard card;
  final KanbanDocument doc;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    final tr = context.t.cockpit.kanbanView;
    final small = typo.mono.copyWith(fontSize: 9.5, color: colors.text4);
    // Só os bloqueadores PENDENTES contam: o que já chegou à última coluna
    // não segura mais ninguém.
    final last = doc.columns.length - 1;
    final pending = [
      for (final b in doc.blockersOf(card))
        if (doc.columnOf(b) != last) b,
    ];
    final blocked = pending.isNotEmpty;
    Widget stat(IconData icon, String text, {Color? color, String? tip}) {
      final row = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color ?? colors.text4),
          const SizedBox(width: 3),
          Text(text, style: small.copyWith(color: color)),
        ],
      );
      if (tip == null) return row;
      return Tooltip(
        tooltip: TooltipContainer(child: Text(tip)).call,
        child: row,
      );
    }

    return Row(
      children: [
        if (card.id case final id?)
          Text('#$id', style: small)
        else
          const SizedBox.shrink(),
        const Spacer(),
        if (card.comments.isNotEmpty) ...[
          stat(Icons.chat_bubble_outline, '${card.comments.length}'),
          const SizedBox(width: 8),
        ],
        if (blocked)
          stat(
            Icons.lock_outline,
            '${pending.length}',
            color: colors.warn,
            tip: '${tr.blockedBy}\n${pending.map((b) => b.title).join('\n')}',
          ),
      ],
    );
  }
}

/// Chip de bloqueador no painel de detalhe: título do card bloqueador (ou o
/// id, quando desconhecido) e um `x` pra remover a dependência.
class _BlockerChip extends StatelessWidget {
  const _BlockerChip({
    required this.title,
    required this.done,
    required this.onRemove,
  });

  final String title;
  final bool done;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 2, 4, 2),
      decoration: BoxDecoration(
        border: Border.all(color: done ? colors.border2 : colors.warn),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.typo.mono.copyWith(
                fontSize: 10,
                color: done ? colors.text4 : colors.text,
                decoration: done ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          const SizedBox(width: 3),
          HoverTap(
            onTap: onRemove,
            padding: const EdgeInsets.all(2),
            borderRadius: BorderRadius.circular(4),
            child: Icon(Icons.close, size: 10, color: colors.text3),
          ),
        ],
      ),
    );
  }
}

/// O botão que empurra o card pra próxima coluna. Na última ele vira o check
/// preenchido e desfaz — riscar é chegada, não uma marcação à mão.
class _AdvanceButton extends StatelessWidget {
  const _AdvanceButton({required this.done, required this.onTap});
  final bool done;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tr = context.t.cockpit.kanbanView;
    return Tooltip(
      tooltip: TooltipContainer(
        child: Text(done ? tr.advanceBack : tr.advance),
      ).call,
      child: GestureDetector(
        // O toque no botão não abre o detalhe nem arrasta o card.
        onTap: onTap,
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? colors.text3 : colors.panel,
            border: Border.all(color: done ? colors.text3 : colors.border2),
          ),
          child: Icon(
            done ? Icons.check : Icons.arrow_forward,
            size: 11,
            color: done ? colors.panel : colors.text3,
          ),
        ),
      ),
    );
  }
}

class _AddCardButton extends StatelessWidget {
  const _AddCardButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      tooltip: TooltipContainer(
        child: Text(context.t.cockpit.kanbanView.newCard),
      ).call,
      child: HoverTap(
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: colors.border2, style: BorderStyle.solid),
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Icon(Icons.add, size: 18, color: colors.text3),
      ),
    );
  }
}

class _AddColumnRail extends StatelessWidget {
  const _AddColumnRail({required this.tooltip, required this.onTap});
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 46,
      padding: const EdgeInsets.only(top: 8),
      alignment: Alignment.topCenter,
      // Sem cor própria: as colunas não pintam fundo (deixam passar o
      // `colors.panel` do quadro), e um `colors.bg` aqui destacava a faixa
      // como se fosse outra superfície.
      child: Tooltip(
        tooltip: TooltipContainer(child: Text(tooltip)).call,
        child: HoverTap(
          onTap: onTap,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: colors.border2),
          padding: const EdgeInsets.all(6),
          child: Icon(Icons.add, size: 13, color: colors.text3),
        ),
      ),
    );
  }
}

class _ListRow extends StatelessWidget {
  const _ListRow({
    required this.card,
    required this.doc,
    required this.isLastColumn,
    required this.selected,
    required this.onAdvance,
    required this.onOpen,
    required this.onMenu,
  });

  final KanbanCard card;
  final KanbanDocument doc;
  final bool isLastColumn;
  final bool selected;
  final VoidCallback onAdvance;
  final VoidCallback onOpen;
  final void Function(Offset position) onMenu;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final stripe = card.labels.isEmpty
        ? colors.border2
        : kanbanLabelColor(context, doc.colorOf(card.labels.first));
    return GestureDetector(
      onTap: onOpen,
      onSecondaryTapUp: (d) => onMenu(d.globalPosition),
      onLongPressStart: (d) => onMenu(d.globalPosition),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? colors.panel3 : null,
          border: Border(bottom: BorderSide(color: colors.border)),
        ),
        child: Row(
          children: [
            Container(width: 3, height: 20, color: stripe),
            const SizedBox(width: 10),
            _AdvanceButton(done: isLastColumn, onTap: onAdvance),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                card.title,
                overflow: TextOverflow.ellipsis,
                style: context.typo.body.copyWith(
                  fontSize: 12.5,
                  color: colors.text,
                  decoration: isLastColumn ? TextDecoration.lineThrough : null,
                  decorationColor: colors.text3,
                ),
              ),
            ),
            for (final label in card.labels) ...[
              const SizedBox(width: 5),
              _LabelChip(label: label, color: doc.colorOf(label)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Painel de detalhe: a nota do card com o quadro ainda à vista. Não é modal
/// de propósito — dá pra ler a nota e mexer no quadro na mesma tela.
///
/// **Sem estado próprio, de propósito.** Os controllers e o modo de edição
/// moram no pai. A razão é uma ordem de eventos: quando o toque cai fora, o
/// `TapRegion` de fora fecha o painel no MESMO evento, e um commit disparado
/// de dentro (por foco ou por `dispose`) chega tarde demais — o widget já
/// morreu e a nota se perdia. Quem fecha é quem grava.
class _DetailPanel extends StatelessWidget {
  const _DetailPanel({
    required this.card,
    required this.doc,
    required this.column,
    required this.notesController,
    required this.notesFocus,
    required this.titleController,
    required this.editingTitle,
    required this.onStartTitleEdit,
    required this.onCommitTitle,
    required this.onClose,
    required this.onToggleLabel,
    required this.onManageLabels,
    required this.onSetBlockedBy,
    required this.commentController,
    required this.composingComment,
    required this.onStartComment,
    required this.onAddComment,
    required this.onCancelComment,
    required this.onDeleteComment,
  });

  final KanbanCard card;
  final KanbanDocument doc;
  final int column;
  final TextEditingController notesController;
  final FocusNode notesFocus;
  final TextEditingController titleController;
  final bool editingTitle;
  final VoidCallback onStartTitleEdit;
  final VoidCallback onCommitTitle;
  final VoidCallback onClose;
  final void Function(String label) onToggleLabel;
  final VoidCallback onManageLabels;

  /// Nova lista completa de bloqueadores (o painel monta a partir da atual).
  final void Function(List<KanbanCard> blockers) onSetBlockedBy;
  final TextEditingController commentController;
  final bool composingComment;
  final VoidCallback onStartComment;
  final VoidCallback onAddComment;
  final VoidCallback onCancelComment;
  final void Function(KanbanComment comment) onDeleteComment;

  /// Menu com busca listando os outros cards do quadro (coluna no rótulo);
  /// escolher um adiciona à lista atual.
  Future<void> _pickBlocker(
    BuildContext anchor,
    List<KanbanCard> current,
  ) async {
    final tr = anchor.t.cockpit.kanbanView;
    final items = <AppMenuItem<int>>[];
    for (final column in doc.columns) {
      for (final c in column.cards) {
        if (!c.recognized || c.startLine == card.startLine) continue;
        if (current.any((o) => o.startLine == c.startLine)) continue;
        items.add(
          AppMenuItem(
            value: c.startLine,
            label: '${c.title}  ·  ${column.name}',
            icon: Icons.crop_square,
          ),
        );
      }
    }
    if (items.isEmpty) return;
    final picked = await showAppMenu<int>(
      anchor,
      items: items,
      minWidth: 260,
      searchHint: tr.searchCards,
      searchThreshold: 6,
    );
    if (picked == null) return;
    final chosen = doc.columns
        .expand((c) => c.cards)
        .firstWhere((c) => c.startLine == picked);
    onSetBlockedBy([...current, chosen]);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    final tr = context.t.cockpit.kanbanView;
    final isLast = column == doc.columns.length - 1;

    final titleStyle = typo.title.copyWith(
      fontSize: 15,
      height: 1.3,
      color: colors.text,
      decoration: isLast ? TextDecoration.lineThrough : null,
      decorationColor: colors.text3,
    );

    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: colors.panel,
        border: Border(left: BorderSide(color: colors.border2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 32,
            padding: const EdgeInsets.fromLTRB(13, 0, 6, 0),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
            child: Row(
              children: [
                const Spacer(),
                HoverTap(
                  onTap: onClose,
                  padding: const EdgeInsets.all(3),
                  borderRadius: BorderRadius.circular(4),
                  child: Icon(Icons.close, size: 13, color: colors.text3),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(13, 12, 13, 16),
              children: [
                // Título editável aqui também: o painel é onde se lê o card
                // inteiro, e voltar ao quadro só pra corrigir uma palavra era
                // vaivém sem motivo. Mesma forma discreta do card — sem
                // moldura e sem anel de foco, o texto vira editável no lugar.
                if (editingTitle)
                  ComponentTheme<FocusOutlineTheme>(
                    data: FocusOutlineTheme(
                      border: Border.all(color: Colors.transparent),
                    ),
                    child: TextField(
                      controller: titleController,
                      autofocus: true,
                      maxLines: null,
                      decoration: const BoxDecoration(),
                      padding: EdgeInsets.zero,
                      style: titleStyle.copyWith(decoration: null),
                      onSubmitted: (_) => onCommitTitle(),
                      onEditingComplete: onCommitTitle,
                    ),
                  )
                else
                  GestureDetector(
                    onTap: card.recognized ? onStartTitleEdit : null,
                    child: Text(card.title, style: titleStyle),
                  ),
                const SizedBox(height: 11),
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final label in doc.allLabels)
                      GestureDetector(
                        onTap: () => onToggleLabel(label),
                        child: Opacity(
                          opacity: card.labels.contains(label) ? 1 : 0.35,
                          child: _LabelChip(
                            label: label,
                            color: doc.colorOf(label),
                          ),
                        ),
                      ),
                    // Os chips acima APLICAM marcadores que já existem; criar e
                    // apagar é outra coisa, e mora atrás deste botão. Misturar
                    // as duas na mesma fileira é o que faz um quadro juntar
                    // marcadores duplicados.
                    _IconAction(
                      icon: Icons.label_outline,
                      tooltip: tr.manageLabels,
                      onTap: onManageLabels,
                    ),
                  ],
                ),
                const SizedBox(height: 11),
                // Dependências: quem segura este card. Chips com o título do
                // bloqueador (riscado quando já terminou) e um botão que abre
                // o picker de cards por título. O inverso ("bloqueia N") é só
                // informativo, no rodapé do card.
                Builder(
                  builder: (anchor) {
                    final blockers = doc.blockersOf(card);
                    final unknown = doc.unknownBlockers(card);
                    final last = doc.columns.length - 1;
                    return Wrap(
                      spacing: 5,
                      runSpacing: 5,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          tr.blockedBy.toUpperCase(),
                          style: typo.mono.copyWith(
                            fontSize: 10,
                            letterSpacing: 0.9,
                            color: colors.text4,
                          ),
                        ),
                        for (final b in blockers)
                          _BlockerChip(
                            title: b.title,
                            done: doc.columnOf(b) == last,
                            onRemove: () => onSetBlockedBy([
                              for (final o in blockers)
                                if (o.startLine != b.startLine) o,
                            ]),
                          ),
                        for (final id in unknown)
                          _BlockerChip(
                            title: '$id (${tr.unknownCard})',
                            done: true,
                            onRemove: () => onSetBlockedBy(blockers),
                          ),
                        if (card.recognized)
                          _IconAction(
                            icon: Icons.add_link,
                            tooltip: tr.addBlocker,
                            onTap: () => _pickBlocker(anchor, blockers),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 11),
                Row(
                  children: [
                    // Só o nome da coluna; mover é pelo card/arrastar, não
                    // pelo painel de detalhe.
                    Container(
                      padding: const EdgeInsets.fromLTRB(9, 3, 9, 3),
                      decoration: BoxDecoration(
                        border: Border.all(color: colors.border2),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        column >= 0 ? doc.columns[column].name : '',
                        style: typo.mono.copyWith(
                          fontSize: 11,
                          color: colors.text,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (card.id != null)
                      Text(
                        card.id!,
                        style: typo.mono.copyWith(
                          fontSize: 10,
                          color: colors.text4,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: colors.border)),
                  ),
                ),
                Text(
                  tr.notes.toUpperCase(),
                  style: typo.mono.copyWith(
                    fontSize: 10,
                    letterSpacing: 0.9,
                    color: colors.text4,
                  ),
                ),
                const SizedBox(height: 8),
                // A nota é um campo o tempo todo, com moldura à mostra — o
                // oposto do título. Ninguém adivinha que um parágrafo de texto
                // solto aceita clique, e o card sem nota precisa de um convite,
                // que é o placeholder.
                TextField(
                  controller: notesController,
                  focusNode: notesFocus,
                  enabled: card.recognized,
                  maxLines: null,
                  minLines: 6,
                  placeholder: Text(tr.notesPlaceholder),
                  style: typo.mono.copyWith(fontSize: 11.5, color: colors.text),
                  border: Border.all(color: colors.border2),
                  borderRadius: BorderRadius.circular(5),
                  padding: const EdgeInsets.all(8),
                  // Só tira o foco. Sobrescrever `onTapOutside` substitui o
                  // padrão do Flutter (que é justamente dar `unfocus`), e sem
                  // blur o campo ficava focado para sempre. Quem grava é o pai,
                  // ao fechar ou trocar de card.
                  onTapOutside: (_) => notesFocus.unfocus(),
                ),
                const SizedBox(height: 18),
                // Comentários: o registro do que foi acontecendo, separado da
                // nota (que descreve o card). O mais novo em cima, porque é o
                // que se quer ler primeiro ao reabrir o card.
                Row(
                  children: [
                    Text(
                      tr.comments.toUpperCase(),
                      style: typo.mono.copyWith(
                        fontSize: 10,
                        letterSpacing: 0.9,
                        color: colors.text4,
                      ),
                    ),
                    const Spacer(),
                    if (!composingComment && card.recognized)
                      _IconAction(
                        icon: Icons.add,
                        tooltip: tr.addComment,
                        onTap: onStartComment,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                // O compositor só existe enquanto se escreve: ao adicionar, ele
                // some e o comentário toma o seu lugar no topo da lista.
                if (composingComment) ...[
                  TextField(
                    controller: commentController,
                    autofocus: true,
                    maxLines: null,
                    minLines: 3,
                    placeholder: Text(tr.commentPlaceholder),
                    style: typo.body.copyWith(fontSize: 12, color: colors.text),
                    border: Border.all(color: colors.accent),
                    borderRadius: BorderRadius.circular(5),
                    padding: const EdgeInsets.all(8),
                  ),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      const Spacer(),
                      GhostButton(
                        onPressed: onCancelComment,
                        child: Text(context.t.common.cancel),
                      ),
                      const SizedBox(width: 6),
                      PrimaryButton(
                        onPressed: onAddComment,
                        child: Text(context.t.common.add),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                for (final comment in card.comments)
                  _CommentTile(
                    comment: comment,
                    onDelete: () => onDeleteComment(comment),
                  ),
                if (card.comments.isEmpty && !composingComment)
                  Text(
                    tr.noComments,
                    style: typo.body.copyWith(
                      fontSize: 12,
                      color: colors.text4,
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

/// Um comentário na lista: data discreta no topo, texto embaixo, e a lixeira
/// que só aparece no hover — apagar é raro e não pode competir com a leitura.
class _CommentTile extends StatefulWidget {
  const _CommentTile({required this.comment, required this.onDelete});

  final KanbanComment comment;
  final VoidCallback onDelete;

  @override
  State<_CommentTile> createState() => _CommentTileState();
}

class _CommentTileState extends State<_CommentTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    final at = widget.comment.createdAt;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        margin: const EdgeInsets.only(bottom: 7),
        padding: const EdgeInsets.fromLTRB(9, 7, 7, 8),
        decoration: BoxDecoration(
          color: colors.panel2,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (at != null && at.isNotEmpty)
                  Text(
                    // Valor de máquina (ISO): sem reformatar por locale, só o
                    // `T` trocado por espaço pra ler melhor.
                    at.replaceFirst('T', ' '),
                    style: typo.mono.copyWith(
                      fontSize: 9.5,
                      color: colors.text4,
                    ),
                  ),
                const Spacer(),
                if (_hover)
                  HoverTap(
                    onTap: widget.onDelete,
                    padding: const EdgeInsets.all(2),
                    borderRadius: BorderRadius.circular(4),
                    child: Icon(
                      Icons.delete_outline,
                      size: 12,
                      color: colors.text4,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              widget.comment.text,
              style: typo.body.copyWith(
                fontSize: 12,
                height: 1.4,
                color: colors.text2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Gerenciador de marcadores: um lugar só onde marcador nasce, muda de cor e
/// morre. O menu do card apenas **aplica** os que já existem — criar no meio
/// do fluxo é o que faz um quadro juntar quarenta tags duplicadas.
class _LabelsDialog extends StatefulWidget {
  const _LabelsDialog({
    required this.doc,
    required this.onUpsert,
    required this.onDelete,
  });

  final KanbanDocument doc;
  final Future<KanbanDocument> Function(String name, KanbanLabelColor color)
  onUpsert;
  final Future<KanbanDocument> Function(String name) onDelete;

  @override
  State<_LabelsDialog> createState() => _LabelsDialogState();
}

class _LabelsDialogState extends State<_LabelsDialog> {
  late KanbanDocument _doc = widget.doc;
  final TextEditingController _newLabel = TextEditingController();

  @override
  void dispose() {
    _newLabel.dispose();
    super.dispose();
  }

  Future<void> _upsert(String name, KanbanLabelColor color) async {
    final doc = await widget.onUpsert(name, color);
    if (mounted) setState(() => _doc = doc);
  }

  Future<void> _delete(String name) async {
    final doc = await widget.onDelete(name);
    if (mounted) setState(() => _doc = doc);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    final tr = context.t.cockpit.kanbanView;
    final labels = _doc.allLabels;

    return AlertDialog(
      title: Text(
        tr.labelsTitle,
        style: typo.title.copyWith(fontSize: 15, color: colors.text),
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final label in labels)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: colors.border)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: typo.mono.copyWith(
                          fontSize: 12,
                          color: kanbanLabelColor(context, _doc.colorOf(label)),
                        ),
                      ),
                    ),
                    for (final color in KanbanLabelColor.values)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: GestureDetector(
                          onTap: () => _upsert(label, color),
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: kanbanLabelColor(context, color),
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(
                                color: _doc.colorOf(label) == color
                                    ? colors.text
                                    : colors.border,
                              ),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(width: 12),
                    // O contador é a defesa antes de apagar: diz quantos cards
                    // perdem o marcador.
                    Text(
                      tr.labelUsage(n: _doc.usageOf(label)),
                      style: typo.mono.copyWith(
                        fontSize: 10,
                        color: colors.text4,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Tooltip(
                      tooltip: TooltipContainer(
                        child: Text(tr.deleteLabel),
                      ).call,
                      child: HoverTap(
                        onTap: () => _delete(label),
                        padding: const EdgeInsets.all(3),
                        borderRadius: BorderRadius.circular(4),
                        child: Icon(
                          Icons.delete_outline,
                          size: 13,
                          color: colors.text4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newLabel,
                    placeholder: Text(tr.labelNamePlaceholder),
                    style: typo.mono.copyWith(fontSize: 12, color: colors.text),
                    border: Border.all(color: colors.border),
                    borderRadius: BorderRadius.circular(5),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 6,
                    ),
                    onSubmitted: (v) {
                      if (v.trim().isEmpty) return;
                      _upsert(v, KanbanLabelColor.blue);
                      _newLabel.clear();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                SecondaryButton(
                  onPressed: () {
                    if (_newLabel.text.trim().isEmpty) return;
                    _upsert(_newLabel.text, KanbanLabelColor.blue);
                    _newLabel.clear();
                  },
                  child: Text(context.t.common.add),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        PrimaryButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.t.common.close),
        ),
      ],
    );
  }
}

/// Conteúdo do popover de filtro: campo de texto (título) + chips de
/// marcadores que alternam + limpar. Guarda uma cópia local pra redesenhar os
/// chips na hora e devolve tudo por [onChanged] a cada mudança.
class _FilterPopup extends StatefulWidget {
  const _FilterPopup({
    required this.labels,
    required this.labelColors,
    required this.text,
    required this.selected,
    required this.blocked,
    required this.onChanged,
  });

  final List<String> labels;
  final Map<String, KanbanLabelColor> labelColors;
  final String text;
  final Set<String> selected;
  final bool? blocked;
  final void Function(String text, Set<String> labels, bool? blocked) onChanged;

  @override
  State<_FilterPopup> createState() => _FilterPopupState();
}

class _FilterPopupState extends State<_FilterPopup> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.text,
  );
  late final Set<String> _selected = {...widget.selected};
  late bool? _blocked = widget.blocked;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _emit() => widget.onChanged(_ctrl.text.trim(), _selected, _blocked);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    final tr = context.t.cockpit.kanbanView;
    final hasAny =
        _ctrl.text.trim().isNotEmpty ||
        _selected.isNotEmpty ||
        _blocked != null;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 320),
      child: MenuPopup(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  key: const ValueKey('kanban-filter-text'),
                  controller: _ctrl,
                  autofocus: true,
                  placeholder: Text(
                    tr.filterTitlePlaceholder,
                    style: typo.body.copyWith(
                      fontSize: 12.5,
                      color: colors.text4,
                    ),
                  ),
                  style: typo.body.copyWith(fontSize: 12.5, color: colors.text),
                  border: Border.all(color: colors.border),
                  borderRadius: BorderRadius.circular(6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  onChanged: (_) => setState(_emit),
                ),
                if (widget.labels.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    tr.filterLabels,
                    style: typo.mono.copyWith(
                      fontSize: 10,
                      letterSpacing: 0.8,
                      color: colors.text4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final label in widget.labels)
                        _FilterLabelChip(
                          key: ValueKey('kanban-filter-label-$label'),
                          label: label,
                          color:
                              widget.labelColors[label] ??
                              KanbanLabelColor.gray,
                          selected: _selected.contains(label),
                          onTap: () => setState(() {
                            if (!_selected.remove(label)) _selected.add(label);
                            _emit();
                          }),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  tr.filterDependencies,
                  style: typo.mono.copyWith(
                    fontSize: 10,
                    letterSpacing: 0.8,
                    color: colors.text4,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: [
                    _FilterLabelChip(
                      key: const ValueKey('kanban-filter-blocked'),
                      label: tr.filterBlocked,
                      color: KanbanLabelColor.red,
                      selected: _blocked == true,
                      onTap: () => setState(() {
                        _blocked = _blocked == true ? null : true;
                        _emit();
                      }),
                    ),
                    _FilterLabelChip(
                      key: const ValueKey('kanban-filter-ready'),
                      label: tr.filterReady,
                      color: KanbanLabelColor.green,
                      selected: _blocked == false,
                      onTap: () => setState(() {
                        _blocked = _blocked == false ? null : false;
                        _emit();
                      }),
                    ),
                  ],
                ),
                if (hasAny) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: GhostButton(
                      key: const ValueKey('kanban-filter-clear'),
                      density: ButtonDensity.compact,
                      onPressed: () => setState(() {
                        _ctrl.clear();
                        _selected.clear();
                        _blocked = null;
                        _emit();
                      }),
                      child: Text(tr.filterClear),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Chip de marcador clicável do filtro: contorno quando fora, preenchido
/// quando selecionado. Mesma paleta do [_LabelChip].
class _FilterLabelChip extends StatelessWidget {
  const _FilterLabelChip({
    super.key,
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final KanbanLabelColor color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final resolved = kanbanLabelColor(context, color);
    return HoverTap(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: selected ? resolved : null,
          border: Border.all(color: resolved),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          label,
          style: context.typo.mono.copyWith(
            fontSize: 10.5,
            color: selected ? context.colors.panel : resolved,
          ),
        ),
      ),
    );
  }
}

class _LabelChip extends StatelessWidget {
  const _LabelChip({required this.label, required this.color});
  final String label;
  final KanbanLabelColor color;

  @override
  Widget build(BuildContext context) {
    final resolved = kanbanLabelColor(context, color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: resolved),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        label,
        style: context.typo.mono.copyWith(fontSize: 9.5, color: resolved),
      ),
    );
  }
}

class _LabelDot extends StatelessWidget {
  const _LabelDot({required this.color});
  final KanbanLabelColor color;

  @override
  Widget build(BuildContext context) => Container(
    width: 9,
    height: 9,
    decoration: BoxDecoration(
      color: kanbanLabelColor(context, color),
      borderRadius: BorderRadius.circular(2),
    ),
  );
}

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.asList, required this.onChanged});
  final bool asList;
  final void Function(bool asList) onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tr = context.t.cockpit.kanbanView;
    Widget segment(
      IconData icon,
      String tooltip,
      bool on,
      VoidCallback onTap,
    ) => Tooltip(
      tooltip: TooltipContainer(child: Text(tooltip)).call,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: on ? colors.accent : Colors.transparent,
          child: Icon(
            icon,
            size: 13,
            color: on ? colors.accentText : colors.text3,
          ),
        ),
      ),
    );

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: colors.border2),
        borderRadius: BorderRadius.circular(5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          segment(
            Icons.view_column_outlined,
            tr.boardView,
            !asList,
            () => onChanged(false),
          ),
          segment(
            Icons.format_list_bulleted,
            tr.listView,
            asList,
            () => onChanged(true),
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
    required this.onTap,
    this.busy = false,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool busy;

  /// Realça o ícone (accent) quando a ação representa um estado ligado, como
  /// um filtro aplicado.
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      tooltip: TooltipContainer(child: Text(tooltip)).call,
      child: HoverTap(
        onTap: busy ? null : onTap,
        padding: const EdgeInsets.all(4),
        borderRadius: BorderRadius.circular(4),
        child: Icon(
          icon,
          size: 14,
          color: busy
              ? colors.text4
              : active
              ? colors.accent
              : colors.text3,
        ),
      ),
    );
  }
}

/// Resolve a cor nomeada do marcador num token do tema atual — cor livre (hex)
/// não sobreviveria à troca de tema claro/escuro.
Color kanbanLabelColor(BuildContext context, KanbanLabelColor color) {
  final colors = context.colors;
  return switch (color) {
    KanbanLabelColor.orange => colors.gitConflict,
    KanbanLabelColor.purple => colors.edited,
    KanbanLabelColor.red => colors.error,
    KanbanLabelColor.green => colors.online,
    KanbanLabelColor.amber => colors.warn,
    KanbanLabelColor.blue => colors.gitUntracked,
    KanbanLabelColor.gray => colors.text3,
  };
}

/// Caminho a mostrar na barra: **relativo** quando o arquivo está dentro do
/// workspace, e a partir de `~` quando está fora dele mas dentro da pasta do
/// usuário. Só cai no caminho absoluto cru quando não é nenhum dos dois.
///
/// Usa o [relativeUnder] do core em vez de comparar strings aqui: é ele que
/// normaliza `\` para `/`, e foi criado justamente porque no Windows o
/// `dart:io` devolve caminho nativo e as comparações davam falso.
String kanbanDisplayPath(String path, String workspaceRoot) {
  if (workspaceRoot.isNotEmpty) {
    final relative = relativeUnder(path, workspaceRoot);
    if (relative.isNotEmpty) return relative;
  }

  final home = userHome();
  if (home != null && home.isNotEmpty) {
    final relative = relativeUnder(path, home);
    if (relative.isNotEmpty) return '~/$relative';
  }
  return path;
}
