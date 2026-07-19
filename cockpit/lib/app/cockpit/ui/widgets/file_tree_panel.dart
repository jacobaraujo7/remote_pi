import 'dart:io' show Platform;

import 'package:cockpit/app/cockpit/domain/entities/file_node.dart';
import 'package:cockpit/app/cockpit/domain/entities/git_file_status.dart';
import 'package:cockpit/app/cockpit/domain/entities/git_info.dart';
import 'package:cockpit/app/cockpit/ui/widgets/commit_message_dialog.dart';
import 'package:cockpit/app/cockpit/ui/widgets/confirm_dialog.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:cockpit/app/core/ui/widgets/app_menu.dart';
import 'package:cockpit/app/core/ui/widgets/app_tooltip.dart';
import 'package:cockpit/app/core/ui/file_icons/file_icons.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:cockpit/app/core/ui/settings_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Root git de um workspace **multi-root** (multirepo) — alimenta o cabeçalho
/// de seção na aba Files e no Source Control. Derivada em runtime pela VM
/// (nunca persistida). Single-root chega como lista de 1 item e nenhum
/// cabeçalho é desenhado (comportamento histórico, N=1).
class WorkspaceRoot {
  const WorkspaceRoot({required this.path, required this.name, this.git});

  /// Caminho absoluto da root (o repo filho).
  final String path;

  /// Basename da root — o nome exibido no cabeçalho da seção.
  final String name;

  /// Estado git da root (`null` = não é repo / git indisponível).
  final GitInfo? git;
}

/// Painel direito (~300px): árvore da pasta do **workspace**. Pastas começam
/// colapsadas e expandem ao clicar (lazy-load). O header tem **+arquivo**,
/// **+pasta** e **Refresh**; criar/renomear é **inline** (linha-input na árvore),
/// deletar manda pra lixeira (macOS) ou pede confirmação (demais).
///
/// Workspace **multi-root** ([roots] com 2+ itens): cada root vira uma seção
/// colapsável com cabeçalho próprio (nome + branch + sujeira); o Source
/// Control agrega as mudanças de todas, seccionadas por root.
class FileTreePanel extends StatefulWidget {
  const FileTreePanel({
    super.key,
    required this.rootPath,
    required this.revision,
    this.selectedPath,
    required this.listChildren,
    required this.gitStatusOf,
    required this.onOpenFile,
    this.onTapFile,
    this.onSelectFile,
    this.onClearSelection,
    required this.onOpenDiff,
    this.onTapDiff,
    required this.isGitRepo,
    required this.changedPaths,
    required this.onOpenWith,
    required this.onCreateInFolder,
    required this.onCreate,
    required this.onRename,
    required this.onDelete,
    required this.onMove,
    this.width = 300,
    this.footer,
    this.searchPanel,
    this.databasePanel,
    this.searchFocusSignal,
    this.tasksPanel,
    this.roots = const <WorkspaceRoot>[],
    this.onRootContextMenu,
    this.onUnstageFile,
    this.onDiscardFile,
    this.onCommitFile,
    this.revealPath,
    this.revealGen = 0,
  });

  /// "Revelar na árvore": arquivo-alvo + geração. Quando [revealGen] muda, a
  /// árvore expande a root e os folders ancestrais de [revealPath] (uma vez) e
  /// destaca o arquivo. Disparado ao selecionar uma tab de FileView.
  final String? revealPath;
  final int revealGen;

  /// Source Control: comita só o arquivo, com a mensagem do dialog.
  /// `null` = sucesso; senão a mensagem de erro do git.
  final Future<String?> Function(String absPath, String message)? onCommitFile;

  /// Source Control: tira o arquivo do index (`git restore --staged`).
  /// `null` no retorno = sucesso; senão a mensagem de erro do git.
  final Future<String?> Function(String absPath)? onUnstageFile;

  /// Source Control: descarta a mudança do working tree (destrutivo — o
  /// painel confirma antes). `null` = sucesso.
  final Future<String?> Function(String absPath)? onDiscardFile;

  /// Roots git do workspace (derivadas). 0–1 itens = single-root, layout de
  /// hoje; 2+ = multi-root com seções por root.
  final List<WorkspaceRoot> roots;

  /// Botão-direito no cabeçalho de uma root (multi-root): a page abre o menu
  /// de contexto (Sync/Pull/Push/worktree/terminal). `null` = sem menu.
  final void Function(WorkspaceRoot root, Offset globalPosition)?
  onRootContextMenu;

  /// Notificado a cada Cmd+Shift+F → ativa a aba de busca (além de focar o
  /// campo, que o próprio [searchPanel] faz). `null` = sem projeto.
  final Listenable? searchFocusSignal;

  /// Rodapé opcional, fixado abaixo da árvore (ex.: barra de status do LSP).
  final Widget? footer;

  /// Subpane de Tasks (executor de build/dev), fixado entre o [searchPanel] e
  /// o [footer]. Null = sem projeto selecionado.
  final Widget? tasksPanel;

  /// Painel de conexões de banco (aba Database, plano 51). Null = sem projeto
  /// (a aba nem aparece no header).
  final Widget? databasePanel;

  /// Painel de busca por conteúdo, fixado entre a árvore e o [footer]
  /// (Cmd+Shift+F). `null` quando não há projeto.
  final Widget? searchPanel;

  final String rootPath;

  /// Token externo (VM) que sobe a cada mutação — força reler as pastas abertas.
  final int revision;

  /// Caminho atualmente selecionado no tree (para highlight). Vindo da VM.
  final String? selectedPath;

  final Future<List<FileNode>> Function(String path) listChildren;

  /// Status git (cor) de um caminho absoluto. `null` = limpo / fora de repo.
  final GitFileStatus? Function(String absolutePath) gitStatusOf;

  /// Duplo-clique num arquivo → abre no pane.
  final ValueChanged<String> onOpenFile;

  /// Clique único → abre preview (VSCode-style).
  final ValueChanged<String>? onTapFile;

  /// Clique único → seleciona o arquivo no tree (highlight).
  final ValueChanged<String>? onSelectFile;

  /// Clique numa área vazia da árvore → limpa a seleção/highlight.
  final VoidCallback? onClearSelection;

  /// Duplo-clique (modo source control) / "Show git diff" → abre o diff no pane.
  final ValueChanged<String> onOpenDiff;

  /// Clique único no modo source control → abre o diff em preview.
  final ValueChanged<String>? onTapDiff;

  /// `true` se o workspace é um repo git — habilita o toggle "Source Control".
  final bool isGitRepo;

  /// Caminhos **absolutos** com mudança git (modo source control, árvore podada).
  final List<String> changedPaths;

  /// "Open with" → abre o arquivo/pasta no app/explorador padrão do SO.
  final ValueChanged<String> onOpenWith;

  /// Menu de contexto de uma **pasta**: cria uma aba (agente/terminal) nela.
  final void Function(String relativeSub, bool terminal) onCreateInFolder;

  /// Cria arquivo (ou pasta) chamado [name] dentro de [parentDir]. Falha → msg.
  final Future<Result<void, String>> Function(
    String parentDir,
    String name,
    bool isFolder,
  )
  onCreate;

  /// Renomeia [path] para [newName] (mesma pasta).
  final Future<Result<void, String>> Function(String path, String newName)
  onRename;

  /// Manda [path] pra lixeira (a confirmação/condições ficam no painel).
  final Future<Result<void, String>> Function(String path) onDelete;

  /// Move [path] pra dentro de [targetDir] (drag-and-drop na árvore).
  final Future<Result<void, String>> Function(String path, String targetDir)
  onMove;

  /// Largura do painel (arrastável pela página — não persistido).
  final double width;

  @override
  State<FileTreePanel> createState() => _FileTreePanelState();
}

/// Aba ativa do painel direito: árvore de arquivos, busca por conteúdo,
/// source control ou conexões de banco (plano 51). Ordem visual no header:
/// Files · Search · Source Control · Database.
enum _RightPaneTab { files, search, sourceControl, database }

/// Intenção de criação inline pendente: dentro de [parentPath], arquivo ou pasta.
class _PendingCreate {
  const _PendingCreate(this.parentPath, this.isFolder);
  final String parentPath;
  final bool isFolder;
}

class _FileTreePanelState extends State<FileTreePanel> {
  int _localRefresh = 0;
  String? _selectedPath;

