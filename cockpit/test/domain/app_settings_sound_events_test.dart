import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:cockpit/app/core/domain/entities/sound_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppSettings sound events', () {
    test('defaults: todos os eventos ligados, sem overrides', () {
      const s = AppSettings();
      expect(s.soundEvents, isEmpty);
      expect(s.soundOverrides, isEmpty);
      for (final e in SoundEvent.values) {
        expect(s.soundEnabledFor(e), isTrue);
      }
    });

    test('migração: master legado desligado vira todos os eventos off', () {
      final s = AppSettings.fromJson(const {'soundEnabled': false});
      for (final e in SoundEvent.values) {
        expect(s.soundEnabledFor(e), isFalse);
      }
      // A chave legada não é re-persistida.
      expect(s.toJson().containsKey('soundEnabled'), isFalse);
    });

    test(
      'migração: toggles próprios têm precedência sobre o master legado',
      () {
        final s = AppSettings.fromJson(const {
          'soundEnabled': false,
          'sound.events': {'turnDone': true},
        });
        expect(s.soundEnabledFor(SoundEvent.turnDone), isTrue);
      },
    );

    test('toggle por evento não afeta os demais', () {
      const s = AppSettings(soundEvents: {SoundEvent.actionRequired: false});
      expect(s.soundEnabledFor(SoundEvent.actionRequired), isFalse);
      expect(s.soundEnabledFor(SoundEvent.turnDone), isTrue);
      expect(s.soundEnabledFor(SoundEvent.agentError), isTrue);
    });

    test('round-trip json preserva toggles, overrides e volume', () {
      const s = AppSettings(
        soundEvents: {SoundEvent.turnDone: false, SoundEvent.agentError: true},
        soundOverrides: {SoundEvent.actionRequired: '/tmp/ding.mp3'},
        soundVolume: 80,
      );
      final restored = AppSettings.fromJson(s.toJson());
      expect(restored.soundEvents, s.soundEvents);
      expect(restored.soundOverrides, s.soundOverrides);
      expect(restored.soundVolume, 80);
    });

    test('soundOnActiveTab: default false, round-trip preserva', () {
      const off = AppSettings();
      for (final e in SoundEvent.values) {
        expect(off.soundOnActiveTab[e] ?? false, isFalse);
      }
      const s = AppSettings(soundOnActiveTab: {SoundEvent.turnDone: true});
      final restored = AppSettings.fromJson(s.toJson());
      expect(restored.soundOnActiveTab, {SoundEvent.turnDone: true});
    });

    test('volume: default 50, clamp e legado sem a chave', () {
      expect(const AppSettings().soundVolume, 50);
      expect(AppSettings.fromJson(const {}).soundVolume, 50);
      expect(
        AppSettings.fromJson(const {'sound.volume': 250}).soundVolume,
        100,
      );
      expect(AppSettings.fromJson(const {'sound.volume': -5}).soundVolume, 0);
    });

    test('defaults não poluem o json persistido', () {
      const s = AppSettings();
      final json = s.toJson();
      expect(json.containsKey('sound.events'), isFalse);
      expect(json.containsKey('sound.overrides'), isFalse);
    });

    test('evento desconhecido no json é ignorado (arquivo de versão nova)', () {
      final restored = AppSettings.fromJson({
        'sound.events': {'turnDone': false, 'futureEvent': true},
        'sound.overrides': {'futureEvent': '/x.wav', 'agentError': '/y.wav'},
      });
      expect(restored.soundEvents, {SoundEvent.turnDone: false});
      expect(restored.soundOverrides, {SoundEvent.agentError: '/y.wav'});
    });

    test('defaultAsset cobre todos os eventos', () {
      expect(
        {for (final e in SoundEvent.values) e.defaultAsset}.length,
        SoundEvent.values.length,
      );
    });
  });
}
