// ViewModel page-scoped da Telemetry (plano 66, passo 6): alimenta o painel
// direito (árvore projeto → run → casos, chips, busca) e a aba de caso
// (detalhe, contexto, blame). Lê o store do workspace ativo; não escreve
// eventos (isso é do ingest). Poll leve enquanto o painel está visível: a
// base é atualizada por outro isolate e não há event bus.

import 'dart:async';
import 'dart:io' show Directory, File, Process;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:cockpit/app/cockpit/domain/contracts/telemetry_store.dart';
import 'package:cockpit/app/cockpit/domain/entities/telemetry_case.dart';
import 'package:cockpit/app/cockpit/domain/entities/telemetry_event.dart';
import 'package:cockpit/app/cockpit/domain/entities/telemetry_run.dart';

/// Chip de filtro do painel.
enum TelemetryFilter { open, fresh, resolved, ignored }

/// Blame do `arquivo:linha` do caso (working tree do repo).
class TelemetryBlame {
  const TelemetryBlame({required this.uncommitted, this.sha, this.at});
  final bool uncommitted;
  final String? sha;
  final DateTime? at;
}

/// Tudo que a aba de caso mostra.
class TelemetryCaseDetail {
  const TelemetryCaseDetail({
    required this.kase,
    required this.last,
    required this.context,
    required this.correlated,
    required this.runs,
    required this.blame,
  });
  final TelemetryCase kase;
  final TelemetryEvent? last;
  final List<TelemetryEvent> context;
  final TelemetryEvent? correlated;
  final Map<String, TelemetryRun> runs;
  final TelemetryBlame? blame;
}

class TelemetryViewModel extends ChangeNotifier {
  TelemetryViewModel(this._stores);

  final TelemetryStoreProvider _stores;

  String? _workspaceId;
  List<String> _roots = const [];
  TelemetryStore? _store;

  TelemetryFilter filter = TelemetryFilter.open;
  bool showWarnings = true;
  String query = '';

  List<TelemetryCase> cases = const [];
  final runsById = <String, TelemetryRun>{};
  int liveRuns = 0;
  int openCount = 0;
  int newCount = 0;
  int resolvedCount = 0;
  int ignoredCount = 0;
  int warningCount = 0;
  int sizeBytes = 0;
  bool loading = false;

  Timer? _poll;
  int _visible = 0;
  int _gen = 0;

  String? get workspaceId => _workspaceId;
  List<String> get roots => _roots;
  bool get hasWorkspace => _workspaceId != null;

  /// Projetos com pelo menos um caso na lista atual (ordem estável).
  List<String> get projects {
    final seen = <String>{};
    for (final c in cases) {
      seen.add(c.project);
    }
    final l = seen.toList()..sort();
    return l;
  }

  /// `true` quando o workspace tem uma root só: a árvore achata o projeto.
  bool get singleRoot => _roots.length <= 1;

  // ---- ciclo de vida ---------------------------------------------------------

  void setWorkspace(String? id, List<String> roots) {
    final changed = id != _workspaceId || !listEquals(roots, _roots);
    _roots = List.unmodifiable(roots);
    if (!changed) return;
    _workspaceId = id;
    _store = null;
    cases = const [];
    runsById.clear();
    // Chamado do `initState`/`didUpdateWidget` do painel, ou seja, durante o
    // build: notificar agora é markNeedsBuild no meio do frame (caso e_38b0
    // da Telemetria). O `refresh` notifica de novo quando os dados chegam.
    scheduleMicrotask(notifyListeners);
    unawaited(refresh());
  }

  /// Painel/aba montado(a): liga o poll. Contagem porque painel e abas de caso
  /// podem coexistir.
  void attach() {
    _visible++;
    _poll ??= Timer.periodic(const Duration(seconds: 2), (_) => refresh());
    unawaited(refresh());
  }

  void detach() {
    _visible = (_visible - 1).clamp(0, 1 << 30);
    if (_visible == 0) {
      _poll?.cancel();
      _poll = null;
    }
  }