  /// `true` quando o item selecionado é uma **pasta** (senão é arquivo). Guia o
  /// alvo do New file/New folder do header: pasta selecionada → cria dentro dela;
  /// arquivo → cria na pasta-mãe; nada selecionado → cria na raiz.
  bool _selectedIsFolder = false;

  /// Geração de reveal já processada + o conjunto de paths de folders ancestrais
  /// do alvo a expandir (`_Folder` consome uma vez, via a geração).
  int _revealGen = 0;
  Set<String> _revealExpand = const <String>{};

  /// Paths dos diretórios ancestrais de [filePath] (sem o próprio arquivo),
  /// preservando o prefixo absoluto. Ex.: `/a/b/c.txt` → `{/a, /a/b}`. Cada
  /// prefixo que termina num `/` é um ancestral. Usado pra saber quais folders
  /// expandir no reveal.
  Set<String> _ancestorDirs(String? filePath) {
    if (filePath == null || filePath.isEmpty) return const <String>{};
    final lastSlash = filePath.lastIndexOf('/');
    if (lastSlash <= 0) return const <String>{}; // arquivo direto na raiz
    final out = <String>{};
    for (var i = 1; i < lastSlash; i++) {
      if (filePath[i] == '/') out.add(filePath.substring(0, i));
    }
    out.add(filePath.substring(0, lastSlash)); // a pasta-mãe imediata
    return out;
  }

  /// Aba ativa do painel: árvore de arquivos, busca ou source control.
  _RightPaneTab _tab = _RightPaneTab.files;

  /// Source Control começa na lista compacta e pode alternar para a hierarquia
  /// de pastas sem afetar a árvore principal de arquivos.
  bool _sourceControlTree = false;

  /// Criação inline em andamento (uma de cada vez).
  _PendingCreate? _pending;

  /// Caminho sendo renomeado inline (`null` = nenhum).
  String? _renaming;

  /// Roots colapsadas na aba Files (multi-root). Chave = path da root.
  final Set<String> _collapsedRoots = <String>{};

  final FocusNode _treeFocus = FocusNode(debugLabel: 'fileTree');

  @override
  void initState() {
    super.initState();
    widget.searchFocusSignal?.addListener(_onSearchFocusRequested);
  }

  @override
  void didUpdateWidget(FileTreePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchFocusSignal != widget.searchFocusSignal) {
      oldWidget.searchFocusSignal?.removeListener(_onSearchFocusRequested);
      widget.searchFocusSignal?.addListener(_onSearchFocusRequested);
    }
    // Novo pedido de reveal (seleção de tab FileView): calcula os ancestrais do
    // alvo, expande a root que o contém (multi-root) e publica o set pros folders.
    if (widget.revealGen != oldWidget.revealGen &&
        widget.revealGen != _revealGen) {
      final path = widget.revealPath;
      _revealGen = widget.revealGen;
      _revealExpand = _ancestorDirs(path);
      if (path != null) {
        for (final r in widget.roots) {
          if (path == r.path || path.startsWith('${r.path}/')) {
            _collapsedRoots.remove(r.path);
            break;
          }
        }
      }
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.searchFocusSignal?.removeListener(_onSearchFocusRequested);
    _treeFocus.dispose();
    super.dispose();
  }

  /// Botão-direito num arquivo do Source Control: View Diff + Unstage OU
  /// Discard (um ou outro, pelo estado do arquivo). Discard confirma antes
  /// (destrutivo) e mostra o erro do git, se houver.
  Future<void> _showChangedFileMenu(String absPath, Offset pos) async {
    final status = widget.gitStatusOf(absPath);
    final staged = status == GitFileStatus.staged;
    final name = absPath.split('/').last;
    final pick = await showAppMenu<String>(
      context,
      globalPosition: pos,
      items: [
        const AppMenuItem(
          value: 'diff',
          label: 'View Diff',
          icon: Icons.difference_outlined,
        ),
        if (widget.onCommitFile != null)
          AppMenuItem(
            value: 'commit',
            label: staged ? 'Commit' : 'Stage and Commit',
            icon: Icons.check_circle_outline,
          ),
        if (staged && widget.onUnstageFile != null)
          const AppMenuItem(
            value: 'unstage',
            label: 'Unstage',
            icon: Icons.remove_circle_outline,
          )
        else if (!staged && widget.onDiscardFile != null)
          const AppMenuItem(
            value: 'discard',
            label: 'Discard Changes',
            icon: Icons.undo,
            danger: true,
          ),
      ],
    );
    if (pick == null || !mounted) return;
    switch (pick) {
      case 'diff':
        widget.onOpenDiff(absPath);
      case 'commit':
        await showCommitMessageDialog(
          context,
          fileName: name,
          staged: staged,
          onCommit: (message) => widget.onCommitFile!(absPath, message),
        );
      case 'unstage':
        final err = await widget.onUnstageFile!(absPath);
        if (err != null && mounted) await _showGitError(err);
      case 'discard':
        final untracked = status == GitFileStatus.untracked;
        final ok = await showConfirmDialog(
          context,
          title: 'Discard changes?',
          message: untracked
              ? '"$name" is untracked — discarding moves the file to the '
                    'trash.'
              : 'Discard the changes in "$name"? This cannot be undone.',
          confirmLabel: 'Discard',
          danger: true,
        );
        if (!ok || !mounted) return;
        final err = await widget.onDiscardFile!(absPath);
        if (err != null && mounted) await _showGitError(err);
    }
  }

  Future<void> _showGitError(String message) => showConfirmDialog(
    context,
    title: 'Git error',
    message: message,
    confirmLabel: 'OK',
  );

  /// Cmd+Shift+F: revela a aba de busca (o campo é focado pelo próprio painel).
  void _onSearchFocusRequested() {
    if (widget.searchPanel != null && _tab != _RightPaneTab.search) {
      setState(() => _tab = _RightPaneTab.search);
    }
  }

  /// Token efetivo: refresh manual (botão) + revisão externa (VM). Ambos
  /// monotônicos → a soma muda sempre que qualquer um muda.
  int get _refreshToken => _localRefresh + widget.revision;

  bool _isUnder(String path, String root) =>
      path == root || path.startsWith('$root/');

  void _select(String path, [bool isFolder = false]) {
    setState(() {
      _selectedPath = path;
      _selectedIsFolder = isFolder;
    });
    // Pasta não passa pelo `onSelectFile` (que seta o highlight da VM); sem
    // limpar, o `effectiveSelected` ficaria preso no último arquivo aberto e a
    // pasta não acenderia. Limpar deixa o `_selectedPath` (a pasta) virar o
    // highlight efetivo.
    if (isFolder) widget.onClearSelection?.call();
    _treeFocus.requestFocus();
  }

  /// Limpa a seleção — chamado ao clicar numa área vazia da árvore. Zera o alvo
  /// local (→ New file/folder volta a mirar a raiz) e o highlight da VM.
  void _deselect() {
    if (_selectedPath == null && widget.selectedPath == null) return;
    setState(() {
      _selectedPath = null;
      _selectedIsFolder = false;
    });
    widget.onClearSelection?.call();
  }

  /// Pasta-alvo dos botões New file/New folder do **header**: a pasta
  /// selecionada, a pasta-mãe do arquivo selecionado, ou a raiz quando nada está
  /// selecionado. `null` = sem alvo válido (multi-root sem seleção → ambíguo, o
  /// botão nem aparece; a criação por-root vive no [_RootHeader]).
  String? _headerCreateTarget() {
    final sel = _selectedPath;
    final rootFallback = widget.roots.length <= 1 ? widget.rootPath : null;
    if (sel == null || sel.isEmpty) return rootFallback;
    if (_selectedIsFolder) return sel;
    final i = sel.lastIndexOf('/');
    return i > 0 ? sel.substring(0, i) : rootFallback;
  }

  /// Dispara o New file/folder do header no alvo resolvido, expandindo a root
  /// que o contém (multi-root) pra o `_DirView`-raiz montar e revelar o input.
  void _headerCreate(bool isFolder) {
    final target = _headerCreateTarget();
    if (target == null || target.isEmpty) return;
    for (final r in widget.roots) {
      if (target == r.path || target.startsWith('${r.path}/')) {
        _expandRoot(r.path);
        break;
      }
    }
    _startCreate(target, isFolder);
  }

  // ---- criação inline -------------------------------------------------------

