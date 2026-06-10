// Plan/31 — ChatViewModel is a thin composer over the SSOT. A message written
// to the DB (via the channel → SyncService) must surface in ChatState.

import 'dart:async';
import 'dart:io';

import 'package:app/data/local/boxes.dart';
import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/repositories/session_read_repository.dart';
import 'package:app/data/sync/sync_service.dart';
import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/domain/session_state.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/ui/chat/states/chat_state.dart';
import 'package:app/ui/chat/viewmodels/chat_viewmodel.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

class _FakeChannel implements IChannel, IControlLink {
  final _ctrl = StreamController<ServerMessage>.broadcast();
  final _control = StreamController<ControlInbound>.broadcast();
  @override
  Stream<ServerMessage> get serverMessages => _ctrl.stream;
  @override
  Stream<ControlInbound> get controlFrames => _control.stream;
  @override
  void sendControl(Map<String, dynamic> json) {}
  @override
  Future<void> send(ClientMessage msg) async {}
  @override
  Future<void> close() async {
    await _ctrl.close();
    await _control.close();
  }

  void push(ServerMessage m) => _ctrl.add(m);
  void pushControl(ControlInbound m) => _control.add(m);
}

class _FakeSecureStorage implements FlutterSecureStorage {
  final Map<String, String> _s = {};
  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _s[key];
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
      _s.remove(key);
    } else {
      _s[key] = value;
    }
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const _peer = PeerRecord(
  remoteEpk: 'epk_chat',
  sessionName: 'Pi',
  relayUrl: 'ws://localhost',
  pairedAt: '2026-01-01T00:00:00Z',
);

class _FakeStorage extends PairingStorage {
  @override
  Future<List<PeerRecord>> listPeers() async => const [_peer];
  @override
  Future<PeerRecord?> loadPeer(String epk) async =>
      epk == _peer.remoteEpk ? _peer : null;
  @override
  Future<void> savePeer(PeerRecord r) async {}

  // In-memory rooms so a RoomAnnounced landing on the real ConnectionManager
  // (_persistRoomsForPeer) never touches flutter_secure_storage.
  final Map<String, List<PersistedRoom>> _rooms = {};
  @override
  Future<void> saveRooms(String epk, List<PersistedRoom> rooms) async =>
      _rooms[epk] = rooms;
  @override
  Future<List<PersistedRoom>> loadRooms(String epk) async =>
      _rooms[epk] ?? const [];
  @override
  Future<void> deleteRooms(String epk) async => _rooms.remove(epk);
}

late Directory _dir;

