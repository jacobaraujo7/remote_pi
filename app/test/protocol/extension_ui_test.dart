// Plan/51 — protocol surface for the extension_ui_request bridge (ask_user via
// pi-ask). Mirrors the contract in `pi-extension/src/protocol/types.ts`:
//   ServerMessage: extension_ui_request (select/confirm/input/editor/notify + ask)
//   ClientMessage: extension_ui_response (value/confirmed/cancelled + ask)

import 'package:app/protocol/protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ExtensionUiMethod — wire round-trip', () {
    test('parses each known method', () {
      const expected = [
        ('select', ExtensionUiMethod.select),
        ('confirm', ExtensionUiMethod.confirm),
        ('input', ExtensionUiMethod.input),
        ('editor', ExtensionUiMethod.editor),
        ('notify', ExtensionUiMethod.notify),
      ];
      for (final (wire, method) in expected) {
        expect(ExtensionUiMethod.fromWire(wire), method);
        expect(method.wire, wire);
      }
    });

    test('unknown method returns null (forward-compat)', () {
      expect(ExtensionUiMethod.fromWire('future'), isNull);
    });
  });

  group('AskQuestionWireType — wire round-trip', () {
    test('parses single/multi/preview', () {
      expect(AskQuestionWireType.fromWire('single'), AskQuestionWireType.single);
      expect(AskQuestionWireType.fromWire('multi'), AskQuestionWireType.multi);
      expect(
        AskQuestionWireType.fromWire('preview'),
        AskQuestionWireType.preview,
      );
    });

    test('unknown returns null', () {
      expect(AskQuestionWireType.fromWire('ranked'), isNull);
    });
  });

  group('ServerMessage — extension_ui_request', () {
    test('select with ask envelope parses questions + options', () {
      final m = ServerMessage.fromJson({
        'type': 'extension_ui_request',
        'id': 'tool:tc_1',
        'method': 'select',
        'title': 'Direction',
        'options': ['Alpha', 'Beta'],
        'ask': {
          'flow_id': 'tool:tc_1',
          'tool_call_id': 'tc_1',
          'source': 'tool',
          'title': 'Direction',
          'questions': [
            {
              'id': 'goal',
              'label': 'Goal',
              'prompt': "What's the goal?",
              'type': 'single',
              'required': true,
              'options': [
                {'value': 'a', 'label': 'Alpha'},
                {'value': 'b', 'label': 'Beta', 'description': 'second'},
              ],
            },
          ],
        },
      });
      final req = m as ExtensionUiRequest;
      expect(req.id, 'tool:tc_1');
      expect(req.method, ExtensionUiMethod.select);
      expect(req.title, 'Direction');
      expect(req.options, ['Alpha', 'Beta']);
      expect(req.ask, isNotNull);
      expect(req.ask!.flowId, 'tool:tc_1');
      expect(req.ask!.toolCallId, 'tc_1');
      expect(req.ask!.questions, hasLength(1));
      final q = req.ask!.questions.first;
      expect(q.id, 'goal');
      expect(q.type, AskQuestionWireType.single);
      expect(q.required, isTrue);
      expect(q.options.map((o) => o.value), ['a', 'b']);
      expect(q.options.last.description, 'second');
    });

    test('notify parses message', () {
      final m = ServerMessage.fromJson({
        'type': 'extension_ui_request',
        'id': 'completed:f1',
        'method': 'notify',
        'message': 'Clarification resolved.',
      });
      final req = m as ExtensionUiRequest;
      expect(req.method, ExtensionUiMethod.notify);
      expect(req.message, 'Clarification resolved.');
      expect(req.ask, isNull);
    });

    test('select without ask envelope still parses (degraded client)', () {
      final m = ServerMessage.fromJson({
        'type': 'extension_ui_request',
        'id': 'r1',
        'method': 'select',
        'title': 'Pick',
        'options': ['One', 'Two'],
      });
      final req = m as ExtensionUiRequest;
      expect(req.options, ['One', 'Two']);
      expect(req.ask, isNull);
    });

    test('unknown method falls back to select (lenient)', () {
      final m = ServerMessage.fromJson({
        'type': 'extension_ui_request',
        'id': 'r2',
        'method': 'future_method',
      });
      expect((m as ExtensionUiRequest).method, ExtensionUiMethod.select);
    });
  });

  group('ClientMessage — extension_ui_response', () {
    test('value encodes value only', () {
      expect(
        ExtensionUiResponse(id: 'r1', value: 'Alpha').toJson(),
        {'type': 'extension_ui_response', 'id': 'r1', 'value': 'Alpha'},
      );
    });

    test('confirmed encodes confirmed bool', () {
      expect(
        ExtensionUiResponse(id: 'r2', confirmed: true).toJson(),
        {'type': 'extension_ui_response', 'id': 'r2', 'confirmed': true},
      );
    });

    test('cancelled encodes cancelled true', () {
      expect(
        ExtensionUiResponse(id: 'r3', cancelled: true).toJson(),
        {'type': 'extension_ui_response', 'id': 'r3', 'cancelled': true},
      );
    });

    test('ask answer envelope carries structured answers', () {
      final j = ExtensionUiResponse(
        id: 'tool:tc_1',
        value: 'Alpha',
        ask: AskResponseEnrichmentWire(
          flowId: 'tool:tc_1',
          mode: 'submit',
          answers: {'goal': AskAnswerWire(values: ['a'])},
        ),
      ).toJson();
      expect(j, {
        'type': 'extension_ui_response',
        'id': 'tool:tc_1',
        'value': 'Alpha',
        'ask': {
          'flow_id': 'tool:tc_1',
          'kind': 'answer',
          'mode': 'submit',
          'answers': {
            'goal': {'values': ['a']},
          },
        },
      });
    });

    test('ask cancel envelope', () {
      final j = ExtensionUiResponse(
        id: 'tool:tc_1',
        cancelled: true,
        ask: AskResponseEnrichmentWire(flowId: 'tool:tc_1', isCancel: true),
      ).toJson();
      expect(j, {
        'type': 'extension_ui_response',
        'id': 'tool:tc_1',
        'cancelled': true,
        'ask': {'flow_id': 'tool:tc_1', 'kind': 'cancel'},
      });
    });
  });
}
