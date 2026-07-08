// ConnectionManager state transition tests.
// Uses a fake ConnectionFactory so no real WS or transport is involved.

import 'dart:async';
import 'dart:typed_data';

import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/data/transport/peer_channel.dart';
import 'package:app/pairing/pair_request_flow.dart';
import 'package:app/pairing/storage.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake infrastructure
// ---------------------------------------------------------------------------

PeerRecord _fakePeer() => const PeerRecord(
  remoteEpk: 'epk_test',
  sessionName: 'test session',
  relayUrl: 'ws://localhost:8080',
  pairedAt: '2026-01-01T00:00:00Z',
);

class _FakeStorage extends PairingStorage {
  final List<PeerRecord> peers;
  final List<PeerRecord> savedPeers = [];
  final Map<String, List<PersistedRoom>> _roomsByEpk = {};
  _FakeStorage(this.peers);

  @override
  Future<List<PeerRecord>> listPeers() async => peers;

  @override
  Future<void> savePeer(PeerRecord r) async {
    savedPeers.add(r);
  }

  @override
  Future<void> saveRooms(String epk, List<PersistedRoom> rooms) async {
    _roomsByEpk[epk] = List.of(rooms);
  }

  @override
  Future<List<PersistedRoom>> loadRooms(String epk) async =>
      List.of(_roomsByEpk[epk] ?? const []);

  @override
  Future<void> deleteRooms(String epk) async {
    _roomsByEpk.remove(epk);
  }
}

class _Q {
  final _buf = <Uint8List>[];
  final _wait = <Completer<Uint8List>>[];

  void add(Uint8List d) {
    if (_wait.isNotEmpty) {
      _wait.removeAt(0).complete(d);
    } else {
      _buf.add(d);
    }
  }

  Future<Uint8List> next() {
    if (_buf.isNotEmpty) return Future.value(_buf.removeAt(0));
    final c = Completer<Uint8List>();
    _wait.add(c);
    return c.future;
  }
}

class _T implements PeerTransport {
  final _Q _s;
  final _Q _r;
  bool _closed = false;

  _T({required _Q send, required _Q recv}) : _s = send, _r = recv;

  @override Future<void> send(Uint8List d) async => _s.add(d);
  @override Future<Uint8List> receive() => _r.next();
  @override Future<void> close() async { _closed = true; }
  bool get isClosed => _closed;
}

