// Verbos `telemetry-*` da CLI interna (plano 66, passo 5). Fala com o store
// do workspace da aba emissora; saída pensada pro agente: resumo antes de
// detalhe, ids estáveis, teto de tamanho com `truncated` + dica do próximo
// comando. Também recebe o wrapper (`telemetry-open/ingest/close`, passo 4).
//
// Saída da CLI é em inglês por decisão (ver CLAUDE.md, "O que não se traduz").

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Process;

import 'package:cockpit/app/cockpit/domain/contracts/telemetry_ingest.dart';
import 'package:cockpit/app/cockpit/domain/contracts/telemetry_store.dart';
import 'package:cockpit/app/cockpit/domain/contracts/terminal_status_server.dart';
import 'package:cockpit/app/cockpit/domain/entities/project.dart';
import 'package:cockpit/app/cockpit/domain/entities/telemetry_case.dart';
import 'package:cockpit/app/cockpit/domain/entities/telemetry_event.dart';
import 'package:cockpit/app/cockpit/domain/entities/telemetry_run.dart';

/// Teto de bytes de uma resposta (o agente nunca recebe 2000 linhas).
const kTelemetryReplyCap = 16 * 1024;

class TelemetryCliHandler {
  TelemetryCliHandler(
    this._stores,
    this._ingest, {
    required this.lastEditAt,
    required this.rootsOf,
  });

  final TelemetryStoreProvider _stores;
  final TelemetryIngest _ingest;

  /// Último save do editor no projeto (`--since-edit`). `null` = nunca.
  final DateTime? Function(String projectId) lastEditAt;

  /// Roots do workspace (pra `probes` rodar o `git diff`).
  final List<String> Function(String projectId) rootsOf;

  static bool handles(String cmd) => cmd.startsWith('telemetry-');

