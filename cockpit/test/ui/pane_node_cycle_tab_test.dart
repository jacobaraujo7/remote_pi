import 'package:cockpit/app/cockpit/ui/states/pane_node.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A pane holding [tabs], with [active] selected.
  LeafPane leaf(List<String> tabs, String active) =>
      LeafPane(id: 'p', tabs: tabs, active: active);

  group('cycleTab — next (delta +1) / previous (delta -1)', () {
    test('advances in visual order from the active tab', () {
      final l = leaf(['a', 'b', 'c'], 'a');
      expect(cycleTab(l, 1), 'b');
    });

    test('goes back in visual order from the active tab', () {
      final l = leaf(['a', 'b', 'c'], 'b');
      expect(cycleTab(l, -1), 'a');
    });

    test('active in the middle: correct neighbours both ways', () {
      final l = leaf(['a', 'b', 'c'], 'b');
      expect(cycleTab(l, 1), 'c');
      expect(cycleTab(l, -1), 'a');
    });
  });

  group('cycleTab — wraps at the ends', () {
    test('next on the last tab wraps to the first', () {
      final l = leaf(['a', 'b', 'c'], 'c');
      expect(cycleTab(l, 1), 'a');
    });

    test('previous on the first tab wraps to the last', () {
      final l = leaf(['a', 'b', 'c'], 'a');
      expect(cycleTab(l, -1), 'c');
    });
  });

  group('cycleTab — no-op (null)', () {
    test('a single-tab pane does not cycle', () {
      expect(cycleTab(leaf(['a'], 'a'), 1), isNull);
      expect(cycleTab(leaf(['a'], 'a'), -1), isNull);
    });

    test('a pane with no tabs does not cycle', () {
      expect(cycleTab(leaf([], ''), 1), isNull);
    });

    test('active not in tabs (inconsistent state) does not guess a tab', () {
      expect(cycleTab(leaf(['a', 'b'], 'zzz'), 1), isNull);
    });
  });
}
