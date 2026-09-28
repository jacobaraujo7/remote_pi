// Adaptador Dart VM Service (plano 66, passo 8): quando um run imprime a URI
// do VM Service (`flutter run` / `dart run --observe`), conectamos como cliente
// adicional e viramos eventos `stream: vm`:
//   - `Logging`   → `dart:developer log()` / pacote `logging` (com error+stack)
//   - `Extension` → `Flutter.Error` (o bloco de erro estruturado do framework)
//   - `Isolate`   → `PauseException` (se pause-on-exceptions estiver ligado)
// Zero código no app. Dedup contra o stdout é da sessão (mesmo fingerprint em
// janela curta).

import 'dart:async';
import 'dart:convert';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import '../../domain/contracts/telemetry_line_parser.dart';
import '../../domain/entities/telemetry_event.dart';
import 'fingerprint.dart';
import 'line_parser/frames.dart';

/// `A Dart VM Service on iPhone is available at: http://127.0.0.1:52914/xK3pQ=/`
final vmServiceUriPattern = RegExp(
  r'(?:Dart VM Service|Observatory)[^\n]*?is available at:?\s*(https?://\S+)',
);

class VmServiceAttachment {
  VmServiceAttachment._(
    this._service,
    this._runId,
    this._sink,
    this._parser,
    this._config,
  );

  final VmService _service;
  final String _runId;
  final void Function(List<TelemetryEvent> events) _sink;
  final TelemetryLineParser _parser;
  final TelemetryParserConfig _config;
  final _subs = <StreamSubscription<Event>>[];
  var _closed = false;

  /// Converte a URI http do VM Service na ws e conecta. `null` se não deu
  /// (app já saiu, porta fechada, token inválido): telemetria segue só pelo
  /// stdout.
  static Future<VmServiceAttachment?> connect(
    Uri httpUri, {
    required String runId,
    required void Function(List<TelemetryEvent> events) sink,
    required TelemetryLineParser parser,
    required TelemetryParserConfig config,
  }) async {
    final path = httpUri.path.endsWith('/')
        ? '${httpUri.path}ws'
        : '${httpUri.path}/ws';
    final ws = httpUri.replace(
      scheme: httpUri.scheme == 'https' ? 'wss' : 'ws',
      path: path,
    );
    VmService service;
    try {
      service = await vmServiceConnectUri(
        ws.toString(),
      ).timeout(const Duration(seconds: 5));
    } on Object {
      return null;
    }
    final a = VmServiceAttachment._(service, runId, sink, parser, config);
    try {
      await a._start();
    } on Object {
      await a.close();
      return null;
    }
    return a;
  }