  void _startCreate(String parentPath, bool isFolder) {
    setState(() {
      _pending = _PendingCreate(parentPath, isFolder);
      _renaming = null;
    });
  }

  void _cancelCreate() {
    if (_pending != null) setState(() => _pending = null);
  }

  /// Expande a seção de uma root (multi-root) se estiver colapsada — necessário
  /// antes de criar nela, pra o `_DirView`-alvo montar e o input inline aparecer.
  void _expandRoot(String rootPath) {
    if (_collapsedRoots.contains(rootPath)) {
      setState(() => _collapsedRoots.remove(rootPath));
    }
  }

  /// Commit do input de criação. Devolve a mensagem de erro (mantém o input) ou
  /// `null` no sucesso (limpa — a árvore recarrega pela revisão da VM).
  Future<String?> _commitCreate(
    String parentPath,
    bool isFolder,
    String name,
  ) async {
    final r = await widget.onCreate(parentPath, name, isFolder);
    return r.fold((_) {
      if (mounted) setState(() => _pending = null);
      return null;
    }, (e) => e);
  }

  // ---- rename inline --------------------------------------------------------

  void _startRename(String path) {
    setState(() {
      _renaming = path;
      _pending = null;
    });
  }

  void _cancelRename() {
    if (_renaming != null) setState(() => _renaming = null);
  }

  Future<String?> _commitRename(String path, String newName) async {
    final r = await widget.onRename(path, newName);
    return r.fold((_) {
      if (mounted) {
        // A seleção segue o novo caminho.
        final parent = path.substring(0, path.lastIndexOf('/'));
        final newPath = '$parent/${newName.trim()}';
        setState(() {
          _renaming = null;
          if (_selectedPath != null && _isUnder(_selectedPath!, path)) {
            _selectedPath = newPath;
          }
        });
      }
      return null;
    }, (e) => e);
  }

  // ---- deleção --------------------------------------------------------------

  Future<void> _requestDelete(String path) async {
    final name = path.split('/').where((p) => p.isNotEmpty).last;
    // Confirma sempre. No macOS o destino é a Lixeira (reversível); nas demais
    // plataformas a deleção é permanente — a mensagem reflete a diferença.
    final ok = await showConfirmDialog(
      context,
      title: 'Delete?',
      message: Platform.isMacOS
          ? 'Move “$name” to the Trash?'
          : 'Permanently delete “$name”? This can’t be undone.',
      confirmLabel: 'Delete',
      danger: true,
    );
    if (!ok || !mounted) return;
    final r = await widget.onDelete(path);
    if (!mounted) return;
    r.fold((_) {
      if (_selectedPath != null && _isUnder(_selectedPath!, path)) {
        setState(() => _selectedPath = null);
      }
    }, (e) => showInfoDialog(context, title: 'Could not delete', message: e));
  }

  // ---- mover (drag-and-drop) ------------------------------------------------

  /// Drop de [path] numa pasta [targetDir]: move mantendo o nome. A validação
  /// (mesma pasta = no-op, pasta dentro de si mesma) fica na VM; falha vira
  /// dialog. A seleção segue o novo caminho.
  Future<void> _requestMove(String path, String targetDir) async {
    final r = await widget.onMove(path, targetDir);
    if (!mounted) return;
    r.fold((_) {
      if (_selectedPath != null && _isUnder(_selectedPath!, path)) {
        final name = path.split('/').where((p) => p.isNotEmpty).last;
        setState(() => _selectedPath = '$targetDir/$name');
      }
    }, (e) => showInfoDialog(context, title: 'Could not move', message: e));
  }

  // ---- atalhos de teclado ---------------------------------------------------

  bool get _editing => _pending != null || _renaming != null;

  void _renameSelected() {
    final p = _selectedPath;
    if (p != null && !_editing) _startRename(p);
  }

  void _deleteSelected() {
    final p = _selectedPath;
    if (p != null && !_editing) _requestDelete(p);
  }

