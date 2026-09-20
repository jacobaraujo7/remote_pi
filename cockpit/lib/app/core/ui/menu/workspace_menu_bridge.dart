import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Ponte **reativa** entre o shell e o menu **File** (New Agent / New Terminal).
/// O `CockpitPage` publica se há um workspace ativo + os callbacks que abrem uma
/// aba nova nele; o menu habilita os itens só quando [hasWorkspace] e dispara a
/// ação. `ChangeNotifier` app-scoped (provido no `ModularApp.provide`): o
/// `AppRoot`/topbar dão `context.watch` pra reconstruir os menus quando um
/// workspace é selecionado/limpo. Espelha o [EditorMenuBridge], mas para o
/// estado de shell (não de editor).
class WorkspaceMenuBridge extends ChangeNotifier {
  bool _hasWorkspace = false;
  VoidCallback? _onNewTerminal;
  VoidCallback? _onSplitRight;
  VoidCallback? _onSplitDown;
  VoidCallback? _onToggleRail;
  VoidCallback? _onToggleFiles;
  void Function(int index)? _onSelectTab;
  VoidCallback? _onSelectLastTab;
  VoidCallback? _onNextWorkspace;
  VoidCallback? _onPreviousWorkspace;
  VoidCallback? _onFocusPaneLeft;
  VoidCallback? _onFocusPaneRight;
  VoidCallback? _onFocusPaneUp;
  VoidCallback? _onFocusPaneDown;

  bool get hasWorkspace => _hasWorkspace;

  void newTerminal() => _onNewTerminal?.call();
  void splitRight() => _onSplitRight?.call();
  void splitDown() => _onSplitDown?.call();
  void toggleRail() => _onToggleRail?.call();
  void toggleFiles() => _onToggleFiles?.call();
  void selectTab(int index) => _onSelectTab?.call(index);
  void selectLastTab() => _onSelectLastTab?.call();
  void nextWorkspace() => _onNextWorkspace?.call();
  void previousWorkspace() => _onPreviousWorkspace?.call();
  void focusPaneLeft() => _onFocusPaneLeft?.call();
  void focusPaneRight() => _onFocusPaneRight?.call();
  void focusPaneUp() => _onFocusPaneUp?.call();
  void focusPaneDown() => _onFocusPaneDown?.call();

  /// O `CockpitPage` publica o estado atual. Callbacks são sempre atualizados;
  /// só notifica (→ menu/settings reconstroem) quando [hasWorkspace] muda.
  void setWorkspace({
    required bool hasWorkspace,
    VoidCallback? onNewTerminal,
    VoidCallback? onSplitRight,
    VoidCallback? onSplitDown,
    VoidCallback? onToggleRail,
    VoidCallback? onToggleFiles,
    void Function(int index)? onSelectTab,
    VoidCallback? onSelectLastTab,
    VoidCallback? onNextWorkspace,
    VoidCallback? onPreviousWorkspace,
    VoidCallback? onFocusPaneLeft,
    VoidCallback? onFocusPaneRight,
    VoidCallback? onFocusPaneUp,
    VoidCallback? onFocusPaneDown,
  }) {
    _onNewTerminal = onNewTerminal;
    _onSplitRight = onSplitRight;
    _onSplitDown = onSplitDown;
    _onToggleRail = onToggleRail;
    _onToggleFiles = onToggleFiles;
    _onSelectTab = onSelectTab;
    _onSelectLastTab = onSelectLastTab;
    _onNextWorkspace = onNextWorkspace;
    _onPreviousWorkspace = onPreviousWorkspace;
    _onFocusPaneLeft = onFocusPaneLeft;
    _onFocusPaneRight = onFocusPaneRight;
    _onFocusPaneUp = onFocusPaneUp;
    _onFocusPaneDown = onFocusPaneDown;
    if (hasWorkspace == _hasWorkspace) return;
    _hasWorkspace = hasWorkspace;
    // CockpitPage clears this bridge from dispose(), which runs while Flutter
    // finalizes the route subtree. Notifying synchronously there asks AppRoot
    // (an ancestor) to rebuild while the element tree is locked and produces
    // the misleading _InactiveElements._unmount cascade. Match the editor
    // bridge: publish state immediately, but defer the rebuild notification
    // whenever Flutter is not idle.
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.idle) {
      notifyListeners();
    } else {
      SchedulerBinding.instance.addPostFrameCallback((_) => notifyListeners());
    }
  }
}
