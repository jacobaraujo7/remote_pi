// Plan/51 — ExtensionUiSheet behavior around submit enablement, rejection
// retry, and system back. Covers the riskiest interactive logic of the
// ask_user modal (the protocol surface is covered by
// test/protocol/extension_ui_test.dart).

import 'package:app/protocol/protocol.dart';
import 'package:app/ui/chat/widgets/extension_ui_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ExtensionUiRequest _richRequest({String id = 'tool:tc_1'}) =>
    ExtensionUiRequest(
      id: id,
      method: ExtensionUiMethod.select,
      title: 'Direction',
      options: const ['Alpha', 'Beta'],
      ask: AskEnrichmentWire(
        flowId: id,
        toolCallId: 'tc_1',
        source: 'tool',
        title: 'Direction',
        questions: const [
          AskQuestionWire(
            id: 'goal',
            label: 'Goal',
            prompt: "What's the goal?",
            type: AskQuestionWireType.single,
            required: true,
            options: [
              AskOptionWire(value: 'a', label: 'Alpha'),
              AskOptionWire(value: 'b', label: 'Beta'),
            ],
          ),
        ],
      ),
    );

ExtensionUiRequest _degradedInput() => const ExtensionUiRequest(
  id: 'flow:input',
  method: ExtensionUiMethod.input,
  title: 'Describe',
  placeholder: 'Describe the goal',
);

void main() {
  Future<void> pumpSheet(
    WidgetTester tester, {
    required ExtensionUiRequest request,
    String? error,
    Future<void> Function(ExtensionUiResponse)? onRespond,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: ExtensionUiSheet(
          key: ValueKey(request.id),
          request: request,
          error: error,
          onRespond: onRespond ?? (_) async {},
        ),
      ),
    );
  }

  Finder submitButton() => find.widgetWithText(FilledButton, 'Submit');

  bool submitEnabled(WidgetTester tester) =>
      tester.widget<FilledButton>(submitButton()).onPressed != null;

  testWidgets('typing custom text alone enables Submit (rich flow)', (
    tester,
  ) async {
    await pumpSheet(tester, request: _richRequest());
    expect(submitEnabled(tester), isFalse, reason: 'nothing answered yet');

    await tester.enterText(find.byType(TextField).first, 'my own answer');
    await tester.pump();

    expect(
      submitEnabled(tester),
      isTrue,
      reason: 'custom text counts as an answer without any option selected',
    );
  });

  testWidgets('typing enables Submit on the degraded input method', (
    tester,
  ) async {
    await pumpSheet(tester, request: _degradedInput());
    expect(submitEnabled(tester), isFalse);

    await tester.enterText(find.byType(TextField), 'free text');
    await tester.pump();

    expect(submitEnabled(tester), isTrue);
  });

  testWidgets('selecting an option enables Submit and submit sends answers', (
    tester,
  ) async {
    final sent = <ExtensionUiResponse>[];
    await pumpSheet(
      tester,
      request: _richRequest(),
      onRespond: (r) async => sent.add(r),
    );

    await tester.tap(find.text('Beta'));
    await tester.pump();
    expect(submitEnabled(tester), isTrue);

    await tester.tap(submitButton());
    await tester.pump();

    expect(sent, hasLength(1));
    final ask = sent.single.ask!;
    expect(ask.flowId, 'tool:tc_1');
    expect(ask.isCancel, isFalse);
    expect(ask.answers['goal']!.values, ['b']);
    // Modal does NOT close optimistically: it spins until completed/error.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets(
    'rejection stops the spinner for retry; clearing the error mid-retry '
    'does not un-spin the in-flight submit',
    (tester) async {
      final sent = <ExtensionUiResponse>[];
      Future<void> onRespond(ExtensionUiResponse r) async => sent.add(r);

      await pumpSheet(tester, request: _richRequest(), onRespond: onRespond);
      await tester.tap(find.text('Alpha'));
      await tester.pump();
      await tester.tap(submitButton());
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // pi-ask rejected → error arrives → spinner off, message shown.
      await pumpSheet(
        tester,
        request: _richRequest(),
        error: 'Unknown option value.',
        onRespond: onRespond,
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Unknown option value.'), findsOneWidget);
      expect(submitEnabled(tester), isTrue, reason: 'retry possible');

      // Retry → viewmodel clears the error (non-null → null). The submit is
      // in flight again; the cleared error must NOT reset the spinner (that
      // would re-enable the buttons and allow a double submit).
      await tester.tap(submitButton());
      await tester.pump();
      await pumpSheet(tester, request: _richRequest(), onRespond: onRespond);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(sent, hasLength(2));
    },
  );

  testWidgets('system back cancels the flow instead of popping the route', (
    tester,
  ) async {
    final sent = <ExtensionUiResponse>[];
    await pumpSheet(
      tester,
      request: _richRequest(),
      onRespond: (r) async => sent.add(r),
    );

    final popped = await tester.binding.handlePopRoute();
    await tester.pump();

    expect(popped, isTrue, reason: 'PopScope intercepted the back gesture');
    expect(sent, hasLength(1));
    expect(sent.single.cancelled, isTrue);
    expect(sent.single.ask?.isCancel, isTrue);
  });

  testWidgets('required question renders the advisory chip', (tester) async {
    await pumpSheet(tester, request: _richRequest());
    expect(find.text('required'), findsOneWidget);
  });
}
