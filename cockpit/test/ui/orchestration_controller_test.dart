import 'package:flutter_test/flutter_test.dart';
import 'package:cockpit/app/cockpit/domain/entities/orchestration_document.dart';
import 'package:cockpit/app/cockpit/domain/entities/workspace_graph.dart';
import 'package:cockpit/app/cockpit/ui/services/orchestration_controller.dart';

OrchestrationBox box(String id) => OrchestrationBox(
  box: GraphBox(
    id: id,
    title: id,
    role: 'optional',
    harness: 'claude',
    model: 'sonnet',
    position: Offset.zero,
  ),
  directory: 'src',
);

class Fixture {
  Fixture({String prefix = 'local'}) {
    controller = OrchestrationController(
      read: () async => disk,
      write: (text) async {
        if (failWrite) throw StateError('read-only');
        disk = text;
      },
      terminals: () => [...live],
      newBoxId: () => 'discovered-${++ids}',
      createShell: (b) async {
        if (b.box.id == failBox) throw StateError('disconnected host');
        final id = '$prefix-${++spawns}';
        live.add(OrchestrationTerminal(id, b.box.title, b.directory));
        return id;
      },
      closeTerminal: (id) async {
        closed.add(id);
        live.removeWhere((t) => t.id == id);
      },
    );
  }
  String disk = OrchestrationDocument(
    boxes: [box('a'), box('b')],
    links: [const GraphLink(from: 'a', to: 'b')],
  ).encode();
  bool failWrite = false;
  String? failBox;
  int spawns = 0, ids = 0;
  final live = <OrchestrationTerminal>[];
  final closed = <String>[];
  late OrchestrationController controller;
}

