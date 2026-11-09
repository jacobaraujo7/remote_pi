import 'package:cockpit/app/cockpit/ui/widgets/http_response_code_view.dart';
import 'package:cockpit/app/cockpit/ui/widgets/http_response_folds.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart' as m show TextField;
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  testWidgets('resposta JSON mostra linhas e permite fechar e abrir fold', (
    tester,
  ) async {
    const source = '{\n  "data": {\n    "ok": true\n  }\n}';
    final foldedStarts = <int>{};

    Widget harness(String key) => ShadcnApp(
      theme: buildTheme(brightness: Brightness.light),
      home: Scaffold(
        child: Center(
          child: SizedBox(
            width: 520,
            height: 240,
            child: HttpResponseCodeView(
              key: ValueKey(key),
              text: source,
              language: 'json',
              foldSyntax: HttpResponseFoldSyntax.json,
              foldedStarts: foldedStarts,
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(harness('first'));
    expect(find.text('1'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.moveTo(tester.getCenter(find.text('1')));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down).first);
    await tester.pumpAndSettle();
    expect(foldedStarts, {0});
    expect(
      tester.widget<m.TextField>(find.byType(m.TextField)).controller!.text,
      '{}',
    );

    await tester.pumpWidget(harness('reopened'));
    expect(foldedStarts, {0});
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    expect(foldedStarts, isEmpty);
    expect(
      tester.widget<m.TextField>(find.byType(m.TextField)).controller!.text,
      source,
    );
    await mouse.removePointer();
  });
}
