@Tags(['preview'])
library;

import 'dart:async';
import 'dart:io';

import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// **Mockup, não feature** — ilustra a proposta da issue #278 (aba "Meus
/// repositórios" no dialog de clone). Nada aqui existe em `lib/`: os widgets
/// são locais ao teste e os textos são literais de propósito. Roda com:
///
///     flutter test test/ui/clone_my_repos_preview_test.dart --tags preview --run-skipped --update-goldens
///
/// Mesmo host/fontes do `clone_repo_preview_test.dart` (Geist no lugar das
/// fontes de produção, que precisam de rede em teste).

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

// ---------------------------------------------------------------------------
// Dados fictícios
// ---------------------------------------------------------------------------

class _Repo {
  const _Repo(
    this.owner,
    this.name,
    this.updated, {
    this.private = false,
    this.cloned = false,
    this.description,
  });

  final String owner;
  final String name;
  final String updated;
  final bool private;
  final bool cloned;
  final String? description;
}

const _repos = <_Repo>[
  _Repo(
    'rafgl',
    'remote_pi',
    'há 2 horas',
    cloned: true,
    description: 'Fork do Remote Pi',
  ),
  _Repo('rafgl', 'dotfiles', 'há 3 dias', private: true),
  _Repo('rafgl', 'flutter-playground', 'há 2 semanas'),
  _Repo(
    'acme-labs',
    'billing-api',
    'há 40 minutos',
    private: true,
    description: 'Cobrança e faturas (Rust)',
  ),
  _Repo(
    'acme-labs',
    'billing-web',
    'ontem',
    private: true,
    description: 'Painel de cobrança (Next.js)',
  ),
  _Repo('acme-labs', 'design-system', 'há 5 dias'),
  _Repo('acme-labs', 'infra', 'há 1 mês', private: true),
];

enum _Mode { list, noCli }

// ---------------------------------------------------------------------------
// Mockup do dialog
// ---------------------------------------------------------------------------

class _MyReposDialog extends StatelessWidget {
  const _MyReposDialog({
    required this.mode,
    this.query = '',
    this.cloning,
    this.cloningProgress = 0,
  });

  final _Mode mode;
  final String query;
  final String? cloning;
  final double cloningProgress;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AlertDialog(
      title: Text(
        'Clonar repositório Git',
        style: context.typo.title.copyWith(fontSize: 15, color: colors.text),
      ),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Tabs(),
            const SizedBox(height: 14),
            if (mode == _Mode.noCli)
              const _NoCli()
            else
              _RepoBrowser(
                query: query,
                cloning: cloning,
                progress: cloningProgress,
              ),
          ],
        ),
      ),
      actions: [
        OutlineButton(onPressed: () {}, child: Text(context.t.common.close)),
      ],
    );
  }
}

/// "Colar URL" | "Meus repositórios" (esta ativa) — mesmo estilo de chip do
/// seletor de auth do dialog de host remoto.
class _Tabs extends StatelessWidget {
  const _Tabs();

  @override
  Widget build(BuildContext context) => Row(
    children: [
      OutlineButton(
        size: ButtonSize.small,
        onPressed: () {},
        leading: const Icon(Icons.link, size: 14),
        child: const Text('Colar URL'),
      ),
      const SizedBox(width: 8),
      PrimaryButton(
        size: ButtonSize.small,
        onPressed: () {},
        leading: const Icon(Icons.inventory_2_outlined, size: 14),
        child: const Text('Meus repositórios'),
      ),
    ],
  );
}

class _RepoBrowser extends StatelessWidget {
  const _RepoBrowser({
    required this.query,
    required this.cloning,
    required this.progress,
  });

