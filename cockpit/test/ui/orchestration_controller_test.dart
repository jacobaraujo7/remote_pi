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
  Fixture({String prefix = 'local', Future<void> Function()? flushLocalState}) {
    controller = OrchestrationController(
      read: () async => disk,
      write: (text) async {
        if (failWrite) throw StateError('read-only');
        disk = text;
      },
      terminals: () => [...live],
      newBoxId: () => 'discovered-${++ids}',
      flushLocalState: flushLocalState,
      createShell: (b) async {
        if (b.box.id == failBox) throw StateError('disconnected host');
        final id = '$prefix-${++spawns}';
        live.add(OrchestrationTerminal(id, b.box.title, b.directory));
        return id;
      },
      closeTerminal: (id) async {
        if (failClose) throw StateError('cannot close disconnected terminal');
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
  bool failClose = false;
  String? failBox;
  int spawns = 0, ids = 0;
  final live = <OrchestrationTerminal>[];
  final closed = <String>[];
  late OrchestrationController controller;
}

void main() {
  test(
    'default document reconciles three blank definitions exactly once',
    () async {
      final f = Fixture();
      var id = 0;
      f.disk = OrchestrationDocument.defaultTerminals(
        newId: () => 'default-${++id}',
      ).encode();
      await Future.wait(List.generate(5, (_) => f.controller.load()));
      expect(f.spawns, 3);
      expect(f.controller.bindings.length, 3);
      expect(
        f.controller.document!.boxes.every(
          (b) =>
              b.box.role.isEmpty &&
              b.box.harness.isEmpty &&
              b.box.model.isEmpty,
        ),
        isTrue,
      );
      expect(f.closed, isEmpty);
      f.controller.dispose();
    },
  );

  test(
    'startup recovery gates edits and retries missing sessions without duplicates',
    () async {
      final f = Fixture();
      var attempts = 0;
      f.controller.beforeReconcile = () async {
        attempts++;
        if (attempts == 1) throw StateError('host disconnected');
        f.live.add(const OrchestrationTerminal('recovered', 'a', 'src'));
        f.controller.restoreSnapshot(
          savedDocument: OrchestrationDocument.parse(f.disk),
          savedBindings: {'a': 'recovered'},
        );
        f.controller.beforeReconcile = null;
      };
      await f.controller.addBox(box('blocked'));
      expect(f.spawns, 0);
      expect(f.controller.error, contains('disconnected'));
      await f.controller.load();
      expect(f.controller.bindings['a'], 'recovered');
      expect(f.spawns, 1);
      await f.controller.load();
      expect(f.spawns, 1);
      f.controller.dispose();
    },
  );

  test(
    'dirty startup snapshot is saved before missing shells are reconciled',
    () async {
      final f = Fixture();
      final saved = OrchestrationDocument(boxes: [box('saved')]);
      f.controller.restoreSnapshot(
        savedDocument: saved,
        savedBindings: {},
        wasDirty: true,
      );
      f.failWrite = true;
      await f.controller.load();
      expect(f.controller.dirty, isTrue);
      expect(f.spawns, 0);
      f.failWrite = false;
      await f.controller.load();
      expect(f.controller.dirty, isFalse);
      expect(f.spawns, 1);
      expect(OrchestrationDocument.parse(f.disk).boxes.single.box.id, 'saved');
      await f.controller.load();
      expect(f.spawns, 1);
      f.controller.dispose();
    },
  );

  test(
    'exit flush captures local presentation after queued portable changes settle',
    () async {
      late final Fixture f;
      final saved = <String>[];
      f = Fixture(
        flushLocalState: () async {
          saved.add(f.disk);
        },
      );
      await f.controller.load();
      final update = f.controller.update([box('b'), box('a')], []);
      await OrchestrationController.flushAll();
      await update;
      expect(saved.length, 1);
      expect(OrchestrationDocument.parse(saved.single).boxes.first.box.id, 'b');
      f.controller.dispose();
    },
  );

  test(
    'concurrent restart requests replace one binding once and retain box links',
    () async {
      final f = Fixture();
      await f.controller.load();
      final before = f.disk, original = f.controller.bindings['a']!;
      await Future.wait(
        List.generate(
          5,
          (_) => f.controller.restartShell('a', expectedTabId: original),
        ),
      );
      expect(f.spawns, 3);
      expect(f.closed, [original]);
      expect(f.controller.bindings['a'], isNot(original));
      expect(f.disk, before);
      expect(f.controller.document!.links.length, 1);
      f.controller.dispose();
    },
  );
  test(
    'restart close failure keeps both owned terminals represented',
    () async {
      final f = Fixture();
      await f.controller.load();
      final original = f.controller.bindings['a']!;
      f.failClose = true;
      await f.controller.restartShell('a', expectedTabId: original);
      expect(f.controller.error, contains('cannot close'));
      expect(f.controller.document!.boxes.length, 3);
      expect(
        f.controller.bindings.values.toSet(),
        f.live.map((t) => t.id).toSet(),
      );
      expect(f.controller.document!.links.single.from, 'a');
      expect(f.controller.bindings['a'], isNot(original));
      f.controller.dispose();
    },
  );
  test(
    'handoff preserves previous terminal as another box and original planned connections',
    () async {
      final f = Fixture();
      await f.controller.load();
      final original = f.controller.bindings['a'];
      await f.controller.handoff('a', historyTitle: 'Previous');
      expect(f.spawns, 3);
      expect(f.closed, isEmpty);
      expect(f.controller.document!.boxes.length, 3);
      expect(f.controller.document!.boxes.last.box.title, 'Previous');
      expect(
        f.controller.bindings[f.controller.document!.boxes.last.box.id],
        original,
      );
      expect(f.controller.bindings['a'], isNot(original));
      expect(f.controller.document!.links.single.from, 'a');
      expect(f.disk, isNot(contains('local-')));
      f.controller.dispose();
    },
  );

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
  test('loading never captures existing or newly opened tabs', () async {
    final f = Fixture();
    f.live.add(const OrchestrationTerminal('manual', 'shell', '.'));
    final disk = f.disk;
    await f.controller.load();
    f.live.add(const OrchestrationTerminal('new', 'other', 'packages'));
    await Future.wait([f.controller.load(), f.controller.load()]);
    expect(f.controller.document!.boxes.map((b) => b.box.id), ['a', 'b']);
    expect(f.disk, disk);
    expect(f.controller.bindings.values, isNot(contains('manual')));
    expect(f.controller.bindings.values, isNot(contains('new')));
    expect(f.spawns, 2);
    f.controller.dispose();
  });
  test(
    'explicit new box creates one blank shell despite concurrent requests',
    () async {
      final f = Fixture();
      await f.controller.load();
      await Future.wait(List.generate(6, (_) => f.controller.addBox(box('c'))));
      expect(f.spawns, 3);
      expect(f.controller.document!.boxes.map((b) => b.box.id), [
        'a',
        'b',
        'c',
      ]);
      expect(OrchestrationDocument.parse(f.disk).boxes.length, 3);
      expect(f.disk, isNot(contains('tabId')));
      f.controller.dispose();
    },
  );
  test(
    'new box failed save retains binding and never duplicates its shell',
    () async {
      final f = Fixture();
      await f.controller.load();
      f.failWrite = true;
      await f.controller.addBox(box('c'));
      expect(f.spawns, 3);
      expect(f.controller.dirty, isTrue);
      expect(f.controller.error, contains('read-only'));
      await f.controller.addBox(box('c'));
      expect(f.spawns, 3);
      // Repeating add retries the save without creating another shell.
      expect(f.controller.dirty, isTrue);
      f.failWrite = false;
      await f.controller.load();
      expect(f.controller.dirty, isFalse);
      expect(f.spawns, 3);
      expect(OrchestrationDocument.parse(f.disk).boxes.length, 3);
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
    'switching legacy bindings preserves sessions without capturing unrepresented ones',
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
