import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Tipografia do Cockpit — espelha o design: Space Grotesk (display/títulos),
/// Hanken Grotesk (UI/texto), JetBrains Mono (código). Servidas via
/// `google_fonts` (runtime + cache), sem bundle de .ttf.
@immutable
class AppTypography extends ThemeExtension<AppTypography> {
  const AppTypography({
    required this.display,
    required this.title,
    required this.body,
    required this.label,
    required this.tab,
    required this.mono,
  });

  /// Space Grotesk — títulos grandes (heading do transcript).
  final TextStyle display;

  /// Space Grotesk — nomes de workspace/aba/seção.
  final TextStyle title;

  /// Hanken Grotesk — corpo do transcript e inputs.
  final TextStyle body;

  /// Hanken Grotesk — rótulos pequenos.
  final TextStyle label;

  /// Space Grotesk — texto das abas.
  final TextStyle tab;

  /// JetBrains Mono — código, args de tool, métricas.
  final TextStyle mono;

  /// Monta a tipografia. Sem args = defaults do design. [uiFont]/[monoFont]
  /// vazios mantêm Space Grotesk/Hanken e JetBrains Mono; preenchidos trocam a
  /// família (resolução pelo SO). [interfaceSize] escala toda a UI
  /// proporcionalmente (baseline 14); [codeSize] define o tamanho do mono.
  factory AppTypography.build({
    String? uiFont,
    String? monoFont,
    double interfaceSize = 14,
    double codeSize = 13,
  }) {
    final hasUi = uiFont != null && uiFont.trim().isNotEmpty;
    final hasMono = monoFont != null && monoFont.trim().isNotEmpty;
    // Display/títulos: Space Grotesk por padrão; corpo/rótulos: Hanken. Com uma
    // fonte custom de interface, ela manda em tudo.
    final TextStyle displayBase = hasUi
        ? TextStyle(fontFamily: uiFont)
        : GoogleFonts.spaceGrotesk();
    final TextStyle ui = hasUi
        ? TextStyle(fontFamily: uiFont)
        : GoogleFonts.hankenGrotesk();
    final TextStyle mono = hasMono
        ? TextStyle(fontFamily: monoFont)
        : GoogleFonts.jetBrainsMono();

    final s = interfaceSize / 14.0; // baseline = 14
    return AppTypography(
      display: displayBase.copyWith(
        fontSize: 22 * s,
        fontWeight: FontWeight.w600,
        height: 1.25,
        letterSpacing: -0.2,
      ),
      title: displayBase.copyWith(fontSize: 13 * s, fontWeight: FontWeight.w600),
      body: ui.copyWith(fontSize: 14.5 * s, height: 1.6),
      label: ui.copyWith(fontSize: 12 * s, height: 1.3),
      tab: displayBase.copyWith(fontSize: 12.5 * s, fontWeight: FontWeight.w500),
      mono: mono.copyWith(fontSize: codeSize, height: 1.55),
    );
  }

  @override
  AppTypography copyWith({
    TextStyle? display,
    TextStyle? title,
    TextStyle? body,
    TextStyle? label,
    TextStyle? tab,
    TextStyle? mono,
  }) {
    return AppTypography(
      display: display ?? this.display,
      title: title ?? this.title,
      body: body ?? this.body,
      label: label ?? this.label,
      tab: tab ?? this.tab,
      mono: mono ?? this.mono,
    );
  }

  @override
  AppTypography lerp(ThemeExtension<AppTypography>? other, double t) {
    if (other is! AppTypography) return this;
    return AppTypography(
      display: TextStyle.lerp(display, other.display, t)!,
      title: TextStyle.lerp(title, other.title, t)!,
      body: TextStyle.lerp(body, other.body, t)!,
      label: TextStyle.lerp(label, other.label, t)!,
      tab: TextStyle.lerp(tab, other.tab, t)!,
      mono: TextStyle.lerp(mono, other.mono, t)!,
    );
  }
}
