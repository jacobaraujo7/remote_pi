import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:cockpit/app/cockpit/ui/services/agent_role_suggestion_service.dart';

void main() {
  test('replies must match the request; partial writes are ignored', () {
    expect(AgentRoleSuggestionService.parseReply('{', 'one'), isNull);
    expect(
      AgentRoleSuggestionService.parseReply(
        '{"requestId":"old","role":"wrong"}',
        'one',
      ),
      isNull,
    );
    expect(
      AgentRoleSuggestionService.parseReply(
        '{"requestId":"one","role":" Review API "}',
        'one',
      ),
      'Review API',
    );
    expect(
      () => AgentRoleSuggestionService.parseReply(
        '{"requestId":"one","role":42}',
        'one',
      ),
      throwsA(AgentRoleSuggestionFailure.invalid),
    );
  });
  test('concurrent requests query once and return only a draft', () async {
    final service = AgentRoleSuggestionService();
    var prepared = 0, sent = 0, disposed = 0, reads = 0;
    Future<String> request() => service.request(
      key: 'worktree/document/box',
      requestId: 'one',
      language: 'pt',
      isCurrent: () => true,
      interval: Duration.zero,
      attempts: 3,
      prepare: () async {
        prepared++;
        return AgentRoleSuggestionChannel(
          path: '/tmp/response.json',
          send: (prompt) async {
            sent++;
            expect(prompt, contains('current session context'));
          },
          read: () async => ++reads == 1
              ? '{'
              : jsonEncode({'requestId': 'one', 'role': 'Revisar API'}),
          dispose: () async {
            disposed++;
          },
        );
      },
    );
    expect(await Future.wait([request(), request()]), [
      'Revisar API',
      'Revisar API',
    ]);
    expect(prepared, 1);
    expect(sent, 1);
    expect(disposed, 1);
    expect(await request(), 'Revisar API');
    expect(sent, 2);
  });
  test(
    'changed terminal/document rejects a late reply and cleans up',
    () async {
      var current = true, disposed = false;
      final result = AgentRoleSuggestionService().request(
        key: 'box',
        requestId: 'id',
        language: 'en',
        isCurrent: () => current,
        interval: Duration.zero,
        prepare: () async => AgentRoleSuggestionChannel(
          path: '/tmp/reply',
          send: (_) async {},
          read: () async {
            current = false;
            return '{"requestId":"id","role":"wrong workspace"}';
          },
          dispose: () async {
            disposed = true;
          },
        ),
      );
      await expectLater(result, throwsA(AgentRoleSuggestionFailure.changed));
      expect(disposed, isTrue);
    },
  );
  test('no reply times out without changing a box', () async {
    final result = AgentRoleSuggestionService().request(
      key: 'box',
      requestId: 'id',
      language: 'en',
      isCurrent: () => true,
      interval: Duration.zero,
      attempts: 2,
      prepare: () async => AgentRoleSuggestionChannel(
        path: '/tmp/reply',
        send: (_) async {},
        read: () async => '{}',
        dispose: () async {},
      ),
    );
    await expectLater(result, throwsA(AgentRoleSuggestionFailure.timeout));
  });
}
