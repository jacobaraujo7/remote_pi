import 'dart:async';
import 'package:cockpit/app/cockpit/ui/document/worktree_document_host.dart';
import 'package:cockpit/app/cockpit/ui/services/orchestration_document_files.dart';
import 'package:cockpit/app/cockpit/data/filesystem/disk_file_change_watcher.dart';
import 'package:cockpit/app/cockpit/ui/session/orchestration_file_presentation.dart';
import 'package:cockpit/app/cockpit/ui/session/file_viewer_session.dart';
import 'package:cockpit/app/cockpit/domain/entities/file_view.dart';
import 'package:cockpit/app/cockpit/domain/entities/orchestration_document.dart';
import 'package:cockpit/app/cockpit/ui/services/orchestration_controller.dart';
import 'package:cockpit/app/cockpit/ui/session/orchestration_session.dart';
import 'package:cockpit/app/cockpit/ui/session/terminal_session.dart';
import 'package:cockpit/app/core/domain/entities/terminal_profile.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cockpit/app/core/ui/window_activity_controller.dart';
import '../support/attachment_terminal_gateway.dart';

class _Gateway extends AttachmentTerminalGateway {
  int stopped = 0;
  bool fail = false;
  @override
  Future<void> kill() async {
    stopped++;
    if (fail) throw StateError('disconnected');
    await super.kill();
  }
}

OrchestrationSession _app(
  String id, {
  Future<void> Function()? beforeDispose,
  bool remoteFileSystem = false,
  String? documentPath,
  WindowActivityController? activity,
  Future<Result<OrchestrationFilePresentation, String>> Function(
    TerminalSession,
    String, {
    int? line,
  })?
  openFile,
}) => OrchestrationSession(
  id: id,
  projectId: 'worktree',
  path: documentPath ?? '/worktree/$id.orchestration',
  remoteFileSystem: remoteFileSystem,
  onBeforeDispose: beforeDispose,
  onOpenFile: openFile,
  windowActive: activity == null ? null : () => activity.isActive,
  windowActivityChanges: activity,
  controller: OrchestrationController(
    read: () async => const OrchestrationDocument().encode(),
    write: (_) async {},
    createShell: (_) async => throw StateError('not requested'),
    closeTerminal: (_) async {},
    terminals: () => [],
    newBoxId: () => 'unused',
  ),
);

TerminalSession _terminal(OrchestrationSession owner, _Gateway gateway) =>
    TerminalSession(
      id: '${owner.id}-terminal',
      owner: owner.terminals.owner,
      projectId: owner.projectId,
      workingDirectory: '/worktree',
      gateway: gateway,
      profile: const TerminalProfile(
        id: 'shell',
        label: 'Shell',
        executable: 'sh',
      ),
    );

OrchestrationFilePresentation _document(String path, String terminal) =>
    OrchestrationFilePresentation(
      id: path,
      path: path,
      terminalId: terminal,
      host: WorktreeDocumentHost(
        workspaceRoot: '/worktree',
        changes: const DiskFileChangeWatcher(),
        files: const LocalDocumentFiles(),
        remote: false,
        available: () => true,
      ),
    );

