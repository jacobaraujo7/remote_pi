// Base SQLite da telemetria (plano 66, passo 2). Síncrona, sobre `sqlite3`,
// pensada pra viver dentro de UM isolate (o `SqliteTelemetryStore` a hospeda
// e fala com ela por mensagens). Só recebe e devolve valores sendable
// (Map/List/String/num/bool) — as entidades são montadas do lado de fora
// pelo `telemetry_codec.dart`.
//
// Um arquivo por workspace, no cache global do Cockpit (nunca dentro do repo).

import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../../domain/entities/telemetry_case.dart';
import '../../domain/entities/telemetry_event.dart';
import 'fingerprint.dart';
import 'redaction.dart';

class TelemetryDb {
  TelemetryDb.open(String path) : _db = sqlite3.open(path) {
    _db.execute('PRAGMA journal_mode=WAL');
    _db.execute('PRAGMA synchronous=NORMAL');
    _db.execute('PRAGMA auto_vacuum=INCREMENTAL');
    _db.execute('PRAGMA foreign_keys=ON');
    _migrate();
  }

  /// Base em memória (testes).
  TelemetryDb.memory() : _db = sqlite3.openInMemory() {
    _migrate();
  }

  final Database _db;
  bool _fts = false;

  bool get hasFts => _fts;

  void dispose() => _db.close();

  // ---- schema ----------------------------------------------------------------

  void _migrate() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS runs (
        id TEXT PRIMARY KEY,
        key TEXT NOT NULL,
        project TEXT NOT NULL,
        source TEXT NOT NULL,
        cwd TEXT NOT NULL,
        command TEXT NOT NULL,
        name TEXT,
        task_key TEXT,
        pane_id TEXT,
        pid INTEGER,
        started_at INTEGER NOT NULL,
        ended_at INTEGER,
        exit_code INTEGER
      );
      CREATE INDEX IF NOT EXISTS runs_key ON runs(key, started_at);
      CREATE INDEX IF NOT EXISTS runs_project ON runs(project, started_at);

