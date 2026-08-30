import 'dart:async';
import 'package:cockpit/app/cockpit/domain/entities/git_file_status.dart';
import 'package:cockpit/app/cockpit/domain/entities/git_info.dart';
import 'package:cockpit/app/cockpit/domain/entities/project.dart';
import 'package:cockpit/app/cockpit/domain/entities/remote_host.dart';
import 'package:cockpit/app/cockpit/domain/entities/remote_workspace_pin.dart';
import 'package:cockpit/app/cockpit/domain/contracts/remote_hosts_store.dart';
import 'package:cockpit/app/cockpit/ui/remote/remote_hosts_controller.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/remote_workspace_controller.dart';
import 'package:cockpit_core/cockpit_core.dart' show GitRunResult, GitStatus;
import 'package:cockpit_remote/cockpit_remote.dart'
    show RemoteFileService, RemoteGitService;
import 'package:flutter_test/flutter_test.dart';

class _EmptyStore implements RemoteHostsStore {
  @override
  List<RemoteHost> hosts() => const [];
  @override
  List<RemoteWorkspacePin> pins() => const [];
  @override
  Future<void> remove(String id) async {}
  @override
  Future<void> removePin(String id) async {}
  @override
  Future<void> save(RemoteHost host) async {}
  @override
  Future<void> savePin(RemoteWorkspacePin pin) async {}
}

Project _ws(String id, String remotePath) => Project(
  id: id,
  name: id,
  path: '',
  colorValue: 0,
  createdAt: DateTime(2026),
  realmId: 'r',
  kind: WorkspaceKind.remoteTerminal,
  remoteHostId: 'h1',
  remotePath: remotePath,
);

/// Controller de hosts com um host e serviços de mentira — o suficiente para
/// exercitar o caminho de `refreshWorktrees` sem rede.
class _FakeHosts extends RemoteHostsController {
  _FakeHosts(this.git) : super(_EmptyStore());

  final _FakeGit git;

  static const RemoteHost _h = RemoteHost(
    id: 'h1',
    name: 'host',
    sshTarget: 'jacob@example',
  );

  @override
  List<RemoteHost> get hosts => [_h];

  @override
  Future<RemoteGitService> gitServiceFor(RemoteHost host) async => git;

  @override
  Future<RemoteFileService> fileServiceFor(RemoteHost host) async =>
      _FakeFiles();
}

class _FakeFiles extends Fake implements RemoteFileService {}

class _FakeGit extends Fake implements RemoteGitService {
  int runs = 0;
  final Completer<void> gate = Completer<void>();

  @override
  Future<GitRunResult> run(String repo, List<String> args) async {
    runs++;
    await gate.future;
    return const GitRunResult(code: 0, stdout: '', stderr: '');
  }

  @override
  Future<GitStatus> status(String repoPath) async =>
      throw StateError('sem status neste teste');
}

