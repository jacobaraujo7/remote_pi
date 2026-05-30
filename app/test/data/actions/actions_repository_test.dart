// Plan/28 Wave C — ActionsRepository unit tests.
//
// Covers id correlation between ClientMessage sends and the matching
// `action_ok` / `action_error` / `models_list` replies, plus the
// disconnect / timeout / caching paths.

import 'dart:async';

import 'package:app/data/actions/actions_repository.dart';
import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeChannel implements IChannel, IControlLink {
  final _ctrl = StreamController<ServerMessage>.broadcast();
  final _controlCtrl = StreamController<ControlInbound>.broadcast();
  final List<ClientMessage> sent = [];

  @override
  Stream<ServerMessage> get serverMessages => _ctrl.stream;

  @override
  Stream<ControlInbound> get controlFrames => _controlCtrl.stream;

  @override
  Future<void> send(ClientMessage msg) async {
    sent.add(msg);
  }

  @override
  void sendControl(Map<String, dynamic> json) {}

  @override
  Future<void> close() async {
    await _ctrl.close();
    await _controlCtrl.close();
  }

  void push(ServerMessage m) => _ctrl.add(m);
  void pushControl(ControlInbound m) => _controlCtrl.add(m);
}

class _FakeStorage extends PairingStorage {
  @override
  Future<List<PeerRecord>> listPeers() async => const [];
}

Future<({ActionsRepository repo, ConnectionManager cm, _FakeChannel ch})>
_setup({Duration timeout = const Duration(seconds: 5)}) async {
  final ch = _FakeChannel();
  // emitDebounce: zero so rooms/presence updates flow synchronously
  // through the rooms stream and the ActionsRepository's reactive
  // hooks (cache invalidation, activeRoomMeta) see them without
  // having to wait for the 50ms debounce window.
  final cm = ConnectionManager(
    factory: (_, _) async => ch,
    storage: _FakeStorage(),
    emitDebounce: Duration.zero,
  );
  final repo = ActionsRepository(cm, timeout: timeout);
  cm.adopt(
    ch,
    const PeerRecord(
      remoteEpk: 'epk_actions',
      sessionName: 'pi',
      relayUrl: 'ws://localhost',
      pairedAt: '2026-01-01T00:00:00Z',
    ),
  );
  // Let the StatusOnline emit propagate into the repo.
  await Future<void>.delayed(const Duration(milliseconds: 5));
  return (repo: repo, cm: cm, ch: ch);
}

