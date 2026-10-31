@Tags(['preview'])
library;

import 'dart:async';
import 'dart:io';

import 'package:cockpit/app/cockpit/domain/contracts/dismissed_update_store.dart';
import 'package:cockpit/app/cockpit/domain/contracts/self_updater.dart';
import 'package:cockpit/app/cockpit/domain/contracts/update_checker.dart';
import 'package:cockpit/app/cockpit/domain/contracts/url_opener.dart';
import 'package:cockpit/app/cockpit/domain/entities/git_info.dart';
import 'package:cockpit/app/cockpit/domain/entities/project.dart';
import 'package:cockpit/app/cockpit/domain/entities/realm.dart';
import 'package:cockpit/app/cockpit/domain/entities/update_info.dart';
import 'package:cockpit/app/cockpit/domain/value_objects/update_target.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/update_viewmodel.dart';
import 'package:cockpit/app/cockpit/ui/widgets/projects_rail.dart';
import 'package:cockpit/app/cockpit/ui/widgets/workspace_settings_dialog.dart'
    show kWorkspacePalette;
import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:cockpit/app/core/ui/keep_awake_controller.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:cockpit_keepawake/cockpit_keepawake.dart'
    show UnsupportedKeepAwake;
import 'package:flutter_modular/flutter_modular.dart';
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
///
/// Premissa da proposta: o clone em um clique roda
/// `gh repo clone <owner>/<repo> <pasta>`, com o login que o `gh` já tem.
/// As telas 6 e 8 usam a [ProjectsRail] real; o resto é mock local.

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

enum _Mode { loading, list, noCli }

/// Plataforma do mockup: muda a pasta padrão e o jeito de instalar o `gh`.
enum _Platform {
  macos('~/Projetos'),
  windows(r'C:\Users\rafgl\Projetos');

  const _Platform(this.projectsDir);

  final String projectsDir;

  String target(String repo) =>
      this == _Platform.windows ? '$projectsDir\\$repo' : '$projectsDir/$repo';
}

/// Falha de clone mostrada na linha do repo.
typedef _RowError = ({String message, String detail});

// ---------------------------------------------------------------------------
// Mockup do dialog
// ---------------------------------------------------------------------------

class _MyReposDialog extends StatelessWidget {
  const _MyReposDialog({
    required this.mode,
    this.query = '',
    this.cloning,
    this.cloningProgress = 0,
    this.errors = const {},
    this.platform = _Platform.macos,
  });

