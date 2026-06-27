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
    this.terminalFont,
    this.syntaxTheme = SyntaxThemeId.one,
    this.pinUserMessage = true,
    this.lastOpenAppId,
    this.lspCommands = const <String, String>{},
    this.lspFormatters = const <String, String>{},
    this.formatOnSave = false,
    this.notificationsEnabled = true,
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

  /// Família da fonte do **terminal** (`null`/vazio = mono padrão do xterm). O
  /// tamanho segue [codeSize].
  final String? terminalFont;

  final SyntaxThemeId syntaxTheme;

  /// Fixa a mensagem do usuário no topo do chat enquanto a resposta rola
  /// (sticky header por turno).
  final bool pinUserMessage;

  /// ID do último app usado para "Abrir" (ex: `'cursor'`, `'vscode'`, `'finder'`).
  final String? lastOpenAppId;

  /// Override do comando do language server (LSP) por `languageId` (ex.:
  /// `'dart' → 'dart language-server'`). Vazio/ausente = usa o default do
  /// catálogo. Editado na seção "Language" das Configurações.
  final Map<String, String> lspCommands;

  /// Comando de formatador **externo** por `languageId`, com placeholder
  /// `%FILE%` (ex.: `'typescript' → 'prettier --write %FILE%'`). Quando
  /// presente, tem precedência sobre o formatting do LSP. Vazio = usa o LSP.
  final Map<String, String> lspFormatters;

  /// Formatar automaticamente ao salvar (Cmd+S).
  final bool formatOnSave;

  /// Disparar notificações do SO quando um agente termina um turno com a janela
  /// fora de foco. Editado na aba "Notifications" das Configurações.
  final bool notificationsEnabled;

  AppSettings copyWith({
    AppThemeMode? themeMode,
    String? interfaceFont,
    bool clearInterfaceFont = false,
    double? interfaceSize,
    String? codeFont,
    bool clearCodeFont = false,
    double? codeSize,
    String? terminalFont,
    bool clearTerminalFont = false,
    SyntaxThemeId? syntaxTheme,
    bool? pinUserMessage,
    String? lastOpenAppId,
    Map<String, String>? lspCommands,
    Map<String, String>? lspFormatters,
    bool? formatOnSave,
    bool? notificationsEnabled,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      interfaceFont: clearInterfaceFont
          ? null
          : (interfaceFont ?? this.interfaceFont),
      interfaceSize: interfaceSize ?? this.interfaceSize,
      codeFont: clearCodeFont ? null : (codeFont ?? this.codeFont),
      codeSize: codeSize ?? this.codeSize,
      terminalFont: clearTerminalFont
          ? null
          : (terminalFont ?? this.terminalFont),
      syntaxTheme: syntaxTheme ?? this.syntaxTheme,
      pinUserMessage: pinUserMessage ?? this.pinUserMessage,
      lastOpenAppId: lastOpenAppId ?? this.lastOpenAppId,
      lspCommands: lspCommands ?? this.lspCommands,
      lspFormatters: lspFormatters ?? this.lspFormatters,
      formatOnSave: formatOnSave ?? this.formatOnSave,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'themeMode': themeMode.name,
    'interfaceFont': interfaceFont,
    'interfaceSize': interfaceSize,
    'codeFont': codeFont,
    'codeSize': codeSize,
    'terminalFont': terminalFont,
    'syntaxTheme': syntaxTheme.name,
    'pinUserMessage': pinUserMessage,
    if (lastOpenAppId != null) 'lastOpenAppId': lastOpenAppId,
    if (lspCommands.isNotEmpty) 'lspCommands': lspCommands,
    if (lspFormatters.isNotEmpty) 'lspFormatters': lspFormatters,
    if (formatOnSave) 'formatOnSave': true,
    if (!notificationsEnabled) 'notificationsEnabled': false,
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
      terminalFont: str(json['terminalFont']),
      syntaxTheme: _enumByName(
        SyntaxThemeId.values,
        json['syntaxTheme'],
        SyntaxThemeId.one,
      ),
      pinUserMessage: json['pinUserMessage'] as bool? ?? true,
      lastOpenAppId: str(json['lastOpenAppId']),
      lspCommands: _strMap(json['lspCommands']),
      lspFormatters: _strMap(json['lspFormatters']),
      formatOnSave: json['formatOnSave'] as bool? ?? false,
      notificationsEnabled: json['notificationsEnabled'] as bool? ?? true,
    );
  }
}

Map<String, String> _strMap(Object? raw) {
  if (raw is! Map) return const <String, String>{};
  final out = <String, String>{};
  raw.forEach((k, v) {
    if (k is String && v is String && v.trim().isNotEmpty) out[k] = v;
  });
  return out;
}

T _enumByName<T extends Enum>(List<T> values, Object? raw, T fallback) {
  if (raw is! String) return fallback;
  for (final v in values) {
    if (v.name == raw) return v;
  }
  return fallback;
}
