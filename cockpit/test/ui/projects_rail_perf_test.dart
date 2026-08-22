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

/// Custo de um build da rail. Cada teste conta quantas vezes o painel pergunta
/// algo ao VM por frame — é isso que multiplica quando o VM notifica.

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

final _realm = Realm(
  id: Realm.defaultId,
  name: 'Default',
  createdAt: DateTime.utc(2026),
);

Project _ws(int i) => Project(
  id: 'ws$i',
  name: 'Workspace $i',
  path: '/repo$i',
  colorValue: 0xFF3B82F6,
  createdAt: DateTime.utc(2026),
  order: i,
);

Project _fork(int w, int f) => Project(
  id: 'ws$w-fork$f',
  name: 'feat/$w-$f',
  path: '/repo$w/.worktrees/$f',
  colorValue: 0xFF3B82F6,
  createdAt: DateTime.utc(2026),
  parentId: 'ws$w',
);

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) => ShadcnApp.router(
    theme: buildTheme(brightness: Brightness.dark),
    routerConfig: ModularApp.routerConfigOf(context),
  );
}

/// Contador de perguntas que o painel faz ao VM durante um build.
class _Calls {
  int gitInfo = 0;
  int rootsOf = 0;
  int moveTargetsOf = 0;
  int forkOriginName = 0;

  void reset() => gitInfo = rootsOf = moveTargetsOf = forkOriginName = 0;
}

Widget _rail({
  required int workspaces,
  required int forksEach,
  required bool expanded,
  required _Calls calls,
}) {
  final projects = [for (var i = 0; i < workspaces; i++) _ws(i)];
  final forksOf = <String, List<Project>>{
    for (var i = 0; i < workspaces; i++)
      'ws$i': [for (var f = 0; f < forksEach; f++) _fork(i, f)],
  };

  final feature = createModule(
    path: '/',
    register: (c) => c.route(
      '/',
      child: (context, state) => Scaffold(
        child: ProjectsRail(
          projects: projects,
          worktreesOf: (id) => forksOf[id] ?? const [],
          worktreesExpanded: (_) => expanded,
          onWorktreesExpanded: (_, _) {},
          selectedId: null,
          notificationCounts: const {},
          gitInfo: (_) {
            calls.gitInfo++;
            return const GitInfo(branch: 'main');
          },
          rootsSummary: (_) => (1, 0),
          rootsOf: (id) {
            calls.rootsOf++;
            return [
              (path: '/repo', name: 'repo', git: const GitInfo(branch: 'main')),
            ];
          },
          forkOriginName: (_) {
            calls.forkOriginName++;
            return null;
          },
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
          moveTargetsOf: (_) {
            calls.moveTargetsOf++;
            return const [];
          },
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

void main() {
  testWidgets('worktrees recolhidas não constroem nenhuma linha de fork', (
    tester,
  ) async {
    final calls = _Calls();
    await tester.pumpWidget(
      _rail(workspaces: 3, forksEach: 4, expanded: false, calls: calls),
    );
    await tester.pumpAndSettle();

    // forkOriginName é perguntado uma vez por _WorktreeItem construído.
    expect(calls.forkOriginName, 0);
  });

  testWidgets('worktrees expandidas constroem uma linha por fork', (
    tester,
  ) async {
    final calls = _Calls();
    await tester.pumpWidget(
      _rail(workspaces: 3, forksEach: 4, expanded: true, calls: calls),
    );
    await tester.pumpAndSettle();

    expect(calls.forkOriginName, 3 * 4);
  });

  testWidgets('o build não resolve os dados que só o menu usa', (tester) async {
    final calls = _Calls();
    await tester.pumpWidget(
      _rail(workspaces: 3, forksEach: 2, expanded: false, calls: calls),
    );
    await tester.pumpAndSettle();

    expect(calls.rootsOf, 0);
    expect(calls.moveTargetsOf, 0);

    // ...mas o menu, quando abre, tem tudo o que precisa.
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Workspace 0')),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();

    expect(calls.rootsOf, greaterThan(0));
    expect(calls.moveTargetsOf, greaterThan(0));
  });

  testWidgets('cada workspace visível é perguntado uma vez só', (tester) async {
    final calls = _Calls();
    await tester.pumpWidget(
      _rail(workspaces: 3, forksEach: 0, expanded: false, calls: calls),
    );
    await tester.pumpAndSettle();

    // Um gitInfo por card — antes eram dois (o valor e o `canCreateWorktree`).
    expect(calls.gitInfo, 3);
  });

  testWidgets('lista longa só constrói o que cabe na viewport', (tester) async {
    final calls = _Calls();
    await tester.pumpWidget(
      _rail(workspaces: 200, forksEach: 0, expanded: false, calls: calls),
    );
    await tester.pumpAndSettle();

    // Viewport de 600px com cards de ~50px: uma fração dos 200 workspaces.
    expect(calls.gitInfo, lessThan(60));
  });
}
