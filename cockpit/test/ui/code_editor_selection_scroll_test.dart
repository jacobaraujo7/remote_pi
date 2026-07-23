import 'package:cockpit/app/cockpit/ui/widgets/code_editor.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/code_editing_controller.dart';
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart' as m show TextField;
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  // Muitas linhas curtas: o conteúdo estoura a altura do viewport → arrastar a
  // seleção até a borda de baixo dispara auto-scroll vertical.
  final text = List.generate(200, (i) => 'line $i').join('\n');

  Widget harness(CodeEditingController ctrl) {
    return ShadcnApp(
      theme: buildTheme(brightness: Brightness.dark),
      home: Scaffold(
        child: Center(
          child: SizedBox(
            width: 320,
            height: 200,
            child: CodeEditor(controller: ctrl, focusNode: FocusNode()),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'drag-select com auto-scroll não faz a âncora inicial escorregar',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final ctrl = CodeEditingController(text: text, language: 'txt');
      await tester.pumpWidget(harness(ctrl));
      await tester.pumpAndSettle();

      final field = find.byType(m.TextField);
      final rect = tester.getRect(field);

      // Começa a seleção perto do TOPO do campo (âncora nas primeiras linhas).
      final start = Offset(rect.left + 40, rect.top + 10);
      final gesture =
          await tester.startGesture(start, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 50));

      // Passos intermediários pra o gesto ser reconhecido como pan de seleção,
      // depois segura na borda inferior → auto-scroll roda por frames.
      await gesture.moveTo(Offset(rect.left + 60, rect.top + 40));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.moveTo(Offset(rect.left + 60, rect.bottom - 2));
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      debugDefaultTargetPlatformOverride = null;

      final sel = ctrl.selection;
      expect(sel.isValid, isTrue);
      expect(sel.isCollapsed, isFalse, reason: 'esperava um intervalo selecionado');

      // A âncora (base) foi fixada perto do topo do texto. Se ela escorregasse
      // com o scroll, o base cairia numa linha bem mais funda. Toleramos as
      // primeiras linhas visíveis no início (o clique não é exatamente no 0).
      final baseLine = '\n'.allMatches(text.substring(0, sel.baseOffset)).length;
      final extentLine =
          '\n'.allMatches(text.substring(0, sel.extentOffset)).length;
      // A âncora (base) foi fixada no topo do texto. O campo é o dono do scroll
      // vertical (scroll interno), então ele fica parado no espaço global e a
      // âncora — recalculada de global→local a cada update do drag — NÃO
      // escorrega. Se escorregasse, o base cairia numa linha bem mais funda.
      // (Mesmo comportamento de um TextField multilinha padrão.)
      expect(
        baseLine,
        lessThan(6),
        reason: 'âncora escorregou com o scroll (baseLine=$baseLine)',
      );
      // A seleção cresceu pra baixo (extent depois da base) — drag pra frente.
      expect(extentLine, greaterThan(baseLine));
    },
  );
}
