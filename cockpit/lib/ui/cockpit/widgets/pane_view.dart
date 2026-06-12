import 'dart:io';
import 'dart:math';

import 'package:cockpit/ui/cockpit/session/agent_session.dart';
import 'package:cockpit/ui/cockpit/session/file_viewer_session.dart';
import 'package:cockpit/ui/cockpit/session/pane_item.dart';
import 'package:cockpit/ui/cockpit/session/terminal_session.dart';
import 'package:cockpit/ui/cockpit/states/pane_node.dart';
import 'package:cockpit/ui/cockpit/viewmodels/cockpit_viewmodel.dart';
import 'package:cockpit/ui/cockpit/widgets/agent_composer.dart';
import 'package:cockpit/ui/cockpit/widgets/agent_transcript.dart';
import 'package:cockpit/ui/cockpit/widgets/app_menu.dart';
import 'package:cockpit/ui/cockpit/widgets/confirm_dialog.dart';
import 'package:cockpit/ui/cockpit/widgets/empty_pane.dart';
import 'package:cockpit/ui/cockpit/widgets/file_viewer.dart';
import 'package:cockpit/ui/core/file_icons/file_icons.dart';
import 'package:cockpit/ui/core/themes/terminal_theme.dart';
import 'package:cockpit/ui/core/themes/themes.dart';
import 'package:cockpit/ui/settings/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';

/// Folha do multiplexador: tab strip + corpo (agente: transcript+composer / empty;
/// terminal: TerminalView). O foco aparece **só na aba ativa**.
class PaneView extends StatelessWidget {
  const PaneView({
    super.key,
    required this.pane,
    required this.vm,
    required this.focused,
    required this.onCreateTab,
    required this.onSplit,
    required this.onFillEmpty,
    required this.onHistoryAgent,
    required this.onRenameAgent,
    required this.onToggleRelayAgent,
  });

  final LeafPane pane;
  final CockpitViewModel vm;
  final bool focused;

  /// Abre uma aba "Novo" (placeholder vazio) — o tipo é escolhido dentro dela.
  final VoidCallback onCreateTab;
  final ValueChanged<SplitDir> onSplit;

  /// Preenche a pane vazia — `(emptyId, terminal)`.
  final void Function(String emptyId, bool terminal) onFillEmpty;

  /// Abre o histórico de sessões de um agente (por id da aba).
  final ValueChanged<String> onHistoryAgent;

  /// Renomeia o agente (id da aba, novo nome já sanitizado).
  final void Function(String agentId, String name) onRenameAgent;

