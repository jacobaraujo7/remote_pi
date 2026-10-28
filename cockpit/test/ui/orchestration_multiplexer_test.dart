import 'package:cockpit/app/cockpit/ui/session/pane_item.dart';
import 'package:cockpit/app/cockpit/ui/states/pane_node.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/orchestration_multiplexer.dart';
import 'package:flutter_test/flutter_test.dart';

class _Terminal extends PaneItem {
  _Terminal(this.id, this.owner, {this.projectId = 'worktree'});
  @override
  final String id;
  @override
  final TerminalOwner owner;
  @override
  final String projectId;
  @override
  String get title => id;
  @override
  String get workingDirectory => '/worktree';
  bool unseen = false;
  bool disposed = false;
  @override
  bool get unseenFinish => unseen;
  @override
  void markUnseen() {
    if (unseen) return;
    unseen = true;
    notifyListeners();
  }

  @override
  void clearUnseen() {
    if (!unseen) return;
    unseen = false;
    notifyListeners();
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

OrchestrationMultiplexer<_Terminal> _mux(String id) =>
    OrchestrationMultiplexer(instanceId: id, projectId: 'worktree');
_Terminal _terminal(String doc, String id) =>
    _Terminal(id, TerminalOwner.orchestration(doc));

void main() {
  test(
    'a background attachment preserves the active tab and keyboard owner',
    () {
      final a = _mux('background');
      final first = _terminal('background', 'one');
      final second = _terminal('background', 'two');
      a.attach(first);
      final pane = a.focusedPaneId!;
      a.attach(second, focus: false);
      expect(findLeaf(a.tree!, pane)!.active, first.id);
      expect(a.keyboardTabId, first.id);
      a.dispose();
      first.dispose();
      second.dispose();
    },
  );

  test(
    'blur/minimize marks owned unread and focus acknowledges only its selected terminal',
    () {
      var windowActive = false;
      final a = OrchestrationMultiplexer<_Terminal>(
        instanceId: 'a',
        projectId: 'worktree',
        windowActive: () => windowActive,
      );
      final first = _terminal('a', 'first'), second = _terminal('a', 'second');
      a.attach(first);
      a.attach(second);
      a.setActive(true);
      a.reveal(first.id, focus: true);
      a.turnFinished(first);
      a.turnFinished(second);
      expect(first.unseenFinish, isTrue);
      expect(second.unseenFinish, isTrue);
      windowActive = true;
      a.refreshReadEligibility();
      expect(first.unseenFinish, isFalse);
      expect(second.unseenFinish, isTrue);
      a.dispose();
      first.dispose();
      second.dispose();
    },
  );

  test(
    'split existing owned terminal preserves objects, direction and tab selection',
    () {
      final a = _mux('a');
      final one = _terminal('a', 'one'), two = _terminal('a', 'two');
      a.attach(one);
      a.attach(two);
      final original = a.paneOf(one.id)!.id;
      expect(
        a.splitTab(
          two.id,
          SplitDir.horizontal,
          anchorPaneId: original,
          before: true,
        ),
        isTrue,
      );
      final root = a.tree! as SplitPane;
      expect(root.dir, SplitDir.horizontal);
      expect((root.a as LeafPane).tabs, [two.id]);
      expect((root.b as LeafPane).tabs, [one.id]);
      expect(a.session(two.id), same(two));
      expect(a.keyboardTabId, two.id);
      final before = a.serialize();
      expect(
        a.splitTab(one.id, SplitDir.vertical, anchorPaneId: 'foreign'),
        isFalse,
      );
      expect(a.serialize(), before);
      a.releaseKeyboard();
      expect(a.keyboardTabId, isNull);
      a.dispose();
      one.dispose();
      two.dispose();
    },
  );

  test('rejects workspace, other document and other worktree ownership', () {
    final a = _mux('a');
    final own = _terminal('a', 'own');
    final outside = _Terminal('outside', const TerminalOwner.workspace());
    final other = _terminal('b', 'foreign');
    final otherTree = _Terminal('other-tree', a.owner, projectId: 'elsewhere');
    a.attach(own);
    final before = a.tree;
    for (final s in [outside, other, otherTree]) {
      expect(() => a.attach(s), throwsArgumentError);
    }
    expect(a.tree, same(before));
    expect(a.sessions.keys, ['own']);
    expect(() => a.sessions.clear(), throwsUnsupportedError);
    a.dispose();
    for (final s in [own, outside, other, otherTree]) {
      s.dispose();
    }
  });

  test(
    'same session reconciliation is idempotent; duplicate IDs are rejected',
    () {
      final a = _mux('a');
      final s = _terminal('a', 'one');
      final duplicate = _terminal('a', 'one');
      a.attach(s);
      final before = a.tree;
      a.attach(s);
      expect(a.tree, same(before));
      expect(a.sessions.length, 1);
      expect(() => a.attach(duplicate), throwsStateError);
      a.dispose();
      s.dispose();
      duplicate.dispose();
    },
  );

  test(
    'tabs, splits, reorder and movement retain the exact session objects',
    () {
      final a = _mux('a');
      final one = _terminal('a', 'one'),
          two = _terminal('a', 'two'),
          three = _terminal('a', 'three');
      a.attach(one);
      a.attach(two);
      final left = a.paneOf(one.id)!.id;
      a.attach(three, split: SplitDir.vertical);
      final right = a.paneOf(three.id)!.id;
      expect(leaves(a.tree!).length, 2);
      expect(a.move(two.id, left, index: 0), isTrue);
      expect(a.paneOf(one.id)!.tabs, [two.id, one.id]);
      expect(a.move(three.id, left), isTrue);
      expect(leaves(a.tree!).length, 1);
      expect(findLeaf(a.tree!, right), isNull);
      expect(a.sessions[three.id], same(three));
      expect([one, two, three].any((s) => s.disposed), isFalse);
      a.dispose();
      one.dispose();
      two.dispose();
      three.dispose();
    },
  );

  test('foreign tab and pane actions cannot change either document', () {
    final a = _mux('a'), b = _mux('b');
    final one = _terminal('a', 'one'), two = _terminal('b', 'two');
    a.attach(one);
    b.attach(two);
    final beforeA = a.serialize(), beforeB = b.serialize();
    expect(a.reveal(two.id), isFalse);
    expect(a.move(one.id, b.focusedPaneId!), isFalse);
    expect(a.detach(two.id), isNull);
    expect(a.resize('foreign-split', .2), isFalse);
    expect(a.serialize(), beforeA);
    expect(b.serialize(), beforeB);
    a.dispose();
    b.dispose();
    one.dispose();
    two.dispose();
  });

  test(
    'graph reveal does not claim terminal keyboard focus or clear unread',
    () {
      final a = _mux('a');
      final one = _terminal('a', 'one'), two = _terminal('a', 'two');
      a.attach(one);
      a.attach(two);
      a.setActive(true);
      a.reveal(one.id);
      a.turnFinished(two);
      expect(two.unseenFinish, isTrue);
      a.reveal(two.id, focus: false);
      expect(a.paneOf(two.id)!.active, two.id);
      expect(a.keyboardTabId, isNull);
      expect(two.unseenFinish, isTrue);
      a.reveal(two.id);
      expect(a.keyboardTabId, two.id);
      expect(two.unseenFinish, isFalse);
      a.dispose();
      one.dispose();
      two.dispose();
    },
  );

  test('completion and read acknowledgements never cross app boundaries', () {
    final a = _mux('a'), b = _mux('b');
    final one = _terminal('a', 'one'), two = _terminal('b', 'two');
    final outside = _Terminal('outside', const TerminalOwner.workspace());
    a.attach(one);
    b.attach(two);
    var bChanges = 0;
    b.addListener(() => bChanges++);
    a.turnFinished(one);
    a.turnFinished(two);
    a.turnFinished(outside);
    expect(one.unseenFinish, isTrue);
    expect(two.unseenFinish, isFalse);
    expect(outside.unseenFinish, isFalse);
    expect(bChanges, 0);
    b.turnFinished(two);
    expect(two.unseenFinish, isTrue);
    a.setActive(true);
    a.reveal(one.id);
    expect(one.unseenFinish, isFalse);
    expect(two.unseenFinish, isTrue);
    a.dispose();
    b.dispose();
    one.dispose();
    two.dispose();
    outside.dispose();
  });

  test('visible focused terminal does not accumulate an unseen badge', () {
    final a = _mux('a');
    final one = _terminal('a', 'one');
    a.attach(one);
    a.setActive(true);
    a.turnFinished(one);
    expect(one.unseenFinish, isFalse);
    a.setActive(false);
    a.turnFinished(one);
    expect(one.unseenFinish, isTrue);
    a.dispose();
    one.dispose();
  });

  test('detach unsubscribes but disposal waits for the UI lifecycle owner', () {
    final a = _mux('a');
    final one = _terminal('a', 'one');
    a.attach(one);
    expect(a.detach(one.id), same(one));
    expect(a.tree, isNull);
    expect(a.keyboardTabId, isNull);
    expect(one.disposed, isFalse);
    var changes = 0;
    a.addListener(() => changes++);
    one.markUnseen();
    expect(changes, 0);
    a.dispose();
    one.dispose();
  });

  test(
    'restores independent tree, ratios, active tabs and keyboard selection',
    () {
      final a = _mux('a'), restored = _mux('a');
      final one = _terminal('a', 'one'), two = _terminal('a', 'two');
      a.attach(one);
      a.attach(two, split: SplitDir.horizontal);
      a.resize((a.tree! as SplitPane).id, .17);
      final state = a.serialize();
      restored.attach(one);
      restored.attach(two);
      restored.restoreLayout(state);
      expect(restored.serialize(), state);
      expect((restored.tree! as SplitPane).frac, closeTo(.67, .001));
      expect(restored.session(one.id), same(one));
      final three = _terminal('a', 'three');
      restored.attach(three, split: SplitDir.vertical);
      final paneIds = <String>[];
      void collect(PaneNode n) {
        paneIds.add(n.id);
        if (n is SplitPane) {
          collect(n.a);
          collect(n.b);
        }
      }

      collect(restored.tree!);
      expect(paneIds.toSet().length, paneIds.length);
      a.dispose();
      restored.dispose();
      one.dispose();
      two.dispose();
      three.dispose();
    },
  );

  test(
    'restoration rejects foreign and duplicate placement transactionally',
    () {
      final a = _mux('a');
      final one = _terminal('a', 'one');
      a.attach(one);
      final before = a.serialize();
      for (final tabs in [
        ['foreign'],
        ['one', 'one'],
      ]) {
        expect(
          () => a.restoreLayout({
            'tree': paneNodeToJson(
              LeafPane(id: 'bad', tabs: tabs, active: tabs.first),
            ),
            'focusedPaneId': 'bad',
            'keyboardTabId': tabs.first,
          }),
          throwsFormatException,
        );
        expect(a.serialize(), before);
      }
      a.dispose();
      one.dispose();
    },
  );

  test(
    'invalid target attachment does not register a session or spawn a pane',
    () {
      final a = _mux('a');
      final one = _terminal('a', 'one');
      expect(() => a.attach(one, inPane: 'outside'), throwsArgumentError);
      expect(a.sessions, isEmpty);
      expect(a.tree, isNull);
      a.dispose();
      one.dispose();
    },
  );
}
