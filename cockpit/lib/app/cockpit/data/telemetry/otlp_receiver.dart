// Receptor OTLP/HTTP (plano 66, passo 9): `POST /v1/logs` e `/v1/traces` em
// JSON (protobuf fica pra depois), só em loopback, porta efêmera. O run é
// resolvido pelo resource attribute `cockpit.run` (o wrapper/task injeta
// `OTEL_RESOURCE_ATTRIBUTES`); sem ele, cai pelo `service.name` = chave de
// um run vivo; sem match, descarta (não inventamos run pra tráfego anônimo).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../domain/entities/telemetry_event.dart';
import 'fingerprint.dart';
import 'line_parser/frames.dart';

/// Quem resolve um run vivo e recebe eventos por ele.
abstract class OtlpSink {
  /// `runId` exato ou `null`.
  String? runFor({String? runId, String? serviceName});
  void addEvents(String runId, List<TelemetryEvent> events);
  List<String> projectRootsOf(String runId);
}

class OtlpReceiver {
  OtlpReceiver(this._sink);

  final OtlpSink _sink;
  HttpServer? _server;

  /// `http://127.0.0.1:<porta>` (vazio enquanto não sobe).
  String get endpoint =>
      _server == null ? '' : 'http://127.0.0.1:${_server!.port}';

