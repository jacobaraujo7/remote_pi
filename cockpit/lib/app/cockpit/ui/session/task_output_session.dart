import 'package:cockpit/app/cockpit/ui/session/pane_item.dart';
import 'package:cockpit/app/core/terminal/terminal_controller.dart';

/// Aba **read-only** que visualiza o output de uma task. É leve e descartável:
/// o [terminal] não é dela — vive no `TaskTerminalStore` —, então abrir/fechar
/// a aba não perde o buffer nem mexe na task. A task em si não sobrevive ao
/// restart (o processo morre), mas o **output** persiste: o `TaskTerminalStore`
/// grava o buffer em disco e o re-semeia ao recriar o terminal, então o restore
/// reabre a aba mostrando o último output (read-only).
class TaskOutputSession extends PaneItem {
  TaskOutputSession({
    required this.id,
    required this.projectId,
    required this.taskId,
    required String label,
    required this.terminal,
    required this.workingDirectory,
  }) : _label = label;

  @override
  final String id;
  @override
  final String projectId;

  /// Id da [TaskDefinition] cujo output esta aba espelha.
  final String taskId;

  /// Terminal compartilhado (dono = `TaskTerminalStore`). **Não** dar dispose.
  final CockpitTerminalController terminal;

  final String _label;

  /// Rótulo cru (sem o prefixo `▶`), persistido pra restaurar a aba.
  String get label => _label;

  @override
  final String workingDirectory;

  @override
  String get title => '▶ $_label';
}