  Future<void> _start() async {
    for (final id in const ['Logging', 'Extension', 'Isolate']) {
      try {
        await _service.streamListen(id);
      } on RPCError {
        // Já assinado por outro cliente do mesmo socket: segue.
      }
    }
    _subs
      ..add(_service.onLoggingEvent.listen(_onLog, onError: (_) {}))
      ..add(_service.onExtensionEvent.listen(_onExtension, onError: (_) {}))
      ..add(_service.onIsolateEvent.listen(_onIsolate, onError: (_) {}));
    unawaited(_service.onDone.then((_) => close()));
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final s in _subs) {
      await s.cancel();
    }
    try {
      await _service.dispose();
    } on Object {
      // socket já fechado
    }
  }

  // ---- Logging ----------------------------------------------------------------

  Future<void> _onLog(Event e) async {
    final r = e.logRecord;
    if (r == null || _closed) return;
    final iso = e.isolate?.id;
    final msg = await _str(iso, r.message) ?? '';
    final level = r.level ?? 800;
    var sev = _severityOf(level);
    TelemetryError? error;
    final errRef = r.error;
    if (errRef != null && errRef.kind != InstanceKind.kNull) {
      final message = await _str(iso, errRef) ?? '';
      final stack = await _str(iso, r.stackTrace);
      final type = errRef.classRef?.name ?? 'Error';
      error = _error(type, message, stack);
      if (!sev.isProblem) sev = TelemetrySeverity.error;
    }
    final logger = await _str(iso, r.loggerName);
    _emit(
      TelemetryEvent(
        runId: _runId,
        ts: r.time == null
            ? DateTime.now()
            : DateTime.fromMillisecondsSinceEpoch(r.time!),
        stream: TelemetryStream.vm,
        severity: sev,
        body: msg.isEmpty ? (error?.message ?? '') : msg,
        attrs: {'logger': ?(logger == null || logger.isEmpty ? null : logger)},
        error: error,
        fingerprint: error == null ? null : fingerprintOf(error),
      ),
    );
  }

  // ---- Extension (Flutter.Error) ------------------------------------------------

  void _onExtension(Event e) {
    if (_closed) return;
    final kind = e.extensionKind ?? '';
    final data = e.extensionData?.data ?? const <String, dynamic>{};
    if (kind == 'Flutter.Error') {
      // O texto renderizado é o mesmo bloco `══╡ EXCEPTION CAUGHT BY ... ╞══`
      // que sai no console: reaproveita o parser (e o fingerprint bate com o
      // do stdout, que é o que a sessão usa pra dedup).
      final rendered =
          data['renderedErrorText']?.toString() ??
          data['description']?.toString();
      if (rendered == null || rendered.isEmpty) return;
      final now = DateTime.now();
      final out = <TelemetryEvent>[];
      for (final line in const LineSplitter().convert(rendered)) {
        out.addAll(_parser.feed(line, stream: TelemetryStream.vm, at: now));
      }
      out.addAll(_parser.flush());
      if (out.isNotEmpty) _sink(out);
      return;
    }
    if (kind.startsWith('Flutter.') || kind.startsWith('ext.')) {
      return; // ruído do framework
    }
    // Evento custom do app (`postEvent('cockpit.x', {...})`): vira log.
    _emit(
      TelemetryEvent(
        runId: _runId,
        ts: DateTime.now(),
        stream: TelemetryStream.vm,
        severity: TelemetrySeverity.parse(data['level']),
        body: data['msg']?.toString() ?? data['message']?.toString() ?? kind,
        attrs: {'event': kind, ...data.map((k, v) => MapEntry(k, v))},
      ),
    );
  }

  // ---- Isolate (PauseException) -------------------------------------------------

  Future<void> _onIsolate(Event e) async {
    if (_closed || e.kind != EventKind.kPauseException) return;
    final iso = e.isolate?.id;
    final ex = e.exception;
    if (ex == null) return;
    final message = await _str(iso, ex) ?? '';
    final error = _error(ex.classRef?.name ?? 'Exception', message, null);
    _emit(
      TelemetryEvent(
        runId: _runId,
        ts: DateTime.now(),
        stream: TelemetryStream.vm,
        severity: TelemetrySeverity.error,
        body: message,
        attrs: const {'paused': true},
        error: error,
        fingerprint: fingerprintOf(error),
      ),
    );
  }

  // ---- helpers -----------------------------------------------------------------

  void _emit(TelemetryEvent e) {
    if (!_closed) _sink([e]);
  }

  TelemetryError _error(String type, String message, String? stack) {
    final frames = <TelemetryFrame>[];
    if (stack != null) {
      for (final l in const LineSplitter().convert(stack)) {
        final f = parseFrame(
          l,
          projectRoots: _config.projectRoots,
          projectFrames: _config.projectFrames,
        );
        if (f != null) frames.add(f);
      }
    }
    // "RangeError (index): msg" → tipo/mensagem separados
    final m = RegExp(
      r'^([A-Z][\w.]*(?:Error|Exception))(?:\s*\([^)]*\))?:\s*(.+)$',
      dotAll: true,
    ).firstMatch(message);
    return TelemetryError(
      type: m?.group(1) ?? type,
      message: m?.group(2) ?? message,
      stack: stack,
      frames: frames,
    );
  }

  static TelemetrySeverity _severityOf(int level) {
    if (level >= 1200) return TelemetrySeverity.fatal; // SHOUT
    if (level >= 1000) return TelemetrySeverity.error; // SEVERE
    if (level >= 900) return TelemetrySeverity.warn; // WARNING
    if (level >= 800) return TelemetrySeverity.info; // INFO
    if (level >= 500) return TelemetrySeverity.debug; // CONFIG/FINE
    return TelemetrySeverity.trace;
  }

  /// String de um [InstanceRef]: `valueAsString` quando inteiro; senão
  /// `toString()` remoto (stack traces e objetos), com teto.
  Future<String?> _str(String? isolateId, InstanceRef? ref) async {
    if (ref == null || ref.kind == InstanceKind.kNull) return null;
    if (ref.valueAsString != null && ref.valueAsStringIsTruncated != true) {
      return ref.valueAsString;
    }
    if (isolateId == null) return ref.valueAsString;
    try {
      if (ref.kind == InstanceKind.kString && ref.id != null) {
        final full = await _service.getObject(isolateId, ref.id!, count: 16384);
        if (full is Instance) return full.valueAsString;
      }
      if (ref.id != null) {
        final r = await _service.invoke(
          isolateId,
          ref.id!,
          'toString',
          const [],
        );
        if (r is InstanceRef) {
          if (r.valueAsStringIsTruncated == true && r.id != null) {
            final full = await _service.getObject(
              isolateId,
              r.id!,
              count: 16384,
            );
            if (full is Instance) return full.valueAsString;
          }
          return r.valueAsString;
        }
      }
    } on Object {
      // isolate já foi embora
    }
    return ref.valueAsString;
  }
}