void main() {
  group('ActionsRepository — typed action dispatch', () {
    test('compact() resolves on action_ok with matching id', () async {
      final s = await _setup();
      final future = s.repo.compact();
      // Let the send complete so we can fish the id out.
      await Future<void>.delayed(const Duration(milliseconds: 1));
      final sent = s.ch.sent.single as SessionCompact;
      s.ch.push(
        ActionOk(
          inReplyTo: sent.id,
          action: ActionName.sessionCompact,
          rawAction: 'session_compact',
        ),
      );
      await future; // completes without throwing
      s.cm.dispose();
    });

    test('compact() throws ActionFailure on action_error', () async {
      final s = await _setup();
      final future = s.repo.compact();
      await Future<void>.delayed(const Duration(milliseconds: 1));
      final sent = s.ch.sent.single as SessionCompact;
      s.ch.push(
        ActionError(
          inReplyTo: sent.id,
          action: ActionName.sessionCompact,
          rawAction: 'session_compact',
          error: 'compact unavailable',
        ),
      );
      expect(
        () => future,
        throwsA(
          isA<ActionFailure>().having(
            (e) => e.message,
            'message',
            contains('compact unavailable'),
          ),
        ),
      );
      s.cm.dispose();
    });

    test('newSession() sends session_new', () async {
      final s = await _setup();
      final future = s.repo.newSession();
      await Future<void>.delayed(const Duration(milliseconds: 1));
      final sent = s.ch.sent.single as SessionNew;
      expect(sent.toJson()['type'], 'session_new');
      s.ch.push(
        ActionOk(
          inReplyTo: sent.id,
          action: ActionName.sessionNew,
          rawAction: 'session_new',
        ),
      );
      await future;
      s.cm.dispose();
    });

    test('setModel(provider, modelId) sends model_set', () async {
      final s = await _setup();
      final future = s.repo.setModel('anthropic', 'claude-opus-4-7');
      await Future<void>.delayed(const Duration(milliseconds: 1));
      final sent = s.ch.sent.single as ModelSet;
      expect(sent.provider, 'anthropic');
      expect(sent.modelId, 'claude-opus-4-7');
      s.ch.push(
        ActionOk(
          inReplyTo: sent.id,
          action: ActionName.modelSet,
          rawAction: 'model_set',
        ),
      );
      await future;
      s.cm.dispose();
    });

    test('setThinking(level) sends thinking_set with wire string', () async {
      final s = await _setup();
      final future = s.repo.setThinking(ThinkingLevel.high);
      await Future<void>.delayed(const Duration(milliseconds: 1));
      final sent = s.ch.sent.single as ThinkingSet;
      expect(sent.level, ThinkingLevel.high);
      expect(sent.toJson()['level'], 'high');
      s.ch.push(
        ActionOk(
          inReplyTo: sent.id,
          action: ActionName.thinkingSet,
          rawAction: 'thinking_set',
        ),
      );
      await future;
      s.cm.dispose();
    });
  });

  group('ActionsRepository — models catalogue', () {
    test('listModels() returns parsed wire models + current', () async {
      final s = await _setup();
      final future = s.repo.listModels();
      await Future<void>.delayed(const Duration(milliseconds: 1));
      final sent = s.ch.sent.single as ListModels;
      const opus = WireModel(
        id: 'claude-opus-4-7',
        name: 'Claude Opus 4.7',
        provider: 'anthropic',
        reasoning: true,
        contextWindow: 200000,
      );
      const sonnet = WireModel(
        id: 'claude-sonnet-4-6',
        name: 'Claude Sonnet 4.6',
        provider: 'anthropic',
        reasoning: false,
        contextWindow: 200000,
      );
      s.ch.push(
        ModelsList(
          inReplyTo: sent.id,
          models: const [opus, sonnet],
          current: opus,
        ),
      );
      final result = await future;
      expect(result.models, [opus, sonnet]);
      expect(result.current, opus);
      s.cm.dispose();
    });

    test(
      'listModels() caches by session and short-circuits second call',
      () async {
        final s = await _setup();
        final firstFuture = s.repo.listModels();
        await Future<void>.delayed(const Duration(milliseconds: 1));
        final sent = s.ch.sent.single as ListModels;
        const m = WireModel(
          id: 'gpt-4o',
          name: 'GPT-4o',
          provider: 'openai',
          reasoning: false,
          contextWindow: 128000,
        );
        s.ch.push(
          ModelsList(inReplyTo: sent.id, models: const [m], current: m),
        );
        await firstFuture;
        // Second call should NOT send another list_models.
        final second = await s.repo.listModels();
        expect(s.ch.sent.whereType<ListModels>().length, 1);
        expect(second.models.single, m);
        s.cm.dispose();
      },
    );

    test('listModels(forceRefresh: true) bypasses cache', () async {
      final s = await _setup();
      final firstFuture = s.repo.listModels();
      await Future<void>.delayed(const Duration(milliseconds: 1));
      final firstSent = s.ch.sent.single as ListModels;
      s.ch.push(ModelsList(inReplyTo: firstSent.id, models: const []));
      await firstFuture;

      final secondFuture = s.repo.listModels(forceRefresh: true);
      await Future<void>.delayed(const Duration(milliseconds: 1));
      final secondSent = s.ch.sent.whereType<ListModels>().last;
      expect(secondSent.id, isNot(firstSent.id));
      s.ch.push(ModelsList(inReplyTo: secondSent.id, models: const []));
      await secondFuture;
      s.cm.dispose();
    });

    test('setModel invalidates the models cache', () async {
      final s = await _setup();
      // Prime the cache.
      final firstList = s.repo.listModels();
      await Future<void>.delayed(const Duration(milliseconds: 1));
      final firstSent = s.ch.sent.single as ListModels;
      s.ch.push(ModelsList(inReplyTo: firstSent.id, models: const []));
      await firstList;

      // Switch model — should drop the cache entry.
      final setModelFuture = s.repo.setModel('openai', 'gpt-4o');
      await Future<void>.delayed(const Duration(milliseconds: 1));
      final modelSet = s.ch.sent.whereType<ModelSet>().single;
      s.ch.push(
        ActionOk(
          inReplyTo: modelSet.id,
          action: ActionName.modelSet,
          rawAction: 'model_set',
        ),
      );
      await setModelFuture;

      // Next listModels triggers a fresh round-trip.
      final secondList = s.repo.listModels();
      await Future<void>.delayed(const Duration(milliseconds: 1));
      expect(s.ch.sent.whereType<ListModels>().length, 2);
      final secondSent = s.ch.sent.whereType<ListModels>().last;
      s.ch.push(ModelsList(inReplyTo: secondSent.id, models: const []));
      await secondList;
      s.cm.dispose();
    });
  });

  group('ActionsRepository — failure modes', () {
    test('compact() throws "offline" when no channel adopted yet', () async {
      final ch = _FakeChannel();
      final cm = ConnectionManager(
        factory: (_, _) async => ch,
        storage: _FakeStorage(),
      );
      final repo = ActionsRepository(cm);
      // No adopt — status is StatusNoPeer.
      expect(
        () => repo.compact(),
        throwsA(
          isA<ActionFailure>().having((e) => e.message, 'message', 'offline'),
        ),
      );
      repo.dispose();
      cm.dispose();
    });

    test('pending action fails with "disconnected" on channel drop', () async {
      final s = await _setup();
      final future = s.repo.compact();
      await Future<void>.delayed(const Duration(milliseconds: 1));
      await s.cm.disconnect();
      expect(
        () => future,
        throwsA(
          isA<ActionFailure>().having(
            (e) => e.message,
            'message',
            'disconnected',
          ),
        ),
      );
      s.cm.dispose();
    });

    test('pending action times out when no reply arrives', () async {
      final s = await _setup(timeout: const Duration(milliseconds: 30));
      final future = s.repo.compact();
      expect(
        () => future,
        throwsA(
          isA<ActionFailure>().having((e) => e.message, 'message', 'timeout'),
        ),
      );
      s.cm.dispose();
    });

    test(
      'external room_meta_updated with new model invalidates listModels cache',
      () async {
        final s = await _setup();
        // Prime the cache.
        final firstFuture = s.repo.listModels();
        await Future<void>.delayed(const Duration(milliseconds: 1));
        final firstSent = s.ch.sent.whereType<ListModels>().single;
        const opus = WireModel(
          id: 'claude-opus-4-7',
          name: 'Claude Opus 4.7',
          provider: 'anthropic',
          reasoning: true,
          contextWindow: 200000,
        );
        s.ch.push(
          ModelsList(
            inReplyTo: firstSent.id,
            models: const [opus],
            current: opus,
          ),
        );
        await firstFuture;

        // Cached: second listModels returns cached, no network call.
        await s.repo.listModels();
        expect(s.ch.sent.whereType<ListModels>().length, 1);

        // Seed a RoomAnnounced + RoomMetaUpdated to simulate external
        // model switch. The ConnectionManager broadcasts roomsStream
        // and the ActionsRepository should drop the cache.
        s.ch.pushControl(
          const RoomAnnounced(
            peer: 'epk_actions',
            roomId: 'main',
            startedAt: 1,
            model: 'claude-opus-4-7',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        s.ch.pushControl(
          const RoomMetaUpdated(
            peer: 'epk_actions',
            roomId: 'main',
            model: 'gpt-4o',
            hasModel: true,
            hasThinking: false,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        // Cache should be busted: third listModels triggers a fresh
        // network call.
        final third = s.repo.listModels();
        await Future<void>.delayed(const Duration(milliseconds: 5));
        final newSends = s.ch.sent.whereType<ListModels>().toList();
        expect(
          newSends.length,
          2,
          reason: 'external model change must invalidate cache',
        );
        s.ch.push(ModelsList(inReplyTo: newSends.last.id, models: const []));
        await third;

        s.cm.dispose();
      },
    );

    test('activeRoomMeta stream forwards model and thinking', () async {
      final s = await _setup();
      final received = <ActiveRoomMeta>[];
      final sub = s.repo.activeRoomMetaStream.listen(received.add);

      s.ch.pushControl(
        const RoomAnnounced(
          peer: 'epk_actions',
          roomId: 'main',
          startedAt: 1,
          model: 'claude-opus-4-7',
          thinking: ThinkingLevel.high,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(received, isNotEmpty);
      final last = received.last;
      expect(last.model, 'claude-opus-4-7');
      expect(last.thinking, ThinkingLevel.high);
      expect(last.peerEpk, 'epk_actions');
      expect(s.repo.activeRoomMeta.thinking, ThinkingLevel.high);

      await sub.cancel();
      s.cm.dispose();
    });

    test(
      'switchRoom (same peer, different cwd) refreshes activeRoomMeta — '
      'fixes the Quick Actions sheet showing the previous chat model',
      () async {
        final s = await _setup();
        // Two cwd-rooms on the same Mac, different models.
        s.ch.pushControl(
          const RoomAnnounced(
            peer: 'epk_actions',
            roomId: 'main',
            startedAt: 1,
            model: 'model-A',
          ),
        );
        s.ch.pushControl(
          const RoomAnnounced(
            peer: 'epk_actions',
            roomId: 'work',
            startedAt: 2,
            model: 'model-B',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 30));
        // Active room is 'main' (the bound default) → model-A.
        expect(s.repo.activeRoomMeta.model, 'model-A');

        // User opens the 'work' cwd chat → ChatViewModel calls switchRoom.
        s.cm.switchRoom('work');
        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(
          s.repo.activeRoomMeta.model,
          'model-B',
          reason: 'meta must follow the active room, not stay on chat 1',
        );
        expect(s.repo.activeRoomMeta.roomId, 'work');
        s.cm.dispose();
      },
    );

    test('replies with unknown id are ignored', () async {
      final s = await _setup();
      s.ch.push(
        ActionOk(
          inReplyTo: 'never-sent',
          action: ActionName.sessionCompact,
          rawAction: 'session_compact',
        ),
      );
      // Real compact still works afterwards.
      final future = s.repo.compact();
      await Future<void>.delayed(const Duration(milliseconds: 1));
      final sent = s.ch.sent.whereType<SessionCompact>().single;
      s.ch.push(
        ActionOk(
          inReplyTo: sent.id,
          action: ActionName.sessionCompact,
          rawAction: 'session_compact',
        ),
      );
      await future;
      s.cm.dispose();
    });
  });
}