void main() {
  test(
    'same portable file creates separate shells in separate worktrees',
    () async {
      final a = Fixture(prefix: 'one'), b = Fixture(prefix: 'two');
      await Future.wait([a.controller.load(), b.controller.load()]);
      expect(a.controller.bindings.keys, b.controller.bindings.keys);
      expect(a.controller.bindings['a'], isNot(b.controller.bindings['a']));
      expect(a.spawns, 2);
      expect(b.spawns, 2);
      a.controller.dispose();
      b.controller.dispose();
    },
  );
  test('concurrent/repeated loads never duplicate terminal sessions', () async {
    final f = Fixture();
    await Future.wait(List.generate(8, (_) => f.controller.load()));
    expect(f.spawns, 2);
    expect(f.controller.error, isNull);
    f.controller.dispose();
  });
  test(
    'partial shell creation failure retries only missing sessions',
    () async {
      final f = Fixture()..failBox = 'b';
      await f.controller.load();
      expect(f.spawns, 1);
      expect(f.controller.error, contains('disconnected'));
      f.failBox = null;
      await f.controller.load();
      expect(f.spawns, 2);
      f.controller.dispose();
    },
  );
  test(
    'discovers existing/new terminals and persists their order once',
    () async {
      final f = Fixture();
      f.live.add(const OrchestrationTerminal('manual', 'shell', '.'));
      await f.controller.load();
      expect(f.controller.document!.boxes.length, 3);
      f.live.add(const OrchestrationTerminal('new', 'other', 'packages'));
      await Future.wait([f.controller.discover(), f.controller.discover()]);
      expect(f.controller.document!.boxes.length, 4);
      expect(f.spawns, 2);
      expect(f.disk, isNot(contains('tabId')));
      f.controller.dispose();
    },
  );
  test(
    'invalid file keeps last good state and never creates or closes a shell',
    () async {
      final f = Fixture();
      await f.controller.load();
      final old = f.controller.document;
      f.disk = '{invalid';
      await f.controller.load();
      expect(f.controller.document, same(old));
      expect(f.spawns, 2);
      expect(f.closed, isEmpty);
      f.controller.dispose();
    },
  );
  test(
    'external removal waits for explicit choice; keep restores definition',
    () async {
      final f = Fixture();
      await f.controller.load();
      f.disk = OrchestrationDocument(boxes: [box('a')]).encode();
      await f.controller.load();
      expect(f.controller.pendingRemovals.keys, ['b']);
      expect(f.closed, isEmpty);
      await f.controller.resolveRemoval('b', close: false);
      expect(f.closed, isEmpty);
      expect(OrchestrationDocument.parse(f.disk).boxes.length, 2);
      expect(f.controller.pendingRemovals, isEmpty);
      f.controller.dispose();
    },
  );
  test('external removal accepted closes exactly the bound terminal', () async {
    final f = Fixture();
    await f.controller.load();
    final id = f.controller.bindings['b'];
    f.disk = OrchestrationDocument(boxes: [box('a')]).encode();
    await f.controller.load();
    await f.controller.resolveRemoval('b', close: true);
    await f.controller.load();
    expect(f.closed, [id]);
    expect(f.spawns, 2);
    f.controller.dispose();
  });
  test(
    'closing X removes definition/links and does not resurrect on reload',
    () async {
      final f = Fixture();
      await f.controller.load();
      final id = f.controller.bindings['b']!;
      f.live.removeWhere((t) => t.id == id);
      await f.controller.forgetTerminal(id);
      await f.controller.load();
      expect(f.spawns, 2);
      expect(f.controller.document!.boxes.map((b) => b.box.id), ['a']);
      expect(f.controller.document!.links, isEmpty);
      f.controller.dispose();
    },
  );
  test(
    'write failure remains visibly dirty and retry saves without new shells',
    () async {
      final f = Fixture();
      await f.controller.load();
      f.failWrite = true;
      await f.controller.update([box('b'), box('a')], []);
      expect(f.controller.dirty, isTrue);
      expect(f.controller.error, contains('read-only'));
      f.failWrite = false;
      await f.controller.load();
      expect(f.controller.dirty, isFalse);
      expect(f.spawns, 2);
      expect(OrchestrationDocument.parse(f.disk).boxes.first.box.id, 'b');
      f.controller.dispose();
    },
  );
  test(
    'switching documents preserves live sessions and discovers unrepresented ones',
    () async {
      final f = Fixture();
      await f.controller.load();
      final first = {...f.controller.bindings};
      f.controller.switchDocument({});
      f.disk = OrchestrationDocument(boxes: [box('c')]).encode();
      await f.controller.load();
      expect(f.spawns, 3);
      expect(f.live.length, 3);
      f.controller.switchDocument(first);
      f.disk = OrchestrationDocument(boxes: [box('a'), box('b')]).encode();
      await f.controller.load();
      expect(f.spawns, 3);
      f.controller.dispose();
    },
  );
  test(
    'restored local bindings reuse sessions instead of recreating them',
    () async {
      final first = Fixture();
      await first.controller.load();
      final reopened = Fixture();
      reopened.live.addAll(first.live);
      reopened.controller.bindings.addAll(first.controller.bindings);
      await reopened.controller.load();
      expect(reopened.spawns, 0);
      first.controller.dispose();
      reopened.controller.dispose();
    },
  );
  test(
    'queued document write completes even if the view/controller is disposed',
    () async {
      final f = Fixture();
      await f.controller.load();
      final update = f.controller.update([box('b'), box('a')], []);
      f.controller.dispose();
      await update;
      await OrchestrationController.flushAll();
      expect(OrchestrationDocument.parse(f.disk).boxes.first.box.id, 'b');
    },
  );
  test(
    'poll reloads external edits without refresh and preserves valid state on parse failure',
    () async {
      final f = Fixture();
      await f.controller.load();
      f.disk = OrchestrationDocument(
        boxes: [box('a'), box('b'), box('c')],
        links: [],
      ).encode();
      await f.controller.poll();
      expect(f.spawns, 3);
      await f.controller.poll();
      expect(f.spawns, 3);
      f.disk = '{invalid';
      await f.controller.poll();
      expect(f.controller.document!.boxes.length, 3);
      expect(f.controller.error, isNotNull);
      f.disk = f.controller.document!.encode();
      await f.controller.poll();
      expect(f.controller.error, isNull);
      expect(f.spawns, 3);
      f.controller.dispose();
    },
  );
  test(
    'poll retries a failed save without replacing local configuration',
    () async {
      final f = Fixture();
      await f.controller.load();
      f.failWrite = true;
      await f.controller.update([box('a'), box('b'), box('draft')], []);
      expect(f.controller.dirty, isTrue);
      f.failWrite = false;
      await f.controller.poll();
      expect(f.controller.dirty, isFalse);
      expect(OrchestrationDocument.parse(f.disk).boxes.last.box.id, 'draft');
      expect(f.spawns, 2);
      f.controller.dispose();
    },
  );
}
