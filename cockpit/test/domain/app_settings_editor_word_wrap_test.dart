import 'package:cockpit/app/core/domain/contracts/settings_store.dart';
import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:cockpit/app/core/ui/settings_controller.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeStore implements SettingsStore {
  AppSettings? saved;

  @override
  Future<AppSettings> load() async => const AppSettings();

  @override
  Future<void> save(AppSettings settings) async => saved = settings;
}

void main() {
  group('AppSettings · editorWordWrap', () {
    test(
      'defaults to null (no choice: the editor uses the language default)',
      () {
        expect(const AppSettings().editorWordWrap, isNull);
        expect(
          AppSettings.fromJson(const <String, dynamic>{}).editorWordWrap,
          isNull,
        );
      },
    );

    test('round-trips an explicit choice', () {
      for (final value in [true, false]) {
        final settings = AppSettings(editorWordWrap: value);
        expect(AppSettings.fromJson(settings.toJson()).editorWordWrap, value);
      }
    });

    test(
      'is omitted from JSON until chosen, then stored under editor.wordWrap',
      () {
        expect(
          const AppSettings().toJson().containsKey('editor.wordWrap'),
          isFalse,
        );
        expect(
          const AppSettings(editorWordWrap: false).toJson(),
          containsPair('editor.wordWrap', false),
        );
      },
    );

    test('copyWith keeps and sets the choice', () {
      const settings = AppSettings(editorWordWrap: true);

      expect(settings.copyWith().editorWordWrap, isTrue);
      expect(settings.copyWith(editorWordWrap: false).editorWordWrap, isFalse);
    });

    test('copyWith can clear the choice back to the language default', () {
      const settings = AppSettings(editorWordWrap: true);

      expect(
        settings.copyWith(clearEditorWordWrap: true).editorWordWrap,
        isNull,
      );
    });
  });

  group('SettingsController.setEditorWordWrap', () {
    test(
      'stores a choice and null goes back to the language default',
      () async {
        final store = _FakeStore();
        final ctrl = SettingsController(store);
        await ctrl.load();

        ctrl.setEditorWordWrap(false);
        expect(ctrl.settings.editorWordWrap, isFalse);
        expect(store.saved?.toJson(), containsPair('editor.wordWrap', false));

        ctrl.setEditorWordWrap(null);
        expect(ctrl.settings.editorWordWrap, isNull);
        expect(store.saved?.toJson().containsKey('editor.wordWrap'), isFalse);
      },
    );
  });
}
