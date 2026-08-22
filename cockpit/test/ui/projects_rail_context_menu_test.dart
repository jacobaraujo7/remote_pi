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
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind, kSecondaryButton;
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// O rodapé da rail tem um [UpdateCard] que faz `context.watch<UpdateViewModel>()`.
/// Estes fakes existem só pra o escopo resolver — sem update pendente, o card
/// vira `SizedBox.shrink()` e não interfere em nada do que é testado aqui.
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
    platform: 'linux',
    format: 'deb',
    arch: 'x64',
  ),
  _NoSelfUpdater(),
);

/// Refino do card de workspace: o kebab ⋮ deu lugar ao **botão-direito**, e o
/// chevron virou o único botão — alterna a lista sem selecionar o workspace.

final _root = Project(
  id: 'ws1',
  name: 'Remote Pi',
  path: '/repo',
  colorValue: 0xFF3B82F6,
  createdAt: DateTime.utc(2026),
);

final _fork = Project(
  id: 'wt1',
  name: 'feat/x',
  path: '/repo/.worktrees/feat-x',
  colorValue: 0xFF3B82F6,
  createdAt: DateTime.utc(2026),
  parentId: 'ws1',
);

final _realm = Realm(
  id: Realm.defaultId,
  name: 'Default',
  createdAt: DateTime.utc(2026),
);

/// Raiz do app de teste: ShadcnApp (tema — `context.colors`/`typo`) sobre o
/// router do Modular (que é quem carrega o escopo do UpdateViewModel).
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) => ShadcnApp.router(
    theme: buildTheme(brightness: Brightness.dark),
    routerConfig: ModularApp.routerConfigOf(context),
  );
}

/// Monta a rail com defaults no-op; cada teste sobrescreve só o que observa.
Widget _rail({
  String? selectedId,
  List<Project> worktrees = const [],
  bool expanded = true,
  void Function(String rootId, bool expanded)? onWorktreesExpanded,
  ValueChanged<String>? onSelect,
  ValueChanged<Project>? onRemoveWorktree,
}) {
  final feature = createModule(
    path: '/',
    register: (c) => c.route(
      '/',
      child: (context, state) => Scaffold(
        child: ProjectsRail(
          projects: [_root],
          worktreesOf: (id) => id == _root.id ? worktrees : const [],
          worktreesExpanded: (_) => expanded,
          onWorktreesExpanded: onWorktreesExpanded ?? (_, _) {},
          selectedId: selectedId,
          notificationCount: (_) => 0,
          gitInfo: (_) => const GitInfo(branch: 'main'),
          rootsSummary: (_) => (1, 0),
          rootsOf: (_) => [
            (path: '/repo', name: 'repo', git: const GitInfo(branch: 'main')),
          ],
          forkOriginName: (_) => null,
          onSelect: onSelect ?? (_) {},
          onAdd: () async => true,
          onConfigure: (_) {},
          onDelete: (_) {},
          onCreateWorktree: (_, _) {},
          onRemoveWorktree: onRemoveWorktree ?? (_) {},
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
      ),
    ),
  );
  return TranslationProvider(
    child: ModularApp(
      module: createModule(register: (c) => c.module(feature)),
      provide: (s) => s.addChangeNotifier<UpdateViewModel>(_fakeUpdateVm),
      child: const _Root(),
    ),
  );
}

/// Rótulo traduzido de "N worktrees", lido da árvore já montada.
String _countLabel(WidgetTester tester, int n) => TranslationProvider.of(
  tester.element(find.text('Remote Pi')),
).translations.cockpit.projectsRail.worktreeCount(n: n);

/// Clique-direito no centro de [finder].
Future<void> _secondaryTap(WidgetTester tester, Finder finder) async {
  final gesture = await tester.startGesture(
    tester.getCenter(finder),
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryButton,
  );
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('card e worktree não têm mais o botão ⋮', (tester) async {
    await tester.pumpWidget(_rail(worktrees: [_fork]));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.more_vert), findsNothing);
  });

  testWidgets('chevron alterna a lista sem selecionar o workspace', (
    tester,
  ) async {
    final expandCalls = <(String, bool)>[];
    var selectCalls = 0;

    // Workspace NÃO selecionado e recolhido: antes o toggle exigia selecionar.
    await tester.pumpWidget(
      _rail(
        selectedId: 'outro',
        worktrees: [_fork],
        expanded: false,
        onWorktreesExpanded: (id, e) => expandCalls.add((id, e)),
        onSelect: (_) => selectCalls++,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();

    expect(expandCalls, [('ws1', true)]);
    expect(selectCalls, 0);
  });

  testWidgets('clique no corpo do card só seleciona', (tester) async {
    final expandCalls = <(String, bool)>[];
    final selected = <String>[];

    await tester.pumpWidget(
      _rail(
        selectedId: 'outro',
        worktrees: [_fork],
        onWorktreesExpanded: (id, e) => expandCalls.add((id, e)),
        onSelect: selected.add,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Remote Pi'));
    await tester.pumpAndSettle();

    expect(selected, ['ws1']);
    expect(expandCalls, isEmpty);
  });

  testWidgets('botão-direito no card abre o menu do workspace', (tester) async {
    await tester.pumpWidget(_rail(worktrees: [_fork]));
    await tester.pumpAndSettle();

    final tr = TranslationProvider.of(
      tester.element(find.text('Remote Pi')),
    ).translations.cockpit.projectsRail;

    expect(find.text(tr.settings), findsNothing);
    await _secondaryTap(tester, find.text('Remote Pi'));
    expect(find.text(tr.settings), findsOneWidget);
    expect(find.text(tr.createWorktree), findsOneWidget);
  });

  testWidgets('botão-direito na worktree abre o menu do fork', (tester) async {
    await tester.pumpWidget(_rail(worktrees: [_fork]));
    await tester.pumpAndSettle();

    final tr = TranslationProvider.of(
      tester.element(find.text('Remote Pi')),
    ).translations.cockpit.projectsRail;

    await _secondaryTap(tester, find.text('feat/x'));
    expect(find.text(tr.mergeToParent), findsOneWidget);
    expect(find.text(tr.remove), findsOneWidget);
  });

  // Expandido, as linhas das worktrees já estão à vista — a contagem só
  // duplicaria a informação. Recolhido, ela é a única pista do que há dentro.
  testWidgets('expandido esconde a contagem de worktrees', (tester) async {
    await tester.pumpWidget(_rail(worktrees: [_fork], expanded: true));
    await tester.pumpAndSettle();

    expect(find.text(_countLabel(tester, 1)), findsNothing);
  });

  testWidgets('recolhido mostra a contagem de worktrees', (tester) async {
    await tester.pumpWidget(_rail(worktrees: [_fork], expanded: false));
    await tester.pumpAndSettle();

    expect(find.text(_countLabel(tester, 1)), findsOneWidget);
  });
}
