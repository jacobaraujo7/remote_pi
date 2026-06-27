import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:cockpit/app/core/domain/entities/lsp_diagnostic.dart';
import 'package:flutter/widgets.dart';

/// Paleta de **syntax highlight** do viewer de código. Mapeia os escopos do
/// highlight.js (className dos nós) para um punhado de cores semânticas, lidas
/// via `context.syntax`. É **independente do tema do app**: cada paleta traz seu
/// próprio [background], então o viewer fica consistente mesmo no light/dark.
@immutable
class SyntaxColors {
  const SyntaxColors({
    required this.background,
    required this.base,
    required this.comment,
    required this.keyword,
    required this.string,
    required this.number,
    required this.klass,
    required this.builtin,
    required this.function,
    required this.variable,
    required this.meta,
    required this.deletion,
  });

  final Color background; // fundo do viewer de código
  final Color base; // texto sem escopo
  final Color comment; // comentários (itálico)
  final Color keyword; // palavras-chave
  final Color string; // strings / regex de valor / adição (diff +)
  final Color number; // números e literais (true/false/null)
  final Color klass; // tipos / classes (`type` colidiria com ThemeExtension)
  final Color builtin; // built-ins
  final Color function; // títulos / nomes de função / seções
  final Color variable; // variáveis / atributos / tags / símbolos
  final Color meta; // meta / decorators / preprocessador
  final Color deletion; // diff -

  // --- One ------------------------------------------------------------------
  /// One Dark.
  static const SyntaxColors oneDark = SyntaxColors(
    background: Color(0xFF282C34),
    base: Color(0xFFABB2BF),
    comment: Color(0xFF7F848E),
    keyword: Color(0xFFC678DD),
    string: Color(0xFF98C379),
    number: Color(0xFFD19A66),
    klass: Color(0xFFE5C07B),
    builtin: Color(0xFF56B6C2),
    function: Color(0xFF61AFEF),
    variable: Color(0xFFE06C75),
    meta: Color(0xFF56B6C2),
    deletion: Color(0xFFE06C75),
  );

  /// One Light (Atom One Light).
  static const SyntaxColors oneLight = SyntaxColors(
    background: Color(0xFFFAFAFA),
    base: Color(0xFF383A42),
    comment: Color(0xFFA0A1A7),
    keyword: Color(0xFFA626A4),
    string: Color(0xFF50A14F),
    number: Color(0xFF986801),
    klass: Color(0xFFC18401),
    builtin: Color(0xFF0184BC),
    function: Color(0xFF4078F2),
    variable: Color(0xFFE45649),
    meta: Color(0xFF0184BC),
    deletion: Color(0xFFE45649),
  );

  // --- Dracula --------------------------------------------------------------
  /// Dracula (dark).
  static const SyntaxColors draculaDark = SyntaxColors(
    background: Color(0xFF282A36),
    base: Color(0xFFF8F8F2),
    comment: Color(0xFF6272A4),
    keyword: Color(0xFFFF79C6),
    string: Color(0xFFF1FA8C),
    number: Color(0xFFBD93F9),
    klass: Color(0xFF8BE9FD),
    builtin: Color(0xFF8BE9FD),
    function: Color(0xFF50FA7B),
    variable: Color(0xFFFFB86C),
    meta: Color(0xFFFF79C6),
    deletion: Color(0xFFFF5555),
  );

  /// Dracula light (Alucard-ish) — escurecido pra legibilidade sobre claro.
  static const SyntaxColors draculaLight = SyntaxColors(
    background: Color(0xFFF6F2FF),
    base: Color(0xFF2A2A37),
    comment: Color(0xFF8C8AA8),
    keyword: Color(0xFFC2268E),
    string: Color(0xFF6B7A1F),
    number: Color(0xFF7C3AED),
    klass: Color(0xFF0E7490),
    builtin: Color(0xFF0E7490),
    function: Color(0xFF1F8A4C),
    variable: Color(0xFFB45309),
    meta: Color(0xFFC2268E),
    deletion: Color(0xFFDC2626),
  );

  // --- GitHub ---------------------------------------------------------------
  /// GitHub Dark.
  static const SyntaxColors githubDark = SyntaxColors(
    background: Color(0xFF0D1117),
    base: Color(0xFFC9D1D9),
    comment: Color(0xFF8B949E),
    keyword: Color(0xFFFF7B72),
    string: Color(0xFFA5D6FF),
    number: Color(0xFF79C0FF),
    klass: Color(0xFFFFA657),
    builtin: Color(0xFF79C0FF),
    function: Color(0xFFD2A8FF),
    variable: Color(0xFFFFA657),
    meta: Color(0xFF7EE787),
    deletion: Color(0xFFFFA198),
  );

