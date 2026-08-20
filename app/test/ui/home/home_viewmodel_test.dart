import 'dart:async';
import 'dart:typed_data';

import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/data/transport/peer_channel.dart';
import 'package:app/pairing/pair_request_flow.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/ui/home/states/home_state.dart';
import 'package:app/ui/home/viewmodels/home_viewmodel.dart';

import 'package:flutter_test/flutter_test.dart';
import '../../helpers/fake_key_value_store.dart';

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

  // Rooms persistence is exercised when a RoomAnnounced lands on a real
  // ConnectionManager (_persistRoomsForPeer). Keep it in-memory so the
  // test never touches flutter_secure_storage (no binding in unit tests).
  final Map<String, List<PersistedRoom>> _rooms = {};
  @override
  Future<void> saveRooms(String epk, List<PersistedRoom> rooms) async {
    _rooms[epk] = rooms;
  }

  @override
  Future<List<PersistedRoom>> loadRooms(String epk) async =>
      _rooms[epk] ?? const [];

  @override
  Future<void> deleteRooms(String epk) async {
    _rooms.remove(epk);
  }
}

const _peerA = PeerRecord(
  remoteEpk: 'epk_A',
  sessionName: 'Pi A',
  relayUrl: 'ws://localhost',
  pairedAt: '2026-01-01T00:00:00Z',
);
const _peerB = PeerRecord(
  remoteEpk: 'epk_B',
  sessionName: 'Pi B',
  relayUrl: 'ws://localhost',
  pairedAt: '2026-01-02T00:00:00Z',
);

class _NoopTransport implements PeerTransport {
  @override
  Future<void> send(Uint8List data) async {}
  @override
  Future<Uint8List> receive() => Completer<Uint8List>().future;
  @override
  Future<void> close() async {}
}

PlainPeerChannel _channel() => PlainPeerChannel(transport: _NoopTransport());

/// Lets a test inject relay control frames (presence / rooms / working)
/// into a real ConnectionManager.
class _ControllableChannel implements IChannel, IControlLink {
  final _serverCtrl = StreamController<ServerMessage>.broadcast();
  final _controlCtrl = StreamController<ControlInbound>.broadcast();

  @override
  Stream<ServerMessage> get serverMessages => _serverCtrl.stream;
  @override
  Stream<ControlInbound> get controlFrames => _controlCtrl.stream;
  @override
  Future<void> send(ClientMessage msg) async {}
  @override
  void sendControl(Map<String, dynamic> json) {}
  @override
  Future<void> close() async {
    await _serverCtrl.close();
    await _controlCtrl.close();
  }

  void pushControl(ControlInbound m) => _controlCtrl.add(m);
}

ConnectionManager _conn({_FakeStorage? storage}) {
  return ConnectionManager(
    factory: (_, _) async => _channel(),
    storage: storage ?? _FakeStorage([]),
  );
}

