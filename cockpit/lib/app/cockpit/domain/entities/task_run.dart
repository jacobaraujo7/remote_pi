// Estado VIVO de uma execução de task. O output (bytes) vai pro CockpitTerminal;
// o TaskRun guarda só status/metadata pra UI do subpane reagir.

/// Ciclo de vida de uma execução, refletido no badge do subpane.
///
/// - [idle]: nunca rodou / foi resetada.
/// - [starting]: play apertado, spawn em preparação (processo ainda não vivo).
/// - [building]: recompilando (entrou num [ProgressPattern.begin]).
/// - [running]: vivo e ocioso (watch) — voltou de um build.
/// - [stopping]: stop apertado, aguardando o processo morrer.
/// - [success]: oneShot terminou com exit 0.
/// - [failed]: terminou com exit != 0.
/// - [stopped]: morto pelo usuário (stop).
enum TaskRunStatus {
  idle,
  starting,
  building,
  running,
  stopping,
  success,
  failed,
  stopped,
}

/// Snapshot imutável do estado de uma task em execução.
class TaskRun {
  const TaskRun({
    required this.taskId,
    required this.status,
    this.profileName,
    this.pid,
    this.exitCode,
  });

  /// [TaskDefinition.id] da task que esta execução representa.
  final String taskId;

  final TaskRunStatus status;

  /// Profile escolhido no start (null = sem profile).
  final String? profileName;

  /// PID do processo enquanto vivo (null quando idle/stopped/terminado).
  final int? pid;

  /// Código de saída quando terminou (null enquanto roda).
  final int? exitCode;

  /// `true` enquanto há processo vivo (building ou running).
  bool get isActive =>
      status == TaskRunStatus.building || status == TaskRunStatus.running;

  /// `true` durante transições (starting/stopping) — a UI mostra progresso e
  /// bloqueia play/stop pra não empilhar comandos.
  bool get isTransitioning =>
      status == TaskRunStatus.starting || status == TaskRunStatus.stopping;

  TaskRun copyWith({
    TaskRunStatus? status,
    String? profileName,
    int? pid,
    int? exitCode,
  }) => TaskRun(
    taskId: taskId,
    status: status ?? this.status,
    profileName: profileName ?? this.profileName,
    pid: pid ?? this.pid,
    exitCode: exitCode ?? this.exitCode,
  );

  static TaskRun idleFor(String taskId) =>
      TaskRun(taskId: taskId, status: TaskRunStatus.idle);
}