  /// Alterna o auto-relay do agente (por id da aba).
  final ValueChanged<String> onToggleRelayAgent;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final active = vm.session(pane.active);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: (_) => vm.focus(pane.id),
      child: Container(
        color: colors.panel,
        child: Column(
          children: [
            _TabStrip(
              pane: pane,
              vm: vm,
              focused: focused,
              onCreateTab: onCreateTab,
              onSplit: onSplit,
              onHistoryAgent: onHistoryAgent,
              onRenameAgent: onRenameAgent,
              onToggleRelayAgent: onToggleRelayAgent,
            ),
            Expanded(
              child: active == null
                  ? const SizedBox.shrink()
                  : _PaneBody(
                      key: ValueKey('body-${active.id}'),
                      item: active,
                      focused: focused,
                      onFillEmpty: (terminal) =>
                          onFillEmpty(active.id, terminal),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Largura fixa de uma aba — também usada pra calcular o auto-scroll do ativo.
const double _kTabWidth = 188;

/// Ícone por tipo de aba (usado na aba e no dropdown "todas as abas").
IconData _tabIcon(PaneItem? item) {
  if (item is TerminalSession) return Icons.terminal_outlined;
  if (item is FileViewerSession) return Icons.description_outlined;
  if (item is AgentSession && item.status == AgentStatus.empty) {
    return Icons.edit_outlined;
  }
  return Icons.auto_awesome;
}

class _TabStrip extends StatefulWidget {
  const _TabStrip({
    required this.pane,
    required this.vm,
    required this.focused,
    required this.onCreateTab,
    required this.onSplit,
    required this.onHistoryAgent,
    required this.onRenameAgent,
    required this.onToggleRelayAgent,
  });

  final LeafPane pane;
  final CockpitViewModel vm;
  final bool focused;
  final VoidCallback onCreateTab;
  final ValueChanged<SplitDir> onSplit;
  final ValueChanged<String> onHistoryAgent;
  final void Function(String agentId, String name) onRenameAgent;
  final ValueChanged<String> onToggleRelayAgent;

  @override
  State<_TabStrip> createState() => _TabStripState();
}

class _TabStripState extends State<_TabStrip> {
  final ScrollController _scroll = ScrollController();
  bool _overflowing = false;
  bool _hovering = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollActiveIntoView();
      _syncOverflow();
    });
  }

  @override
  void didUpdateWidget(_TabStrip old) {
    super.didUpdateWidget(old);
    final activeChanged = old.pane.active != widget.pane.active;
    final countChanged = old.pane.tabs.length != widget.pane.tabs.length;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (activeChanged || countChanged) _scrollActiveIntoView();
      _syncOverflow();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _setHover(bool value) {
    if (value != _hovering) setState(() => _hovering = value);
  }

  /// Mostra/esconde o botão de overflow conforme a strip realmente estoura.
  void _syncOverflow() {
    if (!_scroll.hasClients) return;
    final over = _scroll.position.maxScrollExtent > 0.5;
    if (over != _overflowing) setState(() => _overflowing = over);
  }

  /// Rola a aba ativa pra dentro da área visível (largura fixa → offset = i*W).
  void _scrollActiveIntoView() {
    if (!_scroll.hasClients) return;
    final index = widget.pane.tabs.indexOf(widget.pane.active);
    if (index < 0) return;
    final pos = _scroll.position;
    final start = index * _kTabWidth;
    final end = start + _kTabWidth;
    final viewStart = pos.pixels;
    final viewEnd = viewStart + pos.viewportDimension;
    double? target;
    if (start < viewStart) {
      target = start;
    } else if (end > viewEnd) {
      target = end - pos.viewportDimension;
    }
    if (target != null) {
      _scroll.animateTo(
        target.clamp(0.0, pos.maxScrollExtent),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _confirmClosePane(BuildContext context) async {
    final count = widget.pane.tabs.length;
    final ok = await showConfirmDialog(
      context,
      title: 'Close pane?',
      message:
          'This closes all $count tab(s) in this pane and ends the agents/'
          'terminals in it.',
      confirmLabel: 'Close',
      danger: true,
    );
    if (ok) widget.vm.closePane(widget.pane.id);
  }

  /// Dropdown com todas as abas (pular direto pra uma) — aparece no overflow.
  Future<void> _showTabList(BuildContext anchor) async {
    final pane = widget.pane;
    final picked = await showAppMenu<String>(
      anchor,
      minWidth: 220,
      items: [
        for (final id in pane.tabs)
          AppMenuItem(
            value: id,
            label: widget.vm.session(id)?.title ?? '—',
            icon: _tabIcon(widget.vm.session(id)),
            selected: id == pane.active,
          ),
      ],
    );
    if (picked != null) widget.vm.selectTab(pane.id, picked);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final pane = widget.pane;
    // Re-checa overflow a cada layout (resize de pane, add/remove de aba).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncOverflow();
    });
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: colors.bg,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: MouseRegion(
              onEnter: (_) => _setHover(true),
              onExit: (_) => _setHover(false),
              child: Scrollbar(
                controller: _scroll,
                // Só aparece com o mouse em cima (e quando há overflow).
                thumbVisibility: _hovering && _overflowing,
                thickness: 3,
                radius: const Radius.circular(3),
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(
                    context,
                  ).copyWith(scrollbars: false),
                  child: SingleChildScrollView(
                    controller: _scroll,
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (var i = 0; i < pane.tabs.length; i++)
                          _TabDropSlot(
                            index: i,
                            onInsert: (data, index) => widget.vm.moveTabToIndex(
                              data.paneId,
                              data.tabId,
                              pane.id,
                              index,
                            ),
                            child: _Tab(
                              item: widget.vm.session(pane.tabs[i]),
                              paneId: pane.id,
                              active: pane.tabs[i] == pane.active,
                              focused: widget.focused,
                              onSelect: () =>
                                  widget.vm.selectTab(pane.id, pane.tabs[i]),
                              onClose: () =>
                                  widget.vm.closeTab(pane.id, pane.tabs[i]),
                              onRename: (name) =>
                                  widget.onRenameAgent(pane.tabs[i], name),
                              onToggleRelay: () =>
                                  widget.onToggleRelayAgent(pane.tabs[i]),
                              onHistory: () =>
                                  widget.onHistoryAgent(pane.tabs[i]),
                            ),
                          ),
                        _TabAdd(onTap: widget.onCreateTab),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Overflow: lista todas as abas pra pular direto (só quando estoura).
          if (_overflowing)
            Builder(
              builder: (ctx) => _StripButton(
                icon: Icons.keyboard_arrow_down,
                tooltip: 'All tabs',
                onTap: () => _showTabList(ctx),
              ),
            ),
          _PaneTools(
            onSplitRight: () => widget.onSplit(SplitDir.vertical),
            onSplitDown: () => widget.onSplit(SplitDir.horizontal),
            onClosePane: () => _confirmClosePane(context),
          ),
        ],
      ),
    );
  }
}

/// Botãozinho de ícone da tab strip (28px) — overflow, etc.
class _StripButton extends StatelessWidget {
  const _StripButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(5),
        onTap: onTap,
        child: SizedBox(
          width: 28,
          height: 28,
          child: Icon(icon, size: 16, color: context.colors.text3),
        ),
      ),
    );
  }
}

class _Tab extends StatefulWidget {
  const _Tab({
    required this.item,
    required this.paneId,
    required this.active,
    required this.focused,
    required this.onSelect,
    required this.onClose,
    required this.onRename,
    required this.onToggleRelay,
    required this.onHistory,
  });

  final PaneItem? item;
  final String paneId;
  final bool active;
  final bool focused;
  final VoidCallback onSelect;
  final VoidCallback onClose;
  final ValueChanged<String> onRename;
  final VoidCallback onToggleRelay;
  final VoidCallback onHistory;

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  bool _editing = false;
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(_Tab old) {
    super.didUpdateWidget(old);
    // Se a aba mudou enquanto estava editando, cancela a edição.
    if (old.item?.id != widget.item?.id && _editing) {
      setState(() => _editing = false);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startEditing() {
    final s = widget.item;
    if (s is! AgentSession) return;
    _ctrl.text = s.title;
    _ctrl.selection = TextSelection(
      baseOffset: 0,
      extentOffset: s.title.length,
    );
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _commitEdit() {
    if (!_editing) return;
    final name = _ctrl.text.trim().replaceAll(' ', '-');
    setState(() => _editing = false);
    if (name.isNotEmpty) widget.onRename(name);
  }

  void _cancelEdit() {
    setState(() => _editing = false);
  }

  void _onFocusChange() {
    if (!_focus.hasFocus && _editing) _commitEdit();
  }

  Future<void> _showTabMenu(BuildContext menuCtx) async {
    final s = widget.item;
    if (s == null) return;
    final agent = s is AgentSession ? s : null;
    final isEmpty = agent?.status == AgentStatus.empty;

    final value = await showAppMenu<String>(
      menuCtx,
      minWidth: 150,
      items: [
        if (agent != null && !isEmpty) ...[
          const AppMenuItem(
            value: 'rename',
            label: 'Rename',
            icon: Icons.edit_outlined,
          ),
          AppMenuItem(
            value: 'relay',
            label: 'Auto-relay',
            icon: Icons.cell_tower_outlined,
            selected: agent.autoStartRelay,
          ),
          const AppMenuItem(
            value: 'history',
            label: 'History',
            icon: Icons.history,
          ),
        ],
        const AppMenuItem(value: 'close', label: 'Close', icon: Icons.close),
      ],
    );
    if (!mounted) return;
    switch (value) {
      case 'rename':
        _startEditing();
      case 'relay':
        widget.onToggleRelay();
      case 'history':
        widget.onHistory();
      case 'close':
        widget.onClose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.item;
    if (s == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: s,
      builder: (_, _) {
        final colors = context.colors;
        final isFocusedActive = widget.active && widget.focused;
        final agent = s is AgentSession ? s : null;
        final isEmpty = agent?.status == AgentStatus.empty;
        final streaming = agent?.isStreaming ?? false;

        final icon = _tabIcon(s);

        // Título: texto normal ou campo inline ao renomear.
        final titleWidget = _editing && agent != null
            ? CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.escape): _cancelEdit,
                },
                child: TextField(
                  controller: _ctrl,
                  focusNode: _focus,
                  onSubmitted: (_) => _commitEdit(),
                  style: context.typo.tab.copyWith(
                    fontSize: 12,
                    color: colors.text,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter(
                      RegExp(r' '),
                      allow: false,
                      replacementString: '-',
                    ),
                  ],
                ),
              )
            : Text(
                s.title,
                overflow: TextOverflow.ellipsis,
                style: context.typo.tab.copyWith(
                  color: isFocusedActive || widget.active
                      ? colors.text
                      : colors.text3,
                ),
              );

        final tabBody = Container(
          height: 40,
          width: _kTabWidth,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.active ? colors.panel : colors.bg,
            border: Border(right: BorderSide(color: colors.border)),
          ),
          foregroundDecoration: isFocusedActive
              ? BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: colors.accent, width: 2),
                  ),
                )
              : null,
          padding: const EdgeInsets.only(left: 11, right: 7),
          child: Row(
            children: [
              if (s is FileViewerSession)
                FileTypeIcon.file(s.title, size: 15)
              else
                Icon(
                  icon,
                  size: 13,
                  color: isFocusedActive
                      ? colors.accentText
                      : (widget.active ? colors.text2 : colors.text3),
                ),
              const SizedBox(width: 7),
              Expanded(child: titleWidget),
              const SizedBox(width: 10),
              if (streaming) ...[
                SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: colors.accent,
                  ),
                ),
                const SizedBox(width: 7),
              ] else if (s.unseenFinish) ...[
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: colors.accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
              ],
              _TabClose(onTap: widget.onClose),
            ],
          ),
        );

