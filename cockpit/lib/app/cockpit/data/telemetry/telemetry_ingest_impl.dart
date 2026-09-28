// Implementação do ingest (plano 66, passo 3): resolve o workspace pelo cwd,
// abre o run no store certo, separa linhas, passa pelo parser e grava em
// lotes. Task e wrapper usam a mesma sessão; só muda quem chama `add`.

import 'dart:async';
import 'dart:io' show pid;

import 'package:path/path.dart' as p;

import '../../domain/contracts/telemetry_ingest.dart';
import '../../domain/contracts/telemetry_line_parser.dart';
import '../../domain/contracts/telemetry_store.dart';
import '../../domain/entities/task_definition.dart';
import '../../domain/entities/telemetry_event.dart';
import '../../domain/entities/telemetry_run.dart';
import 'fingerprint.dart';
import 'http_proxy.dart';
import 'otlp_receiver.dart';
import 'telemetry_workspace_config.dart';
import 'vm_service_ingest.dart';

class TelemetryIngestImpl implements TelemetryIngest, OtlpSink {
  TelemetryIngestImpl(this._registry, this._parsers, {bool startOtlp = true}) {
    if (startOtlp) {
      _otlp = OtlpReceiver(this);
      unawaited(_otlp!.start().then((_) => otlpEndpoint = _otlp!.endpoint));
    }
  }

  final TelemetryStoreProvider _registry;
  final TelemetryLineParserFactory _parsers;
  final _workspaces = <String, TelemetryWorkspace>{};
  final _configs = <String, TelemetryWorkspaceConfig>{};
  final _proxies = <String, HttpTelemetryProxy>{};
  final _live = <String, _Session>{};
  final _notices = StreamController<TelemetryErrorNotice>.broadcast();
  OtlpReceiver? _otlp;

  @override
  Stream<TelemetryErrorNotice> get notices => _notices.stream;

  /// Endpoint OTLP local (passo 9). Vazio enquanto o receptor não subiu.
  String otlpEndpoint = '';

  @override
  void registerWorkspace(TelemetryWorkspace workspace) {
    if (workspace.id.isEmpty || workspace.path.isEmpty) return;
    _workspaces[workspace.id] = workspace;
    // `.cockpit/telemetry.json` é relido a cada registro (troca de workspace):
    // barato e evita watcher. Proxy sobe uma vez por workspace.
    final cfg = TelemetryWorkspaceConfig.load(workspace.path);
    _configs[workspace.id] = cfg;
    final proxy = cfg.proxy;
    if (proxy != null && !_proxies.containsKey(workspace.id)) {
      unawaited(_startProxy(workspace, proxy));
    }
  }

  Future<void> _startProxy(
    TelemetryWorkspace ws,
    TelemetryProxyConfig cfg,
  ) async {
    final session =
        await _open(
              cwd: ws.path,
              command: 'proxy :${cfg.listen} → ${cfg.upstream}',
              name: 'proxy',
              source: TelemetryRunSource.wrapper,
            )
            as _Session?;
    if (session == null) return;
    final proxy = HttpTelemetryProxy(
      config: cfg,
      runId: session.runId,
      sink: session.addEvents,
    );
    if (await proxy.start()) {
      _proxies[ws.id] = proxy;
    } else {
      await session.close(exitCode: 1);
    }
  }

  @override
  Future<int?> replay({
    required String workspaceId,
    required DateTime since,
    DateTime? until,
  }) async {
    final proxy = _proxies[workspaceId];
    if (proxy == null) return null;
    final store = await _registry.forWorkspace(workspaceId);
    final events = await store.events(
      TelemetryQuery(
        runId: proxy.runId,
        since: since,
        until: until,
        limit: 2000,
        includeIgnored: true,
      ),
    );
    return proxy.replay(events);
  }

  // ---- OtlpSink ----------------------------------------------------------------

  @override
  String? runFor({String? runId, String? serviceName}) {
    if (runId != null && _live.containsKey(runId)) return runId;
    if (serviceName == null) return null;
    for (final s in _live.values) {
      if (s.run.name == serviceName || s.run.key == 'name:$serviceName') {
        return s.runId;
      }
    }
    return null;
  }

  @override
  void addEvents(String runId, List<TelemetryEvent> events) =>
      _live[runId]?.addEvents(events);

  @override
  List<String> projectRootsOf(String runId) =>
      _live[runId]?.config.projectRoots ?? const [];

  /// Workspace cuja root contém [cwd]; empate → root mais específica.
  ({TelemetryWorkspace ws, String project})? resolve(String cwd) {
    final ncwd = p.normalize(cwd);
    TelemetryWorkspace? best;
    String? bestRoot;
    for (final ws in _workspaces.values) {
      final roots = ws.roots.isEmpty ? [ws.path] : ws.roots;
      for (final r in roots) {
        final nr = p.normalize(r);
        if (nr == ncwd || p.isWithin(nr, ncwd)) {
          if (bestRoot == null || nr.length > bestRoot.length) {
            best = ws;
            bestRoot = nr;
          }
        }
      }
    }
    if (best == null || bestRoot == null) return null;
    final roots = best.roots.isEmpty ? [best.path] : best.roots;
    // Raiz única: o projeto é o próprio workspace (decisão 11 achata).
    final project = roots.length <= 1 ? best.name : p.basename(bestRoot);
    return (ws: best, project: project);
  }