  /// Handler de teclado **no próprio nó focado** (mais confiável que depender do
  /// bubbling até um `CallbackShortcuts` ancestral). Delete/Backspace apagam;
  /// Enter (macOS) / F2 (Win/Linux) renomeiam o selecionado.
  KeyEventResult _onTreeKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _editing || _selectedPath == null) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final isDelete =
        key == LogicalKeyboardKey.delete ||
        (Platform.isMacOS && key == LogicalKeyboardKey.backspace);
    final isRename = Platform.isMacOS
        ? key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.numpadEnter
        : key == LogicalKeyboardKey.f2;
    if (isDelete) {
      _deleteSelected();
      return KeyEventResult.handled;
    }
    if (isRename) {
      _renameSelected();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // Usa o selectedPath da VM se disponível, senão o local.
    final effectiveSelected = widget.selectedPath ?? _selectedPath;

    final edit = _TreeEdit(
      pending: _pending,
      renaming: _renaming,
      selectedPath: effectiveSelected,
      revealExpand: _revealExpand,
      revealGen: _revealGen,
      onSelect: _select,
      onOpenFile: widget.onOpenFile,
      onTapFile: widget.onTapFile,
      onSelectFile: widget.onSelectFile,
      onOpenWith: widget.onOpenWith,
      onCreateInFolder: widget.onCreateInFolder,
      onStartCreate: _startCreate,
      onCancelCreate: _cancelCreate,
      onCommitCreate: _commitCreate,
      onStartRename: _startRename,
      onCancelRename: _cancelRename,
      onCommitRename: _commitRename,
      onRequestDelete: _requestDelete,
      onRequestMove: _requestMove,
      onShowDiff: widget.onOpenDiff,
      gitStatusOf: widget.gitStatusOf,
      listChildren: widget.listChildren,
    );

    // Aba efetiva: source-control só existe em repo git; busca só com projeto.
    // Se a condição da aba ativa sumiu, cai de volta pra Files.
    final hasSearch = widget.searchPanel != null;
    var tab = _tab;
    if (tab == _RightPaneTab.sourceControl && !widget.isGitRepo) {
      tab = _RightPaneTab.files;
    }
    if (tab == _RightPaneTab.search && !hasSearch) {
      tab = _RightPaneTab.files;
    }
    final hasDatabase = widget.databasePanel != null;
    if (tab == _RightPaneTab.database && !hasDatabase) {
      tab = _RightPaneTab.files;
    }
    final scMode = tab == _RightPaneTab.sourceControl;
    final searchMode = tab == _RightPaneTab.search;
    final dbMode = tab == _RightPaneTab.database;

    return Container(
      width: widget.width,
      decoration: BoxDecoration(
        color: colors.bg,
        border: Border(left: BorderSide(color: colors.border)),
      ),
      child: Column(
        children: [
          Container(
            height: 40,
            padding: const EdgeInsets.only(left: 14, right: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
            child: Row(
              children: [
                _HeaderIcon(
                  icon: Icons.folder_outlined,
                  tooltip: 'Files',
                  selected: tab == _RightPaneTab.files,
                  onTap: () => setState(() => _tab = _RightPaneTab.files),
                ),
                if (hasSearch)
                  _HeaderIcon(
                    icon: Icons.search,
                    tooltip: 'Search',
                    selected: searchMode,
                    onTap: () => setState(() => _tab = _RightPaneTab.search),
                  ),
                if (widget.isGitRepo)
                  _HeaderIcon(
                    key: const ValueKey('source-control-tab'),
                    icon: Icons.account_tree_outlined,
                    tooltip: 'Source Control',
                    selected: scMode,
                    onTap: () =>
                        setState(() => _tab = _RightPaneTab.sourceControl),
                  ),
                if (hasDatabase)
                  _HeaderIcon(
                    key: const ValueKey('database-tab'),
                    icon: Icons.storage,
                    tooltip: 'Database',
                    selected: dbMode,
                    onTap: () => setState(() => _tab = _RightPaneTab.database),
                  ),
              ],
            ),
          ),
          // Título da aba ativa + ações contextuais ao lado, no padrão do
          // painel Database (a barra de tabs acima fica só com as tabs).
          if (widget.rootPath.isNotEmpty && tab == _RightPaneTab.files)
            _PanelHeader(
              title: 'FILES',
              actions: [
                // "New file/folder" só quando há alvo: pasta/arquivo
                // selecionado, senão a raiz (single-root). Em **multi-root**
                // sem seleção o alvo é ambíguo ("em qual repo?") → `null` e o
                // botão some (a criação por-root vive em cada `_RootHeader`).
                if (_headerCreateTarget()?.isNotEmpty ?? false) ...[
                  _PanelHeaderAction(
                    icon: Icons.note_add_outlined,
                    tooltip: 'New file',
                    onTap: () => _headerCreate(false),
                  ),
                  _PanelHeaderAction(
                    icon: Icons.create_new_folder_outlined,
                    tooltip: 'New folder',
                    onTap: () => _headerCreate(true),
                  ),
                ],
                _PanelHeaderAction(
                  icon: Icons.refresh,
                  tooltip: 'Refresh',
                  onTap: () => setState(() => _localRefresh++),
                ),
              ],
            ),
          if (widget.rootPath.isNotEmpty && scMode)
            _PanelHeader(
              title: 'SOURCE CONTROL',
              actions: [
                _PanelHeaderAction(
                  key: const ValueKey('source-control-view-toggle'),
                  icon: _sourceControlTree
                      ? Icons.view_list_outlined
                      : Icons.account_tree_outlined,
                  tooltip: _sourceControlTree ? 'View as List' : 'View as Tree',
                  onTap: () => setState(
                    () => _sourceControlTree = !_sourceControlTree,
                  ),
                ),
              ],
            ),
          Expanded(
            child: widget.rootPath.isEmpty
                ? Center(
                    child: Text(
                      'No folder — open a workspace.',
                      textAlign: TextAlign.center,
                      style: context.typo.label.copyWith(color: colors.text3),
                    ),
                  )
                : searchMode
                ? (widget.searchPanel ?? const SizedBox.shrink())
                : dbMode
                ? (widget.databasePanel ?? const SizedBox.shrink())
                : scMode
                ? _ChangedTree(
                    rootPath: widget.rootPath,
                    roots: widget.roots,
                    onFileContextMenu: _showChangedFileMenu,
                    changedPaths: widget.changedPaths,
                    gitStatusOf: widget.gitStatusOf,
                    selectedPath: effectiveSelected,
                    onOpenDiff: widget.onOpenDiff,
                    viewAsTree: _sourceControlTree,
                    onTapDiff: (path) {
                      _select(path);
                      (widget.onTapDiff ?? widget.onOpenDiff)(path);
                    },
                  )
                : Focus(
                    focusNode: _treeFocus,
                    onKeyEvent: _onTreeKey,
                    // Soltar no espaço vazio da árvore move pra RAIZ do
                    // workspace (as pastas, mais internas, capturam antes).
                    child: DragTarget<String>(
                      onWillAcceptWithDetails: (d) => d.data != widget.rootPath,
                      onAcceptWithDetails: (d) =>
                          _requestMove(d.data, widget.rootPath),
                      // Tap na área vazia da árvore → deseleciona (o New file/
                      // folder volta a mirar a raiz). As linhas têm onTap próprio
                      // (descendentes), então o tap nelas não chega aqui.
                      builder: (context, candidates, _) => GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: _deselect,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 6,
                          ),
                            child: widget.roots.length > 1
                                // Multi-root: uma seção colapsável por root,
                                // cada uma com sua própria _DirView (paths
                                // git relativos à root, não à pasta-mãe).
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      for (final root in widget.roots) ...[
                                        _RootHeader(
                                          root: root,
                                          collapsed: _collapsedRoots.contains(
                                            root.path,
                                          ),
                                          onToggle: () => setState(() {
                                            if (!_collapsedRoots.remove(
                                              root.path,
                                            )) {
                                              _collapsedRoots.add(root.path);
                                            }
                                          }),
                                          onContextMenu:
                                              widget.onRootContextMenu,
                                          // New file/folder DESTA root: garante a
                                          // seção expandida (senão o _DirView-alvo
                                          // não monta e o input não aparece) e
                                          // dispara o create mirando root.path.
                                          showCreate: tab == _RightPaneTab.files,
                                          onNewFile: () {
                                            _expandRoot(root.path);
                                            _startCreate(root.path, false);
                                          },
                                          onNewFolder: () {
                                            _expandRoot(root.path);
                                            _startCreate(root.path, true);
                                          },
                                        ),
                                        if (!_collapsedRoots.contains(
                                          root.path,
                                        ))
                                          _DirView(
                                            path: root.path,
                                            rootPath: root.path,
                                            depth: 1,
                                            refreshToken: _refreshToken,
                                            edit: edit,
                                          ),
                                      ],
                                    ],
                                  )
                                : _DirView(
                                    path: widget.rootPath,
                                    rootPath: widget.rootPath,
                                    depth: 0,
                                    refreshToken: _refreshToken,
                                    edit: edit,
                                  ),
                          ),
                        ),
                    ),
                  ),
          ),
          ?widget.tasksPanel,
          ?widget.footer,
        ],
      ),
    );
  }
}

/// Cabeçalho de seção de uma **root** (multi-root): seta de colapso + nome +
/// branch + contagem de sujos. Botão-direito abre o menu de contexto da root
/// (git ops direcionadas — o alvo é o próprio cabeçalho, sem perguntar).
class _RootHeader extends StatefulWidget {
  const _RootHeader({
    required this.root,
    required this.collapsed,
    required this.onToggle,
    this.onContextMenu,
    this.showCreate = false,
    this.onNewFile,
    this.onNewFolder,
  });

  final WorkspaceRoot root;
  final bool collapsed;
  final VoidCallback onToggle;
  final void Function(WorkspaceRoot root, Offset globalPosition)? onContextMenu;

  /// Mostra os ícones New file/New folder (revelados no hover) — só no modo
  /// Files. Cada um cria DENTRO desta root.
  final bool showCreate;
  final VoidCallback? onNewFile;
  final VoidCallback? onNewFolder;

  @override
  State<_RootHeader> createState() => _RootHeaderState();
}