  Future<TelemetryStore?> _s() async {
    final id = _workspaceId;
    if (id == null) return null;
    return _store ??= await _stores.forWorkspace(id);
  }

  // ---- filtros ---------------------------------------------------------------

  void setFilter(TelemetryFilter f) {
    if (f == filter) return;
    filter = f;
    notifyListeners();
    unawaited(refresh());
  }

  void toggleWarnings() {
    showWarnings = !showWarnings;
    notifyListeners();
    unawaited(refresh());
  }

  void setQuery(String q) {
    if (q == query) return;
    query = q;
    unawaited(refresh());
  }

  TelemetryQuery _baseQuery({int limit = 300}) => TelemetryQuery(
    text: query.trim().isEmpty ? null : query.trim(),
    minSeverity: showWarnings
        ? TelemetrySeverity.warn
        : TelemetrySeverity.error,
    limit: limit,
  );

  // ---- carga -----------------------------------------------------------------

  Future<void> refresh() async {
    final store = await _s();
    if (store == null) return;
    final gen = ++_gen;
    loading = true;
    try {
      final base = _baseQuery();
      final all = await store.cases(
        TelemetryQuery(
          text: base.text,
          minSeverity: TelemetrySeverity.warn,
          includeIgnored: true,
          includeResolved: true,
          limit: 500,
        ),
      );
      if (gen != _gen) return;
      openCount = 0;
      newCount = 0;
      resolvedCount = 0;
      ignoredCount = 0;
      warningCount = 0;
      for (final c in all) {
        switch (c.status) {
          case TelemetryTriageStatus.open:
            openCount++;
            if (c.isNew || c.isRegression) newCount++;
            if (c.severity == TelemetrySeverity.warn) warningCount++;
          case TelemetryTriageStatus.resolved:
            resolvedCount++;
          case TelemetryTriageStatus.ignored:
            ignoredCount++;
        }
      }
      final minSev = showWarnings
          ? TelemetrySeverity.warn
          : TelemetrySeverity.error;
      cases = all.where((c) {
        if (c.severity.index < minSev.index) return false;
        return switch (filter) {
          TelemetryFilter.open => c.status == TelemetryTriageStatus.open,
          TelemetryFilter.fresh =>
            c.status == TelemetryTriageStatus.open &&
                (c.isNew || c.isRegression),
          TelemetryFilter.resolved =>
            c.status == TelemetryTriageStatus.resolved,
          TelemetryFilter.ignored => c.status == TelemetryTriageStatus.ignored,
        };
      }).toList();

      // Runs referenciados (rótulo/origem/vivo) + contagem de vivos.
      final need = <String>{for (final c in cases) c.runs.first.runId};
      for (final id in need) {
        if (runsById.containsKey(id) && !runsById[id]!.isLive) continue;
        final r = await store.run(id);
        if (r != null) runsById[id] = r;
      }
      liveRuns = (await store.runs(onlyLive: true, limit: 50)).length;
      sizeBytes = await store.sizeInBytes();
    } on TelemetryStoreError {
      // Base indisponível neste instante (fechando/reabrindo): mantém o que há.
    } finally {
      if (gen == _gen) {
        loading = false;
        notifyListeners();
      }
    }
  }

  /// Run "representante" de uma chave: o mais recente entre os casos.
  TelemetryRun? runForKey(String runKey) {
    TelemetryRun? best;
    for (final c in cases) {
      if (c.runKey != runKey) continue;
      final r = runsById[c.runs.first.runId];
      if (r == null) continue;
      if (best == null || r.startedAt.isAfter(best.startedAt)) best = r;
    }
    return best;
  }

  /// Erros abertos por `taskKey` (badge na linha da task e na aba).
  Map<String, int> get openErrorsByTask {
    final out = <String, int>{};
    for (final c in cases) {
      if (c.status != TelemetryTriageStatus.open ||
          c.severity.index < TelemetrySeverity.error.index) {
        continue;
      }
      final r = runsById[c.runs.first.runId];
      final k = r?.taskKey;
      if (k == null) continue;
      out[k] = (out[k] ?? 0) + 1;
    }
    return out;
  }