void main() {
  group('HomeViewModel', () {
    test(
      'isRoomWorking follows the relay meta.working broadcast for ANY room — '
      'including one that is NOT the connected session, and clears when the '
      'relay says the turn ended (plan/32)',
      () async {
        // Reproduces the smoke-test bugs in sequence:
        //  1) the dot only lit for the active chat (working came from the
        //     connected peer's message channel), and
        //  2) a session that FINISHED while the app was on another chat
        //     stayed blue forever (the DB session index never got idled).
        // Home now reads ONLY ConnectionManager.isRoomWorking — the relay's
        // per-room broadcast — which has no such blind spot.
        final ch = _ControllableChannel();
        final storage = _FakeStorage([_peerA]);
        final conn = ConnectionManager(
          factory: (_, _) async => ch,
          storage: storage,
          emitDebounce: Duration.zero,
        );
        final prefs = Preferences(FakeKeyValueStore());
        final vm = HomeViewModel(storage, prefs, conn);
        await conn.connectTo(_peerA);
        await Future<void>.delayed(const Duration(milliseconds: 10));

        // Room comes online idle.
        ch.pushControl(
          const RoomAnnounced(peer: 'epk_A', roomId: 'r1', startedAt: 1),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(vm.isRoomWorking('epk_A', 'r1'), isFalse);

        // turn_start → relay broadcasts meta.working=true.
        ch.pushControl(
          const RoomMetaUpdated(
            peer: 'epk_A',
            roomId: 'r1',
            working: true,
            hasModel: false,
            hasThinking: false,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(vm.isRoomWorking('epk_A', 'r1'), isTrue);

        // turn_end → meta.working=false → dot goes back off (this is the
        // case that previously stayed blue forever).
        ch.pushControl(
          const RoomMetaUpdated(
            peer: 'epk_A',
            roomId: 'r1',
            working: false,
            hasModel: false,
            hasThinking: false,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(vm.isRoomWorking('epk_A', 'r1'), isFalse);

        vm.dispose();
        await conn.disconnect();
        conn.dispose();
      },
    );

    test('initial state is HomeLoading', () {
      final storage = _FakeStorage([_peerA]);
      final prefs = Preferences(FakeKeyValueStore());
      final vm = HomeViewModel(storage, prefs, _conn(storage: storage));
      expect(vm.state, isA<HomeLoading>());
      vm.dispose();
    });

    test('empty storage → HomeNoPeer', () async {
      final storage = _FakeStorage([]);
      final prefs = Preferences(FakeKeyValueStore());
      final vm = HomeViewModel(storage, prefs, _conn(storage: storage));
      await Future<void>.delayed(Duration.zero);
      expect(vm.state, isA<HomeNoPeer>());
      vm.dispose();
    });

    test('two peers → HomeList containing both', () async {
      final storage = _FakeStorage([_peerA, _peerB]);
      final prefs = Preferences(FakeKeyValueStore());
      final vm = HomeViewModel(storage, prefs, _conn(storage: storage));
      await Future<void>.delayed(Duration.zero);

      final s = vm.state as HomeList;
      expect(s.peers.map((p) => p.remoteEpk), ['epk_A', 'epk_B']);

      vm.dispose();
    });

    test('openSession writes selectedPeerEpk to Preferences', () async {
      final storage = _FakeStorage([_peerA, _peerB]);
      final prefs = Preferences(FakeKeyValueStore());
      final vm = HomeViewModel(storage, prefs, _conn(storage: storage));
      await Future<void>.delayed(Duration.zero);

      await vm.openSession('epk_B');
      expect(prefs.selectedPeerEpk, 'epk_B');

      vm.dispose();
    });

    test(
      'plano app-state-normalization: openSession ONLY sets prefs '
      '(no switchTo from Home — boot races would otherwise happen)',
      () async {
        final storage = _FakeStorage([_peerA, _peerB]);
        final prefs = Preferences(FakeKeyValueStore());
        final connects = <String>[];
        final conn = ConnectionManager(
          factory: (peer, _) async {
            connects.add(peer.remoteEpk);
            return _channel();
          },
          storage: storage,
        );
        final vm = HomeViewModel(storage, prefs, conn);
        await Future<void>.delayed(Duration.zero);

        await vm.openSession('epk_B');
        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(prefs.selectedPeerEpk, 'epk_B');
        expect(
          connects,
          isEmpty,
          reason:
              'Home must NOT call the connection factory — chat owns '
              'the switchTo decision',
        );
        expect(conn.activePeer, isNull);

        vm.dispose();
        conn.dispose();
      },
    );

    test('openSession with unknown epk is a no-op', () async {
      final storage = _FakeStorage([_peerA]);
      final prefs = Preferences(FakeKeyValueStore());
      final vm = HomeViewModel(storage, prefs, _conn(storage: storage));
      await Future<void>.delayed(Duration.zero);

      await vm.openSession('epk_unknown');
      expect(prefs.selectedPeerEpk, isNull);

      vm.dispose();
    });

    test(
      'openSession with roomId persists the composite epk:room AND '
      'awaits before returning — caller can rely on Preferences being '
      'updated before navigating to /chat (race-condition regression)',
      () async {
        final storage = _FakeStorage([_peerA]);
        final prefs = Preferences(FakeKeyValueStore());
        final vm = HomeViewModel(storage, prefs, _conn(storage: storage));
        await Future<void>.delayed(Duration.zero);

        // Seed prefs with a DIFFERENT room (simulating the previous
        // chat the user was looking at).
        await prefs.setSelectedRoom(epk: 'epk_A', roomId: 'room-previous');
        expect(prefs.selectedRoomId, 'room-previous');

        // Now tap a new room → openSession completes, prefs reflect it.
        await vm.openSession('epk_A', roomId: 'room-target');

        // After awaiting openSession, prefs ARE updated. If
        // ChatViewModel.bootstrap reads prefs at this point, it sees
        // the correct room.
        expect(prefs.selectedPeerEpk, 'epk_A');
        expect(prefs.selectedRoomId, 'room-target');

        vm.dispose();
      },
    );
  });

  group('HomeViewModel — presence filter (plan-38 Fase 3)', () {
    test('counts / visibleItems split rooms by liveness; setFilter re-derives '
        'without reloading', () async {
      final ch = _ControllableChannel();
      final storage = _FakeStorage([_peerA]);
      final conn = ConnectionManager(
        factory: (_, _) async => ch,
        storage: storage,
        emitDebounce: Duration.zero,
      );
      final prefs = Preferences(FakeKeyValueStore());
      final vm = HomeViewModel(storage, prefs, conn);
      await conn.connectTo(_peerA);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // r1 stays live; r2 is announced then ended → cached but offline
      // (grey tile — still in _roomsByPeer, dropped from _liveRoomIds).
      ch.pushControl(
        const RoomAnnounced(peer: 'epk_A', roomId: 'r1', startedAt: 1),
      );
      ch.pushControl(
        const RoomAnnounced(peer: 'epk_A', roomId: 'r2', startedAt: 2),
      );
      ch.pushControl(const RoomEnded(peer: 'epk_A', roomId: 'r2', sinceTs: 3));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Sanity — one live, one cached/offline.
      expect(vm.isRoomLive('epk_A', 'r1'), isTrue);
      expect(vm.isRoomLive('epk_A', 'r2'), isFalse);

      // Counts are independent of the selected tab.
      expect(vm.counts, (all: 2, online: 1, offline: 1));

      // Default tab is Online → only the live room is visible.
      expect((vm.state as HomeList).filter, HomeFilter.online);
      expect(vm.visibleItems.map((i) => i.room.roomId).toList(), ['r1']);

      // Offline → only the cached room.
      vm.setFilter(HomeFilter.offline);
      expect((vm.state as HomeList).filter, HomeFilter.offline);
      expect(vm.visibleItems.map((i) => i.room.roomId).toList(), ['r2']);

      // All → both (sorted), and the counts are unchanged.
      vm.setFilter(HomeFilter.all);
      expect(vm.visibleItems.map((i) => i.room.roomId).toList(), ['r1', 'r2']);
      expect(vm.counts, (all: 2, online: 1, offline: 1));

      vm.dispose();
      await conn.disconnect();
      conn.dispose();
    });

    test(
      'setFilter is a no-op when the tab is unchanged, and emits exactly once '
      'when it changes',
      () async {
        final storage = _FakeStorage([_peerA]);
        final prefs = Preferences(FakeKeyValueStore());
        final vm = HomeViewModel(storage, prefs, _conn(storage: storage));
        await Future<void>.delayed(Duration.zero);

        expect((vm.state as HomeList).filter, HomeFilter.online);
        var notifies = 0;
        vm.addListener(() => notifies++);

        vm.setFilter(HomeFilter.online); // same tab → no emit
        expect(notifies, 0);

        vm.setFilter(HomeFilter.offline); // changed → one emit
        expect(notifies, 1);
        expect((vm.state as HomeList).filter, HomeFilter.offline);

        vm.dispose();
      },
    );

    test('counts / visibleItems are empty-safe outside a HomeList', () {
      final storage = _FakeStorage([_peerA]);
      final prefs = Preferences(FakeKeyValueStore());
      final vm = HomeViewModel(storage, prefs, _conn(storage: storage));

      // Synchronously still HomeLoading — the getters must not throw.
      expect(vm.state, isA<HomeLoading>());
      expect(vm.counts, (all: 0, online: 0, offline: 0));
      expect(vm.visibleItems, isEmpty);

      vm.dispose();
    });
  });
}