class _RootHeaderState extends State<_RootHeader> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    final root = widget.root;
    final git = root.git;
    final dirty = git?.dirtyCount ?? 0;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onSecondaryTapDown: widget.onContextMenu == null
            ? null
            : (d) => widget.onContextMenu!(root, d.globalPosition),
        child: HoverTap(
          hoverColor: colors.panel,
          borderRadius: BorderRadius.circular(5),
          onTap: widget.onToggle,
          padding: const EdgeInsets.only(left: 4, right: 6),
          child: SizedBox(
            height: 28,
            child: Row(
              children: [
                Icon(
                  widget.collapsed
                      ? Icons.keyboard_arrow_right
                      : Icons.keyboard_arrow_down,
                  size: 15,
                  color: colors.text3,
                ),
                const SizedBox(width: 2),
                // Nome da root inteiro, sempre — quem trunca é a branch.
                Text(
                  root.name,
                  style: typo.body.copyWith(
                    fontSize: 12.5,
                    color: colors.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (git != null) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.call_split, size: 10, color: colors.warn),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      git.branch,
                      overflow: TextOverflow.ellipsis,
                      style: typo.mono.copyWith(
                        fontSize: 10,
                        color: colors.warn,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                // Ícones de criação (hover) — descendentes com onTap próprio, então
                // o tap vai neles, não no toggle do header.
                if (widget.showCreate && _hovered) ...[
                  _HeaderIcon(
                    icon: Icons.note_add_outlined,
                    tooltip: 'New file',
                    onTap: () => widget.onNewFile?.call(),
                  ),
                  _HeaderIcon(
                    icon: Icons.create_new_folder_outlined,
                    tooltip: 'New folder',
                    onTap: () => widget.onNewFolder?.call(),
                  ),
                ] else if (dirty > 0)
                  Text(
                    '$dirty',
                    style: typo.mono.copyWith(
                      fontSize: 10,
                      color: colors.edited,
                      fontWeight: FontWeight.w700,
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

/// Bundle das interações de edição da árvore — passado de cima a baixo pra evitar
/// explosão de props. Imutável: recriado a cada build do painel.
class _TreeEdit {
  const _TreeEdit({
    required this.pending,
    required this.renaming,
    required this.selectedPath,
    required this.revealExpand,
    required this.revealGen,
    required this.onSelect,
    required this.onOpenFile,
    required this.onTapFile,
    required this.onSelectFile,
    required this.onOpenWith,
    required this.onCreateInFolder,
    required this.onStartCreate,
    required this.onCancelCreate,
    required this.onCommitCreate,
    required this.onStartRename,
    required this.onCancelRename,
    required this.onCommitRename,
    required this.onRequestDelete,
    required this.onRequestMove,
    required this.onShowDiff,
    required this.gitStatusOf,
    required this.listChildren,
  });

  final _PendingCreate? pending;
  final String? renaming;
  final String? selectedPath;

  /// Folders (paths) a expandir no reveal atual + a geração (consumida 1× por
  /// [_Folder]). Ver [FileTreePanel.revealPath].
  final Set<String> revealExpand;
  final int revealGen;

  final void Function(String path, bool isFolder) onSelect;
  final ValueChanged<String> onOpenFile;
  final ValueChanged<String>? onTapFile;
  final ValueChanged<String>? onSelectFile;

  /// "Show git diff" (menu de contexto) → abre o diff do arquivo.
  final ValueChanged<String> onShowDiff;
  final ValueChanged<String> onOpenWith;
  final void Function(String relativeSub, bool terminal) onCreateInFolder;

  final void Function(String parentPath, bool isFolder) onStartCreate;
  final VoidCallback onCancelCreate;
  final Future<String?> Function(String parentPath, bool isFolder, String name)
  onCommitCreate;

  final ValueChanged<String> onStartRename;
  final VoidCallback onCancelRename;
  final Future<String?> Function(String path, String newName) onCommitRename;

  final ValueChanged<String> onRequestDelete;

  /// Drop de um caminho arrastado numa pasta-alvo → move pra dentro dela.
  final void Function(String path, String targetDir) onRequestMove;

  final GitFileStatus? Function(String absolutePath) gitStatusOf;
  final Future<List<FileNode>> Function(String path) listChildren;
}

/// Carrega os filhos de uma pasta e os renderiza. Re-lê quando [refreshToken]
/// muda (Refresh manual ou mutação na VM).
class _DirView extends StatefulWidget {
  const _DirView({
    required this.path,
    required this.rootPath,
    required this.depth,
    required this.refreshToken,
    required this.edit,
  });

  final String path;
  final String rootPath;
  final int depth;
  final int refreshToken;
  final _TreeEdit edit;

  @override
  State<_DirView> createState() => _DirViewState();
}

class _DirViewState extends State<_DirView> {
  List<FileNode>? _children;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_DirView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _load();
  }

  Future<void> _load() async {
    final children = await widget.edit.listChildren(widget.path);
    if (mounted) setState(() => _children = children);
  }

  @override
  Widget build(BuildContext context) {
    final children = _children;
    if (children == null) return const SizedBox.shrink();
    final edit = widget.edit;
    final pending = edit.pending;
    final showCreate = pending != null && pending.parentPath == widget.path;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Input de criação inline (no topo da pasta-alvo).
        if (showCreate)
          _InlineEntry(
            key: ValueKey('create:${widget.path}:${pending.isFolder}'),
            depth: widget.depth,
            isFolder: pending.isFolder,
            onSubmit: (name) =>
                edit.onCommitCreate(widget.path, pending.isFolder, name),
            onCancel: edit.onCancelCreate,
          ),
        for (final node in children)
          if (node.isDirectory)
            // Arrastável (mover pra outra pasta / citar no composer) e também
            // alvo de drop (o DragTarget fica dentro do _Folder, na linha).
            Draggable<String>(
              data: node.path,
              dragAnchorStrategy: pointerDragAnchorStrategy,
              feedback: _FileChip(name: node.name),
              child: _Folder(
                node: node,
                depth: widget.depth,
                refreshToken: widget.refreshToken,
                edit: edit,
              ),
            )
          else
            // Arrasta o arquivo até o input (vira `@<rel>`).
            Draggable<String>(
              data: node.path,
              dragAnchorStrategy: pointerDragAnchorStrategy,
              feedback: _FileChip(name: node.name),
              child: _Row(
                depth: widget.depth,
                isFolder: false,
                name: node.name,
                path: node.path,
                rootPath: widget.rootPath,
                selected: node.path == edit.selectedPath,
                renaming: edit.renaming == node.path,
                gitStatus: edit.gitStatusOf(node.path),
                onTap: () {
                  edit.onSelect(node.path, false);
                  edit.onSelectFile?.call(node.path);
                  edit.onTapFile?.call(node.path);
                },
                onDoubleTap: () => edit.onOpenFile(node.path),
                onOpenWith: () => edit.onOpenWith(node.path),
                onStartRename: () => edit.onStartRename(node.path),
                onCommitRename: (name) => edit.onCommitRename(node.path, name),
                onCancelRename: edit.onCancelRename,
                onDelete: () => edit.onRequestDelete(node.path),
                onShowDiff: () => edit.onShowDiff(node.path),
              ),
            ),
      ],
    );
  }
}

class _Folder extends StatefulWidget {
  const _Folder({
    required this.node,
    required this.depth,
    required this.refreshToken,
    required this.edit,
  });

  final FileNode node;
  final int depth;
  final int refreshToken;
  final _TreeEdit edit;

  @override
  State<_Folder> createState() => _FolderState();
}

class _FolderState extends State<_Folder> {
  bool _expanded = false;

  /// Última geração de reveal já processada por esta pasta (one-shot: expande no
  /// tick novo se for ancestral do alvo, depois deixa o usuário colapsar).
  int _revealGen = -1;

  /// Força abrir quando há criação pendente nesta pasta ou em algo abaixo dela
  /// (pra revelar o input inline alvo).
  bool get _forceExpand {
    final p = widget.edit.pending;
    if (p == null) return false;
    final path = widget.node.path;
    return p.parentPath == path || p.parentPath.startsWith('$path/');
  }

  @override
  Widget build(BuildContext context) {
    final edit = widget.edit;
    // Reveal one-shot: numa geração nova, se esta pasta é ancestral do arquivo
    // revelado, expande (pós-frame — não dá pra setState no build). Cascateia:
    // ao expandir, o _DirView filho monta, seus _Folder buildam com gen novo e
    // seguem a cadeia até o alvo. Consumido 1× por gen → colapsar depois vale.
    if (edit.revealGen != _revealGen) {
      _revealGen = edit.revealGen;
      if (!_expanded && edit.revealExpand.contains(widget.node.path)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_expanded) setState(() => _expanded = true);
        });
      }
    }
    final expanded = _expanded || _forceExpand;
    // Alvo de drop: soltar um caminho arrastado aqui move-o pra DENTRO da
    // pasta. Recusa a si mesma e descendentes (não dá pra mover pra dentro
    // de si); o highlight de hover indica o alvo válido.
    final row = DragTarget<String>(
      onWillAcceptWithDetails: (d) =>
          d.data != widget.node.path &&
          !widget.node.path.startsWith('${d.data}/'),
      onAcceptWithDetails: (d) => edit.onRequestMove(d.data, widget.node.path),
      builder: (context, candidates, _) => Container(
        decoration: candidates.isNotEmpty
            ? BoxDecoration(
                color: context.colors.panel2,
                borderRadius: BorderRadius.circular(5),
              )
            : null,
        child: _Row(
          depth: widget.depth,
          isFolder: true,
          expanded: expanded,
          name: widget.node.name,
          path: widget.node.path,
          rootPath: widget.node.path, // (não usado em pasta)
          selected: widget.node.path == edit.selectedPath,
          renaming: edit.renaming == widget.node.path,
          gitStatus: edit.gitStatusOf(widget.node.path),
          onCreateInFolder: edit.onCreateInFolder,
          onNewFile: () => edit.onStartCreate(widget.node.path, false),
          onNewFolder: () => edit.onStartCreate(widget.node.path, true),
          onOpenWith: () => edit.onOpenWith(widget.node.path),
          onStartRename: () => edit.onStartRename(widget.node.path),
          onCommitRename: (name) => edit.onCommitRename(widget.node.path, name),
          onCancelRename: edit.onCancelRename,
          onDelete: () => edit.onRequestDelete(widget.node.path),
          onTap: () {
            edit.onSelect(widget.node.path, true);
            setState(() => _expanded = !_expanded);
          },
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row,
        if (expanded)
          _DirView(
            path: widget.node.path,
            rootPath: widget.node.path,
            depth: widget.depth + 1,
            refreshToken: widget.refreshToken,
            edit: edit,
          ),
      ],
    );
  }
}

class _Row extends StatefulWidget {
  const _Row({
    required this.depth,
    required this.isFolder,
    required this.name,
    required this.path,
    required this.rootPath,
    this.gitStatus,
    this.expanded = false,
    this.selected = false,
    this.renaming = false,
    this.onTap,
    this.onDoubleTap,
    this.onOpenWith,
    this.onCreateInFolder,
    this.onNewFile,
    this.onNewFolder,
    this.onStartRename,
    this.onCommitRename,
    this.onCancelRename,
    this.onDelete,
    this.onShowDiff,
  });

  final int depth;
  final bool isFolder;
  final String name;
  final String path;
  final String rootPath;

  final GitFileStatus? gitStatus;
  final bool expanded;
  final bool selected;
  final bool renaming;

  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;

  /// "Open with" (arquivo) / "Open in Finder" (pasta).
  final VoidCallback? onOpenWith;

  /// Só pastas: criar agente/terminal nela (relativo, terminal?).
  final void Function(String relativeSub, bool terminal)? onCreateInFolder;

  /// Só pastas: iniciar criação inline de arquivo/pasta dentro dela.
  final VoidCallback? onNewFile;
  final VoidCallback? onNewFolder;

  final VoidCallback? onStartRename;
  final Future<String?> Function(String name)? onCommitRename;
  final VoidCallback? onCancelRename;
  final VoidCallback? onDelete;

  /// "Show git diff" (só arquivos). `null` em pastas.
  final VoidCallback? onShowDiff;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  DateTime? _lastTap;

  String get _relative {
    final root = widget.rootPath.endsWith('/')
        ? widget.rootPath
        : '${widget.rootPath}/';
    return widget.path.startsWith(root)
        ? widget.path.substring(root.length)
        : widget.path;
  }

  void _handleTap() {
    if (widget.onDoubleTap == null) {
      widget.onTap?.call();
      return;
    }
    final now = DateTime.now();
    if (_lastTap != null && now.difference(_lastTap!).inMilliseconds < 350) {
      _lastTap = null;
      widget.onDoubleTap!();
    } else {
      _lastTap = now;
      widget.onTap?.call();
    }
  }

  String get _fileExplorerLabel {
    if (Platform.isMacOS) return 'Open in Finder';
    if (Platform.isWindows) return 'Open in Explorer';
    return 'Open in file manager';
  }

  void _showMenu(BuildContext context, Offset globalPosition) {
    final isFolder = widget.isFolder;
    final isFile = !isFolder;
    // "Create agent" só quando agentes estão ligados (Settings → General →
    // "Enable agents"). "Create terminal" segue sempre. Lido na hora do menu
    // pra refletir o toggle atual.
    final agentsEnabled = context.read<SettingsController>().settings.enableAgent;
    showAppMenu<String>(
      context,
      minWidth: 220,
      globalPosition: globalPosition,
      items: [
        if (isFile) ...[
          const AppMenuItem(
            value: 'open',
            label: 'Open',
            icon: Icons.open_in_new,
          ),
          const AppMenuItem(
            value: 'openwith',
            label: 'Open with',
            icon: Icons.launch_outlined,
          ),
          // Sempre visível; desabilitado quando o arquivo não tem mudança git.
          AppMenuItem(
            value: 'diff',
            label: 'Show git diff',
            icon: Icons.difference_outlined,
            enabled: widget.gitStatus != null,
          ),
        ],
        if (isFolder) ...[
          const AppMenuItem(
            value: 'newfile',
            label: 'New file',
            icon: Icons.note_add_outlined,
          ),
          const AppMenuItem(
            value: 'newfolder',
            label: 'New folder',
            icon: Icons.create_new_folder_outlined,
          ),
          if (agentsEnabled)
            const AppMenuItem(
              value: 'agent',
              label: 'Create agent',
              icon: Icons.auto_awesome,
            ),
          const AppMenuItem(
            value: 'terminal',
            label: 'Create terminal',
            icon: Icons.terminal_outlined,
          ),
        ],
        if (isFolder)
          AppMenuItem(
            value: 'reveal',
            label: _fileExplorerLabel,
            icon: Icons.folder_open_outlined,
          ),
        const AppMenuItem(
          value: 'rename',
          label: 'Rename',
          icon: Icons.drive_file_rename_outline,
        ),
        const AppMenuItem(
          value: 'delete',
          label: 'Delete',
          icon: Icons.delete_outline,
        ),
        const AppMenuItem(
          value: 'rel',
          label: 'Copy relative path',
          icon: Icons.content_copy_outlined,
        ),
        const AppMenuItem(
          value: 'abs',
          label: 'Copy absolute path',
          icon: Icons.content_copy,
        ),
      ],
    ).then((value) {
      switch (value) {
        case 'open':
          widget.onDoubleTap?.call();
        case 'diff':
          widget.onShowDiff?.call();
        case 'openwith':
        case 'reveal':
          widget.onOpenWith?.call();
        case 'newfile':
          widget.onNewFile?.call();
        case 'newfolder':
          widget.onNewFolder?.call();
        case 'agent':
          widget.onCreateInFolder?.call(_relative, false);
        case 'terminal':
          widget.onCreateInFolder?.call(_relative, true);
        case 'rename':
          widget.onStartRename?.call();
        case 'delete':
          widget.onDelete?.call();
        case 'rel':
          Clipboard.setData(ClipboardData(text: _relative));
        case 'abs':
          Clipboard.setData(ClipboardData(text: widget.path));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final Widget label = widget.renaming
        ? _NameField(
            initial: widget.name,
            // Arquivos: pré-seleciona o nome sem extensão (estilo VSCode).
            selectBasename: !widget.isFolder,
            onSubmit: (name) async =>
                await widget.onCommitRename?.call(name) ?? 'Rename failed.',
            onCancel: () => widget.onCancelRename?.call(),
          )
        : Text(
            widget.name,
            overflow: TextOverflow.ellipsis,
            style: context.typo.body.copyWith(
              fontSize: 13,
              color:
                  _gitColor(colors, widget.gitStatus) ??
                  (widget.selected ? colors.text : colors.text2),
            ),
          );

    final row = HoverTap(
      color: widget.selected ? colors.panel2 : Colors.transparent,
      hoverColor: colors.panel,
      borderRadius: BorderRadius.circular(5),
      onTap: widget.renaming ? null : _handleTap,
      padding: EdgeInsets.only(left: 6 + widget.depth * 14.0, right: 6),
      child: SizedBox(
        // Em rename a linha cresce (campo + erro); fora dela, altura fixa.
        height: widget.renaming ? null : 26,
        child: Row(
          children: [
            SizedBox(
              width: 14,
              child: widget.isFolder
                  ? Icon(
                      widget.expanded
                          ? Icons.keyboard_arrow_down
                          : Icons.chevron_right,
                      size: 15,
                      color: colors.text4,
                    )
                  : null,
            ),
            const SizedBox(width: 2),
            widget.isFolder
                ? FileTypeIcon.folder(
                    widget.name,
                    open: widget.expanded,
                    size: 16,
                  )
                : FileTypeIcon.file(widget.name, size: 16),
            const SizedBox(width: 7),
            Expanded(child: label),
          ],
        ),
      ),
    );

    // Em rename o gesto secundário/seleção fica desligado (o campo manda).
    if (widget.renaming) return row;
    return GestureDetector(
      onSecondaryTapUp: (d) => _showMenu(context, d.globalPosition),
      child: row,
    );
  }
}

/// Linha-input de **criação** inline: ícone (arquivo/pasta) + campo de nome,
/// indentado como uma linha normal naquela profundidade.
class _InlineEntry extends StatelessWidget {
  const _InlineEntry({
    super.key,
    required this.depth,
    required this.isFolder,
    required this.onSubmit,
    required this.onCancel,
  });

  final int depth;
  final bool isFolder;
  final Future<String?> Function(String name) onSubmit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 6 + depth * 14.0, right: 6),
      child: Row(
        children: [
          const SizedBox(width: 14), // alinha com o chevron das pastas
          const SizedBox(width: 2),
          isFolder
              ? FileTypeIcon.folder('new', open: false, size: 16)
              : FileTypeIcon.file('new file', size: 16),
          const SizedBox(width: 7),
          Expanded(
            child: _NameField(
              initial: '',
              selectBasename: false,
              onSubmit: onSubmit,
              onCancel: onCancel,
            ),
          ),
        ],
      ),
    );
  }
}

/// Campo de nome compartilhado por criar/renomear: autofoco, Enter confirma,
/// Esc/clique-fora cancela. Erro de validação aparece como linha vermelha abaixo
/// (mantendo o foco pra correção).
class _NameField extends StatefulWidget {
  const _NameField({
    required this.initial,
    required this.selectBasename,
    required this.onSubmit,
    required this.onCancel,
  });

  final String initial;

  /// Pré-seleciona só o nome sem extensão (útil em rename de arquivo).
  final bool selectBasename;

  /// Devolve mensagem de erro (mantém editando) ou `null` no sucesso.
  final Future<String?> Function(String name) onSubmit;
  final VoidCallback onCancel;

  @override
  State<_NameField> createState() => _NameFieldState();
}

class _NameFieldState extends State<_NameField> {
  late final TextEditingController _ctrl;
  final FocusNode _focus = FocusNode();
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial);
    final dot = widget.initial.lastIndexOf('.');
    final end = (widget.selectBasename && dot > 0)
        ? dot
        : widget.initial.length;
    _ctrl.selection = TextSelection(baseOffset: 0, extentOffset: end);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final name = _ctrl.text.trim();
    if (name.isEmpty) {
      widget.onCancel();
      return;
    }
    setState(() => _busy = true);
    final err = await widget.onSubmit(name);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): widget.onCancel,
          },
          child: SizedBox(
            height: 22,
            child: TextField(
              controller: _ctrl,
              focusNode: _focus,
              style: typo.body.copyWith(fontSize: 13, color: colors.text),
              border: Border.all(color: colors.accent),
              borderRadius: BorderRadius.circular(4),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              onSubmitted: (_) => _submit(),
              onTapOutside: (_) => widget.onCancel(),
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 2, left: 2),
            child: Text(
              _error!,
              style: typo.label.copyWith(fontSize: 11, color: colors.error),
            ),
          ),
      ],
    );
  }
}