  Future<void> start() async {
    if (_server != null) return;
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    } on SocketException {
      return; // sem porta: telemetria segue só por stdout
    }
    unawaited(_serve());
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _serve() async {
    final server = _server;
    if (server == null) return;
    await for (final req in server) {
      unawaited(_handle(req));
    }
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      if (req.method != 'POST') {
        req.response.statusCode = HttpStatus.methodNotAllowed;
        await req.response.close();
        return;
      }
      final path = req.uri.path;
      final ct = req.headers.contentType?.mimeType ?? '';
      if (!ct.contains('json')) {
        // protobuf: aceita (204) pra não fazer o SDK do app repetir, mas ignora.
        await req.drain<void>();
        req.response.statusCode = HttpStatus.unsupportedMediaType;
        await req.response.close();
        return;
      }
      var body = await utf8.decoder.bind(req).join();
      if (req.headers.value(HttpHeaders.contentEncodingHeader) == 'gzip') {
        body = utf8.decode(gzip.decode(latin1.encode(body)));
      }
      final json = jsonDecode(body);
      if (json is Map) {
        if (path == '/v1/logs') {
          _logs(json.cast<String, Object?>());
        } else if (path == '/v1/traces') {
          _traces(json.cast<String, Object?>());
        }
      }
      req.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write('{}');
      await req.response.close();
    } on Object {
      try {
        req.response.statusCode = HttpStatus.badRequest;
        await req.response.close();
      } on Object {
        // conexão já fechada
      }
    }
  }

  // ---- logs -------------------------------------------------------------------

  void _logs(Map<String, Object?> payload) {
    for (final rl in _list(payload['resourceLogs'])) {
      final res = _attrs(_map(rl['resource'])?['attributes']);
      final runId = _runOf(res);
      if (runId == null) continue;
      final roots = _sink.projectRootsOf(runId);
      final out = <TelemetryEvent>[];
      for (final sl in _list(rl['scopeLogs'])) {
        for (final r in _list(sl['logRecords'])) {
          final attrs = _attrs(r['attributes']);
          final sev = _severity(r['severityNumber'], r['severityText']);
          final body = _anyValue(r['body'])?.toString() ?? '';
          final exType = attrs.remove('exception.type')?.toString();
          final exMsg = attrs.remove('exception.message')?.toString();
          final exStack = attrs.remove('exception.stacktrace')?.toString();
          TelemetryError? err;
          if (exType != null ||
              exStack != null ||
              (sev.isProblem &&
                  sev.index >= TelemetrySeverity.error.index &&
                  exMsg != null)) {
            err = TelemetryError(
              type: exType ?? 'Error',
              message: exMsg ?? body,
              stack: exStack,
              frames: _frames(exStack, roots),
            );
          }
          out.add(
            TelemetryEvent(
              runId: runId,
              ts: _ts(r['timeUnixNano'] ?? r['observedTimeUnixNano']),
              stream: TelemetryStream.otlp,
              severity: sev,
              body: body.isEmpty ? (err?.message ?? '') : body,
              attrs: {
                if (res['service.name'] != null) 'service': res['service.name'],
                ...attrs,
              },
              error: err,
              fingerprint: err == null ? null : fingerprintOf(err),
              traceId: r['traceId']?.toString(),
              spanId: r['spanId']?.toString(),
            ),
          );
        }
      }
      if (out.isNotEmpty) _sink.addEvents(runId, out);
    }
  }

  // ---- traces -----------------------------------------------------------------

  void _traces(Map<String, Object?> payload) {
    for (final rs in _list(payload['resourceSpans'])) {
      final res = _attrs(_map(rs['resource'])?['attributes']);
      final runId = _runOf(res);
      if (runId == null) continue;
      final roots = _sink.projectRootsOf(runId);
      final out = <TelemetryEvent>[];
      for (final ss in _list(rs['scopeSpans'])) {
        for (final sp in _list(ss['spans'])) {
          final attrs = _attrs(sp['attributes']);
          final start = _ts(sp['startTimeUnixNano']);
          final end = _ts(sp['endTimeUnixNano']);
          final ms = end.difference(start).inMilliseconds;
          final status = _map(sp['status']);
          final failed =
              status?['code'] == 2 || status?['code'] == 'STATUS_CODE_ERROR';
          final name = sp['name']?.toString() ?? 'span';
          final httpStatus =
              attrs['http.response.status_code'] ?? attrs['http.status_code'];
          TelemetryError? err;
          // Eventos de exceção do span viram o erro do evento.
          for (final ev in _list(sp['events'])) {
            if (ev['name'] == 'exception') {
              final ea = _attrs(ev['attributes']);
              final stack = ea['exception.stacktrace']?.toString();
              err = TelemetryError(
                type: ea['exception.type']?.toString() ?? 'Error',
                message: ea['exception.message']?.toString() ?? name,
                stack: stack,
                frames: _frames(stack, roots),
              );
              break;
            }
          }
          if (err == null && failed) {
            err = TelemetryError(
              type: httpStatus != null ? 'HTTP $httpStatus' : 'SpanError',
              message: status?['message']?.toString().isNotEmpty == true
                  ? status!['message'].toString()
                  : name,
            );
          }
          out.add(
            TelemetryEvent(
              runId: runId,
              ts: start,
              stream: TelemetryStream.otlp,
              severity: err != null
                  ? TelemetrySeverity.error
                  : TelemetrySeverity.debug,
              body: '$name ${httpStatus ?? ''} ${ms}ms'
                  .replaceAll(RegExp(r'\s+'), ' ')
                  .trim(),
              attrs: {
                if (res['service.name'] != null) 'service': res['service.name'],
                'span': name,
                'duration_ms': ms,
                if (sp['parentSpanId'] != null &&
                    sp['parentSpanId'].toString().isNotEmpty)
                  'parent_span_id': sp['parentSpanId'],
                ...attrs,
              },
              error: err,
              fingerprint: err == null ? null : fingerprintOf(err),
              traceId: sp['traceId']?.toString(),
              spanId: sp['spanId']?.toString(),
              requestId:
                  attrs['http.request.header.x-request-id']?.toString() ??
                  attrs['x-request-id']?.toString(),
            ),
          );
        }
      }
      if (out.isNotEmpty) _sink.addEvents(runId, out);
    }
  }

  // ---- helpers ----------------------------------------------------------------

  String? _runOf(Map<String, Object?> res) => _sink.runFor(
    runId: res['cockpit.run']?.toString(),
    serviceName: res['service.name']?.toString(),
  );

  static List<Map<String, Object?>> _list(Object? v) => v is List
      ? [
          for (final e in v)
            if (e is Map) e.cast<String, Object?>(),
        ]
      : const [];

  static Map<String, Object?>? _map(Object? v) =>
      v is Map ? v.cast<String, Object?>() : null;

  /// `[{key, value:{stringValue|intValue|...}}]` → mapa plano.
  static Map<String, Object?> _attrs(Object? v) {
    final out = <String, Object?>{};
    for (final kv in _list(v)) {
      final k = kv['key']?.toString();
      if (k == null) continue;
      out[k] = _anyValue(kv['value']);
    }
    return out;
  }

  static Object? _anyValue(Object? v) {
    final m = _map(v);
    if (m == null) return v;
    if (m.containsKey('stringValue')) return m['stringValue'];
    if (m.containsKey('intValue')) {
      return int.tryParse('${m['intValue']}') ?? m['intValue'];
    }
    if (m.containsKey('doubleValue')) return m['doubleValue'];
    if (m.containsKey('boolValue')) return m['boolValue'];
    if (m.containsKey('arrayValue')) {
      return [
        for (final e in _list(_map(m['arrayValue'])?['values'])) _anyValue(e),
      ];
    }
    if (m.containsKey('kvlistValue')) {
      return _attrs(_map(m['kvlistValue'])?['values']);
    }
    return null;
  }

  static DateTime _ts(Object? nanos) {
    final n = nanos == null ? null : int.tryParse(nanos.toString());
    if (n == null) return DateTime.now();
    return DateTime.fromMicrosecondsSinceEpoch(n ~/ 1000);
  }

  static TelemetrySeverity _severity(Object? number, Object? text) {
    final n = number == null ? null : int.tryParse(number.toString());
    if (n != null) {
      if (n >= 21) return TelemetrySeverity.fatal;
      if (n >= 17) return TelemetrySeverity.error;
      if (n >= 13) return TelemetrySeverity.warn;
      if (n >= 9) return TelemetrySeverity.info;
      if (n >= 5) return TelemetrySeverity.debug;
      if (n >= 1) return TelemetrySeverity.trace;
    }
    return TelemetrySeverity.parse(text);
  }

  static List<TelemetryFrame> _frames(String? stack, List<String> roots) {
    if (stack == null) return const [];
    return [
      for (final l in const LineSplitter().convert(stack))
        ?parseFrame(l, projectRoots: roots),
    ];
  }
}
