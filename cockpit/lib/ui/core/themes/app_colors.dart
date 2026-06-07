import 'package:flutter/material.dart';

/// Tokens de cor do Cockpit — espelham `tokens.css` do design (dark pro-tool,
/// accent azul Remote Pi). Lidos via `context.colors.<token>`.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.bg,
    required this.panel,
    required this.panel2,
    required this.panel3,
    required this.border,
    required this.border2,
    required this.text,
    required this.text2,
    required this.text3,
    required this.text4,
    required this.accent,
    required this.accentSoft,
    required this.accentText,
    required this.online,
    required this.ok,
    required this.error,
    required this.warn,
    required this.edited,
    required this.editedBg,
  });

  final Color bg; // app backdrop, deepest
  final Color panel; // pane / rail surface
  final Color panel2; // raised: composer, cards
  final Color panel3; // hover / inset code
  final Color border; // hairlines
  final Color border2; // stronger divider
  final Color text; // primary
  final Color text2; // secondary
  final Color text3; // tertiary / placeholder
  final Color text4; // faint, icons-at-rest
  final Color accent;
  final Color accentSoft;
  final Color accentText;
  final Color online; // the ONLY green
  final Color ok;
  final Color error;
  final Color warn;
  final Color edited; // recently-edited file accent
  final Color editedBg;

  static const AppColors dark = AppColors(
    bg: Color(0xFF0D0D0F),
    panel: Color(0xFF18181B),
    panel2: Color(0xFF1F1F23),
    panel3: Color(0xFF27272C),
    border: Color(0xFF26262A),
    border2: Color(0xFF323238),
    text: Color(0xFFECECEF),
    text2: Color(0xFF9B9BA4),
    text3: Color(0xFF6A6A73),
    text4: Color(0xFF46464D),
    accent: Color(0xFF2F6FF0),
    accentSoft: Color(0x332F6FF0),
    accentText: Color(0xFF7FAAFF),
    online: Color(0xFF3FB868),
    ok: Color(0xFF3FB868),
    error: Color(0xFFE5484D),
    warn: Color(0xFFE0A33A),
    edited: Color(0xFFC98A2B),
    editedBg: Color(0xFF2A210F),
  );

  /// Variante light — mesmos papéis, luminância invertida; accent azul mantido.
  static const AppColors light = AppColors(
    bg: Color(0xFFF5F5F7),
    panel: Color(0xFFFFFFFF),
    panel2: Color(0xFFF0F0F3),
    panel3: Color(0xFFE7E7EC),
    border: Color(0xFFE2E2E7),
    border2: Color(0xFFD1D1D8),
    text: Color(0xFF1A1A1F),
    text2: Color(0xFF5B5B66),
    text3: Color(0xFF8A8A94),
    text4: Color(0xFFB4B4BC),
    accent: Color(0xFF2F6FF0),
    accentSoft: Color(0x222F6FF0),
    accentText: Color(0xFF1F5FD6),
    online: Color(0xFF2E9E54),
    ok: Color(0xFF2E9E54),
    error: Color(0xFFD32F2F),
    warn: Color(0xFFB7791F),
    edited: Color(0xFFB7791F),
    editedBg: Color(0xFFFBF1DC),
  );

  @override
  AppColors copyWith({
    Color? bg,
    Color? panel,
    Color? panel2,
    Color? panel3,
    Color? border,
    Color? border2,
    Color? text,
    Color? text2,
    Color? text3,
    Color? text4,
    Color? accent,
    Color? accentSoft,
    Color? accentText,
    Color? online,
    Color? ok,
    Color? error,
    Color? warn,
    Color? edited,
    Color? editedBg,
  }) {
    return AppColors(
      bg: bg ?? this.bg,
      panel: panel ?? this.panel,
      panel2: panel2 ?? this.panel2,
      panel3: panel3 ?? this.panel3,
      border: border ?? this.border,
      border2: border2 ?? this.border2,
      text: text ?? this.text,
      text2: text2 ?? this.text2,
      text3: text3 ?? this.text3,
      text4: text4 ?? this.text4,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      accentText: accentText ?? this.accentText,
      online: online ?? this.online,
      ok: ok ?? this.ok,
      error: error ?? this.error,
      warn: warn ?? this.warn,
      edited: edited ?? this.edited,
      editedBg: editedBg ?? this.editedBg,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      bg: l(bg, other.bg),
      panel: l(panel, other.panel),
      panel2: l(panel2, other.panel2),
      panel3: l(panel3, other.panel3),
      border: l(border, other.border),
      border2: l(border2, other.border2),
      text: l(text, other.text),
      text2: l(text2, other.text2),
      text3: l(text3, other.text3),
      text4: l(text4, other.text4),
      accent: l(accent, other.accent),
      accentSoft: l(accentSoft, other.accentSoft),
      accentText: l(accentText, other.accentText),
      online: l(online, other.online),
      ok: l(ok, other.ok),
      error: l(error, other.error),
      warn: l(warn, other.warn),
      edited: l(edited, other.edited),
      editedBg: l(editedBg, other.editedBg),
    );
  }
}
