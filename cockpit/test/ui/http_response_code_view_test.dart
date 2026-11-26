import 'package:cockpit/app/cockpit/ui/widgets/http_response_code_view.dart';
import 'package:cockpit/app/cockpit/ui/widgets/http_response_folds.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, PointerScrollEvent;
import 'package:flutter/material.dart' as m show TextField;
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  testWidgets('resposta longa permite rolar sem quebrar linhas', (
    tester,
  ) async {
    final source = '${'x' * 1000} tail\nlast line';
    Widget harness(double width) => ShadcnApp(
      theme: buildTheme(brightness: Brightness.light),
      home: Scaffold(
        child: Center(
          child: SizedBox(
            width: width,
            height: 240,
            child: HttpResponseCodeView(
              text: source,
              language: null,
              foldSyntax: null,
              foldedStarts: <int>{},
            ),
          ),
        ),
      ),
    );

    for (final width in [520.0, 180.0, 700.0]) {
      await tester.pumpWidget(harness(width));
      await tester.pumpAndSettle();
      final horizontal = find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
      );
      final position = tester.state<ScrollableState>(horizontal).position;
      expect(position.maxScrollExtent, greaterThan(width));
      position.jumpTo(0);
      final numberPosition = tester.getTopLeft(find.text('2'));
      final editable = tester
          .state<EditableTextState>(find.byType(EditableText))
          .renderEditable;
      expect(
        editable
                .getLocalRectForCaret(
                  TextPosition(offset: source.indexOf('last')),
                )
                .top -
            editable.getLocalRectForCaret(const TextPosition(offset: 0)).top,
        closeTo(editable.preferredLineHeight, 1),
      );
      // Uma resposta continua navegável depois de selecionar texto para copiar.
      final controller = tester
          .widget<m.TextField>(find.byType(m.TextField))
          .controller!;
      controller.selection = const TextSelection.collapsed(offset: 0);
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 4,
      );
      await tester.pumpAndSettle();
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(horizontal),
          scrollDelta: const Offset(120, 0),
        ),
      );
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(0));
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(horizontal),
          scrollDelta: Offset(position.maxScrollExtent, 0),
        ),
      );
      await tester.pumpAndSettle();
      expect(position.pixels, closeTo(position.maxScrollExtent, 1));
      final tail = editable.localToGlobal(
        editable
            .getLocalRectForCaret(TextPosition(offset: source.indexOf('\n')))
            .topLeft,
      );
      final viewport = tester.getRect(horizontal);
      expect(tail.dx, inInclusiveRange(viewport.left, viewport.right));

      // Arrastar a barra também funciona com uma seleção ativa.
      controller.selection = const TextSelection(
        baseOffset: 1,
        extentOffset: 5,
      );
      await tester.pumpAndSettle();
      final panel = tester.getRect(find.byType(HttpResponseCodeView));
      final mouse = await tester.startGesture(
        Offset(panel.right - 10, panel.bottom - 3),
        kind: PointerDeviceKind.mouse,
      );
      await mouse.moveBy(const Offset(-60, 0));
      await mouse.up();
      await tester.pumpAndSettle();
      expect(position.pixels, lessThan(position.maxScrollExtent));
      expect(controller.text, source);
      expect(tester.getTopLeft(find.text('2')), numberPosition);
      expect(tester.takeException(), isNull);
    }
  });

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
