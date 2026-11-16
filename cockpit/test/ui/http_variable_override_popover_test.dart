import 'package:cockpit/app/cockpit/domain/entities/http_runtime_variable.dart';
import 'package:cockpit/app/cockpit/ui/widgets/http_variable_override_popover.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  testWidgets('undefined abre campo vazio, aplica valor e permite restaurar', (
    tester,
  ) async {
    LocaleSettings.setLocale(AppLocale.ptBr);
    HttpRuntimeVariable? applied;
    var cleared = false;
    HttpRuntimeVariable? current;

    Widget build() => TranslationProvider(
      child: ShadcnApp(
        theme: buildTheme(brightness: Brightness.light),
        home: Scaffold(
          child: Center(
            child: SizedBox(
              width: 340,
              child: HttpVariableOverridePopover(
                name: 'missing',
                effectiveValue: current?.value,
                origin: 'undefined',
                runtimeOverride: current,
                onApply: (value) {
                  applied = value;
                  current = value;
                },
                onClear: () {
                  cleared = true;
                  current = null;
                },
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(build());
    final field = find.byType(TextField);
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    await tester.enterText(field, '42');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.text('number'), findsOneWidget);
    await tester.tap(find.text('number'));
    await tester.tap(field);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpWidget(build());
    expect(applied?.value, '42');
    expect(find.text('Temporária'), findsOneWidget);
    await tester.tap(find.text('Restaurar'));
    await tester.pumpWidget(build());
    expect(cleared, isTrue);
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    expect(find.text('undefined'), findsWidgets);
  });
}