  // ---- triagem ---------------------------------------------------------------

  Future<void> triage(String fingerprint, TelemetryTriageStatus status) async {
    final store = await _s();
    if (store == null) return;
    await store.triage(fingerprint, status, by: TelemetryTriageActor.human);
    await refresh();
  }

  Future<void> clearCase(String fingerprint) async {
    final store = await _s();
    if (store == null) return;
    await store.clear(fingerprint: fingerprint);
    await refresh();
  }

  Future<void> clearRun(String runId) async {
    final store = await _s();
    if (store == null) return;
    await store.clear(runId: runId);
    runsById.remove(runId);
    await refresh();
  }

  Future<void> clearProject(String project) async {
    final store = await _s();
    if (store == null) return;
    await store.clear(project: project);
    await refresh();
  }

  // ---- detalhe ---------------------------------------------------------------

  Future<TelemetryCaseDetail?> detail(String fingerprint) async {
    final store = await _s();
    if (store == null) return null;
    final kase = await store.caseById(fingerprint);
    if (kase == null) return null;
    final last = kase.lastEventId == null
        ? null
        : await store.event(kase.lastEventId!);
    final ctx = last == null
        ? const <TelemetryEvent>[]
        : await store.context(last.id!, before: 12, after: 4);
    TelemetryEvent? correlated;
    if (last != null) {
      for (final x in ctx.reversed) {
        if (x.id == last.id || x.ts.isAfter(last.ts)) continue;
        if (x.attrs.isNotEmpty && x.error == null) {
          correlated = x;
          break;
        }
      }
    }
    final runs = <String, TelemetryRun>{};
    for (final r in kase.runs) {
      final run = runsById[r.runId] ?? await store.run(r.runId);
      if (run != null) runs[r.runId] = run;
    }
    final blame = kase.location == null ? null : await blameFor(kase.location!);
    return TelemetryCaseDetail(
      kase: kase,
      last: last,
      context: ctx,
      correlated: correlated,
      runs: runs,
      blame: blame,
    );
  }

  /// Caminho absoluto de um `arquivo:linha` do projeto (primeira root em que
  /// o arquivo existe), ou `null`.
  ({String path, int line})? resolveLocation(String location) {
    final m = RegExp(r'^(.*?)(?::(\d+))?$').firstMatch(location);
    if (m == null) return null;
    final rel = m.group(1)!;
    final line = int.tryParse(m.group(2) ?? '') ?? 1;
    if (p.isAbsolute(rel) && File(rel).existsSync()) {
      return (path: rel, line: line);
    }
    for (final r in _roots) {
      final abs = p.join(r, rel);
      if (File(abs).existsSync()) return (path: abs, line: line);
    }
    return null;
  }

  /// `git blame -L n,n --porcelain`: sha zerado = mudança não commitada.
  Future<TelemetryBlame?> blameFor(String location) async {
    final loc = resolveLocation(location);
    if (loc == null) return null;
    final root = _roots.firstWhere(
      (r) => p.isWithin(r, loc.path),
      orElse: () => p.dirname(loc.path),
    );
    try {
      final r = await Process.run('git', [
        'blame',
        '-L',
        '${loc.line},${loc.line}',
        '--porcelain',
        '--',
        loc.path,
      ], workingDirectory: Directory(root).existsSync() ? root : null);
      if (r.exitCode != 0) return null;
      final out = (r.stdout as String).split('\n');
      if (out.isEmpty) return null;
      final sha = out.first.split(' ').first;
      if (sha.isEmpty) return null;
      if (RegExp(r'^0+$').hasMatch(sha)) {
        return const TelemetryBlame(uncommitted: true);
      }
      DateTime? at;
      for (final l in out) {
        if (l.startsWith('author-time ')) {
          final secs = int.tryParse(l.substring(12).trim());
          if (secs != null) {
            at = DateTime.fromMillisecondsSinceEpoch(secs * 1000);
          }
          break;
        }
      }
      return TelemetryBlame(
        uncommitted: false,
        sha: sha.substring(0, 7),
        at: at,
      );
    } on Exception {
      return null;
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }
}
