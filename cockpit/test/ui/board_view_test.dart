import 'dart:async';
import 'dart:ui' show PointerDeviceKind;
import 'package:cockpit/app/cockpit/domain/entities/board_document.dart';
import 'package:cockpit/app/cockpit/domain/entities/file_view.dart';
import 'package:cockpit/app/cockpit/ui/session/file_viewer_session.dart';
import 'package:cockpit/app/cockpit/ui/widgets/board_view.dart';
import 'package:cockpit/app/cockpit/ui/widgets/board_painter.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/overlay/app_popover_handler.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/material.dart' as m;
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  testWidgets('applying Mermaid reconciles with the latest workspace object', (
    tester,
  ) async {
    const item = BoardItem(
      'm',
      BoardKind.mermaid,
      40,
      45,
      label: 'flowchart LR\nA',
    );
    final initial = BoardDocument([item]).encode();
    final session = FileViewerSession(
      id: 'mermaid',
      projectId: 'test',
      path: 'diagram.board',
      view: FileViewText(initial),
    );
    addTearDown(session.dispose);
    var writes = 0;
    await tester.pumpWidget(
      TranslationProvider(
        child: ShadcnApp(
          theme: buildTheme(brightness: Brightness.dark),
          home: Scaffold(
            child: BoardView(
              session: session,
              onReload: () async {},
              onSave: (text) async {
                writes++;
                session.adoptDisk(FileViewText(text));
                return true;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final canvas = tester.getTopLeft(find.byType(m.InteractiveViewer));
    await tester.tapAt(canvas + const Offset(70, 65));
    await tester.pump();
    Future<void> applyAfter(List<BoardItem> items) async {
      final button = tester.widget<m.TextButton>(
        find.widgetWithText(m.TextButton, 'Mermaid'),
      );
      button.onPressed!();
      session.adoptDisk(FileViewText(BoardDocument(items).encode()));
      tester.state<NavigatorState>(find.byType(Navigator).first).pop((
        source: 'flowchart LR\nA-->B',
        thumbnail: null as String?,
      ));
      await tester.pumpAndSettle();
    }

    await applyAfter([item.edited(x: 120, color: '#E69F00')]);
    final saved = BoardDocument.parse(
      (session.view as FileViewText).text,
    ).items['m']!;
    expect(
      (saved.x, saved.color, saved.label),
      (120.0, '#E69F00', 'flowchart LR\nA-->B'),
    );
    await applyAfter([saved.edited(label: 'flowchart LR\nA-->C')]);
    expect(writes, 1);
    expect((session.view as FileViewText).text, contains('A-->C'));
    await applyAfter([]);
    expect(writes, 1);
    expect(
      BoardDocument.parse((session.view as FileViewText).text).items,
      isEmpty,
    );
  });
  testWidgets('an open connector follows the current shapes at the pointer', (
    tester,
  ) async {
    const a = BoardItem('a', BoardKind.process, 30, 40);
    const b = BoardItem('b', BoardKind.decision, 250, 40);
    const c = BoardItem('c', BoardKind.process, 250, 190);
    final initial = BoardDocument([a, b, c]).encode();
    final session = FileViewerSession(
      id: 'edge',
      projectId: 'test',
      path: 'edge.board',
      view: FileViewText(initial),
    );
    addTearDown(session.dispose);
    var writes = 0;
    await tester.pumpWidget(
      TranslationProvider(
        child: ShadcnApp(
          theme: buildTheme(brightness: Brightness.dark),
          home: Scaffold(
            child: BoardView(
              session: session,
              onReload: () async {},
              onSave: (source) async {
                writes++;
                session.adoptDisk(FileViewText(source));
                return true;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Connector'));
    await tester.pump();
    final canvas = tester.getTopLeft(find.byType(m.InteractiveViewer));
    Future<TestGesture> connect() async {
      final gesture = await tester.startGesture(
        canvas + const Offset(60, 65),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(canvas + const Offset(275, 65));
      await tester.pump();
      return gesture;
    }

    final first = await connect();
    session.adoptDisk(
      FileViewText(
        BoardDocument([a, b.edited(y: 190), c.edited(y: 40)]).encode(),
      ),
    );
    await tester.pump();
    await first.up();
    await tester.pumpAndSettle();
    final edge = BoardDocument.parse(
      (session.view as FileViewText).text,
    ).items.values.singleWhere((i) => i.kind == BoardKind.arrow);
    expect((edge.from, edge.to), ('a', 'c'));
    session.adoptDisk(FileViewText(initial));
    await tester.pump();
    final second = await connect();
    session.adoptDisk(FileViewText(BoardDocument([b, c]).encode()));
    await tester.pump();
    session.adoptDisk(FileViewText(initial));
    await tester.pump();
    await second.up();
    await tester.pumpAndSettle();
    expect(writes, 1);
  });
  testWidgets('drag uses the current shape and respects external deletion', (
    tester,
  ) async {
    const original = BoardItem(
      'step',
      BoardKind.process,
      40,
      45,
      label: 'Original',
    );
    final session = FileViewerSession(
      id: 'drag',
      projectId: 'test',
      path: 'process.board',
      view: FileViewText(
        BoardDocument([
          original,
          const BoardItem('front', BoardKind.process, 160, 45),
        ]).encode(),
      ),
    );
    addTearDown(session.dispose);
    var writes = 0;
    await tester.pumpWidget(
      TranslationProvider(
        child: ShadcnApp(
          theme: buildTheme(brightness: Brightness.dark),
          home: Scaffold(
            child: BoardView(
              session: session,
              onReload: () async {},
              onSave: (source) async {
                writes++;
                session.adoptDisk(FileViewText(source));
                return true;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final canvas = tester.getTopLeft(find.byType(m.InteractiveViewer));
    Future<TestGesture> drag(Offset at) async {
      final gesture = await tester.startGesture(
        canvas + at,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(25, 10));
      await tester.pump();
      return gesture;
    }

    final move = await drag(const Offset(65, 65));
    final painted = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<BoardPainter>()
        .expand((painter) => painter.items)
        .toList();
    expect(painted.map((item) => item.id), ['step', 'front']);
    expect(painted.first.x, 65);
    final updated = original.edited(x: 90, label: 'Harness', color: '#E69F00');
    session.adoptDisk(FileViewText(BoardDocument([updated]).encode()));
    await tester.pump();
    await move.up();
    await tester.pumpAndSettle();
    final saved = BoardDocument.parse(
      (session.view as FileViewText).text,
    ).items['step']!;
    expect(
      (saved.x, saved.y, saved.label, saved.color),
      (115.0, 55.0, 'Harness', '#E69F00'),
    );
    final remove = await drag(const Offset(140, 75));
    session.adoptDisk(FileViewText(BoardDocument([]).encode()));
    await tester.pump();
    await remove.up();
    await tester.pumpAndSettle();
    expect(writes, 1);
    expect(
      BoardDocument.parse((session.view as FileViewText).text).items,
      isEmpty,
    );
  });
  testWidgets('label drafts reconcile with edits from the harness', (
    tester,
  ) async {
    final initial = BoardDocument([
      const BoardItem('step', BoardKind.process, 40, 45, label: 'Original'),
    ]).encode();
    final session = FileViewerSession(
      id: 'draft',
      projectId: 'test',
      path: 'process.board',
      view: FileViewText(initial),
    );
    addTearDown(session.dispose);
    var writes = 0;
    await tester.pumpWidget(
      TranslationProvider(
        child: ShadcnApp(
          theme: buildTheme(brightness: Brightness.dark),
          home: Scaffold(
            child: BoardView(
              session: session,
              onReload: () async {},
              onSave: (source) async {
                writes++;
                session.adoptDisk(FileViewText(source));
                return true;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final origin = tester.getTopLeft(find.byType(m.InteractiveViewer));
    await tester.tapAt(origin + const Offset(65, 65));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.pump();
    final field = find.byType(m.TextField);
    await tester.enterText(field, 'Human draft');
    session.adoptDisk(
      FileViewText(initial.replaceFirst('> Original', '> Harness')),
    );
    await tester.pump();
    expect(find.text(t.cockpit.gallery.board.labelChanged), findsOneWidget);
    expect(await session.saveDraft!(), isFalse);
    await tester.tapAt(origin + const Offset(330, 170));
    await tester.pumpAndSettle();
    expect(tester.widget<m.TextField>(field).controller!.text, 'Human draft');
    expect(session.dirty, isTrue);
    session.adoptDisk(FileViewText(BoardDocument([]).encode()));
    await tester.pump();
    expect(find.text(t.cockpit.gallery.board.objectDeleted), findsOneWidget);
    expect(await session.saveDraft!(), isFalse);
    expect(tester.widget<m.TextField>(field).controller!.text, 'Human draft');
    expect(session.dirty, isTrue);
    expect(writes, 0);
    session.adoptDisk(
      FileViewText(initial.replaceFirst('> Original', '> Human draft')),
    );
    await tester.pump();
    expect(await session.saveDraft!(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text(t.cockpit.gallery.board.objectDeleted), findsNothing);
    expect(field, findsNothing);
    expect(session.dirty, isFalse);
    expect(writes, 0);
    await tester.tapAt(origin + const Offset(65, 65));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.pump();
    await tester.enterText(field, 'Discard this draft');
    session.adoptDisk(FileViewText(initial));
    await tester.pump();
    expect(find.text(t.cockpit.gallery.board.labelChanged), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text(t.cockpit.gallery.board.labelChanged), findsNothing);
    expect(field, findsNothing);
    expect(session.dirty, isFalse);
    expect(writes, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    final moved = BoardDocument.parse((session.view as FileViewText).text);
    expect(
      (moved.items['step']!.x, moved.items['step']!.label),
      (41, 'Original'),
    );
    expect(writes, 1);
  });
  testWidgets(
    'queued edits use new workspace Markdown when a harness changes it',
    (tester) async {
      final initial = BoardDocument([
        const BoardItem('note', BoardKind.note, 420, 220, label: 'initial'),
      ]);
      final session = FileViewerSession(
        id: 'merge',
        projectId: 'test',
        path: 'merge.board',
        view: FileViewText(initial.encode()),
      );
      addTearDown(session.dispose);
      final gate = Completer<void>();
      var writes = 0;
      await tester.pumpWidget(
        TranslationProvider(
          child: ShadcnApp(
            theme: buildTheme(brightness: Brightness.dark),
            home: Scaffold(
              child: BoardView(
                session: session,
                onReload: () async {},
                onSave: (source) async {
                  writes++;
                  if (writes == 1) {
                    await gate.future;
                    // A watcher event arrives after the first write and before the next.
                    source = source.replaceFirst(
                      '> initial',
                      '> changed by harness',
                    );
                  }
                  session.adoptDisk(FileViewText(source));
                  return true;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final origin = tester.getTopLeft(find.byType(m.InteractiveViewer));
      for (final (tool, point) in [
        ('Process', const Offset(40, 45)),
        ('Decision', const Offset(230, 45)),
      ]) {
        await tester.tap(find.byTooltip(tool));
        await tester.pump();
        await tester.tapAt(origin + point);
        await tester.pump();
      }
      expect(writes, 1);
      gate.complete();
      await tester.pumpAndSettle();
      final reopened = BoardDocument.parse((session.view as FileViewText).text);
      expect(writes, 2);
      expect(reopened.items.length, 3);
      expect(reopened.items['note']!.label, 'changed by harness');
    },
  );
  testWidgets(
    'desktop workflow survives delayed writes and paints ink without rebuilding the toolbar',
    (tester) async {
      final session = FileViewerSession(
        id: 'drag',
        projectId: 'test',
        path: 'drag.board',
        view: FileViewText(BoardDocument([]).encode()),
      );
      addTearDown(session.dispose);
      final gate = Completer<void>();
      var writes = 0;
      await tester.pumpWidget(
        TranslationProvider(
          child: ShadcnApp(
            popoverHandler: const AppPopoverOverlayHandler(),
            theme: buildTheme(brightness: Brightness.dark),
            home: Scaffold(
              child: BoardView(
                session: session,
                onReload: () async {},
                onSave: (source) async {
                  writes++;
                  await gate.future;
                  session.adoptDisk(FileViewText(source));
                  return true;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final viewer = find.byType(m.InteractiveViewer);
      final origin = tester.getTopLeft(viewer);
      Future<void> drag(Offset from, Offset to) async {
        final mouse = await tester.startGesture(
          origin + from,
          kind: PointerDeviceKind.mouse,
        );
        await mouse.moveTo(origin + to);
        await mouse.up();
        await tester.pump();
      }

      await tester.tap(find.byTooltip('Process'));
      await tester.pump();
      await drag(const Offset(30, 40), const Offset(150, 100));
      await tester.tap(find.byTooltip('Decision'));
      await tester.pump();
      await drag(const Offset(270, 40), const Offset(390, 100));
      await tester.tap(find.byTooltip('Connector'));
      await tester.pump();
      await drag(const Offset(80, 65), const Offset(320, 65));
      expect(writes, 1);
      expect(session.dirty, isTrue);
      var readyToClose = false;
      final saved = session.saveDraft!().then((ok) => readyToClose = ok);
      await tester.pump();
      expect(readyToClose, isFalse);
      gate.complete();
      await tester.pumpAndSettle();
      expect(await saved, isTrue);
      expect(session.dirty, isFalse);
      BoardDocument read() =>
          BoardDocument.parse((session.view as FileViewText).text);
      expect(read().items.length, 3);
      final process = read().items.values.first;
      final arrow = read().items.values.last;
      expect(process.width, 120);
      expect(arrow.from, process.id);
      expect(arrow.to, read().items.values.elementAt(1).id);
      await tester.tap(find.byTooltip('Select'));
      await tester.pump();
      await drag(const Offset(80, 65), const Offset(95, 195));
      expect(read().items[process.id]!.y, 170);
      // Include the connector, whose stored origin is (0,0), in a mixed selection.
      await tester.tap(find.byTooltip('Advanced'));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tapAt(origin + const Offset(217, 125));
      await tester.pump();
      expect(find.byTooltip('Align top'), findsNothing);
      await tester.tapAt(origin + const Offset(320, 65));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Align top'));
      await tester.tap(find.byTooltip('Align top'));
      await tester.pumpAndSettle();
      expect(read().items[process.id]!.y, 40);
      expect(read().items[arrow.id]!.from, process.id);
      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();
      expect(read().items[process.id]!.y, 170);
      await tester.ensureVisible(find.byTooltip('Advanced'));
      await tester.tap(find.byTooltip('Advanced'));
      await tester.tapAt(origin + const Offset(95, 195));
      await tester.pumpAndSettle();
      // The selected process has moved to (45,170), with size 120 x 60.
      final handle = origin + const Offset(171, 200);
      final destination = origin + const Offset(320, 65);
      final mouseLink = await tester.startGesture(
        handle,
        kind: PointerDeviceKind.mouse,
      );
      await mouseLink.moveTo(destination);
      await tester.pump();
      expect(read().items.length, 3);
      await mouseLink.up();
      await tester.pumpAndSettle();
      expect(read().items.values.last.from, process.id);
      expect(read().items.values.last.to, arrow.to);
      final count = read().items.length;
      expect(count, 4);
      await tester.tapAt(handle);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.tapAt(destination);
      await tester.pump();
      expect(read().items.length, count);
      await tester.tapAt(origin + const Offset(95, 195));
      await tester.pump();
      await tester.tapAt(handle);
      await tester.pump();
      await tester.tapAt(destination);
      await tester.pumpAndSettle();
      expect(read().items.length, count + 1);
      final camera = tester
          .widget<m.InteractiveViewer>(viewer)
          .transformationController!;
      final beforePan = camera.value.clone();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(tester.widget<m.InteractiveViewer>(viewer).panEnabled, isTrue);
      final hand = await tester.startGesture(
        origin + const Offset(300, 210),
        kind: PointerDeviceKind.mouse,
      );
      await hand.moveBy(const Offset(-25, -25));
      await hand.moveBy(const Offset(-45, -25));
      await hand.up();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(camera.value, isNot(equals(beforePan)));
      expect(tester.widget<m.InteractiveViewer>(viewer).panEnabled, isFalse);
      expect(read().items.length, count + 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await tester.pump();
      expect(find.byType(m.TextField), findsOneWidget);
      expect(
        tester
            .getRect(find.byType(m.TextField))
            .contains(
              origin +
                  MatrixUtils.transformPoint(
                    camera.value,
                    const Offset(95, 195),
                  ),
            ),
        isTrue,
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(tester.widget<m.InteractiveViewer>(viewer).panEnabled, isFalse);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      camera.value = beforePan;
      await tester.pump();
      expect(find.text('Diagram color'), findsOneWidget);
      final object = origin + const Offset(95, 195);
      await tester.tapAt(object, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(object, kind: PointerDeviceKind.mouse);
      await tester.pump();
      final field = find.byType(m.TextField);
      expect(tester.getRect(field).contains(object), isTrue);
      const editedLabel = 'Pedido editado\n\n  ## decisão\n- id: literal\n';
      await tester.enterText(field, editedLabel);
      await tester.tapAt(
        origin + const Offset(610, 270),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(read().items[process.id]!.label, editedLabel);
      await tester.tapAt(object);
      await tester.pump();
      await tester.tap(find.byTooltip('Diagram color'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Green'));
      await tester.pumpAndSettle();
      expect(read().items[process.id]!.color, '#64CBA7');
      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();
      expect(read().items[process.id]!.color, isNull);
      await tester.tapAt(object);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await tester.pump();
      expect(tester.widget<m.TextField>(field).controller!.text, editedLabel);
      await tester.enterText(field, 'Cancelar');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(field, findsNothing);
      expect(read().items[process.id]!.label, editedLabel);
      await tester.tap(find.byTooltip('Text'));
      await tester.pump();
      await tester.tapAt(origin + const Offset(460, 190));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<m.TextField>(find.byType(m.TextField))
            .focusNode!
            .hasFocus,
        isTrue,
      );
      await tester.enterText(find.byType(m.TextField), 'Aprovação financeira');
      await tester.testTextInput.receiveAction(m.TextInputAction.done);
      await tester.pumpAndSettle();
      expect(read().items.values.last.label, 'Aprovação financeira');
      await tester.tap(find.byTooltip('Pencil'));
      await tester.pumpAndSettle();
      final pencil = find.widgetWithIcon(m.IconButton, m.Icons.edit);
      final toolbarButton = tester.widget(pencil);
      final mouse = await tester.startGesture(
        origin + const Offset(80, 240),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      final canvasLayers = find.descendant(
        of: find.byType(m.InteractiveViewer),
        matching: find.byType(CustomPaint),
      );
      expect(canvasLayers.last, paints..circle(radius: 1));
      await mouse.moveTo(origin + const Offset(81, 240));
      for (var i = 1; i <= 100; i++) {
        await mouse.moveTo(
          origin + Offset(80 + i.toDouble(), 240 + (i % 12).toDouble()),
        );
        await tester.pump();
      }
      expect(identical(tester.widget(pencil), toolbarButton), isTrue);
      await mouse.up();
      await tester.pumpAndSettle();
      final stroke = read().items.values.last;
      expect(stroke.points.length, 102);
      expect(stroke.points[1], (x: 1.0, y: 0.0));
      expect(stroke.width, 100);
      expect(stroke.height, 11);
      await tester.tap(find.byTooltip('Advanced'));
      await tester.pump();
      for (final name in ['Lane', 'Container', 'Service', 'Note']) {
        await tester.ensureVisible(find.byTooltip(name));
        await tester.tap(find.byTooltip(name));
        await tester.pump();
        final corner = tester.getTopLeft(viewer) + const Offset(50, 50);
        final mouse = await tester.startGesture(
          corner,
          kind: PointerDeviceKind.mouse,
        );
        await mouse.moveTo(corner + const Offset(165, 85));
        await mouse.up();
        await tester.pumpAndSettle();
        expect(read().items.values.last.kind.name, name.toLowerCase());
      }
      await tester.ensureVisible(find.byTooltip('Pan'));
      await tester.tap(find.byTooltip('Pan'));
      await tester.pumpAndSettle();
      final controller = tester
          .widget<m.InteractiveViewer>(viewer)
          .transformationController!;
      final matrix = controller.value.clone();
      final corner = tester.getCenter(viewer);
      final mousePan = await tester.startGesture(
        corner,
        kind: PointerDeviceKind.mouse,
      );
      await mousePan.moveTo(corner - const Offset(25, 25));
      await mousePan.moveTo(corner - const Offset(80, 80));
      await mousePan.up();
      await tester.pumpAndSettle();
      expect(controller.value, isNot(equals(matrix)));
      await tester.tap(find.byTooltip('Zoom In'));
      await tester.pumpAndSettle();
      expect(find.text('120%'), findsOneWidget);
      await tester.tap(find.text('120%'));
      await tester.pumpAndSettle();
      expect(find.text('100%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Gallery board can insert a process and undo in the Cockpit theme',
    (tester) async {
      final session = FileViewerSession(
        id: 'board',
        projectId: 'test',
        path: 'diagram.board',
        view: FileViewText(BoardDocument([]).encode()),
      );
      addTearDown(session.dispose);
      await tester.pumpWidget(
        TranslationProvider(
          child: ShadcnApp(
            popoverHandler: const AppPopoverOverlayHandler(),
            theme: buildTheme(brightness: Brightness.dark),
            home: Scaffold(
              child: BoardView(
                session: session,
                onSave: (value) async {
                  session.adoptDisk(FileViewText(value));
                  return true;
                },
                onReload: () async {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Process'));
      final viewer = find.byType(m.InteractiveViewer);
      await tester.tapAt(tester.getTopLeft(viewer) + const Offset(128, 128));
      await tester.pumpAndSettle();
      expect(
        BoardDocument.parse(
          (session.view as FileViewText).text,
        ).items.values.single.kind,
        BoardKind.process,
      );
      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();
      expect(
        BoardDocument.parse((session.view as FileViewText).text).items,
        isEmpty,
      );
    },
  );
}