  final String query;
  final String? cloning;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final q = query.toLowerCase();
    final visible = [
      for (final r in _repos)
        if (q.isEmpty || '${r.owner}/${r.name}'.toLowerCase().contains(q)) r,
    ];
    final owners = [
      for (final r in visible)
        if (visible.indexOf(r) == visible.indexWhere((x) => x.owner == r.owner))
          r.owner,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: TextEditingController(text: query),
          placeholder: const Text('Buscar repositórios…'),
          features: const [InputFeature.leading(Icon(Icons.search, size: 16))],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(Icons.check_circle, size: 12, color: colors.online),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'github.com · logado como rafgl (gh)',
                style: context.typo.label.copyWith(color: colors.text3),
              ),
            ),
            Text(
              q.isEmpty
                  ? '${_repos.length} repositórios'
                  : '${visible.length} de ${_repos.length}',
              style: context.typo.label.copyWith(color: colors.text3),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: colors.panel,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            children: [
              for (final owner in owners) ...[
                _OwnerHeader(owner: owner, first: owner == owners.first),
                for (final r in visible.where((r) => r.owner == owner))
                  _RepoRow(
                    repo: r,
                    query: q,
                    cloning: r.name == cloning,
                    progress: progress,
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(Icons.folder_outlined, size: 14, color: colors.text3),
            const SizedBox(width: 6),
            Text(
              'Clona em ',
              style: context.typo.label.copyWith(color: colors.text3),
            ),
            Text(
              '~/Projetos',
              style: context.typo.mono.copyWith(
                fontSize: 11,
                color: colors.text2,
              ),
            ),
            const Spacer(),
            GhostButton(
              size: ButtonSize.small,
              onPressed: () {},
              child: const Text('Alterar…'),
            ),
          ],
        ),
      ],
    );
  }
}

class _OwnerHeader extends StatelessWidget {
  const _OwnerHeader({required this.owner, required this.first});

