@Tags(['preview'])
library;

import 'dart:async';
import 'dart:io';

import 'package:cockpit/app/cockpit/ui/widgets/clone_repository_dialog.dart';
import 'package:cockpit/app/cockpit/ui/widgets/git_process_dialog.dart';
import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/app_menu.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

String _pubCache() =>
    '${Platform.environment['HOME']}/.pub-cache/hosted/pub.dev';

String _flutterRoot() => Platform.environment['FLUTTER_ROOT'] ?? '';

Future<void> _font(String family, String path, [List<String>? more]) async {
  final loader = FontLoader(family);
  for (final file in [path, ...?more]) {
    final f = File(file);
    if (!f.existsSync()) continue;
    loader.addFont(Future.value(f.readAsBytesSync().buffer.asByteData()));
  }
  await loader.load();
}

Future<void> _loadFonts() async {
  final shadcn = '${_pubCache()}/shadcn_flutter-0.0.52/lib';
  final sans = [
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold'])
      '$shadcn/fonts/Geist-$w.otf',
  ];
  final mono = [
    for (final w in ['Regular', 'Medium', 'SemiBold'])
      '$shadcn/fonts/GeistMono-$w.otf',
  ];
  for (final family in ['Geist', 'packages/shadcn_flutter/GeistSans']) {
    await _font(family, sans.first, sans.skip(1).toList());
  }
  for (final family in ['GeistMono', 'packages/shadcn_flutter/GeistMono']) {
    await _font(family, mono.first, mono.skip(1).toList());
  }
  for (final icon in const [
    'icons/LucideIcons.ttf',
    'icons/RadixIcons.otf',
    'icons/BootstrapIcons.otf',
  ]) {
    final family =
        'packages/shadcn_flutter/${icon.split('/').last.split('.').first}';
    await _font(family, '$shadcn/$icon');
  }
  await _font(
    'MaterialIcons',
    '${_flutterRoot()}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
}

const _settings = AppSettings(interfaceFont: 'Geist', codeFont: 'GeistMono');

Widget _host(Widget child) {
  final tokens = buildTokens(brightness: Brightness.dark, settings: _settings);
  return TranslationProvider(
    child: ShadcnApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(
        brightness: Brightness.dark,
        settings: _settings,
      ).copyWith(platform: () => TargetPlatform.macOS),
      // No builder (acima do Navigator), igual ao app: dialogs e menus abrem
      // em rotas próprias e precisam enxergar o CockpitTheme.
      builder: (context, nav) => CockpitTheme(
        colors: tokens.colors,
        typo: tokens.typo,
        syntax: tokens.syntax,
        terminal: tokens.terminal,
        child: nav ?? const SizedBox.shrink(),
      ),
      home: Scaffold(child: child),
    ),
  );
}

/// Faixa do topo da rail de Workspaces, igual à do app.
class _RailHeader extends StatelessWidget {
  const _RailHeader();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tr = context.t.cockpit.remoteHost;
    return Align(
      alignment: Alignment.topLeft,
      child: Container(
        width: 300,
        height: 600,
        decoration: BoxDecoration(
          color: colors.bg,
          border: Border(right: BorderSide(color: colors.border)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
        alignment: Alignment.topLeft,
        child: Row(
          children: [
            Icon(Icons.layers_outlined, size: 16, color: colors.text2),
            const SizedBox(width: 9),
            Text(
              context.t.cockpit.projectsRail.workspaces,
              style: context.typo.title.copyWith(color: colors.text),
            ),
            const Spacer(),
            Builder(
              builder: (btn) => GestureDetector(
                key: const ValueKey('plus'),
                onTap: () => showAppMenu<String>(
                  btn,
                  items: [
                    AppMenuItem(
                      value: 'local',
                      label: tr.newLocal,
                      icon: Icons.folder_outlined,
                    ),
                    AppMenuItem(
                      value: 'remote',
                      label: tr.newRemote,
                      icon: Icons.cloud_outlined,
                    ),
                    AppMenuItem(
                      value: 'clone',
                      label: context.t.cockpit.cloneRepoDialog.menuItem,
                      icon: Icons.download_outlined,
                    ),
                  ],
                ),
                child: Icon(Icons.add, size: 16, color: colors.text2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  late Directory parent;

  setUpAll(() async {
    await _loadFonts();
    LocaleSettings.setLocale(AppLocale.ptBr);
    parent = Directory('${Directory.systemTemp.path}/Projetos')
      ..createSync(recursive: true);
  });

  void size(WidgetTester tester, Size s) {
    tester.view.physicalSize = s * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
  }

  testWidgets('1 menu do +', (tester) async {
    size(tester, const Size(520, 260));
    await tester.pumpWidget(_host(const _RailHeader()));
    await tester.tap(find.byKey(const ValueKey('plus')));
    await _settle(tester);
    await expectLater(
      find.byType(ShadcnApp),
      matchesGoldenFile('previews/clone_1_menu.png'),
    );
  });

  Future<void> openDialog(WidgetTester tester, String? clipboard) async {
    size(tester, const Size(760, 520));
    await tester.pumpWidget(_host(const SizedBox.expand()));
    unawaited(
      showCloneRepositoryDialog(
        tester.element(find.byType(SizedBox).last),
        initialParent: parent.path,
        clipboardText: () async => clipboard,
      ),
    );
    await _settle(tester);
  }

  testWidgets('2 dialog com URL do clipboard', (tester) async {
    await openDialog(tester, 'git@github.com:jacobaraujo7/remote_pi.git');
    await _settle(tester);
    await expectLater(
      find.byType(ShadcnApp),
      matchesGoldenFile('previews/clone_2_dialog.png'),
    );
  });

  testWidgets('3 dialog com erros de validação', (tester) async {
    await openDialog(tester, null);
    await tester.enterText(
      find.byKey(const ValueKey('clone-url')),
      'github.com/repo',
    );
    await tester.tap(find.text('Clonar'));
    await _settle(tester);
    await expectLater(
      find.byType(ShadcnApp),
      matchesGoldenFile('previews/clone_3_errors.png'),
    );
  });

  testWidgets('4 progresso do clone', (tester) async {
    size(tester, const Size(760, 520));
    final out = StreamController<String>();
    final done = Completer<bool>();
    await tester.pumpWidget(_host(const SizedBox.expand()));
    final ctx = tester.element(find.byType(SizedBox).last);
    unawaited(
      showGitProcessDialog(
        ctx,
        title: ctx.t.cockpit.cloneRepoDialog.progressTitle(name: 'remote_pi'),
        output: out.stream,
        success: done.future,
      ),
    );
    await _settle(tester);
    for (final l in [
      r'$ git clone git@github.com:jacobaraujo7/remote_pi.git',
      "Cloning into '${parent.path}/remote_pi'...",
      'remote: Enumerating objects: 48211, done.',
      'remote: Counting objects:  40% (1928/4820)',
      'remote: Counting objects: 100% (4820/4820), done.',
      'Receiving objects:  30% (14464/48211), 21.4 MiB | 9.8 MiB/s',
      'Receiving objects:  70% (33748/48211), 52.0 MiB | 10.1 MiB/s',
      'Receiving objects: 100% (48211/48211), 74.3 MiB | 10.2 MiB/s, done.',
      'Resolving deltas: 100% (31877/31877), done.',
    ]) {
      out.add(l);
    }
    done.complete(true);
    await _settle(tester);
    await expectLater(
      find.byType(ShadcnApp),
      matchesGoldenFile('previews/clone_4_progress.png'),
    );
    unawaited(out.close());
  });
}
