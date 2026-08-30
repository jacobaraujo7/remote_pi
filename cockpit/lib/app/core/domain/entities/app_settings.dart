import 'package:cockpit/app/core/domain/entities/automation.dart';
import 'package:cockpit/app/core/domain/entities/sound_event.dart';

/// Modo de tema escolhido pelo usuário (mapeado pro `ThemeMode` do Flutter na
/// camada de UI; o domínio não importa Flutter).
enum AppThemeMode { system, light, dark }

/// Motor VT usado por terminais criados daqui pra frente.
enum TerminalEngine { ghostty, xterm }

/// Peso do traço da fonte do terminal.
///
/// Existe porque a **mesma** fonte, no mesmo tamanho, tem peso aparente
/// diferente conforme a densidade da tela: o Flutter/Skia no macOS rasteriza
/// sem hinting e com antialiasing em cinza, o que engorda os traços verticais
/// quando há poucos pixels por traço. Num monitor de DPR 1 o texto lê como
/// negrito; no Retina, não. Como a preferência é uma só para todos os monitores,
/// [auto] resolve por densidade em tempo de render (ver `resolveFor`).
enum TerminalFontWeight { auto, light, normal, medium, semiBold }

/// Layout inicial das mudanças no painel Source Control.
enum SourceControlViewMode { list, tree }

