// Contrato da base de telemetria (plano 66): um store por workspace, no
// cache global do Cockpit. Quem escreve: ingest de task/wrapper/VM/OTLP.
// Quem lê: aba Telemetry (UI) e handler da CLI. Nunca devolve frase pronta;
// erros são tipados.

import '../entities/telemetry_case.dart';
import '../entities/telemetry_event.dart';
import '../entities/telemetry_run.dart';

/// Filtros de consulta compartilhados por `errors`, `logs`, `events`.
class TelemetryQuery {
  const TelemetryQuery({
    this.project,
    this.runId,
    this.runKey,
    this.taskKey,
    this.paneId,
    this.minSeverity,
    this.since,
    this.until,
    this.text,
    this.probe,
    this.onlyNew = false,
    this.includeIgnored = false,
    this.includeResolved = false,
    this.limit = 100,
  });

  final String? project;
  final String? runId;
  final String? runKey;
  final String? taskKey;
  final String? paneId;
  final TelemetrySeverity? minSeverity;
  final DateTime? since;
  final DateTime? until;

  /// Busca textual em `body`/`attrs` (FTS quando disponível).
  final String? text;

  /// Só eventos com `attrs.probe == probe` (`*` = qualquer sonda).
  final String? probe;
  final bool onlyNew;
  final bool includeIgnored;
  final bool includeResolved;
  final int limit;
}

/// Falhas tipadas do store (a UI traduz).
enum TelemetryStoreErrorKind { notFound, io, corrupt, closed }

class TelemetryStoreError implements Exception {
  const TelemetryStoreError(this.kind, {this.detail});
  final TelemetryStoreErrorKind kind;
  final String? detail;

  @override
  String toString() =>
      'TelemetryStoreError($kind${detail == null ? '' : ': $detail'})';
}

/// Política de retenção (ring buffer por tamanho e idade; runs inteiros mais
/// antigos saem primeiro).
class TelemetryRetention {
  const TelemetryRetention({
    this.maxBytes = 256 * 1024 * 1024,
    this.maxAge = const Duration(days: 7),
  });
  final int maxBytes;
  final Duration maxAge;
}

/// Um store por workspace (o app cacheia os abertos). A UI e a CLI resolvem
/// por aqui; nunca abrem arquivo direto.
abstract class TelemetryStoreProvider {
  Future<TelemetryStore> forWorkspace(String workspaceId);
}

abstract class TelemetryStore {
  // ---- runs ----------------------------------------------------------------

  /// Abre um run. O store gera o [TelemetryRun.id].
  Future<TelemetryRun> openRun({
    required String key,
    required String project,
    required TelemetryRunSource source,
    required String cwd,
    required String command,
    String? name,
    String? taskKey,
    String? paneId,
    int? pid,
    DateTime? startedAt,
  });

  Future<void> closeRun(String runId, {int? exitCode, DateTime? endedAt});

  Future<TelemetryRun?> run(String runId);

  Future<List<TelemetryRun>> runs({
    String? project,
    String? key,
    bool onlyLive = false,
    int limit = 50,
  });

  // ---- eventos -------------------------------------------------------------

  /// Insere em lote (uma transação). Devolve os eventos com `id` preenchido
  /// e `fingerprint` calculado quando há erro.
  Future<List<TelemetryEvent>> append(List<TelemetryEvent> events);

  Future<TelemetryEvent?> event(String eventId);

  Future<List<TelemetryEvent>> events(TelemetryQuery query);

  /// Linhas cruas ao redor de um evento (mesmo run), pra `show --context`.
  Future<List<TelemetryEvent>> context(
    String eventId, {
    int before = 10,
    int after = 5,
  });

  // ---- casos e triagem -----------------------------------------------------

  /// Casos agrupados por fingerprint + chave de run, respeitando a triagem
  /// (ignorados/resolvidos ficam fora salvo flags do [query]).
  Future<List<TelemetryCase>> cases(TelemetryQuery query);

  /// Resolve `e_3f2a` (short id) ou fingerprint completo.
  Future<TelemetryCase?> caseById(String idOrFingerprint);

  Future<void> triage(
    String fingerprint,
    TelemetryTriageStatus status, {
    required TelemetryTriageActor by,
    String? reason,
  });

  // ---- marcas --------------------------------------------------------------

  Future<void> markStart(String name, {DateTime? at});
  Future<void> markEnd(String name, {DateTime? at});
  Future<(DateTime start, DateTime? end)?> mark(String name);

  // ---- manutenção ----------------------------------------------------------

  Future<void> clear({String? fingerprint, String? runId, String? project});

  /// Aplica a retenção; devolve bytes liberados (aproximado).
  Future<int> vacuum(TelemetryRetention retention);

  Future<int> sizeInBytes();

  Future<void> close();
}
