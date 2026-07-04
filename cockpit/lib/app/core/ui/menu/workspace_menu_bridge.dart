import 'package:flutter/foundation.dart';

/// Ponte **reativa** entre o shell e o menu **File** (New Agent / New Terminal).
/// O `CockpitPage` publica se há um workspace ativo + os callbacks que abrem uma
/// aba nova nele; o menu habilita os itens só quando [hasWorkspace] e dispara a
/// ação. `ChangeNotifier` app-scoped (provido no `ModularApp.provide`): o
/// `AppRoot`/topbar dão `context.watch` pra reconstruir os menus quando um
/// workspace é selecionado/limpo. Espelha o [EditorMenuBridge], mas para o
/// estado de shell (não de editor).
class WorkspaceMenuBridge extends ChangeNotifier {
  bool _hasWorkspace = false;
  bool _agentTabsInUse = false;
  bool _agentsAllowed = true;
  VoidCallback? _onNewAgent;
  VoidCallback? _onNewTerminal;
  VoidCallback? _onSplitRight;
  VoidCallback? _onSplitDown;
  VoidCallback? _onToggleRail;
  VoidCallback? _onToggleFiles;

  bool get hasWorkspace => _hasWorkspace;

  /// `true` se há ao menos uma aba de agente **em uso** (não placeholder vazio).
  /// A tela de Configurações usa isso pra impedir desligar `enableAgent` sem
  /// antes fechar as abas de agente (cross-route: a VM do shell é page-scoped).
  bool get agentTabsInUse => _agentTabsInUse;

  /// `false` no workspace de sistema "Cockpit" (terminal-only): o item
  /// "New Agent" fica indisponível mesmo com `enableAgent` ligado.
  bool get agentsAllowed => _agentsAllowed;

  void newAgent() => _onNewAgent?.call();
  void newTerminal() => _onNewTerminal?.call();
  void splitRight() => _onSplitRight?.call();
  void splitDown() => _onSplitDown?.call();
  void toggleRail() => _onToggleRail?.call();
  void toggleFiles() => _onToggleFiles?.call();

  /// O `CockpitPage` publica o estado atual. Callbacks são sempre atualizados;
  /// só notifica (→ menu/settings reconstroem) quando [hasWorkspace] ou
  /// [agentTabsInUse] mudam.
  void setWorkspace({
    required bool hasWorkspace,
    bool agentTabsInUse = false,
    bool agentsAllowed = true,
    VoidCallback? onNewAgent,
    VoidCallback? onNewTerminal,
    VoidCallback? onSplitRight,
    VoidCallback? onSplitDown,
    VoidCallback? onToggleRail,
    VoidCallback? onToggleFiles,
  }) {
    _onNewAgent = onNewAgent;
    _onNewTerminal = onNewTerminal;
    _onSplitRight = onSplitRight;
    _onSplitDown = onSplitDown;
    _onToggleRail = onToggleRail;
    _onToggleFiles = onToggleFiles;
    if (hasWorkspace == _hasWorkspace &&
        agentTabsInUse == _agentTabsInUse &&
        agentsAllowed == _agentsAllowed) {
      return;
    }
    _hasWorkspace = hasWorkspace;
    _agentTabsInUse = agentTabsInUse;
    _agentsAllowed = agentsAllowed;
    notifyListeners();
  }
}
