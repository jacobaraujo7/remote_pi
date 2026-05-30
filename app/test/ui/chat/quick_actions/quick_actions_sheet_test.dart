// Plan/28 Wave C — Quick Actions bottom sheet widget tests.
//
// These drive the REAL `QuickActionsSheetBody` (not a replica harness) so
// the close-on-success, success/error toast, and `session_new` reset wiring
// are actually exercised. The ViewModel is built with a fake
// `IActionsRepository` so we don't spin up the DI graph or a live channel.

import 'package:app/data/actions/actions_repository.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/ui/chat/quick_actions/states/quick_actions_state.dart';
import 'package:app/ui/chat/quick_actions/viewmodels/quick_actions_viewmodel.dart';
import 'package:app/ui/chat/quick_actions/widgets/quick_actions_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _FakeRepo implements IActionsRepository {
  int compactCalls = 0;
  int newSessionCalls = 0;
  ThinkingLevel? thinking;
  WireModel? modelArg;

  /// When set, the matching action throws [ActionFailure] to exercise the
  /// failure path (error toast + sheet stays open).
  bool failCompact = false;
  bool failNewSession = false;

  @override
  ActiveRoomMeta get activeRoomMeta => const ActiveRoomMeta();

  @override
  Stream<ActiveRoomMeta> get activeRoomMetaStream =>
      const Stream<ActiveRoomMeta>.empty();

  @override
  Future<void> compact() async {
    compactCalls++;
    if (failCompact) throw const ActionFailure('compact boom');
  }

  @override
  Future<void> newSession() async {
    newSessionCalls++;
    if (failNewSession) throw const ActionFailure('new boom');
  }

  @override
  Future<void> setModel(String provider, String modelId) async {
    modelArg = WireModel(
      id: modelId,
      provider: provider,
      name: modelId,
      reasoning: false,
      contextWindow: 0,
    );
  }

  @override
  Future<void> setThinking(ThinkingLevel level) async {
    thinking = level;
  }

  @override
  Future<ModelsCatalogue> listModels({bool forceRefresh = false}) async {
    return const ModelsCatalogue(models: [], current: null);
  }

  @override
  void dispose() {}
}

/// Opens the real sheet body over a host Scaffold. Returns the fake repo and
/// a list appended to by the `onSessionReset` callback.
Future<({_FakeRepo repo, List<int> resetCalls})> _openSheet(
  WidgetTester tester, {
  bool failCompact = false,
  bool failNewSession = false,
}) async {
  final repo = _FakeRepo()
    ..failCompact = failCompact
    ..failNewSession = failNewSession;
  final vm = QuickActionsViewModel(repo);
  final resetCalls = <int>[];

  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (ctx) => ElevatedButton(
          onPressed: () {
            final messenger = ScaffoldMessenger.of(ctx);
            showModalBottomSheet<void>(
              context: ctx,
              // Mirror the production entry point so the full body has room
              // (otherwise the Column overflows the half-height default).
              isScrollControlled: true,
              builder: (_) =>
                  ChangeNotifierProvider<QuickActionsViewModel>.value(
                value: vm,
                child: QuickActionsSheetBody(
                  messenger: messenger,
                  onSessionReset: () async => resetCalls.add(1),
                ),
              ),
            );
          },
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return (repo: repo, resetCalls: resetCalls);
}

void main() {
  testWidgets('Compact: tap sends, closes the sheet, toasts success',
      (tester) async {
    final s = await _openSheet(tester);
    await tester.tap(find.byKey(const Key('qa-compact')));
    await tester.pumpAndSettle();

    expect(s.repo.compactCalls, 1);
    // Sheet dismissed on success.
    expect(find.byKey(const Key('qa-compact')), findsNothing);
    // Success toast surfaced via the host messenger.
    expect(find.text('Context compacted'), findsOneWidget);
  });

  testWidgets('Compact: failure keeps the sheet open and toasts the error',
      (tester) async {
    final s = await _openSheet(tester, failCompact: true);
    await tester.tap(find.byKey(const Key('qa-compact')));
    await tester.pumpAndSettle();

    expect(s.repo.compactCalls, 1);
    // Sheet stays open so the user can retry.
    expect(find.byKey(const Key('qa-compact')), findsOneWidget);
    expect(find.text('compact boom'), findsOneWidget);
    expect(find.text('Context compacted'), findsNothing);
  });

  testWidgets('New session: confirm fires, resets chat, closes, toasts',
      (tester) async {
    final s = await _openSheet(tester);
    await tester.tap(find.byKey(const Key('qa-new-session')));
    await tester.pumpAndSettle();
    // Confirmation dialog up.
    expect(find.text('Start a new session?'), findsOneWidget);
    await tester.tap(find.text('Start new'));
    await tester.pumpAndSettle();

    expect(s.repo.newSessionCalls, 1);
    // Local chat mirror reset requested exactly once.
    expect(s.resetCalls.length, 1);
    // Sheet dismissed + success toast.
    expect(find.byKey(const Key('qa-new-session')), findsNothing);
    expect(find.text('New session started'), findsOneWidget);
  });

  testWidgets('New session: cancel fires nothing and keeps the sheet',
      (tester) async {
    final s = await _openSheet(tester);
    await tester.tap(find.byKey(const Key('qa-new-session')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(s.repo.newSessionCalls, 0);
    expect(s.resetCalls, isEmpty);
    // Sheet still open.
    expect(find.byKey(const Key('qa-new-session')), findsOneWidget);
  });

  testWidgets('New session: failure keeps sheet open and does not reset chat',
      (tester) async {
    final s = await _openSheet(tester, failNewSession: true);
    await tester.tap(find.byKey(const Key('qa-new-session')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start new'));
    await tester.pumpAndSettle();

    expect(s.repo.newSessionCalls, 1);
    // Reset must NOT run when the Pi rejects the new session.
    expect(s.resetCalls, isEmpty);
    expect(find.byKey(const Key('qa-new-session')), findsOneWidget);
    expect(find.text('new boom'), findsOneWidget);
  });

  testWidgets('thinking segment forwards level to repo', (tester) async {
    final s = await _openSheet(tester);
    await tester.tap(find.byKey(const Key('qa-thinking-medium')));
    await tester.pumpAndSettle();
    expect(s.repo.thinking, ThinkingLevel.medium);
  });

  test('QuickActionsState equality covers idle + busy', () {
    expect(const QuickActionsIdle(), const QuickActionsIdle());
    expect(
      const QuickActionsIdle(currentThinking: ThinkingLevel.low),
      const QuickActionsIdle(currentThinking: ThinkingLevel.low),
    );
    expect(
      const QuickActionsBusy(action: ActionName.modelSet),
      const QuickActionsBusy(action: ActionName.modelSet),
    );
  });
}
