// Plan 58 — notification tests (Notifier abstraction).
import 'package:app/domain/contracts/notifier.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeNotifier implements Notifier {
  int agentFinishedCalls = 0;
  String? lastAgentName;
  String? lastWorkspace;

  @override
  Future<void> init() async {}

  @override
  Future<bool?> hasPermission() async => true;

  @override
  Future<void> agentFinished({
    required String agentName,
    required String workspace,
  }) async {
    agentFinishedCalls++;
    lastAgentName = agentName;
    lastWorkspace = workspace;
  }
}

void main() {
  group('Notifier (abstraction)', () {
    test('agentFinished is called with correct params', () async {
      final notifier = FakeNotifier();
      await notifier.agentFinished(
        agentName: 'Lootia',
        workspace: '/home/lootia',
      );
      expect(notifier.agentFinishedCalls, 1);
      expect(notifier.lastAgentName, 'Lootia');
      expect(notifier.lastWorkspace, '/home/lootia');
    });

    test('agentFinished with empty workspace', () async {
      final notifier = FakeNotifier();
      await notifier.agentFinished(agentName: 'Agent', workspace: '');
      expect(notifier.agentFinishedCalls, 1);
      expect(notifier.lastWorkspace, '');
    });
  });
}
