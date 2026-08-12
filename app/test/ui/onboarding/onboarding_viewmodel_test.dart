import 'package:app/data/preferences/preferences.dart';
import 'package:app/ui/onboarding/states/onboarding_state.dart';
import 'package:app/ui/onboarding/viewmodels/onboarding_viewmodel.dart';

import 'package:flutter_test/flutter_test.dart';
import '../../helpers/fake_key_value_store.dart';

Future<({Preferences prefs, OnboardingViewModel vm})> _setup() async {
  final prefs = Preferences(FakeKeyValueStore());
  final vm = OnboardingViewModel(prefs);
  return (prefs: prefs, vm: vm);
}

void main() {
  group('OnboardingViewModel', () {
    test('initial state is OnboardingInProgress(welcome, community)',
        () async {
      final s = await _setup();
      final state = s.vm.state;
      expect(state, isA<OnboardingInProgress>());
      final p = state as OnboardingInProgress;
      expect(p.step, OnboardingStep.welcome);
      expect(p.relayChoice, RelayChoice.community);
      expect(p.customRelayUrl, isEmpty);
      expect(p.customRelayError, isNull);
    });

    test('next() advances welcome → relay', () async {
      final s = await _setup();
      s.vm.next();
      expect((s.vm.state as OnboardingInProgress).step, OnboardingStep.relay);
    });

    test(
      'next() on relay step with community choice persists null relay '
      '(falls back to default) and advances to pair',
      () async {
        final s = await _setup();
        s.vm.next(); // → relay
        s.vm.next(); // community → pair
        expect((s.vm.state as OnboardingInProgress).step, OnboardingStep.pair);
        expect(s.prefs.relayUrl, isNull,
            reason: 'community choice clears the override');
      },
    );

    test(
      'next() on relay step with INVALID custom URL emits error + '
      'stays on relay step',
      () async {
        final s = await _setup();
        s.vm.next(); // → relay
        s.vm.setRelayChoice(RelayChoice.custom);
        s.vm.setCustomRelayUrl('not-a-url');
        s.vm.next(); // should not advance
        final state = s.vm.state as OnboardingInProgress;
        expect(state.step, OnboardingStep.relay);
        expect(state.customRelayError, isNotNull);
      },
    );

    test(
      'next() on relay step with VALID custom URL persists it and '
      'advances to pair',
      () async {
        final s = await _setup();
        s.vm.next(); // → relay
        s.vm.setRelayChoice(RelayChoice.custom);
        s.vm.setCustomRelayUrl('https://my-relay.example');
        s.vm.next();
        expect((s.vm.state as OnboardingInProgress).step, OnboardingStep.pair);
        // setRelayUrl is await-able but called fire-and-forget inside
        // the VM. Give the microtask a tick.
        await Future<void>.delayed(Duration.zero);
        expect(s.prefs.relayUrl, 'https://my-relay.example');
      },
    );

    test('back() walks pair → relay → welcome and stops there', () async {
      final s = await _setup();
      s.vm.next();
      s.vm.next();
      expect((s.vm.state as OnboardingInProgress).step, OnboardingStep.pair);
      s.vm.back();
      expect((s.vm.state as OnboardingInProgress).step, OnboardingStep.relay);
      s.vm.back();
      expect((s.vm.state as OnboardingInProgress).step, OnboardingStep.welcome);
      s.vm.back(); // no-op
      expect((s.vm.state as OnboardingInProgress).step, OnboardingStep.welcome);
    });

    test(
      'setCustomRelayUrl validates on-the-fly: invalid → error, empty → '
      'no error, valid → clear error',
      () async {
        final s = await _setup();
        s.vm.next();
        s.vm.setRelayChoice(RelayChoice.custom);

        s.vm.setCustomRelayUrl('ftp://nope');
        expect((s.vm.state as OnboardingInProgress).customRelayError,
            isNotNull);

        s.vm.setCustomRelayUrl('');
        expect((s.vm.state as OnboardingInProgress).customRelayError, isNull);

        s.vm.setCustomRelayUrl('https://localhost');
        expect((s.vm.state as OnboardingInProgress).customRelayError, isNull);
      },
    );

    test(
      'setCustomRelayUrl flags ws:// and wss:// with the scheme-specific '
      'hint about internal conversion',
      () async {
        final s = await _setup();
        s.vm.next();
        s.vm.setRelayChoice(RelayChoice.custom);

        s.vm.setCustomRelayUrl('ws://localhost');
        final err1 =
            (s.vm.state as OnboardingInProgress).customRelayError;
        expect(err1, isNotNull);
        expect(err1, contains('ws://'));
        expect(err1, contains('http://'));

        s.vm.setCustomRelayUrl('wss://relay.example');
        final err2 =
            (s.vm.state as OnboardingInProgress).customRelayError;
        expect(err2, isNotNull);
        expect(err2, contains('ws://'));
      },
    );

    test('completePairing flips onboardingCompleted and emits complete',
        () async {
      final s = await _setup();
      expect(s.prefs.onboardingCompleted, isFalse);
      await s.vm.completePairing();
      expect(s.prefs.onboardingCompleted, isTrue);
      expect(s.vm.state, isA<OnboardingComplete>());
    });
  });
}
