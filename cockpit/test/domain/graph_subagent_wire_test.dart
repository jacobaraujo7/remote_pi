// The app receives this transitive protocol type through cockpit_remote.
// ignore: depend_on_referenced_packages
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'optional metric and own identity fields survive transport and old payloads',
    () {
      const message = TurnStatus(
        paneId: 'own',
        status: 'metric',
        contextTokens: 42,
        contextWindow: 100,
        graphSelfName: 'self',
        graphRecipient: 'peer',
      );
      final decoded = RemoteMessage.fromJson(message.toJson()) as TurnStatus;
      expect(decoded.contextTokens, 42);
      expect(decoded.contextWindow, 100);
      expect(decoded.graphSelfName, 'self');
      expect(decoded.graphRecipient, 'peer');
      final legacy = TurnStatus.fromJson({'pane': 'old', 'st': 'idle'});
      expect(legacy.contextTokens, isNull);
      expect(legacy.graphSelfName, isNull);
    },
  );

  test('remote turn status carries temporary child identity', () {
    const message = TurnStatus(
      paneId: 'tab-main',
      status: 'subagent_start',
      event: 'SubagentStart',
      sid: 'session-main',
      harness: 'codex',
      subagentId: 'child-1',
      subagentType: 'reviewer',
      eventEpochMs: 1780000000000,
    );
    final decoded = RemoteMessage.fromJson(message.toJson()) as TurnStatus;
    expect(decoded.paneId, 'tab-main');
    expect(decoded.subagentId, 'child-1');
    expect(decoded.subagentType, 'reviewer');
    expect(decoded.eventEpochMs, 1780000000000);
  });
}
