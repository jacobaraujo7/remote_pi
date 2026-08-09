import 'package:cockpit/app/core/ui/themes/theme_codec.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';

/// Tokens de cor do Cockpit — espelham `tokens.css` do design (dark pro-tool,
/// accent azul Remote Pi). Lidos via `context.colors.<token>`.
@immutable
class AppColors {
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
    required this.gitStaged,
    required this.gitUntracked,
    required this.gitDeleted,
    required this.gitConflict,
    required this.scrim,
    required this.shadow,
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

  // Git status (file tree). Modificado reusa [warn] (âmbar, mesma da branch).
  final Color gitStaged; // staged no index → verde
  final Color gitUntracked; // novo / não-rastreado → azul
  final Color gitDeleted; // removido → vermelho
  final Color gitConflict; // conflito de merge → laranja

  // Overlays. Ambos são translúcidos: o alpha é parte do token.
  final Color scrim; // barrierColor de dialog/palette
  final Color shadow; // sombra projetada de superfície flutuante

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
    gitStaged: Color(0xFF3FB868),
    gitUntracked: Color(0xFF4F9DF0),
    gitDeleted: Color(0xFFE5484D),
    gitConflict: Color(0xFFF0883E),
    scrim: Color(0x99000000),
    shadow: Color(0x55000000),
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
    gitStaged: Color(0xFF2E9E54),
    gitUntracked: Color(0xFF2F6FF0),
    gitDeleted: Color(0xFFD32F2F),
    gitConflict: Color(0xFFD9730D),
    // No light o preto puro pesa: scrim mais leve e sombra mais discreta.
    scrim: Color(0x66000000),
    shadow: Color(0x33000000),
  );

  /// Lê os tokens de [json], herdando de [base] tudo que o arquivo não declarar.
  ///
  /// Essa herança é o que torna tema custom viável de escrever à mão: 25 tokens
  /// é muito pra pedir de uma vez, então na prática um tema declara `accent` +
  /// meia dúzia de superfícies e o resto vem da base.
  factory AppColors.fromJson(
    Map<String, Object?> json, {
    required AppColors base,
    String path = 'ui',
  }) {
    Color read(String key, Color fallback) =>
        colorOr(json, key, fallback, path: path);
    return AppColors(
      bg: read('bg', base.bg),
      panel: read('panel', base.panel),
      panel2: read('panel2', base.panel2),
      panel3: read('panel3', base.panel3),
      border: read('border', base.border),
      border2: read('border2', base.border2),
      text: read('text', base.text),
      text2: read('text2', base.text2),
      text3: read('text3', base.text3),
      text4: read('text4', base.text4),
      accent: read('accent', base.accent),
      accentSoft: read('accentSoft', base.accentSoft),
      accentText: read('accentText', base.accentText),
      online: read('online', base.online),
      ok: read('ok', base.ok),
      error: read('error', base.error),
      warn: read('warn', base.warn),
      edited: read('edited', base.edited),
      editedBg: read('editedBg', base.editedBg),
      gitStaged: read('gitStaged', base.gitStaged),
      gitUntracked: read('gitUntracked', base.gitUntracked),
      gitDeleted: read('gitDeleted', base.gitDeleted),
      gitConflict: read('gitConflict', base.gitConflict),
      scrim: read('scrim', base.scrim),
      shadow: read('shadow', base.shadow),
    );
  }

  /// Serializa **todos** os tokens (export sempre gera arquivo completo, mesmo
  /// que o tema tenha sido escrito com `extends` — assim o export é autônomo).
  Map<String, Object?> toJson() => {
    'bg': encodeHexColor(bg),
    'panel': encodeHexColor(panel),
    'panel2': encodeHexColor(panel2),
    'panel3': encodeHexColor(panel3),
    'border': encodeHexColor(border),
    'border2': encodeHexColor(border2),
    'text': encodeHexColor(text),
    'text2': encodeHexColor(text2),
    'text3': encodeHexColor(text3),
    'text4': encodeHexColor(text4),
    'accent': encodeHexColor(accent),
    'accentSoft': encodeHexColor(accentSoft),
    'accentText': encodeHexColor(accentText),
    'online': encodeHexColor(online),
    'ok': encodeHexColor(ok),
    'error': encodeHexColor(error),
    'warn': encodeHexColor(warn),
    'edited': encodeHexColor(edited),
    'editedBg': encodeHexColor(editedBg),
    'gitStaged': encodeHexColor(gitStaged),
    'gitUntracked': encodeHexColor(gitUntracked),
    'gitDeleted': encodeHexColor(gitDeleted),
    'gitConflict': encodeHexColor(gitConflict),
    'scrim': encodeHexColor(scrim),
    'shadow': encodeHexColor(shadow),
  };

  /// Igualdade por valor. Não é conveniência de teste: o [CockpitTheme] decide
  /// se repinta a árvore comparando estes objetos, e `buildTokens` devolve uma
  /// instância **nova** a cada build da raiz. Sem `==`, qualquer rebuild da raiz
  /// (troca de aba focada, estado do editor) invalidava todo consumidor de
  /// `context.colors` no app.
  List<Object?> get _props => [
    bg,
    panel,
    panel2,
    panel3,
    border,
    border2,
    text,
    text2,
    text3,
    text4,
    accent,
    accentSoft,
    accentText,
    online,
    ok,
    error,
    warn,
    edited,
    editedBg,
    gitStaged,
    gitUntracked,
    gitDeleted,
    gitConflict,
    scrim,
    shadow,
  ];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppColors && listEquals(_props, other._props);

  @override
  int get hashCode => Object.hashAll(_props);
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
    Color? gitStaged,
    Color? gitUntracked,
    Color? gitDeleted,
    Color? gitConflict,
    Color? scrim,
    Color? shadow,
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
      gitStaged: gitStaged ?? this.gitStaged,
      gitUntracked: gitUntracked ?? this.gitUntracked,
      gitDeleted: gitDeleted ?? this.gitDeleted,
      gitConflict: gitConflict ?? this.gitConflict,
      scrim: scrim ?? this.scrim,
      shadow: shadow ?? this.shadow,
    );
  }
}