        // Ao editar o nome, desabilita drag e cliques de seleção para não
        // interferir com a seleção de texto no TextField.
        if (_editing) return tabBody;

        // Builder garante um BuildContext com RenderBox para showAppMenu.
        final interactive = Builder(
          builder: (menuCtx) => GestureDetector(
            onTapUp: (d) => widget.onSelect(),
            onDoubleTap: agent != null && !isEmpty ? _startEditing : null,
            onSecondaryTapUp: isEmpty ? null : (d) => _showTabMenu(menuCtx),
            child: tabBody,
          ),
        );

        return Draggable<TabDragData>(
          data: TabDragData(paneId: widget.paneId, tabId: s.id),
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: Transform.translate(
            offset: const Offset(12, 8),
            child: _DragFeedback(icon: icon, title: s.title),
          ),
          childWhenDragging: Opacity(opacity: 0.3, child: tabBody),
          child: interactive,
        );
      },
    );
  }
}

/// Alvo de drop por aba: ao arrastar outra aba pra cima desta, mostra um caret
/// vertical no lado (esquerda = inserir antes, direita = depois) e, ao soltar,
/// insere/reordena naquela posição. É o que permite **trocar abas de lugar**.
class _TabDropSlot extends StatefulWidget {
  const _TabDropSlot({
    required this.index,
    required this.onInsert,
    required this.child,
  });