  /// [project] é `null` só no modo `--app` (store do próprio Cockpit, plano
  /// 68): verbos que precisam de workspace (open/close/probes) falham.
  Future<CockpitCommandResult> handle(
    CockpitCommand c,
    Project? project,
    String root,
  ) async {
    final a = c.args;
    if (project == null &&
        const {
          'telemetry-open',
          'telemetry-close',
          'telemetry-probes',
        }.contains(c.cmd)) {
      return const CockpitCommandResult.fail(
        'this verb needs a workspace (drop --app)',
      );
    }
    // ---- wrapper (passo 4): não precisa de store, o ingest resolve ----
    switch (c.cmd) {
      case 'telemetry-open':
        final s = await _ingest.openWrapperRun(
          cwd: _s(a['cwd']) ?? root,
          command: _s(a['command']) ?? '',
          name: _s(a['name']),
          paneId: c.tabId,
          pid: _i(a['pid']),
        );
        if (s == null) {
          return const CockpitCommandResult.fail(
            'no_workspace: cwd is not inside an open workspace',
          );
        }
        return CockpitCommandResult.ok({
          'run': s.runId,
          'env': s.childEnvironment,
        });
      case 'telemetry-ingest':
        final s = _ingest.session(_s(a['run']) ?? '');
        if (s == null) {
          return const CockpitCommandResult.fail(
            'no_run: unknown or closed run',
          );
        }
        final stream = _s(a['stream']) == 'err'
            ? TelemetryStream.err
            : TelemetryStream.out;
        final lines = a['lines'];
        if (lines is List) {
          s.add(
            lines.map((l) => l.toString()).join('\n') +
                (lines.isEmpty ? '' : '\n'),
            stream: stream,
          );
        } else if (a['data'] is String) {
          s.add(
            utf8.decode(
              base64Decode(a['data'] as String),
              allowMalformed: true,
            ),
            stream: stream,
          );
        }
        return const CockpitCommandResult.ok();
      case 'telemetry-close':
        final s = _ingest.session(_s(a['run']) ?? '');
        if (s == null) {
          return const CockpitCommandResult.fail(
            'no_run: unknown or closed run',
          );
        }
        await s.close(exitCode: _i(a['exit_code']));
        final store = await _stores.forWorkspace(project!.id);
        final cases = await store.cases(
          TelemetryQuery(runId: s.runId, limit: 500),
        );
        final errors = cases
            .where((x) => x.severity.index >= TelemetrySeverity.error.index)
            .length;
        final warns = cases.length - errors;
        return CockpitCommandResult.ok({
          'run': s.runId,
          'errors': errors,
          'warnings': warns,
        });
    }

    final store = await _stores.forWorkspace(
      project?.id ?? kTelemetryAppWorkspaceId,
    );
    switch (c.cmd) {
      // `cockpit telemetry perf` (plano 68): P50/P95/máx por métrica do run
      // do app (o mais recente, ou `--run`). Só faz sentido com `--app`, mas
      // funciona em qualquer store que tenha eventos `metric`.
      case 'telemetry-perf':
        return _perf(store, a);
      case 'telemetry-errors':
        final q = await _query(
          a,
          project,
          store,
          minSeverity: _sev(a['level']) ?? TelemetrySeverity.error,
          limit: 50,
        );
        final cases = await store.cases(q);
        return _capped('cases', [
          for (final x in cases) _caseSummary(x),
        ], hint: 'cockpit telemetry show <id>');
      case 'telemetry-logs':
      case 'telemetry-events':
        final q = await _query(
          a,
          project,
          store,
          minSeverity:
              _sev(a['level']) ??
              (c.cmd == 'telemetry-logs' ? TelemetrySeverity.debug : null),
          limit: 100,
        );
        final evs = await store.events(q);
        return _capped('events', [
          for (final e in evs) _eventSummary(e),
        ], hint: 'narrow with --since/--run/--level');
      case 'telemetry-runs':
        final runs = await store.runs(
          project: _s(a['project']),
          key: _s(a['key']),
          onlyLive: a['live'] == true || _s(a['live']) == 'true',
          limit: _i(a['limit']) ?? 20,
        );
        return CockpitCommandResult.ok({
          'runs': [for (final r in runs) _runSummary(r)],
        });
      case 'telemetry-show':
        return _show(store, _s(a['id']) ?? '', context: _i(a['context']) ?? 12);
      case 'telemetry-wait':
        return _wait(store, a);
      case 'telemetry-mark':
        final name = _s(a['name']) ?? '';
        if (name.isEmpty) {
          return const CockpitCommandResult.fail('missing mark name');
        }
        if (_s(a['action']) == 'end') {
          await store.markEnd(name);
        } else {
          await store.markStart(name);
        }
        final m = await store.mark(name);
        return CockpitCommandResult.ok({
          'mark': name,
          'start': m?.$1.toIso8601String(),
          'end': m?.$2?.toIso8601String(),
        });
      case 'telemetry-triage':
        final cs = await store.caseById(_s(a['id']) ?? '');
        if (cs == null) {
          return const CockpitCommandResult.fail(
            'not_found: no case with that id',
          );
        }
        final status = switch (_s(a['status'])) {
          'resolve' || 'resolved' => TelemetryTriageStatus.resolved,
          'ignore' || 'ignored' => TelemetryTriageStatus.ignored,
          _ => TelemetryTriageStatus.open,
        };
        await store.triage(
          cs.fingerprint,
          status,
          by: TelemetryTriageActor.agent,
          reason: _s(a['reason']),
        );
        return CockpitCommandResult.ok({
          'id': cs.shortId,
          'status': status.name,
        });
      case 'telemetry-clear':
        final id = _s(a['case']);
        String? fp;
        if (id != null) {
          final cs = await store.caseById(id);
          if (cs == null) {
            return const CockpitCommandResult.fail(
              'not_found: no case with that id',
            );
          }
          fp = cs.fingerprint;
        }
        await store.clear(
          fingerprint: fp,
          runId: _s(a['run']),
          project: _s(a['project']),
        );
        return const CockpitCommandResult.ok({'cleared': true});
      case 'telemetry-probes':
        return _probes(project!, _s(a['project']));
      case 'telemetry-replay':
        DateTime? since;
        DateTime? until;
        final mark = _s(a['mark']);
        if (mark != null) {
          final m = await store.mark(mark);
          if (m == null) {
            return const CockpitCommandResult.fail('not_found: no such mark');
          }
          since = m.$1;
          until = m.$2;
        } else if (_s(a['since']) != null) {
          since = _parseSince(_s(a['since'])!);
        }
        if (since == null) {
          return const CockpitCommandResult.fail(
            'missing --mark <name> or --since <10m>',
          );
        }
        final n = await _ingest.replay(
          workspaceId: project?.id ?? kTelemetryAppWorkspaceId,
          since: since,
          until: until,
        );
        if (n == null) {
          return const CockpitCommandResult.fail(
            'no_proxy: add "proxy" to .cockpit/telemetry.json first',
          );
        }
        return CockpitCommandResult.ok({'replayed': n});
    }
    return CockpitCommandResult.fail('unknown telemetry command ${c.cmd}');
  }