  final _Mode mode;
  final String query;
  final String? cloning;
  final double cloningProgress;
  final Map<String, _RowError> errors;
  final _Platform platform;

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
            switch (mode) {
              _Mode.noCli => _NoCli(platform: platform),
              _Mode.loading => const _Loading(),
              _Mode.list => _RepoBrowser(
                query: query,
                cloning: cloning,
                progress: cloningProgress,
                errors: errors,
                platform: platform,
              ),
            },
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
    required this.errors,
    required this.platform,
  });

  final String query;
  final String? cloning;
  final double progress;
  final Map<String, _RowError> errors;
  final _Platform platform;

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
                    error: errors[r.name],
                    platform: platform,
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
              platform.projectsDir,
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
    this.error,
    this.platform = _Platform.macos,
  });

  final _Repo repo;
  final String query;
  final bool cloning;
  final double progress;
  final _RowError? error;
  final _Platform platform;

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
      color: cloning || error != null ? colors.panel2 : null,
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
              else if (error != null)
                PrimaryButton(
                  size: ButtonSize.small,
                  onPressed: () {},
                  leading: const Icon(Icons.refresh, size: 14),
                  child: const Text('Tentar de novo'),
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
                'Já clonado em ${platform.target(repo.name)}',
                style: context.typo.mono.copyWith(
                  fontSize: 10.5,
                  color: colors.text3,
                ),
              ),
            ),
          if (error case final e?) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 25),
              child: Row(
                children: [
                  Icon(Icons.error_outline, size: 14, color: colors.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      e.message,
                      style: context.typo.label.copyWith(color: colors.error),
                    ),
                  ),
                  GhostButton(
                    size: ButtonSize.small,
                    onPressed: () {},
                    child: const Text('Ver detalhes'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 25, top: 2),
              child: Text(
                e.detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.typo.mono.copyWith(
                  fontSize: 10.5,
                  color: colors.text3,
                ),
              ),
            ),
          ],
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
                  Text(
                    'Recebendo objetos ${(progress * 100).round()}% · 38.2 MiB',
                    style: meta,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '\$ gh repo clone ${repo.owner}/${repo.name} '
                    '${platform.target(repo.name)}',
                    style: context.typo.mono.copyWith(
                      fontSize: 10.5,
                      color: colors.text2,
                    ),
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
  const _NoCli({this.platform = _Platform.macos});

  final _Platform platform;

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
          Flexible(
            child: Text(
              note,
              style: context.typo.label.copyWith(color: colors.text3),
            ),
          ),
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
          if (platform == _Platform.windows)
            cmd(
              'winget install --id GitHub.cli',
              'se ainda não tiver o gh (ou o instalador de cli.github.com)',
            )
          else
            cmd('brew install gh', 'se ainda não tiver o gh'),
          cmd('gh auth login', 'entra na sua conta do GitHub'),
          const SizedBox(height: 8),
          Text(
            'Os clones vão para ${platform.projectsDir}.',
            style: context.typo.label.copyWith(color: colors.text3),
          ),
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

/// Tela 5: lista carregando (o `gh repo list` está rodando).
class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    Widget bar(double w, double h) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: colors.panel3,
        borderRadius: BorderRadius.circular(4),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          enabled: false,
          placeholder: const Text('Buscar repositórios…'),
          features: const [InputFeature.leading(Icon(Icons.search, size: 16))],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                value: 0.3,
                size: 12,
                color: colors.accent,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Buscando seus repositórios no GitHub…',
              style: context.typo.label.copyWith(color: colors.text2),
            ),
            const Spacer(),
            Text(
              'gh repo list',
              style: context.typo.mono.copyWith(
                fontSize: 10.5,
                color: colors.text3,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          decoration: BoxDecoration(
            color: colors.panel,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              bar(90, 10),
              const SizedBox(height: 12),
              for (final w in const [140.0, 110.0, 170.0, 125.0, 150.0])
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    children: [
                      bar(15, 15),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            bar(w, 12),
                            const SizedBox(height: 6),
                            bar(w + 120, 9),
                          ],
                        ),
                      ),
                      bar(78, 28),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Tela 9 — **variante da decisão 2 da #278** ("pasta padrão: perguntar no
/// primeiro uso"): aparece só antes do primeiro clone em um clique.
class _FirstFolderDialog extends StatelessWidget {
  const _FirstFolderDialog();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AlertDialog(
      title: Text(
        'Onde clonar seus repositórios?',
        style: context.typo.title.copyWith(fontSize: 15, color: colors.text),
      ),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cada clone em um clique vira uma pasta aqui dentro, com o nome '
              'do repositório (gh repo clone owner/repo <pasta>).',
              style: context.typo.body.copyWith(color: colors.text2),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.accentSoft,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.accent),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.radio_button_checked,
                    size: 16,
                    color: colors.accent,
                  ),
                  const SizedBox(width: 10),
                  Icon(Icons.folder_outlined, size: 16, color: colors.text2),
                  const SizedBox(width: 8),
                  Text(
                    '~/Projetos',
                    style: context.typo.mono.copyWith(
                      fontSize: 13,
                      color: colors.text,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'sugerida',
                    style: context.typo.label.copyWith(
                      color: colors.accentText,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            OutlineButton(
              size: ButtonSize.small,
              onPressed: () {},
              leading: const Icon(Icons.drive_folder_upload_outlined, size: 14),
              child: const Text('Escolher outra pasta…'),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(Icons.info_outline, size: 13, color: colors.text3),
                const SizedBox(width: 6),
                Text(
                  'Dá pra mudar depois em Configurações.',
                  style: context.typo.label.copyWith(color: colors.text3),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        OutlineButton(onPressed: () {}, child: Text(context.t.common.cancel)),
        PrimaryButton(
          onPressed: () {},
          child: const Text('Usar ~/Projetos e clonar'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Janela com a ProjectsRail real (telas 6 e 8)
// ---------------------------------------------------------------------------

class _NoUpdateChecker implements UpdateChecker {
  @override
  Future<UpdateInfo?> fetchLatest() async => null;
}

class _NoDismissStore implements DismissedUpdateStore {
  @override
  String? dismissedVersion() => null;
  @override
  Future<void> dismiss(String version) async {}
}

class _NoUrlOpener implements UrlOpener {
  @override
  Future<bool> open(String url) async => true;
}

class _NoSelfUpdater implements SelfUpdater {
  @override
  bool get isSupported => false;
  @override
  SelfUpdateState get state => const SelfUpdateState.idle();
  @override
  Stream<SelfUpdateState> get changes => const Stream.empty();
  @override
  Future<void> initialize() async {}
  @override
  Future<void> checkForUpdates({bool inBackground = true}) async {}
  @override
  Future<void> applyUpdate() async {}
  @override
  void dispose() {}
}

UpdateViewModel _fakeUpdateVm() => UpdateViewModel(
  _NoUpdateChecker(),
  _NoDismissStore(),
  _NoUrlOpener(),
  const UpdateTarget(
    version: '1.0.0',
    platform: 'macos',
    format: 'dmg',
    arch: 'arm64',
  ),
  _NoSelfUpdater(),
);

final _realm = Realm(
  id: Realm.defaultId,
  name: 'Default',
  createdAt: DateTime.utc(2026),
);

Project _ws(String id, String name, int order) => Project(
  id: id,
  name: name,
  path: '/Users/rafgl/Projetos/$name',
  // Cada workspace novo pega a próxima cor da paleta (como no app).
  colorValue: kWorkspacePalette[order % kWorkspacePalette.length],
  createdAt: DateTime.utc(2026),
  order: order,
);

/// Workspaces que já existiam + (opcional) o recém-clonado no fim.
List<Project> _workspaces({required bool withBillingApi}) => [
  _ws('ws-remote-pi', 'remote_pi', 0),
  _ws('ws-site', 'site-pessoal', 1),
  if (withBillingApi) _ws('ws-billing-api', 'billing-api', 2),
];

/// Área principal mínima: cabeçalho do workspace + estado vazio.
class _MainArea extends StatelessWidget {
  const _MainArea({required this.project, this.toast});

  final Project project;
  final String? toast;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Stack(
      children: [
        Column(
          children: [
            Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: colors.panel,
                border: Border(bottom: BorderSide(color: colors.border)),
              ),
              child: Row(
                children: [
                  Text(
                    project.name,
                    style: context.typo.title.copyWith(color: colors.text),
                  ),
                  const SizedBox(width: 10),
                  Icon(Icons.call_split, size: 13, color: colors.text3),
                  const SizedBox(width: 4),
                  Text(
                    'main',
                    style: context.typo.mono.copyWith(
                      fontSize: 11,
                      color: colors.text2,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '~/Projetos/${project.name}',
                    style: context.typo.mono.copyWith(
                      fontSize: 11,
                      color: colors.text3,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.terminal, size: 28, color: colors.text4),
                    const SizedBox(height: 10),
                    Text(
                      'Abra um terminal ou um agente em ${project.name}',
                      style: context.typo.body.copyWith(color: colors.text3),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        // Toast estático no estilo do `_toast` do app (SurfaceCard no canto
        // inferior direito); o showToast real anima e deixaria timer pendente.
        if (toast != null)
          Positioned(
            right: 16,
            bottom: 16,
            child: SurfaceCard(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 18,
                      color: colors.ok,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      toast!,
                      style: context.typo.label.copyWith(color: colors.text),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Janela do Cockpit: [ProjectsRail] real à esquerda + [_MainArea].
Widget _window({
  required List<Project> projects,
  required String selectedId,
  String? toast,
}) {
  final tokens = buildTokens(brightness: Brightness.dark, settings: _settings);
  final selected = projects.firstWhere((p) => p.id == selectedId);
  final feature = createModule(
    path: '/',
    register: (c) => c.route(
      '/',
      child: (context, state) => Scaffold(
        child: Row(
          children: [
            ProjectsRail(
              projects: projects,
              worktreesOf: (_) => const [],
              worktreesExpanded: (_) => false,
              onWorktreesExpanded: (_, _) {},
              selectedId: selectedId,
              notificationCounts: const {},
              gitInfo: (_) => const GitInfo(branch: 'main'),
              rootsSummary: (_) => (1, 0),
              rootsOf: (id) => [
                (
                  path: projects.firstWhere((p) => p.id == id).path,
                  name: projects.firstWhere((p) => p.id == id).name,
                  git: const GitInfo(branch: 'main'),
                ),
              ],
              forkOriginName: (_) => null,
              onSelect: (_) {},
              onAdd: () async => true,
              onConfigure: (_) {},
              onDelete: (_) {},
              onCreateWorktree: (_, _) {},
              onRemoveWorktree: (_) {},
              onMergeWorktree: (_) {},
              onUpdateWorktree: (_) {},
              onForkWorktree: (_) {},
              onSync: (_, _) {},
              onPull: (_, _) {},
              onPush: (_, _) {},
              onOpenSettings: () {},
              onReorder: (_, _, _) {},
              realms: [_realm],
              activeRealm: _realm,
              onSwitchRealm: (_) {},
              onCreateRealm: () {},
              onManageRealms: () {},
              moveTargetsOf: (_) => const [],
              onMoveToRealm: (_, _) {},
              onSelectCockpit: () {},
              onNewWorkspace: (_) {},
              onSelectRemote: (_) {},
              remoteGitInfoOf: (_) => null,
              onRemoteWorkspaceAction: (_, _) {},
            ),
            Expanded(
              child: _MainArea(project: selected, toast: toast),
            ),
          ],
        ),
      ),
    ),
  );
  return TranslationProvider(
    child: ModularApp(
      module: createModule(register: (c) => c.module(feature)),
      provide: (s) => s
        ..addChangeNotifier<UpdateViewModel>(_fakeUpdateVm)
        ..addChangeNotifier<KeepAwakeController>(
          () => KeepAwakeController(keepAwake: const UnsupportedKeepAwake()),
        ),
      child: Builder(
        builder: (context) => ShadcnApp.router(
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
          routerConfig: ModularApp.routerConfigOf(context),
        ),
      ),
    ),
  );
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

  testWidgets('4b sem gh (Windows)', (tester) async {
    await shot(
      tester,
      const _MyReposDialog(mode: _Mode.noCli, platform: _Platform.windows),
      'clone_my_repos_4b_no_cli_windows.png',
      height: 560,
    );
  });

  testWidgets('5 carregando', (tester) async {
    await shot(
      tester,
      const _MyReposDialog(mode: _Mode.loading),
      'clone_my_repos_5_loading.png',
      height: 640,
    );
  });

  Future<void> windowShot(WidgetTester tester, Widget app, String file) async {
    tester.view.physicalSize = const Size(1100, 640) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app);
    await _settle(tester);
    await expectLater(
      find.byType(ShadcnApp),
      matchesGoldenFile('previews/$file'),
    );
  }

  testWidgets('6 workspace criado', (tester) async {
    await windowShot(
      tester,
      _window(
        projects: _workspaces(withBillingApi: true),
        selectedId: 'ws-billing-api',
        toast: 'billing-api clonado em ~/Projetos/billing-api',
      ),
      'clone_my_repos_6_done.png',
    );
  });

  testWidgets('7 erro na linha', (tester) async {
    await shot(
      tester,
      const _MyReposDialog(
        mode: _Mode.list,
        query: 'acme-labs/',
        errors: {
          'infra': (
            message: 'Sem permissão para acme-labs/infra',
            detail:
                'gh repo clone acme-labs/infra: HTTP 404 · confira o acesso '
                'à org em github.com/acme-labs',
          ),
          'billing-web': (
            message:
                'A pasta ~/Projetos/billing-web já existe e não está vazia',
            detail:
                "fatal: destination path '~/Projetos/billing-web' already "
                'exists and is not an empty directory.',
          ),
        },
      ),
      'clone_my_repos_7_error.png',
      height: 820,
    );
  });

  testWidgets('8 abrir já clonado', (tester) async {
    await windowShot(
      tester,
      _window(
        projects: _workspaces(withBillingApi: false),
        selectedId: 'ws-remote-pi',
      ),
      'clone_my_repos_8_open.png',
    );
  });

  // Variante da decisão 2 da #278: perguntar a pasta no primeiro uso.
  testWidgets('9 primeira pasta (decisão 2)', (tester) async {
    await shot(
      tester,
      const _FirstFolderDialog(),
      'clone_my_repos_9_first_folder.png',
      height: 560,
    );
  });
}
