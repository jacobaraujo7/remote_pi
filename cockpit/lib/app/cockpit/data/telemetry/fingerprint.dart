// Fingerprint de erro (plano 66): tipo + mensagem normalizada + primeiro
// frame do projeto. Estável sob variação de ids/números/caminhos, diferente
// sob frame diferente. É a chave de agrupamento da aba e da triagem.

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../domain/entities/telemetry_event.dart';

final _uuid = RegExp(
  r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
);
final _ulid = RegExp(r'\b[0-9A-HJKMNP-TV-Z]{26}\b');
final _absPath = RegExp(r'(?:[A-Za-z]:\\|/)(?:[\w.@-]+[\\/])+[\w.@-]+');
final _quoted = RegExp('"[^"]*"|\'[^\']*\'|`[^`]*`');
// Qualquer token com dígito (ids curtos como `91c0`, `sku88`, `12:30`).
final _numeric = RegExp(r'\b\w*\d\w*\b');
final _ws = RegExp(r'\s+');

/// Mensagem com o dado variável mascarado por `*`.
String normalizeMessage(String message) => message
    .replaceAll(_uuid, '*')
    .replaceAll(_ulid, '*')
    .replaceAll(_absPath, '*')
    .replaceAll(_quoted, '*')
    .replaceAll(_numeric, '*')
    .replaceAll(_ws, ' ')
    .trim()
    .toLowerCase();

/// SHA-1 hex do fingerprint. [frame] é o primeiro frame do projeto
/// (`null` quando o erro não tem stack do projeto).
String fingerprintOf(TelemetryError error) {
  final loc = error.projectFrame?.location ?? '';
  final input = '${error.type}\n${normalizeMessage(error.message)}\n$loc';
  return sha1.convert(utf8.encode(input)).toString();
}
