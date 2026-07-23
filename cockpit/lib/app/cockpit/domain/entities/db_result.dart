import 'dart:convert';
import 'dart:typed_data';

/// Coluna de um resultado: nome + tipo declarado pelo engine (texto livre,
/// ex.: `INTEGER`, `text`, `timestamptz` — exibição/JSON, sem semântica).
class DbColumn {
  const DbColumn(this.name, this.type);
  final String name;
  final String type;

  Map<String, Object?> toJson() => {'name': name, 'type': type};
}

/// Resultado normalizado de uma query — o contrato que grid e CLI conhecem.
///
/// Células são restritas ao conjunto normalizado (responsabilidade do driver):
/// `null | int | double | bool | String | DateTime | Uint8List` (blob).
class DbResult {
  const DbResult({
    required this.columns,
    required this.rows,
    required this.elapsed,
    this.truncated = false,
    this.affectedRows,
  });

  final List<DbColumn> columns;
  final List<List<Object?>> rows;
  final Duration elapsed;

  /// True quando o `limit` cortou o cursor — nunca truncar em silêncio.
  final bool truncated;

  /// Presente só em DML (`execute`).
  final int? affectedRows;

  /// Forma JSON da CLI (`{"ok": {...}}` fica por conta do chamador). Blobs
  /// não trafegam: viram marcador com o tamanho; DateTime vira ISO-8601.
  Map<String, Object?> toJson() => {
    'columns': [for (final c in columns) c.toJson()],
    'rows': [
      for (final r in rows) [for (final v in r) _cellToJson(v)],
    ],
    'rowCount': rows.length,
    'truncated': truncated,
    'elapsedMs': elapsed.inMilliseconds,
    if (affectedRows != null) 'affectedRows': affectedRows,
  };

  static Object? _cellToJson(Object? v) => switch (v) {
    null || int() || double() || bool() || String() => v,
    DateTime() => v.toIso8601String(),
    Uint8List() => {'blob': v.length},
    _ => v.toString(),
  };
}

/// Erro de execução normalizado (mesma forma na tab e na CLI).
class DbQueryException implements Exception {
  const DbQueryException(this.kind, this.message);

  /// Categoria estável pra CLI/agente: `connection_failed`, `query_failed`,
  /// `timeout`, `unsupported_engine`, `unknown_connection`, `password_required`.
  final String kind;
  final String message;

  Map<String, Object?> toJson() => {
    'error': {'kind': kind, 'message': message},
  };

  String toJsonLine() => jsonEncode(toJson());

  @override
  String toString() => 'DbQueryException($kind): $message';
}
