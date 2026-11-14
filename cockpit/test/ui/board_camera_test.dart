import 'dart:ui' show PointerDeviceKind;
import 'package:cockpit/app/cockpit/domain/entities/board_document.dart';
import 'package:cockpit/app/cockpit/domain/entities/file_view.dart';
import 'package:cockpit/app/cockpit/ui/session/file_viewer_session.dart';
import 'package:cockpit/app/cockpit/ui/widgets/board_view.dart';
import 'package:cockpit/app/cockpit/ui/widgets/board_painter.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter/material.dart' as m;
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  testWidgets(
    'fit document and selection preserve negative and distant positions',
    (tester) async {
      const left = BoardItem(
        'left',
        BoardKind.process,
        -150,
        -40,
        width: 500,
        height: 200,
      );
      const right = BoardItem(
        'right',
        BoardKind.decision,
        6500,
        400,
        width: 500,
        height: 200,
      );
      final board = BoardDocument([
        left,
        right,
        const BoardItem(
          'edge',
          BoardKind.arrow,
          0,
          0,
          from: 'left',
          to: 'right',
        ),
      ]);
      final session = FileViewerSession(
        id: 'camera',
        projectId: 'test',
        path: 'camera.board',
        view: FileViewText(board.encode()),
      );
      addTearDown(session.dispose);
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
      final canvas = find.byType(m.InteractiveViewer);
      final camera = tester
          .widget<m.InteractiveViewer>(canvas)
          .transformationController!;
      final size = tester.getSize(canvas), origin = tester.getTopLeft(canvas);
      final box = Offset.zero & size;
      Set<String> painted() => tester
          .widgetList<m.CustomPaint>(find.byType(m.CustomPaint))
          .map((paint) => paint.painter)
          .whereType<BoardPainter>()
          .expand((paint) => paint.items.map((item) => item.id))
          .toSet();
      expect(painted(), contains(left.id));
      expect(painted(), isNot(contains(right.id)));
      Offset mapped(Offset scene) => m.MatrixUtils.transformPoint(
        camera.value,
        scene + const Offset(150, 40),
      );
      await tester.tap(find.byTooltip('Fit document'));
      await tester.pumpAndSettle();
      expect(painted(), containsAll([left.id, right.id, 'edge']));
      for (final node in [left, right]) {
        expect(box.contains(mapped(Offset(node.x, node.y))), isTrue);
        expect(
          box.contains(
            mapped(Offset(node.x + node.width, node.y + node.height)),
          ),
          isTrue,
        );
      }
      final fullScale = camera.value.getMaxScaleOnAxis();
      final center = Offset(
        right.x + right.width / 2,
        right.y + right.height / 2,
      );
      await tester.tapAt(origin + mapped(center));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Fit selection'));
      await tester.pumpAndSettle();
      expect(camera.value.getMaxScaleOnAxis(), greaterThan(fullScale));
      expect(
        (mapped(center) - size.center(Offset.zero)).distance,
        lessThan(.01),
      );
      final touchpad = await tester.createGesture(
        kind: PointerDeviceKind.trackpad,
      );
      await touchpad.panZoomStart(origin + size.center(Offset.zero));
      await touchpad.panZoomUpdate(
        origin + size.center(Offset.zero),
        scale: 1.1,
      );
      await touchpad.panZoomEnd();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Fit selection'));
      await tester.pumpAndSettle();
      expect(
        (mapped(center) - size.center(Offset.zero)).distance,
        lessThan(.01),
      );
      expect((session.view as FileViewText).text, board.encode());
    },
  );
}