/// Um arquivo modificado, já quebrado em nome + diretório relativo (pra lista
/// plana do modo Source Control).
class _ChangedFile {
  const _ChangedFile({
    required this.absPath,
    required this.name,
    required this.dir,
  });
  final String absPath;
  final String name;

  /// Diretório relativo à raiz (sem barra final), vazio quando na raiz.
  final String dir;
}

/// Lista **plana** do modo Source Control (estilo VSCode): cada arquivo
/// modificado numa linha, com o nome + o diretório relativo esmaecido ao lado
/// (ex.: `main.dart  lib/app`). Clique abre o diff — só leitura.
class _ChangedTree extends StatelessWidget {
  const _ChangedTree({
    required this.rootPath,
    required this.roots,
    required this.onFileContextMenu,
    required this.changedPaths,
    required this.gitStatusOf,
    required this.selectedPath,
    required this.onOpenDiff,
    required this.onTapDiff,
    required this.viewAsTree,
  });

  final String rootPath;

  /// Roots do workspace (2+ = seções por root; senão fluxo plano).
  final List<WorkspaceRoot> roots;

  /// Botão-direito num arquivo → menu (View Diff / Unstage / Discard).
  final void Function(String absPath, Offset pos) onFileContextMenu;
  final List<String> changedPaths;
  final GitFileStatus? Function(String absolutePath) gitStatusOf;
  final String? selectedPath;
  final ValueChanged<String> onOpenDiff;
  final ValueChanged<String> onTapDiff;
  final bool viewAsTree;

