import 'package:cockpit/app/cockpit/ui/states/pane_node.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  LeafPane leaf(String id) => LeafPane(id: id, tabs: [id], active: id);

  SplitPane split(String id, double frac, {SplitDir dir = SplitDir.vertical}) =>
      SplitPane(id: id, dir: dir, a: leaf('L'), b: leaf('R'), frac: frac);

  group('findSplit', () {
    test('acha o split por id (aninhado) e devolve o frac atual', () {
      final tree = SplitPane(
        id: 'outer',
        dir: SplitDir.vertical,
        a: leaf('L'),
        b: split('inner', 0.3, dir: SplitDir.horizontal),
        frac: 0.6,
      );
      expect(findSplit(tree, 'outer')?.frac, 0.6);
      expect(findSplit(tree, 'inner')?.frac, 0.3);
      expect(findSplit(tree, 'missing'), isNull);
      expect(findSplit(leaf('L'), 'x'), isNull);
    });
  });

  group('drag do divisor — acumulação de deltas incrementais', () {
    // Reproduz o padrão do resizeSplitBy: cada onPanUpdate traz um delta
    // incremental e vários podem chegar antes do rebuild. Somar sobre o frac
    // ATUAL da árvore (lido via findSplit) tem que acumular — se dependesse de
    // um `aSize` capturado no build, os deltas do mesmo frame se perderiam.
    PaneNode nudge(PaneNode tree, String id, double dFrac) {
      final cur = findSplit(tree, id)!.frac;
      return setFrac(tree, id, (cur + dFrac).clamp(0.16, 0.84));
    }

    test('vários deltas no mesmo frame somam (não sobrescrevem)', () {
      PaneNode tree = split('s', 0.5);
      for (final d in [0.1, 0.05, 0.05]) {
        tree = nudge(tree, 's', d);
      }
      expect(findSplit(tree, 's')!.frac, closeTo(0.7, 1e-9));
    });

    test('deltas negativos também acumulam', () {
      PaneNode tree = split('s', 0.5);
      for (final d in [-0.1, -0.1]) {
        tree = nudge(tree, 's', d);
      }
      expect(findSplit(tree, 's')!.frac, closeTo(0.3, 1e-9));
    });

    test('clampa nos limites (0.16..0.84) sem estourar', () {
      PaneNode tree = split('s', 0.8);
      for (var i = 0; i < 10; i++) {
        tree = nudge(tree, 's', 0.1);
      }
      expect(findSplit(tree, 's')!.frac, 0.84);
    });
  });
}
