import 'dart:async';

import 'package:cockpit/app/core/ui/window_activity_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('focus resumes activity without a restore event', () {
    final activity = WindowActivityController();
    addTearDown(activity.dispose);
    activity
      ..blur()
      ..minimize()
      ..focus();
    expect(activity.isActive, isTrue);
  });

  test('focus and restore coalesce into one active transition', () {
    final activity = WindowActivityController();
    addTearDown(activity.dispose);
    var transitions = 0;
    activity.addListener(() => transitions++);

    activity
      ..blur()
      ..minimize()
      ..focus()
      ..focus()
      ..restore()
      ..restore();

    expect(activity.isActive, isTrue);
    expect(transitions, 2, reason: 'one pause and one coalesced resume');
  });

  test(
    'late observer synchronizes an already inactive native window',
    () async {
      final activity = WindowActivityController();
      addTearDown(activity.dispose);
      final synchronizer = WindowActivitySynchronizer(
        activity: activity,
        readSnapshot: () async =>
            const WindowActivitySnapshot(focused: false, minimized: true),
      );

      await synchronizer.synchronize();

      expect(activity.isActive, isFalse);
    },
  );

  test(
    'native event observed during snapshot wins over stale snapshot',
    () async {
      final activity = WindowActivityController();
      addTearDown(activity.dispose);
      final snapshot = Completer<WindowActivitySnapshot>();
      final synchronizer = WindowActivitySynchronizer(
        activity: activity,
        readSnapshot: () => snapshot.future,
      );

      final initialSync = synchronizer.synchronize();
      synchronizer.blur();
      snapshot.complete(
        const WindowActivitySnapshot(focused: true, minimized: false),
      );
      await initialSync;

      expect(activity.isActive, isFalse);
    },
  );

  testWidgets(
    'essential PTY/RPC-shaped stream stays subscribed while inactive',
    (tester) async {
      final activity = WindowActivityController();
      addTearDown(activity.dispose);
      final stream = StreamController<int>();
      addTearDown(stream.close);
      final received = <int>[];
      var mounts = 0;
      var disposals = 0;

      await tester.pumpWidget(
        WindowActivityBoundary(
          activity: activity,
          child: _EssentialStreamProbe(
            stream: stream.stream,
            onMount: () => mounts++,
            onData: received.add,
            onDispose: () => disposals++,
          ),
        ),
      );
      stream.add(1);
      await tester.pump();

      activity
        ..blur()
        ..minimize();
      await tester.pump();
      stream.add(2);
      await tester.pump();

      activity
        ..focus()
        ..restore();
      await tester.pump();
      stream.add(3);
      await tester.pump();

      expect(received, [1, 2, 3]);
      expect(mounts, 1, reason: 'essential process/stream state stays mounted');
      expect(
        disposals,
        0,
        reason: 'blur/minimize never disposes PTY/RPC wiring',
      );
    },
  );
}

class _EssentialStreamProbe extends StatefulWidget {
  const _EssentialStreamProbe({
    required this.stream,
    required this.onMount,
    required this.onData,
    required this.onDispose,
  });

  final Stream<int> stream;
  final VoidCallback onMount;
  final ValueChanged<int> onData;
  final VoidCallback onDispose;

  @override
  State<_EssentialStreamProbe> createState() => _EssentialStreamProbeState();
}

class _EssentialStreamProbeState extends State<_EssentialStreamProbe> {
  late final StreamSubscription<int> _subscription;

  @override
  void initState() {
    super.initState();
    widget.onMount();
    _subscription = widget.stream.listen(widget.onData);
  }

  @override
  void dispose() {
    _subscription.cancel();
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
