/// Entidades do LSP usadas pela UI e pelo gateway — desacopladas do wire
/// JSON-RPC. Posições seguem a convenção do LSP: **base 0**, e `character` é
/// contado em **code units UTF-16** (que é a mesma unidade da `String` Dart e
/// dos offsets do Flutter — ver `CodeEditingController.offsetFor`).
library;

/// Posição num documento. `line` e `character` são base 0 (LSP).
class LspPosition {
  const LspPosition(this.line, this.character);

  final int line;
  final int character;

  factory LspPosition.fromJson(Map<String, dynamic> json) => LspPosition(
    (json['line'] as num?)?.toInt() ?? 0,
    (json['character'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {'line': line, 'character': character};
}

/// Intervalo `[start, end)` num documento.
class LspRange {
  const LspRange(this.start, this.end);

  final LspPosition start;
  final LspPosition end;

  factory LspRange.fromJson(Map<String, dynamic> json) => LspRange(
    LspPosition.fromJson((json['start'] as Map).cast<String, dynamic>()),
    LspPosition.fromJson((json['end'] as Map).cast<String, dynamic>()),
  );

  Map<String, dynamic> toJson() => {
    'start': start.toJson(),
    'end': end.toJson(),
  };
}

/// Severidade do diagnostic (LSP DiagnosticSeverity, base 1).
enum LspSeverity {
  error,
  warning,
  info,
  hint;

  /// Mapeia o inteiro do wire (1=error … 4=hint). Default `error` (defensivo:
  /// um diagnostic sem severity é tratado como o mais grave).
  static LspSeverity fromWire(Object? value) {
    return switch ((value as num?)?.toInt()) {
      2 => LspSeverity.warning,
      3 => LspSeverity.info,
      4 => LspSeverity.hint,
      _ => LspSeverity.error,
    };
  }
}

/// Um diagnostic publicado pelo servidor (`textDocument/publishDiagnostics`).
class LspDiagnostic {
  const LspDiagnostic({
    required this.range,
    required this.severity,
    required this.message,
    this.source,
    this.code,
  });

  final LspRange range;
  final LspSeverity severity;
  final String message;

  /// Origem (ex.: `dart`, `eslint`). Mostrado junto da mensagem quando presente.
  final String? source;

  /// Código do diagnostic (ex.: `unused_import`). Pode ser String ou número.
  final String? code;

  factory LspDiagnostic.fromJson(Map<String, dynamic> json) => LspDiagnostic(
    range: LspRange.fromJson((json['range'] as Map).cast<String, dynamic>()),
    severity: LspSeverity.fromWire(json['severity']),
    message: (json['message'] as String?)?.trim() ?? '',
    source: json['source'] as String?,
    code: json['code']?.toString(),
  );
}

/// Conjunto de diagnostics de um documento (`uri`) numa publicação.
class LspDiagnosticsBatch {
  const LspDiagnosticsBatch({required this.uri, required this.diagnostics});

  /// URI do documento (`file:///...`).
  final String uri;
  final List<LspDiagnostic> diagnostics;
}
