import 'dart:ui' show PointerDeviceKind;
import 'package:cockpit/app/cockpit/domain/entities/board_document.dart';
import 'package:cockpit/app/cockpit/domain/entities/file_view.dart';
import 'package:cockpit/app/cockpit/ui/session/file_viewer_session.dart';
import 'package:cockpit/app/cockpit/ui/widgets/board_view.dart';
import 'package:cockpit/app/core/ui/overlay/app_popover_handler.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  testWidgets(
    'secondary click from pencil, keyboard menu, stale target and background',
    (tester) async {
      final doc = BoardDocument([
        const BoardItem('a', BoardKind.process, 20, 30, label: 'Receive'),
        const BoardItem('b', BoardKind.process, 220, 30, label: 'Approve'),
      ], id: 'review');
      final session = FileViewerSession(
        id: 'menu',
        projectId: 'test',
        path: 'review.canvas',
        view: FileViewText(doc.encode()),
      );
      addTearDown(session.dispose);
      var saves = 0;
      BoardDocument saved() =>
          BoardDocument.parse((session.view as FileViewText).text);
      await tester.pumpWidget(
        TranslationProvider(
          child: ShadcnApp(
            theme: buildTheme(brightness: Brightness.dark),
            popoverHandler: const AppPopoverOverlayHandler(),
            home: Scaffold(
              child: BoardView(
                session: session,
                onSave: (text) async {
                  saves++;
                  session.adoptDisk(FileViewText(text));
                  return true;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final origin = tester.getTopLeft(find.byType(material.InteractiveViewer));
      Future<void> right(Offset point) async {
        await tester.tapAt(
          origin + point,
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
      }

      Future<void> choose(String name) async {
        await tester.tap(find.text(name).last);
        await tester.pumpAndSettle();
      }

      await tester.tap(find.byTooltip('Pencil'));
      await right(const Offset(60, 60));
      expect(saves, 0);
      await choose('Line width');
      await choose('4');
      expect(saved().items['a']!.strokeWidth, 4);
      expect(saved().items.length, 2);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.f10);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      await choose('Bring to front');
      expect(saved().paintOrder.last.id, 'a');
      await right(const Offset(60, 60));
      session.adoptDisk(
        FileViewText(
          BoardDocument([
            saved().items['a']!.edited(label: 'Edited elsewhere'),
            saved().items['b']!,
          ], id: doc.id).encode(),
        ),
      );
      await tester.pumpAndSettle();
      await choose('Delete');
      expect(saved().items['a']!.label, 'Edited elsewhere');
      expect(saves, 2);
      await right(const Offset(450, 300));
      expect(find.text('Bring to front'), findsNothing);
      expect(saves, 2);
      await tester.tap(find.byTooltip('Select'));
      await tester.tapAt(origin + const Offset(60, 60));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tapAt(origin + const Offset(250, 60));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await right(const Offset(60, 60));
      await choose('Group');
      final group = saved().items['a']!.group;
      expect(group, isNotNull);
      expect(saved().items['b']!.group, group);
      await right(const Offset(250, 60));
      await choose('Diagram color');
      await choose('Green');
      expect(saved().items.values.every((i) => i.color == '#64CBA7'), isTrue);
      await right(const Offset(250, 60));
      await choose('Ungroup');
      expect(saved().items.values.every((i) => i.group == null), isTrue);
      await right(const Offset(250, 60));
      await choose('Delete');
      expect(saved().items, isEmpty);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(saved().items.keys, ['a', 'b']);
    },
  );
}
