import 'package:cockpit/app/cockpit/ui/widgets/pane_view.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('selects another dock on mouse down even when drag wins', (
    tester,
  ) async {
    var selected = 0;
    var tapUps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Draggable<int>(
                data: 1,
                feedback: const SizedBox(width: 20, height: 20),
                child: TabPointerSelection(
                  tabWidth: 188,
                  onSelect: () => selected++,
                  child: GestureDetector(
                    onTapUp: (_) => tapUps++,
                    child: const SizedBox(width: 188, height: 40),
                  ),
                ),
              ),
              const Expanded(child: SizedBox()),
            ],
          ),
        ),
      ),
    );

    final tab = tester.getRect(find.byType(TabPointerSelection));
    final gesture = await tester.startGesture(
      tab.centerLeft + const Offset(30, 0),
      kind: PointerDeviceKind.mouse,
    );
    expect(selected, 1, reason: 'a aba deve mudar antes de soltar o mouse');
    await gesture.moveBy(const Offset(0, 80));
    await tester.pump();
    await gesture.up();
    expect(selected, 1);
    expect(tapUps, 0, reason: 'o drag cancela o onTapUp anterior');
  });

  testWidgets('close area and secondary button do not select', (tester) async {
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: TabPointerSelection(
            tabWidth: 188,
            onSelect: () => selected++,
            child: const SizedBox(width: 188, height: 40),
          ),
        ),
      ),
    );

    final tab = tester.getRect(find.byType(TabPointerSelection));
    await tester.tapAt(
      tab.centerRight - const Offset(10, 0),
      kind: PointerDeviceKind.mouse,
    );
    final secondary = await tester.startGesture(
      tab.center,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await secondary.up();
    expect(selected, 0);
  });
}
