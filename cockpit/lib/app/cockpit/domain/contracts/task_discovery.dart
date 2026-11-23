import 'package:cockpit/app/cockpit/domain/entities/task_definition.dart';

/// Agrega os [TaskAdapter]s e devolve as tasks de um projeto. Também é o ponto
/// onde o `.cockpit/tasks.json` (manual) é mesclado sobre as detectadas.
abstract class TaskDiscovery {
  /// Tasks do projeto em [cwd]: detectadas pelos adapters + manuais do JSON.
  /// Returned IDs must include [workspaceId], the discovery root and the
  /// remote host, using [TaskDefinition.scopedTo], before entering shared state.
  /// Omit [workspaceId] only for standalone discovery outside a workspace.
  Future<List<TaskDefinition>> discover(String cwd, {String? workspaceId});
}
