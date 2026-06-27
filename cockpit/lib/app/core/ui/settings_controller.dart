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

  void _apply(AppSettings next) {
    _settings = next;
    notifyListeners();
    // Persiste em background — falha de IO não pode travar a UI.
    _store.save(next);
  }
}