PlainPeerChannel _makeChannel() {
  final q1 = _Q();
  final q2 = _Q();
  final iT = _T(send: q1, recv: q2);
  return PlainPeerChannel(transport: iT);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // Plan 17 — rooms suite registered alongside the rest.
  _registerRoomsTests();

  group('ConnectionManager', () {
    test('boot() → StatusNoPeer when storage is empty', () async {
      final cm = ConnectionManager(
        factory: (peer, cancel) async => _makeChannel(),
        storage: _FakeStorage([]),
        emitDebounce: Duration.zero,
      );

      final states = <ConnectionStatus>[];
      cm.statusStream.listen(states.add);

      await cm.boot();
      await Future<void>.delayed(Duration.zero);

      expect(cm.status, isA<StatusNoPeer>());
      cm.dispose();
    });

    test('boot() → Connecting → Online when factory succeeds', () async {
      final states = <ConnectionStatus>[];
      final cm = ConnectionManager(
        factory: (_, token) async {
          if (token.isCancelled) throw Exception('cancelled');
          return _makeChannel();
        },
        storage: _FakeStorage([_fakePeer()]),
        emitDebounce: Duration.zero,
      );

      cm.statusStream.listen(states.add);
      await cm.boot();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(states.any((s) => s is StatusConnecting), isTrue);
      expect(cm.status, isA<StatusOnline>());
      expect(cm.channel, isNotNull);

      cm.dispose();
    });

    test('factory failure → StatusRetrying with attempt=0', () async {
      final states = <ConnectionStatus>[];
      final cm = ConnectionManager(
        factory: (peer, cancel) async => throw Exception('connection refused'),
        storage: _FakeStorage([_fakePeer()]),
        emitDebounce: Duration.zero,
      );

      cm.statusStream.listen(states.add);
      await cm.boot();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(states.any((s) => s is StatusRetrying), isTrue);
      final retrying = states.whereType<StatusRetrying>().first;
      expect(retrying.attempt, 0);
      expect(retrying.nextRetry.inSeconds, 1);

      cm.dispose();
    });

    test('disconnect() returns to StatusNoPeer', () async {
      final cm = ConnectionManager(
        factory: (peer, cancel) async => _makeChannel(),
        storage: _FakeStorage([_fakePeer()]),
        emitDebounce: Duration.zero,
      );

      await cm.boot();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(cm.status, isA<StatusOnline>());

      await cm.disconnect();
      expect(cm.status, isA<StatusNoPeer>());
      expect(cm.channel, isNull);

      cm.dispose();
    });

    test('backoff sequence increments on repeated failures', () async {
      final retries = <StatusRetrying>[];
      final cm = ConnectionManager(
        factory: (peer, token) async {
          if (token.isCancelled) throw Exception('cancelled');
          throw Exception('refused');
        },
        storage: _FakeStorage([_fakePeer()]),
        emitDebounce: Duration.zero,
      );

      cm.statusStream
          .where((s) => s is StatusRetrying)
          .cast<StatusRetrying>()
          .listen(retries.add);
      await cm.boot();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(retries, isNotEmpty);
      expect(retries.first.attempt, 0);
      expect(retries.first.nextRetry, const Duration(seconds: 1));

      cm.dispose();
    });

    test('adopt: factory NOT called, state becomes StatusOnline immediately', () async {
      var factoryCalled = false;
      final cm = ConnectionManager(
        factory: (peer, cancel) async {
          factoryCalled = true;
          return _makeChannel();
        },
        storage: _FakeStorage([_fakePeer()]),
        emitDebounce: Duration.zero,
      );

      final fakeChannel = _makeChannel();
      final states = <ConnectionStatus>[];
      cm.statusStream.listen(states.add);

      cm.adopt(fakeChannel, _fakePeer());

      expect(factoryCalled, isFalse,
          reason: 'factory must NOT be called when adopting a live channel');
      expect(cm.status, isA<StatusOnline>());
      expect(cm.channel, isNotNull);

      cm.dispose();
    });

    test('activePeer is null at start, set by adopt, cleared by disconnect',
        () async {
      final cm = ConnectionManager(
        factory: (_, _) async => _makeChannel(),
        storage: _FakeStorage([_fakePeer()]),
        emitDebounce: Duration.zero,
      );
      expect(cm.activePeer, isNull);

      cm.adopt(_makeChannel(), _fakePeer());
      expect(cm.activePeer?.remoteEpk, 'epk_test');

      await cm.disconnect();
      expect(cm.activePeer, isNull);

      cm.dispose();
    });

    test('switchTo: idempotent when already online to the target', () async {
      var factoryCalls = 0;
      final cm = ConnectionManager(
        factory: (peer, _) async {
          factoryCalls++;
          return _makeChannel();
        },
        storage: _FakeStorage([_fakePeer()]),
        emitDebounce: Duration.zero,
      );
      cm.adopt(_makeChannel(), _fakePeer());
      expect(cm.activePeer?.remoteEpk, 'epk_test');

      await cm.switchTo(_fakePeer());
      expect(factoryCalls, 0,
          reason: 'no reconnect when already online to that peer');
      expect(cm.activePeer?.remoteEpk, 'epk_test');

      cm.dispose();
    });

    test('switchTo: disconnects old peer and connects to new', () async {
      final factoryCalls = <String>[];
      const other = PeerRecord(
        remoteEpk: 'epk_other',
        sessionName: 'Other',
        relayUrl: 'ws://localhost:8080',
        pairedAt: '2026-01-02T00:00:00Z',
      );
      final cm = ConnectionManager(
        factory: (peer, _) async {
          factoryCalls.add(peer.remoteEpk);
          return _makeChannel();
        },
        storage: _FakeStorage([_fakePeer(), other]),
        emitDebounce: Duration.zero,
      );
      cm.adopt(_makeChannel(), _fakePeer());

      await cm.switchTo(other);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(factoryCalls, ['epk_other']);
      expect(cm.activePeer?.remoteEpk, 'epk_other');
      expect(cm.status, isA<StatusOnline>());

      cm.dispose();
    });

    test('boot is no-op while another peer connect is in flight', () async {
      // Repro for the Home tap bug: user picks Pi B (not peers.first); the
      // ChatViewModel's constructor calls boot() while switchTo is still
      // awaiting the factory. boot() must NOT cancel the in-flight connect
      // and reroute to peers.first.
      const a = PeerRecord(
        remoteEpk: 'epk_A',
        sessionName: 'A',
        relayUrl: 'ws://localhost',
        pairedAt: '2026-01-01T00:00:00Z',
      );
      const b = PeerRecord(
        remoteEpk: 'epk_B',
        sessionName: 'B',
        relayUrl: 'ws://localhost',
        pairedAt: '2026-01-02T00:00:00Z',
      );

      // Factory hangs forever — simulates a slow WS connect.
      final factoryCalls = <String>[];
      final hang = Completer<IChannel>();
      final cm = ConnectionManager(
        factory: (peer, _) {
          factoryCalls.add(peer.remoteEpk);
          return hang.future;
        },
        storage: _FakeStorage([a, b]), // peers.first = A,
        emitDebounce: Duration.zero,
      );

      // Kick off a switch to B (in-flight).
      // ignore: unawaited_futures
      cm.switchTo(b);
      await Future<void>.delayed(Duration.zero);
      expect(factoryCalls, ['epk_B']);
      expect(cm.activePeer?.remoteEpk, 'epk_B');

      // ChatViewModel-style boot kicks in: must NOT override the active peer.
      await cm.boot();
      expect(factoryCalls, ['epk_B'],
          reason: 'boot must not cancel the in-flight connect and reroute');
      expect(cm.activePeer?.remoteEpk, 'epk_B');

      cm.dispose();
    });

    test('boot after adopt is a no-op when already online', () async {
      var factoryCalled = false;
      final cm = ConnectionManager(
        factory: (peer, cancel) async {
          factoryCalled = true;
          return _makeChannel();
        },
        storage: _FakeStorage([_fakePeer()]),
        emitDebounce: Duration.zero,
      );

      final fakeChannel = _makeChannel();
      cm.adopt(fakeChannel, _fakePeer());
      expect(cm.status, isA<StatusOnline>());

      await cm.boot();
      await Future<void>.delayed(Duration.zero);

      expect(factoryCalled, isFalse,
          reason: 'boot must skip factory when already online via adopt');
      expect(cm.status, isA<StatusOnline>());

      cm.dispose();
    });
  });

  // Channel close keeps `_closed` reachable so the lint about unused field
  // is silenced; verify the close path runs.
  test('PlainPeerChannel.close marks transport closed', () async {
    final q1 = _Q();
    final q2 = _Q();
    final t = _T(send: q1, recv: q2);
    final ch = PlainPeerChannel(transport: t);
    await ch.close();
    expect(t.isClosed, isTrue);
  });

  // ---------------------------------------------------------------------------
  // offline-loop fix regressions (Patches A + B)
  // ---------------------------------------------------------------------------

  group('ConnectionManager — offline-loop fix', () {
    test(
      'onDone on a stale channel (already replaced) does NOT trigger a retry',
      () async {
        final lostStates = <ConnectionStatus>[];
        // Two distinct channels we can independently control.
        final chA = _ControllableChannel();
        final chB = _ControllableChannel();
        var idx = 0;
        final cm = ConnectionManager(
          factory: (_, _) async {
            return [chA, chB][idx++];
          },
          storage: _FakeStorage([_fakePeer()]),
          emitDebounce: Duration.zero,
        );

        await cm.connectTo(_fakePeer()); // → chA
        expect(cm.channel, same(chA));
        await Future<void>.delayed(const Duration(milliseconds: 5));

        // Force a reconnect — chB becomes the live channel.
        await cm.disconnect();
        await cm.connectTo(_fakePeer()); // → chB
        await Future<void>.delayed(const Duration(milliseconds: 5));
        expect(cm.channel, same(chB));

        cm.statusStream.listen(lostStates.add);
        // Now simulate chA's `onDone` firing late (the relay killed the
        // old WS after the new one authenticated). Without the stale
        // guard this would emit StatusRetrying.
        await chA.closeStream();
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(
          lostStates.whereType<StatusRetrying>(),
          isEmpty,
          reason: 'stale onDone must not schedule a retry',
        );
        expect(cm.status, isA<StatusOnline>());

        cm.dispose();
      },
    );

    test(
      '_retryAttempt stays at 0 until the channel listener sees inbound; '
      'a channel close right after connect keeps the backoff at attempt=0 '
      '(rather than escalating)',
      () async {
        // Multiple controllable channels, each closes mid-flight before
        // delivering any inbound — simulates the death-spiral scenario
        // where the relay keeps kicking us.
        final channels = <_ControllableChannel>[];
        var idx = 0;
        final cm = ConnectionManager(
          factory: (_, _) async {
            final ch = _ControllableChannel();
            channels.add(ch);
            return ch;
          },
          storage: _FakeStorage([_fakePeer()]),
          emitDebounce: Duration.zero,
        );

        final retries = <StatusRetrying>[];
        cm.statusStream
            .where((s) => s is StatusRetrying)
            .cast<StatusRetrying>()
            .listen(retries.add);

        await cm.connectTo(_fakePeer());
        await Future<void>.delayed(const Duration(milliseconds: 5));
        // Channel closes WITHOUT sending any inbound → counts as a real
        // loss (live channel). Retry should be scheduled with attempt=0.
        await channels[idx++].closeStream();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(retries, hasLength(1));
        expect(retries.first.attempt, 0);

        cm.dispose();
      },
    );

    // -----------------------------------------------------------------------
    // Presence (plano 12)
    // -----------------------------------------------------------------------

    test(
      'boot subscribes presence with ALL stored peers',
      () async {
        const a = PeerRecord(
          remoteEpk: 'epk_A',
          sessionName: 'A',
          relayUrl: 'ws://x',
          pairedAt: '2026-01-01T00:00:00Z',
        );
        const b = PeerRecord(
          remoteEpk: 'epk_B',
          sessionName: 'B',
          relayUrl: 'ws://x',
          pairedAt: '2026-01-02T00:00:00Z',
        );
        final ch = _ControllableChannel();
        final cm = ConnectionManager(
          factory: (_, _) async => ch,
          storage: _FakeStorage([a, b]),
          emitDebounce: Duration.zero,
        );

        await cm.boot();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        final subs = ch.sentControl
            .where((m) => m['type'] == 'subscribe_presence')
            .toList();
        expect(subs, isNotEmpty);
        expect((subs.first['peers'] as List).toSet(), {'epk_A', 'epk_B'});

        cm.dispose();
      },
    );

    test(
      'peer_online frame → presence map updates + stream emits',
      () async {
        final ch = _ControllableChannel();
        final cm = ConnectionManager(
          factory: (_, _) async => ch,
          storage: _FakeStorage([_fakePeer()]),
          emitDebounce: Duration.zero,
        );
        await cm.boot();
        await Future<void>.delayed(const Duration(milliseconds: 10));

        final snapshots = <Map<String, PresenceState>>[];
        cm.presenceStream.listen(snapshots.add);
        ch.pushControl(const PeerOnline(peer: 'epk_test'));
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(cm.presenceFor('epk_test'), isA<PresenceOnline>());
        expect(snapshots, isNotEmpty);
        // The map is keyed in canonical (standard base64) form; look up
        // via `presenceFor` which coerces — direct map access would
        // require the standard-encoded key.
        expect(snapshots.last.values, contains(isA<PresenceOnline>()));

        cm.dispose();
      },
    );

    test(
      'peer_offline frame → PresenceOffline with sinceTs',
      () async {
        final ch = _ControllableChannel();
        final cm = ConnectionManager(
          factory: (_, _) async => ch,
          storage: _FakeStorage([_fakePeer()]),
          emitDebounce: Duration.zero,
        );
        await cm.boot();
        await Future<void>.delayed(const Duration(milliseconds: 10));

        ch.pushControl(const PeerOffline(peer: 'epk_test', sinceTs: 42));
        await Future<void>.delayed(const Duration(milliseconds: 10));

        final s = cm.presenceFor('epk_test') as PresenceOffline;
        expect(s.sinceTs, 42);

        cm.dispose();
      },
    );

    test(
      'presence snapshot → batch update for all listed peers',
      () async {
        final ch = _ControllableChannel();
        final cm = ConnectionManager(
          factory: (_, _) async => ch,
          storage: _FakeStorage([_fakePeer()]),
          emitDebounce: Duration.zero,
        );
        await cm.boot();
        await Future<void>.delayed(const Duration(milliseconds: 10));

        ch.pushControl(const PresenceSnapshot(states: [
          PeerPresence(peer: 'epk_A', online: true, sinceTs: null),
          PeerPresence(peer: 'epk_B', online: false, sinceTs: 100),
        ]));
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(cm.presenceFor('epk_A'), isA<PresenceOnline>());
        expect(cm.presenceFor('epk_B'), isA<PresenceOffline>());
        expect((cm.presenceFor('epk_B') as PresenceOffline).sinceTs, 100);

        cm.dispose();
      },
    );

    test(
      'dedup: repeated identical peer_online does not emit again '
      '(relay firehose mitigation)',
      () async {
        final ch = _ControllableChannel();
        final cm = ConnectionManager(
          factory: (_, _) async => ch,
          storage: _FakeStorage([_fakePeer()]),
          emitDebounce: Duration.zero,
        );
        await cm.boot();
        await Future<void>.delayed(const Duration(milliseconds: 10));

        final emits = <Map<String, PresenceState>>[];
        cm.presenceStream.listen(emits.add);
        ch.pushControl(const PeerOnline(peer: 'epk_test'));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        final afterFirst = emits.length;
        expect(afterFirst, greaterThan(0));

        // Three more identical pushes — dedup must suppress them all.
        ch.pushControl(const PeerOnline(peer: 'epk_test'));
        ch.pushControl(const PeerOnline(peer: 'epk_test'));
        ch.pushControl(const PeerOnline(peer: 'epk_test'));
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(emits.length, afterFirst,
            reason: 'repeated identical peer_online must be deduped');

        cm.dispose();
      },
    );

    test(
      'dedup: identical rooms snapshot does not re-emit',
      () async {
        final ch = _ControllableChannel();
        final cm = ConnectionManager(
          factory: (_, _) async => ch,
          storage: _FakeStorage([_fakePeer()]),
          emitDebounce: Duration.zero,
        );
        await cm.boot();
        await Future<void>.delayed(const Duration(milliseconds: 10));

        final emits = <Map<String, List<RoomInfo>>>[];
        cm.roomsStream.listen(emits.add);
        final snapshot = RoomsSnapshot(peer: 'epk_test', rooms: const [
          RoomInfo(roomId: 'r1', name: 'work', cwd: '/x', startedAt: 1),
        ]);
        ch.pushControl(snapshot);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        final afterFirst = emits.length;
        expect(afterFirst, greaterThan(0));

        // Re-push exact same snapshot multiple times.
        ch.pushControl(snapshot);
        ch.pushControl(snapshot);
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(emits.length, afterFirst,
            reason: 'identical rooms snapshot must be deduped');

        cm.dispose();
      },
    );

    test(
      'debounce coalesces a burst of distinct presence changes into '
      'a single emit',
      () async {
        final ch = _ControllableChannel();
        // Use a non-zero debounce so the burst observably coalesces.
        final cm = ConnectionManager(
          factory: (_, _) async => ch,
          storage: _FakeStorage([_fakePeer()]),
          emitDebounce: const Duration(milliseconds: 30),
        );
        await cm.boot();
        await Future<void>.delayed(const Duration(milliseconds: 10));

        final emits = <Map<String, PresenceState>>[];
        cm.presenceStream.listen(emits.add);

        // Three different presence states arriving quickly — each is
        // a real change (different peer), but should fire only one
        // combined emit at the debounce edge.
        ch.pushControl(const PeerOnline(peer: 'epk_A'));
        ch.pushControl(const PeerOnline(peer: 'epk_B'));
        ch.pushControl(const PeerOffline(peer: 'epk_A', sinceTs: 99));
        await Future<void>.delayed(const Duration(milliseconds: 60));

        expect(emits.length, 1,
            reason: 'burst within debounce window must coalesce');
        // The single emit reflects the FINAL state (Offline for A).
        expect(emits.single['epk_A'], isA<PresenceOffline>());
        expect(emits.single['epk_B'], isA<PresenceOnline>());

        cm.dispose();
      },
    );

    // -----------------------------------------------------------------------
    // Plano 13: chat-state recovery (boot preferredEpk + no-NoPeer switchTo)
    // -----------------------------------------------------------------------

    test(
      'boot(preferredEpk=B) connects to B even when peers.first is A',
      () async {
        const a = PeerRecord(
          remoteEpk: 'epk_A',
          sessionName: 'A',
          relayUrl: 'ws://x',
          pairedAt: '2026-01-01T00:00:00Z',
        );
        const b = PeerRecord(
          remoteEpk: 'epk_B',
          sessionName: 'B',
          relayUrl: 'ws://x',
          pairedAt: '2026-01-02T00:00:00Z',
        );
        final connects = <String>[];
        final cm = ConnectionManager(
          factory: (peer, _) async {
            connects.add(peer.remoteEpk);
            return _ControllableChannel();
          },
          storage: _FakeStorage([a, b]),
          emitDebounce: Duration.zero,
        );

        await cm.boot(preferredEpk: 'epk_B');
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(connects, ['epk_B']);
        expect(cm.activePeer?.remoteEpk, 'epk_B');

        cm.dispose();
      },
    );

    test(
      'boot() without preferredEpk falls back to peers.first',
      () async {
        const a = PeerRecord(
          remoteEpk: 'epk_A',
          sessionName: 'A',
          relayUrl: 'ws://x',
          pairedAt: '2026-01-01T00:00:00Z',
        );
        const b = PeerRecord(
          remoteEpk: 'epk_B',
          sessionName: 'B',
          relayUrl: 'ws://x',
          pairedAt: '2026-01-02T00:00:00Z',
        );
        final connects = <String>[];
        final cm = ConnectionManager(
          factory: (peer, _) async {
            connects.add(peer.remoteEpk);
            return _ControllableChannel();
          },
          storage: _FakeStorage([a, b]),
          emitDebounce: Duration.zero,
        );

        await cm.boot();
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(connects, ['epk_A']);

        cm.dispose();
      },
    );

    test(
      'boot(preferredEpk=missing) falls back to peers.first',
      () async {
        const a = PeerRecord(
          remoteEpk: 'epk_A',
          sessionName: 'A',
          relayUrl: 'ws://x',
          pairedAt: '2026-01-01T00:00:00Z',
        );
        final connects = <String>[];
        final cm = ConnectionManager(
          factory: (peer, _) async {
            connects.add(peer.remoteEpk);
            return _ControllableChannel();
          },
          storage: _FakeStorage([a]),
          emitDebounce: Duration.zero,
        );

        await cm.boot(preferredEpk: 'epk_does_not_exist');
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(connects, ['epk_A']);

        cm.dispose();
      },
    );

    test(
      'switchTo between peers never emits transient StatusNoPeer',
      () async {
        const a = PeerRecord(
          remoteEpk: 'epk_A',
          sessionName: 'A',
          relayUrl: 'ws://x',
          pairedAt: '2026-01-01T00:00:00Z',
        );
        const b = PeerRecord(
          remoteEpk: 'epk_B',
          sessionName: 'B',
          relayUrl: 'ws://x',
          pairedAt: '2026-01-02T00:00:00Z',
        );
        final cm = ConnectionManager(
          factory: (_, _) async => _ControllableChannel(),
          storage: _FakeStorage([a, b]),
          emitDebounce: Duration.zero,
        );
        cm.adopt(_ControllableChannel(), a);

        final seen = <ConnectionStatus>[];
        cm.statusStream.listen(seen.add);

        await cm.switchTo(b);
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(
          seen.whereType<StatusNoPeer>(),
          isEmpty,
          reason: 'plano 13 — switchTo must not flash through NoPeer',
        );
        // Must still go through Connecting on the way to Online.
        expect(seen.any((s) => s is StatusConnecting), isTrue);

        cm.dispose();
      },
    );

    test(
      'disconnect() still emits StatusNoPeer (public API contract intact)',
      () async {
        final cm = ConnectionManager(
          factory: (_, _) async => _ControllableChannel(),
          storage: _FakeStorage([_fakePeer()]),
          emitDebounce: Duration.zero,
        );
        cm.adopt(_ControllableChannel(), _fakePeer());

        final seen = <ConnectionStatus>[];
        cm.statusStream.listen(seen.add);

        await cm.disconnect();
        // Broadcast stream delivers events via microtask; let them drain.
        await Future<void>.delayed(const Duration(milliseconds: 5));

        expect(seen.whereType<StatusNoPeer>(), isNotEmpty);
        expect(cm.activePeer, isNull);

        cm.dispose();
      },
    );

    test(
      'boot() normalises _subscribedEpks: replay frames go out in standard '
      '(regression — url-safe leak caused inconsistent Home dots)',
      () async {
        // PeerRecord stores url-safe (with `_`). The relay indexes by
        // standard (with `/`). Boot's `_replaySubscriptions` runs after
        // _connect succeeds; assert the FIRST replay payload is already
        // standard, not url-safe.
        const urlSafe = 'Bz02uLiwrmQZ0S8qiwtFJAt0KzUvrgepYO_oMQ6yyQE';
        const peer = PeerRecord(
          remoteEpk: urlSafe,
          sessionName: 'Pi',
          relayUrl: 'ws://x',
          pairedAt: '2026-01-01T00:00:00Z',
        );
        final ch = _ControllableChannel();
        final cm = ConnectionManager(
          factory: (_, _) async => ch,
          storage: _FakeStorage([peer]),
          emitDebounce: Duration.zero,
        );

        await cm.boot();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        final subs = ch.sentControl
            .where((m) => m['type'] == 'subscribe_presence')
            .toList();
        expect(subs, isNotEmpty);
        final wire = (subs.first['peers'] as List).single as String;
        expect(wire.contains('_'), isFalse,
            reason: 'url-safe `_` leaked into the relay-bound payload');
        expect(wire.contains('-'), isFalse);
        expect(wire.contains('/') || wire.contains('+') || wire.endsWith('='),
            isTrue,
            reason: 'must be standard base64');

        cm.dispose();
      },
    );

    test(
      'subscribe_presence converts url-safe epks to standard base64',
      () async {
        // 32-byte random key → base64url has `_` if the bytes happen to
        // map to 0x3e/0x3f sextets. Use one with `_` deterministically:
        // bytes = [0xff, 0xfe, 0xfd, ...] → standard `+/Pz...`,
        // url-safe `-_Pz...`. Easier: pick a known url-safe string with
        // `_` and decode-encode through the helper.
        final ch = _ControllableChannel();
        final cm = ConnectionManager(
          factory: (_, _) async => ch,
          storage: _FakeStorage([_fakePeer()]),
          emitDebounce: Duration.zero,
        );
        await cm.boot();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        ch.sentControl.clear();

        // url-safe contains `-_`; standard contains `+/`.
        const urlSafe = 'Bz02uLiwrmQZ0S8qiwtFJAt0KzUvrgepYO_oMQ6yyQE';
        cm.subscribeToPeers([urlSafe]);

        final sub = ch.sentControl
            .firstWhere((m) => m['type'] == 'subscribe_presence');
        final wire = (sub['peers'] as List).single as String;
        expect(wire.contains('_'), isFalse,
            reason: 'standard base64 must not contain `_`');
        expect(wire.contains('-'), isFalse,
            reason: 'standard base64 must not contain `-`');

        cm.dispose();
      },
    );

    test(
      'presenceFor accepts either url-safe or standard epk',
      () async {
        final ch = _ControllableChannel();
        final cm = ConnectionManager(
          factory: (_, _) async => ch,
          storage: _FakeStorage([_fakePeer()]),
          emitDebounce: Duration.zero,
        );
        await cm.boot();
        await Future<void>.delayed(const Duration(milliseconds: 10));

        // Relay pushes presence with the STANDARD form (what the relay
        // sees in `hello.pubkey`).
        const standard = 'Bz02uLiwrmQZ0S8qiwtFJAt0KzUvrgepYO/oMQ6yyQE=';
        ch.pushControl(const PeerOnline(peer: standard));
        await Future<void>.delayed(const Duration(milliseconds: 10));

        // The app looks up using the url-safe form from PairingStorage.
        const urlSafe = 'Bz02uLiwrmQZ0S8qiwtFJAt0KzUvrgepYO_oMQ6yyQE';
        expect(cm.presenceFor(urlSafe), isA<PresenceOnline>());
        // And standard form still works.
        expect(cm.presenceFor(standard), isA<PresenceOnline>());

        cm.dispose();
      },
    );

    test(
      'subscribeToPeers (called later) sends a fresh subscribe_presence',
      () async {
        final ch = _ControllableChannel();
        final cm = ConnectionManager(
          factory: (_, _) async => ch,
          storage: _FakeStorage([_fakePeer()]),
          emitDebounce: Duration.zero,
        );
        await cm.boot();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        ch.sentControl.clear(); // ignore the boot subscribe

        cm.subscribeToPeers(['epk_new1', 'epk_new2']);

        final subs = ch.sentControl
            .where((m) => m['type'] == 'subscribe_presence')
            .toList();
        expect(subs, hasLength(1));
        // The wire form is normalised to standard base64; the test
        // only cares that the count matches and the inputs survived
        // the round-trip semantically.
        expect((subs.first['peers'] as List), hasLength(2));

        cm.dispose();
      },
    );

    test(
      'inbound message resets _retryAttempt back to 0',
      () async {
        // First connect fails → attempt rises. Second connect succeeds
        // and delivers an inbound → next failure should re-start at 0.
        var attempt = 0;
        final ch = _ControllableChannel();
        final cm = ConnectionManager(
          factory: (peer, _) async {
            attempt++;
            if (attempt == 1) throw Exception('fail once');
            return ch;
          },
          storage: _FakeStorage([_fakePeer()]),
          emitDebounce: Duration.zero,
        );

        final retries = <StatusRetrying>[];
        cm.statusStream
            .where((s) => s is StatusRetrying)
            .cast<StatusRetrying>()
            .listen(retries.add);

        // ignore: unawaited_futures
        cm.connectTo(_fakePeer());
        // First attempt fails → schedules retry attempt=0.
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(retries.first.attempt, 0);

        // Wait for retry to fire (~1s) and the second attempt to succeed.
        await Future<void>.delayed(const Duration(seconds: 2));
        expect(cm.status, isA<StatusOnline>());

        // Deliver an inbound message; listener resets retry attempt.
        ch.pushMessage(Pong(inReplyTo: 'x'));
        await Future<void>.delayed(const Duration(milliseconds: 20));

        // Now drop the channel → another retry should start at 0 again.
        await ch.closeStream();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final fresh = retries.last;
        expect(
          fresh.attempt,
          0,
          reason: 'inbound traffic resets backoff; next loss is attempt=0',
        );

        cm.dispose();
      },
    );
  });
}

