@Tags(['preview'])
library;

import 'dart:io';

import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:cockpit/app/core/ui/menu/app_menu_bar.dart';
import 'package:cockpit/app/core/ui/menu/menu_model.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:flutter/services.dart' show FontLoader, LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// **Ferramenta de preview, não teste de regressão** — gera PNGs da barra de
/// título do Windows/Linux pra inspeção visual no mac (onde o app usa a barra
/// nativa e nunca desenha esta). Roda com:
///
///     flutter test --tags preview --run-skipped --update-goldens
///
/// Fica fora do `flutter test` normal (tag `preview` em dart_test.yaml): golden
/// depende da renderização de fonte da máquina e quebraria em CI.
///
/// As fontes reais (Space/Hanken Grotesk) vêm do `google_fonts` em runtime e não
/// existem offline; aqui a **Geist** (bundlada no shadcn) é registrada no lugar
/// delas só pra o texto sair legível. Geometria/espaçamento são fiéis; o
/// desenho da letra não é o de produção.
Future<void> _loadFonts() async {
  // Fonte custom nas settings → o AppTypography usa `TextStyle(fontFamily:)` e
  // NÃO chama o google_fonts (que precisaria de rede/asset). Registramos a Geist
  // bundlada no shadcn sob esse nome.
  final geist = File(
    '${_pubCache()}/shadcn_flutter-0.0.52/lib/fonts/Geist-Regular.otf',
  );
  final geistBytes = geist.readAsBytesSync().buffer.asByteData();
  await (FontLoader('Geist')..addFont(Future.value(geistBytes))).load();

  // Ícones do próprio shadcn (seta de submenu, checks): sem elas o glifo some
  // e vira caixinha.
  for (final icon in const [
    'icons/LucideIcons.ttf',
    'icons/RadixIcons.otf',
    'icons/BootstrapIcons.otf',
  ]) {
    final f = File('${_pubCache()}/shadcn_flutter-0.0.52/lib/$icon');
    if (!f.existsSync()) continue;
    final family = 'packages/shadcn_flutter/${icon.split('/').last.split('.').first}';
    final bytes = f.readAsBytesSync().buffer.asByteData();
    await (FontLoader(family)..addFont(Future.value(bytes))).load();
  }

  // Ícone do hambúrguer: fonte do Material que acompanha o SDK do Flutter.
  final icons = File(
    '${_flutterRoot()}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (icons.existsSync()) {
    final bytes = icons.readAsBytesSync().buffer.asByteData();
    await (FontLoader('MaterialIcons')..addFont(Future.value(bytes))).load();
  }
}

String _pubCache() =>
    '${Platform.environment['HOME']}/.pub-cache/hosted/pub.dev';

String _flutterRoot() {
  final exe = Platform.environment['FLUTTER_ROOT'];
  if (exe != null && exe.isNotEmpty) return exe;
  return '${Platform.environment['HOME']}/flutter';
}

/// Menus reais o suficiente pra medir a barra (mesmos rótulos do app).
List<MenuBarMenu> _menus() => <MenuBarMenu>[
  MenuBarMenu('Cockpit', <MenuNode>[
    MenuAction('Settings…', onSelected: () {}),
    MenuAction('Check for Updates…', onSelected: () {}),
  ]),
  MenuBarMenu('File', <MenuNode>[
    MenuAction('New Agent', onSelected: () {}),
    MenuAction('New Terminal', onSelected: () {}),
    const MenuSeparator(),
    MenuAction(
      'Open Workspace',
      accelerator: const MenuAccelerator(LogicalKeyboardKey.keyO),
      onSelected: () {},
    ),
    const MenuSeparator(),
    MenuAction(
      'Save',
      accelerator: const MenuAccelerator(LogicalKeyboardKey.keyS),
      onSelected: () {},
    ),
    const MenuAction('Discard'),
    const MenuAction('Format'),
  ]),
  MenuBarMenu('View', <MenuNode>[
    MenuAction(
      'Toggle Workspace Panel',
      accelerator: const MenuAccelerator(LogicalKeyboardKey.keyB),
      onSelected: () {},
    ),
    MenuAction('Toggle Files', onSelected: () {}),
    const MenuSeparator(),
    MenuAction('Split Right', onSelected: () {}),
    MenuAction('Split Down', onSelected: () {}),
  ]),
  const MenuBarMenu('Window', <MenuNode>[
    MenuRole(MenuBarRole.minimizeWindow),
    MenuRole(MenuBarRole.zoomWindow),
  ]),
];