  // ---- consultas -------------------------------------------------------------

  Future<TelemetryQuery> _query(
    Map<String, dynamic> a,
    Project? project,
    TelemetryStore store, {
    TelemetrySeverity? minSeverity,
    required int limit,
  }) async {
    DateTime? since;
    DateTime? until;
    String? runId = _s(a['run']);
    final sinceRaw = _s(a['since']);
    if (sinceRaw != null) since = _parseSince(sinceRaw);
    if (a['since_edit'] == true) {
      since = project == null
          ? DateTime.now()
          : (lastEditAt(project.id) ?? DateTime.now());
    }
    if (a['since_run'] == true) {
      final runs = await store.runs(
        project: _s(a['project']),
        key: _s(a['key']),
        limit: 1,
      );
      if (runs.isNotEmpty) since = runs.first.startedAt;
    }
    final before = _s(a['before']);
    if (before != null) {
      final ev = await store.event(before);
      final cs = ev == null ? await store.caseById(before) : null;
      final anchor =
          ev ??
          (cs?.lastEventId == null
              ? null
              : await store.event(cs!.lastEventId!));
      if (anchor != null) {
        final win =
            _parseDuration(_s(a['window']) ?? '5s') ??
            const Duration(seconds: 5);
        until = anchor.ts;
        since = anchor.ts.subtract(win);
        runId ??= anchor.runId;
      }
    }
    final mark = _s(a['mark']);
    if (mark != null) {
      final m = await store.mark(mark);
      if (m != null) {
        since = m.$1;
        until = m.$2;
      }
    }
    return TelemetryQuery(
      project: _s(a['project']),
      runId: runId,
      runKey: _s(a['key']),
      taskKey: _s(a['task']),
      paneId: _s(a['tab']),
      minSeverity: minSeverity,
      since: since,
      until: until,
      text: _s(a['text']),
      probe: _s(a['probe']),
      onlyNew: a['new'] == true,
      includeIgnored: a['include_ignored'] == true,
      includeResolved: a['include_resolved'] == true,
      limit: _i(a['limit']) ?? limit,
    );
  }

