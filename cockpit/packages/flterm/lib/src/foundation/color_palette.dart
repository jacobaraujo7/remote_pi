import 'dart:collection';

import 'package:flutter/painting.dart';
import 'package:libghostty/libghostty.dart'
    show RgbColor, defaultColorPalette, generateColorPalette;
import 'package:meta/meta.dart';

List<RgbColor> _basePalette(List<Color> ansiColors) {
  final palette = defaultColorPalette();
  for (var i = 0; i < ansiColors.length; i++) {
    palette[i] = _toRgbColor(ansiColors[i]);
  }
  return palette;
}

Color _toColor(RgbColor color) => Color(color.toArgb32);

RgbColor _toRgbColor(Color color) {
  return RgbColor(
    (color.r * 255.0).round(),
    (color.g * 255.0).round(),
    (color.b * 255.0).round(),
  );
}

void _validateAnsi(List<Color> ansiColors) {
  if (ansiColors.length != 16) {
    throw ArgumentError.value(
      ansiColors.length,
      'ansiColors',
      'must contain exactly 16 colors',
    );
  }
}

/// The default background, foreground, and 256-color palette for a terminal.
///
/// Indices 0–15 hold the 16 ANSI base colors. Indices 16–255 hold the
/// extended palette produced by one of two modes:
///
/// - Default constructor: the standard xterm 6×6×6 RGB cube (16–231) plus
///   a 24-step grayscale ramp (232–255), matching mainstream terminal
///   defaults.
/// - [ColorPalette.generated]: indices 16–255 are derived from
///   [background], [foreground], and the 16 base colors using libghostty's
///   terminal palette generation.
///
/// ```dart
/// final palette = ColorPalette(
///   ansiColors: const [Color(0xFF1D1F21), /* ...14 more... */ Color(0xFFEAEAEA)],
///   background: const Color(0xFF1D1F21),
///   foreground: const Color(0xFFC5C8C6),
/// );
/// final red = palette[1];
/// ```
@immutable
final class ColorPalette {
  /// Default canvas color used by cells with no explicit background.
  final Color background;

  /// Default text color used by cells with no explicit foreground.
  final Color foreground;

  final bool _generated;
  final bool _harmonious;
  final List<Color> _colors;

  /// Builds a palette with the xterm cube for indices 16–255.
  ///
  /// [ansiColors] must contain exactly 16 entries.
  factory ColorPalette({
    required List<Color> ansiColors,
    required Color background,
    required Color foreground,
  }) {
    _validateAnsi(ansiColors);
    return ColorPalette._(
      background: background,
      foreground: foreground,
      colors: List<Color>.unmodifiable(_basePalette(ansiColors).map(_toColor)),
      generated: false,
      harmonious: false,
    );
  }

  /// Builds a palette whose indices 16–255 are generated from [ansiColors],
  /// [background], and [foreground] using libghostty's terminal palette rules.
  ///
  /// Indices 0–15 are always preserved from [ansiColors]. For light themes,
  /// [harmonious] controls whether generated entries keep the theme's
  /// background-to-foreground orientation; when false, the generated cube and
  /// grayscale ramp run dark-to-light.
  ///
  /// [ansiColors] must contain exactly 16 entries.
  factory ColorPalette.generated({
    required List<Color> ansiColors,
    required Color background,
    required Color foreground,
    bool harmonious = false,
  }) {
    _validateAnsi(ansiColors);
    return ColorPalette._(
      background: background,
      foreground: foreground,
      colors: List<Color>.unmodifiable(
        generateColorPalette(
          base: _basePalette(ansiColors),
          background: _toRgbColor(background),
          foreground: _toRgbColor(foreground),
          harmonious: harmonious,
        ).map(_toColor),
      ),
      generated: true,
      harmonious: harmonious,
    );
  }

  const ColorPalette._({
    required this._colors,
    required this.background,
    required this.foreground,
    required this._generated,
    required this._harmonious,
  }) : assert(_colors.length == 256, 'palette must contain exactly 256 colors');

  /// The 16 ANSI base colors (indices 0–15) supplied at construction.
  List<Color> get ansiColors => UnmodifiableListView(_colors.take(16));

  @override
  int get hashCode =>
      Object.hash(background, foreground, Object.hashAll(_colors));

  @override
  bool operator ==(Object other) {
    if (other is! ColorPalette) return false;
    if (background != other.background) return false;
    if (foreground != other.foreground) return false;
    for (var i = 0; i < 256; i++) {
      if (_colors[i] != other._colors[i]) return false;
    }
    return true;
  }

  /// Returns the [Color] at the given palette [index] (0–255).
  Color operator [](int index) => _colors[index];

  /// Returns a copy of this palette with the given fields replaced.
  ///
  /// Preserves the construction mode: if this palette was built via
  /// [ColorPalette.generated], the copy is generated too (with the same
  /// [harmonious] setting). Otherwise the copy uses the xterm cube.
  ColorPalette copyWith({
    List<Color>? ansiColors,
    Color? background,
    Color? foreground,
  }) {
    final newAnsi = ansiColors ?? this.ansiColors;
    final newBg = background ?? this.background;
    final newFg = foreground ?? this.foreground;
    if (_generated) {
      return ColorPalette.generated(
        ansiColors: newAnsi,
        background: newBg,
        foreground: newFg,
        harmonious: _harmonious,
      );
    }
    return ColorPalette(
      ansiColors: newAnsi,
      background: newBg,
      foreground: newFg,
    );
  }

  /// Linearly interpolates between two palettes.
  ///
  /// [background], [foreground], and each of the 256 entries are interpolated
  /// independently via [Color.lerp]. Used by `TerminalTheme.lerp` for animated
  /// theme transitions; the per-entry lerp avoids regenerating the extended
  /// palette every frame.
  ///
  /// The resulting palette is not tagged as generated even if both inputs
  /// were; lerp always produces a plain palette whose [copyWith] uses the
  /// xterm cube.
  static ColorPalette? lerp(ColorPalette? begin, ColorPalette? end, double t) {
    if (identical(begin, end)) return begin;
    if (begin == null || end == null) return t < 0.5 ? begin : end;
    return ColorPalette._(
      background: Color.lerp(begin.background, end.background, t)!,
      foreground: Color.lerp(begin.foreground, end.foreground, t)!,
      colors: List<Color>.unmodifiable(
        List<Color>.generate(256, (i) => Color.lerp(begin[i], end[i], t)!),
      ),
      generated: false,
      harmonious: false,
    );
  }
}
