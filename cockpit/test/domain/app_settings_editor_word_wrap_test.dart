import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

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

    test('copyWith keeps, sets and clears the choice', () {
      const settings = AppSettings(editorWordWrap: true);

      expect(settings.copyWith().editorWordWrap, isTrue);
      expect(settings.copyWith(editorWordWrap: false).editorWordWrap, isFalse);
      expect(
        settings.copyWith(clearEditorWordWrap: true).editorWordWrap,
        isNull,
      );
    });
  });
}
