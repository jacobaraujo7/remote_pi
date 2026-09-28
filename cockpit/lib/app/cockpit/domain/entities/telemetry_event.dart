// Evento de telemetria: a tabela única onde caem stdout de task/wrapper,
// VM Service, OTLP e proxy (plano 66). Formato inspirado no LogRecord do OTel
// pra que as torneiras futuras não mudem o schema.

/// Severidade normalizada. A ordem importa (comparações `>=`).
enum TelemetrySeverity {
  trace,
  debug,
  info,
  warn,
  error,
  fatal;

  bool get isProblem => index >= TelemetrySeverity.warn.index;

  /// Aceita nomes (`warning`, `err`) e os níveis numéricos do pino
  /// (10..60). Desconhecido = `info`.
  static TelemetrySeverity parse(Object? raw) {
    if (raw == null) return info;
    if (raw is num) {
      if (raw >= 60) return fatal;
      if (raw >= 50) return error;
      if (raw >= 40) return warn;
      if (raw >= 30) return info;
      if (raw >= 20) return debug;
      return trace;
    }
    final s = raw.toString().trim().toLowerCase();
    final n = int.tryParse(s);
    if (n != null) return parse(n);
    return switch (s) {
      'trace' || 'verbose' || 'finest' || 'finer' => trace,
      'debug' || 'dbg' || 'fine' || 'config' => debug,
      'info' || 'information' || 'notice' || 'log' => info,
      'warn' || 'warning' || 'wrn' => warn,
      'error' || 'err' || 'severe' || 'e' => error,
      'fatal' || 'critical' || 'crit' || 'panic' || 'shout' => fatal,
      _ => info,
    };
  }
}

/// De qual torneira o evento veio.
enum TelemetryStream { out, err, vm, otlp, proxy }

/// Um frame de stack já interpretado.
class TelemetryFrame {
  const TelemetryFrame({
    required this.raw,
    this.file,
    this.line,
    this.column,
    this.function,
    this.inProject = false,
  });

  final String raw;

  /// Caminho como aparece no stack (`lib/cart/cart_service.dart`,
  /// `/abs/src/db.ts`, `package:app/cart/cart_service.dart`).
  final String? file;
  final int? line;
  final int? column;
  final String? function;

  /// `true` quando o frame pertence ao código do workspace (não a
  /// `package:flutter`, `node_modules`, `dart:`, `node:`...).
  final bool inProject;

  /// `arquivo:linha` curto pra UI e fingerprint (`null` sem arquivo).
  String? get location =>
      file == null ? null : (line == null ? file : '$file:$line');

  Map<String, Object?> toJson() => {
    'raw': raw,
    if (file != null) 'file': file,
    if (line != null) 'line': line,
    if (column != null) 'column': column,
    if (function != null) 'function': function,
    'inProject': inProject,
  };

  static TelemetryFrame fromJson(Map<String, Object?> m) => TelemetryFrame(
    raw: m['raw'] as String? ?? '',
    file: m['file'] as String?,
    line: (m['line'] as num?)?.toInt(),
    column: (m['column'] as num?)?.toInt(),
    function: m['function'] as String?,
    inProject: m['inProject'] == true,
  );
}

/// Erro estruturado anexado ao evento.
class TelemetryError {
  const TelemetryError({
    required this.type,
    required this.message,
    this.stack,
    this.frames = const [],
  });

  /// `RangeError`, `TypeError`, `Test failed`, `Warning`...
  final String type;
  final String message;

  /// Stack cru (texto), quando houver.
  final String? stack;
  final List<TelemetryFrame> frames;

  /// Primeiro frame do projeto (é ele que entra no fingerprint e na UI).
  TelemetryFrame? get projectFrame {
    for (final f in frames) {
      if (f.inProject) return f;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'type': type,
    'message': message,
    if (stack != null) 'stack': stack,
    'frames': [for (final f in frames) f.toJson()],
  };

  static TelemetryError fromJson(Map<String, Object?> m) => TelemetryError(
    type: m['type'] as String? ?? 'Error',
    message: m['message'] as String? ?? '',
    stack: m['stack'] as String?,
    frames: [
      for (final f in (m['frames'] as List? ?? const []))
        TelemetryFrame.fromJson((f as Map).cast<String, Object?>()),
    ],
  );
}

class TelemetryEvent {
  const TelemetryEvent({
    required this.runId,
    required this.ts,
    required this.stream,
    required this.severity,
    required this.body,
    this.id,
    this.attrs = const {},
    this.error,
    this.fingerprint,
    this.traceId,
    this.spanId,
    this.requestId,
    this.rawLineOffset,
    this.repeat = 1,
  });

  /// `e_` + base36; `null` antes de persistir.
  final String? id;
  final String runId;
  final DateTime ts;
  final TelemetryStream stream;
  final TelemetrySeverity severity;

  /// Mensagem principal (`msg` do JSON, a linha do erro, ou a linha crua).
  final String body;

  /// Atributos do JSON (tudo que não é campo conhecido) ou do OTLP.
  final Map<String, Object?> attrs;
  final TelemetryError? error;

  /// Só eventos com [error] têm fingerprint.
  final String? fingerprint;
  final String? traceId;
  final String? spanId;
  final String? requestId;

  /// Índice da linha no scrollback da aba de origem ("ver no terminal").
  final int? rawLineOffset;

  /// Quantas ocorrências este evento representa (Flutter suprime repetições
  /// e imprime "repetido N×"; o parser incrementa em vez de duplicar).
  final int repeat;

  bool get isError => error != null;

  /// Atributo `probe` (sondas temporárias do agente), se houver.
  String? get probe => attrs['probe']?.toString();

  TelemetryEvent copyWith({
    String? id,
    String? fingerprint,
    int? repeat,
    int? rawLineOffset,
    TelemetryError? error,
  }) => TelemetryEvent(
    id: id ?? this.id,
    runId: runId,
    ts: ts,
    stream: stream,
    severity: severity,
    body: body,
    attrs: attrs,
    error: error ?? this.error,
    fingerprint: fingerprint ?? this.fingerprint,
    traceId: traceId,
    spanId: spanId,
    requestId: requestId,
    rawLineOffset: rawLineOffset ?? this.rawLineOffset,
    repeat: repeat ?? this.repeat,
  );
}