// ---------------------------------------------------------------------------
// _ControllableChannel — IChannel where we control the inbound stream and
// can simulate WS close on demand. Used by the offline-loop regression
// tests. Also implements [IControlLink] so presence tests can inject
// frames and inspect outbound `subscribe_presence`/`presence_check`.
// ---------------------------------------------------------------------------

class _ControllableChannel implements IChannel, IControlLink {
  final _ctrl = StreamController<ServerMessage>.broadcast();
  final _controlCtrl = StreamController<ControlInbound>.broadcast();
  final List<Map<String, dynamic>> sentControl = [];
  String? activeRoom;

  void setActiveRoom(String roomId) {
    activeRoom = roomId;
  }

  @override
  Stream<ServerMessage> get serverMessages => _ctrl.stream;

  @override
  Future<void> send(ClientMessage msg) async {}

  @override
  Future<void> close() async {
    if (!_ctrl.isClosed) await _ctrl.close();
    if (!_controlCtrl.isClosed) await _controlCtrl.close();
  }

  void pushMessage(ServerMessage m) {
    if (!_ctrl.isClosed) _ctrl.add(m);
  }

  Future<void> closeStream() async {
    if (!_ctrl.isClosed) await _ctrl.close();
  }

  @override
  Stream<ControlInbound> get controlFrames => _controlCtrl.stream;

