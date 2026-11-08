import 'package:cockpit/app/cockpit/ui/widgets/code_editor.dart';
import 'package:cockpit/app/cockpit/domain/entities/http_runtime_variable.dart';
import 'package:cockpit/app/cockpit/ui/widgets/http_variable_override_popover.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/code_editing_controller.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, PointerScrollEvent;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  testWidgets('popover acompanha rolagem do editor', (tester) async {
    LocaleSettings.setLocale(AppLocale.ptBr);
    final source =
        '${List.filled(7, '// filler').join('\n')}\n'
        'GET {{value}}\n${List.filled(35, '// filler').join('\n')}';
    final start = source.indexOf('{{value}}');
    final controller = CodeEditingController(text: source, language: 'http');
    final focus = FocusNode();
    addTearDown(() {
      controller.dispose();
      focus.dispose();
    });
    await tester.pumpWidget(
      TranslationProvider(
        child: ShadcnApp(
          theme: buildTheme(brightness: Brightness.light),
          home: Scaffold(
            child: SizedBox(
              width: 500,
              height: 220,
              child: CodeEditor(
                controller: controller,
                focusNode: focus,
                variableNameAt: (offset) =>
                    offset >= start && offset < start + 9 ? 'value' : null,
                variablePopoverBuilder: (name) => HttpVariableOverridePopover(
                  name: name,
                  effectiveValue: 'original',
                  origin: 'Arquivo HTTP',
                  runtimeOverride: null,
                  onApply: (_) {},
                  onClear: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    final editor = tester.getTopLeft(find.byType(CodeEditor));
    final popup = find.byType(HttpVariableOverridePopover);
    for (final y in [140.0, 150.0, 160.0, 170.0, 180.0, 190.0]) {
      await mouse.moveTo(editor + Offset(125, y));
      await tester.pump();
      if (popup.evaluate().isNotEmpty) break;
    }
    expect(popup, findsOneWidget);
    await tester.tap(find.byType(TextField));
    final before = tester.getRect(popup);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: editor + const Offset(480, 100),
        scrollDelta: const Offset(0, 50),
      ),
    );
    await tester.pumpAndSettle();
    expect(popup, findsOneWidget);
    final after = tester.getRect(popup);
    expect(after.top, isNot(before.top));
    await mouse.removePointer();
  });

  testWidgets('popover ancora na variável e cabe nas bordas da janela', (
    tester,
  ) async {
    LocaleSettings.setLocale(AppLocale.ptBr);
    const source = '// 1\n// 2\n// 3\n// 4\n// 5\nGET {{value}}';
    final controller = CodeEditingController(text: source, language: 'http');
    final focus = FocusNode();
    addTearDown(() {
      controller.dispose();
      focus.dispose();
    });
    await tester.pumpWidget(
      TranslationProvider(
        child: ShadcnApp(
          theme: buildTheme(brightness: Brightness.light),
          home: Scaffold(
            child: Align(
              alignment: Alignment.bottomRight,
              child: SizedBox(
                width: 400,
                height: 180,
                child: CodeEditor(
                  controller: controller,
                  focusNode: focus,
                  variableNameAt: (offset) =>
                      offset >= source.indexOf('{{value}}') &&
                          offset < source.indexOf('{{value}}') + 9
                      ? 'value'
                      : null,
                  variablePopoverBuilder: (name) => HttpVariableOverridePopover(
                    name: name,
                    effectiveValue: 'original',
                    origin: 'Arquivo HTTP',
                    runtimeOverride: null,
                    onApply: (_) {},
                    onClear: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    final editor = tester.getTopLeft(find.byType(CodeEditor));
    final popup = find.byType(HttpVariableOverridePopover);
    for (final y in [100.0, 110.0, 120.0, 130.0, 140.0, 150.0]) {
      await mouse.moveTo(editor + Offset(125, y));
      await tester.pump();
      if (popup.evaluate().isNotEmpty) break;
    }
    expect(popup, findsOneWidget);
    final rect = tester.getRect(popup);
    final window = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(window.width));
    expect(rect.bottom, lessThanOrEqualTo(window.height));
    expect(rect.top, lessThan(editor.dy + 150));
    await tester.tap(find.byType(TextField));
    tester.view.physicalSize = const Size(640, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpAndSettle();
    final resized = tester.getRect(popup);
    expect(resized.left, greaterThanOrEqualTo(0));
    expect(resized.top, greaterThanOrEqualTo(0));
    expect(resized.right, lessThanOrEqualTo(640));
    expect(resized.bottom, lessThanOrEqualTo(480));
    await mouse.removePointer();
  });

  testWidgets('popover mantém foco e valor ao sair com o mouse', (
    tester,
  ) async {
    LocaleSettings.setLocale(AppLocale.ptBr);
    final controller = CodeEditingController(
      text: 'GET {{value}}/items',
      language: 'http',
    );
    final focus = FocusNode();
    HttpRuntimeVariable? current;
    addTearDown(() {
      controller.dispose();
      focus.dispose();
    });
    await tester.pumpWidget(
      TranslationProvider(
        child: ShadcnApp(
          theme: buildTheme(brightness: Brightness.light),
          home: Scaffold(
            child: StatefulBuilder(
              builder: (context, update) => SizedBox(
                width: 500,
                height: 250,
                child: CodeEditor(
                  controller: controller,
                  focusNode: focus,
                  variableNameAt: (offset) =>
                      offset >= 4 && offset < 13 ? 'value' : null,
                  variablePopoverBuilder: (name) => HttpVariableOverridePopover(
                    key: ValueKey(name),
                    name: name,
                    effectiveValue: current?.value ?? 'original',
                    origin: 'Arquivo HTTP',
                    runtimeOverride: current,
                    onApply: (value) => update(() => current = value),
                    onClear: () => update(() => current = null),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    final editor = tester.getTopLeft(find.byType(CodeEditor));
    await mouse.moveTo(editor + const Offset(125, 24));
    await tester.pump();
    final field = find.byType(TextField);
    expect(field, findsOneWidget);
    final popup = find.byType(HttpVariableOverridePopover);
    expect(tester.getTopLeft(popup).dx, lessThan(editor.dx + 125));

    await mouse.moveTo(tester.getCenter(field));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(field);
    await mouse.moveTo(editor + const Offset(480, 220));
    await tester.pump(const Duration(milliseconds: 300));
    expect(popup, findsOneWidget);
    await tester.enterText(field, '42');
    await tester.tap(find.text('string'));
    await tester.pump();
    await tester.tap(find.text('number'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(popup, findsOneWidget);
    await tester.tap(field);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(current?.value, '42');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 300));
    expect(popup, findsNothing);
    await mouse.moveTo(editor + const Offset(125, 24));
    await tester.pump();
    expect(popup, findsOneWidget);
    await tester.enterText(field, 'unconfirmed');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(popup, findsNothing);
    expect(current?.value, '42');

    await mouse.moveTo(editor + const Offset(125, 24));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField).last).controller!.text,
      '42',
    );
    await tester.tap(find.text('Restaurar'));
    await tester.pump();
    expect(current, isNull);
    await tester.tapAt(editor + const Offset(480, 220));
    await tester.pump();
    expect(popup, findsNothing);
    await mouse.removePointer();
  });

  testWidgets('hover de placeholder mostra popover interativo', (tester) async {
    final controller = CodeEditingController(
      text: 'GET {{value}}/items',
      language: 'http',
    );
    final focus = FocusNode();
    addTearDown(() {
      controller.dispose();
      focus.dispose();
    });
    await tester.pumpWidget(
      ShadcnApp(
        theme: buildTheme(brightness: Brightness.light),
        home: Scaffold(
          child: SizedBox(
            width: 500,
            height: 250,
            child: CodeEditor(
              controller: controller,
              focusNode: focus,
              variableNameAt: (offset) =>
                  offset >= 4 && offset < 13 ? 'value' : null,
              variablePopoverBuilder: (name) => Container(
                color: const Color(0xFFFFFFFF),
                child: Text('popover-$name'),
              ),
            ),
          ),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    final topLeft = tester.getTopLeft(find.byType(CodeEditor));
    await mouse.moveTo(topLeft + const Offset(125, 24));
    await tester.pump();
    expect(find.text('popover-value'), findsOneWidget);
    await mouse.moveTo(tester.getCenter(find.text('popover-value')));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('popover-value'), findsOneWidget);
    await mouse.moveTo(topLeft + const Offset(480, 220));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('popover-value'), findsNothing);
    await mouse.removePointer();
  });

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

  testWidgets('popup de script mostra assinatura e permite seleção', (
    tester,
  ) async {
    final controller = CodeEditingController(
      text: '< {% client.global.',
      language: 'http',
    );
    final focus = FocusNode();
    String? chosen;
    addTearDown(() {
      controller.dispose();
      focus.dispose();
    });
    await tester.pumpWidget(
      ShadcnApp(
        theme: buildTheme(brightness: Brightness.dark),
        home: Scaffold(
          child: SizedBox(
            width: 500,
            height: 300,
            child: CodeEditor(
              controller: controller,
              focusNode: focus,
              completionVisible: true,
              completionItems: const ['set', 'get'],
              completionDetails: const {
                'set': 'set(name, value)',
                'get': 'get(name)',
              },
              completionMethods: const {'set', 'get'},
              onCompletionSelected: (name) => chosen = name,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('set(name, value)'), findsOneWidget);
    await tester.tap(find.text('get'));
    expect(chosen, 'get');
  });
}
