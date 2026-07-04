import 'package:cockpit/app/core/domain/contracts/settings_store.dart';
import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:cockpit/app/core/ui/settings_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// Store em memória: captura o último `save` para inspeção.
class _FakeStore implements SettingsStore {
  static const AppSettings _initial = AppSettings();
  AppSettings? saved;

  @override
  Future<AppSettings> load() async => _initial;

  @override
  Future<void> save(AppSettings settings) async => saved = settings;
}

void main() {
  group('AppSettings — visibilidade dos painéis', () {
    test('default é fechado (rail e árvore) em install novo', () {
      const s = AppSettings();
      expect(s.railVisible, isFalse);
      expect(s.treeVisible, isFalse);
    });

    test('JSON ausente → fechado (upgrade sem as chaves)', () {
      final s = AppSettings.fromJson(const <String, dynamic>{});
      expect(s.railVisible, isFalse);
      expect(s.treeVisible, isFalse);
    });

    test('round-trip preserva o estado aberto/fechado', () {
      const s = AppSettings(railVisible: true, treeVisible: false);
      final back = AppSettings.fromJson(s.toJson());
      expect(back.railVisible, isTrue);
      expect(back.treeVisible, isFalse);
    });

    test('só grava a chave quando true (JSON enxuto)', () {
      expect(const AppSettings().toJson().containsKey('railVisible'), isFalse);
      expect(const AppSettings().toJson().containsKey('treeVisible'), isFalse);
      final open = const AppSettings(railVisible: true, treeVisible: true)
          .toJson();
      expect(open['railVisible'], true);
      expect(open['treeVisible'], true);
    });
  });

  group('SettingsController.setPanelVisibility', () {
    test('persiste no store sem disparar notifyListeners', () async {
      final store = _FakeStore();
      final ctrl = SettingsController(store);
      await ctrl.load();

      var notified = false;
      ctrl.addListener(() => notified = true);

      ctrl.setPanelVisibility(rail: true, tree: false);

      // Persiste é async (fire-and-forget); aguarda o microtask.
      await Future<void>.delayed(Duration.zero);

      expect(store.saved, isNotNull);
      expect(store.saved!.railVisible, isTrue);
      expect(store.saved!.treeVisible, isFalse);
      expect(ctrl.settings.railVisible, isTrue);
      // A VM é a fonte de verdade em runtime → não deve notificar a árvore.
      expect(notified, isFalse);
    });
  });
}