void main() {
  test('newer file open wins over a late earlier callback', () async {
    final old = Completer<Result<OrchestrationFilePresentation, String>>();
    final app = _app(
      'files',
      openFile: (terminal, path, {line}) async => path == '/old'
          ? await old.future
          : Success(_document(path, terminal.id)),
    );
    final terminal = _terminal(app, _Gateway());
    app.terminals.attach(terminal);
    final earlier = app.openFile(terminal.id, '/old');
    expect(
      await app.openFile(terminal.id, '/new'),
      isA<Success<String, String>>(),
    );
    old.complete(Success(_document('/old', terminal.id)));
    expect(await earlier, isA<Failure<String, String>>());
    expect(app.filePresentation!.path, '/new');
    await app.dispose();
  });

  test(
    'hidden drafts prevent replacement and parent shutdown until explicitly discarded',
    () async {
      final app = _app(
        'draft',
        openFile: (terminal, path, {line}) async =>
            Success(_document(path, terminal.id)),
      );
      final gateway = _Gateway();
      final terminal = _terminal(app, gateway);
      app.terminals.attach(terminal);
      app.setPresentationActive(true);
      await app.openFile(terminal.id, '/draft');
      final document = app.filePresentation!;
      final draft = FileViewerSession(
        id: 'draft-file',
        projectId: app.projectId,
        path: '/draft',
        view: const FileViewText('unsaved'),
      )..setDirty(true);
      document.viewer = draft;
      app.showTerminals();
      expect(app.fileVisible, isFalse);
      expect(
        await app.openFile(terminal.id, '/replacement'),
        isA<Failure<String, String>>(),
      );
      expect(app.filePresentation, same(document));
      expect(app.closeFile(), isFalse);
      expect(await app.prepareClose(), isA<Failure<String, String>>());
      expect(gateway.stopped, 0);
      expect(app.closeFile(discard: true), isTrue);
      expect(await app.prepareClose(), isA<Success<String, String>>());
      await app.dispose();
      draft.dispose();
    },
  );

  test('closing the app rejects a pending file callback', () async {
    final gate = Completer<Result<OrchestrationFilePresentation, String>>();
    final app = _app('closed', openFile: (_, path, {line}) => gate.future);
    final terminal = _terminal(app, _Gateway());
    app.terminals.attach(terminal);
    final opening = app.openFile(terminal.id, '/late');
    await app.dispose();
    gate.complete(Success(_document('/late', terminal.id)));
    expect(await opening, isA<Failure<String, String>>());
    expect(app.filePresentation, isNull);
  });

  test(
    'window activity subscription acknowledges only the selected owned terminal and detaches on dispose',
    () async {
      final activity = WindowActivityController()..blur();
      final app = _app('window', activity: activity);
      final terminal = _terminal(app, _Gateway());
      app.terminals.attach(terminal);
      app.terminals.setActive(true);
      app.terminals.turnFinished(terminal);
      expect(terminal.unseenFinish, isTrue);
      activity.focus();
      expect(terminal.unseenFinish, isFalse);
      await app.dispose();
      activity.blur();
      activity.dispose();
    },
  );

  test(
    'shutdown captures child metadata before releasing its registry',
    () async {
      late final OrchestrationSession app;
      final captured = <String>[];
      app = _app(
        'a',
        beforeDispose: () async {
          captured.addAll(app.terminals.sessions.keys);
        },
      );
      final gateway = _Gateway();
      final terminal = _terminal(app, gateway);
      app.terminals.attach(terminal);
      final closing = app.dispose();
      expect(captured, [terminal.id]);
      await closing;
      expect(gateway.stopped, 1);
    },
  );

  test(
    'confirmed app close stops only its children and disposal does not kill twice',
    () async {
      final a = _app('a'), b = _app('b');
      final gatewayA = _Gateway(), gatewayB = _Gateway();
      final one = _terminal(a, gatewayA), two = _terminal(b, gatewayB);
      a.terminals.attach(one);
      b.terminals.attach(two);
      await Future.wait([a.controller.load(), b.controller.load()]);
      expect(await a.prepareClose(), isA<Success>());
      expect(gatewayA.stopped, 1);
      expect(gatewayB.stopped, 0);
      expect(a.terminals.session(one.id), same(one)); // view can unmount first
      expect(b.terminals.session(two.id), same(two));
      await a.dispose();
      await a.dispose();
      expect(gatewayA.stopped, 1);
      expect(gatewayB.stopped, 0);
      await b.dispose();
    },
  );
  test(
    'failed app close preserves the registered session and allows retry',
    () async {
      final app = _app('a');
      final gateway = _Gateway()..fail = true;
      final terminal = _terminal(app, gateway);
      app.terminals.attach(terminal);
      await app.controller.load();
      expect(await app.prepareClose(), isA<Failure>());
      expect(app.closing, isFalse);
      expect(app.terminals.session(terminal.id), same(terminal));
      expect(app.disposed, isFalse);
      gateway.fail = false;
      expect(await app.prepareClose(), isA<Success>());
      expect(gateway.stopped, 2);
      await app.dispose();
      expect(gateway.stopped, 2);
    },
  );
  test(
    'renaming the document preserves owner, terminal bindings and context identity',
    () async {
      final app = _app('a');
      final gateway = _Gateway();
      final terminal = _terminal(app, gateway);
      app.terminals.attach(terminal);
      final context = app.context, owner = terminal.owner;
      app.retarget('/worktree/renamed.orchestration');
      expect(app.context, same(context));
      expect(app.context.selectedDisplayTitle, 'renamed.orchestration');
      expect(app.title, contains('renamed.orchestration'));
      expect(terminal.owner, owner);
      expect(gateway.stopped, 0);
      expect(app.terminals.session(terminal.id), same(terminal));
      await app.dispose();
    },
  );
  test(
    'local rename preserves bindings and leaves remote homonyms unchanged',
    () async {
      final local = _app('local', documentPath: '/worktree/agents.orc');
      final remote = _app(
        'remote',
        documentPath: '/worktree/agents.orc',
        remoteFileSystem: true,
      );
      final localGateway = _Gateway(), remoteGateway = _Gateway();
      final localTerminal = _terminal(local, localGateway);
      final remoteTerminal = _terminal(remote, remoteGateway);
      local.terminals.attach(localTerminal);
      remote.terminals.attach(remoteTerminal);
      local.controller.bindings['box'] = localTerminal.id;
      remote.controller.bindings['box'] = remoteTerminal.id;
      final localContext = local.context, remoteContext = remote.context;
      expect(
        local.retargetLocalFilesystem(
          '/worktree/agents.orc',
          '/worktree/team.orc',
        ),
        isTrue,
      );
      expect(
        remote.retargetLocalFilesystem(
          '/worktree/agents.orc',
          '/worktree/team.orc',
        ),
        isFalse,
      );
      expect(local.path, '/worktree/team.orc');
      expect(remote.path, '/worktree/agents.orc');
      expect(local.context, same(localContext));
      expect(remote.context, same(remoteContext));
      expect(local.controller.bindings['box'], localTerminal.id);
      expect(remote.controller.bindings['box'], remoteTerminal.id);
      expect(local.terminals.session(localTerminal.id), same(localTerminal));
      expect(remote.terminals.session(remoteTerminal.id), same(remoteTerminal));
      expect(localGateway.stopped, 0);
      expect(remoteGateway.stopped, 0);
      await local.dispose();
      await remote.dispose();
    },
  );

  test(
    'local directory rename follows descendants but not siblings or closing apps',
    () async {
      final nested = _app('nested', documentPath: '/worktree/team/agents.orc');
      final sibling = _app(
        'sibling',
        documentPath: '/worktree/team-other/agents.orc',
      );
      final closing = _app('closing', documentPath: '/worktree/team/closed.orc')
        ..closing = true;
      expect(
        nested.retargetLocalFilesystem('/worktree/team', '/worktree/renamed'),
        isTrue,
      );
      expect(nested.path, '/worktree/renamed/agents.orc');
      expect(
        sibling.retargetLocalFilesystem('/worktree/team', '/worktree/renamed'),
        isFalse,
      );
      expect(sibling.path, '/worktree/team-other/agents.orc');
      expect(
        closing.retargetLocalFilesystem('/worktree/team', '/worktree/renamed'),
        isFalse,
      );
      expect(closing.path, '/worktree/team/closed.orc');
      await nested.dispose();
      await sibling.dispose();
      await closing.dispose();
    },
  );
}
