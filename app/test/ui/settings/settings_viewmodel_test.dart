import 'dart:async';
import 'dart:typed_data';

import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/data/transport/peer_channel.dart';
import 'package:app/data/transport/relay_config.dart';
import 'package:app/pairing/pair_request_flow.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/ui/settings/states/settings_state.dart';
import 'package:app/ui/settings/viewmodels/settings_viewmodel.dart';

import 'package:flutter_test/flutter_test.dart';
import '../../helpers/fake_key_value_store.dart';

class _NoopTransport implements PeerTransport {
  @override Future<void> send(Uint8List data) async {}
  @override Future<Uint8List> receive() => Completer<Uint8List>().future;
  @override Future<void> close() async {}
}

PlainPeerChannel _channel() => PlainPeerChannel(transport: _NoopTransport());

ConnectionManager _conn({_FakeStorage? storage}) {
  return ConnectionManager(
    factory: (_, _) async => _channel(),
    storage: storage ?? _FakeStorage([]),
  );
}

class _FakeStorage extends PairingStorage {
  List<PeerRecord> peers;
  _FakeStorage(this.peers);

  @override
  Future<List<PeerRecord>> listPeers() async => List.of(peers);

  @override
  Future<void> savePeer(PeerRecord r) async {
    peers = [r, ...peers.where((p) => p.remoteEpk != r.remoteEpk)];
  }

  @override
  Future<void> deletePeer(String epk) async {
    peers = peers.where((p) => p.remoteEpk != epk).toList();
  }

  @override
  Future<void> deletePeerSilent(String epk) async {
    peers = peers.where((p) => p.remoteEpk != epk).toList();
  }
}

PeerRecord _peerA() => const PeerRecord(
  remoteEpk: 'epk_A',
  sessionName: 'Pi A',
  relayUrl: 'ws://localhost',
  pairedAt: '2026-01-01T00:00:00Z',
);

