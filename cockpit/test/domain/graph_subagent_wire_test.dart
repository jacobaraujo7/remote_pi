// The app receives this transitive protocol type through cockpit_remote.
// ignore: depend_on_referenced_packages
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
