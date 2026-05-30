// Plan/31 — SyncService is the single DB writer. Drives it through a fake
// channel adopted into a real ConnectionManager and asserts box contents.

import 'dart:async';
import 'dart:io';

import 'package:app/data/local/boxes.dart';
import 'package:app/data/local/records/message_record.dart';
import 'package:app/data/local/records/session_index_record.dart';
import 'package:app/data/sync/sync_service.dart';
import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

class _FakeChannel implements IChannel {
  final _ctrl = StreamController<ServerMessage>.broadcast();
  final List<ClientMessage> sent = [];
  @override
  Stream<ServerMessage> get serverMessages => _ctrl.stream;
  @override
  Future<void> send(ClientMessage msg) async => sent.add(msg);
  @override
  Future<void> close() => _ctrl.close();
  void push(ServerMessage m) => _ctrl.add(m);
}

class _FakeStorage extends PairingStorage {
  @override
  Future<List<PeerRecord>> listPeers() async => const [];
}

int _counter = 0;

late Directory _dir;

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 30));

void main() {
  setUpAll(() async {
    _dir = Directory.systemTemp.createTempSync('rp_v2_sync_');
    await LocalBoxes.initForTest(_dir.path);
  });
  tearDownAll(() async {
    await Hive.close();
    await _dir.delete(recursive: true);
  });

  Future<
    ({ConnectionManager conn, _FakeChannel ch, SyncService sync, String epk})
  >
  setup() async {
    final ch = _FakeChannel();
    final conn = ConnectionManager(
      factory: (_, _) async => ch,
      storage: _FakeStorage(),
    );
    final boxes = LocalBoxes();
    final sync = SyncService(conn, boxes);
    final epk = 'epk_sync_${++_counter}';
    conn.adopt(
      ch,
      PeerRecord(
        remoteEpk: epk,
        sessionName: 'Pi',
        relayUrl: 'ws://localhost',
        pairedAt: '2026-01-01T00:00:00Z',
      ),
    );
    await _settle(); // _onlineActivated → activate(epk) settles
    return (conn: conn, ch: ch, sync: sync, epk: epk);
  }

  List<MessageRecord> messages(String epk) {
    final box = LocalBoxes().openMsgsBox(epk, 'main');
    final out = [
      for (final v in box.values)
        MessageRecord.fromJson((v as Map).cast<String, dynamic>()),
    ];
    out.sort((a, b) => a.seq.compareTo(b.seq));
    return out;
  }

  SessionIndexRecord? index(String epk) {
    final raw = LocalBoxes().sessionsIndexBox().get('$epk:main');
    return raw is Map
        ? SessionIndexRecord.fromJson(raw.cast<String, dynamic>())
        : null;
  }

  test(
    'user_message echo writes one MessageRecord + updates the index',
    () async {
      final s = await setup();
      s.ch.push(UserInput(id: 'u1', text: 'hi'));
      await _settle();

      final m = messages(s.epk);
      expect(m, hasLength(1));
      expect(m.first.role, MsgRole.user);
      expect(m.first.text, 'hi');
      expect(m.first.pending, isFalse);
      expect(index(s.epk)?.status, SessionActivity.working);
      s.conn.dispose();
      s.sync.dispose();
    },
  );

  test('optimistic send + echo dedupe → exactly one record', () async {
    final s = await setup();
    await s.sync.sendMessage('hello');
    await _settle();
    expect(messages(s.epk), hasLength(1));
    expect(messages(s.epk).first.pending, isTrue);

    final id = (s.ch.sent.whereType<UserMessage>().last).id;
    s.ch.push(UserInput(id: id, text: 'hello'));
    await _settle();

    final m = messages(s.epk);
    expect(m, hasLength(1), reason: 'echo dedupes by id — no duplicate');
    expect(m.first.pending, isFalse);
    s.conn.dispose();
    s.sync.dispose();
  });

  test('streaming delta does NOT write to the DB (#7)', () async {
    final s = await setup();
    final before = messages(s.epk).length;
    s.ch.push(AgentChunk(inReplyTo: 'r1', delta: 'partial...'));
    await _settle();
    expect(messages(s.epk).length, before, reason: 'no row for a delta');
    expect(s.sync.streaming, isNotNull);
    expect(s.sync.streaming!.buffer, 'partial...');
    s.conn.dispose();
    s.sync.dispose();
  });

  test('agent_done finalizes the streamed message + flips to idle', () async {
    final s = await setup();
    s.ch.push(AgentChunk(inReplyTo: 'r1', delta: 'done text'));
    await _settle();
    s.ch.push(AgentDone(inReplyTo: 'r1'));
    await _settle();

    final assistant = messages(
      s.epk,
    ).where((m) => m.role == MsgRole.assistant).toList();
    expect(assistant, hasLength(1));
    expect(assistant.first.text, 'done text');
    expect(s.sync.streaming, isNull);
    expect(index(s.epk)?.status, SessionActivity.idle);
    s.conn.dispose();
    s.sync.dispose();
  });

  test('isWorking spans the whole turn (echo → agent_done)', () async {
    final s = await setup();
    expect(s.sync.isWorking, isFalse);
    final flags = <bool>[];
    final sub = s.sync.workingStream.listen(flags.add);

    s.ch.push(UserInput(id: 'u1', text: 'hi'));
    await _settle();
    expect(s.sync.isWorking, isTrue, reason: 'working from the echo');

    s.ch.push(AgentDone(inReplyTo: 'u1'));
    await _settle();
    expect(s.sync.isWorking, isFalse, reason: 'idle after agent_done');
    expect(flags, [true, false]);

    await sub.cancel();
    s.conn.dispose();
    s.sync.dispose();
  });

  test(
    'cursor: streaming is seeded EMPTY at turn start, before any chunk',
    () async {
      final s = await setup();
      expect(s.sync.streaming, isNull);

      // Optimistic send seeds the thinking cursor (online).
      await s.sync.sendMessage('hi');
      await _settle();
      expect(s.sync.streaming, isNotNull, reason: 'cursor during thinking');
      expect(s.sync.streaming!.buffer, isEmpty);

      s.conn.dispose();
      s.sync.dispose();
    },
  );

  test(
    'cursor: foreign echo seeds it; a text-less turn clears it on done',
    () async {
      final s = await setup();
      s.ch.push(UserInput(id: 'u9', text: 'from terminal'));
      await _settle();
      expect(s.sync.streaming, isNotNull, reason: 'cursor before any chunk');
      expect(s.sync.streaming!.buffer, isEmpty);

      // Turn produces no text (e.g. only tool calls) → done still clears it.
      s.ch.push(AgentDone(inReplyTo: 'u9'));
      await _settle();
      expect(s.sync.streaming, isNull, reason: 'done clears the cursor');
      s.conn.dispose();
      s.sync.dispose();
    },
  );

  test('cursor: a chunk appends onto the seeded empty buffer', () async {
    final s = await setup();
    s.ch.push(UserInput(id: 'u1', text: 'hi'));
    await _settle();
    s.ch.push(AgentChunk(inReplyTo: 'u1', delta: 'tok'));
    await _settle();
    expect(s.sync.streaming!.buffer, 'tok', reason: 'appended, not replaced');
    s.conn.dispose();
    s.sync.dispose();
  });

  test(
    'sequential: text → tool → text renders in chronological order',
    () async {
      final s = await setup();
      s.ch.push(UserInput(id: 'u1', text: 'go'));
      await _settle();
      s.ch.push(AgentChunk(inReplyTo: 'u1', delta: 'let me check'));
      await _settle(); // 16ms flush settles into the streaming buffer
      s.ch.push(ToolRequest(toolCallId: 'tc1', tool: 'Read', args: {}));
      await _settle();
      s.ch.push(ToolResult(toolCallId: 'tc1', result: {'ok': true}));
      await _settle();
      s.ch.push(AgentChunk(inReplyTo: 'u1', delta: 'all done'));
      await _settle();
      s.ch.push(AgentDone(inReplyTo: 'u1'));
      await _settle();

      final m = messages(s.epk);
      expect(
        m.map((r) => r.role),
        [MsgRole.user, MsgRole.assistant, MsgRole.tool, MsgRole.assistant],
        reason: 'pre-tool text, then tool, then post-tool text — in order',
      );
      expect(m[1].text, 'let me check');
      expect(m[2].tool?.tool, 'Read');
      expect(m[3].text, 'all done');
      s.conn.dispose();
      s.sync.dispose();
    },
  );

  test('clearActiveSession wipes the rows + index', () async {
    final s = await setup();
    s.ch.push(UserInput(id: 'u1', text: 'hi'));
    await _settle();
    expect(messages(s.epk), hasLength(1));

    await s.sync.clearActiveSession();
    await _settle();
    expect(messages(s.epk), isEmpty);
    expect(index(s.epk), isNull);
    s.conn.dispose();
    s.sync.dispose();
  });
}
