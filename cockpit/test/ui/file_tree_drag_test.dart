import 'package:cockpit/app/cockpit/domain/entities/file_node.dart';
import 'package:cockpit/app/cockpit/ui/widgets/file_tree_panel.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class _TreeActions {
  final taps = <String>[];
  final opens = <String>[];
  final moves = <(String, String)>[];
}

Future<_TreeActions> _pumpTree(WidgetTester tester) async {
  LocaleSettings.setLocale(AppLocale.en);
  final actions = _TreeActions();
  await tester.pumpWidget(
    TranslationProvider(
      child: ShadcnApp(
        theme: buildTheme(brightness: Brightness.dark),
        home: Scaffold(
          child: FileTreePanel(
            rootPath: '/workspace',
            revision: 1,
            listChildren: (path) async => switch (path) {
              '/workspace' => const [
                FileNode(
                  name: 'source',
                  path: '/workspace/source',
                  isDirectory: true,
                ),
                FileNode(
                  name: 'target',
                  path: '/workspace/target',
                  isDirectory: true,
                ),
                FileNode(
                  name: 'file.txt',
                  path: '/workspace/file.txt',
                  isDirectory: false,
                ),
              ],
              '/workspace/source' => const [
                FileNode(
                  name: 'child.txt',
                  path: '/workspace/source/child.txt',
                  isDirectory: false,
                ),
              ],
              _ => const [],
            },
            gitStatusOf: (_) => null,
            onOpenFile: actions.opens.add,
            onTapFile: actions.taps.add,
            onOpenDiff: (_) {},
            isGitRepo: false,
            changedPaths: const [],
            onOpenWith: (_) {},
            onCreateInFolder: (_, {command}) {},
            onCreate: (_, _, _) async => const Success(null),
            onRename: (_, _) async => const Success(null),
            onDelete: (_) async => const Success(null),
            onMove: (path, target) async {
              actions.moves.add((path, target));
              return const Success(null);
            },
            onCopy: (_) {},
            onCut: (_) {},
            onPaste: (_) async => const Success(null),
            canPaste: false,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return actions;
}

void main() {
  final feedback = find.byIcon(Icons.alternate_email);
  for (final name in ['source', 'file.txt']) {
    for (final distance in [0.0, 2.0, 8.0]) {
      testWidgets(
        'quick mouse click on $name with $distance px drift stays a click',
        (tester) async {
          final actions = await _pumpTree(tester);
          final start = tester.getCenter(find.text(name));
          final mouse = await tester.startGesture(
            start,
            kind: PointerDeviceKind.mouse,
          );
          await mouse.moveTo(start + Offset(distance, 0));
          await tester.pump(const Duration(milliseconds: 10));
          expect(feedback, findsNothing);
          await mouse.up();
          await tester.pumpAndSettle();
          expect(find.text('Move?'), findsNothing);
          expect(actions.moves, isEmpty);
          if (name == 'source') {
            expect(find.text('child.txt'), findsOneWidget);
          } else {
            expect(actions.taps, ['/workspace/file.txt']);
          }
        },
      );
    }

    testWidgets(
      'holding and jittering $name does not accumulate drag distance',
      (tester) async {
        final actions = await _pumpTree(tester);
        final start = tester.getCenter(find.text(name));
        final mouse = await tester.startGesture(
          start,
          kind: PointerDeviceKind.mouse,
        );
        for (var i = 0; i < 8; i++) {
          await mouse.moveTo(start + Offset(i.isEven ? 4 : -4, 0));
          await tester.pump(const Duration(milliseconds: 100));
          expect(feedback, findsNothing);
        }
        await mouse.up();
        await tester.pumpAndSettle();
        expect(find.text('Move?'), findsNothing);
        expect(actions.moves, isEmpty);
        if (name == 'source') {
          expect(find.text('child.txt'), findsOneWidget);
        } else {
          expect(actions.taps, ['/workspace/file.txt']);
        }
      },
    );

    testWidgets(
      'deliberate mouse drag of $name starts without delay and confirms before moving',
      (tester) async {
        final actions = await _pumpTree(tester);
        final start = tester.getCenter(find.text(name));
        final mouse = await tester.startGesture(
          start,
          kind: PointerDeviceKind.mouse,
        );
        await mouse.moveTo(start + const Offset(9, 0));
        await tester.pump();
        expect(feedback, findsOneWidget);
        expect(actions.taps, isEmpty);
        expect(find.text('child.txt'), findsNothing);
        await mouse.moveTo(tester.getCenter(find.text('target')));
        await tester.pump();
        expect(find.text('Move?'), findsNothing);
        await mouse.up();
        await tester.pumpAndSettle();
        expect(find.text('Move?'), findsOneWidget);
        expect(actions.moves, isEmpty);
        await tester.tap(find.text('Move'));
        await tester.pumpAndSettle();
        expect(actions.moves, [('/workspace/$name', '/workspace/target')]);
      },
    );
  }

  testWidgets('small drift across the next folder does not request a move', (
    tester,
  ) async {
    final actions = await _pumpTree(tester);
    // A click near the bottom of a 26px row can cross into its sibling.
    final start = tester.getCenter(find.text('source')) + const Offset(0, 12);
    final mouse = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveBy(const Offset(0, 4));
    await tester.pump();
    expect(feedback, findsNothing);
    await mouse.up();
    await tester.pumpAndSettle();
    expect(find.text('child.txt'), findsOneWidget);
    expect(find.text('Move?'), findsNothing);
    expect(actions.moves, isEmpty);
  });

  testWidgets('rapid file double click with drift still opens the file', (
    tester,
  ) async {
    final actions = await _pumpTree(tester);
    for (var i = 0; i < 2; i++) {
      final mouse = await tester.startGesture(
        tester.getCenter(find.text('file.txt')),
        kind: PointerDeviceKind.mouse,
      );
      await mouse.moveBy(const Offset(3, 2));
      await mouse.up();
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
    expect(actions.taps, ['/workspace/file.txt']);
    expect(actions.opens, ['/workspace/file.txt']);
    expect(actions.moves, isEmpty);
  });

  testWidgets(
    'dragging an expanded child moves the child rather than its folder',
    (tester) async {
      final actions = await _pumpTree(tester);
      await tester.tap(find.text('source'));
      await tester.pumpAndSettle();
      final mouse = await tester.startGesture(
        tester.getCenter(find.text('child.txt')),
        kind: PointerDeviceKind.mouse,
      );
      await mouse.moveBy(const Offset(9, 0));
      await tester.pump();
      expect(feedback, findsOneWidget);
      await mouse.moveTo(tester.getCenter(find.text('target')));
      await tester.pump();
      await mouse.up();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move'));
      await tester.pumpAndSettle();
      expect(actions.moves, [
        ('/workspace/source/child.txt', '/workspace/target'),
      ]);
    },
  );

  testWidgets(
    'cancelled pointer and release outside a drop target do not move',
    (tester) async {
      final actions = await _pumpTree(tester);
      for (final cancel in [true, false]) {
        final mouse = await tester.startGesture(
          tester.getCenter(find.text('file.txt')),
          kind: PointerDeviceKind.mouse,
        );
        await mouse.moveBy(const Offset(9, 0));
        await tester.pump();
        expect(feedback, findsOneWidget);
        await mouse.moveTo(const Offset(1, 1));
        await tester.pump();
        if (cancel) {
          await mouse.cancel();
        } else {
          await mouse.up();
        }
        await tester.pumpAndSettle();
        expect(feedback, findsNothing);
        expect(find.text('Move?'), findsNothing);
        expect(actions.moves, isEmpty);
      }
    },
  );

  for (final name in ['source', 'file.txt']) {
    testWidgets('dropping $name in its current parent needs no confirmation', (
      tester,
    ) async {
      final actions = await _pumpTree(tester);
      final mouse = await tester.startGesture(
        tester.getCenter(find.text(name)),
        kind: PointerDeviceKind.mouse,
      );
      await mouse.moveBy(const Offset(9, 0));
      await tester.pump();
      expect(feedback, findsOneWidget);
      await mouse.up();
      await tester.pumpAndSettle();
      expect(feedback, findsNothing);
      expect(find.text('Move?'), findsNothing);
      expect(actions.moves, isEmpty);
    });
  }

  testWidgets(
    'diagonal drag uses distance and cancelling confirmation does not move',
    (tester) async {
      final actions = await _pumpTree(tester);
      final mouse = await tester.startGesture(
        tester.getCenter(find.text('file.txt')),
        kind: PointerDeviceKind.mouse,
      );
      await mouse.moveBy(const Offset(6, 6));
      await tester.pump();
      expect(feedback, findsOneWidget);
      await mouse.moveTo(tester.getCenter(find.text('target')));
      await tester.pump();
      await mouse.up();
      await tester.pumpAndSettle();
      expect(find.text('Move?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(actions.moves, isEmpty);
      expect(actions.taps, isEmpty);
    },
  );

  testWidgets('touch on desktop retains the Flutter touch threshold', (
    tester,
  ) async {
    await _pumpTree(tester);
    final touch = await tester.startGesture(
      tester.getCenter(find.text('file.txt')),
      kind: PointerDeviceKind.touch,
    );
    await touch.moveBy(const Offset(9, 0));
    await tester.pump();
    expect(feedback, findsNothing);
    await touch.moveBy(const Offset(10, 0));
    await tester.pump();
    expect(feedback, findsOneWidget);
    await touch.moveTo(const Offset(1, 1));
    await touch.up();
    await tester.pumpAndSettle();
    expect(find.text('Move?'), findsNothing);
  });
}
