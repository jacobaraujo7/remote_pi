// Plan 29 — SpeechToTextService locale resolution + transcript / cancel /
// level behavior, exercised through the SttPlugin seam (no device).

import 'package:app/data/voice/speech_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSttPlugin implements SttPlugin {
  bool initializeResult = true;
  bool permission = true;
  List<String> localeList = ['en_US', 'pt_BR'];

  int stopCalls = 0;
  int cancelCalls = 0;
  String? listenedLocale;
  Duration? listenedFor;

  SttResultCallback? _onResult;
  SttLevelCallback? _onLevel;
  SttErrorCallback? _onError;
  void Function()? _onDone;

  @override
  Future<bool> initialize() async => initializeResult;

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<List<String>> locales() async => localeList;

  @override
  Future<void> listen({
    required String localeId,
    required Duration listenFor,
    required SttResultCallback onResult,
    required SttLevelCallback onLevel,
    required SttErrorCallback onError,
    required void Function() onDone,
  }) async {
    listenedLocale = localeId;
    listenedFor = listenFor;
    _onResult = onResult;
    _onLevel = onLevel;
    _onError = onError;
    _onDone = onDone;
  }

  @override
  Future<void> stop() async => stopCalls++;

  @override
  Future<void> cancel() async => cancelCalls++;

  // Test drivers.
  void emitResult(String words, {bool isFinal = false}) => _onResult?.call(
    words,
    isFinal ? SttResultKind.finalResult : SttResultKind.partial,
  );
  void emitSegmentEnd(String words) =>
      _onResult?.call(words, SttResultKind.segmentEnd);
  void emitLevel(double level) => _onLevel?.call(level);
  void emitError(String msg) => _onError?.call(msg);
  void emitDone() => _onDone?.call();
}

/// Starts a fresh capture on [plugin] through a ready service.
Future<SpeechToTextService> _listening(
  _FakeSttPlugin plugin, {
  Duration finalResultTimeout = const Duration(milliseconds: 50),
}) async {
  final service = SpeechToTextService(
    plugin,
    SoundLevelScale.android,
    finalResultTimeout,
  );
  await service.init(preferredLocaleId: 'en_US');
  await service.start(
    localeId: 'en_US',
    maxDuration: const Duration(seconds: 60),
  );
  return service;
}

