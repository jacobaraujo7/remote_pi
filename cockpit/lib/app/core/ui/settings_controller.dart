import 'package:cockpit/app/core/domain/contracts/settings_store.dart';
import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:flutter/foundation.dart';

/// Estado global das preferências do app. Vive **acima do `ShadcnApp`** pra
/// trocar tema/fonte em runtime, e é lido pela tela de Configurações. Cada
/// mudança aplica na hora (notify) e persiste (Hive).
class SettingsController extends ChangeNotifier {
  SettingsController(this._store);

  final SettingsStore _store;
  AppSettings _settings = const AppSettings();

  AppSettings get settings => _settings;

  /// Carrega o que está salvo (chamado no boot, antes do primeiro frame).
  Future<void> load() async {
    _settings = await _store.load();
    notifyListeners();
  }

  void setThemeMode(AppThemeMode mode) =>
      _apply(_settings.copyWith(themeMode: mode));

  void setInterfaceFont(String? font) {
    final empty = font == null || font.trim().isEmpty;
    _apply(_settings.copyWith(interfaceFont: font, clearInterfaceFont: empty));
  }

  void setInterfaceSize(double size) =>
      _apply(_settings.copyWith(interfaceSize: size));

  void setCodeFont(String? font) {
    final empty = font == null || font.trim().isEmpty;
    _apply(_settings.copyWith(codeFont: font, clearCodeFont: empty));
  }

  void setCodeSize(double size) => _apply(_settings.copyWith(codeSize: size));

  void setTerminalFont(String? font) {
    final empty = font == null || font.trim().isEmpty;
    _apply(_settings.copyWith(terminalFont: font, clearTerminalFont: empty));
  }

  void setTerminalEngine(TerminalEngine engine) =>
      _apply(_settings.copyWith(terminalEngine: engine));

  /// Define (ou limpa, se `null`/vazio) o perfil de terminal padrão do `+`
  /// (plano 50). Limpar = voltar ao fallback de plataforma.
  void setDefaultTerminalProfileId(String? id) {
    final empty = id == null || id.trim().isEmpty;
    _apply(
      _settings.copyWith(
        defaultTerminalProfileId: id,
        clearDefaultTerminalProfileId: empty,
      ),
    );
  }

  void setSyntaxTheme(SyntaxThemeId id) =>
      _apply(_settings.copyWith(syntaxTheme: id));

  void setPinUserMessage(bool value) =>
      _apply(_settings.copyWith(pinUserMessage: value));

  void setLastOpenApp(String id) =>
      _apply(_settings.copyWith(lastOpenAppId: id));

  /// Define (ou limpa, se vazio) o comando do language server de [languageId].
  void setLspCommand(String languageId, String? command) {
    final next = Map<String, String>.of(_settings.lspCommands);
    final trimmed = command?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      next.remove(languageId);
    } else {
      next[languageId] = trimmed;
    }
    _apply(_settings.copyWith(lspCommands: next));
  }

  /// Define (ou limpa, se vazio) o comando de formatador externo de [languageId].
  void setLspFormatter(String languageId, String? command) {
    final next = Map<String, String>.of(_settings.lspFormatters);
    final trimmed = command?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      next.remove(languageId);
    } else {
      next[languageId] = trimmed;
    }
    _apply(_settings.copyWith(lspFormatters: next));
  }

  void setFormatOnSave(bool value) =>
      _apply(_settings.copyWith(formatOnSave: value));

  void setNotificationsEnabled(bool value) =>
      _apply(_settings.copyWith(notificationsEnabled: value));

  void setSoundEnabled(bool value) =>
      _apply(_settings.copyWith(soundEnabled: value));

  void setSearchPanelHeight(double value) =>
      _apply(_settings.copyWith(searchPanelHeight: value));

  void setTasksPanelHeight(double value) =>
      _apply(_settings.copyWith(tasksPanelHeight: value));

  void setEnableAgent(bool value) =>
      _apply(_settings.copyWith(enableAgent: value));

  void setShowCockpit(bool value) =>
      _apply(_settings.copyWith(showCockpit: value));

  /// Persiste a visibilidade dos painéis do shell (rail de projetos + árvore de
  /// arquivos) para restaurar no próximo boot. Não faz `notifyListeners` porque
  /// a fonte de verdade em runtime é a `CockpitViewModel` — aqui só grava.
  void setPanelVisibility({required bool rail, required bool tree}) {
    final next = _settings.copyWith(railVisible: rail, treeVisible: tree);
    _settings = next;
    _store.save(next);
  }

  void _apply(AppSettings next) {
    _settings = next;
    notifyListeners();
    // Persiste em background — falha de IO não pode travar a UI.
    _store.save(next);
  }
}