  final int index;
  final void Function(TabDragData data, int index) onInsert;
  final Widget child;

  @override
  State<_TabDropSlot> createState() => _TabDropSlotState();
}

class _TabDropSlotState extends State<_TabDropSlot> {
  /// `null` = sem caret; `true` = caret à esquerda (antes); `false` = direita.
  bool? _before;

  void _update(Offset global) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final local = box.globalToLocal(global);
    final before = local.dx < box.size.width / 2;
    if (before != _before) setState(() => _before = before);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DragTarget<TabDragData>(
      onMove: (d) => _update(d.offset),
      onLeave: (_) {
        if (_before != null) setState(() => _before = null);
      },
      onAcceptWithDetails: (d) {
        final before = _before ?? true;
        setState(() => _before = null);
        widget.onInsert(d.data, before ? widget.index : widget.index + 1);
      },
      builder: (context, candidate, rejected) {
        final caret = candidate.isNotEmpty ? _before : null;
        return Stack(
          children: [
            widget.child,
            if (caret != null)
              Positioned(
                top: 6,
                bottom: 6,
                left: caret ? 0 : null,
                right: caret ? null : 0,
                child: Container(
                  width: 2.5,
                  decoration: BoxDecoration(
                    color: colors.accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _TabClose extends StatelessWidget {
  const _TabClose({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Icon(Icons.close, size: 12, color: context.colors.text3),
        ),
      ),
    );
  }
}

/// "+" — abre direto uma aba "Novo" (placeholder); o tipo (agente/terminal) é
/// escolhido dentro da aba.
class _TabAdd extends StatelessWidget {
  const _TabAdd({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      message: 'New tab',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: colors.border)),
            ),
            child: Icon(Icons.add, size: 14, color: colors.text4),
          ),
        ),
      ),
    );
  }
}

