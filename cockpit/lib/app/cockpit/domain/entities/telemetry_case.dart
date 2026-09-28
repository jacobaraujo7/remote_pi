// Caso = fingerprint agrupado dentro de uma chave de run, com estado de
// triagem (plano 66, decisão 10). É o que a aba Telemetry lista e o que a CLI
// devolve em `errors`. A triagem vive por fingerprint e sobrevive a runs.

import 'telemetry_event.dart';

enum TelemetryTriageStatus { open, resolved, ignored }

enum TelemetryTriageActor { human, agent }

class TelemetryTriage {
  const TelemetryTriage({
    required this.fingerprint,
    required this.status,
    required this.by,
    required this.at,
    this.reason,
  });

  final String fingerprint;
  final TelemetryTriageStatus status;
  final TelemetryTriageActor by;
  final DateTime at;
  final String? reason;
}

/// Ocorrências de um caso dentro de um run específico.
class TelemetryCaseRun {
  const TelemetryCaseRun({
    required this.runId,
    required this.count,
    required this.firstAt,
    required this.lastAt,
    required this.live,
  });

  final String runId;
  final int count;
  final DateTime firstAt;
  final DateTime lastAt;
  final bool live;
}

class TelemetryCase {
  const TelemetryCase({
    required this.fingerprint,
    required this.runKey,
    required this.project,
    required this.severity,
    required this.type,
    required this.message,
    required this.count,
    required this.firstAt,
    required this.lastAt,
    required this.status,
    required this.isNew,
    required this.isRegression,
    required this.runs,
    this.location,
    this.triage,
    this.lastEventId,
  });

  final String fingerprint;
  final String runKey;
  final String project;
  final TelemetrySeverity severity;
  final String type;
  final String message;

  /// `arquivo:linha` do primeiro frame do projeto (`null` sem frame).
  final String? location;

  /// Soma de `repeat` de todas as ocorrências (todos os runs da chave).
  final int count;
  final DateTime firstAt;
  final DateTime lastAt;

  final TelemetryTriageStatus status;
  final TelemetryTriage? triage;

  /// Fingerprint sem ocorrência em nenhum run anterior da mesma chave.
  final bool isNew;

  /// Estava `resolved` e voltou num run posterior à triagem.
  final bool isRegression;

  /// Ocorrências por run, do mais recente pro mais antigo.
  final List<TelemetryCaseRun> runs;

  /// Id do evento mais recente (pra `show` e "ver no terminal").
  final String? lastEventId;

  /// Id curto e estável usado na CLI/UI (`e_` + 4 primeiros hex do
  /// fingerprint). Colisão é resolvida pelo store com mais dígitos.
  String get shortId => 'e_${fingerprint.substring(0, 4)}';
}
