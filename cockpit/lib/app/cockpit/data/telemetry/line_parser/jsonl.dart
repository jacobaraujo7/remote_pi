// JSON Lines: o caminho "rico" (plano 66, decisão 7). Não é convenção nossa:
// pino, structlog, slog, tracing e o `logging` do Dart já emitem isso. Aqui
// só conhecemos os apelidos de campo.

import 'dart:convert';

import '../../../domain/entities/telemetry_event.dart';
import '../fingerprint.dart';
import 'frames.dart';

const _levelKeys = ['level', 'severity', 'lvl', 'severityText', 'loglevel'];
const _msgKeys = ['msg', 'message', 'event', 'body', 'text'];
const _timeKeys = ['time', 'ts', 'timestamp', '@timestamp', 'datetime'];
const _errKeys = ['err', 'error', 'exception', 'exc_info'];
const _serviceKeys = ['service', 'name', 'logger', 'app'];
const _traceKeys = ['trace_id', 'traceId', 'traceID', 'trace'];
const _spanKeys = ['span_id', 'spanId', 'spanID'];
const _reqKeys = ['reqId', 'requestId', 'request_id', 'req_id', 'x-request-id'];

/// Tenta interpretar [text] como um objeto JSON de log. `null` se não for.
TelemetryEvent? parseJsonLine(
  String text, {
  required String runId,
  required DateTime at,
  required TelemetryStream stream,
  int? offset,
  String? service,
  List<String> projectRoots = const [],
  List<String> projectFrames = const [],
}) {
  final t = text.trim();
  if (t.length < 2 || !t.startsWith('{') || !t.endsWith('}')) return null;
  Object? decoded;
  try {
    decoded = jsonDecode(t);
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;
  final map = decoded.cast<String, Object?>();

  Object? take(List<String> keys) {
    for (final k in keys) {
      if (map.containsKey(k)) return map.remove(k);
    }
    return null;
  }

  final severity = TelemetrySeverity.parse(take(_levelKeys));
  final msg = take(_msgKeys)?.toString() ?? '';
  final ts = _time(take(_timeKeys)) ?? at;
  final errRaw = take(_errKeys);
  final stackTop = map.remove('stack')?.toString();
  final svc = take(_serviceKeys)?.toString() ?? service;
  final traceId = take(_traceKeys)?.toString();
  final spanId = take(_spanKeys)?.toString();
  final requestId = take(_reqKeys)?.toString();

  TelemetryError? error;
  if (errRaw != null || stackTop != null) {
    error = _error(
      errRaw,
      stackTop,
      fallbackMessage: msg,
      projectRoots: projectRoots,
      projectFrames: projectFrames,
    );
  }
  final attrs = <String, Object?>{'service': ?svc, ...map};
  final sev = error != null && !severity.isProblem
      ? TelemetrySeverity.error
      : severity;
  return TelemetryEvent(
    runId: runId,
    ts: ts,
    stream: stream,
    severity: sev,
    body: msg.isNotEmpty ? msg : (error?.message ?? t),
    attrs: attrs,
    error: error,
    fingerprint: error == null ? null : fingerprintOf(error),
    traceId: traceId,
    spanId: spanId,
    requestId: requestId,
    rawLineOffset: offset,
  );
}

DateTime? _time(Object? v) {
  if (v == null) return null;
  if (v is num) {
    final n = v.toInt();
    // epoch em ms (pino) ou s
    return DateTime.fromMillisecondsSinceEpoch(n > 100000000000 ? n : n * 1000);
  }
  return DateTime.tryParse(v.toString());
}

TelemetryError _error(
  Object? raw,
  String? stackTop, {
  required String fallbackMessage,
  required List<String> projectRoots,
  required List<String> projectFrames,
}) {
  String type = 'Error';
  String message = fallbackMessage;
  String? stack = stackTop;
  if (raw is Map) {
    final m = raw.cast<String, Object?>();
    type = (m['type'] ?? m['name'] ?? m['kind'] ?? m['class'] ?? type)
        .toString();
    message = (m['message'] ?? m['msg'] ?? message).toString();
    stack ??= m['stack']?.toString() ?? m['stacktrace']?.toString();
  } else if (raw is String && raw.isNotEmpty) {
    // "RangeError: msg" ou só a mensagem
    final m = RegExp(
      r'^([A-Z][\w.]*(?:Error|Exception|Warning)?):\s*(.+)$',
      dotAll: true,
    ).firstMatch(raw);
    if (m != null) {
      type = m.group(1)!;
      message = m.group(2)!;
    } else {
      message = raw;
    }
    if (raw.contains('\n    at ') || raw.contains('\n#')) stack = raw;
  } else if (raw is List) {
    message = raw.map((e) => e.toString()).join('\n');
  }
  final frames = <TelemetryFrame>[];
  if (stack != null) {
    for (final line in const LineSplitter().convert(stack)) {
      final f = parseFrame(
        line,
        projectRoots: projectRoots,
        projectFrames: projectFrames,
      );
      if (f != null) frames.add(f);
    }
    // "Error: msg" na primeira linha do stack do Node
    final head = RegExp(
      r'^([A-Z][\w.]*(?:Error|Exception)):\s*(.+)$',
    ).firstMatch(stack.split('\n').first);
    if (head != null && type == 'Error') {
      type = head.group(1)!;
      if (message.isEmpty || message == fallbackMessage) {
        message = head.group(2)!;
      }
    }
  }
  return TelemetryError(
    type: type,
    message: message,
    stack: stack,
    frames: frames,
  );
}
