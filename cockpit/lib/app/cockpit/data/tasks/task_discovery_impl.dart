import 'package:cockpit/app/cockpit/data/tasks/tasks_json_loader.dart';
import 'package:cockpit/app/cockpit/domain/contracts/task_adapter.dart';
import 'package:cockpit/app/cockpit/domain/contracts/task_discovery.dart';
import 'package:cockpit/app/cockpit/domain/entities/task_definition.dart';

/// Junta as duas fontes de tasks de um projeto:
///
/// 1. **Detecção** — cada [TaskAdapter] que reconhece o `cwd` (mesmo padrão
///    multi-marcador do `project_root_finder`).
/// 2. **Manual** — o `.cockpit/tasks.json` via [TasksJsonLoader].
///
/// O JSON tem **precedência**: uma task manual com o mesmo `id` de uma detectada
/// substitui a detectada (deixa o usuário sobrescrever a heurística).
class TaskDiscoveryImpl implements TaskDiscovery {
  TaskDiscoveryImpl(
    this._adapters, [
    this._jsonLoader = const TasksJsonLoader(),
  ]);

  final List<TaskAdapter> _adapters;
  final TasksJsonLoader _jsonLoader;

  @override
  Future<List<TaskDefinition>> discover(
    String cwd, {
    String? workspaceId,
  }) async {
    if (cwd.isEmpty) return const [];
    final detected = await Future.wait(
      _adapters.map((a) async {
        return await a.matches(cwd)
            ? await a.tasksFor(cwd)
            : const <TaskDefinition>[];
      }),
    );
    final manual = await _jsonLoader.load(cwd);

    // Indexa por id; manuais (do JSON) sobrescrevem detectadas de mesmo id.
    final byId = <String, TaskDefinition>{};
    for (final list in detected) {
      for (final t in list) {
        byId[t.id] = t;
      }
    }
    for (final t in manual) {
      byId[t.id] = t;
    }
    return byId.values
        .map((task) => task.scopedTo(cwd, workspaceId: workspaceId))
        .toList();
  }
}