/// Reproduz a faixa da barra de título do Windows: menu à esquerda, título no
/// meio, botões de janela à direita (é essa disputa por espaço que motivou o
/// hambúrguer). Os `_WinBtn` são só um stand-in visual dos controles nativos.
Widget _titleBar({required bool hamburger}) => Container(
  height: 40,
  color: const Color(0xFF121215),
  child: Row(
    children: [
      const SizedBox(width: 12),
      if (hamburger)
        WindowMenuBar(menus: _menus(), renderOnMacOS: true)
      else
        _LegacyBar(menus: _menus()),
      const SizedBox(width: 8),
      const Icon(Icons.view_sidebar_outlined, size: 16),
      const SizedBox(width: 8),
      const Text('remote_pi'),
      const Spacer(),
      const Icon(Icons.view_sidebar_outlined, size: 16),
      const SizedBox(width: 12),
      const _WinBtn(Icons.minimize),
      const _WinBtn(Icons.crop_square),
      const _WinBtn(Icons.close),
    ],
  ),
);

/// Como era ANTES: um botão por menu de topo (pra comparar lado a lado).
class _LegacyBar extends StatelessWidget {
  const _LegacyBar({required this.menus});
  final List<MenuBarMenu> menus;

  @override
  Widget build(BuildContext context) => Menubar(
    border: false,
    children: menus
        .map(
          (m) => MenuButton(
            subMenu: const <MenuItem>[],
            child: Text(m.label, style: context.typo.label.copyWith(fontSize: 13)),
          ),
        )
        .toList(growable: false),
  );
}

class _WinBtn extends StatelessWidget {
  const _WinBtn(this.icon);
  final IconData icon;

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: 46, height: 40, child: Icon(icon, size: 14));
}

/// Host = o mesmo empilhamento do `AppRoot`: ShadcnApp + CockpitTheme (que é a
/// origem do `context.typo` usado nos rótulos do menu). Sem o CockpitTheme o
/// fallback chamaria o google_fonts (rede) e o preview quebraria.
const _previewSettings = AppSettings(interfaceFont: 'Geist', codeFont: 'Geist');

Widget _host(Widget child) {
  final tokens = buildTokens(
    brightness: Brightness.dark,
    settings: _previewSettings,
  );
  return ShadcnApp(
    debugShowCheckedModeBanner: false,
    // windows: sem isto o preview mente — em teste o defaultTargetPlatform é
    // android e o shadcn desenha o menu como bottom sheet, não como o popover
    // ancorado que o Windows usa.
    theme: buildTheme(
      brightness: Brightness.dark,
      settings: _previewSettings,
    ).copyWith(platform: () => TargetPlatform.windows),
    home: CockpitTheme(
      colors: tokens.colors,
      typo: tokens.typo,
      syntax: tokens.syntax,
      child: Scaffold(child: Align(alignment: Alignment.topLeft, child: child)),
    ),
  );
}

void main() {
  setUpAll(_loadFonts);


  testWidgets('preview: barra fechada — antes (menus soltos) x depois (hambúrguer)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1800, 240);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 900,
          child: Column(
            children: [
              _titleBar(hamburger: false), // ANTES
              const SizedBox(height: 8),
              _titleBar(hamburger: true), // DEPOIS
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    await expectLater(
      find.byType(ShadcnApp),
      matchesGoldenFile('preview_titlebar_compare.png'),
    );
  });

  testWidgets('preview: popup aberto no hambúrguer', (tester) async {
    tester.view.physicalSize = const Size(2800, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(SizedBox(width: 1400, child: _titleBar(hamburger: true))));
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    await expectLater(
      find.byType(ShadcnApp),
      matchesGoldenFile('preview_titlebar_popup.png'),
    );
  });

  testWidgets('preview: submenu File aberto', (tester) async {
    tester.view.physicalSize = const Size(2800, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(SizedBox(width: 1400, child: _titleBar(hamburger: true))));
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.text('File'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    await expectLater(
      find.byType(ShadcnApp),
      matchesGoldenFile('preview_titlebar_submenu.png'),
    );
  });
}
