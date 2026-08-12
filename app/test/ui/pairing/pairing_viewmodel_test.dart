// Tests for PairingViewModel: scan → pair_request → paired.
// Uses in-memory transport so no real WS is needed.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/connection_manager.dart';

import 'package:app/pairing/owner_identity_bridge.dart';
import 'package:app/pairing/pair_request_flow.dart' show PeerTransport;
import 'package:app/pairing/storage.dart';
import 'package:app/ui/pairing/states/pairing_state.dart';
import 'package:app/ui/pairing/viewmodels/pairing_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:remote_pi_identity/remote_pi_identity.dart';
import '../../helpers/fake_key_value_store.dart';

// ---------------------------------------------------------------------------
// Test infrastructure
// ---------------------------------------------------------------------------

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

class _MemTransport implements PeerTransport {
  final _Q _s;
  final _Q _r;
  _MemTransport({required _Q send, required _Q recv}) : _s = send, _r = recv;
  @override
  Future<void> send(Uint8List d) async => _s.add(d);
  @override
  Future<Uint8List> receive() => _r.next();
  @override
  Future<void> close() async {}
}

/// Synchronous Preferences subclass for tests. Pre-set relay URL to
/// `ws://localhost` so it matches `_qrUri` (which still embeds the
/// legacy `r=ws://localhost`); avoids tripping the relay-mismatch
/// guard in `pair_request_flow.performPairing`. Pass `null` to force
/// a different URL and exercise the mismatch path.
class _PrefsForTest extends Preferences {
  final String? _relay;
  _PrefsForTest({String? relay = 'ws://localhost'})
    : _relay = relay,
      super(FakeKeyValueStore());
  @override
  String? get relayUrl => _relay;
}

class _FakeStorage extends PairingStorage {
  final List<PeerRecord> _saved = [];

  @override
  Future<List<PeerRecord>> listPeers() async => _saved;

  @override
  Future<void> savePeer(PeerRecord r) async => _saved.add(r);
}

/// Helper: build a fully-booted [OwnerIdentityBridge] backed by an
/// in-memory plugin store, seeded with a freshly-generated identity.
/// Mirrors what `dependencies.dart` + the router's _BootState do before
/// PairingViewModel runs in production.
Future<OwnerIdentityBridge> _bootedBridge(PairingStorage storage) async {
  final store = InMemoryOwnerIdentityStore();
  final bridge = OwnerIdentityBridge(store, storage);
  await bridge.boot();
  return bridge;
}

const _qrUri =
    'remotepi://pair?t=AAAAAAAAAAAAAAAAAAAAAA&'
    'epk=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA&'
    'r=ws%3A%2F%2Flocalhost&n=test+session';

/// A pairing transport factory that runs a fake "Pi" responder which replies
/// with the given inner message to whatever `pair_request` it receives.
PairingTransportFactory _factoryReplyingWith(Map<String, dynamic> reply) {
  return (qr, deviceEd25519) async {
    final q1 = _Q();
    final q2 = _Q();
    final iTrans = _MemTransport(send: q1, recv: q2);
    final rTrans = _MemTransport(send: q2, recv: q1);

    // Responder runs in background — copies in_reply_to from the request.
    unawaited(() async {
      final raw = await rTrans.receive();
      final req = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
      final resp = Map<String, dynamic>.from(reply);
      resp['in_reply_to'] = req['id'];
      await rTrans.send(Uint8List.fromList(utf8.encode(jsonEncode(resp))));
    }());

    return iTrans;
  };
}

// ---------------------------------------------------------------------------
// Spy ConnectionManager — records adopt/disconnect (plan/31: PairingViewModel
// now drives the ConnectionManager directly). Overrides skip super so no
// ping/connect timers are started.
// ---------------------------------------------------------------------------

class _SpyConn extends ConnectionManager {
  _SpyConn()
    : super(
        factory: (_, _) async => throw UnimplementedError(),
        storage: _FakeStorage(),
      );

  IChannel? adoptedChannel;
  PeerRecord? adoptedPeer;
  int disconnectCalls = 0;

  @override
  void adopt(IChannel channel, PeerRecord peer) {
    adoptedChannel = channel;
    adoptedPeer = peer;
  }

  @override
  Future<void> disconnect() async => disconnectCalls++;
}

// ---------------------------------------------------------------------------
// Unit tests — PairingViewModel
// ---------------------------------------------------------------------------

