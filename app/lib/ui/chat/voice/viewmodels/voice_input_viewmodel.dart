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
  }) : _tickInterval = tickInterval,
       super(const VoiceIdle());

  final SpeechService _service;

  /// Hard cap on a single recording (decision #5).
  final Duration maxDuration;
  final Duration _tickInterval;

  SpeechAvailability? _availability;
  String? _localeId;
  StreamSubscription<double>? _levelSub;
  StreamSubscription<SpeechFailure>? _errorSub;
  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  double _level = 0;
  bool _starting = false;

  /// [SpeechService.start] is in flight: a recognizer error now belongs to
  /// this capture even though recording hasn't been shown yet.
  bool _awaitingStart = false;

  /// An error ended the capture while [_awaitingStart]; the pending start
  /// must not enter [VoiceRecording].
  bool _startFailed = false;

  /// Finalized transcripts, delivered the same way whether the session ended
  /// by user release or by the 60s cap (decision #5). The composer listens
  /// here and populates the empty `TextField` — a single source of truth, so
  /// the cap path can never silently drop a transcript.
  final StreamController<String> _transcripts =
      StreamController<String>.broadcast();
  Stream<String> get transcripts => _transcripts.stream;

  /// Recognizer failures that ended a recording early. The composer turns
  /// them into a hint so the user knows why no text appeared.
  final StreamController<SpeechFailure> _failures =
      StreamController<SpeechFailure>.broadcast();
  Stream<SpeechFailure> get failures => _failures.stream;

  /// Resolve permission + on-device locale, caching the outcome. Idempotent:
  /// once [SpeechReady] is reached it short-circuits. On failure the state is
  /// updated to the matching [VoiceUnavailable] so the UI reacts.
  Future<SpeechAvailability> ensureInit() async {
    final cached = _availability;
    if (cached is SpeechReady) return cached;

    final result = await _service.init();
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

  /// Begin a hold-to-talk session. No-op while starting, recording or
  /// transcribing: the previous capture's transcript is still on its way.
  Future<void> startRecording() async {
    if (_starting || state is VoiceRecording || state is VoiceTranscribing) {
      return;
    }
    _starting = true;
    try {
      final availability = await ensureInit();
      if (availability is! SpeechReady) return; // state already reflects it

      _elapsed = Duration.zero;
      _level = 0;
      _errorSub ??= _service.errors.listen(_onError);
      _levelSub?.cancel();
      _levelSub = _service.soundLevel.listen((level) {
        _level = level;
        if (state is VoiceRecording) {
          emit(VoiceRecording(elapsed: _elapsed, level: _level));
        }
      });

      _startFailed = false;
      _awaitingStart = true;
      try {
        await _service.start(localeId: _localeId!, maxDuration: maxDuration);
      } finally {
        _awaitingStart = false;
      }
      if (_startFailed) return; // _onError already ended and reported it
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

  /// The recognizer gave up while the mic is still held (or while it was
  /// still starting): end the session now instead of recording into a dead
  /// recognizer until release.
  Future<void> _onError(SpeechFailure failure) async {
    if (_awaitingStart) {
      _startFailed = true;
    } else if (state is! VoiceRecording) {
      return;
    }
    _stopTimers();
    emit(const VoiceIdle());
    if (!_failures.isClosed) _failures.add(failure);
    await _service.cancel();
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
    _errorSub?.cancel();
    _transcripts.close();
    _failures.close();
    super.dispose();
  }
}
