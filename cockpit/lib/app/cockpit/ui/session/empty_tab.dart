import 'package:cockpit/app/cockpit/ui/session/pane_item.dart';

/// Aba **vazia**: o placeholder que ocupa uma pane sem nada aberto e mostra o
/// seletor do "+" (terminal, arquivo, etc.). Nunca tem processo nem estado;
/// abrir qualquer coisa na pane a substitui.
///
/// Existia como `AgentSession` com `AgentStatus.empty` enquanto o agente nativo
/// (`pi --mode rpc`) morava no binário. Removido o agente (k16 do roadmap 2.0),
/// o papel de placeholder virou este tipo próprio.
class EmptyTab extends PaneItem {
  EmptyTab({
    required this.id,
    required this.projectId,
    required this.workingDirectory,
  });

  @override
  final String id;
  @override
  final String projectId;
  @override
  final String workingDirectory;

  @override
  String get title => 'New tab';
}
