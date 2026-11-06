import 'package:cockpit/app/cockpit/ui/widgets/code_editor.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/code_editing_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  testWidgets('popup de variáveis aparece, permite clique e desaparece', (
    tester,
  ) async {
    final controller = CodeEditingController(
      text: 'GET {{ho}}',
      language: 'http',
    )..selection = const TextSelection.collapsed(offset: 8);
    final focus = FocusNode();
    String? chosen;

    Widget app(bool visible) => ShadcnApp(
      theme: buildTheme(brightness: Brightness.dark),
      home: Scaffold(
        child: SizedBox(
          width: 500,
          height: 300,
          child: CodeEditor(
            controller: controller,
            focusNode: focus,
            completionVisible: visible,
            completionItems: const ['host', 'hostname'],
            completionEmptyLabel: 'No matches',
            onCompletionSelected: (name) => chosen = name,
          ),
        ),
      ),
    );

    await tester.pumpWidget(app(false));
    await tester.pumpWidget(app(true));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('http-variable-completion')),
      findsOneWidget,
    );
    expect(find.text('host'), findsOneWidget);
    await tester.tap(find.text('host'));
    expect(chosen, 'host');

    await tester.pumpWidget(app(false));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('http-variable-completion')),
      findsNothing,
    );
    controller.dispose();
    focus.dispose();
  });
}
