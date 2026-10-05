import 'package:cockpit/app/cockpit/domain/contracts/notifier.dart';
import 'package:cockpit/app/cockpit/ui/session/pane_item.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/session_notifications_controller.dart';
import 'package:cockpit/app/core/domain/entities/sound_event.dart';
import 'package:cockpit/app/core/ui/window_activity_controller.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePane extends PaneItem {
  _FakePane(this.id);

  @override
  final String id;
  @override
  String get projectId => 'workspace';
  @override
  String get title => id;
  @override
  String get workingDirectory => '';

  bool _unseen = false;
  @override
  bool get unseenFinish => _unseen;
  @override
  void markUnseen() {
    if (_unseen) return;
    _unseen = true;
    notifyListeners();
  }
}

class _FakeNotifier implements Notifier {
  int finished = 0;
  int played = 0;

  @override
  Future<void> init() async {}

  @override
  Future<void> agentFinished({
    required String agentName,
    required String workspace,
  }) async {
    finished++;
  }

  @override
  Future<void> agentNeedsAction({
    required String agentName,
    required String workspace,
  }) async {}

  @override
  Future<void> play(
    SoundEvent event, {
    String? customPath,
    double volume = 50,
  }) async {
    played++;
  }
}

void main() {
  test('multiple completions only notify when a badge changes', () async {
    final activity = WindowActivityController();
    final notifier = _FakeNotifier();
    final controller = SessionNotificationsController(notifier, activity)
      ..focusedTabId = () => 'focused';
    final tabs = List.generate(8, (i) => _FakePane('tab-$i'));
    var changes = 0;
    controller.addListener(() => changes++);

    await Future.wait(tabs.map(controller.turnFinished));
    expect(changes, 8);
    expect(tabs.every((t) => t.unseenFinish), isTrue);

    await Future.wait(tabs.map(controller.turnFinished));
    expect(changes, 8);
    controller.dispose();
    activity.dispose();
    for (final tab in tabs) {
      tab.dispose();
    }
  });

  test('window activity routes completion to OS or in-app sound', () async {
    final activity = WindowActivityController()..blur();
    final notifier = _FakeNotifier();
    final controller = SessionNotificationsController(notifier, activity)
      ..focusedTabId = () => 'focused';
    controller.workspaceName = (_) => 'Workspace';
    final tab = _FakePane('tab');

    await controller.turnFinished(tab);
    expect(notifier.finished, 1);
    expect(notifier.played, 0);

    activity.focus();
    await controller.turnFinished(tab);
    expect(notifier.finished, 1);
    expect(notifier.played, 1);
    controller.dispose();
    activity.dispose();
    tab.dispose();
  });
}
