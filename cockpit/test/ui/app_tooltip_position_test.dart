import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/app_tooltip.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Reproduz a topologia real do app: o zoom (`_AppZoom` = MediaQuery reduzida +
/// FittedBox) fica no `builder` do ShadcnApp, ACIMA do Navigator/Overlay.
Widget host({required double scale, required Widget child}) => ShadcnApp(
  theme: buildTheme(
    brightness: Brightness.dark,
  ).copyWith(platform: () => TargetPlatform.macOS),
  builder: (context, appChild) {
    if ((scale - 1.0).abs() < 0.001) return appChild!;
    final mq = MediaQuery.of(context);
    final scaled = mq.size / scale;
    return MediaQuery(
      data: mq.copyWith(size: scaled),
      child: FittedBox(
        fit: BoxFit.fill,
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: scaled.width,
          height: scaled.height,
          child: appChild,
        ),
      ),
    );
  },
  home: Align(
    alignment: Alignment.centerLeft,
    child: Padding(padding: const EdgeInsets.only(left: 300), child: child),
  ),
);

Future<Rect> showBalloon(WidgetTester tester) async {
  final trigger = find.byType(AppTooltip);
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  addTearDown(gesture.removePointer);
  await gesture.moveTo(tester.getCenter(trigger));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 300));
  final balloon = find.byType(TooltipContainer);
  expect(balloon, findsOneWidget);
  return tester.getRect(balloon);
}

void main() {
  const tip = AppTooltip(
    message: 'Split right',
    child: SizedBox(width: 13, height: 13),
  );

  testWidgets('zoom 1.0 — balão logo abaixo do trigger', (tester) async {
    await tester.pumpWidget(host(scale: 1.0, child: tip));
    final triggerRect = tester.getRect(find.byType(AppTooltip));
    final balloonRect = await showBalloon(tester);
    expect((balloonRect.center.dx - triggerRect.center.dx).abs(), lessThan(30));
    expect(balloonRect.top - triggerRect.bottom, inInclusiveRange(0, 24));
  });

  testWidgets('zoom 1.5 — balão logo abaixo do trigger', (tester) async {
    await tester.pumpWidget(host(scale: 21 / 14, child: tip));
    final triggerRect = tester.getRect(find.byType(AppTooltip));
    final balloonRect = await showBalloon(tester);
    // ignore: avoid_print
    print('trigger: $triggerRect balloon: $balloonRect');
    expect((balloonRect.center.dx - triggerRect.center.dx).abs(), lessThan(30));
    expect(balloonRect.top - triggerRect.bottom, inInclusiveRange(0, 36));
  });
}