enum UpdateCheckFrequency { daily, weekly, monthly, never }

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
    this.terminalSize,
    this.terminalFontWeight = TerminalFontWeight.auto,
    this.themeId = 'cockpit',
    this.pinUserMessage = true,
    this.lastOpenAppId,
    this.lspCommands = const <String, String>{},
    this.lspFormatters = const <String, String>{},
    this.formatOnSave = false,
    this.notificationsEnabled = true,
    this.soundEvents = const <SoundEvent, bool>{},
    this.soundOverrides = const <SoundEvent, String>{},
    this.soundOnActiveTab = const <SoundEvent, bool>{},
    this.soundVolume = 50,
    this.searchPanelHeight = 260,
    this.tasksPanelHeight = 200,
    this.enableAgent = false,
    this.swapSidePanels = false,
    this.railVisible = false,
    this.treeVisible = false,
    this.showCockpit = true,
    this.launchAtStartup = false,
    this.defaultTerminalProfileId,
    this.terminalEngine = TerminalEngine.ghostty,
    this.locale,
    this.sourceControlViewMode = SourceControlViewMode.list,
    this.automationHarnessId,
    this.automationModelId,
    this.updateCheckFrequency = UpdateCheckFrequency.daily,
    this.lastUpdateCheckTime,
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

  /// Família da fonte do **terminal** (`null`/vazio = mono padrão do xterm).
  final String? terminalFont;

  /// Tamanho da fonte do terminal (px). `null` = herda [codeSize].
  ///
  /// Separado do código porque a densidade da tela muda o que é confortável: o
  /// mesmo valor que fica bom num Retina fica pequeno num monitor de DPR 1, e
  /// o terminal é onde isso mais pesa.
  final double? terminalSize;

  /// Peso do traço no terminal. Ver [TerminalFontWeight].
  final TerminalFontWeight terminalFontWeight;

  /// Id do tema ativo (UI + syntax + terminal num bundle só). Os built-in e os
  /// importados dividem o mesmo espaço de ids, por isso é `String` e não enum:
  /// tema custom não pode exigir mudança de código para ser persistido.
  /// Resolvido em `theme_registry.dart`; id desconhecido cai no default.
  final String themeId;

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

  /// Som ligado/desligado **por evento**. Ausente no mapa = ligado (default de
  /// todos os eventos). O antigo master switch `soundEnabled` foi absorvido:
  /// quem o tinha desligado migra pra todos os eventos desligados (fromJson).
  final Map<SoundEvent, bool> soundEvents;

  /// Caminho de um áudio custom (`.wav`/`.mp3`) por evento. Ausente = som
  /// embarcado do app. O arquivo é uma **cópia** feita pro storage do app no
  /// momento do pick (o original pode sumir); limpar o override volta ao
  /// padrão e apaga a cópia.
  final Map<SoundEvent, String> soundOverrides;

  /// Tocar o som do evento **mesmo com a aba dele ativa** (janela focada).
  /// Ausente = `false`: aba ativa fica muda — o usuário já está olhando a
  /// resposta/prompt. Só faz sentido pra `turnDone`/`actionRequired`
  /// (`agentError` sempre toca).
  final Map<SoundEvent, bool> soundOnActiveTab;

  /// Volume dos sons in-app, em % (0–100). Aplica a todos os eventos (default
  /// 50: os assets embarcados são altos no volume cheio).
  final double soundVolume;

  /// `true` quando o som do [event] deve tocar.
  bool soundEnabledFor(SoundEvent event) => soundEvents[event] ?? true;

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

  /// Troca os painéis laterais de lado: workspaces à direita, arquivos/busca/
  /// git/database à esquerda. Só a POSIÇÃO muda — largura, visibilidade e
  /// atalhos de cada painel seguem os mesmos.
  final bool swapSidePanels;

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

  /// Inicia o Cockpit junto com o login do sistema (item de login do SO).
  /// Persistido; a aplicação real no SO é feita pelo [LaunchAtStartupService]
  /// quando o valor muda.
  final bool launchAtStartup;

  /// `id` do [TerminalProfile] padrão do `+` (plano 50), persistido sob
  /// `terminal.default_profile_id`. `null` = **comportamento atual**: o
  /// resolver cai no fallback de plataforma (Windows: PowerShell — cmd no ARM;
  /// POSIX: login shell). Guardamos só o `id` estável: os perfis são
  /// re-descobertos a cada boot, e um `id` que sumiu degrada pro fallback.
  final String? defaultTerminalProfileId;

  /// Motor padrão de novas abas/buffers. Abas existentes guardam o próprio
  /// motor no descritor de layout e não são recriadas ao trocar esta opção.
  final TerminalEngine terminalEngine;

  /// Idioma escolhido (código raw pro `AppLocale.languageCode`/`countryCode`
  /// do slang, ex.: `'en'`, `'es'`, `'pt-BR'`). `null` = seguir o locale do SO
  /// (`LocaleSettings.useDeviceLocale()`). Editado na seção "Language" das
  /// Configurações.
  final String? locale;

  /// Layout padrão compartilhado por todos os workspaces, worktrees e seções
  /// (Changes/Staged) do Source Control.
  final SourceControlViewMode sourceControlViewMode;

  /// Harness global usado pelas automações. Ausente = automações desabilitadas.
  final HarnessKind? automationHarnessId;

  /// Modelo opcional do harness. Ausente = usar o default do próprio CLI.
  final String? automationModelId;

  /// Modelo efetivo. String vazia (ou ausência) é o sentinel de “deixar o
  /// harness decidir”: quem tem roteamento automático usa `auto`, quem não tem
  /// usa o modelo que o próprio CLI já traz configurado. Resolvido na hora de
  /// gerar, contra o catálogo descoberto — não dá para congelar aqui, o
  /// catálogo muda com o plano do usuário.
  String? get selectedAutomationModelId {
    final stored = automationModelId;
    return stored == null || stored.isEmpty ? null : stored;
  }

  AutomationSelection? get automationSelection => automationHarnessId == null
      ? null
      : AutomationSelection(
          harnessId: automationHarnessId!,
          modelId: selectedAutomationModelId,
        );

  /// Frequência de verificação de atualizações.
  final UpdateCheckFrequency updateCheckFrequency;

  /// Data da última verificação de atualização.
  final DateTime? lastUpdateCheckTime;

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
    double? terminalSize,
    bool clearTerminalSize = false,
    TerminalFontWeight? terminalFontWeight,
    String? themeId,
    bool? pinUserMessage,
    String? lastOpenAppId,
    Map<String, String>? lspCommands,
    Map<String, String>? lspFormatters,
    bool? formatOnSave,
    bool? notificationsEnabled,
    Map<SoundEvent, bool>? soundEvents,
    Map<SoundEvent, String>? soundOverrides,
    Map<SoundEvent, bool>? soundOnActiveTab,
    double? soundVolume,
    double? searchPanelHeight,
    double? tasksPanelHeight,
    bool? enableAgent,
    bool? swapSidePanels,
    bool? railVisible,
    bool? treeVisible,
    bool? showCockpit,
    bool? launchAtStartup,
    String? defaultTerminalProfileId,
    bool clearDefaultTerminalProfileId = false,
    TerminalEngine? terminalEngine,
    String? locale,
    bool clearLocale = false,
    SourceControlViewMode? sourceControlViewMode,
    HarnessKind? automationHarnessId,
    bool clearAutomationHarnessId = false,
    String? automationModelId,
    bool clearAutomationModelId = false,
    bool useDefaultAutomationModel = false,
    UpdateCheckFrequency? updateCheckFrequency,
    DateTime? lastUpdateCheckTime,
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
      terminalSize: clearTerminalSize
          ? null
          : (terminalSize ?? this.terminalSize),
      terminalFontWeight: terminalFontWeight ?? this.terminalFontWeight,
      themeId: themeId ?? this.themeId,
      pinUserMessage: pinUserMessage ?? this.pinUserMessage,
      lastOpenAppId: lastOpenAppId ?? this.lastOpenAppId,
      lspCommands: lspCommands ?? this.lspCommands,
      lspFormatters: lspFormatters ?? this.lspFormatters,
      formatOnSave: formatOnSave ?? this.formatOnSave,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      soundEvents: soundEvents ?? this.soundEvents,
      soundOverrides: soundOverrides ?? this.soundOverrides,
      soundOnActiveTab: soundOnActiveTab ?? this.soundOnActiveTab,
      soundVolume: soundVolume ?? this.soundVolume,
      searchPanelHeight: searchPanelHeight ?? this.searchPanelHeight,
      tasksPanelHeight: tasksPanelHeight ?? this.tasksPanelHeight,
      enableAgent: enableAgent ?? this.enableAgent,
      swapSidePanels: swapSidePanels ?? this.swapSidePanels,
      railVisible: railVisible ?? this.railVisible,
      treeVisible: treeVisible ?? this.treeVisible,
      showCockpit: showCockpit ?? this.showCockpit,
      launchAtStartup: launchAtStartup ?? this.launchAtStartup,
      defaultTerminalProfileId: clearDefaultTerminalProfileId
          ? null
          : (defaultTerminalProfileId ?? this.defaultTerminalProfileId),
      terminalEngine: terminalEngine ?? this.terminalEngine,
      locale: clearLocale ? null : (locale ?? this.locale),
      sourceControlViewMode:
          sourceControlViewMode ?? this.sourceControlViewMode,
      automationHarnessId: clearAutomationHarnessId
          ? null
          : (automationHarnessId ?? this.automationHarnessId),
      automationModelId: clearAutomationModelId
          ? null
          : useDefaultAutomationModel
          ? ''
          : (automationModelId ?? this.automationModelId),
      updateCheckFrequency: updateCheckFrequency ?? this.updateCheckFrequency,
      lastUpdateCheckTime: lastUpdateCheckTime ?? this.lastUpdateCheckTime,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'themeMode': themeMode.name,
    'interfaceFont': interfaceFont,
    'interfaceSize': interfaceSize,
    'codeFont': codeFont,
    'codeSize': codeSize,
    'terminalFont': terminalFont,
    'terminalSize': terminalSize,
    'terminalFontWeight': terminalFontWeight.name,
    'themeId': themeId,
    'pinUserMessage': pinUserMessage,
    if (lastOpenAppId != null) 'lastOpenAppId': lastOpenAppId,
    if (lspCommands.isNotEmpty) 'lspCommands': lspCommands,
    if (lspFormatters.isNotEmpty) 'lspFormatters': lspFormatters,
    if (formatOnSave) 'formatOnSave': true,
    if (!notificationsEnabled) 'notificationsEnabled': false,
    if (soundEvents.isNotEmpty)
      'sound.events': <String, bool>{
        for (final e in soundEvents.entries) e.key.name: e.value,
      },
    if (soundOverrides.isNotEmpty)
      'sound.overrides': <String, String>{
        for (final e in soundOverrides.entries) e.key.name: e.value,
      },
    if (soundOnActiveTab.isNotEmpty)
      'sound.onActiveTab': <String, bool>{
        for (final e in soundOnActiveTab.entries) e.key.name: e.value,
      },
    'sound.volume': soundVolume,
    'searchPanelHeight': searchPanelHeight,
    'tasksPanelHeight': tasksPanelHeight,
    // Sempre gravado (mesmo quando false) para a migração distinguir "install
    // novo" (chave presente = false) de "upgrade sem a flag" (chave ausente).
    'enableAgent': enableAgent,
    'swapSidePanels': swapSidePanels,
    if (railVisible) 'railVisible': true,
    if (treeVisible) 'treeVisible': true,
    // Sempre gravado: a migração distingue "install novo" (chave presente) de
    // "upgrade sem a flag" (chave ausente → liga automático).
    'showCockpit': showCockpit,
    'launchAtStartup': launchAtStartup,
    // Só quando escolhido: a AUSÊNCIA da chave é o "sem padrão" → fallback de
    // plataforma. Nada a migrar (plano 50).
    if (defaultTerminalProfileId != null)
      'terminal.default_profile_id': defaultTerminalProfileId,
    'terminal.engine': terminalEngine.name,
    // Só quando escolhido: ausência = seguir o locale do SO.
    if (locale != null) 'locale': locale,
    'sourceControl.viewMode': sourceControlViewMode.name,
    if (automationHarnessId != null)
      'automation.harnessId': automationHarnessId!.name,
    if (automationHarnessId != null)
      'automation.modelId': automationModelId ?? '',
    'updateCheckFrequency': updateCheckFrequency.name,
    if (lastUpdateCheckTime != null)
      'lastUpdateCheckTime': lastUpdateCheckTime!.toIso8601String(),
  };

  factory AppSettings.fromJson(Map<dynamic, dynamic> json) {
    String? str(Object? v) {
      final s = (v as String?)?.trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    final automationHarnessId = _harnessByStoredName(
      json['automation.harnessId'],
    );
    final rawAutomationModel = json['automation.modelId'];
    final automationModelId = rawAutomationModel is String
        ? rawAutomationModel.trim()
        : null;

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
      // Ausente = herda o tamanho do código, que é o que valia antes deste
      // campo existir.
      terminalSize: (json['terminalSize'] as num?)?.toDouble(),
      terminalFontWeight: _enumByName(
        TerminalFontWeight.values,
        json['terminalFontWeight'],
        TerminalFontWeight.auto,
      ),
      themeId: _themeIdFrom(json),
      pinUserMessage: json['pinUserMessage'] as bool? ?? true,
      lastOpenAppId: str(json['lastOpenAppId']),
      lspCommands: _strMap(json['lspCommands']),
      lspFormatters: _strMap(json['lspFormatters']),
      formatOnSave: json['formatOnSave'] as bool? ?? false,
      notificationsEnabled: json['notificationsEnabled'] as bool? ?? true,
      soundEvents: _migrateSoundEvents(json),
      soundOverrides: _soundEventMap<String>(json['sound.overrides']),
      soundOnActiveTab: _soundEventMap<bool>(json['sound.onActiveTab']),
      soundVolume: ((json['sound.volume'] as num?)?.toDouble() ?? 50).clamp(
        0,
        100,
      ),
      searchPanelHeight: (json['searchPanelHeight'] as num?)?.toDouble() ?? 260,
      tasksPanelHeight: (json['tasksPanelHeight'] as num?)?.toDouble() ?? 200,
      enableAgent: json['enableAgent'] as bool? ?? false,
      swapSidePanels: json['swapSidePanels'] as bool? ?? false,
      railVisible: json['railVisible'] as bool? ?? false,
      treeVisible: json['treeVisible'] as bool? ?? false,
      showCockpit: json['showCockpit'] as bool? ?? true,
      launchAtStartup: json['launchAtStartup'] as bool? ?? false,
      defaultTerminalProfileId: str(json['terminal.default_profile_id']),
      terminalEngine: _enumByName(
        TerminalEngine.values,
        json['terminal.engine'],
        TerminalEngine.ghostty,
      ),
      locale: str(json['locale']),
      sourceControlViewMode: _enumByName(
        SourceControlViewMode.values,
        json['sourceControl.viewMode'],
        SourceControlViewMode.list,
      ),
      automationHarnessId: automationHarnessId,
      automationModelId: automationModelId,
      updateCheckFrequency: _enumByName(
        UpdateCheckFrequency.values,
        json['updateCheckFrequency'],
        UpdateCheckFrequency.daily,
      ),
      lastUpdateCheckTime: json['lastUpdateCheckTime'] != null
          ? DateTime.tryParse(json['lastUpdateCheckTime'] as String)
          : null,
    );
  }
}

