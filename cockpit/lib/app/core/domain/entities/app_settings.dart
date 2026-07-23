/// Modo de tema escolhido pelo usuário (mapeado pro `ThemeMode` do Flutter na
/// camada de UI; o domínio não importa Flutter).
enum AppThemeMode { system, light, dark }

/// Família do tema de syntax highlight do viewer de código. Cada família tem
/// variante light/dark, resolvida pelo brilho do app.
enum SyntaxThemeId { one, dracula, github }

/// Motor VT usado por terminais criados daqui pra frente.
enum TerminalEngine { ghostty, xterm }

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
    this.soundEnabled = true,
    this.searchPanelHeight = 260,
    this.tasksPanelHeight = 200,
    this.enableAgent = false,
    this.railVisible = false,
    this.treeVisible = false,
    this.showCockpit = true,
    this.defaultTerminalProfileId,
    this.terminalEngine = TerminalEngine.ghostty,
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

  /// Tocar um chime curto quando um turno termina com a janela focada (chama
  /// atenção sem banner do SO). Editado na aba "Notifications".
  final bool soundEnabled;

  /// Altura (px) da área de resultados do painel de busca por conteúdo
  /// (find-in-files), ajustável arrastando a borda superior do painel.
  final double searchPanelHeight;

  /// Altura (px) da área de lista do subpane de Tasks (redimensionável).
  final double tasksPanelHeight;

  /// Habilita o suporte a **agentes** (abas de `pi`). Desligado por padrão em
  /// instalações novas (experiência terminal-first); ligado por migração para
  /// quem já usava agentes numa versão anterior (ver `HiveSettingsStore.load`).
  /// Com ela desligada, o app não oferece criar aba de agente (só terminal).
  final bool enableAgent;

  /// Visibilidade do painel esquerdo (rail de projetos). Persistido entre
  /// sessões; fechado por padrão em instalações novas.
  final bool railVisible;

  /// Visibilidade do painel direito (árvore de arquivos). Persistido entre
  /// sessões; fechado por padrão em instalações novas.
  final bool treeVisible;

  /// Mostra o workspace de sistema "Cockpit" (terminal-only, sem pasta) fixo no
  /// topo do rail. Ligado por padrão; desligar remove o slot e mata seus PTYs.
  /// Persistido; migração liga automático para quem já usava (ver
  /// `HiveSettingsStore.load`).
  final bool showCockpit;

  /// `id` do [TerminalProfile] padrão do `+` (plano 50), persistido sob
  /// `terminal.default_profile_id`. `null` = **comportamento atual**: o
  /// resolver cai no fallback de plataforma (Windows: PowerShell — cmd no ARM;
  /// POSIX: login shell). Guardamos só o `id` estável: os perfis são
  /// re-descobertos a cada boot, e um `id` que sumiu degrada pro fallback.
  final String? defaultTerminalProfileId;

  /// Motor padrão de novas abas/buffers. Abas existentes guardam o próprio
  /// motor no descritor de layout e não são recriadas ao trocar esta opção.
  final TerminalEngine terminalEngine;

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
    bool? soundEnabled,
    double? searchPanelHeight,
    double? tasksPanelHeight,
    bool? enableAgent,
    bool? railVisible,
    bool? treeVisible,
    bool? showCockpit,
    String? defaultTerminalProfileId,
    bool clearDefaultTerminalProfileId = false,
    TerminalEngine? terminalEngine,
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
      soundEnabled: soundEnabled ?? this.soundEnabled,
      searchPanelHeight: searchPanelHeight ?? this.searchPanelHeight,
      tasksPanelHeight: tasksPanelHeight ?? this.tasksPanelHeight,
      enableAgent: enableAgent ?? this.enableAgent,
      railVisible: railVisible ?? this.railVisible,
      treeVisible: treeVisible ?? this.treeVisible,
      showCockpit: showCockpit ?? this.showCockpit,
      defaultTerminalProfileId: clearDefaultTerminalProfileId
          ? null
          : (defaultTerminalProfileId ?? this.defaultTerminalProfileId),
      terminalEngine: terminalEngine ?? this.terminalEngine,
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
    if (!soundEnabled) 'soundEnabled': false,
    'searchPanelHeight': searchPanelHeight,
    'tasksPanelHeight': tasksPanelHeight,
    // Sempre gravado (mesmo quando false) para a migração distinguir "install
    // novo" (chave presente = false) de "upgrade sem a flag" (chave ausente).
    'enableAgent': enableAgent,
    if (railVisible) 'railVisible': true,
    if (treeVisible) 'treeVisible': true,
    // Sempre gravado: a migração distingue "install novo" (chave presente) de
    // "upgrade sem a flag" (chave ausente → liga automático).
    'showCockpit': showCockpit,
    // Só quando escolhido: a AUSÊNCIA da chave é o "sem padrão" → fallback de
    // plataforma. Nada a migrar (plano 50).
    if (defaultTerminalProfileId != null)
      'terminal.default_profile_id': defaultTerminalProfileId,
    'terminal.engine': terminalEngine.name,
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
      soundEnabled: json['soundEnabled'] as bool? ?? true,
      searchPanelHeight: (json['searchPanelHeight'] as num?)?.toDouble() ?? 260,
      tasksPanelHeight: (json['tasksPanelHeight'] as num?)?.toDouble() ?? 200,
      enableAgent: json['enableAgent'] as bool? ?? false,
      railVisible: json['railVisible'] as bool? ?? false,
      treeVisible: json['treeVisible'] as bool? ?? false,
      showCockpit: json['showCockpit'] as bool? ?? true,
      defaultTerminalProfileId: str(json['terminal.default_profile_id']),
      terminalEngine: _enumByName(
        TerminalEngine.values,
        json['terminal.engine'],
        TerminalEngine.ghostty,
      ),
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