  Future<CockpitCommandResult> _show(
    TelemetryStore store,
    String id, {
    required int context,
  }) async {
    if (id.isEmpty) return const CockpitCommandResult.fail('missing id');
    if (id.startsWith('r_')) {
      final r = await store.run(id);
      if (r == null) {
        return const CockpitCommandResult.fail(
          'not_found: no run with that id',
        );
      }
      final cases = await store.cases(
        TelemetryQuery(
          runId: id,
          minSeverity: TelemetrySeverity.warn,
          limit: 50,
        ),
      );
      return CockpitCommandResult.ok({
        'run': _runSummary(r),
        'cases': [for (final x in cases) _caseSummary(x)],
      });
    }
    if (id.startsWith('ev_')) {
      final e = await store.event(id);
      if (e == null) {
        return const CockpitCommandResult.fail(
          'not_found: no event with that id',
        );
      }
      final ctx = await store.context(id, before: context, after: 4);
      return CockpitCommandResult.ok({
        'event': _eventDetail(e),
        'context': [for (final x in ctx) _eventSummary(x)],
      });
    }
    final cs = await store.caseById(id);
    if (cs == null) {
      return const CockpitCommandResult.fail(
        'not_found: no case with that id (try `cockpit telemetry errors`)',
      );
    }
    final last = cs.lastEventId == null
        ? null
        : await store.event(cs.lastEventId!);
    final ctx = last == null
        ? const <TelemetryEvent>[]
        : await store.context(last.id!, before: context, after: 3);
    // Log JSON mais próximo antes do erro no mesmo run (o "correlacionado").
    TelemetryEvent? correlated;
    if (last != null) {
      for (final x in ctx.reversed) {
        if (x.id == last.id) continue;
        if (x.ts.isAfter(last.ts)) continue;
        if (x.attrs.isNotEmpty && x.error == null) {
          correlated = x;
          break;
        }
      }
    }
    return CockpitCommandResult.ok({
      'case': _caseSummary(cs),
      'triage': cs.triage == null
          ? null
          : {
              'status': cs.triage!.status.name,
              'by': cs.triage!.by.name,
              'at': cs.triage!.at.toIso8601String(),
              'reason': cs.triage!.reason,
            },
      'runs': [
        for (final r in cs.runs)
          {
            'run': r.runId,
            'count': r.count,
            'first': r.firstAt.toIso8601String(),
            'last': r.lastAt.toIso8601String(),
            'live': r.live,
          },
      ],
      'last': last == null ? null : _eventDetail(last),
      'correlated': correlated == null ? null : _eventSummary(correlated),
      'context': [for (final x in ctx) _eventSummary(x)],
    });
  }

  /// `--fingerprint <id> --absent <s>`: ok se não reapareceu em `absent`
  /// segundos E houve atividade observável (senão `inconclusive`).
  /// `--any-new`: hit assim que surgir caso novo/regressão.
  /// Agrega os eventos `metric` de um run: por métrica e campo numérico,
  /// `count`, `p50`, `p95`, `max` e `last`. Quem grava é o
  /// `PerformanceDiagnostics` via `AppTelemetryBridge.metric`.
  Future<CockpitCommandResult> _perf(
    TelemetryStore store,
    Map<String, dynamic> a,
  ) async {
    var runId = _s(a['run']);
    if (runId == null) {
      final runs = await store.runs(limit: 1);
      if (runs.isEmpty) {
        return const CockpitCommandResult.fail(
          'no runs in this store (start the app with COCKPIT_PERF=1)',
        );
      }
      runId = runs.first.id;
    }
    final wanted = _s(a['metric']);
    final events = await store.events(
      TelemetryQuery(runId: runId, limit: 5000, includeIgnored: true),
    );
    // metric → field → amostras
    final samples = <String, Map<String, List<num>>>{};
    for (final e in events) {
      final metric = e.attrs['metric']?.toString();
      if (metric == null || (wanted != null && metric != wanted)) continue;
      final fields = samples.putIfAbsent(metric, () => {});
      for (final entry in e.attrs.entries) {
        final v = entry.value;
        if (entry.key == 'metric' || v is! num) continue;
        fields.putIfAbsent(entry.key, () => []).add(v);
      }
    }
    num pct(List<num> sorted, double q) =>
        sorted[((sorted.length - 1) * q).round()];
    final out = <String, Object?>{};
    for (final m in samples.entries) {
      final fields = <String, Object?>{};
      for (final f in m.value.entries) {
        final sorted = List<num>.of(f.value)..sort();
        fields[f.key] = {
          'count': sorted.length,
          'p50': pct(sorted, 0.5),
          'p95': pct(sorted, 0.95),
          'max': sorted.last,
          'last': f.value.last,
        };
      }
      out[m.key] = fields;
    }
    return CockpitCommandResult.ok({
      'run': runId,
      'metrics': out,
      if (out.isEmpty)
        'hint': 'no metric events; run the app with COCKPIT_PERF=1',
    });
  }