  @override
  Widget build(BuildContext context) {
    if (changedPaths.isEmpty) {
      return Center(
        child: Text(
          'No changes.',
          style: context.typo.label.copyWith(color: context.colors.text3),
        ),
      );
    }

    // Multi-root: agrega as mudanças de todas as roots, **seccionadas por
    // root** — cabeçalho (nome + branch + contagem) e, dentro, a mesma
    // visualização (lista/hierarquia) com paths relativos à root. Roots
    // limpas não têm seção. Single-root cai no fluxo plano (sem cabeçalho).
    if (roots.length > 1) {
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final root in roots)
              ..._rootSection(context, root, _filesUnder(root.path)),
          ],
        ),
      );
    }

    final files = _filesUnder(rootPath);
    if (viewAsTree) {
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        child: _buildTree(files),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _buildRows(files),
      ),
    );
  }

  /// Mudanças sob [base], com paths relativos a ela, ordenadas por pasta.
  List<_ChangedFile> _filesUnder(String base) {
    final normalized = base.endsWith('/') ? base : '$base/';
    final files = <_ChangedFile>[];
    for (final abs in changedPaths) {
      if (!abs.startsWith(normalized)) continue;
      final rel = abs.substring(normalized.length);
      final slash = rel.lastIndexOf('/');
      files.add(
        _ChangedFile(
          absPath: abs,
          name: slash >= 0 ? rel.substring(slash + 1) : rel,
          dir: slash >= 0 ? rel.substring(0, slash) : '',
        ),
      );
    }
    // Ordena pelo caminho relativo completo (agrupa por pasta, estável).
    files.sort((a, b) {
      final ap = a.dir.isEmpty ? a.name : '${a.dir}/${a.name}';
      final bp = b.dir.isEmpty ? b.name : '${b.dir}/${b.name}';
      return ap.toLowerCase().compareTo(bp.toLowerCase());
    });
    return files;
  }

  Widget _buildTree(List<_ChangedFile> files) {
    final root = _ChangedDirectory('');
    for (final file in files) {
      root.add(file);
    }
    return _ChangedDirectoryView(
      directory: root,
      gitStatusOf: gitStatusOf,
      selectedPath: selectedPath,
      onOpenDiff: onOpenDiff,
      onTapDiff: onTapDiff,
      onFileContextMenu: onFileContextMenu,
    );
  }

  List<Widget> _buildRows(List<_ChangedFile> files) => [
    for (final f in files)
      _ChangedRow(
        file: f,
        gitStatus: gitStatusOf(f.absPath),
        selected: f.absPath == selectedPath,
        onTap: () => onTapDiff(f.absPath),
        onDoubleTap: () => onOpenDiff(f.absPath),
        onSecondaryTap: (pos) => onFileContextMenu(f.absPath, pos),
      ),
  ];

  /// Seção de uma root no modo multi-root. Root limpa = sem seção.
  List<Widget> _rootSection(
    BuildContext context,
    WorkspaceRoot root,
    List<_ChangedFile> files,
  ) {
    if (files.isEmpty) return const [];
    return [
      _ScRootSection(
        root: root,
        // O corpo respeita o toggle lista/hierarquia vigente.
        body: viewAsTree
            ? _buildTree(files)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _buildRows(files),
              ),
      ),
    ];
  }
}

/// Seção **colapsável** de uma root no Source Control multi-root: cabeçalho
/// (seta + nome inteiro + branch truncável) e o corpo (lista/hierarquia).
/// O nome da root nunca trunca — quem cede espaço é a branch.
class _ScRootSection extends StatefulWidget {
  const _ScRootSection({required this.root, required this.body});

  final WorkspaceRoot root;
  final Widget body;

  @override
  State<_ScRootSection> createState() => _ScRootSectionState();
}