  /// GitHub Light.
  static const SyntaxColors githubLight = SyntaxColors(
    background: Color(0xFFFFFFFF),
    base: Color(0xFF24292F),
    comment: Color(0xFF6E7781),
    keyword: Color(0xFFCF222E),
    string: Color(0xFF0A3069),
    number: Color(0xFF0550AE),
    klass: Color(0xFF953800),
    builtin: Color(0xFF0550AE),
    function: Color(0xFF8250DF),
    variable: Color(0xFF953800),
    meta: Color(0xFF116329),
    deletion: Color(0xFF82071E),
  );

  /// Fallback usado por `context.syntax` fora da árvore com tema.
  static const SyntaxColors dark = oneDark;

  // --- Diagnostics (LSP) ----------------------------------------------------
  // Cores semânticas independentes da paleta (legíveis sobre dark e light),
  // usadas no squiggle e no ícone de severity do gutter.
  static const Color diagnosticError = Color(0xFFE5484D);
  static const Color diagnosticWarning = Color(0xFFF5A623);
  static const Color diagnosticInfo = Color(0xFF4C9AFF);
  static const Color diagnosticHint = Color(0xFF8B949E);

  /// Cor do sublinhado/ícone por severidade.
  static Color diagnosticColor(LspSeverity severity) => switch (severity) {
    LspSeverity.error => diagnosticError,
    LspSeverity.warning => diagnosticWarning,
    LspSeverity.info => diagnosticInfo,
    LspSeverity.hint => diagnosticHint,
  };

  /// Estilo de sublinhado ondulado para um range com diagnostic da [severity].
  /// É feito para `style.merge(...)` sobre o span de syntax (preserva a cor).
  static TextStyle underlineStyleFor(LspSeverity severity) => TextStyle(
    decoration: TextDecoration.underline,
    decorationStyle: TextDecorationStyle.wavy,
    decorationColor: diagnosticColor(severity),
  );

  /// Resolve a paleta pelo id escolhido **e o brilho do app** — cada família
  /// tem variante light/dark, então o highlight segue o tema (claro no claro).
  static SyntaxColors forId(SyntaxThemeId id, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return switch (id) {
      SyntaxThemeId.one => isDark ? oneDark : oneLight,
      SyntaxThemeId.dracula => isDark ? draculaDark : draculaLight,
      SyntaxThemeId.github => isDark ? githubDark : githubLight,
    };
  }

  /// Estilo de um escopo do highlight.js. `null` → herda o estilo base (texto
  /// sem realce). Comentários ganham itálico.
  TextStyle? styleFor(String scope) {
    final color = _colorFor(scope);
    if (color == null) return null;
    if (scope == 'comment' || scope == 'quote') {
      return TextStyle(color: color, fontStyle: FontStyle.italic);
    }
    return TextStyle(color: color);
  }

  Color? _colorFor(String scope) {
    switch (scope) {
      case 'comment':
      case 'quote':
        return comment;
      case 'keyword':
      case 'selector-tag':
        return keyword;
      case 'string':
      case 'regexp':
      case 'meta-string':
      case 'selector-attr':
      case 'selector-pseudo':
      case 'addition':
        return string;
      case 'number':
      case 'literal':
        return number;
      case 'type':
      case 'class':
      case 'title.class':
        return klass;
      case 'built_in':
      case 'builtin-name':
        return builtin;
      case 'title':
      case 'title.function':
      case 'function':
      case 'section':
        return function;
      case 'attr':
      case 'attribute':
      case 'variable':
      case 'template-variable':
      case 'symbol':
      case 'bullet':
      case 'name':
      case 'selector-id':
      case 'selector-class':
        return variable;
      case 'meta':
      case 'meta-keyword':
      case 'doctag':
      case 'tag':
        return meta;
      case 'deletion':
        return deletion;
      default:
        return null;
    }
  }

  SyntaxColors copyWith({
    Color? background,
    Color? base,
    Color? comment,
    Color? keyword,
    Color? string,
    Color? number,
    Color? klass,
    Color? builtin,
    Color? function,
    Color? variable,
    Color? meta,
    Color? deletion,
  }) {
    return SyntaxColors(
      background: background ?? this.background,
      base: base ?? this.base,
      comment: comment ?? this.comment,
      keyword: keyword ?? this.keyword,
      string: string ?? this.string,
      number: number ?? this.number,
      klass: klass ?? this.klass,
      builtin: builtin ?? this.builtin,
      function: function ?? this.function,
      variable: variable ?? this.variable,
      meta: meta ?? this.meta,
      deletion: deletion ?? this.deletion,
    );
  }
}
