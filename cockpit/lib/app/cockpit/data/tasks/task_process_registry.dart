import 'package:cockpit/app/core/data/process/owned_process_registry.dart';

/// Registro isolado dos processos raiz das tasks executadas em PTY.
///
/// Não usa o registry de agentes: um Cockpit iniciado por `flutter run` é filho
/// da task do Cockpit pai e não pode interpretar esse PID como agente órfão.
class TaskProcessRegistry {
  TaskProcessRegistry._();

  static final OwnedProcessRegistry _registry = OwnedProcessRegistry(
    category: 'tasks',
  );

  static Future<void> cleanOrphans() => _registry.cleanOrphans();

  static Future<void> register(int pid) => _registry.register(pid);

  static Future<void> unregister(int pid) => _registry.unregister(pid);
}