class _PaneTools extends StatelessWidget {
  const _PaneTools({
    required this.onSplitRight,
    required this.onSplitDown,
    required this.onClosePane,
  });

  final VoidCallback onSplitRight;
  final VoidCallback onSplitDown;
  final VoidCallback onClosePane;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final iconColor = colors.text3;
    const spacing = 13.0;
    Widget btn(Widget icon, String tip, VoidCallback onTap) => Tooltip(
      message: tip,
      child: InkWell(
        mouseCursor: SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(5),
        onTap: onTap,
        child: SizedBox(width: spacing, height: spacing, child: icon),
      ),
    );
    // Mesma base (splitscreen = dois painéis), pra ler "horizontal vs vertical"
    // num relance: empilhado = dividir abaixo; girado 90° (colunas lado-a-lado)
    // = dividir à direita. (Mockup.)

    return Padding(
      padding: const EdgeInsets.only(right: spacing),
      child: Row(
        spacing: 12,
        children: [
          btn(
            _SplitterScreenIcon(
              type: _SplitterScreenIconType.horizontal,
              color: iconColor,
            ),
            'Split right',
            onSplitRight,
          ),
          btn(
            _SplitterScreenIcon(
              type: _SplitterScreenIconType.vertical,
              color: iconColor,
            ),
            'Split down',
            onSplitDown,
          ),
          btn(
            _SplitterScreenIcon(
              type: _SplitterScreenIconType.close,
              color: iconColor,
            ),
            'Close pane',
            onClosePane,
          ),
        ],
      ),
    );
  }
}

class _PaneBody extends StatefulWidget {
  const _PaneBody({
    super.key,
    required this.item,
    required this.focused,
    required this.onFillEmpty,
  });
  final PaneItem item;
  final bool focused;

  /// `(terminal)` — qual tipo criar ao preencher a pane vazia.
  final ValueChanged<bool> onFillEmpty;

  @override
  State<_PaneBody> createState() => _PaneBodyState();
}

class _PaneBodyState extends State<_PaneBody> {
  final ScrollController _scroll = ScrollController();
  final FocusNode _terminalFocus = FocusNode();

  static const double _stickThreshold = 80;