  final String owner;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final org = owner != 'rafgl';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      decoration: BoxDecoration(
        border: first ? null : Border(top: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Icon(
            org ? Icons.apartment_outlined : Icons.person_outline,
            size: 13,
            color: colors.text3,
          ),
          const SizedBox(width: 6),
          Text(
            org ? '$owner · organização' : '$owner · você',
            style: context.typo.label.copyWith(
              color: colors.text3,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _RepoRow extends StatelessWidget {
  const _RepoRow({
    required this.repo,
    required this.query,
    required this.cloning,
    required this.progress,
  });

  final _Repo repo;
  final String query;
  final bool cloning;
  final double progress;

  /// Nome com o trecho buscado destacado.
  Widget _name(BuildContext context) {
    final colors = context.colors;
    final base = context.typo.body.copyWith(
      color: colors.text,
      fontWeight: FontWeight.w600,
    );
    final i = query.isEmpty ? -1 : repo.name.toLowerCase().indexOf(query);
    if (i < 0) return Text(repo.name, style: base);
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(text: repo.name.substring(0, i)),
          TextSpan(
            text: repo.name.substring(i, i + query.length),
            style: base.copyWith(
              color: colors.accentText,
              backgroundColor: colors.accentSoft,
            ),
          ),
          TextSpan(text: repo.name.substring(i + query.length)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final meta = context.typo.label.copyWith(color: colors.text3);
    return Container(
      color: cloning ? colors.panel2 : null,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                repo.private ? Icons.lock_outline : Icons.book_outlined,
                size: 15,
                color: colors.text3,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _name(context),
                        if (repo.private) ...[
                          const SizedBox(width: 6),
                          _Badge('privado'),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        repo.owner,
                        if (repo.description != null) repo.description!,
                        'atualizado ${repo.updated}',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: meta,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (cloning)
                OutlineButton(
                  size: ButtonSize.small,
                  onPressed: () {},
                  child: const Text('Cancelar'),
                )
              else if (repo.cloned)
                OutlineButton(
                  size: ButtonSize.small,
                  onPressed: () {},
                  leading: Icon(Icons.check, size: 14, color: colors.online),
                  child: const Text('Abrir'),
                )
              else
                PrimaryButton(
                  size: ButtonSize.small,
                  onPressed: () {},
                  leading: const Icon(Icons.download_outlined, size: 14),
                  child: const Text('Clonar'),
                ),
            ],
          ),
          if (repo.cloned && !cloning)
            Padding(
              padding: const EdgeInsets.only(left: 25, top: 4),
              child: Text(
                'Já clonado em ~/Projetos/${repo.name}',
                style: context.typo.mono.copyWith(
                  fontSize: 10.5,
                  color: colors.text3,
                ),
              ),
            ),
          if (cloning) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 25),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: SizedBox(
                      height: 6,
                      child: Stack(
                        children: [
                          Container(color: colors.panel3),
                          FractionallySizedBox(
                            widthFactor: progress,
                            child: Container(color: colors.accent),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        'Recebendo objetos ${(progress * 100).round()}% · 38.2 MiB',
                        style: meta,
                      ),
                      const Spacer(),
                      Text(
                        '→ ~/Projetos/${repo.name}',
                        style: context.typo.mono.copyWith(
                          fontSize: 10.5,
                          color: colors.text2,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.border2),
      ),
      child: Text(
        text,
        style: context.typo.label.copyWith(fontSize: 10, color: colors.text3),
      ),
    );
  }
}

/// Estado sem `gh` instalado ou sem login.
class _NoCli extends StatelessWidget {
  const _NoCli();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    Widget cmd(String text, String note) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: colors.panel3,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              text,
              style: context.typo.mono.copyWith(
                fontSize: 12,
                color: colors.text,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(note, style: context.typo.label.copyWith(color: colors.text3)),
        ],
      ),
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.terminal, size: 18, color: colors.warn),
              const SizedBox(width: 8),
              Text(
                'GitHub CLI não encontrado ou sem login',
                style: context.typo.title.copyWith(color: colors.text),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'A lista usa o gh que já está na sua máquina. O Cockpit não pede '
            'nem guarda token. Rode no terminal:',
            style: context.typo.body.copyWith(color: colors.text2),
          ),
          const SizedBox(height: 4),
          cmd('brew install gh', 'se ainda não tiver o gh'),
          cmd('gh auth login', 'entra na sua conta do GitHub'),
          const SizedBox(height: 14),
          Row(
            children: [
              PrimaryButton(
                size: ButtonSize.small,
                onPressed: () {},
                leading: const Icon(Icons.refresh, size: 14),
                child: const Text('Tentar de novo'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Colar a URL na aba "Colar URL" continua funcionando.',
                  style: context.typo.label.copyWith(color: colors.text3),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUpAll(() async {
    await _loadFonts();
    LocaleSettings.setLocale(AppLocale.ptBr);
  });

  Future<void> shot(
    WidgetTester tester,
    Widget dialog,
    String file, {
    double height = 840,
  }) async {
    tester.view.physicalSize = Size(820, height) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(const SizedBox.expand()));
    unawaited(
      showDialog<void>(
        context: tester.element(find.byType(SizedBox).last),
        barrierColor: tester.element(find.byType(SizedBox).last).colors.scrim,
        builder: (_) => dialog,
      ),
    );
    await _settle(tester);
    await expectLater(
      find.byType(ShadcnApp),
      matchesGoldenFile('previews/$file'),
    );
  }

  testWidgets('1 lista', (tester) async {
    await shot(
      tester,
      const _MyReposDialog(mode: _Mode.list),
      'clone_my_repos_1_list.png',
    );
  });

  testWidgets('2 busca', (tester) async {
    await shot(
      tester,
      const _MyReposDialog(mode: _Mode.list, query: 'billing'),
      'clone_my_repos_2_search.png',
      height: 560,
    );
  });

  testWidgets('3 clonando', (tester) async {
    await shot(
      tester,
      const _MyReposDialog(
        mode: _Mode.list,
        cloning: 'billing-api',
        cloningProgress: 0.62,
      ),
      'clone_my_repos_3_cloning.png',
      height: 920,
    );
  });

  testWidgets('4 sem gh', (tester) async {
    await shot(
      tester,
      const _MyReposDialog(mode: _Mode.noCli),
      'clone_my_repos_4_no_cli.png',
      height: 520,
    );
  });
}
