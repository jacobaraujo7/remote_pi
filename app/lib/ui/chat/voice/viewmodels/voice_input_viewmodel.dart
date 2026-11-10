import 'dart:async';

import 'package:app/data/voice/speech_service.dart';
import 'package:app/ui/chat/voice/states/voice_input_state.dart';
import 'package:app/ui/core/viewmodel/viewmodel.dart';

/// Plan 29 — drives the [SpeechService] for hold-to-talk voice input.
///
/// Lifecycle: [startRecording] (lazy [ensureInit] → native permission prompt
/// on first use, decision #10) → ticking [VoiceRecording] → [stopAndTranscribe]
/// (on release **or** the 60s cap, decision #5) returns the transcript for the
/// composer, or [cancel] (slide-to-cancel, decision #4) discards it.
///
/// The recognizer never auto-sends: the transcript is handed back to the
/// caller, which drops it into the empty `TextField` for manual review and
/// send (decision #3).
class VoiceInputViewModel extends ViewModel<VoiceInputState> {
  VoiceInputViewModel(
    this._service, {
    this.maxDuration = const Duration(seconds: 60),
    Duration tickInterval = const Duration(milliseconds: 200),
    String? Function()? preferredLocale,
  }) : _tickInterval = tickInterval,
       _preferredLocale = preferredLocale,
       super(const VoiceIdle());

  final SpeechService _service;

  /// Hard cap on a single recording (decision #5).
  final Duration maxDuration;
  final Duration _tickInterval;

  /// Returns the user-pinned recognition locale (e.g. `he_IL`), or `null`
  /// for the system default. Read on every [ensureInit] so a change in
  /// Settings takes effect without restarting the app.
  final String? Function()? _preferredLocale;

  SpeechAvailability? _availability;
  String? _localeId;
  /// The preferred-locale value the cached [_availability] was resolved
  /// against — when the Settings preference changes, the next init re-runs
  /// instead of returning the stale cached locale.
  String? _resolvedPreferred;
  StreamSubscription<double>? _levelSub;
  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  double _level = 0;
  bool _starting = false;

  /// Finalized transcripts, delivered the same way whether the session ended
  /// by user release or by the 60s cap (decision #5). The composer listens
  /// here and populates the empty `TextField` — a single source of truth, so
  /// the cap path can never silently drop a transcript.
  final StreamController<String> _transcripts =
      StreamController<String>.broadcast();
  Stream<String> get transcripts => _transcripts.stream;

  /// Resolve permission + on-device locale, caching the outcome. Idempotent:
  /// once [SpeechReady] is reached it short-circuits. On failure the state is
  /// updated to the matching [VoiceUnavailable] so the UI reacts.
  Future<SpeechAvailability> ensureInit() async {
    final preferred = _preferredLocale?.call();
    final cached = _availability;
    if (cached is SpeechReady && _resolvedPreferred == preferred) {
      return cached;
    }

    final result = await _service.init(preferredLocaleId: preferred);
    _resolvedPreferred = preferred;
    _availability = result;
    switch (result) {
      case SpeechReady(:final localeId):
        _localeId = localeId;
        if (state is VoiceUnavailable) emit(const VoiceIdle());
      case SpeechPermissionDenied():
        emit(const VoiceUnavailable(VoiceUnavailableReason.permissionDenied));
      case SpeechUnsupported():
        emit(const VoiceUnavailable(VoiceUnavailableReason.unsupported));
    }
    return result;
  }

  /// Begin a hold-to-talk session. No-op if already starting/recording.
  Future<void> startRecording() async {
    if (_starting || state is VoiceRecording) return;
    _starting = true;
    try {
      final availability = await ensureInit();
      if (availability is! SpeechReady) return; // state already reflects it

      _elapsed = Duration.zero;
      _level = 0;
      _levelSub?.cancel();
      _levelSub = _service.soundLevel.listen((level) {
        _level = level;
        if (state is VoiceRecording) {
          emit(VoiceRecording(elapsed: _elapsed, level: _level));
        }
      });

      await _service.start(localeId: _localeId!, maxDuration: maxDuration);
      emit(VoiceRecording(elapsed: _elapsed, level: _level));

      _ticker = Timer.periodic(_tickInterval, (_) {
        _elapsed += _tickInterval;
        if (_elapsed >= maxDuration) {
          // 60s cap — transcribe what we have, populate the field (#5).
          // ignore: discarded_futures
          stopAndTranscribe();
          return;
        }
        if (state is VoiceRecording) {
          emit(VoiceRecording(elapsed: _elapsed, level: _level));
        }
      });
    } finally {
      _starting = false;
    }
  }

  /// Stop and resolve with the transcript (may be empty → caller no-ops, #12).
  /// Idempotent: a concurrent call (release racing the cap) returns ''.
  Future<String> stopAndTranscribe() async {
    if (state is! VoiceRecording) return '';
    _stopTimers();
    emit(const VoiceTranscribing());
    final text = await _service.stop();
    emit(const VoiceIdle());
    if (!_transcripts.isClosed) _transcripts.add(text);
    return text;
  }

  /// Discard the recording (slide-to-cancel). Field stays untouched (#4).
  Future<void> cancel() async {
    if (state is! VoiceRecording && state is! VoiceTranscribing) return;
    _stopTimers();
    await _service.cancel();
    emit(const VoiceIdle());
  }

  void _stopTimers() {
    _ticker?.cancel();
    _ticker = null;
    _levelSub?.cancel();
    _levelSub = null;
  }

  @override
  void dispose() {
    _stopTimers();
    // Release the mic if we navigate away mid-recording. The service is an
    // app-lifecycle singleton, so we cancel the session but never dispose it.
    if (state is VoiceRecording || state is VoiceTranscribing) {
      // ignore: discarded_futures
      _service.cancel();
    }
    _transcripts.close();
    super.dispose();
  }
}