void main() {
  setUpAll(() async {
    _dir = Directory.systemTemp.createTempSync('rp_v2_chatvm_');
    await LocalBoxes.initForTest(_dir.path);
  });
  tearDownAll(() async {
    await Hive.close();
    await _dir.delete(recursive: true);
  });

  test('a message written to the DB surfaces in ChatState', () async {
    final ch = _FakeChannel();
    final storage = _FakeStorage();
    final conn = ConnectionManager(
      factory: (_, _) async => ch,
      storage: storage,
    );
    final boxes = LocalBoxes();
    final sync = SyncService(conn, boxes);
    final read = SessionReadRepository(boxes);
    final prefs = Preferences(_FakeSecureStorage());
    await prefs.setSelectedPeerEpk(_peer.remoteEpk);
    await prefs.setSelectedRoom(epk: _peer.remoteEpk, roomId: 'main');

    conn.adopt(ch, _peer);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    final vm = ChatViewModel(read, sync, conn, prefs, storage);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // The Pi rebroadcasts a user message → SyncService writes a row →
    // SessionReadRepository emits → ChatViewModel recomposes.
    ch.push(UserInput(id: 'u1', text: 'hello from db'));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final state = vm.state;
    expect(state, isA<ChatReady>());
    final messages = (state as ChatReady).messages;
    expect(
      messages.whereType<UserMsg>().map((m) => m.text),
      contains('hello from db'),
    );

    // BUG fix (smoke): the chat "working" pill must be on for the whole turn,
    // not just the token-streaming window — and the composer locks + the send
    // button becomes "stop" (cancelTargetId points at the in-flight turn).
    expect(vm.isWorking, isTrue, reason: 'turn started → working');
    expect(vm.cancelTargetId, 'u1', reason: 'stop button cancels this turn');
    ch.push(AgentDone(inReplyTo: 'u1'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(vm.isWorking, isFalse, reason: 'agent_done → idle');
    expect(vm.cancelTargetId, isNull, reason: 'no turn to cancel when idle');

    vm.dispose();
    sync.dispose();
    conn.dispose();
  });

  test(
    'cancelled clears the stop state without deleting the user row',
    () async {
      final ch = _FakeChannel();
      final storage = _FakeStorage();
      final conn = ConnectionManager(
        factory: (_, _) async => ch,
        storage: storage,
      );
      final boxes = LocalBoxes();
      final msgBox = await boxes.msgsBox(_peer.remoteEpk, 'main');
      await msgBox.clear();
      final sync = SyncService(conn, boxes);
      final read = SessionReadRepository(boxes);
      final prefs = Preferences(_FakeSecureStorage());
      await prefs.setSelectedPeerEpk(_peer.remoteEpk);
      await prefs.setSelectedRoom(epk: _peer.remoteEpk, roomId: 'main');

      conn.adopt(ch, _peer);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final vm = ChatViewModel(read, sync, conn, prefs, storage);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      ch.push(UserInput(id: 'cancel-u1', text: 'please stop'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      ch.push(AgentChunk(inReplyTo: 'cancel-u1', delta: 'partial'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(vm.isWorking, isTrue);
      expect(vm.cancelTargetId, 'cancel-u1');
      expect((vm.state as ChatReady).streaming, isNotNull);

      ch.push(Cancelled(inReplyTo: 'cancel-1', targetId: 'cancel-u1'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final state = vm.state as ChatReady;
      expect(vm.isWorking, isFalse);
      expect(vm.cancelTargetId, isNull);
      expect(state.streaming, isNull);
      expect(
        state.messages.whereType<UserMsg>().map((m) => m.text),
        contains('please stop'),
      );
      expect(
        state.messages.whereType<UserMsg>().single.status,
        UserMsgStatus.confirmed,
      );

      vm.dispose();
      sync.dispose();
      conn.dispose();
    },
  );

  test(
    'an empty session reaches ChatReady with no messages → the chat shows the '
    'default "Nothing here" placeholder (plan/32)',
    () async {
      final ch = _FakeChannel();
      final storage = _FakeStorage();
      final conn = ConnectionManager(
        factory: (_, _) async => ch,
        storage: storage,
      );
      final boxes = LocalBoxes();
      // The msgs box is shared across tests in this file (setUpAll) — start
      // this one from a clean slate so "empty session" really is empty.
      (await boxes.msgsBox(_peer.remoteEpk, 'main')).clear();
      final sync = SyncService(conn, boxes);
      final read = SessionReadRepository(boxes);
      final prefs = Preferences(_FakeSecureStorage());
      await prefs.setSelectedPeerEpk(_peer.remoteEpk);
      await prefs.setSelectedRoom(epk: _peer.remoteEpk, roomId: 'main');

      conn.adopt(ch, _peer);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final vm = ChatViewModel(read, sync, conn, prefs, storage);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final state = vm.state;
      expect(state, isA<ChatReady>());
      state as ChatReady;
      // Empty + nothing streaming → _buildBody renders the default Pi-icon +
      // "Nothing here" placeholder (shown whenever the body is empty).
      expect(state.messages, isEmpty);
      expect(state.streaming, isNull);

      vm.dispose();
      sync.dispose();
      conn.dispose();
    },
  );

  test(
    'working pill follows the relay per-room broadcast (same mechanism as '
    'Home) and the flip rebuilds the state (plan/32)',
    () async {
      final ch = _FakeChannel();
      final storage = _FakeStorage();
      final conn = ConnectionManager(
        factory: (_, _) async => ch,
        storage: storage,
        emitDebounce: Duration.zero,
      );
      final boxes = LocalBoxes();
      final sync = SyncService(conn, boxes);
      final read = SessionReadRepository(boxes);
      final prefs = Preferences(_FakeSecureStorage());
      await prefs.setSelectedPeerEpk(_peer.remoteEpk);
      await prefs.setSelectedRoom(epk: _peer.remoteEpk, roomId: 'main');

      conn.adopt(ch, _peer);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final vm = ChatViewModel(read, sync, conn, prefs, storage);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Room comes online idle (no local turn started in THIS chat).
      ch.pushControl(const RoomAnnounced(
        peer: 'epk_chat',
        roomId: 'main',
        startedAt: 1,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(vm.isWorking, isFalse);

      // The relay broadcasts meta.working=true for this room (turn_start) —
      // no local send/echo, purely the per-room signal that also drives Home.
      ch.pushControl(const RoomMetaUpdated(
        peer: 'epk_chat',
        roomId: 'main',
        working: true,
        hasModel: false,
        hasThinking: false,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(vm.isWorking, isTrue, reason: 'relay per-room working drives the pill');
      expect((vm.state as ChatReady).isWorking, isTrue,
          reason: 'state carries isWorking so the flip rebuilds the UI');

      // If the app sees agent_done but the relay's meta.working=false
      // broadcast is delayed/missed, the active chat must not stay stuck on
      // the stop button. The local channel observation clears the room flag.
      ch.push(AgentDone(inReplyTo: 'u1'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(vm.isWorking, isFalse);
      expect((vm.state as ChatReady).isWorking, isFalse);

      // A later turn_end broadcast remains idempotent.
      ch.pushControl(const RoomMetaUpdated(
        peer: 'epk_chat',
        roomId: 'main',
        working: false,
        hasModel: false,
        hasThinking: false,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(vm.isWorking, isFalse);
      expect((vm.state as ChatReady).isWorking, isFalse);

      vm.dispose();
      sync.dispose();
      conn.dispose();
    },
  );
}
