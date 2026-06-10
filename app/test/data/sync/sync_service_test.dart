// Plan/31 — SyncService is the single DB writer. Drives it through a fake
// channel adopted into a real ConnectionManager and asserts box contents.

import 'dart:async';
import 'dart:io';

import 'package:app/data/local/boxes.dart';
import 'package:app/data/local/records/message_record.dart';
import 'package:app/data/local/records/session_index_record.dart';
import 'package:app/data/repositories/session_read_repository.dart';
import 'package:app/data/sync/sync_service.dart';
import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/domain/session_state.dart';
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
  setup({Duration pendingSendTimeout = const Duration(seconds: 20)}) async {
    final ch = _FakeChannel();
    final conn = ConnectionManager(
      factory: (_, _) async => ch,
      storage: _FakeStorage(),
    );
    final boxes = LocalBoxes();
    final sync = SyncService(
      conn,
      boxes,
      pendingSendTimeout: pendingSendTimeout,
    );
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

  test('cancel sends a Cancel frame for the active turn target', () async {
    final s = await setup();
    s.ch.push(UserInput(id: 'u1', text: 'hi'));
    await _settle();

    await s.sync.cancel('u1');
    await _settle();

    final cancel = s.ch.sent.whereType<Cancel>().single;
    expect(cancel.targetId, 'u1');
    s.conn.dispose();
    s.sync.dispose();
  });

  test('cancelled stops the turn but preserves confirmed user history', () async {
    final s = await setup();
    s.ch.push(UserInput(id: 'u1', text: 'keep this'));
    await _settle();
    s.ch.push(AgentChunk(inReplyTo: 'u1', delta: 'partial'));
    s.ch.push(Cancelled(inReplyTo: 'cancel-1', targetId: 'u1'));
    await _settle();

    final rows = messages(s.epk);
    expect(
      rows.where((m) => m.id == 'u1' && m.role == MsgRole.user),
      hasLength(1),
    );
    expect(rows.singleWhere((m) => m.id == 'u1').pending, isFalse);
    expect(s.sync.streaming, isNull);
    expect(s.sync.isWorking, isFalse);
    expect(index(s.epk)?.status, SessionActivity.idle);
    s.conn.dispose();
    s.sync.dispose();
  });

  test('cancelled removes a still-pending optimistic user row', () async {
    final s = await setup();
    await s.sync.sendMessage('stop before echo');
    await _settle();
    final id = (s.ch.sent.whereType<UserMessage>().last).id;
    expect(messages(s.epk).single.pending, isTrue);

    s.ch.push(Cancelled(inReplyTo: 'cancel-1', targetId: id));
    await _settle();

    expect(messages(s.epk), isEmpty);
    expect(s.sync.streaming, isNull);
    expect(s.sync.isWorking, isFalse);
    expect(index(s.epk)?.status, SessionActivity.idle);
    s.conn.dispose();
    s.sync.dispose();
  });

  test(
    'server error clears pending chunk flush so chat does not stay working',
    () async {
      final s = await setup();
      s.ch.push(UserInput(id: 'u1', text: 'hi'));
      await _settle();
      s.ch.push(AgentChunk(inReplyTo: 'u1', delta: 'partial'));
      s.ch.push(ErrorMessage(
        inReplyTo: 'cancel-1',
        code: 'internal_error',
        message: 'No active Pi context to abort',
      ));
      await _settle();

      expect(s.sync.streaming, isNull);
      expect(s.sync.isWorking, isFalse);
      expect(index(s.epk)?.status, SessionActivity.idle);
      final errorTexts = messages(
        s.epk,
      ).where((m) => m.role == MsgRole.assistant).map((m) => m.text);
      expect(errorTexts, contains(startsWith('⚠ internal_error:')));
      s.conn.dispose();
      s.sync.dispose();
    },
  );

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

  test('switching sessions resets the in-memory turn state — working/streaming '
      'do NOT leak into the next chat (plan/32)', () async {
    final s = await setup();

    // Session 1 is mid-turn: working flag + streaming buffer populated.
    s.ch.push(AgentChunk(inReplyTo: 'r1', delta: 'thinking...'));
    await _settle();
    expect(s.sync.isWorking, isTrue);
    expect(s.sync.streaming, isNotNull);
    expect(s.sync.workingReplyTo, 'r1');

    final flags = <bool>[];
    final sub = s.sync.workingStream.listen(flags.add);

    // Switch the writer to a DIFFERENT session (what the chat does on a
    // tablet session switch). Must clear the in-memory signals.
    await s.sync.activate('epk_other_session', 'main');
    await _settle();

    expect(
      s.sync.isWorking,
      isFalse,
      reason: 'chat 2 must not inherit chat 1 working',
    );
    expect(
      s.sync.streaming,
      isNull,
      reason: 'chat 1 streaming buffer must not show in chat 2',
    );
    expect(s.sync.workingReplyTo, isNull);
    expect(
      flags,
      contains(false),
      reason: 'listeners are notified the flag cleared',
    );

    // The previous session's DURABLE index must stay "working" — the Pi
    // may still be mid-turn and Home reflects it (relay broadcast + DB).
    // Clearing the in-memory signals must NOT idle the box row.
    expect(
      index(s.epk)?.status,
      SessionActivity.working,
      reason: 'switching away must not idle chat 1 in the DB',
    );

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

  test('re-applying an IDENTICAL SessionHistory is idempotent — no box churn, '
      'so the relay re-sending history on every reconnect no longer tears the '
      'list down and rebuilds it (plan/32 flicker fix)', () async {
    final s = await setup();
    final read = SessionReadRepository(LocalBoxes());
    var emits = 0;
    final sub = read.watchMessages(s.epk, 'main').listen((_) => emits++);
    await _settle();

    SessionHistory hist(String inReplyTo) => SessionHistory(
      inReplyTo: inReplyTo,
      sessionStartedAt: 0,
      events: const [
        UserInputEvt(ts: 1, id: 'u1', text: 'hi'),
        AgentMessageEvt(ts: 2, inReplyTo: 'a1', text: 'hello'),
        ToolRequestEvt(ts: 3, toolCallId: 'c1', tool: 'Read', args: null),
      ],
      eos: true,
    );

    s.ch.push(hist('sync1'));
    await _settle();
    final afterFirst = emits;
    expect(afterFirst, greaterThan(1), reason: 'first apply populates rows');
    expect(messages(s.epk).map((r) => r.role), [
      MsgRole.user,
      MsgRole.assistant,
      MsgRole.tool,
    ]);

    // Relay re-delivers the SAME history (different in_reply_to, identical
    // events) — the reconcile must write nothing → no watch event → no emit.
    s.ch.push(hist('sync2'));
    await _settle();
    expect(
      emits,
      afterFirst,
      reason: 'identical re-apply must not emit (no list rebuild/flicker)',
    );

    await sub.cancel();
    s.conn.dispose();
    s.sync.dispose();
  });

  test(
    'switching the writer to a new session: a late frame from the OLD '
    "connection is dropped — it neither writes the new box nor appears in the "
    "new session's read projection (plan/32f session-switch bleed)",
    () async {
      final s = await setup(); // bound to s.epk (peer A)
      s.ch.push(UserInput(id: 'a1', text: 'from chat1'));
      await _settle();
      expect(messages(s.epk), hasLength(1));

      // Switch the writer to chat 2 (epkB) WITHOUT a new channel — simulates
      // the window where the chat calls activate(epkB) before switchTo tears
      // the old peer's channel down. _activeEpk moves; the old channel (origin
      // = peer A) is still draining.
      const epkB = 'epk_chat2_zzz';
      final read = SessionReadRepository(LocalBoxes());
      final seenLens = <int>[];
      final sub = read
          .watchMessages(epkB, 'main')
          .listen((rows) => seenLens.add(rows.length));
      await s.sync.activate(epkB, 'main');
      await _settle();

      // Straggler frame on the OLD (peer A) channel.
      s.ch.push(UserInput(id: 'late', text: 'late chat1'));
      await _settle();

      expect(
        messages(epkB),
        isEmpty,
        reason: 'old-connection frame must not bleed into the new box',
      );
      expect(
        seenLens.every((n) => n == 0),
        isTrue,
        reason: "chat 2's projection never shows chat 1 rows",
      );
      expect(
        messages(s.epk),
        hasLength(1),
        reason: 'chat 1 box keeps exactly its own row (late frame dropped)',
      );

      await sub.cancel();
      s.conn.dispose();
      s.sync.dispose();
    },
  );

  test('compaction ServerMessage writes a system row that projects to a '
      'CompactionMsg system bubble (plan/32)', () async {
    final s = await setup();
    s.ch.push(
      Compaction(
        summary: 'recapped the thread',
        tokensBefore: 12000,
        ts: 1700000000000,
      ),
    );
    await _settle();

    final m = messages(s.epk);
    expect(m, hasLength(1));
    expect(m.first.role, MsgRole.compaction);
    expect(m.first.text, 'recapped the thread');
    expect(m.first.tokensBefore, 12000);
    // Projects to the domain system-bubble message.
    expect(m.first.toChatMessage(), isA<CompactionMsg>());

    s.conn.dispose();
    s.sync.dispose();
  });

  test('compaction event in session_history reconstructs the system row on '
      're-sync (plan/32)', () async {
    final s = await setup();
    s.ch.push(
      SessionHistory(
        inReplyTo: 'sync1',
        sessionStartedAt: 0,
        events: const [
          UserInputEvt(ts: 1, id: 'u1', text: 'hi'),
          AgentMessageEvt(ts: 2, inReplyTo: 'a1', text: 'hello'),
          CompactionEvt(ts: 3, summary: 'compacted', tokensBefore: 5000),
        ],
        eos: true,
      ),
    );
    await _settle();

    final m = messages(s.epk);
    expect(m.map((r) => r.role), [
      MsgRole.user,
      MsgRole.assistant,
      MsgRole.compaction,
    ]);
    expect(m.last.text, 'compacted');
    expect(m.last.tokensBefore, 5000);
    expect(m.last.toChatMessage(), isA<CompactionMsg>());

    s.conn.dispose();
    s.sync.dispose();
  });

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

  // Plan/32 safety net — a sent message whose echo never comes back must not
  // spin forever; the optimistic bubble is removed SILENTLY after the timeout.
  group('no-echo send timeout', () {
    const short = Duration(milliseconds: 60);

    test(
      '(a) pending bubble is removed silently when no echo arrives',
      () async {
        final s = await setup(pendingSendTimeout: short);
        await s.sync.sendMessage('hello');
        await _settle();
        expect(messages(s.epk), hasLength(1), reason: 'optimistic pending row');
        expect(messages(s.epk).first.pending, isTrue);
        expect(s.sync.isWorking, isTrue);
        expect(s.sync.streaming, isNotNull, reason: 'thinking cursor seeded');

        // No echo — wait past the timeout window.
        await Future<void>.delayed(const Duration(milliseconds: 140));
        await _settle();

        expect(
          messages(s.epk),
          isEmpty,
          reason: 'bubble removed, no failed state',
        );
        expect(
          s.sync.isWorking,
          isFalse,
          reason: 'working cleared for this id',
        );
        expect(s.sync.streaming, isNull, reason: 'thinking cursor cleared');
        expect(index(s.epk)?.status, SessionActivity.idle);
        expect(s.sync.debugPendingSendTimerCount, 0);
        s.conn.dispose();
        s.sync.dispose();
      },
    );

    test(
      '(b) echo within the window confirms the row and cancels the timer',
      () async {
        final s = await setup(pendingSendTimeout: short);
        await s.sync.sendMessage('hello');
        await _settle();
        expect(s.sync.debugPendingSendTimerCount, 1, reason: 'timer armed');
        final id = s.ch.sent.whereType<UserMessage>().last.id;

        // Echo arrives promptly → confirms + disarms.
        s.ch.push(UserInput(id: id, text: 'hello'));
        await _settle();
        expect(messages(s.epk), hasLength(1));
        expect(
          messages(s.epk).first.pending,
          isFalse,
          reason: 'confirmed by echo',
        );
        expect(
          s.sync.debugPendingSendTimerCount,
          0,
          reason: 'echo cancelled timer',
        );

        // Wait PAST the timeout — the cancelled timer must NOT remove the row.
        await Future<void>.delayed(const Duration(milliseconds: 140));
        await _settle();
        expect(
          messages(s.epk),
          hasLength(1),
          reason: 'row survives the window',
        );
        expect(messages(s.epk).first.pending, isFalse);
        s.conn.dispose();
        s.sync.dispose();
      },
    );

    test(
      '(c) timers are cancelled on session switch and on dispose (no leak)',
      () async {
        // Session switch path.
        final s = await setup(pendingSendTimeout: short);
        await s.sync.sendMessage('one');
        await _settle();
        expect(s.sync.debugPendingSendTimerCount, 1);

        await s.sync.activate('epk_switch_target', 'main');
        await _settle();
        expect(
          s.sync.debugPendingSendTimerCount,
          0,
          reason: 'session switch cancels + clears pending timers',
        );

        // dispose path (fresh service so the switch above doesn't mask it).
        final s2 = await setup(pendingSendTimeout: short);
        await s2.sync.sendMessage('two');
        await _settle();
        expect(s2.sync.debugPendingSendTimerCount, 1);
        s2.sync.dispose();
        expect(
          s2.sync.debugPendingSendTimerCount,
          0,
          reason: 'dispose cancels + clears pending timers',
        );

        s.conn.dispose();
        s.sync.dispose();
        s2.conn.dispose();
      },
    );

    test('(d) an offline (held-pending) send is reaped too', () async {
      // No channel ever adopted → sendMessage takes the offline path. Decision:
      // held-pending is reaped 20s after its ts as well (nothing spins forever).
      final conn = ConnectionManager(
        factory: (_, _) async => _FakeChannel(),
        storage: _FakeStorage(),
      );
      final sync = SyncService(conn, LocalBoxes(), pendingSendTimeout: short);
      final epk = 'epk_offline_${++_counter}';
      await sync.activate(epk, 'main');
      await _settle();

      await sync.sendMessage('typed while offline');
      await _settle();
      expect(messages(epk), hasLength(1), reason: 'held pending row written');
      expect(messages(epk).first.pending, isTrue);
      expect(
        sync.debugPendingSendTimerCount,
        1,
        reason: 'reaper armed offline',
      );

      await Future<void>.delayed(const Duration(milliseconds: 140));
      await _settle();
      expect(
        messages(epk),
        isEmpty,
        reason: 'offline bubble reaped (decision)',
      );
      conn.dispose();
      sync.dispose();
    });

    test(
      '(e) returning to a session reaps a bubble already past the window',
      () async {
        // Quick exit then return: the live timer is cancelled on switch-away,
        // but _loadIndex re-arms on return using the saved ts → an already-stale
        // row fires immediately. Covers app-restart + quick-switch orphans.
        final s = await setup(pendingSendTimeout: short);
        await s.sync.sendMessage('hi');
        await _settle();
        expect(messages(s.epk), hasLength(1));

        // Leave quickly → live timer cancelled; row stays pending in the box.
        await s.sync.activate('epk_away_${++_counter}', 'main');
        await _settle();
        expect(
          s.sync.debugPendingSendTimerCount,
          0,
          reason: 'timers cleared on switch',
        );
        expect(
          messages(s.epk),
          hasLength(1),
          reason: 'orphaned row still in box',
        );

        // Time passes beyond the window while away from the session.
        await Future<void>.delayed(const Duration(milliseconds: 140));
        expect(
          messages(s.epk),
          hasLength(1),
          reason: 'no live timer reaps it while away',
        );

        // Return → load re-arms by ts → already stale → reaped on arrival.
        await s.sync.activate(s.epk, 'main');
        await _settle();
        expect(
          messages(s.epk),
          isEmpty,
          reason: 'stale pending reaped on return',
        );
        s.conn.dispose();
        s.sync.dispose();
      },
    );
  });
}
