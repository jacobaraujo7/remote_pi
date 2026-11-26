import '../contracts/worktree_manager.dart';
import '../utils/coalescing_single_flight.dart';

/// Single-flight da reconciliação de worktrees, mantendo o manager explícito
/// para que o wiring manager→gate seja observável em teste.
class WorktreeReconciler {
  WorktreeReconciler(this.manager);

  final WorktreeManager manager;
  final CoalescingSingleFlight<String> _flights =
      CoalescingSingleFlight<String>();

  Future<void> settle() => _flights.settle();

  Future<void> run(
    String rootId,
    Future<void> Function(WorktreeManager manager) operation,
  ) => _flights.run(rootId, () => operation(manager));
}
