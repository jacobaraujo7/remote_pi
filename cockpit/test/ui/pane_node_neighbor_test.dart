import 'package:cockpit/app/cockpit/ui/states/pane_node.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  LeafPane leaf(String id) => LeafPane(id: id, tabs: [id], active: id);

  group('neighborLeaf — dois panes', () {
    test('lado a lado (split vertical): ←→ navegam, ↑↓ não', () {
      final tree = SplitPane(
        id: 'sp',
        dir: SplitDir.vertical,
        a: leaf('L'),
        b: leaf('R'),
        frac: 0.5,
      );
      expect(neighborLeaf(tree, 'L', PaneMove.right), 'R');
      expect(neighborLeaf(tree, 'R', PaneMove.left), 'L');
      expect(neighborLeaf(tree, 'L', PaneMove.left), isNull);
      expect(neighborLeaf(tree, 'R', PaneMove.right), isNull);
      expect(neighborLeaf(tree, 'L', PaneMove.up), isNull);
      expect(neighborLeaf(tree, 'L', PaneMove.down), isNull);
    });

    test('empilhados (split horizontal): ↑↓ navegam, ←→ não', () {
      final tree = SplitPane(
        id: 'sp',
        dir: SplitDir.horizontal,
        a: leaf('T'),
        b: leaf('B'),
        frac: 0.5,
      );
      expect(neighborLeaf(tree, 'T', PaneMove.down), 'B');
      expect(neighborLeaf(tree, 'B', PaneMove.up), 'T');
      expect(neighborLeaf(tree, 'T', PaneMove.up), isNull);
      expect(neighborLeaf(tree, 'T', PaneMove.left), isNull);
      expect(neighborLeaf(tree, 'T', PaneMove.right), isNull);
    });
  });

  group('neighborLeaf — árvore aninhada (coluna esquerda T/B + direita R)', () {
    // vertical( horizontal(LT, LB), R )
    final tree = SplitPane(
      id: 'root',
      dir: SplitDir.vertical,
      a: SplitPane(
        id: 'left',
        dir: SplitDir.horizontal,
        a: leaf('LT'),
        b: leaf('LB'),
        frac: 0.5,
      ),
      b: leaf('R'),
      frac: 0.5,
    );

    test('da coluna esquerda → direita cai em R', () {
      expect(neighborLeaf(tree, 'LT', PaneMove.right), 'R');
      expect(neighborLeaf(tree, 'LB', PaneMove.right), 'R');
    });

    test('de R → esquerda cai na pane de cima (a, determinístico)', () {
      expect(neighborLeaf(tree, 'R', PaneMove.left), 'LT');
    });

    test('dentro da coluna esquerda ↑↓ navegam', () {
      expect(neighborLeaf(tree, 'LT', PaneMove.down), 'LB');
      expect(neighborLeaf(tree, 'LB', PaneMove.up), 'LT');
    });

    test('R não tem vizinho acima/abaixo (só uma pane na coluna direita)', () {
      expect(neighborLeaf(tree, 'R', PaneMove.up), isNull);
      expect(neighborLeaf(tree, 'R', PaneMove.down), isNull);
      expect(neighborLeaf(tree, 'R', PaneMove.right), isNull);
    });
  });

  test('neighborLeaf — leaf inexistente devolve null', () {
    final tree = leaf('only');
    expect(neighborLeaf(tree, 'ghost', PaneMove.right), isNull);
    expect(neighborLeaf(tree, 'only', PaneMove.right), isNull);
  });
}
