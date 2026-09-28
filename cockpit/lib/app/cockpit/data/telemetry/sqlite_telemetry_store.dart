// Implementação do `TelemetryStore` sobre o `TelemetryDb`, hospedado num
// isolate dedicado (a FFI do sqlite bloqueia a thread; escrita quente de dev
// server não pode disputar a UI). Uma instância por workspace.

import 'dart:async';
import 'dart:isolate';

import '../../domain/contracts/telemetry_store.dart';
import '../../domain/entities/telemetry_case.dart';
import '../../domain/entities/telemetry_event.dart';
import '../../domain/entities/telemetry_run.dart';
import 'telemetry_codec.dart';
import 'telemetry_db.dart';

class SqliteTelemetryStore implements TelemetryStore {
  SqliteTelemetryStore._(this._path);

  /// Abre (ou cria) a base em [path]. `':memory:'` para testes.
  static Future<SqliteTelemetryStore> open(String path) async {
    final s = SqliteTelemetryStore._(path);
    await s._spawn();
    return s;
  }

  final String _path;
  late final SendPort _tx;
  late final Isolate _isolate;
  final _rx = ReceivePort();
  final _pending = <int, Completer<Object?>>{};
  var _seq = 0;
  var _closed = false;

  Future<void> _spawn() async {
    final ready = Completer<SendPort>();
    _rx.listen((msg) {
      if (msg is SendPort) {
        ready.complete(msg);
        return;
      }
      final (int id, bool ok, Object? payload) = msg as (int, bool, Object?);
      final c = _pending.remove(id);
      if (c == null) return;
      if (ok) {
        c.complete(payload);
      } else {
        c.completeError(
          TelemetryStoreError(TelemetryStoreErrorKind.io, detail: '$payload'),
        );
      }
    });
    _isolate = await Isolate.spawn(_worker, (
      _rx.sendPort,
      _path,
    ), debugName: 'telemetry-db');
    _tx = await ready.future;
  }

  Future<T> _call<T>(String method, [Map<String, Object?> args = const {}]) {
    if (_closed) {
      throw const TelemetryStoreError(TelemetryStoreErrorKind.closed);
    }
    final id = ++_seq;
    final c = Completer<Object?>();
    _pending[id] = c;
    _tx.send((id, method, args));
    return c.future.then((v) => v as T);
  }

  static void _worker((SendPort, String) init) {
    final (out, path) = init;
    final rx = ReceivePort();
    out.send(rx.sendPort);
    final db = path == ':memory:'
        ? TelemetryDb.memory()
        : TelemetryDb.open(path);
    rx.listen((msg) {
      final (int id, String method, Map<String, Object?> a) =
          msg as (int, String, Map<String, Object?>);
      try {
        final r = _dispatch(db, method, a);
        out.send((id, true, r));
        if (method == 'close') {
          db.dispose();
          rx.close();
        }
      } catch (e) {
        out.send((id, false, e.toString()));
      }
    });
  }

  static Object? _dispatch(
    TelemetryDb db,
    String m,
    Map<String, Object?> a,
  ) => switch (m) {
    'openRun' => db.openRun(a),
    'closeRun' => _v(
      () => db.closeRun(
        a['id'] as String,
        exitCode: a['exit_code'] as int?,
        endedAt: a['ended_at'] as int,
      ),
    ),
    'run' => db.run(a['id'] as String),
    'runs' => db.runs(
      project: a['project'] as String?,
      key: a['key'] as String?,
      onlyLive: a['only_live'] == true,
      limit: a['limit'] as int,
    ),
    'append' => db.append((a['events'] as List).cast<Map<String, Object?>>()),
    'event' => db.event(a['id'] as String),
    'events' => db.events(a),
    'context' => db.context(
      a['id'] as String,
      before: a['before'] as int,
      after: a['after'] as int,
    ),
    'cases' => db.cases(a),
    'caseById' => db.caseById(a['id'] as String),
    'triage' => _v(
      () => db.triage(
        a['fingerprint'] as String,
        a['status'] as String,
        actor: a['actor'] as String,
        reason: a['reason'] as String?,
        at: a['at'] as int,
      ),
    ),
    'markStart' => _v(() => db.markStart(a['name'] as String, a['at'] as int)),
    'markEnd' => _v(() => db.markEnd(a['name'] as String, a['at'] as int)),
    'mark' => db.mark(a['name'] as String),
    'clear' => _v(
      () => db.clear(
        fingerprint: a['fingerprint'] as String?,
        runId: a['run_id'] as String?,
        project: a['project'] as String?,
      ),
    ),
    'vacuum' => db.vacuum(
      maxBytes: a['max_bytes'] as int,
      maxAgeMs: a['max_age_ms'] as int,
      now: a['now'] as int,
    ),
    'size' => db.sizeInBytes(),
    'close' => null,
    _ => throw ArgumentError('unknown method $m'),
  };

  static Object? _v(void Function() f) {
    f();
    return null;
  }

