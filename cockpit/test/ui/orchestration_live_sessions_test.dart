import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cockpit/app/cockpit/ui/services/orchestration_live_sessions.dart';

void main() {
  test('unchanged session metadata does not rebuild the orchestration', () {
    final parent = ChangeNotifier(), terminal = ChangeNotifier();
    var status = 'idle';
    final live = OrchestrationLiveSessions(
      sources: [parent],
      sessions: () => [terminal],
      sessionState: () => [status],
    );
    var updates = 0;
    live.addListener(() => updates++);
    for (var i = 0; i < 100; i++) {
      terminal.notifyListeners();
    }
    expect(updates, 0);
    status = 'waiting';
    terminal.notifyListeners();
    expect(updates, 1);
    parent.notifyListeners();
    expect(updates, 2);
    live.dispose();
    parent.dispose();
    terminal.dispose();
  });
  test('bursts coalesce and callbacks queued before disposal are harmless', () {
    final parent = ChangeNotifier(), terminal = ChangeNotifier();
    final callbacks = <VoidCallback>[];
    final live = OrchestrationLiveSessions(
      sources: [parent],
      sessions: () => [terminal],
      schedule: callbacks.add,
    );
    var updates = 0;
    live.addListener(() => updates++);
    for (var i = 0; i < 100; i++) {
      parent.notifyListeners();
      terminal.notifyListeners();
    }
    expect(callbacks.length, 1);
    callbacks.removeAt(0)();
    expect(updates, 1);
    parent.notifyListeners();
    live.dispose();
    callbacks.removeAt(0)();
    expect(updates, 1);
    parent.dispose();
    terminal.dispose();
  });
  test(
    'new terminals are observed immediately and removed sessions detach',
    () {
      final parent = ChangeNotifier(),
          first = ChangeNotifier(),
          later = ChangeNotifier();
      var sessions = [first];
      final live = OrchestrationLiveSessions(
        sources: [parent],
        sessions: () => sessions,
      );
      var updates = 0;
      live.addListener(() => updates++);
      first.notifyListeners();
      expect(updates, 1);
      sessions = [first, later];
      parent.notifyListeners();
      later.notifyListeners();
      expect(updates, 3);
      sessions = [later];
      parent.notifyListeners();
      first.notifyListeners();
      expect(updates, 4);
      live.dispose();
      parent.notifyListeners();
      later.notifyListeners();
      expect(updates, 4);
      parent.dispose();
      first.dispose();
      later.dispose();
    },
  );
}