void main() {
  group('SettingsViewModel', () {
    test('initial state is SettingsLoading', () {
      final storage = _FakeStorage([_peerA()]);
      final prefs = Preferences(FakeKeyValueStore());
      final vm = SettingsViewModel(storage, prefs, _conn(storage: storage));
      expect(vm.state, isA<SettingsLoading>());
      vm.dispose();
    });

    test('empty storage → SettingsNoPeer', () async {
      final storage = _FakeStorage([]);
      final prefs = Preferences(FakeKeyValueStore());
      final vm = SettingsViewModel(storage, prefs, _conn(storage: storage));
      await Future<void>.delayed(Duration.zero);
      expect(vm.state, isA<SettingsNoPeer>());
      vm.dispose();
    });

    test('peers loaded → SettingsList', () async {
      final storage = _FakeStorage([_peerA()]);
      final prefs = Preferences(FakeKeyValueStore());
      final vm = SettingsViewModel(storage, prefs, _conn(storage: storage));
      await Future<void>.delayed(Duration.zero);

      final s = vm.state as SettingsList;
      expect(s.peers.single.remoteEpk, 'epk_A');

      vm.dispose();
    });

    test('revoke deletes peer + clears selectedPeerEpk if it matched',
        () async {
      final storage = _FakeStorage([_peerA()]);
      final prefs = Preferences(FakeKeyValueStore());
      await prefs.setSelectedPeerEpk('epk_A');

      final vm = SettingsViewModel(storage, prefs, _conn(storage: storage));
      await Future<void>.delayed(Duration.zero);

      await vm.revoke('epk_A');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(storage.peers, isEmpty);
      expect(prefs.selectedPeerEpk, isNull);
      expect(vm.state, isA<SettingsNoPeer>());

      vm.dispose();
    });

    test('revoke does NOT touch selectedPeerEpk if different', () async {
      final storage = _FakeStorage([_peerA()]);
      final prefs = Preferences(FakeKeyValueStore());
      await prefs.setSelectedPeerEpk('epk_other');

      final vm = SettingsViewModel(storage, prefs, _conn(storage: storage));
      await Future<void>.delayed(Duration.zero);

      await vm.revoke('epk_A');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(prefs.selectedPeerEpk, 'epk_other');

      vm.dispose();
    });

    test('setNickname updates state and storage', () async {
      final storage = _FakeStorage([_peerA()]);
      final prefs = Preferences(FakeKeyValueStore());
      final vm = SettingsViewModel(storage, prefs, _conn(storage: storage));
      await Future<void>.delayed(Duration.zero);

      await vm.setNickname('epk_A', 'Casa');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final s = vm.state as SettingsList;
      expect(s.peers.single.nickname, 'Casa');
      expect(storage.peers.single.nickname, 'Casa');

      vm.dispose();
    });

    test('setNickname with null clears the nickname', () async {
      final storage = _FakeStorage([
        _peerA().copyWith(nickname: 'Casa'),
      ]);
      final prefs = Preferences(FakeKeyValueStore());
      final vm = SettingsViewModel(storage, prefs, _conn(storage: storage));
      await Future<void>.delayed(Duration.zero);

      await vm.setNickname('epk_A', null);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect((vm.state as SettingsList).peers.single.nickname, isNull);
      expect(storage.peers.single.nickname, isNull);

      vm.dispose();
    });

    test('setNickname with whitespace clears the nickname', () async {
      final storage = _FakeStorage([
        _peerA().copyWith(nickname: 'Casa'),
      ]);
      final prefs = Preferences(FakeKeyValueStore());
      final vm = SettingsViewModel(storage, prefs, _conn(storage: storage));
      await Future<void>.delayed(Duration.zero);

      await vm.setNickname('epk_A', '   ');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect((vm.state as SettingsList).peers.single.nickname, isNull);

      vm.dispose();
    });

    test('setNickname is a no-op for unknown epk', () async {
      final storage = _FakeStorage([_peerA()]);
      final prefs = Preferences(FakeKeyValueStore());
      final vm = SettingsViewModel(storage, prefs, _conn(storage: storage));
      await Future<void>.delayed(Duration.zero);

      await vm.setNickname('epk_does_not_exist', 'Casa');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(storage.peers.single.nickname, isNull);

      vm.dispose();
    });
  });

  group('SettingsViewModel — plan 14 relay config', () {
    test('saveRelayUrl with valid URL persists override + returns null',
        () async {
      final prefs = Preferences(FakeKeyValueStore());
      final vm = SettingsViewModel(_FakeStorage([]), prefs, _conn());
      await Future<void>.delayed(Duration.zero);

      final err = await vm.saveRelayUrl('https://custom.example');
      expect(err, isNull);
      expect(prefs.relayUrl, 'https://custom.example');
      expect(vm.effectiveRelayUrl, 'https://custom.example');

      vm.dispose();
    });

    test(
      'saveRelayUrl with invalid URL returns error and does NOT persist',
      () async {
        final prefs = Preferences(FakeKeyValueStore());
        final vm = SettingsViewModel(_FakeStorage([]), prefs, _conn());
        await Future<void>.delayed(Duration.zero);

        final err = await vm.saveRelayUrl('not-a-url');
        expect(err, isNotNull);
        expect(prefs.relayUrl, isNull);

        vm.dispose();
      },
    );

    test('saveRelayUrl rejects ws:// / wss:// with the scheme-specific hint',
        () async {
      final prefs = Preferences(FakeKeyValueStore());
      final vm = SettingsViewModel(_FakeStorage([]), prefs, _conn());
      await Future<void>.delayed(Duration.zero);

      final err = await vm.saveRelayUrl('wss://relay.example');
      expect(err, isNotNull);
      expect(err, contains('ws://'));
      expect(err, contains('http://'));
      expect(prefs.relayUrl, isNull);

      vm.dispose();
    });

    test(
      'saveRelayUrl with empty / null is rejected (URL is now required) and '
      'does NOT clear the existing override',
      () async {
        final prefs = Preferences(FakeKeyValueStore());
        await prefs.setRelayUrl('https://x.example');
        final vm = SettingsViewModel(_FakeStorage([]), prefs, _conn());
        await Future<void>.delayed(Duration.zero);

        // Empty → error, override untouched.
        final emptyErr = await vm.saveRelayUrl('');
        expect(emptyErr, isNotNull);
        expect(prefs.relayUrl, 'https://x.example');

        // Whitespace-only → same (trimmed to empty).
        final blankErr = await vm.saveRelayUrl('   ');
        expect(blankErr, isNotNull);
        expect(prefs.relayUrl, 'https://x.example');

        // null → same.
        final nullErr = await vm.saveRelayUrl(null);
        expect(nullErr, isNotNull);
        expect(prefs.relayUrl, 'https://x.example');

        vm.dispose();
      },
    );

    test(
      'relayUrlOverride defaults to kDefaultRelayUrl (pre-fill for the '
      '"use default" button) and reflects a saved override',
      () async {
        final prefs = Preferences(FakeKeyValueStore());
        final vm = SettingsViewModel(_FakeStorage([]), prefs, _conn());
        await Future<void>.delayed(Duration.zero);

        // No override yet → the field pre-fills with the default endpoint.
        expect(vm.relayUrlOverride, kDefaultRelayUrl);
        expect(vm.effectiveRelayUrl, kDefaultRelayUrl);

        // Saving the default URL explicitly is valid (what the button does).
        final err = await vm.saveRelayUrl(kDefaultRelayUrl);
        expect(err, isNull);
        expect(vm.relayUrlOverride, kDefaultRelayUrl);
        expect(prefs.relayUrl, kDefaultRelayUrl);

        vm.dispose();
      },
    );
  });
}
