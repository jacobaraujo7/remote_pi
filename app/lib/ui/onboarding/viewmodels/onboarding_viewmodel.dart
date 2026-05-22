import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/transport/relay_config.dart';
import 'package:app/ui/core/viewmodel/viewmodel.dart';
import 'package:app/ui/onboarding/states/onboarding_state.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// Owns the 3-step onboarding flow. Pure state machine — the actual
/// pairing happens via [PairingViewModel] surfaced inside `pair_step.dart`.
/// Once pairing succeeds (callback into [completePairing]) the flag in
/// [Preferences] flips and the router redirects to `/home`.
class OnboardingViewModel extends ViewModel<OnboardingState> {
  final Preferences _prefs;

  OnboardingViewModel(this._prefs) : super(const OnboardingInProgress());

  // ---------------------------------------------------------------------------
  // Step navigation
  // ---------------------------------------------------------------------------

  void next() {
    final s = state;
    if (s is! OnboardingInProgress) return;
    switch (s.step) {
      case OnboardingStep.welcome:
        emit(s.copyWith(step: OnboardingStep.relay));
      case OnboardingStep.relay:
        // Validate the relay choice before advancing.
        if (s.relayChoice == RelayChoice.custom) {
          if (!isValidRelayUrl(s.customRelayUrl)) {
            emit(s.copyWith(
              customRelayError: 'URL must start with ws:// or wss://',
            ));
            return;
          }
        }
        // Persist relay (null = use default community).
        final urlToSave = s.relayChoice == RelayChoice.custom
            ? s.customRelayUrl
            : null;
        // ignore: unawaited_futures
        _prefs.setRelayUrl(urlToSave);
        emit(s.copyWith(step: OnboardingStep.pair, clearCustomError: true));
      case OnboardingStep.pair:
        // Advancing from pair happens via `completePairing` (callback
        // when pair_ok lands). Manual `next()` from pair is a no-op.
        debugPrint('[onboarding] next() ignored on pair step — use completePairing');
    }
  }

  void back() {
    final s = state;
    if (s is! OnboardingInProgress) return;
    switch (s.step) {
      case OnboardingStep.welcome:
        return; // first step — no back
      case OnboardingStep.relay:
        emit(s.copyWith(step: OnboardingStep.welcome));
      case OnboardingStep.pair:
        emit(s.copyWith(step: OnboardingStep.relay));
    }
  }

  // ---------------------------------------------------------------------------
  // Step 2 — relay configuration
  // ---------------------------------------------------------------------------

  void setRelayChoice(RelayChoice choice) {
    final s = state;
    if (s is! OnboardingInProgress) return;
    emit(s.copyWith(relayChoice: choice, clearCustomError: true));
  }

  /// Updates the in-flight custom URL string. Validates on-the-fly:
  /// inline error if non-empty + invalid. Empty input clears the error
  /// (user is still typing).
  void setCustomRelayUrl(String url) {
    final s = state;
    if (s is! OnboardingInProgress) return;
    String? error;
    if (url.isNotEmpty && !isValidRelayUrl(url)) {
      error = 'URL must start with ws:// or wss://';
    }
    emit(s.copyWith(
      customRelayUrl: url,
      customRelayError: error,
      clearCustomError: error == null,
    ));
  }

  // ---------------------------------------------------------------------------
  // Step 3 — pairing success
  // ---------------------------------------------------------------------------

  /// Called by `pair_step.dart` when the underlying PairingViewModel
  /// reports a successful pair_ok. Flips the onboarding flag in
  /// preferences and transitions to [OnboardingComplete] — the
  /// OnboardingPage observes that and navigates to `/home`.
  Future<void> completePairing() async {
    await _prefs.setOnboardingCompleted(true);
    emit(const OnboardingComplete());
  }
}