      CREATE TABLE IF NOT EXISTS events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        run_id TEXT NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
        ts INTEGER NOT NULL,
        stream TEXT NOT NULL,
        severity INTEGER NOT NULL,
        body TEXT NOT NULL,
        attrs TEXT,
        error TEXT,
        fingerprint TEXT,
        trace_id TEXT,
        span_id TEXT,
        request_id TEXT,
        raw_offset INTEGER,
        repeat INTEGER NOT NULL DEFAULT 1
      );
      CREATE INDEX IF NOT EXISTS events_run ON events(run_id, id);
      CREATE INDEX IF NOT EXISTS events_fp ON events(fingerprint, ts);
      CREATE INDEX IF NOT EXISTS events_ts ON events(ts);
      CREATE INDEX IF NOT EXISTS events_trace ON events(trace_id);

      CREATE TABLE IF NOT EXISTS triage (
        fingerprint TEXT PRIMARY KEY,
        status TEXT NOT NULL,
        actor TEXT NOT NULL,
        at INTEGER NOT NULL,
        reason TEXT
      );

      CREATE TABLE IF NOT EXISTS marks (
        name TEXT PRIMARY KEY,
        start_at INTEGER NOT NULL,
        end_at INTEGER
      );

      CREATE TABLE IF NOT EXISTS meta (k TEXT PRIMARY KEY, v TEXT);
    ''');
    try {
      _db.execute('''
        CREATE VIRTUAL TABLE IF NOT EXISTS events_fts USING fts5(
          body, attrs, content='events', content_rowid='id'
        );
        CREATE TRIGGER IF NOT EXISTS events_ai AFTER INSERT ON events BEGIN
          INSERT INTO events_fts(rowid, body, attrs)
          VALUES (new.id, new.body, coalesce(new.attrs, ''));
        END;
        CREATE TRIGGER IF NOT EXISTS events_ad AFTER DELETE ON events BEGIN
          INSERT INTO events_fts(events_fts, rowid, body, attrs)
          VALUES ('delete', old.id, old.body, coalesce(old.attrs, ''));
        END;
      ''');
      _fts = true;
    } on SqliteException {
      // Build sem FTS5: busca cai pra LIKE.
      _fts = false;
    }
  }

  // ---- ids -------------------------------------------------------------------

  int _nextSeq(String k) {
    final row = _db.select('SELECT v FROM meta WHERE k = ?', [k]);
    final cur = row.isEmpty ? 0 : int.parse(row.first['v'] as String);
    final next = cur + 1;
    _db.execute(
      'INSERT INTO meta(k, v) VALUES (?, ?) ON CONFLICT(k) DO UPDATE SET v = excluded.v',
      [k, '$next'],
    );
    return next;
  }

  static String _b36(int n) => n.toRadixString(36);
  static String eventId(int rowid) => 'ev_${_b36(rowid)}';
  static int? eventRowid(String id) =>
      id.startsWith('ev_') ? int.tryParse(id.substring(3), radix: 36) : null;

  // ---- runs ------------------------------------------------------------------

  Map<String, Object?> openRun(Map<String, Object?> r) {
    final id = 'r_${_b36(_nextSeq('run_seq'))}';
    _db.execute(
      '''INSERT INTO runs(id, key, project, source, cwd, command, name, task_key,
         pane_id, pid, started_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)''',
      [
        id,
        r['key'],
        r['project'],
        r['source'],
        r['cwd'],
        r['command'],
        r['name'],
        r['task_key'],
        r['pane_id'],
        r['pid'],
        r['started_at'],
      ],
    );
    return run(id)!;
  }

  void closeRun(String id, {int? exitCode, required int endedAt}) {
    _db.execute(
      'UPDATE runs SET ended_at = ?, exit_code = ? WHERE id = ? AND ended_at IS NULL',
      [endedAt, exitCode, id],
    );
  }

  Map<String, Object?>? run(String id) {
    final rs = _db.select('SELECT * FROM runs WHERE id = ?', [id]);
    return rs.isEmpty ? null : _row(rs.first);
  }

  List<Map<String, Object?>> runs({
    String? project,
    String? key,
    bool onlyLive = false,
    int limit = 50,
  }) {
    final where = <String>[];
    final args = <Object?>[];
    if (project != null) {
      where.add('project = ?');
      args.add(project);
    }
    if (key != null) {
      where.add('key = ?');
      args.add(key);
    }
    if (onlyLive) where.add('ended_at IS NULL');
    final sql =
        'SELECT * FROM runs ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'} '
        'ORDER BY started_at DESC LIMIT ?';
    return [
      for (final r in _db.select(sql, [...args, limit])) _row(r),
    ];
  }

  // ---- eventos ---------------------------------------------------------------

  /// Insere em transação. Redige segredos e calcula fingerprint quando o
  /// evento tem erro e veio sem. Devolve os ids gerados (na ordem).
  List<String> append(List<Map<String, Object?>> events) {
    final ids = <String>[];
    _db.execute('BEGIN');
    try {
      final stmt = _db.prepare(
        '''INSERT INTO events(run_id, ts, stream, severity, body, attrs, error,
           fingerprint, trace_id, span_id, request_id, raw_offset, repeat)
           VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)''',
      );
      try {
        for (final e in events) {
          final attrsRaw = e['attrs'] as String?;
          String? attrs;
          if (attrsRaw != null && attrsRaw.isNotEmpty) {
            attrs = jsonEncode(
              redactAttrs(
                (jsonDecode(attrsRaw) as Map).cast<String, Object?>(),
              ),
            );
          }
          final errRaw = e['error'] as String?;
          String? fp = e['fingerprint'] as String?;
          String? err;
          if (errRaw != null && errRaw.isNotEmpty) {
            final em = (jsonDecode(errRaw) as Map).cast<String, Object?>();
            em['message'] = redactText(em['message']?.toString() ?? '');
            if (em['stack'] != null) {
              em['stack'] = redactText(em['stack'].toString());
            }
            err = jsonEncode(em);
            fp ??= fingerprintOf(TelemetryError.fromJson(em));
          }
          stmt.execute([
            e['run_id'],
            e['ts'],
            e['stream'],
            e['severity'],
            redactText(e['body'] as String? ?? ''),
            attrs,
            err,
            fp,
            e['trace_id'],
            e['span_id'],
            e['request_id'],
            e['raw_offset'],
            e['repeat'] ?? 1,
          ]);
          ids.add(eventId(_db.lastInsertRowId));
        }
      } finally {
        stmt.close();
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
    return ids;
  }

  Map<String, Object?>? event(String id) {
    final rowid = eventRowid(id);
    if (rowid == null) return null;
    final rs = _db.select('SELECT * FROM events WHERE id = ?', [rowid]);
    return rs.isEmpty ? null : _eventRow(rs.first);
  }

  List<Map<String, Object?>> events(Map<String, Object?> q) {
    final where = <String>[];
    final args = <Object?>[];
    _applyRunFilters(q, where, args);
    if (q['min_severity'] != null) {
      where.add('e.severity >= ?');
      args.add(q['min_severity']);
    }
    if (q['since'] != null) {
      where.add('e.ts >= ?');
      args.add(q['since']);
    }
    if (q['until'] != null) {
      where.add('e.ts <= ?');
      args.add(q['until']);
    }
    if (q['only_errors'] == true) where.add('e.error IS NOT NULL');
    final probe = q['probe'] as String?;
    if (probe != null) {
      if (probe == '*') {
        where.add("e.attrs LIKE '%\"probe\":%'");
      } else {
        where.add('e.attrs LIKE ?');
        args.add('%"probe":${jsonEncode(probe)}%');
      }
    }
    final text = q['text'] as String?;
    if (text != null && text.trim().isNotEmpty) {
      if (_fts) {
        where.add(
          'e.id IN (SELECT rowid FROM events_fts WHERE events_fts MATCH ?)',
        );
        args.add(_ftsQuery(text));
      } else {
        where.add('(e.body LIKE ? OR e.attrs LIKE ?)');
        args
          ..add('%$text%')
          ..add('%$text%');
      }
    }
    if (q['include_ignored'] != true) {
      where.add(
        "(e.fingerprint IS NULL OR e.fingerprint NOT IN (SELECT fingerprint FROM triage WHERE status = 'ignored'))",
      );
    }
    final sql =
        'SELECT e.* FROM events e JOIN runs r ON r.id = e.run_id '
        '${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'} '
        'ORDER BY e.id DESC LIMIT ?';
    final rows = _db.select(sql, [...args, q['limit'] ?? 100]);
    return [for (final r in rows.toList().reversed) _eventRow(r)];
  }

  List<Map<String, Object?>> context(
    String id, {
    int before = 10,
    int after = 5,
  }) {
    final rowid = eventRowid(id);
    if (rowid == null) return const [];
    final base = _db.select('SELECT run_id FROM events WHERE id = ?', [rowid]);
    if (base.isEmpty) return const [];
    final runId = base.first['run_id'];
    final prev = _db.select(
      'SELECT * FROM events WHERE run_id = ? AND id < ? ORDER BY id DESC LIMIT ?',
      [runId, rowid, before],
    );
    final next = _db.select(
      'SELECT * FROM events WHERE run_id = ? AND id >= ? ORDER BY id ASC LIMIT ?',
      [runId, rowid, after + 1],
    );
    return [
      for (final r in prev.toList().reversed) _eventRow(r),
      for (final r in next) _eventRow(r),
    ];
  }

  // ---- casos -----------------------------------------------------------------

  List<Map<String, Object?>> cases(Map<String, Object?> q) {
    final where = <String>['e.fingerprint IS NOT NULL'];
    final args = <Object?>[];
    _applyRunFilters(q, where, args);
    if (q['min_severity'] != null) {
      where.add('e.severity >= ?');
      args.add(q['min_severity']);
    }
    if (q['since'] != null) {
      where.add('e.ts >= ?');
      args.add(q['since']);
    }
    if (q['until'] != null) {
      where.add('e.ts <= ?');
      args.add(q['until']);
    }
    final text = q['text'] as String?;
    if (text != null && text.trim().isNotEmpty) {
      if (_fts) {
        where.add(
          'e.id IN (SELECT rowid FROM events_fts WHERE events_fts MATCH ?)',
        );
        args.add(_ftsQuery(text));
      } else {
        where.add('(e.body LIKE ? OR e.error LIKE ?)');
        args
          ..add('%$text%')
          ..add('%$text%');
      }
    }
    // Agregado por (fingerprint, key, run) — o resto é montado em Dart.
    final rows = _db.select('''
      SELECT e.fingerprint AS fp, r.key AS run_key, r.project AS project,
             r.id AS run_id, r.started_at AS run_started, r.ended_at AS run_ended,
             SUM(e.repeat) AS cnt, MIN(e.ts) AS first_at, MAX(e.ts) AS last_at,
             MAX(e.severity) AS sev, MAX(e.id) AS last_id
      FROM events e JOIN runs r ON r.id = e.run_id
      WHERE ${where.join(' AND ')}
      GROUP BY e.fingerprint, r.key, r.id
      ORDER BY last_at DESC
    ''', args);
    if (rows.isEmpty) return const [];

    // Triagem em memória (pequena).
    final triage = <String, Map<String, Object?>>{
      for (final t in _db.select('SELECT * FROM triage'))
        t['fingerprint'] as String: _row(t),
    };
    // Último run de cada chave (pra "new").
    final latestRun = <String, String>{
      for (final r in _db.select(
        'SELECT key, id FROM runs r1 WHERE started_at = (SELECT MAX(started_at) FROM runs r2 WHERE r2.key = r1.key)',
      ))
        r['key'] as String: r['id'] as String,
    };

    final grouped = <String, List<Row>>{};
    for (final r in rows) {
      grouped.putIfAbsent('${r['fp']}\u0000${r['run_key']}', () => []).add(r);
    }
    final includeIgnored = q['include_ignored'] == true;
    final includeResolved = q['include_resolved'] == true;
    final onlyNew = q['only_new'] == true;
    final out = <Map<String, Object?>>[];
    for (final entry in grouped.entries) {
      final list = entry.value
        ..sort(
          (a, b) =>
              (b['run_started'] as int).compareTo(a['run_started'] as int),
        );
      final fp = list.first['fp'] as String;
      final key = list.first['run_key'] as String;
      final lastAt = list
          .map((r) => r['last_at'] as int)
          .reduce((a, b) => a > b ? a : b);
      final firstAt = list
          .map((r) => r['first_at'] as int)
          .reduce((a, b) => a < b ? a : b);
      final count = list.fold<int>(0, (s, r) => s + (r['cnt'] as int));
      final sev = list
          .map((r) => r['sev'] as int)
          .reduce((a, b) => a > b ? a : b);
      final lastId = list
          .map((r) => r['last_id'] as int)
          .reduce((a, b) => a > b ? a : b);

      final t = triage[fp];
      var status = t == null ? 'open' : t['status'] as String;
      var regression = false;
      if (status == 'resolved' && lastAt > (t!['at'] as int)) {
        status = 'open';
        regression = true;
      }
      if (status == 'ignored' && !includeIgnored) continue;
      if (status == 'resolved' && !includeResolved) continue;

      // new = só aparece no run mais recente da chave
      final runIds = list.map((r) => r['run_id'] as String).toSet();
      final isNew = runIds.length == 1 && runIds.single == latestRun[key];
      if (onlyNew && !(isNew || regression)) continue;

      final last = _db.select('SELECT error FROM events WHERE id = ?', [
        lastId,
      ]).first;
      final em = (jsonDecode(last['error'] as String) as Map)
          .cast<String, Object?>();
      final err = TelemetryError.fromJson(em);
      out.add({
        'fingerprint': fp,
        'run_key': key,
        'project': list.first['project'],
        'severity': sev,
        'type': err.type,
        'message': err.message,
        'location': err.projectFrame?.location,
        'count': count,
        'first_at': firstAt,
        'last_at': lastAt,
        'status': status,
        'is_new': isNew,
        'is_regression': regression,
        'last_event_id': eventId(lastId),
        'triage': t == null
            ? null
            : {
                'status': t['status'],
                'by': t['actor'],
                'at': t['at'],
                'reason': t['reason'],
              },
        'runs': [
          for (final r in list)
            {
              'run_id': r['run_id'],
              'count': r['cnt'],
              'first_at': r['first_at'],
              'last_at': r['last_at'],
              'live': r['run_ended'] == null,
            },
        ],
      });
    }
    out.sort((a, b) => (b['last_at'] as int).compareTo(a['last_at'] as int));
    final limit = (q['limit'] as int?) ?? 100;
    return out.length > limit ? out.sublist(0, limit) : out;
  }

  /// `e_3f2a` (prefixo hex) ou fingerprint completo.
  Map<String, Object?>? caseById(String idOrFp) {
    var prefix = idOrFp.startsWith('e_') ? idOrFp.substring(2) : idOrFp;
    prefix = prefix.toLowerCase();
    final fps = _db.select(
      'SELECT DISTINCT fingerprint FROM events WHERE fingerprint LIKE ?',
      ['$prefix%'],
    );
    if (fps.length != 1) return null;
    final fp = fps.first['fingerprint'] as String;
    final all = cases({
      'include_ignored': true,
      'include_resolved': true,
      'limit': 1000,
    });
    for (final c in all) {
      if (c['fingerprint'] == fp) return c;
    }
    return null;
  }

  void triage(
    String fingerprint,
    String status, {
    required String actor,
    String? reason,
    required int at,
  }) {
    if (status == TelemetryTriageStatus.open.name) {
      _db.execute('DELETE FROM triage WHERE fingerprint = ?', [fingerprint]);
      return;
    }
    _db.execute(
      '''INSERT INTO triage(fingerprint, status, actor, at, reason) VALUES (?,?,?,?,?)
         ON CONFLICT(fingerprint) DO UPDATE SET status = excluded.status,
         actor = excluded.actor, at = excluded.at, reason = excluded.reason''',
      [fingerprint, status, actor, at, reason],
    );
  }

  // ---- marcas ----------------------------------------------------------------

  void markStart(String name, int at) => _db.execute(
    'INSERT INTO marks(name, start_at, end_at) VALUES (?,?,NULL) '
    'ON CONFLICT(name) DO UPDATE SET start_at = excluded.start_at, end_at = NULL',
    [name, at],
  );

  void markEnd(String name, int at) =>
      _db.execute('UPDATE marks SET end_at = ? WHERE name = ?', [at, name]);

  Map<String, Object?>? mark(String name) {
    final rs = _db.select('SELECT * FROM marks WHERE name = ?', [name]);
    return rs.isEmpty ? null : _row(rs.first);
  }

  // ---- manutenção ------------------------------------------------------------

  void clear({String? fingerprint, String? runId, String? project}) {
    if (fingerprint != null) {
      _db.execute('DELETE FROM events WHERE fingerprint = ?', [fingerprint]);
    }
    if (runId != null) _db.execute('DELETE FROM runs WHERE id = ?', [runId]);
    if (project != null) {
      _db.execute('DELETE FROM runs WHERE project = ?', [project]);
    }
    if (fingerprint == null && runId == null && project == null) {
      _db.execute('DELETE FROM runs');
    }
  }

  int sizeInBytes() {
    final r = _db.select(
      'SELECT page_count * page_size AS s FROM pragma_page_count(), pragma_page_size()',
    );
    return (r.first['s'] as int?) ?? 0;
  }

  /// Ring buffer: apaga runs encerrados mais antigos que [maxAgeMs] e, se
  /// ainda passar de [maxBytes], os mais antigos até caber. Devolve bytes
  /// liberados (aproximado).
  int vacuum({required int maxBytes, required int maxAgeMs, required int now}) {
    final before = sizeInBytes();
    _db.execute(
      'DELETE FROM runs WHERE ended_at IS NOT NULL AND started_at < ?',
      [now - maxAgeMs],
    );
    var guard = 0;
    while (sizeInBytes() > maxBytes && guard++ < 10000) {
      final oldest = _db.select(
        'SELECT id FROM runs WHERE ended_at IS NOT NULL ORDER BY started_at ASC LIMIT 1',
      );
      if (oldest.isEmpty) break;
      _db.execute('DELETE FROM runs WHERE id = ?', [oldest.first['id']]);
      _db.execute('PRAGMA incremental_vacuum');
    }
    _db.execute('PRAGMA incremental_vacuum');
    final after = sizeInBytes();
    return before - after;
  }

  // ---- helpers ---------------------------------------------------------------

  void _applyRunFilters(
    Map<String, Object?> q,
    List<String> where,
    List<Object?> args,
  ) {
    void eq(String col, String k) {
      if (q[k] != null) {
        where.add('$col = ?');
        args.add(q[k]);
      }
    }

    eq('r.project', 'project');
    eq('r.id', 'run_id');
    eq('r.key', 'run_key');
    eq('r.task_key', 'task_key');
    eq('r.pane_id', 'pane_id');
  }

  static String _ftsQuery(String text) {
    // Cada termo vira prefixo; aspas escapadas. Sem operadores do usuário.
    final terms = text.trim().split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
    return terms.map((t) => '"${t.replaceAll('"', '""')}"*').join(' ');
  }

  static Map<String, Object?> _row(Row r) => Map<String, Object?>.from(r);

  static Map<String, Object?> _eventRow(Row r) {
    final m = _row(r);
    m['id'] = eventId(r['id'] as int);
    return m;
  }
}
