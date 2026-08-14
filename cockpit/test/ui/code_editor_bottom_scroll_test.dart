import 'package:cockpit/app/cockpit/ui/widgets/code_editor.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/code_editing_controller.dart';
import 'package:flutter/material.dart' as m show TextField;
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  testWidgets(
    'no fim do scroll a última linha do gutter fica acima da faixa da scrollbar',
    (tester) async {
      final text = List.generate(80, (i) => 'line ${i + 1}').join('\n');
      final ctrl = CodeEditingController(text: text, language: 'txt');

      await tester.pumpWidget(
        ShadcnApp(
          theme: buildTheme(brightness: Brightness.dark),
          home: Scaffold(
            child: Center(
              child: SizedBox(
                width: 320,
                height: 220,
                child: CodeEditor(controller: ctrl, focusNode: FocusNode()),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      ScrollPosition? vert;
      for (final s in tester.widgetList<Scrollable>(find.byType(Scrollable))) {
        final pos = s.controller?.position;
        if (pos != null &&
            pos.axis == Axis.vertical &&
            pos.maxScrollExtent > 0) {
          vert = pos;
          break;
        }
      }
      expect(vert, isNotNull);
      vert!.jumpTo(vert.maxScrollExtent);
      await tester.pumpAndSettle();

      final field = tester.getRect(find.byType(m.TextField));
      final lastLine = tester.getRect(find.text('80'));

      // Folga de 14px no fim do scroll — a última linha não pode assentar no
      // fio do viewport (onde a scrollbar horizontal faz overlay).
      const padBottom = 14.0;
      expect(
        lastLine.bottom,
        lessThanOrEqualTo(field.bottom - padBottom + 0.5),
        reason:
            'última linha ainda colada no fundo do campo '
            '(bottom=${lastLine.bottom}, field=${field.bottom})',
      );
      expect(lastLine.height, greaterThan(10));
    },
  );
}
