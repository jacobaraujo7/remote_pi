// Entrada de telemetria (plano 66, passo 3): quem é pai de um processo
// (runner de task hoje, wrapper `cockpit telemetry` depois) abre uma sessão,
// despeja a saída crua nela e fecha com o exit code. A sessão cuida de
// separar linhas, passar pelo parser e gravar no store do workspace certo.

import '../entities/task_definition.dart';
import '../entities/telemetry_event.dart';

/// Sessão de ingest de UM run. Aceita chunks arbitrários (não precisam
/// terminar em `\n`); o resto de linha fica em buffer até o próximo chunk
/// ou o [close].
/// Id do "workspace" que guarda os runs do próprio app (plano 68). Não é um
/// projeto: é um store fixo, consultado com `cockpit telemetry --app`.
const String kTelemetryAppWorkspaceId = '__cockpit__';

abstract class TelemetryIngestSession {
  String get runId;

  /// Variáveis a injetar no processo filho (`COCKPIT_RUN_ID`, `OTEL_*`).
  Map<String, String> get childEnvironment;

  void add(String chunk, {TelemetryStream stream = TelemetryStream.out});

  /// Eventos já estruturados (VM Service, OTLP, o próprio app).
  void addEvents(List<TelemetryEvent> events);

  Future<void> close({int? exitCode});
}

/// Contexto de um workspace registrado pra roteamento de runs.
class TelemetryWorkspace {
  const TelemetryWorkspace({
    required this.id,
    required this.name,
    required this.path,
    required this.roots,
  });

  /// UUID do workspace (chave da base).
  final String id;
  final String name;
  final String path;

  /// Roots multi-root (raiz única = `[path]`).
  final List<String> roots;
}

/// Aviso de erros recém-gravados num run (push pro agente, passo 7). Quem
/// decide se é "novo" e quando entregar é a UI (conhece o status do turno).
class TelemetryErrorNotice {
  const TelemetryErrorNotice({
    required this.workspaceId,
    required this.runId,
    required this.project,
    required this.fingerprints,
    this.paneId,
  });
  final String workspaceId;
  final String runId;
  final String project;
  final String? paneId;
  final Set<String> fingerprints;
}

abstract class TelemetryIngest {
  /// Erros gravados, por lote (fingerprints únicos do lote).
  Stream<TelemetryErrorNotice> get notices;

  /// Informa o workspace ativo (id + roots). Chamado pela UI a cada troca;
  /// runs resolvem seu workspace pelo `cwd` contra os registrados.
  void registerWorkspace(TelemetryWorkspace workspace);

  /// Abre um run vindo do wrapper `cockpit telemetry <cmd>` (terminal solto
  /// ou Bash do agente). `null` se o `cwd` não pertence a workspace algum.
  Future<TelemetryIngestSession?> openWrapperRun({
    required String cwd,
    required String command,
    String? name,
    String? paneId,
    int? pid,
  });

  /// Sessão aberta e ainda viva por `runId` (pra `telemetry-ingest/close`).
  TelemetryIngestSession? session(String runId);

  /// Run do PRÓPRIO Cockpit (plano 68): erros dos handlers globais, warnings e
  /// métricas do app. Um por boot, no store [kTelemetryAppWorkspaceId].
  Future<TelemetryIngestSession?> openAppRun({required String version});

  /// Reenvia pelo proxy HTTP do workspace os requests gravados na janela.
  /// `null` = workspace sem proxy configurado; senão quantos foram enviados.
  Future<int?> replay({
    required String workspaceId,
    required DateTime since,
    DateTime? until,
  });

  /// Abre um run de task. `null` quando a task desligou telemetria ou o
  /// `cwd` não pertence a nenhum workspace registrado.
  Future<TelemetryIngestSession?> openTaskRun(
    TaskDefinition def, {
    required String command,
    int? pid,
    String? paneId,
  });
}
