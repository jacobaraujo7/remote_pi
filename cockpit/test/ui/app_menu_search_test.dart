import 'dart:async';

import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/app_menu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// `platform: windows` pela mesma razão do `window_menu_bar_test`: o
/// `flutter_test` se reporta como android e o shadcn trocaria o popover
/// ancorado por um bottom sheet, exercitando um caminho que ninguém vê no
/// desktop.
Future<BuildContext> _pumpHost(WidgetTester tester) async {
  late BuildContext captured;
  await tester.pumpWidget(
    ShadcnApp(
      theme: buildTheme(
        brightness: Brightness.dark,
      ).copyWith(platform: () => TargetPlatform.windows),
      home: Scaffold(
        child: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  return captured;
}

List<AppMenuItem<String>> _models(int count) => [
  for (var i = 0; i < count; i++)
    AppMenuItem<String>(value: 'model-$i', label: 'Model $i'),
];

void main() {
  testWidgets('lista longa mostra só os curados até alguém digitar', (
    tester,
  ) async {
    final context = await _pumpHost(tester);

    unawaited(
      showAppMenu<String>(
        context,
        items: _models(30),
        searchHint: 'Search among 30 models…',
        collapsedLimit: 12,
      ),
    );
    // O popover ancorado liga um ticker que segue o widget âncora a cada
    // frame, então `pumpAndSettle` nunca assenta — mesma razão pela qual o
    // `window_menu_bar_test` bombeia frames à mão.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    // Sem query: só os 12 primeiros. Rolar 30+ itens é pior que buscar.
    expect(find.text('Model 0'), findsOneWidget);
    expect(find.text('Model 11'), findsOneWidget);
    expect(find.text('Model 12'), findsNothing);
    expect(find.text('Search among 30 models…'), findsOneWidget);

    // Com query, a busca alcança a lista inteira — inclusive o que o corte
    // tinha escondido.
    await tester.enterText(find.byType(TextField), 'Model 27');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    // Pelo MenuButton, não por `find.text`: o próprio campo de busca agora
    // contém o texto digitado.
    expect(find.widgetWithText(MenuButton, 'Model 27'), findsOneWidget);
    expect(find.widgetWithText(MenuButton, 'Model 0'), findsNothing);
  });

  testWidgets('lista curta não ganha campo de busca', (tester) async {
    final context = await _pumpHost(tester);

    unawaited(
      showAppMenu<String>(
        context,
        items: _models(4),
        searchHint: 'Search among 4 models…',
        collapsedLimit: 12,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(TextField), findsNothing);
    expect(find.text('Model 3'), findsOneWidget);
  });
}
