import 'package:cockpit/app/core/domain/contracts/settings_store.dart';
import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:cockpit/app/core/ui/settings_controller.dart';
import 'package:flutter_test/flutter_test.dart';

class _Store implements SettingsStore {
  AppSettings? saved;

  @override
  Future<AppSettings> load() async => const AppSettings();

  @override
  Future<void> save(AppSettings settings) async => saved = settings;
}

void main() {
  test('Neovim is disabled by default and absent from compact JSON', () {
    const settings = AppSettings();
    expect(settings.neovimEnabled, isFalse);
    expect(settings.toJson(), isNot(contains('editor.neovim.enabled')));
  });

  test('Neovim preference round-trips with a stable key', () {
    const settings = AppSettings(neovimEnabled: true);
    final json = settings.toJson();
    expect(json['editor.neovim.enabled'], isTrue);
    expect(AppSettings.fromJson(json).neovimEnabled, isTrue);
  });

  test('SettingsController persists Neovim changes', () async {
    final store = _Store();
    final controller = SettingsController(store);
    await controller.load();

    controller.setNeovimEnabled(true);
    await Future<void>.delayed(Duration.zero);

    expect(controller.settings.neovimEnabled, isTrue);
    expect(store.saved?.neovimEnabled, isTrue);
  });
}
