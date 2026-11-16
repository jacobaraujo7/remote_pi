import 'dart:convert';

/// Valor informado no editor. Existe apenas em memória durante a sessão.
enum HttpRuntimeValueType { string, number, boolean, json }

enum HttpRuntimeValidationError {
  invalidNumber,
  nonFiniteNumber,
  invalidBoolean,
  invalidJson,
}

class HttpRuntimeVariable {
  const HttpRuntimeVariable(this.input, this.type);

  final String input;
  final HttpRuntimeValueType type;

  /// O HTTP Client interpola texto. O tipo controla a validação e a forma
  /// canônica usada na interpolação, sem modificar a definição original.
  String get value => switch (type) {
    HttpRuntimeValueType.string => input,
    HttpRuntimeValueType.number => '${num.parse(input.trim())}',
    HttpRuntimeValueType.boolean =>
      input.trim().toLowerCase() == 'true' ? 'true' : 'false',
    HttpRuntimeValueType.json => jsonEncode(jsonDecode(input)),
  };

  HttpRuntimeValidationError? get validationError {
    try {
      switch (type) {
        case HttpRuntimeValueType.string:
          break;
        case HttpRuntimeValueType.number:
          final parsed = num.parse(input.trim());
          if (!parsed.isFinite) {
            return HttpRuntimeValidationError.nonFiniteNumber;
          }
        case HttpRuntimeValueType.boolean:
          if (!{'true', 'false'}.contains(input.trim().toLowerCase())) {
            return HttpRuntimeValidationError.invalidBoolean;
          }
        case HttpRuntimeValueType.json:
          jsonDecode(input);
      }
      return null;
    } on FormatException {
      return type == HttpRuntimeValueType.json
          ? HttpRuntimeValidationError.invalidJson
          : HttpRuntimeValidationError.invalidNumber;
    }
  }

  static HttpRuntimeValueType inferType(String? value) {
    if (value == null) return HttpRuntimeValueType.string;
    final trimmed = value.trim();
    if (trimmed == 'true' || trimmed == 'false') {
      return HttpRuntimeValueType.boolean;
    }
    if (num.tryParse(trimmed) != null) return HttpRuntimeValueType.number;
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      try {
        jsonDecode(trimmed);
        return HttpRuntimeValueType.json;
      } on FormatException {
        // Texto comum que parece JSON incompleto.
      }
    }
    return HttpRuntimeValueType.string;
  }
}
