import 'package:cockpit/app/cockpit/domain/entities/orchestration_document.dart';
import 'package:cockpit/app/cockpit/ui/services/orchestration_controller.dart';
import 'package:cockpit/app/cockpit/ui/session/orchestration_session.dart';
import 'package:cockpit/app/cockpit/ui/session/terminal_session.dart';
import 'package:cockpit/app/core/domain/entities/terminal_profile.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:flutter_test/flutter_test.dart';
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
}) => OrchestrationSession(
  id: id,
  projectId: 'worktree',
  path: '/worktree/$id.orchestration',
  onBeforeDispose: beforeDispose,
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

void main() {
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
}