void main() {
  late RemoteWorkspaceController ctrl;

  setUp(() {
    ctrl = RemoteWorkspaceController(RemoteHostsController(_EmptyStore()));
    ctrl.resolveProject = (id) => id == 'ws' ? _ws('ws', '/srv/multi') : null;
    ctrl.selectedId = () => 'ws';
  });

  test('sem descoberta ainda, a root é a pasta do pin (single-root)', () {
    expect(ctrl.rootsOf('ws'), ['/srv/multi']);
    expect(ctrl.isMultiRoot('ws'), isFalse);
  });

  group('multirepo remoto', () {
    setUp(() {
      ctrl.seedGit(
        'ws',
        ['/srv/multi/api', '/srv/multi/web'],
        {
          '/srv/multi/api': const GitInfo(
            branch: 'main',
            files: {'lib/a.dart': GitFileStatus.modified},
            stagedFiles: {'lib/a.dart': GitFileStatus.modified},
          ),
          '/srv/multi/web': const GitInfo(branch: 'dev'),
        },
      );
    });

    test('roots descobertas viram multirepo', () {
      expect(ctrl.isMultiRoot('ws'), isTrue);
      expect(ctrl.rootsOf('ws'), ['/srv/multi/api', '/srv/multi/web']);
    });

    test('não existe "o" git do workspace — só por root', () {
      expect(ctrl.gitInfoOf('ws'), isNull);
      expect(ctrl.infoForRoot('ws', '/srv/multi/api')?.branch, 'main');
      expect(ctrl.infoForRoot('ws', '/srv/multi/web')?.branch, 'dev');
    });

    test('resumo agregado conta as roots sujas', () {
      expect(ctrl.rootsSummary('ws'), (2, 1));
      expect(ctrl.hasGit('ws'), isTrue);
    });

    test('resolve a root dona de um caminho', () {
      expect(
        ctrl.rootContaining('ws', '/srv/multi/api/lib/a.dart'),
        '/srv/multi/api',
      );
      expect(ctrl.rootContaining('ws', '/srv/multi/web/x'), '/srv/multi/web');
      // Solto na pasta-mãe: não pertence a repo nenhum.
      expect(ctrl.rootContaining('ws', '/srv/multi/README.md'), isNull);
    });

    test('status usa o git da root dona, não o da pasta-mãe', () {
      // O arquivo modificado está em `api`; `web` tem o mesmo caminho relativo
      // e está limpa — se a resolução de root falhar, este é o teste que pega.
      expect(
        ctrl.statusForPath('/srv/multi', '/srv/multi/api/lib/a.dart'),
        GitFileStatus.modified,
      );
      expect(
        ctrl.statusForPath('/srv/multi', '/srv/multi/web/lib/a.dart'),
        isNull,
      );
    });

    test('pasta agrega o status dos descendentes na root certa', () {
      expect(
        ctrl.statusForPath('/srv/multi', '/srv/multi/api/lib'),
        GitFileStatus.modified,
      );
      expect(ctrl.statusForPath('/srv/multi', '/srv/multi/web/lib'), isNull);
    });

    test('forget limpa roots e git do workspace', () {
      ctrl.forget('ws');
      expect(ctrl.rootsOf('ws'), ['/srv/multi']); // volta ao pin
      expect(ctrl.infoForRoot('ws', '/srv/multi/api'), isNull);
    });
  });

  group('forks (worktrees remotos)', () {
    test('falha de listagem NÃO apaga os forks já conhecidos', () async {
      // Regressão da 1.28.12: ao varrer as roots do multirepo, um erro de
      // listagem virava `continue` e a lista saía vazia — o VM então removia
      // todos os forks e jogava a seleção de volta no workspace pai. Com host
      // offline (o caso deste teste, sem conexão nenhuma), o refresh tem de
      // sair sem aplicar nada.
      var applied = 0;
      ctrl.applyForks = (_, _, _) => applied++;
      await ctrl.refreshWorktrees('ws');
      expect(applied, 0, reason: 'nada foi aplicado a partir de uma falha');
    });

    test('workspace sem pasta não dispara refresh', () async {
      var applied = 0;
      ctrl.applyForks = (_, _, _) => applied++;
      await ctrl.refreshWorktrees('desconhecido');
      expect(applied, 0);
    });
  });

  test('single-root remoto continua com "o" git do workspace', () {
    ctrl.seedGit(
      'ws',
      ['/srv/multi'],
      {'/srv/multi': const GitInfo(branch: 'main')},
    );
    expect(ctrl.isMultiRoot('ws'), isFalse);
    expect(ctrl.gitInfoOf('ws')?.branch, 'main');
  });

  test('refreshWorktrees concorrente não empilha listagens', () async {
    final git = _FakeGit();
    final c = RemoteWorkspaceController(_FakeHosts(git));
    c.resolveProject = (id) => id == 'ws' ? _ws('ws', '/srv/multi') : null;
    c.selectedId = () => 'ws';
    c.applyForks = (wsId, forks, originOf) {};
    c.seedGit('ws', ['/srv/multi'], const {});

    // [ensureLoaded] roda a cada transição de fase da conexão; com o reconnect
    // em backoff isso vira rajada. O segundo refresh tem de morrer no guard.
    final a = c.refreshWorktrees('ws');
    final b = c.refreshWorktrees('ws');
    await pumpEventQueue();
    expect(git.runs, 1);

    git.gate.complete();
    await Future.wait([a, b]);
  });
}