/// Toggles por evento, com migração do antigo master switch `soundEnabled`:
/// quem o tinha desligado (chave legada `false`) e ainda não tem toggles
/// próprios recebe todos os eventos desligados — o silêncio escolhido não pode
/// voltar a tocar num update. A chave legada deixa de ser gravada e some do
/// arquivo na primeira persistência.
Map<SoundEvent, bool> _migrateSoundEvents(Map<dynamic, dynamic> json) {
  final events = _soundEventMap<bool>(json['sound.events']);
  final legacyOff = json['soundEnabled'] == false;
  if (legacyOff && events.isEmpty) {
    return {for (final e in SoundEvent.values) e: false};
  }
  return events;
}

/// Mapa persistido por `SoundEvent.name`. Nome desconhecido (evento removido /
/// arquivo de versão mais nova) é ignorado; valor de tipo errado idem.
Map<SoundEvent, V> _soundEventMap<V>(Object? raw) {
  if (raw is! Map) return <SoundEvent, V>{};
  final out = <SoundEvent, V>{};
  raw.forEach((k, v) {
    if (k is! String || v is! V) return;
    final event = _nullableEnumByName(SoundEvent.values, k);
    if (event != null) out[event] = v;
  });
  return out;
}

Map<String, String> _strMap(Object? raw) {
  if (raw is! Map) return const <String, String>{};
  final out = <String, String>{};
  raw.forEach((k, v) {
    if (k is String && v is String && v.trim().isNotEmpty) out[k] = v;
  });
  return out;
}

