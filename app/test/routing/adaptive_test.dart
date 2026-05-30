// Plan/tablet — adaptive master-detail shell.
//
// Verifies the three moving parts without spinning up the full DI/boot:
//   1. SessionSelection notifier semantics (select / matches / clear / no-op).
//   2. isWideLayout breakpoint.
//   3. The StatefulShellRoute + navigatorContainerBuilder layout decision:
//      wide → master + detail side by side; narrow → only the active branch.

import 'package:app/routing/adaptive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

GoRouter _buildAdaptiveRouter() {
  return GoRouter(
    initialLocation: '/home',
    routes: [
      StatefulShellRoute(
        builder: (ctx, st, navShell) => navShell,
        navigatorContainerBuilder: (ctx, navShell, children) {
          if (!isWideLayout(ctx)) return children[navShell.currentIndex];
          return Row(
            children: [
              SizedBox(width: 360, child: children[0]),
              Expanded(child: children[1]),
            ],
          );
        },
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/home',
              builder: (_, _) =>
                  const Scaffold(body: Center(child: Text('MASTER'))),
            ),
          ]),
          StatefulShellBranch(preload: true, routes: [
            GoRoute(
              path: '/session',
              builder: (_, _) =>
                  const Scaffold(body: Center(child: Text('DETAIL'))),
            ),
          ]),
        ],
      ),
    ],
  );
}

Future<void> _pumpAt(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp.router(routerConfig: _buildAdaptiveRouter()));
  await tester.pumpAndSettle();
}

void main() {
  group('SessionSelection', () {
    test('starts empty (no pre-selection on launch)', () {
      final sel = SessionSelection();
      expect(sel.current, isNull);
      expect(sel.matches('epk', 'main'), isFalse);
    });

    test('select sets current and matches the (epk, room)', () {
      final sel = SessionSelection();
      var notifications = 0;
      sel.addListener(() => notifications++);

      sel.select('epkA', 'main', 'Title A');
      expect(sel.current?.epk, 'epkA');
      expect(sel.current?.roomId, 'main');
      expect(sel.current?.title, 'Title A');
      expect(sel.matches('epkA', 'main'), isTrue);
      expect(sel.matches('epkA', 'other'), isFalse);
      expect(sel.matches('epkB', 'main'), isFalse);
      expect(notifications, 1);
    });

    test('re-selecting the same session is a no-op (no rebuild)', () {
      final sel = SessionSelection();
      sel.select('epkA', 'main', 'Title A');
      var notifications = 0;
      sel.addListener(() => notifications++);

      sel.select('epkA', 'main', 'Title A again');
      expect(notifications, 0, reason: 'same (epk, room) must not notify');
      expect(sel.current?.title, 'Title A', reason: 'unchanged');
    });

    test('clear resets to empty and notifies once', () {
      final sel = SessionSelection();
      sel.select('epkA', 'main', 'Title A');
      var notifications = 0;
      sel.addListener(() => notifications++);

      sel.clear();
      expect(sel.current, isNull);
      expect(notifications, 1);
      sel.clear(); // already empty
      expect(notifications, 1, reason: 'clearing twice must not re-notify');
    });
  });

  group('isWideLayout', () {
    testWidgets('true at/above breakpoint, false below', (tester) async {
      late bool wide;
      Future<void> probe(double width) async {
        await tester.pumpWidget(MediaQuery(
          data: MediaQueryData(size: Size(width, 800)),
          child: Builder(builder: (ctx) {
            wide = isWideLayout(ctx);
            return const SizedBox();
          }),
        ));
      }

      await probe(kTabletBreakpoint - 1);
      expect(wide, isFalse);
      await probe(kTabletBreakpoint);
      expect(wide, isTrue);
      await probe(1024);
      expect(wide, isTrue);
    });
  });

  group('adaptive shell layout', () {
    testWidgets('wide → master AND detail are both shown', (tester) async {
      await _pumpAt(tester, const Size(1200, 800));
      expect(find.text('MASTER'), findsOneWidget);
      expect(find.text('DETAIL'), findsOneWidget);
    });

    testWidgets('narrow → only the active branch (master) is shown',
        (tester) async {
      await _pumpAt(tester, const Size(420, 900));
      expect(find.text('MASTER'), findsOneWidget);
      expect(find.text('DETAIL'), findsNothing);
    });
  });

  group('zero-state collapse', () {
    GoRouter buildGatedRouter() {
      return GoRouter(
        initialLocation: '/home',
        routes: [
          StatefulShellRoute(
            builder: (ctx, st, navShell) => navShell,
            navigatorContainerBuilder: (ctx, navShell, children) {
              final twoPane =
                  isWideLayout(ctx) && !ctx.watch<ShellLayout>().isZeroState;
              if (!twoPane) return children[navShell.currentIndex];
              return Row(
                children: [
                  SizedBox(width: 360, child: children[0]),
                  Expanded(child: children[1]),
                ],
              );
            },
            branches: [
              StatefulShellBranch(routes: [
                GoRoute(
                  path: '/home',
                  builder: (_, _) =>
                      const Scaffold(body: Center(child: Text('MASTER'))),
                ),
              ]),
              StatefulShellBranch(preload: true, routes: [
                GoRoute(
                  path: '/session',
                  builder: (_, _) =>
                      const Scaffold(body: Center(child: Text('DETAIL'))),
                ),
              ]),
            ],
          ),
        ],
      );
    }

    testWidgets('wide + zero-state shows only master; flipping back re-splits',
        (tester) async {
      final shell = ShellLayout()..setZeroState(true);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(ChangeNotifierProvider<ShellLayout>.value(
        value: shell,
        child: MaterialApp.router(routerConfig: buildGatedRouter()),
      ));
      await tester.pumpAndSettle();

      // Zero-state on a wide screen → single pane (no split).
      expect(find.text('MASTER'), findsOneWidget);
      expect(find.text('DETAIL'), findsNothing);

      // Sessions appear → the split returns.
      shell.setZeroState(false);
      await tester.pumpAndSettle();
      expect(find.text('MASTER'), findsOneWidget);
      expect(find.text('DETAIL'), findsOneWidget);
    });
  });
}
