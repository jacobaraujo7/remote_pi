import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

/// "Inverter panes" (Configurações → Aparência) troca o lado dos painéis
/// laterais. É preferência persistida, então precisa sobreviver ao round-trip
/// e nascer desligada — quem já usa o app não pode ter a tela reorganizada
/// numa atualização.
void main() {
  test('nasce desligada', () {
    expect(const AppSettings().swapSidePanels, isFalse);
  });

  test('sobrevive ao round-trip de JSON', () {
    const settings = AppSettings(swapSidePanels: true);
    final restored = AppSettings.fromJson(settings.toJson());
    expect(restored.swapSidePanels, isTrue);
  });

  test('registro antigo (sem a chave) continua com o layout de sempre', () {
    final legacy = const AppSettings().toJson()..remove('swapSidePanels');
    expect(AppSettings.fromJson(legacy).swapSidePanels, isFalse);
  });

  test('copyWith preserva e altera', () {
    const off = AppSettings();
    expect(off.copyWith().swapSidePanels, isFalse);
    expect(off.copyWith(swapSidePanels: true).swapSidePanels, isTrue);
    expect(
      const AppSettings(swapSidePanels: true).copyWith().swapSidePanels,
      isTrue,
      reason: 'copyWith sem o campo não pode zerar a preferência',
    );
  });
}