  Future<CockpitCommandResult> _wait(
    TelemetryStore store,
    Map<String, dynamic> a,
  ) async {
    final timeout =
        _parseDuration(_s(a['timeout']) ?? '60s') ??
        const Duration(seconds: 60);
    final absent =
        _parseDuration(_s(a['absent']) ?? '30s') ?? const Duration(seconds: 30);
    final fpId = _s(a['fingerprint']);
    final route = _s(a['route']);
    final anyNew = a['any_new'] == true;
    final start = DateTime.now();
    final deadline = start.add(
      timeout > const Duration(minutes: 10)
          ? const Duration(minutes: 10)
          : timeout,
    );
    String? fp;
    if (fpId != null) {
      final cs = await store.caseById(fpId);
      if (cs == null) {
        return const CockpitCommandResult.fail(
          'not_found: no case with that id',
        );
      }
      fp = cs.fingerprint;
    }
    final baseline = anyNew
        ? (await store.cases(
            const TelemetryQuery(onlyNew: true, limit: 500),
          )).map((c) => c.fingerprint).toSet()
        : <String>{};
    DateTime? quietSince;
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 1));
      final recent = await store.events(
        TelemetryQuery(since: start, limit: 500, includeIgnored: true),
      );
      if (fp != null) {
        final hit = recent.where((e) => e.fingerprint == fp).toList();
        if (hit.isNotEmpty) {
          return CockpitCommandResult.ok({
            'result': 'hit',
            'count': hit.length,
            'elapsed_s': DateTime.now().difference(start).inSeconds,
          });
        }
        if (recent.isNotEmpty) {
          quietSince ??= DateTime.now();
          if (DateTime.now().difference(quietSince) >= absent) {
            return CockpitCommandResult.ok({
              'result': 'ok',
              'observed_events': recent.length,
              'elapsed_s': DateTime.now().difference(start).inSeconds,
            });
          }
        }
      }
      if (route != null) {
        final hit = recent.where(
          (e) =>
              e.stream == TelemetryStream.proxy &&
              '${e.attrs['method']} ${e.attrs['route']}'.contains(route),
        );
        if (hit.isNotEmpty) {
          final e = hit.last;
          return CockpitCommandResult.ok({
            'result': 'hit',
            'status': e.attrs['status'],
            'duration_ms': e.attrs['duration_ms'],
            'request_id': e.requestId,
            'event': e.id,
          });
        }
      }
      if (anyNew) {
        final now = await store.cases(
          const TelemetryQuery(onlyNew: true, limit: 500),
        );
        final fresh = now
            .where((c) => !baseline.contains(c.fingerprint))
            .toList();
        if (fresh.isNotEmpty) {
          return CockpitCommandResult.ok({
            'result': 'hit',
            'cases': [for (final x in fresh) _caseSummary(x)],
          });
        }
      }
    }
    return CockpitCommandResult.ok({
      'result': fp != null && quietSince == null ? 'inconclusive' : 'timeout',
      'elapsed_s': DateTime.now().difference(start).inSeconds,
    });
  }

  /// Linhas ADICIONADAS no working tree que carregam uma sonda (`"probe"`).
  Future<CockpitCommandResult> _probes(
    Project project,
    String? onlyProject,
  ) async {
    final roots = rootsOf(project.id);
    final out = <Map<String, Object?>>[];
    for (final root in roots) {
      if (onlyProject != null && !root.endsWith(onlyProject)) continue;
      try {
        final r = await Process.run('git', [
          'diff',
          'HEAD',
          '--unified=0',
          '--no-color',
        ], workingDirectory: root);
        if (r.exitCode != 0) continue;
        String? file;
        var line = 0;
        for (final l in const LineSplitter().convert(r.stdout as String)) {
          if (l.startsWith('+++ b/')) {
            file = l.substring(6);
            continue;
          }
          final h = RegExp(r'^@@ -\d+(?:,\d+)? \+(\d+)').firstMatch(l);
          if (h != null) {
            line = int.parse(h.group(1)!);
            continue;
          }
          if (l.startsWith('+') && !l.startsWith('+++')) {
            if (RegExp('["\']probe["\']\\s*:').hasMatch(l)) {
              out.add({
                'file': file,
                'line': line,
                'text': l.substring(1).trim(),
                'root': root,
              });
            }
            line++;
          } else if (!l.startsWith('-')) {
            line++;
          }
        }
      } on Exception {
        // git ausente ou root sem repo: sem sondas a listar aqui.
      }
    }
    return CockpitCommandResult.ok({
      'probes': out,
      'hint': out.isEmpty ? null : 'remove before committing',
    });
  }

  // ---- formatação ------------------------------------------------------------

  Map<String, Object?> _caseSummary(TelemetryCase c) => {
    'id': c.shortId,
    'level': c.severity.name,
    'type': c.type,
    'message': _clip(c.message, 300),
    'location': c.location,
    'count': c.count,
    'project': c.project,
    'key': c.runKey,
    'status': c.status.name,
    if (c.isNew) 'new': true,
    if (c.isRegression) 'regression': true,
    'first': c.firstAt.toIso8601String(),
    'last': c.lastAt.toIso8601String(),
    'runs': c.runs.length,
    'last_event': c.lastEventId,
  };

  Map<String, Object?> _eventSummary(TelemetryEvent e) => {
    'id': e.id,
    'ts': e.ts.toIso8601String(),
    'run': e.runId,
    'level': e.severity.name,
    'body': _clip(e.body, 400),
    if (e.attrs.isNotEmpty) 'attrs': e.attrs,
    if (e.error != null)
      'error': {
        'type': e.error!.type,
        'location': e.error!.projectFrame?.location,
      },
    if (e.repeat > 1) 'repeat': e.repeat,
  };

  Map<String, Object?> _eventDetail(TelemetryEvent e) => {
    ..._eventSummary(e),
    'stream': e.stream.name,
    'line': e.rawLineOffset,
    if (e.traceId != null) 'trace_id': e.traceId,
    if (e.requestId != null) 'request_id': e.requestId,
    if (e.error != null)
      'error': {
        'type': e.error!.type,
        'message': e.error!.message,
        'location': e.error!.projectFrame?.location,
        'frames': [
          for (final f in e.error!.frames)
            {'at': f.raw.trim(), if (f.inProject) 'project': true},
        ],
      },
  };

  Map<String, Object?> _runSummary(TelemetryRun r) => {
    'id': r.id,
    'key': r.key,
    'project': r.project,
    'name': r.name,
    'command': r.command,
    'source': r.source.name,
    'started': r.startedAt.toIso8601String(),
    'ended': r.endedAt?.toIso8601String(),
    'exit_code': r.exitCode,
    'live': r.isLive,
  };

  /// Corta a lista até caber no teto; sinaliza `truncated` e a dica.
  CockpitCommandResult _capped(
    String key,
    List<Map<String, Object?>> items, {
    required String hint,
  }) {
    var list = items;
    var truncated = false;
    while (list.isNotEmpty && jsonEncode(list).length > kTelemetryReplyCap) {
      list = list.sublist(
        0,
        (list.length * 0.7).floor().clamp(1, list.length - 1),
      );
      truncated = true;
    }
    return CockpitCommandResult.ok({
      key: list,
      'total': items.length,
      if (truncated) 'truncated': true,
      if (truncated) 'hint': hint,
    });
  }

  static String _clip(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}…';
  static String? _s(Object? v) =>
      v == null || v.toString().isEmpty ? null : v.toString();
  static int? _i(Object? v) =>
      v == null ? null : (v is int ? v : int.tryParse(v.toString()));
  static TelemetrySeverity? _sev(Object? v) =>
      v == null ? null : TelemetrySeverity.parse(v);

  static DateTime? _parseSince(String raw) {
    final d = _parseDuration(raw);
    if (d != null) return DateTime.now().subtract(d);
    return DateTime.tryParse(raw);
  }

  static Duration? _parseDuration(String raw) {
    final m = RegExp(r'^(\d+)\s*(ms|s|m|h|d)?$').firstMatch(raw.trim());
    if (m == null) return null;
    final n = int.parse(m.group(1)!);
    return switch (m.group(2)) {
      'ms' => Duration(milliseconds: n),
      'm' => Duration(minutes: n),
      'h' => Duration(hours: n),
      'd' => Duration(days: n),
      _ => Duration(seconds: n),
    };
  }
}