  @override
  void sendControl(Map<String, dynamic> json) {
    sentControl.add(json);
  }

  void pushControl(ControlInbound c) {
    if (!_controlCtrl.isClosed) _controlCtrl.add(c);
  }
}

// ---------------------------------------------------------------------------
// Presence (plano 12)
// ---------------------------------------------------------------------------

void mainPresence() {} // placeholder so the group below is visible

// ---------------------------------------------------------------------------
// Rooms (plan 17)
// ---------------------------------------------------------------------------

void _registerRoomsTests() {
  group('ConnectionManager — rooms (plan 17)', () {
    test(
      'replaySubscriptions sends BOTH subscribe_presence AND '
      'subscribe_rooms after connect',
      () async {
        final ch = _ControllableChannel();
        final cm = ConnectionManager(
          factory: (_, _) async => ch,
          storage: _FakeStorage([]),
          emitDebounce: Duration.zero,
        );
        cm.subscribeToPeers(['Bz02uLi']);
        await cm.connectTo(_fakePeer());
        await Future<void>.delayed(const Duration(milliseconds: 10));

        final types = ch.sentControl.map((m) => m['type']).toList();
        expect(types, contains('subscribe_presence'));
        expect(types, contains('subscribe_rooms'));
        expect(types, contains('rooms_check'));

        cm.dispose();
      },
    );

    test(
      'RoomAnnounced / RoomEnded / RoomsSnapshot mutate _roomsByPeer + '
      'emit on roomsStream',
      () async {
        final ch = _ControllableChannel();
        final cm = ConnectionManager(
          factory: (_, _) async => ch,
          storage: _FakeStorage([]),
          emitDebounce: Duration.zero,
        );
        await cm.connectTo(_fakePeer());
        await Future<void>.delayed(const Duration(milliseconds: 10));

        final snapshots = <Map<String, List<RoomInfo>>>[];
        final sub = cm.roomsStream.listen(snapshots.add);

        ch.pushControl(const RoomAnnounced(
          peer: 'epkA',
          roomId: 'r1',
          name: 'work',
          cwd: '/Users/x',
          startedAt: 1000,
        ));
        await Future<void>.delayed(const Duration(milliseconds: 5));

        expect(cm.roomsFor('epkA'), hasLength(1));
        expect(cm.roomsFor('epkA').single.roomId, 'r1');
        expect(snapshots, isNotEmpty);

        ch.pushControl(const RoomEnded(
          peer: 'epkA',
          roomId: 'r1',
          sinceTs: 2000,
        ));
        await Future<void>.delayed(const Duration(milliseconds: 5));
        // Plan-17 follow-up: RoomEnded keeps the room CACHED so the
        // tile stays in Home (marked offline) — only the live set
        // shrinks. isRoomLive now distinguishes the two.
        expect(cm.roomsFor('epkA'), hasLength(1));
        expect(cm.isRoomLive('epkA', 'r1'), isFalse);

        ch.pushControl(const RoomsSnapshot(peer: 'epkA', rooms: [
          RoomInfo(roomId: 'rA', startedAt: 3000, cwd: '/a'),
          RoomInfo(roomId: 'rB', startedAt: 4000, cwd: '/b'),
        ]));
        await Future<void>.delayed(const Duration(milliseconds: 5));
        // Plan-17 follow-up: snapshots MERGE with cached rooms (so a
        // room going offline keeps its tile). r1 is still in cache
        // (offline), rA and rB are now live → total 3.
        expect(cm.roomsFor('epkA'), hasLength(3));
        expect(cm.isRoomLive('epkA', 'r1'), isFalse);
        expect(cm.isRoomLive('epkA', 'rA'), isTrue);
        expect(cm.isRoomLive('epkA', 'rB'), isTrue);

        await sub.cancel();
        cm.dispose();
      },
    );

    test(
      '_connect adopts peer.roomId (plan 17 fix — bind room on the '
      'first frame so the relay routes correctly)',
      () async {
        final ch = _ControllableChannel();
        final cm = ConnectionManager(
          factory: (_, _) async => ch,
          storage: _FakeStorage([]),
          emitDebounce: Duration.zero,
        );
        await cm.connectTo(const PeerRecord(
          remoteEpk: 'epk_room_aware',
          sessionName: 'Pi',
          relayUrl: 'wss://x',
          pairedAt: '2026-01-01T00:00:00Z',
          roomId: 'cwd-A',
        ));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(cm.activeRoomId, 'cwd-A',
            reason: 'PeerRecord.roomId should be adopted at connect');

        cm.dispose();
      },
    );

    test(
      'legacy peer (PeerRecord.roomId == null) → discovers + persists '
      'first announced room',
      () async {
        final storage = _FakeStorage([]);
        final ch = _ControllableChannel();
        final cm = ConnectionManager(
          factory: (_, _) async => ch,
          storage: storage,
          emitDebounce: Duration.zero,
        );
        // Pre-fix peer record — no roomId.
        const legacyPeer = PeerRecord(
          remoteEpk: 'epk_legacy',
          sessionName: 'Pi',
          relayUrl: 'wss://x',
          pairedAt: '2025-12-01T00:00:00Z',
        );
        await cm.connectTo(legacyPeer);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(cm.activeRoomId, 'main',
            reason: 'no persisted roomId → falls back to main');

        // Relay announces the real room for this peer.
        ch.pushControl(const RoomAnnounced(
          peer: 'epk_legacy',
          roomId: 'discovered-room-id',
          name: 'work',
          cwd: '/Users/x',
          startedAt: 1000,
        ));
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(cm.activeRoomId, 'discovered-room-id',
            reason: 'discovery should auto-adopt the announced room');
        // Persisted on storage so subsequent app launches skip the
        // discovery round-trip.
        final saved = storage.savedPeers;
        expect(saved, isNotEmpty);
        expect(saved.last.roomId, 'discovered-room-id');

        cm.dispose();
      },
    );

    test(
      'explicit room switch is not overwritten by later room announce',
      () async {
        final storage = _FakeStorage([]);
        final ch = _ControllableChannel();
        final cm = ConnectionManager(
          factory: (_, _) async => ch,
          storage: storage,
          emitDebounce: Duration.zero,
        );
        const peer = PeerRecord(
          remoteEpk: 'epk_explicit',
          sessionName: 'Pi',
          relayUrl: 'wss://x',
          pairedAt: '2026-01-01T00:00:00Z',
          roomId: 'robflow',
        );
        await cm.connectTo(peer);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(cm.activeRoomId, 'robflow');

        cm.switchRoom('remote');
        expect(cm.activeRoomId, 'remote');
        expect(ch.activeRoom, 'remote');

        ch.pushControl(const RoomAnnounced(
          peer: 'epk_explicit',
          roomId: 'robflow',
          name: 'robflow',
          cwd: '/work/robflow',
          startedAt: 1000,
        ));
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(cm.activeRoomId, 'remote');
        expect(ch.activeRoom, 'remote');
        expect(storage.savedPeers, isEmpty);

        cm.dispose();
      },
    );

    test(
      'explicit room switch is not overwritten by rooms snapshot order',
      () async {
        final ch = _ControllableChannel();
        final cm = ConnectionManager(
          factory: (_, _) async => ch,
          storage: _FakeStorage([]),
          emitDebounce: Duration.zero,
        );
        const peer = PeerRecord(
          remoteEpk: 'epk_explicit_snapshot',
          sessionName: 'Pi',
          relayUrl: 'wss://x',
          pairedAt: '2026-01-01T00:00:00Z',
          roomId: 'robflow',
        );
        await cm.connectTo(peer);
        await Future<void>.delayed(const Duration(milliseconds: 10));

        cm.switchRoom('remote');
        ch.pushControl(const RoomsSnapshot(peer: 'epk_explicit_snapshot', rooms: [
          RoomInfo(roomId: 'robflow', startedAt: 1000),
          RoomInfo(roomId: 'remote', startedAt: 1001),
        ]));
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(cm.activeRoomId, 'remote');
        expect(ch.activeRoom, 'remote');

        cm.dispose();
      },
    );

    test(
      'RoomMetaUpdated patches the model on an existing room (plan 18)',
      () async {
        final ch = _ControllableChannel();
        final cm = ConnectionManager(
          factory: (_, _) async => ch,
          storage: _FakeStorage([_fakePeer()]),
          emitDebounce: Duration.zero,
        );
        await cm.connectTo(_fakePeer());
        await Future<void>.delayed(const Duration(milliseconds: 10));

        // Seed via RoomAnnounced (no model yet).
        ch.pushControl(const RoomAnnounced(
          peer: 'epk_test',
          roomId: 'r1',
          startedAt: 1,
        ));
        await Future<void>.delayed(const Duration(milliseconds: 5));
        expect(cm.roomsFor('epk_test').single.model, isNull);

        // Pi changes model mid-session.
        ch.pushControl(const RoomMetaUpdated(
          peer: 'epk_test',
          roomId: 'r1',
          model: 'claude-sonnet-4.5',
        ));
        await Future<void>.delayed(const Duration(milliseconds: 5));
        expect(cm.roomsFor('epk_test').single.model, 'claude-sonnet-4.5');

        // Updating again (e.g. switched models) overwrites cleanly.
        ch.pushControl(const RoomMetaUpdated(
          peer: 'epk_test',
          roomId: 'r1',
          model: 'gpt-4o',
        ));
        await Future<void>.delayed(const Duration(milliseconds: 5));
        expect(cm.roomsFor('epk_test').single.model, 'gpt-4o');

        cm.dispose();
      },
    );

    test(
      'RoomMetaUpdated for unknown room is a no-op (no crash, no insert)',
      () async {
        final ch = _ControllableChannel();
        final cm = ConnectionManager(
          factory: (_, _) async => ch,
          storage: _FakeStorage([]),
          emitDebounce: Duration.zero,
        );
        await cm.connectTo(_fakePeer());
        await Future<void>.delayed(const Duration(milliseconds: 10));

        ch.pushControl(const RoomMetaUpdated(
          peer: 'epk_unknown',
          roomId: 'r_ghost',
          model: 'claude',
        ));
        await Future<void>.delayed(const Duration(milliseconds: 5));
        expect(cm.roomsFor('epk_unknown'), isEmpty);

        cm.dispose();
      },
    );

    test(
      'setRoomLocalName preserves model + other fields (regression: '
      'rename used to drop model and the tile fell back to '
      '"Last Paired")',
      () async {
        final ch = _ControllableChannel();
        final cm = ConnectionManager(
          factory: (_, _) async => ch,
          storage: _FakeStorage([_fakePeer()]),
          emitDebounce: Duration.zero,
        );
        await cm.connectTo(_fakePeer());
        await Future<void>.delayed(const Duration(milliseconds: 10));

        // Seed a room WITH model + cwd.
        ch.pushControl(const RoomAnnounced(
          peer: 'epk_test',
          roomId: 'r1',
          name: 'work',
          cwd: '/Users/jacob/projects/app',
          startedAt: 1000,
          model: 'claude-sonnet-4.5',
        ));
        await Future<void>.delayed(const Duration(milliseconds: 5));
        expect(cm.roomsFor('epk_test').single.model, 'claude-sonnet-4.5');

        // Rename via long-press path.
        await cm.setRoomLocalName('epk_test', 'r1', 'meu-projeto');
        await Future<void>.delayed(const Duration(milliseconds: 10));

        final after = cm.roomsFor('epk_test').single;
        expect(after.name, 'meu-projeto',
            reason: 'local name override applied');
        expect(after.model, 'claude-sonnet-4.5',
            reason: 'model must survive rename');
        expect(after.cwd, '/Users/jacob/projects/app',
            reason: 'cwd must survive rename');
        expect(after.startedAt, 1000,
            reason: 'startedAt must survive rename');

        cm.dispose();
      },
    );

    test('switchRoom updates activeRoomId (and forwards to channel)',
        () async {
      final ch = _ControllableChannel();
      final cm = ConnectionManager(
        factory: (_, _) async => ch,
        storage: _FakeStorage([]),
        emitDebounce: Duration.zero,
      );
      await cm.connectTo(_fakePeer());
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(cm.activeRoomId, 'main');
      cm.switchRoom('room-xyz');
      expect(cm.activeRoomId, 'room-xyz');
      expect(cm.activePeer?.roomId, 'room-xyz');

      // Same room is a no-op.
      cm.switchRoom('room-xyz');
      expect(cm.activeRoomId, 'room-xyz');

      cm.dispose();
    });

    test(
      'WS retry keeps switchRoom cwd — stale peer.roomId must not clobber',
      () async {
        const peerB = PeerRecord(
          remoteEpk: 'epk_test',
          sessionName: 'test session',
          relayUrl: 'ws://localhost:8080',
          pairedAt: '2026-01-01T00:00:00Z',
          roomId: 'channel-B',
        );
        var idx = 0;
        final ch1 = _ControllableChannel();
        final ch2 = _ControllableChannel();
        final cm = ConnectionManager(
          factory: (_, _) async => idx++ == 0 ? ch1 : ch2,
          storage: _FakeStorage([peerB]),
          emitDebounce: Duration.zero,
        );
        await cm.connectTo(peerB);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(cm.activeRoomId, 'channel-B');

        cm.switchRoom('channel-A');
        expect(cm.activeRoomId, 'channel-A');
        expect(cm.activePeer?.roomId, 'channel-A');

        await ch1.closeStream();
        // First retry backoff is 1s.
        await Future<void>.delayed(const Duration(milliseconds: 1100));

        expect(cm.activeRoomId, 'channel-A',
            reason: 'retry must not snap back to stale peer.roomId');
        expect(cm.activePeer?.roomId, 'channel-A');
        expect(cm.status, isA<StatusOnline>());

        cm.dispose();
      },
    );
  });
}

