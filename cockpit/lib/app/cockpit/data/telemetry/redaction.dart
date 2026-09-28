// Redação de segredos NA ENTRADA (plano 66, contrato do evento): nada de
// token chega na base, então nem a UI nem o agente conseguem vazar.

const redacted = '[redacted]';

final _secretKey = RegExp(
  r'^(authorization|proxy-authorization|cookie|set-cookie|x-api-key|api[-_]?key|'
  r'password|passwd|pwd|secret|client[-_]?secret|token|access[-_]?token|'
  r'refresh[-_]?token|id[-_]?token|private[-_]?key|session[-_]?id)$',
  caseSensitive: false,
);

final _secretText = [
  // JWT
  RegExp(r'eyJ[\w-]{8,}\.[\w-]{8,}\.[\w-]{8,}'),
  // Bearer / Basic
  RegExp(r'(?<=\b(?:Bearer|Basic)\s)[A-Za-z0-9+/=._-]{12,}'),
  // chaves com prefixo conhecido
  RegExp(r'\b(?:sk|pk|rk|ghp|gho|xox[abp]|AKIA)[-_][A-Za-z0-9_-]{12,}'),
  RegExp(r'\bAKIA[0-9A-Z]{16}\b'),
  // password=... / token=... em query string ou texto
  RegExp(
    r'(?<=(?:password|passwd|token|secret|api[-_]?key)=)[^&\s"]+',
    caseSensitive: false,
  ),
];

bool isSecretKey(String key) => _secretKey.hasMatch(key.trim());

/// Mascara padrões de segredo dentro de texto livre.
String redactText(String text) {
  var out = text;
  for (final re in _secretText) {
    out = out.replaceAll(re, redacted);
  }
  return out;
}

/// Mascara valores de chaves sensíveis (recursivo) e padrões nos textos.
Map<String, Object?> redactAttrs(Map<String, Object?> attrs) => attrs.map(
  (k, v) => MapEntry(k, isSecretKey(k) ? redacted : _redactValue(v)),
);

Object? _redactValue(Object? v) => switch (v) {
  String s => redactText(s),
  Map m => redactAttrs(m.cast<String, Object?>()),
  List l => [for (final e in l) _redactValue(e)],
  _ => v,
};
