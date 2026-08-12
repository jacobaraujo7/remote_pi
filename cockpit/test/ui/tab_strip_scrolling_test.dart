import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Tab strip horizontal scrolling', () {
    testWidgets('PointerScrollEvent dy translates to horizontal scroll offset', (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 40,
              child: Listener(
                onPointerSignal: (pointerSignal) {
                  if (pointerSignal is PointerScrollEvent &&
                      controller.hasClients) {
                    final dy = pointerSignal.scrollDelta.dy;
                    final dx = pointerSignal.scrollDelta.dx;
                    final delta = (dx != 0) ? dx : dy;
                    if (delta != 0) {
                      final newOffset = (controller.offset + delta).clamp(
                        0.0,
                        controller.position.maxScrollExtent,
                      );
                      controller.jumpTo(newOffset);
                    }
                  }
                },
                child: SingleChildScrollView(
                  controller: controller,
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: List.generate(
                      10,
                      (index) =>
                          SizedBox(width: 100, child: Text('Tab $index')),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      expect(controller.offset, 0.0);

      final location = tester.getCenter(find.text('Tab 0'));
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: location,
          scrollDelta: const Offset(0, 150),
        ),
      );
      await tester.pump();

      expect(controller.offset, 150.0);
    });
  });
}
