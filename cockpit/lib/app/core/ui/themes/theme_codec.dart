import 'package:flutter/widgets.dart';

/// Erro de parse de um tema em JSON. Carrega o **caminho** do campo (ex.:
/// `variants.dark.ui.accent`) pra UI conseguir dizer onde o arquivo quebrou.
/// Segue a regra de camadas: é tipo, não frase — a tradução mora na UI.
@immutable
class ThemeParseError implements Exception {
  const ThemeParseError(this.kind, {required this.path, this.value});

  final ThemeParseErrorKind kind;

  /// Caminho pontuado dentro do JSON, para apontar o campo culpado.
  final String path;

  /// Valor cru encontrado (quando existe), interpolado na mensagem.
  final String? value;

  @override
  String toString() => 'ThemeParseError($kind at $path, value: $value)';
}

enum ThemeParseErrorKind {
  notAnObject,
  missingField,
  badColor,
  unknownBase,
  noVariants,
}

/// Lê uma cor no formato **CSS hex**: `#RGB`, `#RRGGBB` ou `#RRGGBBAA`.
///
/// Deliberadamente não aceita o `0xAARRGGBB` do Dart: quem escreve tema à mão
/// (ou converte de um tema de editor) pensa em hex CSS, com o alpha **no fim**.
Color parseHexColor(String raw, {required String path}) {
  var hex = raw.trim();
  if (hex.startsWith('#')) hex = hex.substring(1);
  // #RGB → #RRGGBB
  if (hex.length == 3) {
    hex = hex.split('').map((c) => '$c$c').join();
  }
  if (hex.length == 6) hex = '${hex}FF'; // opaco por padrão
  if (hex.length != 8 || !RegExp(r'^[0-9a-fA-F]{8}$').hasMatch(hex)) {
    throw ThemeParseError(ThemeParseErrorKind.badColor, path: path, value: raw);
  }
  // JSON é RRGGBBAA; o Color do Dart é AARRGGBB.
  final rgba = int.parse(hex, radix: 16);
  final argb = ((rgba & 0xFF) << 24) | (rgba >> 8);
  return Color(argb);
}

/// Serializa uma cor como `#RRGGBB` (ou `#RRGGBBAA` quando translúcida).
String encodeHexColor(Color color) {
  String hex2(double channel) =>
      (channel * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  final rgb = '${hex2(color.r)}${hex2(color.g)}${hex2(color.b)}';
  final alpha = (color.a * 255).round();
  return alpha == 255 ? '#$rgb' : '#$rgb${hex2(color.a)}';
}

/// Lê uma cor de [map] em [key], caindo em [fallback] quando ausente.
///
/// A ausência ser legal é o que faz o `extends` funcionar: um tema declara só
/// os tokens que muda e herda o resto da base.
Color colorOr(
  Map<String, Object?> map,
  String key,
  Color fallback, {
  required String path,
}) {
  final raw = map[key];
  if (raw == null) return fallback;
  if (raw is! String) {
    throw ThemeParseError(
      ThemeParseErrorKind.badColor,
      path: '$path.$key',
      value: '$raw',
    );
  }
  return parseHexColor(raw, path: '$path.$key');
}

/// Casting defensivo de um nó do JSON para objeto.
Map<String, Object?> objectAt(
  Map<String, Object?> map,
  String key, {
  required String path,
}) {
  final node = map[key];
  if (node == null) return const {};
  if (node is! Map<String, Object?>) {
    throw ThemeParseError(ThemeParseErrorKind.notAnObject, path: '$path.$key');
  }
  return node;
}
