import 'dart:convert';
import 'dart:io';

import 'package:app/protocol/codec.dart';
import 'package:app/protocol/protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('decode fixtures', () {
    final fixtureDir = Directory('../.orchestration/contracts/fixtures');

    test('fixture directory exists', () {
      expect(
        fixtureDir.existsSync(),
        isTrue,
        reason: 'fixtures dir not found at ${fixtureDir.path}',
      );
    });

    test('all fixture lines parse or throw UnsupportedTypeException', () {
      final files = fixtureDir.listSync().whereType<File>().toList();
      expect(files, isNotEmpty, reason: 'no fixture files found');

      for (final file in files) {
        final lines = file.readAsLinesSync().where((l) => l.trim().isNotEmpty);
        for (final line in lines) {
          try {
            final msg = decodeServer(line);
            expect(msg, isNotNull);
          } on UnsupportedTypeException {
            // client-only types (user_message, approve_tool, etc.) — expected
          }
        }
      }
    });
  });

  group('AgentChunk', () {
    test('parses in_reply_to and delta', () {
      final msg = ServerMessage.fromJson({
        'type': 'agent_chunk',
        'in_reply_to': '018f9c2a-7b1e-7000-9a3b-1c2d3e4f5a6e',
        'delta': 'Vou olhar o ',
      });

      expect(msg, isA<AgentChunk>());
      final chunk = msg as AgentChunk;
      expect(chunk.inReplyTo, '018f9c2a-7b1e-7000-9a3b-1c2d3e4f5a6e');
      expect(chunk.delta, 'Vou olhar o ');
    });
  });

  group('AgentDone', () {
    test('parses usage', () {
      final msg = ServerMessage.fromJson({
        'type': 'agent_done',
        'in_reply_to': 'x',
        'usage': {'input_tokens': 120, 'output_tokens': 340},
      });
      final done = msg as AgentDone;
      expect(done.usage!.inputTokens, 120);
      expect(done.usage!.outputTokens, 340);
    });

    test('usage is optional', () {
      final msg = ServerMessage.fromJson({
        'type': 'agent_done',
        'in_reply_to': 'x',
      });
      expect((msg as AgentDone).usage, isNull);
    });
  });

  group('ToolRequest', () {
    test('parses tool_call_id, tool, args', () {
      final msg = ServerMessage.fromJson({
        'type': 'tool_request',
        'tool_call_id': 'tc_018f9c2b',
        'tool': 'Bash',
        'args': {'command': 'rm -rf node_modules'},
      });
      final req = msg as ToolRequest;
      expect(req.toolCallId, 'tc_018f9c2b');
      expect(req.tool, 'Bash');
    });
  });

  group('ToolResult', () {
    test('parses result', () {
      final msg = ServerMessage.fromJson({
        'type': 'tool_result',
        'tool_call_id': 'tc_1',
        'result': {'exit_code': 0},
      });
      expect((msg as ToolResult).toolCallId, 'tc_1');
      expect(msg.error, isNull);
    });

    test('parses error field', () {
      final msg = ServerMessage.fromJson({
        'type': 'tool_result',
        'tool_call_id': 'tc_2',
        'error': 'command timed out after 60s',
      });
      expect((msg as ToolResult).error, 'command timed out after 60s');
      expect(msg.result, isNull);
    });
  });

  group('AskUser protocol', () {
    test('parses ask_user_prompt with options and flags', () {
      final msg = ServerMessage.fromJson({
        'type': 'ask_user_prompt',
        'id': 'ask_1',
        'question': 'Pick one',
        'context': 'Context',
        'options': [
          'A',
          {'title': 'B', 'description': 'Fast path'},
        ],
        'allow_multiple': true,
        'allow_freeform': true,
        'allow_comment': false,
      });
      final prompt = msg as AskUserPrompt;
      expect(prompt.id, 'ask_1');
      expect(prompt.question, 'Pick one');
      expect(prompt.context, 'Context');
      expect(prompt.options, hasLength(2));
      expect(prompt.options[0].title, 'A');
      expect(prompt.options[1].description, 'Fast path');
      expect(prompt.allowMultiple, isTrue);
      expect(prompt.allowFreeform, isTrue);
    });

    test('parses ask_user room_id for app-side room filtering', () {
      final prompt = ServerMessage.fromJson({
        'type': 'ask_user_prompt',
        'id': 'ask_room',
        'question': 'Room scoped?',
        'room_id': 'room-current',
      }) as AskUserPrompt;
      final resolved = ServerMessage.fromJson({
        'type': 'ask_user_resolved',
        'id': 'ask_room',
        'answer_label': 'A',
        'cancelled': false,
        'room_id': 'room-current',
      }) as AskUserResolved;

      expect(prompt.roomId, 'room-current');
      expect(resolved.roomId, 'room-current');
    });

    test('parses ask_user_resolved with cancellation flag', () {
      final msg = ServerMessage.fromJson({
        'type': 'ask_user_resolved',
        'id': 'ask_1',
        'answer_label': 'A',
        'cancelled': false,
      });
      final resolved = msg as AskUserResolved;
      expect(resolved.id, 'ask_1');
      expect(resolved.answerLabel, 'A');
      expect(resolved.cancelled, isFalse);
    });

    test('encodes AskUserResponse.selection', () {
      final msg = encodeClient(
        AskUserResponse.selection(
          id: 'ask_1',
          selections: const ['A', 'B'],
          comment: 'needs one',
        ),
      );
      final raw = jsonDecode(msg.trim()) as Map<String, dynamic>;
      expect(raw['type'], 'ask_user_response');
      expect(raw['response']['kind'], 'selection');
      expect(raw['response']['selections'], ['A', 'B']);
      expect(raw['response']['comment'], 'needs one');
    });

    test('encodes AskUserResponse.freeform and cancelled', () {
      final freeform =
          jsonDecode(
                encodeClient(
                  AskUserResponse.freeform(id: 'ask_2', text: 'Use B'),
                ).trim(),
              )
              as Map<String, dynamic>;
      final canceled =
          jsonDecode(encodeClient(AskUserResponse.cancelled('ask_2')).trim())
              as Map<String, dynamic>;

      expect(freeform['response']['kind'], 'freeform');
      expect(freeform['response']['text'], 'Use B');
      expect(canceled['cancelled'], true);
      expect(canceled.containsKey('response'), isFalse);
    });

    test('parses SessionHistory ask_user events', () {
      final hist =
          ServerMessage.fromJson({
                'type': 'session_history',
                'in_reply_to': 'sync1',
                'session_started_at': 0,
                'eos': true,
                'room_id': 'room-hist',
                'events': [
                  {
                    'type': 'ask_user_prompt',
                    'ts': 1,
                    'id': 'ask_h1',
                    'question': 'Q',
                    'context': 'Ctx',
                    'options': [
                      {'title': 'A'},
                    ],
                    'allow_multiple': false,
                    'allow_freeform': false,
                    'allow_comment': false,
                  },
                  {
                    'type': 'ask_user_resolved',
                    'ts': 2,
                    'id': 'ask_h1',
                    'answer_label': 'A',
                    'cancelled': false,
                  },
                ],
              })
              as SessionHistory;
      expect(hist.roomId, 'room-hist');
      expect(hist.events, hasLength(2));
      expect(hist.events[0], isA<AskUserPromptEvt>());
      expect(hist.events[1], isA<AskUserResolvedEvt>());
    });
  });

  group('UnsupportedTypeException', () {
    test('thrown for unknown type', () {
      expect(
        () => ServerMessage.fromJson({'type': 'future_type'}),
        throwsA(isA<UnsupportedTypeException>()),
      );
    });

    test('thrown for null type', () {
      expect(
        () => ServerMessage.fromJson({'data': 1}),
        throwsA(isA<UnsupportedTypeException>()),
      );
    });
  });

  group('Pair messages', () {
    test('PairOk fixture parses', () {
      final file = File('../.orchestration/contracts/fixtures/pair_ok.jsonl');
      final line = file.readAsLinesSync().firstWhere(
        (l) => l.trim().isNotEmpty,
      );
      final msg = decodeServer(line) as PairOk;
      expect(msg.inReplyTo, isNotEmpty);
      expect(msg.sessionName, contains('remote_pi'));
    });

    test('PairOk.fromJson decodes harness + hostname (plan/27 Wave A)', () {
      final msg = PairOk.fromJson({
        'type': 'pair_ok',
        'in_reply_to': 'req-1',
        'session_name': 'remote_pi · main',
        'session_started_at': 1700000000000,
        'room_id': 'room-xyz',
        'hostname': 'Mac do Jacob',
        'harness': {'name': 'Pi coding agent', 'version': '0.4.2'},
      });
      expect(msg.hostname, 'Mac do Jacob');
      expect(msg.harness, isNotNull);
      expect(msg.harness!.name, 'Pi coding agent');
      expect(msg.harness!.version, '0.4.2');
    });

    test('PairOk.fromJson tolerates missing harness/hostname (legacy Pi)', () {
      final msg = PairOk.fromJson({
        'type': 'pair_ok',
        'in_reply_to': 'req-2',
        'session_name': 'remote_pi · main',
        'session_started_at': 1700000000000,
      });
      expect(msg.harness, isNull);
      expect(msg.hostname, isNull);
    });

    test(
      'PiHarness.fromJson tolerates partial blob with default fallbacks',
      () {
        final h = PiHarness.fromJson(<String, dynamic>{});
        expect(h.name, PiHarness.piCodingAgentUnknown.name);
        expect(h.version, PiHarness.piCodingAgentUnknown.version);
      },
    );

    test('PairError fixture parses', () {
      final file = File(
        '../.orchestration/contracts/fixtures/pair_error.jsonl',
      );
      final line = file.readAsLinesSync().firstWhere(
        (l) => l.trim().isNotEmpty,
      );
      final msg = decodeServer(line) as PairError;
      expect(msg.code, isNotEmpty);
      expect(msg.message, isNotEmpty);
    });

    test('peer_online fixture parses (ControlInbound.tryFromJson)', () {
      final file = File(
        '../.orchestration/contracts/fixtures/peer_online.jsonl',
      );
      final line = file.readAsLinesSync().firstWhere(
        (l) => l.trim().isNotEmpty,
      );
      final m = ControlInbound.tryFromJson(
        jsonDecode(line) as Map<String, dynamic>,
      );
      expect(m, isA<PeerOnline>());
      expect((m! as PeerOnline).peer, isNotEmpty);
    });

    test('peer_offline fixture parses with sinceTs', () {
      final file = File(
        '../.orchestration/contracts/fixtures/peer_offline.jsonl',
      );
      final line = file.readAsLinesSync().firstWhere(
        (l) => l.trim().isNotEmpty,
      );
      final m =
          ControlInbound.tryFromJson(jsonDecode(line) as Map<String, dynamic>)
              as PeerOffline;
      expect(m.sinceTs, 1716234500000);
    });

    test('presence snapshot fixture parses with mixed online/offline', () {
      final file = File('../.orchestration/contracts/fixtures/presence.jsonl');
      final line = file.readAsLinesSync().firstWhere(
        (l) => l.trim().isNotEmpty,
      );
      final m =
          ControlInbound.tryFromJson(jsonDecode(line) as Map<String, dynamic>)
              as PresenceSnapshot;
      expect(m.states, hasLength(2));
      expect(m.states.first.online, isTrue);
      expect(m.states.last.online, isFalse);
      expect(m.states.last.sinceTs, 1716234500000);
    });

    test('subscribe_presence outbound helper', () {
      final j = subscribePresenceFrame(['A', 'B']);
      expect(j['type'], 'subscribe_presence');
      expect(j['peers'], ['A', 'B']);
    });

    test('Bye fixture parses with peer_stop reason', () {
      final file = File('../.orchestration/contracts/fixtures/bye.jsonl');
      final line = file.readAsLinesSync().firstWhere(
        (l) => l.trim().isNotEmpty,
      );
      final msg = decodeServer(line) as Bye;
      expect(msg.reason, ByeReason.peerStop);
      expect(msg.rawReason, 'peer_stop');
    });

    test('Bye unknown reason → ByeReason.unknown but rawReason preserved', () {
      final msg =
          ServerMessage.fromJson({'type': 'bye', 'reason': 'mystery'}) as Bye;
      expect(msg.reason, ByeReason.unknown);
      expect(msg.rawReason, 'mystery');
    });

    test('UserInput fixture parses', () {
      final file = File(
        '../.orchestration/contracts/fixtures/user_input.jsonl',
      );
      final line = file.readAsLinesSync().firstWhere(
        (l) => l.trim().isNotEmpty,
      );
      final msg = decodeServer(line) as UserInput;
      expect(msg.id, isNotEmpty);
      expect(msg.text, 'listar arquivos modificados');
    });

    test(
      'Server-emitted "user_message" is treated as UserInput (Pi rebroadcast '
      'echo — plan/24-fix-app-source-of-truth follow-up)',
      () {
        final msg = decodeServer(
          '{"type":"user_message","id":"cli_42","text":"hello"}',
        );
        expect(msg, isA<UserInput>());
        final ui = msg as UserInput;
        expect(ui.id, 'cli_42');
        expect(ui.text, 'hello');
      },
    );

    test('PairRequest encodes correctly', () {
      final msg = PairRequest(
        id: '018f9c3a-0000-7000-9a3b-1c2d3e4f5a01',
        token: 'qBcD3fG4h5J6k7L8m9N0pQ',
        deviceName: 'iPhone do Jacob',
      );
      final decoded =
          jsonDecode(encodeClient(msg).trim()) as Map<String, dynamic>;
      expect(decoded['type'], 'pair_request');
      expect(decoded['device_name'], 'iPhone do Jacob');
      expect(decoded['token'], 'qBcD3fG4h5J6k7L8m9N0pQ');
      expect(decoded['capabilities'], contains('ask_user_prompt_cards_v2'));
      expect(decoded['capabilities'], isNot(contains('ask_user_prompt_cards')));
    });
  });

  group('encodeClient', () {
    test('UserMessage roundtrip', () {
      final msg = UserMessage(id: 'test-id-1', text: 'hello world');
      final line = encodeClient(msg);
      expect(line, endsWith('\n'));
      final decoded = jsonDecode(line.trim()) as Map<String, dynamic>;
      expect(decoded['type'], 'user_message');
      expect(decoded['id'], 'test-id-1');
      expect(decoded['text'], 'hello world');
      expect(decoded.containsKey('streaming_behavior'), isFalse);
    });

    test('UserMessage with steer behavior includes streaming_behavior', () {
      final msg = UserMessage(
        id: 'test-id-steer',
        text: 'refine this',
        streamingBehavior: UserMessageStreamingBehavior.steer,
      );
      final line = encodeClient(msg);
      final decoded = jsonDecode(line.trim()) as Map<String, dynamic>;
      expect(decoded['streaming_behavior'], 'steer');
    });

    test('ApproveTool encodes decision as string', () {
      final msg = ApproveTool(
        id: 'x',
        toolCallId: 'tc_1',
        decision: ApproveDecision.allow,
      );
      final decoded =
          jsonDecode(encodeClient(msg).trim()) as Map<String, dynamic>;
      expect(decoded['decision'], 'allow');
      expect(decoded['tool_call_id'], 'tc_1');
    });

    test('Ping encodes correctly', () {
      final msg = Ping(id: 'ping-id');
      final decoded =
          jsonDecode(encodeClient(msg).trim()) as Map<String, dynamic>;
      expect(decoded['type'], 'ping');
      expect(decoded['id'], 'ping-id');
    });

    test('Cancel encodes target_id', () {
      final msg = Cancel(id: 'c1', targetId: 'target-x');
      final decoded =
          jsonDecode(encodeClient(msg).trim()) as Map<String, dynamic>;
      expect(decoded['type'], 'cancel');
      expect(decoded['target_id'], 'target-x');
    });

    test('SessionSync advertises v2 ask_user prompt cards only', () {
      final msg = SessionSync(id: 'sync-1');
      final decoded =
          jsonDecode(encodeClient(msg).trim()) as Map<String, dynamic>;
      expect(decoded['type'], 'session_sync');
      expect(decoded['capabilities'], contains('ask_user_prompt_cards_v2'));
      expect(decoded['capabilities'], isNot(contains('ask_user_prompt_cards')));
    });
  });

  // Plan/30 — image attachments on user_message + WireModel.vision.
  group('image attachments (plan 30)', () {
    test('UserMessage without images omits the field (retro-compat)', () {
      final msg = UserMessage(id: 'u1', text: 'hi');
      final decoded =
          jsonDecode(encodeClient(msg).trim()) as Map<String, dynamic>;
      expect(decoded.containsKey('images'), isFalse);
    });

    test('UserMessage with one image encodes an images array', () {
      final msg = UserMessage(
        id: 'u2',
        text: 'look',
        images: const [WireImage(data: 'QUJD', mime: 'image/jpeg')],
      );
      final decoded =
          jsonDecode(encodeClient(msg).trim()) as Map<String, dynamic>;
      final images = decoded['images'] as List<dynamic>;
      expect(images, hasLength(1));
      expect((images.first as Map)['data'], 'QUJD');
      expect((images.first as Map)['mime'], 'image/jpeg');
    });

    test('user_message echo decodes images → UserInput.image', () {
      final msg =
          ServerMessage.fromJson({
                'type': 'user_message',
                'id': 'u3',
                'text': 'caption',
                'images': [
                  {'data': 'QUJD', 'mime': 'image/jpeg'},
                ],
              })
              as UserInput;
      expect(msg.image, isNotNull);
      expect(msg.image!.data, 'QUJD');
      expect(msg.image!.mime, 'image/jpeg');
    });

    test('user_message echo with steer behavior parses on UserInput', () {
      final msg =
          ServerMessage.fromJson({
                'type': 'user_message',
                'id': 'u-steer',
                'text': 'refine',
                'streaming_behavior': 'steer',
              })
              as UserInput;
      expect(msg.streamingBehavior, UserMessageStreamingBehavior.steer);
    });

    test('unknown streaming_behavior is ignored (compatibility)', () {
      final msg =
          ServerMessage.fromJson({
                'type': 'user_message',
                'id': 'u-unknown',
                'text': 'legacy',
                'streaming_behavior': 'unknown-mode',
              })
              as UserInput;
      expect(msg.streamingBehavior, isNull);
    });

    test('user_message without images → UserInput.image is null', () {
      final msg =
          ServerMessage.fromJson({
                'type': 'user_message',
                'id': 'u4',
                'text': 'plain',
              })
              as UserInput;
      expect(msg.image, isNull);
    });

    test('session_history user_input event carries the image', () {
      final hist =
          ServerMessage.fromJson({
                'type': 'session_history',
                'in_reply_to': 'sync1',
                'session_started_at': 0,
                'eos': true,
                'events': [
                  {
                    'type': 'user_input',
                    'ts': 1,
                    'id': 'u5',
                    'text': 'replayed',
                    'images': [
                      {'data': 'QUJD', 'mime': 'image/jpeg'},
                    ],
                  },
                ],
              })
              as SessionHistory;
      final evt = hist.events.single as UserInputEvt;
      expect(evt.image?.data, 'QUJD');
    });

    test('WireModel.vision roundtrips and defaults to false', () {
      const m = WireModel(
        id: 'claude-opus-4-7',
        name: 'Claude Opus 4.7',
        provider: 'anthropic',
        reasoning: true,
        contextWindow: 200000,
        vision: true,
      );
      final back = WireModel.fromJson(m.toJson());
      expect(back.vision, isTrue);
      expect(back, m);

      final noVision = WireModel.fromJson({
        'id': 'x',
        'name': 'X',
        'provider': 'p',
        'reasoning': false,
        'context_window': 1,
      });
      expect(noVision.vision, isFalse);
    });
  });
}