  @override
  TelemetryIngestSession? session(String runId) => _live[runId];

  @override
  Future<TelemetryIngestSession?> openWrapperRun({
    required String cwd,
    required String command,
    String? name,
    String? paneId,
    int? pid,
  }) => _open(
    cwd: cwd,
    command: command,
    name: name,
    source: TelemetryRunSource.wrapper,
    paneId: paneId,
    pid: pid,
  );

  @override
  Future<TelemetryIngestSession?> openTaskRun(
    TaskDefinition def, {
    required String command,
    int? pid,
    String? paneId,
  }) async {
    if (!def.telemetryEnabled || def.cwd.isEmpty) return null;
    return _open(
      cwd: def.cwd,
      command: command,
      name: def.label,
      source: TelemetryRunSource.task,
      taskKey: def.id,
      paneId: paneId,
      pid: pid,
    );
  }

  @override
  Future<TelemetryIngestSession?> openAppRun({required String version}) async {
    final store = await _registry.forWorkspace(kTelemetryAppWorkspaceId);
    final run = await store.openRun(
      key: 'app:cockpit',
      project: 'Cockpit',
      source: TelemetryRunSource.app,
      cwd: '',
      command: 'Cockpit $version',
      name: 'Cockpit',
      pid: pid,
    );
    const config = TelemetryParserConfig();
    final s = _Session(
      store: store,
      run: run,
      parser: _parsers.create(runId: run.id, config: config),
      vmParser: () => _parsers.create(runId: run.id, config: config),
      config: config,
      ignore: const [],
      otlpEndpoint: otlpEndpoint,
      project: 'Cockpit',
      onClosed: () => _live.remove(run.id),
      // Sem push: o run do app não tem pane de agente.
      onErrors: (_) {},
    );
    _live[run.id] = s;
    return s;
  }

  Future<TelemetryIngestSession?> _open({
    required String cwd,
    required String command,
    required TelemetryRunSource source,
    String? name,
    String? taskKey,
    String? paneId,
    int? pid,
  }) async {
    if (cwd.isEmpty) return null;
    final hit = resolve(cwd);
    if (hit == null) return null;
    final store = await _registry.forWorkspace(hit.ws.id);
    final run = await store.openRun(
      key: TelemetryRun.keyFor(cwd: cwd, command: command, name: name),
      project: hit.project,
      source: source,
      cwd: cwd,
      command: command,
      name: name,
      taskKey: taskKey,
      paneId: paneId,
      pid: pid,
    );
    final roots = hit.ws.roots.isEmpty ? [hit.ws.path] : hit.ws.roots;
    final wsCfg = _configs[hit.ws.id] ?? TelemetryWorkspaceConfig.empty;
    final config = TelemetryParserConfig(
      projectRoots: roots,
      unwrap: wsCfg.unwrap,
      projectFrames: wsCfg.projectFrames,
    );
    final s = _Session(
      store: store,
      run: run,
      parser: _parsers.create(runId: run.id, config: config),
      vmParser: () => _parsers.create(runId: run.id, config: config),
      config: config,
      ignore: wsCfg.ignore,
      otlpEndpoint: otlpEndpoint,
      project: hit.project,
      onClosed: () => _live.remove(run.id),
      onErrors: (fps) {
        if (_notices.isClosed) return;
        _notices.add(
          TelemetryErrorNotice(
            workspaceId: hit.ws.id,
            runId: run.id,
            project: hit.project,
            paneId: paneId,
            fingerprints: fps,
          ),
        );
      },
    );
    _live[run.id] = s;
    return s;
  }
}

class _Session implements TelemetryIngestSession {
  _Session({
    required this.store,
    required this.run,
    required this.parser,
    required this.vmParser,
    required this.config,
    required this.ignore,
    required this.otlpEndpoint,
    required this.project,
    required this.onClosed,
    required this.onErrors,
  });

  final TelemetryStore store;
  final TelemetryRun run;
  final TelemetryLineParser parser;

  /// Parser separado pro texto vindo do VM Service (blocos não se misturam
  /// com os do stdout).
  final TelemetryLineParser Function() vmParser;
  final TelemetryParserConfig config;

  /// Padrões do `telemetry.json` descartados na entrada (ruído conhecido).
  final List<RegExp> ignore;
  final String otlpEndpoint;
  final String project;
  final void Function() onClosed;
  final void Function(Set<String> fingerprints) onErrors;

  final _partial = <TelemetryStream, StringBuffer>{};
  final _pending = <TelemetryEvent>[];
  Timer? _flushTimer;
  Future<void> _writes = Future.value();
  var _lines = 0;
  var _closed = false;

