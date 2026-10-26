import 'package:cockpit/app/core/ui/overlay/app_popover_handler.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  testWidgets(
    'dismissed popovers remove their barrier and release project taps',
    (tester) async {
      late BuildContext anchor;
      var projectTaps = 0;
      final host = ShadcnApp(
        theme: buildTheme(
          brightness: Brightness.dark,
        ).copyWith(platform: () => TargetPlatform.windows),
        home: Scaffold(
          child: Builder(
            builder: (context) {
              anchor = context;
              return Align(
                alignment: Alignment.bottomLeft,
                child: GestureDetector(
                  onTap: () => projectTaps++,
                  child: const SizedBox(
                    width: 180,
                    height: 60,
                    child: Text('Project target'),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpWidget(TickerMode(enabled: true, child: host));

      for (var cycle = 0; cycle < 3; cycle++) {
        final entry = const AppPopoverOverlayHandler().show<void>(
          context: anchor,
          alignment: Alignment.topLeft,
          position: const Offset(250, 100),
          builder: (_) => const SizedBox(
            width: 100,
            height: 60,
            child: Text('Popover content'),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(find.text('Popover content'), findsOneWidget);

        if (cycle == 2) {
          // Minimized/offstage windows can stop animation ticks while event
          // processing continues. Logical dismissal must still release input.
          await tester.pumpWidget(TickerMode(enabled: false, child: host));
        }

        await tester.tap(find.text('Project target'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pump();

        expect(entry.isCompleted, isTrue);
        expect(entry.isAnimationCompleted, isTrue);
        expect(find.byType(PopoverOverlayWidget), findsNothing);
        await tester.tap(find.text('Project target'));
        expect(projectTaps, cycle + 1);
      }
    },
  );
}
