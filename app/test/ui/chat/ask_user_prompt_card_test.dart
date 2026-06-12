import 'package:app/domain/session_state.dart';
import 'package:app/ui/chat/widgets/ask_user_prompt_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('AskUserPromptCard', () {
    testWidgets('single-select sends selected option', (tester) async {
      String? gotId;
      List<String>? gotSelections;
      String? gotFreeform;
      String? gotComment;
      bool? gotCancelled;
      await tester.pumpWidget(
        _wrap(
          AskUserPromptCard(
            prompt: const AskUserPromptMsg(
              id: 'p1',
              question: 'Choose',
              context: 'ctx',
              options: [
                AskUserPromptChoice(title: 'A'),
                AskUserPromptChoice(title: 'B'),
              ],
              allowMultiple: false,
              allowFreeform: false,
              allowComment: true,
            ),
            onRespond: (id, selections, freeform, comment, cancelled) {
              gotId = id;
              gotSelections = selections;
              gotFreeform = freeform;
              gotComment = comment;
              gotCancelled = cancelled;
            },
          ),
        ),
      );

      await tester.tap(find.text('A'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'look good');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit selection'));
      await tester.pumpAndSettle();

      expect(gotId, 'p1');
      expect(gotSelections, ['A']);
      expect(gotFreeform, isNull);
      expect(gotComment, 'look good');
      expect(gotCancelled, isFalse);
    });

    testWidgets('option prompt can submit a freeform answer', (tester) async {
      String? gotFreeform;
      await tester.pumpWidget(
        _wrap(
          AskUserPromptCard(
            prompt: const AskUserPromptMsg(
              id: 'p1b',
              question: 'Choose or type',
              context: '',
              options: [AskUserPromptChoice(title: 'A')],
              allowMultiple: false,
              allowFreeform: true,
              allowComment: false,
            ),
            onRespond: (_, _, freeform, _, _) {
              gotFreeform = freeform;
            },
          ),
        ),
      );

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Submit text'), findsNothing);
      await tester.enterText(find.byType(TextField).first, 'Use a custom path');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit text'));
      await tester.pumpAndSettle();

      expect(gotFreeform, 'Use a custom path');
    });

    testWidgets('multi-select sends all chosen options', (tester) async {
      List<String>? gotSelections;
      await tester.pumpWidget(
        _wrap(
          AskUserPromptCard(
            prompt: const AskUserPromptMsg(
              id: 'p2',
              question: 'Pick',
              context: '',
              options: [
                AskUserPromptChoice(title: 'Alpha'),
                AskUserPromptChoice(title: 'Beta'),
              ],
              allowMultiple: true,
              allowFreeform: false,
              allowComment: false,
            ),
            onRespond: (_, selections, _, _, _) {
              gotSelections = selections;
            },
          ),
        ),
      );

      await tester.tap(find.text('Alpha'));
      await tester.tap(find.text('Beta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit selection'));
      await tester.pumpAndSettle();

      expect(gotSelections, hasLength(2));
      expect(gotSelections, containsAll(['Alpha', 'Beta']));
    });

    testWidgets('freeform-only sends text answer', (tester) async {
      String? gotFreeform;
      await tester.pumpWidget(
        _wrap(
          AskUserPromptCard(
            prompt: const AskUserPromptMsg(
              id: 'p3',
              question: 'How?',
              context: '',
              options: [],
              allowMultiple: false,
              allowFreeform: true,
              allowComment: true,
            ),
            onRespond: (_, _, freeform, _, _) {
              gotFreeform = freeform;
            },
          ),
        ),
      );

      await tester.enterText(find.byType(TextField).first, 'Use option B');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit text'));
      await tester.pumpAndSettle();

      expect(gotFreeform, 'Use option B');
    });

    testWidgets('cancel sends cancelled=true', (tester) async {
      bool? gotCancelled;
      await tester.pumpWidget(
        _wrap(
          AskUserPromptCard(
            prompt: const AskUserPromptMsg(
              id: 'p4',
              question: 'Cancel?',
              context: '',
              options: [AskUserPromptChoice(title: 'A')],
              allowMultiple: false,
              allowFreeform: true,
              allowComment: false,
            ),
            onRespond: (_, _, _, _, cancelled) {
              gotCancelled = cancelled;
            },
          ),
        ),
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(gotCancelled, isTrue);
    });

    testWidgets('resolved prompt is read-only', (tester) async {
      var called = false;
      await tester.pumpWidget(
        _wrap(
          AskUserPromptCard(
            prompt: const AskUserPromptMsg(
              id: 'p5',
              question: 'Done',
              context: '',
              options: [AskUserPromptChoice(title: 'A')],
              allowMultiple: false,
              allowFreeform: false,
              allowComment: false,
              resolved: true,
              answerLabel: 'A',
            ),
            onRespond: (_, _, _, _, _) {
              called = true;
            },
          ),
        ),
      );

      expect(find.text('Submit selection'), findsNothing);
      expect(find.text('Cancel'), findsNothing);
      await tester.tap(find.text('A'));
      await tester.pumpAndSettle();
      expect(called, isFalse);
      expect(find.text('Answered'), findsOneWidget);
    });
  });
}
