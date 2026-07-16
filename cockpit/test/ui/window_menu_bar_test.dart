import 'package:cockpit/app/core/ui/menu/app_menu_bar.dart';
import 'package:cockpit/app/core/ui/menu/menu_model.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Windows/Linux: o menu desenhado na barra de título é **um hambúrguer só** —
/// os menus de topo viram submenus dele (senão File/View/Window espremem o
/// título contra os botões de janela, que no Windows moram na mesma barra).
///
/// A suíte roda em macOS, onde o widget é um `SizedBox` por design → os testes
/// usam `renderOnMacOS: true` pra exercitar o renderer desenhado.
/// `platform: windows` é essencial: o `flutter_test` reporta **android**, e aí o
/// shadcn troca o popover ancorado por um bottom sheet
/// (`isMobile(theme.platform) ? SheetOverlayHandler() : PopoverOverlayHandler()`).
/// Sem isto o teste exercitaria um caminho que nenhum usuário de Windows vê.
Widget _host(Widget child) => ShadcnApp(
  theme: buildTheme(
    brightness: Brightness.dark,
  ).copyWith(platform: () => TargetPlatform.windows),
  home: Scaffold(child: Align(alignment: Alignment.topLeft, child: child)),
);

void main() {
  var newTerminalCalls = 0;

  List<MenuBarMenu> menus() => <MenuBarMenu>[
    MenuBarMenu('File', <MenuNode>[
      MenuAction('New Terminal', onSelected: () => newTerminalCalls++),
      const MenuSeparator(),
      const MenuAction('Save'), // onSelected null → desabilitado
    ]),
    const MenuBarMenu('View', <MenuNode>[MenuAction('Zoom In')]),
  ];

  setUp(() => newTerminalCalls = 0);

  testWidgets('mostra só o hambúrguer — nenhum menu de topo na barra', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(WindowMenuBar(menus: menus(), renderOnMacOS: true)),
    );

    expect(find.byIcon(Icons.menu), findsOneWidget);
    // O ganho: 'File'/'View' não ocupam mais a barra de título.
    expect(find.text('File'), findsNothing);
    expect(find.text('View'), findsNothing);
  });

  testWidgets('clique no hambúrguer abre o popup com os menus de topo', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(WindowMenuBar(menus: menus(), renderOnMacOS: true)),
    );

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('File'), findsOneWidget);
    expect(find.text('View'), findsOneWidget);
    // Só os pais: os itens-folha ficam um nível abaixo.
    expect(find.text('New Terminal'), findsNothing);
  });

  testWidgets('submenu aninhado abre e dispara a ação da folha', (tester) async {
    await tester.pumpWidget(
      _host(WindowMenuBar(menus: menus(), renderOnMacOS: true)),
    );

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    // Este é o caminho que a mudança estreia: MenuBarMenu dentro de subMenu.
    await tester.tap(find.text('File'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('New Terminal'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);

    await tester.tap(find.text('New Terminal'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(newTerminalCalls, 1);
  });

  testWidgets('no macOS não desenha nada (a barra é a nativa do SO)', (
    tester,
  ) async {
    await tester.pumpWidget(_host(WindowMenuBar(menus: menus())));

    expect(find.byIcon(Icons.menu), findsNothing);
  });
}
