import 'package:cockpit/domain/contracts/settings_store.dart';
import 'package:cockpit/domain/entities/app_settings.dart';
import 'package:flutter/foundation.dart';

/// Estado global das preferências do app. Vive **acima do `MaterialApp`** pra
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
    _apply(
      _settings.copyWith(interfaceFont: font, clearInterfaceFont: empty),
    );
  }

  void setInterfaceSize(double size) =>
      _apply(_settings.copyWith(interfaceSize: size));

  void setCodeFont(String? font) {
    final empty = font == null || font.trim().isEmpty;
    _apply(_settings.copyWith(codeFont: font, clearCodeFont: empty));
  }

  void setCodeSize(double size) =>
      _apply(_settings.copyWith(codeSize: size));

  void setSyntaxTheme(SyntaxThemeId id) =>
      _apply(_settings.copyWith(syntaxTheme: id));

  void setLastOpenApp(String id) =>
      _apply(_settings.copyWith(lastOpenAppId: id));

  void _apply(AppSettings next) {
    _settings = next;
    notifyListeners();
    // Persiste em background — falha de IO não pode travar a UI.
    _store.save(next);
  }
}