  @override
  void initState() {
    super.initState();
    if (widget.item is TerminalSession && widget.focused) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _terminalFocus.requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(_PaneBody old) {
    super.didUpdateWidget(old);
    if (widget.item is! TerminalSession) return;
    if (widget.focused && !old.focused) {
      // Adiar para pós-frame: o requestFocus() síncrono durante onTapDown
      // interfere com o onTapUp da seleção de tab no mesmo ciclo de gestos.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _terminalFocus.requestFocus();
      });
    } else if (!widget.focused && old.focused) {
      _terminalFocus.unfocus();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _terminalFocus.dispose();
    super.dispose();
  }

  void _maybeStickToBottom() {
    final bool stick;
    if (!_scroll.hasClients) {
      stick = true;
    } else {
      final pos = _scroll.position;
      stick = pos.pixels >= pos.maxScrollExtent - _stickThreshold;
    }
    if (!stick) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;

    // Viewer de arquivo (read-only): markdown / texto / imagem.
    if (item is FileViewerSession) {
      return FileViewer(view: item.view);
    }

    // Terminal: só o TerminalView (ele se atualiza sozinho pelo Terminal model).
    if (item is TerminalSession) {
      final settings = context.watch<SettingsController>().settings;
      final termFont = settings.terminalFont;
      // Fonte exclusiva do terminal (vazia = mono padrão do xterm); tamanho =
      // "tamanho do código". O zoom da interface é global (Transform em
      // `_AppZoom`), então não precisa escalar aqui.
      final termStyle = (termFont == null || termFont.isEmpty)
          ? TerminalStyle(fontSize: settings.codeSize)
          : TerminalStyle(fontSize: settings.codeSize, fontFamily: termFont);
      return ColoredBox(
        color: context.colors.panel,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 0, 8),
          child: TerminalView(
            item.terminal,
            focusNode: _terminalFocus,
            // Windows: o caminho de IME/TextInput do xterm quebra no desktop
            // ("Could not set client, view ID is null") e impede digitar. O
            // modo só-hardware ignora o TextInput e lê KeyEvents crus. No
            // macOS mantemos o IME (melhor pra acentos/composição).
            hardwareKeyboardOnly: Platform.isWindows,
            theme: cockpitTerminalThemeFor(Theme.of(context).brightness),
            textStyle: termStyle,
          ),
        ),
      );
    }

    final agent = item as AgentSession;
    return ListenableBuilder(
      listenable: agent,
      builder: (context, _) {
        if (agent.status == AgentStatus.empty) {
          return EmptyPane(
            onNewAgent: () => widget.onFillEmpty(false),
            onNewTerminal: () => widget.onFillEmpty(true),
          );
        }
        _maybeStickToBottom();
        return Stack(
          children: [
            Positioned.fill(
              child: AgentTranscript(
                entries: agent.entries,
                controller: _scroll,
                onUiResponse: agent.respondUi,
                bottomPadding: 150,
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              // Centraliza e limita a largura — em panes largas o input não
              // estica de ponta a ponta; em panes estreitas, preenche.
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: AgentComposer(
                    key: ValueKey('composer-${agent.id}'),
                    session: agent,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ============================================================================
// Drag & drop de abas entre panes
// ============================================================================

/// Carga arrastada quando o usuário pega uma aba: de onde veio e qual aba.
class TabDragData {
  const TabDragData({required this.paneId, required this.tabId});
  final String paneId;
  final String tabId;
}

/// Onde a aba será solta dentro de um pane.
/// [strip]/[center] = acoplar como aba; as bordas = criar um split.
enum _DropZone { strip, center, left, right, top, bottom }

/// Mini-chip que segue o cursor enquanto a aba é arrastada.
class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.icon, required this.title});
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 200),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: colors.panel2,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: colors.accent),
          boxShadow: const [
            BoxShadow(
              color: Color(0x55000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: colors.accentText),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: context.typo.tab.copyWith(color: colors.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Envolve uma [PaneView] como alvo de drop. Mostra as zonas (acoplar / dividir)
/// sob o cursor enquanto uma aba é arrastada, e dispara a operação ao soltar.
class PaneDropZone extends StatefulWidget {
  const PaneDropZone({
    super.key,
    required this.paneId,
    required this.vm,
    required this.child,
  });

  final String paneId;
  final CockpitViewModel vm;
  final Widget child;

  @override
  State<PaneDropZone> createState() => _PaneDropZoneState();
}

class _PaneDropZoneState extends State<PaneDropZone> {
  static const double _stripHeight = 40;
  static const double _edge = 0.25; // fração da borda que vira split

  _DropZone? _zone;
  bool _fileOver = false;

  /// Retorna a sessão ativa na pane, ou `null` se não encontrada.
  PaneItem? _activeSession() {
    final projectId = widget.vm.selectedProjectId;
    if (projectId == null) return null;
    final tree = widget.vm.tree(projectId);
    if (tree == null) return null;
    final leaf = findLeaf(tree, widget.paneId);
    final activeId = leaf?.active;
    if (activeId == null) return null;
    return widget.vm.session(activeId);
  }

  _DropZone _zoneAt(Offset global) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return _DropZone.center;
    final local = box.globalToLocal(global);
    final size = box.size;
    if (local.dy <= _stripHeight) return _DropZone.strip;

    final bw = size.width;
    final bh = size.height - _stripHeight;
    if (bw <= 0 || bh <= 0) return _DropZone.center;
    final fx = (local.dx / bw).clamp(0.0, 1.0);
    final fy = ((local.dy - _stripHeight) / bh).clamp(0.0, 1.0);

    // Profundidade dentro de cada borda; a mais rasa (< _edge) vence.
    var best = _DropZone.center;
    var bestDepth = _edge;
    void consider(_DropZone zone, double depth) {
      if (depth < bestDepth) {
        bestDepth = depth;
        best = zone;
      }
    }

    consider(_DropZone.left, fx);
    consider(_DropZone.right, 1 - fx);
    consider(_DropZone.top, fy);
    consider(_DropZone.bottom, 1 - fy);
    return best;
  }

  void _commit(TabDragData data) {
    final zone = _zone ?? _DropZone.center;
    final vm = widget.vm;
    final target = widget.paneId;
    switch (zone) {
      case _DropZone.strip:
      case _DropZone.center:
        vm.moveTabToPane(data.paneId, data.tabId, target);
      case _DropZone.left:
        vm.moveTabToNewSplit(
          data.paneId,
          data.tabId,
          target,
          SplitDir.vertical,
          before: true,
        );
      case _DropZone.right:
        vm.moveTabToNewSplit(
          data.paneId,
          data.tabId,
          target,
          SplitDir.vertical,
          before: false,
        );
      case _DropZone.top:
        vm.moveTabToNewSplit(
          data.paneId,
          data.tabId,
          target,
          SplitDir.horizontal,
          before: true,
        );
      case _DropZone.bottom:
        vm.moveTabToNewSplit(
          data.paneId,
          data.tabId,
          target,
          SplitDir.horizontal,
          before: false,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Camada externa: arrastar um **arquivo** (da árvore, `Draggable<String>`)
    // sobre a pane abre-o como aba. O input (composer) é um `DragTarget<String>`
    // mais interno → soltar nele vira `@menção`; soltar no resto da pane vira
    // aba. Os dois disputam o mesmo drag; o mais interno (input) ganha.
    return DragTarget<String>(
      hitTestBehavior: HitTestBehavior.opaque,
      onMove: (_) {
        if (!_fileOver) setState(() => _fileOver = true);
      },
      onLeave: (_) {
        if (_fileOver) setState(() => _fileOver = false);
      },
      onAcceptWithDetails: (d) {
        final session = _activeSession();
        if (session is TerminalSession) {
          // Terminal ativo: insere o caminho absoluto no PTY (como se digitado).
          session.insertText(d.data);
        } else {
          widget.vm.openFile(d.data, inPane: widget.paneId);
        }
        setState(() => _fileOver = false);
      },
      builder: (context, fileCandidate, fileRejected) {
        final fileOver = _fileOver && fileCandidate.isNotEmpty;
        // Camada interna: mover **abas** entre panes (`DragTarget<TabDragData>`).
        return DragTarget<TabDragData>(
          hitTestBehavior: HitTestBehavior.opaque,
          onMove: (d) {
            final z = _zoneAt(d.offset);
            if (z != _zone) setState(() => _zone = z);
          },
          onLeave: (_) {
            if (_zone != null) setState(() => _zone = null);
          },
          onAcceptWithDetails: (d) {
            _commit(d.data);
            setState(() => _zone = null);
          },
          builder: (context, candidate, rejected) {
            final dragging = candidate.isNotEmpty && _zone != null;
            return Stack(
              children: [
                widget.child,
                if (dragging)
                  Positioned.fill(
                    child: IgnorePointer(child: _ZonePreview(zone: _zone!)),
                  ),
                // Realce sutil: arquivo sobre a pane → vira aba ao soltar.
                if (fileOver)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: context.colors.accentSoft,
                          border: Border.all(
                            color: context.colors.accent,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Realce da zona de drop sob o cursor (metade pra split, tudo pra acoplar, ou
/// uma faixa na tab strip).
class _ZonePreview extends StatelessWidget {
  const _ZonePreview({required this.zone});
  final _DropZone zone;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    if (zone == _DropZone.strip) {
      return Align(
        alignment: Alignment.topCenter,
        child: Container(
          height: 40,
          width: double.infinity,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.accentSoft,
            border: Border(bottom: BorderSide(color: colors.accent, width: 2)),
          ),
          child: Text(
            'Drop here to move the tab',
            style: context.typo.tab.copyWith(color: colors.accentText),
          ),
        ),
      );
    }

    final (align, wf, hf, label) = switch (zone) {
      _DropZone.center => (Alignment.center, 1.0, 1.0, 'Dock as tab'),
      _DropZone.left => (Alignment.centerLeft, 0.5, 1.0, null),
      _DropZone.right => (Alignment.centerRight, 0.5, 1.0, null),
      _DropZone.top => (Alignment.topCenter, 1.0, 0.5, null),
      _DropZone.bottom => (Alignment.bottomCenter, 1.0, 0.5, null),
      _DropZone.strip => (Alignment.center, 1.0, 1.0, null), // inalcançável
    };

    return Padding(
      // Não cobre a tab strip (o realce de split mora só no corpo).
      padding: const EdgeInsets.only(top: 40),
      child: Align(
        alignment: align,
        child: FractionallySizedBox(
          widthFactor: wf,
          heightFactor: hf,
          child: Container(
            margin: const EdgeInsets.all(8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.accentSoft,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.accent, width: 2),
            ),
            child: label == null
                ? null
                : Text(
                    label,
                    style: context.typo.tab.copyWith(color: colors.accentText),
                  ),
          ),
        ),
      ),
    );
  }
}

enum _SplitterScreenIconType { horizontal, vertical, close }

class _SplitterScreenIcon extends StatelessWidget {
  final _SplitterScreenIconType type;
  final Color color;
  const _SplitterScreenIcon({required this.type, required this.color});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final size = min(width, height);
        final borderLine = size * 0.10;
        final borderRadius = size * 0.10;
        final gap = size * 0.1;

        if (_SplitterScreenIconType.close == type) {
          return SizedBox(
            width: size,
            height: size,
            child: Transform.rotate(
              angle: 45 * pi / 180,
              child: Stack(
                children: [
                  Center(
                    child: Container(
                      width: borderRadius,
                      height: height,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(borderRadius),
                        color: color,
                      ),
                    ),
                  ),
                  Center(
                    child: Container(
                      width: width,
                      height: borderRadius,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(borderRadius),
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final children = [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: color, width: borderLine),
                borderRadius: BorderRadius.circular(borderRadius),
              ),
            ),
          ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: color, width: borderLine),
                borderRadius: BorderRadius.circular(borderRadius),
              ),
            ),
          ),
        ];

        return Center(
          child: SizedBox(
            width: height,
            height: height,
            child: type == _SplitterScreenIconType.vertical
                ? Column(spacing: gap, children: children)
                : Row(spacing: gap, children: children),
          ),
        );
      },
    );
  }
}