  Map<String, Object?> _query(TelemetryQuery q, {bool onlyErrors = false}) => {
    'project': q.project,
    'run_id': q.runId,
    'run_key': q.runKey,
    'task_key': q.taskKey,
    'pane_id': q.paneId,
    'min_severity': q.minSeverity?.index,
    'since': q.since?.millisecondsSinceEpoch,
    'until': q.until?.millisecondsSinceEpoch,
    'text': q.text,
    'probe': q.probe,
    'only_new': q.onlyNew,
    'include_ignored': q.includeIgnored,
    'include_resolved': q.includeResolved,
    'only_errors': onlyErrors,
    'limit': q.limit,
  };

  // ---- TelemetryStore --------------------------------------------------------

  @override
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
  }) async {
    final m = await _call<Map<String, Object?>>('openRun', {
      'key': key,
      'project': project,
      'source': source.name,
      'cwd': cwd,
      'command': command,
      'name': name,
      'task_key': taskKey,
      'pane_id': paneId,
      'pid': pid,
      'started_at': (startedAt ?? DateTime.now()).millisecondsSinceEpoch,
    });
    return runFromMap(m);
  }

  @override
  Future<void> closeRun(String runId, {int? exitCode, DateTime? endedAt}) =>
      _call<void>('closeRun', {
        'id': runId,
        'exit_code': exitCode,
        'ended_at': (endedAt ?? DateTime.now()).millisecondsSinceEpoch,
      });

  @override
  Future<TelemetryRun?> run(String runId) async {
    final m = await _call<Map<String, Object?>?>('run', {'id': runId});
    return m == null ? null : runFromMap(m);
  }

  @override
  Future<List<TelemetryRun>> runs({
    String? project,
    String? key,
    bool onlyLive = false,
    int limit = 50,
  }) async {
    final l = await _call<List>('runs', {
      'project': project,
      'key': key,
      'only_live': onlyLive,
      'limit': limit,
    });
    return [for (final m in l) runFromMap((m as Map).cast())];
  }

  @override
  Future<List<TelemetryEvent>> append(List<TelemetryEvent> events) async {
    if (events.isEmpty) return const [];
    final ids = await _call<List>('append', {
      'events': [for (final e in events) eventToMap(e)],
    });
    return [
      for (var i = 0; i < events.length; i++)
        events[i].copyWith(id: ids[i] as String),
    ];
  }

  @override
  Future<TelemetryEvent?> event(String eventId) async {
    final m = await _call<Map<String, Object?>?>('event', {'id': eventId});
    return m == null ? null : eventFromMap(m);
  }

  @override
  Future<List<TelemetryEvent>> events(TelemetryQuery query) async {
    final l = await _call<List>('events', _query(query));
    return [for (final m in l) eventFromMap((m as Map).cast())];
  }

  @override
  Future<List<TelemetryEvent>> context(
    String eventId, {
    int before = 10,
    int after = 5,
  }) async {
    final l = await _call<List>('context', {
      'id': eventId,
      'before': before,
      'after': after,
    });
    return [for (final m in l) eventFromMap((m as Map).cast())];
  }

  @override
  Future<List<TelemetryCase>> cases(TelemetryQuery query) async {
    final l = await _call<List>('cases', _query(query));
    return [for (final m in l) caseFromMap((m as Map).cast())];
  }

  @override
  Future<TelemetryCase?> caseById(String idOrFingerprint) async {
    final m = await _call<Map<String, Object?>?>('caseById', {
      'id': idOrFingerprint,
    });
    return m == null ? null : caseFromMap(m);
  }

  @override
  Future<void> triage(
    String fingerprint,
    TelemetryTriageStatus status, {
    required TelemetryTriageActor by,
    String? reason,
  }) => _call<void>('triage', {
    'fingerprint': fingerprint,
    'status': status.name,
    'actor': by.name,
    'reason': reason,
    'at': DateTime.now().millisecondsSinceEpoch,
  });

  @override
  Future<void> markStart(String name, {DateTime? at}) => _call<void>(
    'markStart',
    {'name': name, 'at': (at ?? DateTime.now()).millisecondsSinceEpoch},
  );

  @override
  Future<void> markEnd(String name, {DateTime? at}) => _call<void>('markEnd', {
    'name': name,
    'at': (at ?? DateTime.now()).millisecondsSinceEpoch,
  });

  @override
  Future<(DateTime, DateTime?)?> mark(String name) async {
    final m = await _call<Map<String, Object?>?>('mark', {'name': name});
    if (m == null) return null;
    final end = m['end_at'] as int?;
    return (
      DateTime.fromMillisecondsSinceEpoch(m['start_at'] as int),
      end == null ? null : DateTime.fromMillisecondsSinceEpoch(end),
    );
  }

  @override
  Future<void> clear({String? fingerprint, String? runId, String? project}) =>
      _call<void>('clear', {
        'fingerprint': fingerprint,
        'run_id': runId,
        'project': project,
      });

  @override
  Future<int> vacuum(TelemetryRetention retention) => _call<int>('vacuum', {
    'max_bytes': retention.maxBytes,
    'max_age_ms': retention.maxAge.inMilliseconds,
    'now': DateTime.now().millisecondsSinceEpoch,
  });

  @override
  Future<int> sizeInBytes() => _call<int>('size');

  @override
  Future<void> close() async {
    if (_closed) return;
    await _call<void>('close');
    _closed = true;
    _rx.close();
    _isolate.kill(priority: Isolate.beforeNextEvent);
  }
}
