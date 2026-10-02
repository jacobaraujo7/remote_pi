import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show PlatformDispatcher;

import 'package:app/domain/contracts/contracts.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Plan 29 — on-device speech-to-text, app-only.
///
/// Wraps the `speech_to_text` plugin behind a testable contract. The audio
/// is captured by the recognizer and transcribed in-stream — **no audio file
/// is ever created** — and `onDevice: true` forces local recognition so the
/// audio never leaves the device (decisions #2 / #7). The output is plain
/// text that the caller drops into the chat composer for manual review.
///
/// ### On-device detection (Risk 1 spike — resolved)
///
/// `speech_to_text` 7.x does **not** expose a per-locale on-device capability
/// query: `locales()` returns a flat list of recognition locales with no
/// "supportsOnDevice" tag, and `onDevice` is only honored at `listen()` time
/// (`SpeechListenOptions.onDevice`). On iOS that maps to
/// `SFSpeechRecognizer.requiresOnDeviceRecognition`; a locale with no local
/// model fails the listen attempt at runtime (delivered via `onError`).
///
/// So detection is best-effort: [init] resolves the locale from `locales()`
/// membership (preferred → same-language → `en_US` → any English, decision
/// #9), and the `onDevice: true` flag plus the runtime `onError` backstop
/// guard the rare "listed but no local model" case (a permanent error there
/// surfaces as an empty transcript → no-op, decision #12).
abstract class SpeechService extends Service {
  /// Resolve permission + on-device availability + the locale to use.
  /// [preferredLocaleId] defaults to the platform locale when null.
  Future<SpeechAvailability> init({String? preferredLocaleId});

  /// Recognition locale ids supported on this device (e.g. `pt_BR`, `en_US`),
  /// for the Settings language picker. Does not trigger the mic permission
  /// prompt; an empty list means the device exposed no locales.
  Future<List<String>> locales();

  /// Amplitude envelope in `0..1` for the waveform. This is a volume
  /// envelope, **not** an FFT spectrum (Risk 4).
  Stream<double> get soundLevel;

  /// Begin on-device capture for [localeId], hard-capped at [maxDuration].
  Future<void> start({required String localeId, required Duration maxDuration});

  /// Stop capture and resolve with the accumulated transcript (trimmed;
  /// empty string when nothing was recognized).
  Future<String> stop();

  /// Abort capture and discard any accumulated transcript.
  Future<void> cancel();

  /// Release the sound-level stream. Owned by the app lifecycle (the service
  /// is a singleton); ViewModels must NOT call this.
  @override
  void dispose();
}

/// Outcome of [SpeechService.init].
sealed class SpeechAvailability {
  const SpeechAvailability();
}

/// Voice input is usable; [localeId] is the resolved on-device locale.
final class SpeechReady extends SpeechAvailability {
  const SpeechReady(this.localeId);
  final String localeId;

  @override
  bool operator ==(Object other) =>
      other is SpeechReady && other.localeId == localeId;

  @override
  int get hashCode => localeId.hashCode;
}

/// Mic / speech permission was denied (decision #10).
final class SpeechPermissionDenied extends SpeechAvailability {
  const SpeechPermissionDenied();

  @override
  bool operator ==(Object other) => other is SpeechPermissionDenied;

  @override
  int get hashCode => (SpeechPermissionDenied).hashCode;
}

/// No on-device recognition available for any acceptable locale — the mic is
/// hidden (decision #9, edge case).
final class SpeechUnsupported extends SpeechAvailability {
  const SpeechUnsupported();

  @override
  bool operator ==(Object other) => other is SpeechUnsupported;

  @override
  int get hashCode => (SpeechUnsupported).hashCode;
}

// ---------------------------------------------------------------------------
// Production implementation
// ---------------------------------------------------------------------------

/// Default [SpeechService] backed by the `speech_to_text` plugin.
///
/// The plugin is reached through the [SttPlugin] seam so the locale-resolution
/// / cap / transcript-accumulation logic is unit-testable without a device.
class SpeechToTextService implements SpeechService {
  SpeechToTextService([SttPlugin? plugin, SoundLevelScale? levelScale])
    : _plugin = plugin ?? SttPluginImpl(),
      _levelScale = levelScale ?? SoundLevelScale.forPlatform();

