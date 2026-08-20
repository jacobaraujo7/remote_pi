import 'package:app/data/preferences/preferences.dart';
import 'package:app/ui/core/themes/app_font_scale.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_key_value_store.dart';

void main() {
  group('Preferences', () {
    test('defaults to hideToolCalls=false before load()', () {
      final p = Preferences(FakeKeyValueStore());
      expect(p.hideToolCalls, isFalse);
    });

    test('load() hydrates from storage', () async {
      final store = FakeKeyValueStore();
      await store.write('prefs.hide_tool_calls', 'true');
      final p = Preferences(store);
      await p.load();
      expect(p.hideToolCalls, isTrue);
    });

    test('setHideToolCalls writes to storage and notifies', () async {
      final store = FakeKeyValueStore();
      final p = Preferences(store);
      var notifs = 0;
      p.addListener(() => notifs++);

      await p.setHideToolCalls(true);
      expect(p.hideToolCalls, isTrue);
      expect(await store.read('prefs.hide_tool_calls'), 'true');
      expect(notifs, 1);

      // No-op if value unchanged.
      await p.setHideToolCalls(true);
      expect(notifs, 1);

      await p.setHideToolCalls(false);
      expect(p.hideToolCalls, isFalse);
      expect(notifs, 2);
    });

    test('relayUrl defaults to null and round-trips via setRelayUrl',
        () async {
      final store = FakeKeyValueStore();
      final p = Preferences(store);
      expect(p.relayUrl, isNull);

      await p.setRelayUrl('wss://custom.example.com');
      expect(p.relayUrl, 'wss://custom.example.com');
      expect(await store.read('prefs.relay_url'), 'wss://custom.example.com');

      // Reload from cold start → value survives.
      final p2 = Preferences(store);
      await p2.load();
      expect(p2.relayUrl, 'wss://custom.example.com');

      // Clearing sends null and removes the key.
      await p.setRelayUrl(null);
      expect(p.relayUrl, isNull);
      expect(await store.read('prefs.relay_url'), isNull);

      // Empty string also clears.
      await p.setRelayUrl('wss://x');
      await p.setRelayUrl('');
      expect(p.relayUrl, isNull);
    });

    test(
      'onboardingCompleted defaults to false and round-trips via '
      'setOnboardingCompleted',
      () async {
        final store = FakeKeyValueStore();
        final p = Preferences(store);
        expect(p.onboardingCompleted, isFalse);

        await p.setOnboardingCompleted(true);
        expect(p.onboardingCompleted, isTrue);
        expect(await store.read('prefs.onboarding_completed'), 'true');

        final p2 = Preferences(store);
        await p2.load();
        expect(p2.onboardingCompleted, isTrue);
      },
    );

    test('selectedRoom round-trips epk + roomId composite (plan 17)',
        () async {
      final store = FakeKeyValueStore();
      final p = Preferences(store);
      await p.setSelectedRoom(epk: 'abc123', roomId: 'room-xyz');
      expect(p.selectedPeerEpk, 'abc123');
      expect(p.selectedRoomId, 'room-xyz');
      expect(p.selectedRoomRaw, 'abc123:room-xyz');

      // Reload from cold → preserved
      final p2 = Preferences(store);
      await p2.load();
      expect(p2.selectedPeerEpk, 'abc123');
      expect(p2.selectedRoomId, 'room-xyz');
    });

    test(
      'backward-compat: legacy value (no `:room` suffix) returns epk '
      'and null roomId so caller defaults to "main"',
      () async {
        final store = FakeKeyValueStore();
        // Pre-populate with legacy format (just the epk, no suffix).
        await store.write('prefs.selected_peer_epk', 'legacy_epk');
        final p = Preferences(store);
        await p.load();
        expect(p.selectedPeerEpk, 'legacy_epk');
        expect(p.selectedRoomId, isNull);
      },
    );

    // Issue #114 — in-app text size.
    test(
        'fontScale defaults to standard and round-trips through storage',
        () async {
      final store = FakeKeyValueStore();
      final p = Preferences(store);
      await p.load();
      expect(p.fontScale, AppFontScale.standard);

      await p.setFontScale(AppFontScale.large);
      expect(p.fontScale, AppFontScale.large);

      final reloaded = Preferences(store);
      await reloaded.load();
      expect(reloaded.fontScale, AppFontScale.large);
    });

    test('an unknown persisted font scale falls back to standard', () async {
      final store = FakeKeyValueStore();
      // A stale/corrupt value must never leave the app at an unreadable size.
      await store.write('prefs.font_scale', 'gigantic');
      final p = Preferences(store);
      await p.load();
      expect(p.fontScale, AppFontScale.standard);
    });

    test('setFontScale notifies listeners only on a real change', () async {
      final p = Preferences(FakeKeyValueStore());
      var calls = 0;
      p.addListener(() => calls++);

      await p.setFontScale(AppFontScale.small);
      expect(calls, 1);
      await p.setFontScale(AppFontScale.small);
      expect(calls, 1);
    });

    test('setSelectedRoom with null epk clears the selection', () async {
      final store = FakeKeyValueStore();
      final p = Preferences(store);
      await p.setSelectedRoom(epk: 'abc', roomId: 'r');
      expect(p.selectedPeerEpk, 'abc');
      await p.setSelectedRoom(epk: null);
      expect(p.selectedPeerEpk, isNull);
      expect(p.selectedRoomRaw, isNull);
    });
  });
}
