// ChatViewModel reacts to ISessionRepository stream changes.
//
// Post plan 10.x, ChatViewModel owns the connection lifecycle:
//   - on mount it reads selectedPeerEpk + loads the peer + openSession
//   - on dispose it disconnects
//
// Tests use a fake repo whose `openSession` is a no-op; state transitions
// are driven by pushing into `sessionStream` directly.

import 'dart:async';

import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/repositories/i_session_repository.dart';
import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/domain/session_state.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/ui/chat/states/chat_state.dart';
import 'package:app/ui/chat/viewmodels/chat_viewmodel.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeRepo implements ISessionRepository {
  final _ctrl = StreamController<SessionState>.broadcast(sync: true);
  final _events = StreamController<SessionEvent>.broadcast(sync: true);
  SessionState _state = const SessionState();
  int openSessionCalls = 0;
  int disconnectCalls = 0;

  @override SessionState get current => _state;
  @override Stream<SessionState> get sessionStream => _ctrl.stream;
  @override Stream<SessionEvent> get eventStream => _events.stream;
  @override Future<void> boot() async {}
  @override Future<void> connectTo(PeerRecord p) async {}

  void pushEvent(SessionEvent e) => _events.add(e);

  @override
  Future<void> sendMessage(String text) async {
    final id = 'u${_ctrl.hashCode}';
    _push(_state.copyWith(
      messages: [..._state.messages, UserMsg(id: id, text: text)],
      streaming: StreamingMessage(inReplyTo: id),
    ));
  }

  @override Future<void> cancel(String targetId) async {}

  int clearActiveSessionCalls = 0;
  @override
  Future<void> clearActiveSession() async {
    clearActiveSessionCalls++;
    _push(const SessionState());
  }

  @override
  Future<void> approveTool(String toolCallId, ApproveDecision decision) async {
    final updated = _state.messages.map((m) {
      if (m is ToolEvent && m.toolCallId == toolCallId) {
        return m.copyWith(
          status: decision == ApproveDecision.allow
              ? ToolEventStatus.allowed
              : ToolEventStatus.denied,
        );
      }
      return m;
    }).toList();
    _push(_state.copyWith(messages: updated));
  }

  @override
  void dispose() {
    _ctrl.close();
    _events.close();
  }
  @override void adoptChannel(IChannel channel, PeerRecord peer) {}
  @override Future<void> disconnect() async { disconnectCalls++; }
  PeerRecord? fakeActivePeer;
  @override
  PeerRecord? get activePeer => fakeActivePeer;

  int setActivePeerCalls = 0;
  String? lastSetRoomId;
  List<ChatMessage>? cachedMessagesForBootstrap;
  @override
  Future<void> setActivePeer(PeerRecord peer, {String? roomId}) async {
    setActivePeerCalls++;
    lastSetRoomId = roomId;
    final cache = cachedMessagesForBootstrap;
    if (cache != null) {
      _push(_state.copyWith(messages: cache, clearStreaming: true));
    }
  }
  int requestSyncCalls = 0;
  @override void requestSync() { requestSyncCalls++; }
  int switchRoomCalls = 0;
  String? lastSwitchedRoom;
  @override void switchRoom(String roomId) {
    switchRoomCalls++;
    lastSwitchedRoom = roomId;
  }

  final _roomsCtrl =
      StreamController<Map<String, List<RoomInfo>>>.broadcast(sync: true);
  final Map<String, List<RoomInfo>> _rooms = {};
  final Map<String, Set<String>> _liveRooms = {};
  @override
  Stream<Map<String, List<RoomInfo>>> get roomsStream => _roomsCtrl.stream;
  @override
  List<RoomInfo> roomsFor(String epk) =>
      List.unmodifiable(_rooms[epk] ?? const []);
  @override
  bool isRoomLive(String epk, String roomId) =>
      _liveRooms[epk]?.contains(roomId) ?? false;
  void setRooms(String epk, List<RoomInfo> rooms, {Set<String>? live}) {
    _rooms[epk] = rooms;
    _liveRooms[epk] = live ?? rooms.map((r) => r.roomId).toSet();
    _roomsCtrl.add(Map.unmodifiable(_rooms));
  }

  // Plan-18 follow-up — fake "working" signal. Tests don't exercise
  // this surface yet; expose static null/empty.
  @override
  String? get workingEpk => null;
  @override
  String? get workingRoomId => null;
  @override
  Stream<({String? epk, String? roomId})> get workingStream =>
      const Stream.empty();
  @override
  Future<void> openSession(PeerRecord peer) async { openSessionCalls++; }

  final _presenceCtrl =
      StreamController<Map<String, PresenceState>>.broadcast(sync: true);
  final Map<String, PresenceState> _presence = {};
  @override
  Stream<Map<String, PresenceState>> get presenceStream => _presenceCtrl.stream;
  @override
  PresenceState presenceFor(String epk) =>
      _presence[epk] ?? const PresenceUnknown();
  void setPresence(String epk, PresenceState s) {
    _presence[epk] = s;
    _presenceCtrl.add(Map.unmodifiable(_presence));
  }

  void push(SessionState s) => _push(s);

  void _push(SessionState s) {
    _state = s;
    _ctrl.add(s);
  }
}