  final SttPlugin _plugin;
  final SoundLevelScale _levelScale;
  final StreamController<double> _levelController =
      StreamController<double>.broadcast();

  /// Latest recognized words (partial or final). Reset on each [start].
  String _transcript = '';
  bool _initialized = false;

  @override
  Stream<double> get soundLevel => _levelController.stream;

  @override
  Future<SpeechAvailability> init({String? preferredLocaleId}) async {
    final ok = _initialized || await _plugin.initialize();
    if (!ok) {
      // initialize() returns false for either a denied permission or an
      // unavailable recognizer — disambiguate via hasPermission().
      final granted = await _plugin.hasPermission();
      return granted
          ? const SpeechUnsupported()
          : const SpeechPermissionDenied();
    }
    _initialized = true;

    final supported = await _plugin.locales();
    final preferred = _normalize(preferredLocaleId ?? _platformLocaleId());
    final resolved = _resolveLocale(preferred, supported);
    return resolved == null ? const SpeechUnsupported() : SpeechReady(resolved);
  }

  @override
  Future<List<String>> locales() => _plugin.locales();

  @override
  Future<void> start({
    required String localeId,
    required Duration maxDuration,
  }) async {
    _transcript = '';
    await _plugin.listen(
      localeId: localeId,
      listenFor: maxDuration,
      onResult: (words, _) {
        // Decision #6 — partial results are accumulated but never shown live;
        // the latest text wins and only materializes on stop().
        if (words.isNotEmpty) _transcript = words;
      },
      onLevel: (level) {
        if (!_levelController.isClosed) {
          _levelController.add(_levelScale.normalize(level));
        }
      },
    );
  }

  @override
  Future<String> stop() async {
    await _plugin.stop();
    return _transcript.trim();
  }

  @override
  Future<void> cancel() async {
    _transcript = '';
    await _plugin.cancel();
  }

  @override
  void dispose() {
    if (!_levelController.isClosed) _levelController.close();
  }

  // -------------------------------------------------------------------------
  // Locale resolution (decision #8 / #9)
  // -------------------------------------------------------------------------

  /// `en-US` / `en_us` → `en_US`. The plugin reports underscores; normalize
  /// case + separator so comparisons are robust.
  static String _normalize(String id) {
    final parts = id.replaceAll('-', '_').split('_');
    if (parts.isEmpty) return id;
    final lang = parts.first.toLowerCase();
    if (parts.length == 1) return lang;
    return '${lang}_${parts[1].toUpperCase()}';
  }

  static String _platformLocaleId() {
    final l = PlatformDispatcher.instance.locale;
    final country = l.countryCode;
    return (country == null || country.isEmpty)
        ? l.languageCode
        : '${l.languageCode}_$country';
  }

  /// preferred exact → preferred language → `en_US` → any English → null.
  /// Returns the original (un-normalized) supported id so it round-trips back
  /// into `listen()`.
  static String? _resolveLocale(String preferred, List<String> supported) {
    String? firstWhere(bool Function(String normalized) test) {
      for (final s in supported) {
        if (test(_normalize(s))) return s;
      }
      return null;
    }

    final lang = preferred.split('_').first;
    return firstWhere((s) => s == preferred) ??
        firstWhere((s) => s.split('_').first == lang) ??
        firstWhere((s) => s == 'en_US') ??
        firstWhere((s) => s.split('_').first == 'en');
  }

}

/// Maps the plugin's raw `onSoundLevelChange` value to the `0..1` envelope the
/// waveform renders. The raw scale is **platform-specific** because each native
/// side computes it differently (Risk 4 — heuristic, tune on a device):
///
/// - **Android** (`SpeechRecognizer.onRmsChanged`) reports an `rmsdB` envelope
///   roughly in `[-2, 10]`.
/// - **iOS / macOS** compute `20 * log10(rms)` over the PCM buffer — a *negative*
///   dBFS value, roughly `[-50, -10]` for typical speech.
///
/// A single fixed range cannot serve both: the Android range clamps every iOS
/// sample (all `< -2`) to `0`, flat-lining the waveform even though capture and
/// transcription work fine. So the range is chosen per platform.
class SoundLevelScale {
  const SoundLevelScale({required this.min, required this.max});

