// Unidade básica da telemetria (plano 66, decisão 1): a vida de UM processo
// observado. Task = run com nome; terminal solto / Bash do agente = run aberto
// pelo wrapper `cockpit telemetry <cmd>`. A [key] é o que permite comparar
// runs do mesmo comando ao longo dos dias ("isso é novo?", regressão).

/// Quem abriu o run.
/// `app` = o próprio Cockpit (plano 68): um run por boot, no store
/// `kTelemetryAppWorkspaceId`, alimentado pelo `DiagnosticsLog`.
enum TelemetryRunSource { task, wrapper, app }

class TelemetryRun {
  const TelemetryRun({
    required this.id,
    required this.key,
    required this.project,
    required this.source,
    required this.cwd,
    required this.command,
    required this.startedAt,
    this.name,
    this.taskKey,
    this.paneId,
    this.pid,
    this.endedAt,
    this.exitCode,
  });

  /// Identificador estável (`r_` + base36 monotônico dentro da base).
  final String id;

  /// Chave estável entre execuções: `--name`/nome da task quando existe,
  /// senão `(cwd, comando)` normalizado. Ver [TelemetryRun.keyFor].
  final String key;

  /// Root multi-root resolvida a partir do [cwd] (raiz única = nome do
  /// workspace).
  final String project;

  final TelemetryRunSource source;
  final String cwd;

  /// Linha de comando como foi digitada/definida (argv unido por espaço).
  final String command;

  /// Nome amigável (task ou `--name`). `null` quando o run é anônimo.
  final String? name;

  /// `TaskDefinition.id` quando [source] é [TelemetryRunSource.task].
  final String? taskKey;

  /// Pane onde o processo roda (`COCKPIT_PANE_ID`), pra badge e push.
  final String? paneId;

  final int? pid;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int? exitCode;

  bool get isLive => endedAt == null;

  /// Chave canônica: nome explícito vence; senão cwd absoluto + comando com
  /// espaços colapsados. Não inclui flags voláteis (ex.: `--vm-service-port`).
  static String keyFor({
    required String cwd,
    required String command,
    String? name,
  }) {
    if (name != null && name.trim().isNotEmpty) return 'name:${name.trim()}';
    final cmd = command.trim().replaceAll(RegExp(r'\s+'), ' ');
    return 'cmd:$cwd::$cmd';
  }

  TelemetryRun copyWith({DateTime? endedAt, int? exitCode, int? pid}) =>
      TelemetryRun(
        id: id,
        key: key,
        project: project,
        source: source,
        cwd: cwd,
        command: command,
        startedAt: startedAt,
        name: name,
        taskKey: taskKey,
        paneId: paneId,
        pid: pid ?? this.pid,
        endedAt: endedAt ?? this.endedAt,
        exitCode: exitCode ?? this.exitCode,
      );
}
