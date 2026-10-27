import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cockpit/app/cockpit/ui/services/orchestration_live_sessions.dart';

void main() {
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
