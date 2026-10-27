import 'package:flutter_test/flutter_test.dart';
import 'package:cockpit/app/cockpit/ui/services/orchestration_terminal_target.dart';
import 'package:cockpit/app/cockpit/ui/states/pane_node.dart';

void main() {
  const app = LeafPane(
    id: 'app-pane',
    tabs: ['orchestration'],
    active: 'orchestration',
  );
  const terminal = LeafPane(
    id: 'terminal-pane',
    tabs: ['shell'],
    active: 'shell',
  );
  test(
    'no other terminal dock requests a split without changing original tree',
    () {
      final before = paneNodeToJson(app);
      final target = orchestrationTerminalTarget(
        tree: app,
        orchestrationTabId: 'orchestration',
        terminalIds: {},
      );
      expect(target, (paneId: 'app-pane', split: SplitDir.vertical));
      expect(paneNodeToJson(app), before);
    },
  );
  test(
    'existing terminal dock is reused and split proportions are preserved',
    () {
      const tree = SplitPane(
        id: 'split',
        dir: SplitDir.vertical,
        a: app,
        b: terminal,
        frac: .37,
      );
      final before = paneNodeToJson(tree);
      expect(
        orchestrationTerminalTarget(
          tree: tree,
          orchestrationTabId: 'orchestration',
          terminalIds: {'shell'},
        ),
        (paneId: 'terminal-pane', split: null),
      );
      expect(paneNodeToJson(tree), before);
    },
  );
  test(
    'last terminal dock wins; stale or moved docks fall back to a valid one',
    () {
      const second = LeafPane(id: 'second', tabs: ['shell2'], active: 'shell2');
      const tree = SplitPane(
        id: 'split',
        dir: SplitDir.vertical,
        a: app,
        b: SplitPane(
          id: 'nested',
          dir: SplitDir.horizontal,
          a: terminal,
          b: second,
          frac: .5,
        ),
        frac: .5,
      );
      expect(
        orchestrationTerminalTarget(
          tree: tree,
          orchestrationTabId: 'orchestration',
          terminalIds: {'shell', 'shell2'},
          lastTerminalPaneId: 'second',
        ).paneId,
        'second',
      );
      expect(
        orchestrationTerminalTarget(
          tree: tree,
          orchestrationTabId: 'orchestration',
          terminalIds: {'shell', 'shell2'},
          lastTerminalPaneId: 'removed',
        ).paneId,
        'terminal-pane',
      );
    },
  );
  test(
    'moving app into a terminal dock never replaces that app with a new terminal',
    () {
      const mixed = LeafPane(
        id: 'mixed',
        tabs: ['shell', 'orchestration'],
        active: 'orchestration',
      );
      expect(
        orchestrationTerminalTarget(
          tree: mixed,
          orchestrationTabId: 'orchestration',
          terminalIds: {'shell'},
        ),
        (paneId: 'mixed', split: SplitDir.vertical),
      );
    },
  );
}
