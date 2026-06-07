/// Modo de tema escolhido pelo usuário (mapeado pro `ThemeMode` do Flutter na
/// camada de UI; o domínio não importa Flutter).
enum AppThemeMode { system, light, dark }

/// Família do tema de syntax highlight do viewer de código. Cada família tem
/// variante light/dark, resolvida pelo brilho do app.
enum SyntaxThemeId { one, dracula, github }

/// Preferências do app, persistidas localmente (Hive). Imutável; mudanças via
/// [copyWith]. Fontes vazias (`null`) = usar os defaults do design.
class AppSettings {
  const AppSettings({
    this.themeMode = AppThemeMode.system,
    this.interfaceFont,
    this.interfaceSize = 14,
    this.codeFont,
    this.codeSize = 13,
    this.syntaxTheme = SyntaxThemeId.one,
    this.lastOpenAppId,
  });

  final AppThemeMode themeMode;

  /// Família da fonte da interface (`null`/vazio = Space Grotesk/Hanken).
  final String? interfaceFont;

  /// Tamanho base da UI (px). Os estilos escalam proporcionalmente.
  final double interfaceSize;

  /// Família da fonte de código (`null`/vazio = JetBrains Mono).
  final String? codeFont;

  /// Tamanho da fonte de código (px) — viewer/diff/terminal.
  final double codeSize;

  final SyntaxThemeId syntaxTheme;

  /// ID do último app usado para "Abrir" (ex: `'cursor'`, `'vscode'`, `'finder'`).
  final String? lastOpenAppId;

  AppSettings copyWith({
    AppThemeMode? themeMode,
    String? interfaceFont,
    bool clearInterfaceFont = false,
    double? interfaceSize,
    String? codeFont,
    bool clearCodeFont = false,
    double? codeSize,
    SyntaxThemeId? syntaxTheme,
    String? lastOpenAppId,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      interfaceFont: clearInterfaceFont
          ? null
          : (interfaceFont ?? this.interfaceFont),
      interfaceSize: interfaceSize ?? this.interfaceSize,
      codeFont: clearCodeFont ? null : (codeFont ?? this.codeFont),
      codeSize: codeSize ?? this.codeSize,
      syntaxTheme: syntaxTheme ?? this.syntaxTheme,
      lastOpenAppId: lastOpenAppId ?? this.lastOpenAppId,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'themeMode': themeMode.name,
    'interfaceFont': interfaceFont,
    'interfaceSize': interfaceSize,
    'codeFont': codeFont,
    'codeSize': codeSize,
    'syntaxTheme': syntaxTheme.name,
    if (lastOpenAppId != null) 'lastOpenAppId': lastOpenAppId,
  };

  factory AppSettings.fromJson(Map<dynamic, dynamic> json) {
    String? str(Object? v) {
      final s = (v as String?)?.trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    return AppSettings(
      themeMode: _enumByName(
        AppThemeMode.values,
        json['themeMode'],
        AppThemeMode.system,
      ),
      interfaceFont: str(json['interfaceFont']),
      interfaceSize: (json['interfaceSize'] as num?)?.toDouble() ?? 14,
      codeFont: str(json['codeFont']),
      codeSize: (json['codeSize'] as num?)?.toDouble() ?? 13,
      syntaxTheme: _enumByName(
        SyntaxThemeId.values,
        json['syntaxTheme'],
        SyntaxThemeId.one,
      ),
      lastOpenAppId: str(json['lastOpenAppId']),
    );
  }
}

T _enumByName<T extends Enum>(List<T> values, Object? raw, T fallback) {
  if (raw is! String) return fallback;
  for (final v in values) {
    if (v.name == raw) return v;
  }
  return fallback;
}
