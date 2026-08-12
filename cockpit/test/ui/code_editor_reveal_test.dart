import 'package:cockpit/app/cockpit/domain/entities/scm_line_decorations.dart';
import 'package:cockpit/app/cockpit/ui/widgets/code_editor.dart';
import 'package:cockpit/app/core/domain/entities/lsp_diagnostic.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/code_editing_controller.dart';
import 'package:cockpit/app/core/ui/widgets/code_highlight.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  // Linha longa à direita pra forçar scroll horizontal no reveal.
  final longLine = 'x' * 400;
  final text = 'line0\n$longLine target here\nline2\nline3 target end';
  final matchStart = text.indexOf('target'); // no meio da linha longa

  Widget harness(
    CodeEditingController ctrl, {
    int? revealStart,
    int? revealLine,
    bool revealSelect = true,
    int tick = 0,
    ScmLineDecorations scmDecorations = ScmLineDecorations.empty,
    Brightness brightness = Brightness.dark,
    double width = 300,
    double height = 200,
  }) {
    return ShadcnApp(
      theme: buildTheme(brightness: brightness),
      home: Scaffold(
        child: Center(
          child: SizedBox(
            width: width,
            height: height,
            child: CodeEditor(
              controller: ctrl,
              focusNode: FocusNode(),
              revealLine: revealLine,
              revealSelect: revealSelect,
              revealTick: tick,
              scmDecorations: scmDecorations,
              revealMatchStart: revealStart,
              revealMatchTick: tick,
            ),
          ),
        ),
      ),
    );
  }

  bool hasPaintedColor(WidgetTester tester, Key key, Color expected) {
    return find
        .descendant(
          of: find.byKey(key),
          matching: find.byWidgetPredicate((w) {
            if (w is ColoredBox) return w.color == expected;
            if (w is Container) {
              if (w.color == expected) return true;
              final d = w.decoration;
              return d is BoxDecoration && d.color == expected;
            }
            return false;
          }),
        )
        .evaluate()
        .isNotEmpty;
  }

  testWidgets('reveal de match assenta sem travar (scroll anexado)', (
    tester,
  ) async {
    final ctrl = CodeEditingController(text: text, language: 'txt');
    await tester.pumpWidget(harness(ctrl));
    await tester.pumpAndSettle();

    // Dispara o reveal — o scroll horizontal já tem clients aqui.
    await tester.pumpWidget(harness(ctrl, revealStart: matchStart, tick: 1));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('mudancas Git decoram o gutter sem selecionar a linha', (
    tester,
  ) async {
    final ctrl = CodeEditingController(text: text, language: 'txt');
    await tester.pumpWidget(
      harness(
        ctrl,
        revealLine: 2,
        revealSelect: false,
        tick: 1,
        scmDecorations: const ScmLineDecorations(
          addedLines: {2},
          modifiedLines: {3},
          removalBoundaries: {3},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('git-change-line:2')), findsOneWidget);
    expect(find.byKey(const ValueKey('git-change-line:3')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('git-removal-boundary:3')),
      findsOneWidget,
    );
    expect(ctrl.selection.isCollapsed, isTrue);
  });

  testWidgets('SCM gutter usa tokens online/accent/gitDeleted', (tester) async {
    final ctrl = CodeEditingController(text: 'a\nb\nc\n', language: 'txt');
    await tester.pumpWidget(
      harness(
        ctrl,
        scmDecorations: const ScmLineDecorations(
          addedLines: {1},
          modifiedLines: {2},
          removalBoundaries: {0, 3},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      hasPaintedColor(
        tester,
        const ValueKey('git-change-line:1'),
        AppColors.dark.online,
      ),
      isTrue,
    );
    expect(
      hasPaintedColor(
        tester,
        const ValueKey('git-change-line:2'),
        AppColors.dark.accent,
      ),
      isTrue,
    );
    expect(
      hasPaintedColor(
        tester,
        const ValueKey('git-removal-boundary:0'),
        AppColors.dark.gitDeleted,
      ),
      isTrue,
    );
    expect(
      hasPaintedColor(
        tester,
        const ValueKey('git-removal-boundary:3'),
        AppColors.dark.gitDeleted,
      ),
      isTrue,
    );
  });

  testWidgets('removal boundary 0 aparece na primeira linha visível', (
    tester,
  ) async {
    final ctrl = CodeEditingController(text: 'only\n', language: 'txt');
    await tester.pumpWidget(
      harness(
        ctrl,
        scmDecorations: const ScmLineDecorations(
          addedLines: {},
          modifiedLines: {},
          removalBoundaries: {0},
        ),
      ),
    );
    await tester.pumpAndSettle();
    // hasScm → Stack ganha git-change-line:1; o vermelho é o boundary 0.
    expect(find.byKey(const ValueKey('git-change-line:1')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('git-removal-boundary:0')),
      findsOneWidget,
    );
  });

  testWidgets('linha SCM fora do viewport não é construída (virtualização)', (
    tester,
  ) async {
    final lines = List.generate(80, (i) => 'line$i').join('\n');
    final ctrl = CodeEditingController(text: lines, language: 'txt');
    await tester.pumpWidget(
      harness(
        ctrl,
        height: 160,
        scmDecorations: const ScmLineDecorations(
          addedLines: {1, 70},
          modifiedLines: {},
          removalBoundaries: {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('git-change-line:1')), findsOneWidget);
    expect(find.byKey(const ValueKey('git-change-line:70')), findsNothing);
  });

  testWidgets('marcador SCM não recebe hit test (IgnorePointer)', (
    tester,
  ) async {
    final ctrl = CodeEditingController(text: 'a\nb\nc\n', language: 'txt');
    await tester.pumpWidget(
      harness(
        ctrl,
        scmDecorations: const ScmLineDecorations(
          addedLines: {1},
          modifiedLines: {},
          removalBoundaries: {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('git-change-line:1')),
        matching: find.byType(IgnorePointer),
      ),
      findsWidgets,
    );
  });

  testWidgets('SCM e diagnostic coexistem na mesma linha do gutter', (
    tester,
  ) async {
    final ctrl = CodeEditingController(text: 'a\nb\n', language: 'txt')
      ..diagnostics = const [
        LspDiagnostic(
          range: LspRange(LspPosition(0, 0), LspPosition(0, 1)),
          severity: LspSeverity.error,
          message: 'boom',
        ),
      ];
    await tester.pumpWidget(
      harness(
        ctrl,
        scmDecorations: const ScmLineDecorations(
          addedLines: {1},
          modifiedLines: {},
          removalBoundaries: {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('git-change-line:1')), findsOneWidget);
    expect(find.byIcon(Icons.error), findsOneWidget);
  });

  testWidgets('reveal repetido (navegação entre matches) assenta', (
    tester,
  ) async {
    final ctrl = CodeEditingController(text: text, language: 'txt');
    final second = text.indexOf('target', matchStart + 1);
    await tester.pumpWidget(harness(ctrl));
    await tester.pumpAndSettle();
    for (var t = 1; t <= 6; t++) {
      final off = t.isEven ? second : matchStart;
      ctrl.setSearchMatches([MatchSpan(off, off + 6)], 0);
      await tester.pumpWidget(harness(ctrl, revealStart: off, tick: t));
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('setSearchMatches com seleção de intervalo (pin ligado) não '
      'entra em busy-loop de microtask', (tester) async {
    final ctrl = CodeEditingController(text: text, language: 'txt');
    await tester.pumpWidget(harness(ctrl));
    await tester.pumpAndSettle();
    // Seleção de intervalo na linha longa → liga o pin horizontal do editor.
    ctrl.selection = const TextSelection(baseOffset: 6, extentOffset: 60);
    await tester.pumpAndSettle();
    // Aplica matches repetidamente COM a seleção de intervalo viva. Se o pin
    // ficar em busy-loop de microtask, pumpAndSettle nunca retorna.
    for (var t = 1; t <= 6; t++) {
      ctrl.setSearchMatches([MatchSpan(matchStart, matchStart + 6)], 0);
      await tester.pumpWidget(harness(ctrl, revealStart: matchStart, tick: t));
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }
    expect(tester.takeException(), isNull);
  });
}