class _FakeChannel implements IChannel {
  final _ctrl = StreamController<ServerMessage>.broadcast(sync: true);

  @override Stream<ServerMessage> get serverMessages => _ctrl.stream;
  @override Future<void> send(ClientMessage msg) async {}
  @override Future<void> close() async => _ctrl.close();

  void push(ServerMessage msg) => _ctrl.add(msg);
}

class _FakeStorage extends PairingStorage {
  final Map<String, PeerRecord> _peers;
  _FakeStorage([Map<String, PeerRecord>? peers]) : _peers = peers ?? {};

  @override
  Future<PeerRecord?> loadPeer(String epk) async => _peers[epk];
}

class _FakeSecureStorage implements FlutterSecureStorage {
  final Map<String, String> _store = {};
  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _store[key];
  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _store.remove(key);
    } else {
      _store[key] = value;
    }
  }
  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _store.remove(key);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const _peerA = PeerRecord(
  remoteEpk: 'epk_A',
  sessionName: 'Pi A',
  relayUrl: 'ws://localhost',
  pairedAt: '2026-01-01T00:00:00Z',
);

Future<({_FakeRepo repo, Preferences prefs, _FakeStorage storage, ChatViewModel vm})>
    _build({
  String? selectedEpk,
  _FakeStorage? storage,
  SessionState? seedRepoState,
}) async {
  final repo = _FakeRepo();
  if (seedRepoState != null) {
    // Seed BEFORE construction so `_repo.current` already reflects the
    // pre-existing connection (mirrors the boot-time WS scenario).
    repo._state = seedRepoState;
  }
  final prefs = Preferences(_FakeSecureStorage());
  if (selectedEpk != null) await prefs.setSelectedPeerEpk(selectedEpk);
  final st = storage ?? _FakeStorage();
  final vm = ChatViewModel(repo, prefs, st);
  await Future<void>.delayed(Duration.zero); // let _bootstrap finish
  return (repo: repo, prefs: prefs, storage: st, vm: vm);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ChatViewModel', () {
    test('no selectedPeerEpk → bootstraps to ChatNoPeer', () async {
      final s = await _build();
      expect(s.vm.state, isA<ChatNoPeer>());
      expect(s.repo.openSessionCalls, 0);
      s.vm.dispose();
      s.repo.dispose();
    });

    test('selectedPeerEpk + peer in storage → openSession called',
        () async {
      final s = await _build(
        selectedEpk: 'epk_A',
        storage: _FakeStorage({'epk_A': _peerA}),
      );
      expect(s.repo.openSessionCalls, 1);
      s.vm.dispose();
      s.repo.dispose();
    });

    test('selectedPeerEpk pointing to a missing peer → ChatNoPeer',
        () async {
      final s = await _build(selectedEpk: 'epk_unknown');
      expect(s.vm.state, isA<ChatNoPeer>());
      expect(s.repo.openSessionCalls, 0);
      s.vm.dispose();
      s.repo.dispose();
    });

    test('dispose does NOT disconnect (connection shared since plano 12)',
        () async {
      final s = await _build(
        selectedEpk: 'epk_A',
        storage: _FakeStorage({'epk_A': _peerA}),
      );
      s.vm.dispose();
      expect(s.repo.disconnectCalls, 0,
          reason: 'WS lives from app boot; chat is a passive observer');
      s.repo.dispose();
    });

    test('StatusOnline → ChatReady with empty messages', () async {
      final s = await _build();
      final ch = _FakeChannel();
      s.repo.push(SessionState(connection: StatusOnline(ch)));
      final state = s.vm.state;
      expect(state, isA<ChatReady>());
      expect((state as ChatReady).messages, isEmpty);
      expect(state.isOffline, isFalse);
      s.vm.dispose();
      s.repo.dispose();
    });

    test('StatusRetrying → ChatReady with isOffline=true', () async {
      final s = await _build();
      s.repo.push(
        const SessionState(
          connection: StatusRetrying(
            nextRetry: Duration(seconds: 2),
            attempt: 1,
          ),
        ),
      );
      expect((s.vm.state as ChatReady).isOffline, isTrue);
      s.vm.dispose();
      s.repo.dispose();
    });

    test('fingerprint mismatch → ChatFatalError', () async {
      final s = await _build();
      s.repo.push(
        const SessionState(
          connection: StatusOffline(
            reason: 'Remote key changed',
            canRetry: false,
          ),
        ),
      );
      expect(s.vm.state, isA<ChatFatalError>());
      expect((s.vm.state as ChatFatalError).message, 'Remote key changed');
      s.vm.dispose();
      s.repo.dispose();
    });

    test('messages accumulate in ChatReady', () async {
      final s = await _build();
      final ch = _FakeChannel();
      const msg1 = UserMsg(id: 'u1', text: 'hi');
      const msg2 = AssistantMsg(id: 'u1', text: 'hello back');
      s.repo.push(
        SessionState(
          connection: StatusOnline(ch),
          messages: [msg1, msg2],
        ),
      );
      expect((s.vm.state as ChatReady).messages, [msg1, msg2]);
      s.vm.dispose();
      s.repo.dispose();
    });

    test('streaming field propagates to ChatReady', () async {
      final s = await _build();
      final ch = _FakeChannel();
      const streaming = StreamingMessage(inReplyTo: 'u1', buffer: 'hello...');
      s.repo.push(
        SessionState(connection: StatusOnline(ch), streaming: streaming),
      );
      expect((s.vm.state as ChatReady).streaming, streaming);
      s.vm.dispose();
      s.repo.dispose();
    });

    test('sendMessage adds UserMsg', () async {
      final s = await _build();
      await s.vm.sendMessage('test message');
      expect(s.repo.current.messages, isNotEmpty);
      expect(s.repo.current.messages.first, isA<UserMsg>());
      expect((s.repo.current.messages.first as UserMsg).text, 'test message');
      s.vm.dispose();
      s.repo.dispose();
    });

    test('clearActiveSession delegates to repo and empties the thread',
        () async {
      final s = await _build();
      final ch = _FakeChannel();
      s.repo.push(SessionState(
        connection: StatusOnline(ch),
        messages: const [UserMsg(id: 'u1', text: 'old turn')],
      ));
      expect(s.repo.current.messages, isNotEmpty);

      await s.vm.clearActiveSession();

      expect(s.repo.clearActiveSessionCalls, 1);
      expect(s.repo.current.messages, isEmpty);
      s.vm.dispose();
      s.repo.dispose();
    });

    test('approveTool updates ToolEvent status', () async {
      final s = await _build();
      final ch = _FakeChannel();
      const tool = ToolEvent(
        id: 'tc1',
        toolCallId: 'tc1',
        tool: 'Bash',
        args: {'command': 'ls'},
      );
      s.repo.push(
        SessionState(connection: StatusOnline(ch), messages: [tool]),
      );

      await s.vm.approveTool('tc1', ApproveDecision.allow);

      final updated = s.repo.current.messages.first as ToolEvent;
      expect(updated.status, ToolEventStatus.allowed);
      s.vm.dispose();
      s.repo.dispose();
    });

    test(
      'Pi offline + cached history → ChatReady (history visible, '
      'NOT stuck in ChatConnecting)',
      () async {
        // Repo starts in StatusNoPeer (no WS yet). setActivePeer
        // populates the cache. Bootstrap order matters: cache must
        // be loaded BEFORE openSession, so history is in state even
        // if openSession can never complete (Pi offline / WS down).
        final repo = _FakeRepo();
        repo.cachedMessagesForBootstrap = const [
          UserMsg(id: 'u1', text: 'old question'),
          AssistantMsg(id: 'u1', text: 'old reply'),
        ];
        final prefs = Preferences(_FakeSecureStorage());
        await prefs.setSelectedPeerEpk('epk_A');
        final st = _FakeStorage({'epk_A': _peerA});
        final vm = ChatViewModel(repo, prefs, st);
        await Future<void>.delayed(Duration.zero);

        expect(repo.setActivePeerCalls, 1,
            reason: 'cache must be loaded before openSession');
        final state = vm.state;
        expect(state, isA<ChatReady>(),
            reason: 'history present → render surface, even offline');
        final ready = state as ChatReady;
        expect(ready.messages, hasLength(2));
        expect(ready.isOffline, isTrue,
            reason: 'WS not online → input disabled, banner-able');

        vm.dispose();
        repo.dispose();
      },
    );

    test(
      'plano 13 fast-path: when activePeer already matches → openSession '
      'is NOT called',
      () async {
        final repo = _FakeRepo();
        repo.fakeActivePeer = _peerA; // boot already settled on this peer
        final ch = _FakeChannel();
        repo._state = SessionState(connection: StatusOnline(ch));
        final prefs = Preferences(_FakeSecureStorage());
        await prefs.setSelectedPeerEpk('epk_A');
        final st = _FakeStorage({'epk_A': _peerA});

        final vm = ChatViewModel(repo, prefs, st);
        await Future<void>.delayed(Duration.zero);

        expect(repo.openSessionCalls, 0,
            reason: 'fast-path must skip openSession when already driving');
        expect(repo.setActivePeerCalls, 1,
            reason: 'cache load still happens');
        expect(vm.state, isA<ChatReady>());

        vm.dispose();
        repo.dispose();
      },
    );

    test(
      'plano 13 slow-path: when activePeer mismatches → openSession called',
      () async {
        const other = PeerRecord(
          remoteEpk: 'epk_OTHER',
          sessionName: 'Other',
          relayUrl: 'ws://x',
          pairedAt: '2026-01-01T00:00:00Z',
        );
        final repo = _FakeRepo();
        repo.fakeActivePeer = other; // boot landed on a different peer
        final prefs = Preferences(_FakeSecureStorage());
        await prefs.setSelectedPeerEpk('epk_A');
        final st = _FakeStorage({'epk_A': _peerA});

        final vm = ChatViewModel(repo, prefs, st);
        await Future<void>.delayed(Duration.zero);

        expect(repo.openSessionCalls, 1,
            reason: 'must call openSession to switch the connection');

        vm.dispose();
        repo.dispose();
      },
    );

    test(
      'mounts when conn was already Online before VM existed → ChatReady '
      '(no stuck in ChatConnecting)',
      () async {
        // Simulate: boot opened the WS before /chat was navigated to; the
        // repo already has connection=Online by the time ChatViewModel
        // constructs.
        final ch = _FakeChannel();
        final s = await _build(
          selectedEpk: 'epk_A',
          storage: _FakeStorage({'epk_A': _peerA}),
          seedRepoState: SessionState(connection: StatusOnline(ch)),
        );
        expect(s.vm.state, isA<ChatReady>(),
            reason: 'must seed from _repo.current — no future event needed');
        s.vm.dispose();
        s.repo.dispose();
      },
    );

    test(
      'openSession idempotent (no events fire) → state still becomes Ready',
      () async {
        // Same as above but explicit: openSession() in the fake does
        // not emit anything. The seed path is what keeps us out of
        // ChatConnecting.
        final ch = _FakeChannel();
        final s = await _build(
          selectedEpk: 'epk_A',
          storage: _FakeStorage({'epk_A': _peerA}),
          seedRepoState: SessionState(connection: StatusOnline(ch)),
        );
        expect(s.repo.openSessionCalls, 1);
        expect(s.vm.state, isA<ChatReady>());
        s.vm.dispose();
        s.repo.dispose();
      },
    );

    test(
      'bootstrap also fires requestSync (covers idempotent-openSession path)',
      () async {
        final ch = _FakeChannel();
        final s = await _build(
          selectedEpk: 'epk_A',
          storage: _FakeStorage({'epk_A': _peerA}),
          seedRepoState: SessionState(connection: StatusOnline(ch)),
        );
        // Plan/24-fix-session-sync (follow-up): the bootstrap calls
        // requestSync once; the ChatViewModel's Online-edge detector
        // (in _onSession) also fires one when the first seed emit
        // arrives with StatusOnline. Either path on its own is enough
        // to recover the history — coexisting is harmless (Pi is
        // idempotent on session_sync) and gives us belt-and-suspenders
        // against bootstrap races.
        expect(s.repo.requestSyncCalls, greaterThanOrEqualTo(1),
            reason:
                'session_sync would never fire on its own when '
                'switchTo no-ops — bootstrap must force it');
        s.vm.dispose();
        s.repo.dispose();
      },
    );

    test(
      'room offline → ChatReady.peerPresence is PresenceOffline '
      '(plan-17 follow-up: presence now derives from room-live state)',
      () async {
        final s = await _build(
          selectedEpk: 'epk_A',
          storage: _FakeStorage({'epk_A': _peerA}),
        );
        final ch = _FakeChannel();
        s.repo.push(SessionState(connection: StatusOnline(ch)));
        // Initial: no rooms in the snapshot → roomLive=false →
        // peerPresence renders as PresenceOffline.
        await Future<void>.delayed(const Duration(milliseconds: 10));
        // Trigger a rooms emit (empty) so _onRooms picks it up.
        s.repo.setRooms('epk_A', const [], live: {});
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect((s.vm.state as ChatReady).peerPresence, isA<PresenceOffline>());

        s.vm.dispose();
        s.repo.dispose();
      },
    );

    test(
      'room comes online → ChatReady.peerPresence flips to PresenceOnline',
      () async {
        final s = await _build(
          selectedEpk: 'epk_A',
          storage: _FakeStorage({'epk_A': _peerA}),
        );
        final ch = _FakeChannel();
        s.repo.push(SessionState(connection: StatusOnline(ch)));

        // Start offline: no rooms.
        s.repo.setRooms('epk_A', const [], live: {});
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect((s.vm.state as ChatReady).peerPresence, isA<PresenceOffline>());

        // Pi announces the active room → live=true.
        s.repo.setRooms(
          'epk_A',
          const [RoomInfo(roomId: 'main', startedAt: 1)],
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect((s.vm.state as ChatReady).peerPresence, isA<PresenceOnline>());

        s.vm.dispose();
        s.repo.dispose();
      },
    );

    test('PairingRevoked event sets ChatReady.pairingRevoked=true',
        () async {
      final s = await _build();
      final ch = _FakeChannel();
      s.repo.push(SessionState(connection: StatusOnline(ch)));
      expect((s.vm.state as ChatReady).pairingRevoked, isFalse);

      s.repo.pushEvent(const PairingRevoked());
      expect((s.vm.state as ChatReady).pairingRevoked, isTrue);
      s.vm.dispose();
      s.repo.dispose();
    });

    test(
      'PeerWentOffline followed by presence flip back to PresenceOnline '
      'auto-clears the sticky banner AND triggers requestSync — '
      'regression for "tenho que sair do chat e voltar pra ver online"',
      () async {
        final s = await _build(
          selectedEpk: 'epk_A',
          storage: _FakeStorage({'epk_A': _peerA}),
        );
        final ch = _FakeChannel();
        s.repo.push(SessionState(connection: StatusOnline(ch)));
        // Start with the active room live.
        s.repo.setRooms(
          'epk_A',
          const [RoomInfo(roomId: 'main', startedAt: 1)],
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));

        // Pi sends Bye → ChatViewModel.onEvent stores offlineReason.
        // Then the relay flips the room to offline.
        s.repo.pushEvent(const PeerWentOffline('peer_stop'));
        s.repo.setRooms(
          'epk_A',
          const [RoomInfo(roomId: 'main', startedAt: 1)],
          live: {},
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect((s.vm.state as ChatReady).peerOfflineReason, 'peer_stop',
            reason: 'banner reason is set when Bye lands');

        // Room comes back live (relay → room_announced).
        final syncCallsBefore = s.repo.requestSyncCalls;
        s.repo.setRooms(
          'epk_A',
          const [RoomInfo(roomId: 'main', startedAt: 1)],
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));

        // Banner cleared automatically.
        expect((s.vm.state as ChatReady).peerOfflineReason, isNull,
            reason: 'offlineReason must auto-clear when Pi returns');
        // And requestSync was fired so we pull any new history.
        expect(
          s.repo.requestSyncCalls - syncCallsBefore,
          greaterThanOrEqualTo(1),
          reason: 'must trigger requestSync on Pi-back transition',
        );

        s.vm.dispose();
        s.repo.dispose();
      },
    );
  });
}
