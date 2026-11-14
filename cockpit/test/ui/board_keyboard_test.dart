import 'package:cockpit/app/cockpit/domain/entities/board_document.dart';
import 'package:cockpit/app/cockpit/domain/entities/file_view.dart';
import 'package:cockpit/app/cockpit/ui/session/file_viewer_session.dart';
import 'package:cockpit/app/cockpit/ui/widgets/board_view.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  testWidgets(
    'traverse, nudge and connect distinct overlapping shapes by keyboard',
    (tester) async {
      final board = BoardDocument([
        const BoardItem('a', BoardKind.process, 20, 25, label: 'Receive'),
        const BoardItem('b', BoardKind.decision, 240, 25, label: 'Approve?'),
        const BoardItem('c', BoardKind.process, 240, 25, label: 'Archive'),
      ]);
      final session = FileViewerSession(
        id: 'keyboard',
        projectId: 'test',
        path: 'keyboard.board',
        view: FileViewText(board.encode()),
      );
      addTearDown(session.dispose);
      BoardDocument saved() =>
          BoardDocument.parse((session.view as FileViewText).text);
      await tester.pumpWidget(
        TranslationProvider(
          child: ShadcnApp(
            theme: buildTheme(brightness: Brightness.dark),
            home: Scaffold(
              child: BoardView(
                session: session,
                onReload: () async {},
                onSave: (text) async {
                  session.adoptDisk(FileViewText(text));
                  return true;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> press(LogicalKeyboardKey key, {bool shift = false}) async {
        if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(key);
        if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pumpAndSettle();
      }

      final receive = find.semantics.byLabel('Process · Receive');
      expect(receive, findsOne);
      await press(LogicalKeyboardKey.tab);
      expect(receive, isSemantics(isSelected: true));
      await press(LogicalKeyboardKey.arrowRight);
      await press(LogicalKeyboardKey.arrowDown, shift: true);
      expect(saved().items['a']!.x, 21);
      expect(saved().items['a']!.y, 35);
      await press(LogicalKeyboardKey.tab);
      expect(
        find.semantics.byLabel('Decision · Approve?'),
        isSemantics(isSelected: true),
      );
      await press(LogicalKeyboardKey.tab, shift: true);
      await press(LogicalKeyboardKey.keyC);
      expect(
        find.textContaining('Destination: Decision · Approve?'),
        findsOneWidget,
      );
      await press(LogicalKeyboardKey.tab);
      expect(
        find.textContaining('Destination: Process · Archive'),
        findsOneWidget,
      );
      await press(LogicalKeyboardKey.escape);
      expect(saved().items.length, 3);
      await press(LogicalKeyboardKey.keyC);
      await press(LogicalKeyboardKey.enter);
      final arrow = saved().items.values.last;
      expect(arrow.kind, BoardKind.arrow);
      expect(arrow.from, 'a');
      expect(arrow.to, 'b');
      expect(
        find.semantics.byLabel(
          'Connector · From Process · Receive to Decision · Approve?',
        ),
        findsOne,
      );
      tester.semantics.tap(find.semantics.byLabel('Process · Archive'));
      await tester.pumpAndSettle();
      expect(
        find.semantics.byLabel('Process · Archive'),
        isSemantics(isSelected: true, hasLongPressAction: true),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
