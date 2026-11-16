import 'package:cockpit/app/cockpit/domain/entities/board_document.dart';
import 'package:cockpit/app/cockpit/domain/entities/file_view.dart';
import 'package:cockpit/app/cockpit/ui/session/file_viewer_session.dart';
import 'package:cockpit/app/cockpit/ui/widgets/board_view.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/overlay/app_popover_handler.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  for (final width in [280.0, 420.0]) {
    testWidgets('split pane at $width exposes color, click-to-move and zoom', (
      tester,
    ) async {
      final document = BoardDocument([
        const BoardItem('a', BoardKind.process, 10, 10, width: 60, height: 40),
        const BoardItem('b', BoardKind.decision, 90, 10),
        const BoardItem('edge', BoardKind.arrow, 0, 0, from: 'a', to: 'b'),
      ]);
      final session = FileViewerSession(
        id: 'compact',
        projectId: 'test',
        path: 'compact.board',
        view: FileViewText(document.encode()),
      );
      addTearDown(session.dispose);
      BoardDocument saved() =>
          BoardDocument.parse((session.view as FileViewText).text);
      await tester.pumpWidget(
        TranslationProvider(
          child: ShadcnApp(
            popoverHandler: const AppPopoverOverlayHandler(),
            theme: buildTheme(brightness: Brightness.dark),
            home: Scaffold(
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  height: 480,
                  child: BoardView(
                    session: session,
                    onSave: (text) async {
                      session.adoptDisk(FileViewText(text));
                      return true;
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final origin = tester.getTopLeft(find.byType(material.InteractiveViewer));
      await tester.tapAt(origin + const Offset(40, 30));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Diagram color'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Green'));
      await tester.pumpAndSettle();
      expect(saved().items['a']!.color, '#64CBA7');
      final move = find.byTooltip('Move here');
      await tester.ensureVisible(move);
      await tester.tap(move);
      await tester.pumpAndSettle();
      expect(find.textContaining('Click where to place'), findsOneWidget);
      await tester.tapAt(origin + const Offset(120, 150));
      await tester.pumpAndSettle();
      expect(saved().items['a']!.x, 90);
      expect(saved().items['a']!.y, 130);
      expect(saved().items['edge']!.from, 'a');
      final zoom = find.byTooltip('Zoom In');
      await tester.ensureVisible(zoom);
      await tester.tap(zoom);
      await tester.pumpAndSettle();
      expect(find.text('120%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
