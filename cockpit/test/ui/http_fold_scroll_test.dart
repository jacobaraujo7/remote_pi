import 'package:cockpit/app/cockpit/ui/widgets/code_editor.dart';
import 'package:cockpit/app/cockpit/ui/widgets/http_request_folds.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/code_editing_controller.dart';
import 'package:flutter/material.dart' as m show TextField;
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  testWidgets('fold mantém o scroll do editor ao trocar a projeção', (
    tester,
  ) async {
    final source = List.generate(
      60,
      (i) => 'GET https://example.test/$i\nAccept: application/json\n',
    ).join('\n');
    const foldLine = 90;
    final projection = HttpRequestFolds.build(source, {foldLine});
    final original = CodeEditingController(text: source, language: 'http');
    final folded = CodeEditingController(
      text: projection.text,
      language: 'http',
    );
    final focus = FocusNode();
    addTearDown(original.dispose);
    addTearDown(folded.dispose);
    addTearDown(focus.dispose);

    Widget editor(
      CodeEditingController controller, {
      required bool isFolded,
      ({int oldLine, int newLine, int tick})? anchor,
      List<int>? lineNumbers,
    }) => ShadcnApp(
      theme: buildTheme(brightness: Brightness.dark),
      home: Scaffold(
        child: Center(
          child: SizedBox(
            width: 600,
            height: 200,
            child: CodeEditor(
              controller: controller,
              focusNode: focus,
              readOnly: isFolded,
              lineNumbers: isFolded
                  ? lineNumbers ?? projection.lineNumbers
                  : null,
              scrollAnchor: anchor,
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(editor(original, isFolded: false));
    focus.requestFocus();
    await tester.pump();
    final beforeController = tester
        .widget<m.TextField>(find.byType(m.TextField))
        .scrollController!;
    beforeController.jumpTo(90 * 18.0 - 80);
    await tester.pumpAndSettle();
    final before = beforeController.offset;
    expect(before, greaterThan(1000));

    folded.selection = TextSelection.collapsed(
      offset: projection.text.split('\n').take(foldLine).join('\n').length + 1,
    );
    await tester.pumpWidget(
      editor(
        folded,
        isFolded: true,
        anchor: (oldLine: foldLine, newLine: foldLine, tick: 1),
      ),
    );
    await tester.pumpAndSettle();
    final afterController = tester
        .widget<m.TextField>(find.byType(m.TextField))
        .scrollController!;
    expect(identical(afterController, beforeController), isTrue);
    expect(afterController.offset, closeTo(before, 1));

    // Um segundo fold muda o mesmo controller projetado enquanto o editor
    // já está recolhido. A linha clicada deve permanecer no viewport.
    const secondSourceLine = 120;
    final secondProjection = HttpRequestFolds.build(source, {
      foldLine,
      secondSourceLine,
    });
    const secondVisibleLine = secondSourceLine - 1;
    afterController.jumpTo(secondVisibleLine * 18.0 - 80);
    await tester.pumpAndSettle();
    final secondBefore = afterController.offset;
    folded.text = secondProjection.text;
    folded.selection = TextSelection.collapsed(
      offset:
          secondProjection.text
              .split('\n')
              .take(secondVisibleLine)
              .join('\n')
              .length +
          1,
    );
    await tester.pumpWidget(
      editor(
        folded,
        isFolded: true,
        lineNumbers: secondProjection.lineNumbers,
        anchor: (
          oldLine: secondVisibleLine,
          newLine: secondVisibleLine,
          tick: 2,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(afterController.offset, closeTo(secondBefore, 1));

    original.selection = TextSelection.collapsed(
      offset: source.split('\n').take(secondSourceLine).join('\n').length + 1,
    );
    await tester.pumpWidget(
      editor(
        original,
        isFolded: false,
        anchor: (
          oldLine: secondVisibleLine,
          newLine: secondSourceLine,
          tick: 3,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(beforeController.offset, closeTo(secondBefore + 18, 3));
  });
}
