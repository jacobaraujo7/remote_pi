import 'package:cockpit/app/cockpit/domain/entities/scm_line_decorations.dart';
import 'package:cockpit/app/cockpit/ui/widgets/code_editor.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/code_editing_controller.dart';
import 'package:flutter/rendering.dart' show RenderEditable;
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  // Linha 2 (base 1) longa o bastante para quebrar várias vezes em 300px.
  final longLine = 'x' * 400;
  final text = 'line0\n$longLine target\nline2 tail\nline3';
  final line3Start = text.indexOf('line2'); // início da linha 3 (base 1)

  Widget harness(
    CodeEditingController ctrl, {
    bool wordWrap = true,
    double width = 300,
    double height = 200,
    int? revealLine,
    int? revealStart,
    int tick = 0,
    ScmLineDecorations scmDecorations = ScmLineDecorations.empty,
  }) {
    return ShadcnApp(
      theme: buildTheme(brightness: Brightness.dark),
      home: Scaffold(
        child: Center(
          child: SizedBox(
            width: width,
            height: height,
            child: CodeEditor(
              controller: ctrl,
              focusNode: FocusNode(),
              wordWrap: wordWrap,
              revealLine: revealLine,
              revealSelect: false,
              revealTick: tick,
              revealMatchStart: revealStart,
              revealMatchTick: tick,
              scmDecorations: scmDecorations,
            ),
          ),
        ),
      ),
    );
  }

  CodeEditingController controller(WidgetTester tester) {
    final ctrl = CodeEditingController(text: text, language: 'markdown');
    addTearDown(ctrl.dispose);
    return ctrl;
  }

  Finder horizontalScrollable() => find.byWidgetPredicate(
    (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
  );

  RenderEditable editable(WidgetTester tester) =>
      tester.state<EditableTextState>(find.byType(EditableText)).renderEditable;

  /// Y global do caret no [offset] do texto (topo da linha visual).
  double caretY(WidgetTester tester, int offset) {
    final re = editable(tester);
    final rect = re.getLocalRectForCaret(TextPosition(offset: offset));
    return re.localToGlobal(rect.topLeft).dy;
  }

  testWidgets('com quebra, a linha longa quebra e não há scroll horizontal', (
    tester,
  ) async {
    await tester.pumpWidget(harness(controller(tester)));
    await tester.pumpAndSettle();

    expect(horizontalScrollable(), findsNothing);
    // A linha 3 começa várias linhas visuais abaixo da linha 2.
    final row = editable(tester).preferredLineHeight;
    expect(
      caretY(tester, line3Start) - caretY(tester, 0),
      greaterThan(4 * row),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('sem quebra, o layout de código continua com scroll horizontal', (
    tester,
  ) async {
    await tester.pumpWidget(harness(controller(tester), wordWrap: false));
    await tester.pumpAndSettle();

    expect(horizontalScrollable(), findsOneWidget);
    final row = editable(tester).preferredLineHeight;
    expect(caretY(tester, line3Start) - caretY(tester, 0), closeTo(2 * row, 1));
  });

  testWidgets('número e marca Git da linha 3 alinham com o texto da linha 3', (
    tester,
  ) async {
    // Quebra em poucas linhas visuais: a linha 3 precisa caber no viewport
    // (o gutter é virtualizado e não constrói linhas fora da tela).
    final shortWrap = 'line0\n${'x' * 60}\nline2 tail\nline3';
    final ctrl = CodeEditingController(text: shortWrap, language: 'markdown');
    addTearDown(ctrl.dispose);
    await tester.pumpWidget(
      harness(
        ctrl,
        scmDecorations: const ScmLineDecorations(
          addedLines: {3},
          modifiedLines: {},
          removalBoundaries: {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final row = editable(tester).preferredLineHeight;
    final start = shortWrap.indexOf('line2');
    // Sem a tabela de alturas, o gutter poria a linha 3 a 2 linhas do topo.
    expect(caretY(tester, start) - caretY(tester, 0), greaterThan(3 * row));
    final textY = caretY(tester, start);
    final gutterY = tester
        .getTopLeft(find.byKey(const ValueKey('git-change-line:3')))
        .dy;
    expect((gutterY - textY).abs(), lessThan(row / 2));
    expect(
      (tester.getTopLeft(find.text('3')).dy - textY).abs(),
      lessThan(row / 2),
    );
  });

  testWidgets('reveal da linha 3 a deixa visível com quebra', (tester) async {
    final ctrl = controller(tester);
    await tester.pumpWidget(harness(ctrl));
    await tester.pumpAndSettle();

    await tester.pumpWidget(harness(ctrl, revealLine: 3, tick: 1));
    await tester.pumpAndSettle();

    final box = tester.getRect(find.byType(CodeEditor));
    final y = caretY(tester, line3Start);
    expect(y, inInclusiveRange(box.top, box.bottom));
  });

  testWidgets('reveal de match no fim da linha quebrada o deixa visível', (
    tester,
  ) async {
    final ctrl = controller(tester);
    final match = text.indexOf('target');
    await tester.pumpWidget(harness(ctrl));
    await tester.pumpAndSettle();

    await tester.pumpWidget(harness(ctrl, revealStart: match, tick: 1));
    await tester.pumpAndSettle();

    final box = tester.getRect(find.byType(CodeEditor));
    expect(caretY(tester, match), inInclusiveRange(box.top, box.bottom));
  });

  testWidgets('alternar a quebra em tempo de execução não lança', (
    tester,
  ) async {
    final ctrl = controller(tester);
    await tester.pumpWidget(harness(ctrl, wordWrap: false));
    await tester.pumpAndSettle();
    expect(horizontalScrollable(), findsOneWidget);

    await tester.pumpWidget(harness(ctrl));
    await tester.pumpAndSettle();
    expect(horizontalScrollable(), findsNothing);

    await tester.pumpWidget(harness(ctrl, wordWrap: false));
    await tester.pumpAndSettle();
    expect(horizontalScrollable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  /// Cada número do gutter alinhado com o início da sua linha no campo.
  void expectGutterAligned(WidgetTester tester, String source, int lines) {
    final row = editable(tester).preferredLineHeight;
    var start = 0;
    for (var i = 1; i <= lines; i++) {
      final number = find.text('$i');
      expect(number, findsOneWidget, reason: 'line $i built in the gutter');
      expect(
        (tester.getTopLeft(number).dy - caretY(tester, start)).abs(),
        lessThan(row / 2),
        reason: 'gutter number $i aligned with its text',
      );
      start = source.indexOf('\n', start) + 1;
    }
  }

  testWidgets('editar a linha até ela quebrar realinha o gutter', (
    tester,
  ) async {
    final ctrl = CodeEditingController(
      text: 'a\nb\nc\nd',
      language: 'markdown',
    );
    addTearDown(ctrl.dispose);
    await tester.pumpWidget(harness(ctrl));
    await tester.pumpAndSettle();
    expectGutterAligned(tester, ctrl.text, 4);

    // Sem `\n` novo: a linha 2 passa a ocupar várias linhas visuais.
    ctrl.text = 'a\n${'b' * 60}\nc\nd';
    await tester.pump();
    expectGutterAligned(tester, ctrl.text, 4);

    // E volta a uma linha visual.
    ctrl.text = 'a\nb\nc\nd';
    await tester.pump();
    expectGutterAligned(tester, ctrl.text, 4);
  });

  testWidgets(
    'tabela de alturas quebra igual ao campo em larguras de fronteira',
    (tester) async {
      // Linhas de 1 a 40 caracteres cruzam várias fronteiras de quebra; as 14
      // larguras seguidas (um glifo da fonte de teste + o `letterSpacing` do
      // tema) garantem que alguma caia a menos de 3px da fronteira — onde
      // errar a margem do caret (`kEditorWrapCaretMargin`) ou o estilo
      // efetivo do campo quebraria a tabela diferente do campo.
      tester.view.physicalSize = const Size(800, 4200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final source = [for (var n = 1; n <= 40; n++) 'x' * n].join('\n');
      final ctrl = CodeEditingController(text: source, language: 'markdown');
      addTearDown(ctrl.dispose);
      for (var width = 300.0; width < 314; width++) {
        await tester.pumpWidget(harness(ctrl, width: width, height: 4000));
        await tester.pumpAndSettle();
        expectGutterAligned(tester, source, 40);
      }
    },
  );
}
