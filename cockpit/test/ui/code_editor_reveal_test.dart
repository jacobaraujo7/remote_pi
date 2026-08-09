import 'package:cockpit/app/cockpit/ui/widgets/code_editor.dart';
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
    Set<int> addedLines = const {},
    Set<int> modifiedLines = const {},
    Set<int> removedLines = const {},
  }) {
    return ShadcnApp(
      theme: buildTheme(brightness: Brightness.dark),
      home: Scaffold(
        child: Center(
          child: SizedBox(
            width: 300,
            height: 200,
            child: CodeEditor(
              controller: ctrl,
              focusNode: FocusNode(),
              revealLine: revealLine,
              revealSelect: revealSelect,
              revealTick: tick,
              addedLines: addedLines,
              modifiedLines: modifiedLines,
              removedLines: removedLines,
              revealMatchStart: revealStart,
              revealMatchTick: tick,
            ),
          ),
        ),
      ),
    );
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
        addedLines: const {2},
        modifiedLines: const {3},
        removedLines: const {4},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('git-change-line:2')), findsOneWidget);
    expect(find.byKey(const ValueKey('git-change-line:3')), findsOneWidget);
    expect(find.byKey(const ValueKey('git-change-line:4')), findsOneWidget);
    expect(ctrl.selection.isCollapsed, isTrue);
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