void main() {
  group('PairingViewModel', () {
    test('initial state is PairingScanning', () async {
      final storage = _FakeStorage();
      final bridge = await _bootedBridge(storage);
      final vm = PairingViewModel(
        storage,
        (qr, key) async => throw Exception('should not be called'),
        _SpyConn(),
        _PrefsForTest(),
        bridge,
      );
      expect(vm.state, isA<PairingScanning>());
      vm.dispose();
    });

    test('invalid QR is ignored — stays PairingScanning', () async {
      final storage = _FakeStorage();
      final bridge = await _bootedBridge(storage);
      final vm = PairingViewModel(
        storage,
        (qr, key) async => throw Exception('should not be called'),
        _SpyConn(),
        _PrefsForTest(),
        bridge,
      );
      await vm.onQrScanned('https://example.com/not-a-qr');
      expect(vm.state, isA<PairingScanning>());
      vm.dispose();
    });

    test('scan → connecting → paired (channel adopted)', () async {
      final storage = _FakeStorage();
      final fakeRepo = _SpyConn();
      final bridge = await _bootedBridge(storage);
      final factory = _factoryReplyingWith({
        'type': 'pair_ok',
        'session_name': 'test session',
      });
      final vm = PairingViewModel(
        storage,
        factory,
        fakeRepo,
        _PrefsForTest(),
        bridge,
      );

      final fut = vm.onQrScanned(_qrUri);
      expect(vm.state, isA<PairingConnecting>());

      await fut;
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(vm.state, isA<PairingPaired>());
      expect(storage._saved, hasLength(1));
      expect(storage._saved.first.sessionName, 'test session');
      expect(fakeRepo.adoptedChannel, isNotNull);
      expect(fakeRepo.adoptedPeer?.remoteEpk, isNotEmpty);
      expect(fakeRepo.disconnectCalls, 1);

      vm.dispose();
    });

    test('pair_error → PairingError(canRetry: true)', () async {
      final storage = _FakeStorage();
      final bridge = await _bootedBridge(storage);
      final factory = _factoryReplyingWith({
        'type': 'pair_error',
        'code': 'token_expired',
        'message': 'Token expired',
      });
      final vm = PairingViewModel(
        storage,
        factory,
        _SpyConn(),
        _PrefsForTest(),
        bridge,
      );

      await vm.onQrScanned(_qrUri);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(vm.state, isA<PairingError>());
      final err = vm.state as PairingError;
      expect(err.canRetry, isTrue);
      expect(err.message, contains('QR expired'));
      expect(storage._saved, isEmpty);

      vm.dispose();
    });

    test(
      'transport failure → PairingError + retry returns to scanning',
      () async {
        final storage = _FakeStorage();
        final bridge = await _bootedBridge(storage);
        final vm = PairingViewModel(
          storage,
          (qr, key) async => throw Exception('socket exception'),
          _SpyConn(),
          _PrefsForTest(),
          bridge,
        );

        await vm.onQrScanned(_qrUri);
        expect(vm.state, isA<PairingError>());
        expect((vm.state as PairingError).canRetry, isTrue);

        vm.retry();
        expect(vm.state, isA<PairingScanning>());

        vm.dispose();
      },
    );
  });

  // -------------------------------------------------------------------------
  // Widget harness test — page reacts to ViewModel state changes
  // -------------------------------------------------------------------------

  group('PairingPage widget', () {
    testWidgets('navigates via PairingPaired after pair_ok', (tester) async {
      final storage = _FakeStorage();
      final bridge = await _bootedBridge(storage);
      final factory = _factoryReplyingWith({
        'type': 'pair_ok',
        'session_name': 'test session',
      });
      final conn = _SpyConn();
      final vm = PairingViewModel(
        storage,
        factory,
        conn,
        _PrefsForTest(),
        bridge,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider.value(
            value: vm,
            child: _PairingPageTestHarness(vm: vm),
          ),
        ),
      );

      await tester.runAsync(() async {
        await vm.onQrScanned(_qrUri);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      expect(vm.state, isA<PairingPaired>());
      expect(find.text('Done'), findsOneWidget);

      vm.dispose();
      conn.dispose(); // cancel the watchdog before the timer-pending check
    });

    testWidgets('shows error view on pair_error', (tester) async {
      final factory = _factoryReplyingWith({
        'type': 'pair_error',
        'code': 'token_consumed',
        'message': 'Already used',
      });
      final storage = _FakeStorage();
      final bridge = await _bootedBridge(storage);
      final conn = _SpyConn();
      final vm = PairingViewModel(
        storage,
        factory,
        conn,
        _PrefsForTest(),
        bridge,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider.value(
            value: vm,
            child: _PairingPageTestHarness(vm: vm),
          ),
        ),
      );

      await tester.runAsync(() async {
        await vm.onQrScanned(_qrUri);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      expect(vm.state, isA<PairingError>());
      expect(find.text('Try again'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(vm.state, isA<PairingScanning>());

      vm.dispose();
      conn.dispose(); // cancel the watchdog before the timer-pending check
    });
  });
}

// ---------------------------------------------------------------------------
// Minimal widget harness that renders PairingState without MobileScanner
// ---------------------------------------------------------------------------

class _PairingPageTestHarness extends StatelessWidget {
  final PairingViewModel vm;
  const _PairingPageTestHarness({required this.vm});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PairingViewModel>().state;

    return Scaffold(
      body: switch (state) {
        PairingIdle() => const Text('Idle'),
        PairingScanning() => const Text('Scanning'),
        PairingConnecting() => const Text('Connecting…'),
        PairingPaired() => const Text('Done'),
        PairingError(:final message) => Column(
          children: [
            Text(message),
            ElevatedButton(onPressed: vm.retry, child: const Text('Try again')),
          ],
        ),
      },
    );
  }
}