  /// Dedup stdout × VM Service: fingerprint → última vez visto.
  final _recentFps = <String, DateTime>{};
  static const _dedupWindow = Duration(milliseconds: 1500);
  VmServiceAttachment? _vm;
  bool _vmTried = false;

  static const _batchLines = 200;
  static const _batchDelay = Duration(milliseconds: 100);

  @override
  String get runId => run.id;

  @override
  Map<String, String> get childEnvironment => {
    'COCKPIT_RUN_ID': run.id,
    'OTEL_SERVICE_NAME': run.name ?? run.command,
    'OTEL_RESOURCE_ATTRIBUTES':
        'cockpit.run=${run.id},cockpit.project=$project',
    if (otlpEndpoint.isNotEmpty) 'OTEL_EXPORTER_OTLP_ENDPOINT': otlpEndpoint,
  };

  @override
  void add(String chunk, {TelemetryStream stream = TelemetryStream.out}) {
    if (_closed || chunk.isEmpty) return;
    final buf = _partial.putIfAbsent(stream, StringBuffer.new)..write(chunk);
    final text = buf.toString();
    var start = 0;
    final now = DateTime.now();
    for (var i = 0; i < text.length; i++) {
      final c = text.codeUnitAt(i);
      if (c == 0x0A) {
        var line = text.substring(start, i);
        if (line.isNotEmpty && line.codeUnitAt(line.length - 1) == 0x0D) {
          line = line.substring(0, line.length - 1);
        }
        _pending.addAll(
          parser.feed(line, stream: stream, at: now, offset: _lines++),
        );
        if (!_vmTried) _maybeAttachVm(line);
        start = i + 1;
      }
    }
    buf
      ..clear()
      ..write(text.substring(start));
    _scheduleFlush();
  }

  void _scheduleFlush() {
    if (_pending.length >= _batchLines) {
      _flush();
      return;
    }
    _flushTimer ??= Timer(_batchDelay, _flush);
  }

  void _flush() {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_pending.isEmpty) return;
    final batch = _dedup(List<TelemetryEvent>.of(_pending));
    _pending.clear();
    if (batch.isEmpty) return;
    // Serializa as escritas: a ordem dos eventos é a ordem das linhas.
    _writes = _writes
        .then((_) => store.append(batch))
        .then((saved) {
          final fps = <String>{
            for (final e in saved)
              if (e.fingerprint != null &&
                  e.severity.index >= TelemetrySeverity.error.index)
                e.fingerprint!,
          };
          if (fps.isNotEmpty) onErrors(fps);
        })
        .catchError((_) {});
  }

  @override
  Future<void> close({int? exitCode}) async {
    if (_closed) return;
    _closed = true;
    final now = DateTime.now();
    for (final e in _partial.entries) {
      final rest = e.value.toString();
      if (rest.trim().isNotEmpty) {
        _pending.addAll(
          parser.feed(rest, stream: e.key, at: now, offset: _lines++),
        );
      }
    }
    _pending.addAll(parser.flush());
    _flush();
    await _writes;
    await _vm?.close();
    await store.closeRun(run.id, exitCode: exitCode);
    onClosed();
  }

  /// Eventos que não passam pelo parser de linhas (VM Service, OTLP, app).
  @override
  void addEvents(List<TelemetryEvent> events) {
    if (_closed || events.isEmpty) return;
    _pending.addAll(events);
    _scheduleFlush();
  }

  /// Um erro que chegou pelo stdout E pelo VM Service (mesmo fingerprint,
  /// janela curta) conta uma vez.
  List<TelemetryEvent> _dedup(List<TelemetryEvent> batch) {
    final now = DateTime.now();
    _recentFps.removeWhere((_, t) => now.difference(t) > _dedupWindow * 4);
    final out = <TelemetryEvent>[];
    for (var e in batch) {
      if (ignore.isNotEmpty) {
        final text = e.error == null
            ? e.body
            : '${e.error!.type}: ${e.error!.message}';
        if (ignore.any((re) => re.hasMatch(text))) continue;
      }
      final fp =
          e.fingerprint ?? (e.error == null ? null : fingerprintOf(e.error!));
      if (fp != null) {
        final seen = _recentFps[fp];
        if (seen != null && e.ts.difference(seen).abs() <= _dedupWindow) {
          continue;
        }
        _recentFps[fp] = e.ts;
        if (e.fingerprint == null) e = e.copyWith(fingerprint: fp);
      }
      out.add(e);
    }
    return out;
  }

  void _maybeAttachVm(String line) {
    final m = vmServiceUriPattern.firstMatch(line);
    if (m == null) return;
    final uri = Uri.tryParse(m.group(1)!.trim());
    if (uri == null) return;
    _vmTried = true;
    unawaited(
      VmServiceAttachment.connect(
        uri,
        runId: run.id,
        sink: addEvents,
        parser: vmParser(),
        config: config,
      ).then((a) {
        if (a == null) return;
        if (_closed) {
          unawaited(a.close());
        } else {
          _vm = a;
        }
      }),
    );
  }
}