class _ScRootSectionState extends State<_ScRootSection> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    final root = widget.root;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HoverTap(
          hoverColor: colors.panel,
          borderRadius: BorderRadius.circular(5),
          onTap: () => setState(() => _expanded = !_expanded),
          padding: const EdgeInsets.only(left: 2, right: 6),
          child: SizedBox(
            height: 26,
            child: Row(
              children: [
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                  size: 15,
                  color: colors.text3,
                ),
                const SizedBox(width: 2),
                Text(
                  root.name,
                  style: typo.body.copyWith(
                    fontSize: 12.5,
                    color: colors.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (root.git != null) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.call_split, size: 10, color: colors.warn),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      root.git!.branch,
                      overflow: TextOverflow.ellipsis,
                      style: typo.mono.copyWith(
                        fontSize: 10,
                        color: colors.warn,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (_expanded) widget.body,
        const SizedBox(height: 6),
      ],
    );
  }
}

/// Nó em memória da visualização hierárquica de mudanças.
class _ChangedDirectory {
  _ChangedDirectory(this.name);

  final String name;
  final Map<String, _ChangedDirectory> directories =
      <String, _ChangedDirectory>{};
  final List<_ChangedFile> files = <_ChangedFile>[];

  void add(_ChangedFile file) {
    var current = this;
    for (final part in file.dir.split('/').where((part) => part.isNotEmpty)) {
      current = current.directories.putIfAbsent(
        part,
        () => _ChangedDirectory(part),
      );
    }
    current.files.add(file);
  }
}

/// Conteúdo de uma pasta da árvore de Source Control. A raiz não desenha linha;
/// subpastas começam expandidas para a troca de visualização revelar os arquivos.
class _ChangedDirectoryView extends StatefulWidget {
  const _ChangedDirectoryView({
    required this.directory,
    required this.gitStatusOf,
    required this.selectedPath,
    required this.onOpenDiff,
    required this.onTapDiff,
    required this.onFileContextMenu,
    this.depth = 0,
    this.isRoot = true,
  });

  final _ChangedDirectory directory;
  final GitFileStatus? Function(String absolutePath) gitStatusOf;
  final String? selectedPath;
  final ValueChanged<String> onOpenDiff;
  final ValueChanged<String> onTapDiff;
  final void Function(String absPath, Offset pos) onFileContextMenu;
  final int depth;
  final bool isRoot;

  @override
  State<_ChangedDirectoryView> createState() => _ChangedDirectoryViewState();
}

class _ChangedDirectoryViewState extends State<_ChangedDirectoryView> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final directories = widget.directory.directories.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final files = widget.directory.files.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.isRoot)
          HoverTap(
            key: ValueKey(
              'source-control-folder:${widget.depth}:${widget.directory.name}',
            ),
            hoverColor: context.colors.panel,
            borderRadius: BorderRadius.circular(5),
            onTap: () => setState(() => _expanded = !_expanded),
            padding: EdgeInsets.only(left: 6 + widget.depth * 14, right: 6),
            child: SizedBox(
              height: 26,
              child: Row(
                children: [
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_right,
                    size: 15,
                    color: context.colors.text3,
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    _expanded
                        ? Icons.folder_open_outlined
                        : Icons.folder_outlined,
                    size: 16,
                    color: context.colors.text3,
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      widget.directory.name,
                      overflow: TextOverflow.ellipsis,
                      style: context.typo.body.copyWith(
                        fontSize: 13,
                        color: context.colors.text2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (widget.isRoot || _expanded) ...[
          for (final directory in directories)
            _ChangedDirectoryView(
              directory: directory,
              gitStatusOf: widget.gitStatusOf,
              selectedPath: widget.selectedPath,
              onOpenDiff: widget.onOpenDiff,
              onTapDiff: widget.onTapDiff,
              onFileContextMenu: widget.onFileContextMenu,
              depth: widget.isRoot ? 0 : widget.depth + 1,
              isRoot: false,
            ),
          for (final file in files)
            _ChangedRow(
              key: ValueKey('source-control-file:${file.absPath}'),
              file: file,
              gitStatus: widget.gitStatusOf(file.absPath),
              selected: file.absPath == widget.selectedPath,
              depth: widget.isRoot ? 0 : widget.depth + 1,
              showDirectory: false,
              onTap: () => widget.onTapDiff(file.absPath),
              onDoubleTap: () => widget.onOpenDiff(file.absPath),
              onSecondaryTap: (pos) =>
                  widget.onFileContextMenu(file.absPath, pos),
            ),
        ],
      ],
    );
  }
}

/// Uma linha da lista de source control. Clique = diff; botão-direito =
/// menu de contexto (View Diff / Unstage / Discard).
class _ChangedRow extends StatefulWidget {
  const _ChangedRow({
    super.key,
    required this.file,
    required this.gitStatus,
    required this.selected,
    required this.onTap,
    required this.onDoubleTap,
    this.onSecondaryTap,
    this.depth = 0,
    this.showDirectory = true,
  });

  final _ChangedFile file;
  final GitFileStatus? gitStatus;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;

  /// Botão-direito (posição global do clique) → menu de contexto.
  final void Function(Offset globalPos)? onSecondaryTap;
  final int depth;
  final bool showDirectory;

  @override
  State<_ChangedRow> createState() => _ChangedRowState();
}

class _ChangedRowState extends State<_ChangedRow> {
  DateTime? _lastTap;

  void _handleTap() {
    if (widget.onDoubleTap == null) {
      widget.onTap?.call();
      return;
    }
    final now = DateTime.now();
    if (_lastTap != null && now.difference(_lastTap!).inMilliseconds < 350) {
      _lastTap = null;
      widget.onDoubleTap!();
    } else {
      _lastTap = now;
      widget.onTap?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    final file = widget.file;
    final nameColor =
        _gitColor(colors, widget.gitStatus) ??
        (widget.selected ? colors.text : colors.text2);
    return GestureDetector(
      onSecondaryTapDown: widget.onSecondaryTap == null
          ? null
          : (d) => widget.onSecondaryTap!(d.globalPosition),
      child: HoverTap(
        color: widget.selected ? colors.panel2 : Colors.transparent,
        hoverColor: colors.panel,
        borderRadius: BorderRadius.circular(5),
        onTap: _handleTap,
        padding: EdgeInsets.only(left: 6 + widget.depth * 14, right: 6),
        child: SizedBox(
          height: 26,
          child: Row(
            children: [
              FileTypeIcon.file(file.name, size: 16),
              const SizedBox(width: 7),
              // Nome do arquivo (não encolhe) + diretório esmaecido (trunca).
              Flexible(
                child: Text(
                  file.name,
                  overflow: TextOverflow.ellipsis,
                  style: typo.body.copyWith(
                    fontSize: 13,
                    color: nameColor,
                    // Deletado = riscado (strikethrough), além da cor.
                    decoration: widget.gitStatus == GitFileStatus.deleted
                        ? TextDecoration.lineThrough
                        : null,
                    decorationColor: nameColor,
                  ),
                ),
              ),
              if (widget.showDirectory && file.dir.isNotEmpty) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    file.dir,
                    overflow: TextOverflow.ellipsis,
                    style: typo.label.copyWith(
                      fontSize: 11,
                      color: colors.text4,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Cor do nome conforme o status git da linha.
Color? _gitColor(AppColors colors, GitFileStatus? status) {
  switch (status) {
    case null:
      return null;
    case GitFileStatus.ignored:
      return colors.text4;
    case GitFileStatus.modified:
      return colors.warn;
    case GitFileStatus.staged:
      return colors.gitStaged;
    case GitFileStatus.untracked:
      return colors.gitUntracked;
    case GitFileStatus.deleted:
      return colors.gitDeleted;
    case GitFileStatus.conflict:
      return colors.gitConflict;
  }
}

/// Cabeçalho de painel no padrão da aba Database: título em caps à esquerda e
/// ações contextuais à direita (Files e Source Control usam este).
class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.title, this.actions = const []});
  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 4),
      child: Row(
        children: [
          Text(
            title,
            style: context.typo.label.copyWith(
              fontSize: 10,
              letterSpacing: 1.1,
              color: colors.text3,
            ),
          ),
          const Spacer(),
          ...actions,
        ],
      ),
    );
  }
}

/// Ação de [_PanelHeader]: ícone 14px com hover, no padrão do header Database.
class _PanelHeaderAction extends StatelessWidget {
  const _PanelHeaderAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppTooltip(
      message: tooltip,
      child: HoverTap(
        onTap: onTap,
        padding: const EdgeInsets.all(3),
        child: Icon(icon, size: 14, color: colors.text3),
      ),
    );
  }
}

class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.selected = false,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  /// Toggle ativo → fundo realçado + ícone em cor primária.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // AppTooltip (não o Tooltip do shadcn): posiciona certo sob o zoom do app.
    return AppTooltip(
      message: tooltip,
      child: HoverTap(
        color: selected ? colors.panel2 : Colors.transparent,
        borderRadius: BorderRadius.circular(5),
        onTap: onTap,
        child: SizedBox(
          width: 28,
          height: 28,
          child: Icon(
            icon,
            size: 16,
            color: selected ? colors.text : colors.text3,
          ),
        ),
      ),
    );
  }
}

/// Chip que segue o cursor ao arrastar um arquivo do painel pro input.
class _FileChip extends StatelessWidget {
  const _FileChip({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
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
          Icon(Icons.alternate_email, size: 13, color: colors.accentText),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: context.typo.body.copyWith(
                fontSize: 12.5,
                color: colors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