  /// Raw value mapped to `0`; anything at or below is silence.
  final double min;

  /// Raw value mapped to `1`; anything at or above is full amplitude.
  final double max;

  /// Android `rmsdB` envelope.
  static const SoundLevelScale android = SoundLevelScale(min: -2, max: 10);

  /// iOS / macOS dBFS envelope (`20 * log10(rms)`).
  static const SoundLevelScale darwin = SoundLevelScale(min: -50, max: -10);

  /// The scale matching the native plugin on the current platform.
  factory SoundLevelScale.forPlatform() =>
      (Platform.isIOS || Platform.isMacOS) ? darwin : android;

  /// Clamp [level] into `[min, max]` and scale to `0..1`. Tolerates `±∞`/`NaN`
  /// (a fully silent buffer yields `log10(0) = -∞`): both clamp to an endpoint.
  double normalize(double level) {
    if (level.isNaN) return 0;
    final clamped = level.clamp(min, max);
    return (clamped - min) / (max - min);
  }
}

// ---------------------------------------------------------------------------
// Plugin seam
// ---------------------------------------------------------------------------

typedef SttResultCallback = void Function(String words, bool isFinal);
typedef SttLevelCallback = void Function(double level);

/// Thin seam over the `speech_to_text` plugin so [SpeechToTextService]'s logic
/// can be exercised with a fake in unit tests (no platform channel / device).
abstract class SttPlugin {
  /// Initialize the recognizer (triggers the native permission prompt on the
  /// first call). Returns false if unavailable or permission denied.
  Future<bool> initialize();

  Future<bool> hasPermission();

  /// Recognition locale ids supported on this device (e.g. `pt_BR`, `en_US`).
  Future<List<String>> locales();

  /// Start an on-device listen session. [onResult] fires for partial + final
  /// results; [onLevel] feeds the sound-level envelope.
  Future<void> listen({
    required String localeId,
    required Duration listenFor,
    required SttResultCallback onResult,
    required SttLevelCallback onLevel,
  });

  Future<void> stop();

  Future<void> cancel();
}

/// Production [SttPlugin] wrapping the real `speech_to_text` plugin.
class SttPluginImpl implements SttPlugin {
  SttPluginImpl([stt.SpeechToText? plugin])
    : _stt = plugin ?? stt.SpeechToText();

  final stt.SpeechToText _stt;

  @override
  Future<bool> initialize() => _stt.initialize(
    // The error stream is consulted by the service only as a backstop for
    // the "listed locale, no on-device model" case; swallow here so a
    // transient error during init doesn't throw into the ViewModel.
    onError: (SpeechRecognitionError _) {},
  );

  @override
  Future<bool> hasPermission() => _stt.hasPermission;

  @override
  Future<List<String>> locales() async {
    final list = await _stt.locales();
    return [for (final l in list) l.localeId];
  }

  @override
  Future<void> listen({
    required String localeId,
    required Duration listenFor,
    required SttResultCallback onResult,
    required SttLevelCallback onLevel,
  }) async {
    await _stt.listen(
      onResult: (SpeechRecognitionResult r) =>
          onResult(r.recognizedWords, r.finalResult),
      onSoundLevelChange: onLevel,
      listenOptions: stt.SpeechListenOptions(
        // Decision #7 — local recognition only; audio never leaves the device.
        onDevice: true,
        // Accumulate partials internally (decision #6 hides them visually).
        partialResults: true,
        // Hold-to-talk: don't auto-stop on a pause; only the user release or
        // the listenFor cap ends the session.
        pauseFor: listenFor,
        listenFor: listenFor,
        localeId: localeId,
        cancelOnError: false,
      ),
    );
  }

  @override
  Future<void> stop() => _stt.stop();

  @override
  Future<void> cancel() => _stt.cancel();
}