void main() {
  group('init — locale resolution (#8 / #9)', () {
    test('exact preferred locale is used', () async {
      final plugin = _FakeSttPlugin()..localeList = ['en_US', 'pt_BR'];
      final service = SpeechToTextService(plugin);
      final a = await service.init(preferredLocaleId: 'pt_BR');
      expect(a, const SpeechReady('pt_BR'));
    });

    test('falls back to a same-language variant', () async {
      final plugin = _FakeSttPlugin()..localeList = ['en_US', 'pt_BR'];
      final service = SpeechToTextService(plugin);
      final a = await service.init(preferredLocaleId: 'pt_PT');
      expect(a, const SpeechReady('pt_BR'));
    });

    test('locale without on-device support falls back to en_US (#9)', () async {
      final plugin = _FakeSttPlugin()..localeList = ['en_US', 'pt_BR'];
      final service = SpeechToTextService(plugin);
      final a = await service.init(preferredLocaleId: 'de_DE');
      expect(a, const SpeechReady('en_US'));
    });

    test('no en_US but another English variant present', () async {
      final plugin = _FakeSttPlugin()..localeList = ['en_GB', 'fr_FR'];
      final service = SpeechToTextService(plugin);
      final a = await service.init(preferredLocaleId: 'de_DE');
      expect(a, const SpeechReady('en_GB'));
    });

    test('case/separator-insensitive matching', () async {
      final plugin = _FakeSttPlugin()..localeList = ['en-us', 'pt_br'];
      final service = SpeechToTextService(plugin);
      final a = await service.init(preferredLocaleId: 'PT_BR');
      expect(a, const SpeechReady('pt_br'));
    });

    test('no acceptable locale → unsupported (mic hidden)', () async {
      final plugin = _FakeSttPlugin()..localeList = ['fr_FR'];
      final service = SpeechToTextService(plugin);
      final a = await service.init(preferredLocaleId: 'de_DE');
      expect(a, const SpeechUnsupported());
    });
  });

  group('init — availability', () {
    test(
      'permission denied when initialize fails & no permission (#10)',
      () async {
        final plugin = _FakeSttPlugin()
          ..initializeResult = false
          ..permission = false;
        final service = SpeechToTextService(plugin);
        final a = await service.init(preferredLocaleId: 'en_US');
        expect(a, const SpeechPermissionDenied());
      },
    );

    test('unsupported when initialize fails but permission granted', () async {
      final plugin = _FakeSttPlugin()
        ..initializeResult = false
        ..permission = true;
      final service = SpeechToTextService(plugin);
      final a = await service.init(preferredLocaleId: 'en_US');
      expect(a, const SpeechUnsupported());
    });
  });

  group('capture lifecycle', () {
    test('stop returns the latest accumulated transcript, trimmed', () async {
      final plugin = _FakeSttPlugin();
      final service = SpeechToTextService(plugin);
      await service.init(preferredLocaleId: 'en_US');

      await service.start(
        localeId: 'en_US',
        maxDuration: const Duration(seconds: 60),
      );
      expect(plugin.listenedLocale, 'en_US');
      expect(plugin.listenedFor, const Duration(seconds: 60));

      plugin.emitResult('hello');
      plugin.emitResult('hello world  ', isFinal: true);
      final text = await service.stop();
      expect(text, 'hello world');
      expect(plugin.stopCalls, 1);
    });

    test('empty/silent capture resolves to empty string (#12)', () async {
      final plugin = _FakeSttPlugin();
      final service = SpeechToTextService(plugin);
      await service.init(preferredLocaleId: 'en_US');
      await service.start(
        localeId: 'en_US',
        maxDuration: const Duration(seconds: 60),
      );
      final text = await service.stop();
      expect(text, isEmpty);
    });

    test('cancel discards the transcript and never returns text', () async {
      final plugin = _FakeSttPlugin();
      final service = SpeechToTextService(plugin);
      await service.init(preferredLocaleId: 'en_US');

      await service.start(
        localeId: 'en_US',
        maxDuration: const Duration(seconds: 60),
      );
      plugin.emitResult('secret words');
      await service.cancel();
      expect(plugin.cancelCalls, 1);

      // A fresh capture must not inherit the cancelled transcript.
      await service.start(
        localeId: 'en_US',
        maxDuration: const Duration(seconds: 60),
      );
      expect(await service.stop(), isEmpty);
    });

    test(
      'sound level is normalized to 0..1 on the soundLevel stream (Android scale)',
      () async {
        final plugin = _FakeSttPlugin();
        // Pin the Android rmsdB scale so the assertions don't depend on the
        // host the test runs on (forPlatform() picks darwin on macOS).
        final service = SpeechToTextService(plugin, SoundLevelScale.android);
        await service.init(preferredLocaleId: 'en_US');

        final levels = <double>[];
        final sub = service.soundLevel.listen(levels.add);

        await service.start(
          localeId: 'en_US',
          maxDuration: const Duration(seconds: 60),
        );
        plugin.emitLevel(-2.0); // min → 0
        plugin.emitLevel(4.0); // midpoint → 0.5
        plugin.emitLevel(10.0); // max → 1
        plugin.emitLevel(99.0); // clamped → 1
        await Future<void>.delayed(Duration.zero);

        expect(levels, [0.0, 0.5, 1.0, 1.0]);
        await sub.cancel();
        service.dispose();
      },
    );

    test(
      'sound level uses the dBFS scale on iOS/macOS (negative avgPower)',
      () async {
        // Regression: iOS reports 20*log10(rms), a negative dBFS value. The
        // Android range [-2, 10] clamps all of it to 0 → flat waveform. The
        // darwin scale [-50, -10] must spread typical speech across 0..1.
        final plugin = _FakeSttPlugin();
        final service = SpeechToTextService(plugin, SoundLevelScale.darwin);
        await service.init(preferredLocaleId: 'en_US');

        final levels = <double>[];
        final sub = service.soundLevel.listen(levels.add);

        await service.start(
          localeId: 'en_US',
          maxDuration: const Duration(seconds: 60),
        );
        plugin.emitLevel(-50.0); // min → 0
        plugin.emitLevel(-30.0); // midpoint → 0.5
        plugin.emitLevel(-10.0); // max → 1
        plugin.emitLevel(-60.0); // below floor → clamped → 0
        plugin.emitLevel(double.negativeInfinity); // silent buffer → 0
        await Future<void>.delayed(Duration.zero);

        expect(levels, [0.0, 0.5, 1.0, 0.0, 0.0]);
        await sub.cancel();
        service.dispose();
      },
    );
  });

  group('transcript across pauses and release', () {
    test(
      'keeps earlier segments when the recognizer resets after a pause',
      () async {
        // Android sends an empty partial at each pause, then starts the next
        // segment from scratch (seen on a Galaxy, Android 16 on-device).
        final plugin = _FakeSttPlugin();
        final service = await _listening(plugin);

        plugin.emitResult('The quick brown fox');
        plugin.emitResult('The quick brown fox jumps over the lazy dog');
        plugin.emitResult('');
        plugin.emitResult('Remote Pi should');
        plugin.emitResult('Remote Pi should turn every word I say into text');
        plugin.emitResult(
          ' Remote Pi should turn every word I say into text',
          isFinal: true,
        );

        expect(
          await service.stop(),
          'The quick brown fox jumps over the lazy dog '
          'Remote Pi should turn every word I say into text',
        );
      },
    );

    test('keeps segments the recognizer marks final mid-capture', () async {
      final plugin = _FakeSttPlugin();
      final service = await _listening(
        plugin,
        finalResultTimeout: const Duration(seconds: 5),
      );

      plugin.emitResult('first sentence', isFinal: true);
      plugin.emitResult('second');

      final text = service.stop();
      await Future<void>.delayed(Duration.zero);
      plugin.emitResult('second sentence', isFinal: true);

      expect(await text, 'first sentence second sentence');
    });

    test(
      'a segment end keeps the segment when the next one starts without a pause marker',
      () async {
        // Seen on device: no empty partial between sentences — Android closes
        // the segment with an intermediate result, then the next segment's
        // first partial arrives directly.
        final plugin = _FakeSttPlugin();
        final service = await _listening(plugin);

        plugin.emitResult('The quick brown fox jumps over the lazy dog');
        plugin.emitSegmentEnd('The quick brown fox jumps over the lazy dog');
        plugin.emitSegmentEnd(' The quick brown fox jumps over the lazy dog');
        plugin.emitResult('Pro');
        plugin.emitResult('Promote pi should turn every word I say into text');

        expect(
          await service.stop(),
          'The quick brown fox jumps over the lazy dog '
          'Promote pi should turn every word I say into text',
        );
      },
    );

    test('a new segment may arrive directly as a final result', () async {
      final plugin = _FakeSttPlugin();
      final service = await _listening(plugin);

      plugin.emitSegmentEnd('first sentence');
      plugin.emitResult('second sentence', isFinal: true);

      expect(await service.stop(), 'first sentence second sentence');
    });

    test('a result that extends a closed segment updates it', () async {
      // Seen on device: the segment end is repeated, and the final result
      // after release restates (or completes) the same segment.
      final plugin = _FakeSttPlugin();
      final service = await _listening(plugin);

      plugin.emitSegmentEnd('Remote Pi should turn');
      plugin.emitSegmentEnd(' Remote Pi should turn every word');
      final stopped = service.stop();
      plugin.emitResult(
        ' Remote Pi should turn every word I say into text',
        isFinal: true,
      );

      expect(await stopped, 'Remote Pi should turn every word I say into text');
    });

    test('waits for words that arrive after release', () async {
      final plugin = _FakeSttPlugin();
      final service = await _listening(
        plugin,
        finalResultTimeout: const Duration(seconds: 5),
      );
      plugin.emitResult('every word I');

      final text = service.stop();
      await Future<void>.delayed(Duration.zero);
      plugin.emitResult('every word I say into text');
      plugin.emitResult('every word I say into text', isFinal: true);

      expect(await text, 'every word I say into text');
    });

    test('a done status without a final result ends the wait', () async {
      final plugin = _FakeSttPlugin();
      final service = await _listening(
        plugin,
        finalResultTimeout: const Duration(seconds: 5),
      );
      plugin.emitResult('hello');

      final text = service.stop();
      await Future<void>.delayed(Duration.zero);
      plugin.emitDone();

      expect(await text, 'hello');
    });

    test('returns what it has when no final result arrives in time', () async {
      final plugin = _FakeSttPlugin();
      final service = await _listening(plugin);
      plugin.emitResult('hello there');

      expect(await service.stop(), 'hello there');
    });

    test(
      'late results from a finished session do not leak into the next',
      () async {
        final plugin = _FakeSttPlugin();
        final service = await _listening(plugin);
        final firstSession = plugin._onResult!;
        plugin.emitResult('first');
        expect(await service.stop(), 'first');

        await service.start(
          localeId: 'en_US',
          maxDuration: const Duration(seconds: 60),
        );
        firstSession('first and late', SttResultKind.finalResult);
        plugin.emitResult('second');

        expect(await service.stop(), 'second');
      },
    );
  });

  group('overlapping captures', () {
    test(
      'starting a new capture ends a pending stop with its own words',
      () async {
        final plugin = _FakeSttPlugin();
        final service = await _listening(
          plugin,
          finalResultTimeout: const Duration(seconds: 10),
        );
        plugin.emitResult('first capture');
        final firstStop = service.stop();

        await service.start(
          localeId: 'en_US',
          maxDuration: const Duration(seconds: 60),
        );
        plugin.emitResult('second capture');

        // Resolves without waiting out the timeout, with A's words only.
        expect(
          await firstStop.timeout(const Duration(seconds: 1)),
          'first capture',
        );
        final secondStop = service.stop();
        plugin.emitResult('second capture', isFinal: true);
        expect(await secondStop, 'second capture');
      },
    );

    test('cancelling a pending stop returns no text', () async {
      final plugin = _FakeSttPlugin();
      final service = await _listening(
        plugin,
        finalResultTimeout: const Duration(seconds: 10),
      );
      plugin.emitResult('secret words');
      final stopped = service.stop();
      await service.cancel();

      expect(await stopped.timeout(const Duration(seconds: 1)), isEmpty);
    });
  });

  group('recognizer errors', () {
    test('an error while listening is reported with its kind', () async {
      final plugin = _FakeSttPlugin();
      final service = await _listening(plugin);
      final errors = <SpeechFailure>[];
      final sub = service.errors.listen(errors.add);

      plugin.emitError('error_language_not_supported');
      plugin.emitError('error_language_unavailable');
      plugin.emitError('error_no_match');
      plugin.emitError('error_server_disconnected');
      await Future<void>.delayed(Duration.zero);

      expect(errors.map((e) => e.kind), [
        SpeechFailureKind.languageUnavailable,
        SpeechFailureKind.languageUnavailable,
        SpeechFailureKind.noSpeech,
        SpeechFailureKind.other,
      ]);
      expect(errors.last.message, 'error_server_disconnected');
      await sub.cancel();
    });

    test('an error after release ends the wait and is not reported', () async {
      final plugin = _FakeSttPlugin();
      final service = await _listening(
        plugin,
        finalResultTimeout: const Duration(seconds: 5),
      );
      final errors = <SpeechFailure>[];
      final sub = service.errors.listen(errors.add);
      plugin.emitResult('hello');

      final text = service.stop();
      await Future<void>.delayed(Duration.zero);
      plugin.emitError('error_client');

      expect(await text, 'hello');
      await Future<void>.delayed(Duration.zero);
      expect(errors, isEmpty);
      await sub.cancel();
    });
  });

  group('SoundLevelScale', () {
    test('forPlatform picks the darwin scale on macOS test host', () {
      // The unit-test host is macOS, so the platform factory must resolve to
      // the dBFS scale — guarding the iOS waveform regression directly.
      expect(SoundLevelScale.forPlatform(), SoundLevelScale.darwin);
    });

    test('normalize clamps NaN and ±infinity to the endpoints', () {
      expect(SoundLevelScale.darwin.normalize(double.nan), 0.0);
      expect(SoundLevelScale.darwin.normalize(double.negativeInfinity), 0.0);
      expect(SoundLevelScale.darwin.normalize(double.infinity), 1.0);
    });
  });
}
