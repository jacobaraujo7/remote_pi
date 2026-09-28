// (De)serialização das entidades de telemetria em mapas sendable entre
// isolates e gravaveis como JSON. Mora no data/ pra manter o domain/ sem
// conhecimento de formato.

import 'dart:convert';

import '../../domain/entities/telemetry_case.dart';
import '../../domain/entities/telemetry_event.dart';
import '../../domain/entities/telemetry_run.dart';

int _ms(DateTime d) => d.millisecondsSinceEpoch;
DateTime _dt(Object? v) =>
    DateTime.fromMillisecondsSinceEpoch((v as num).toInt());
DateTime? _dtn(Object? v) => v == null ? null : _dt(v);

Map<String, Object?> runToMap(TelemetryRun r) => {
  'id': r.id,
  'key': r.key,
  'project': r.project,
  'source': r.source.name,
  'cwd': r.cwd,
  'command': r.command,
  'name': r.name,
  'task_key': r.taskKey,
  'pane_id': r.paneId,
  'pid': r.pid,
  'started_at': _ms(r.startedAt),
  'ended_at': r.endedAt == null ? null : _ms(r.endedAt!),
  'exit_code': r.exitCode,
};

TelemetryRun runFromMap(Map<String, Object?> m) => TelemetryRun(
  id: m['id'] as String,
  key: m['key'] as String,
  project: m['project'] as String,
  source: TelemetryRunSource.values.byName(m['source'] as String),
  cwd: m['cwd'] as String,
  command: m['command'] as String,
  name: m['name'] as String?,
  taskKey: m['task_key'] as String?,
  paneId: m['pane_id'] as String?,
  pid: (m['pid'] as num?)?.toInt(),
  startedAt: _dt(m['started_at']),
  endedAt: _dtn(m['ended_at']),
  exitCode: (m['exit_code'] as num?)?.toInt(),
);

Map<String, Object?> eventToMap(TelemetryEvent e) => {
  'id': e.id,
  'run_id': e.runId,
  'ts': _ms(e.ts),
  'stream': e.stream.name,
  'severity': e.severity.index,
  'body': e.body,
  'attrs': e.attrs.isEmpty ? null : jsonEncode(e.attrs),
  'error': e.error == null ? null : jsonEncode(e.error!.toJson()),
  'fingerprint': e.fingerprint,
  'trace_id': e.traceId,
  'span_id': e.spanId,
  'request_id': e.requestId,
  'raw_offset': e.rawLineOffset,
  'repeat': e.repeat,
};

TelemetryEvent eventFromMap(Map<String, Object?> m) {
  final attrs = m['attrs'];
  final err = m['error'];
  return TelemetryEvent(
    id: m['id'] as String?,
    runId: m['run_id'] as String,
    ts: _dt(m['ts']),
    stream: TelemetryStream.values.byName(m['stream'] as String),
    severity: TelemetrySeverity.values[(m['severity'] as num).toInt()],
    body: m['body'] as String? ?? '',
    attrs: attrs is String && attrs.isNotEmpty
        ? (jsonDecode(attrs) as Map).cast<String, Object?>()
        : const {},
    error: err is String && err.isNotEmpty
        ? TelemetryError.fromJson(
            (jsonDecode(err) as Map).cast<String, Object?>(),
          )
        : null,
    fingerprint: m['fingerprint'] as String?,
    traceId: m['trace_id'] as String?,
    spanId: m['span_id'] as String?,
    requestId: m['request_id'] as String?,
    rawLineOffset: (m['raw_offset'] as num?)?.toInt(),
    repeat: (m['repeat'] as num?)?.toInt() ?? 1,
  );
}

Map<String, Object?> caseToMap(TelemetryCase c) => {
  'fingerprint': c.fingerprint,
  'run_key': c.runKey,
  'project': c.project,
  'severity': c.severity.index,
  'type': c.type,
  'message': c.message,
  'location': c.location,
  'count': c.count,
  'first_at': _ms(c.firstAt),
  'last_at': _ms(c.lastAt),
  'status': c.status.name,
  'is_new': c.isNew,
  'is_regression': c.isRegression,
  'last_event_id': c.lastEventId,
  'triage': c.triage == null
      ? null
      : {
          'status': c.triage!.status.name,
          'by': c.triage!.by.name,
          'at': _ms(c.triage!.at),
          'reason': c.triage!.reason,
        },
  'runs': [
    for (final r in c.runs)
      {
        'run_id': r.runId,
        'count': r.count,
        'first_at': _ms(r.firstAt),
        'last_at': _ms(r.lastAt),
        'live': r.live,
      },
  ],
};

TelemetryCase caseFromMap(Map<String, Object?> m) {
  final t = m['triage'] as Map?;
  return TelemetryCase(
    fingerprint: m['fingerprint'] as String,
    runKey: m['run_key'] as String,
    project: m['project'] as String,
    severity: TelemetrySeverity.values[(m['severity'] as num).toInt()],
    type: m['type'] as String,
    message: m['message'] as String,
    location: m['location'] as String?,
    count: (m['count'] as num).toInt(),
    firstAt: _dt(m['first_at']),
    lastAt: _dt(m['last_at']),
    status: TelemetryTriageStatus.values.byName(m['status'] as String),
    isNew: m['is_new'] == true,
    isRegression: m['is_regression'] == true,
    lastEventId: m['last_event_id'] as String?,
    triage: t == null
        ? null
        : TelemetryTriage(
            fingerprint: m['fingerprint'] as String,
            status: TelemetryTriageStatus.values.byName(t['status'] as String),
            by: TelemetryTriageActor.values.byName(t['by'] as String),
            at: _dt(t['at']),
            reason: t['reason'] as String?,
          ),
    runs: [
      for (final r in (m['runs'] as List).cast<Map>())
        TelemetryCaseRun(
          runId: r['run_id'] as String,
          count: (r['count'] as num).toInt(),
          firstAt: _dt(r['first_at']),
          lastAt: _dt(r['last_at']),
          live: r['live'] == true,
        ),
    ],
  );
}