/// Resolve o `themeId` salvo, caindo no tema oficial quando ausente.
///
/// O `syntaxTheme` antigo (enum `one`/`dracula`/`github`, que escolhia só o
/// realce de código) foi absorvido pelo tema completo e **não** é migrado: as
/// famílias viraram um tema oficial só. A chave velha, se existir no arquivo,
/// é simplesmente ignorada. O id literal espelha
/// `ui/themes/theme_registry.dart` — o domínio não pode importar a camada de
/// UI, mas os dois têm que concordar.
String _themeIdFrom(Map<dynamic, dynamic> json) {
  final explicit = json['themeId'];
  if (explicit is String && explicit.trim().isNotEmpty) return explicit.trim();
  return 'cockpit';
}

T _enumByName<T extends Enum>(List<T> values, Object? raw, T fallback) {
  if (raw is! String) return fallback;
  for (final v in values) {
    if (v.name == raw) return v;
  }
  return fallback;
}

/// Nomes que a versão anterior gravava, antes de o catálogo de harness ser
/// unificado com o da detecção de terminal. `gemini` não tem equivalente — o
/// Gemini CLI saiu e os modelos Gemini passaram a vir pelo Antigravity, então
/// a preferência antiga cai para "não configurado".
const Map<String, HarnessKind> _legacyHarnessNames = {
  'claude': HarnessKind.claudeCode,
  'copilot': HarnessKind.gitHubCopilot,
  'opencode': HarnessKind.openCode,
  'codex': HarnessKind.codex,
  'pi': HarnessKind.pi,
};

HarnessKind? _harnessByStoredName(Object? raw) {
  if (raw is! String) return null;
  return _nullableEnumByName(HarnessKind.values, raw) ??
      _legacyHarnessNames[raw];
}

T? _nullableEnumByName<T extends Enum>(List<T> values, Object? raw) {
  if (raw is! String) return null;
  for (final value in values) {
    if (value.name == raw) return value;
  }
  return null;
}
