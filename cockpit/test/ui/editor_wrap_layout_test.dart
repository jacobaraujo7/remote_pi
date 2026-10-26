import 'package:cockpit/app/cockpit/ui/widgets/editor_overview_ruler.dart';
import 'package:cockpit/app/cockpit/ui/widgets/editor_wrap_layout.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Fonte de teste (FlutterTest): todo glifo é um quadrado de `fontSize` px,
  // então 10 caracteres = 100px e a altura de linha = 10px.
  const style = TextStyle(fontSize: 10, height: 1);
  const row = 10.0;

  EditorWrapLayout measured(List<String> lines, double width) =>
      EditorWrapLayout()..update(lines.join('\n'), width, style);

  test('linha longa ocupa N linhas visuais; vazia e curta ocupam uma', () {
    final layout = measured(['', 'abc', 'x' * 35], 100);

    expect(layout.height(0), row);
    expect(layout.height(1), row);
    expect(layout.height(2), 4 * row); // 35 chars em 100px = 4 linhas
    expect(layout.top(2), 2 * row);
    expect(layout.totalHeight, 6 * row);
  });

  test('lineAtY cai na linha lógica certa; abaixo do conteúdo fica fora', () {
    final layout = measured(['a', 'x' * 25, 'b'], 100);
    // tops: 0, 10, 40, 50

    expect(layout.lineAtY(-5), 0);
    expect(layout.lineAtY(0), 0);
    expect(layout.lineAtY(9.9), 0);
    expect(layout.lineAtY(10), 1);
    expect(layout.lineAtY(39.9), 1);
    expect(layout.lineAtY(40), 2);
    expect(layout.lineAtY(49.9), 2);
    expect(layout.lineAtY(50), 3); // abaixo do documento = nº de linhas
    expect(layout.lineAtY(500), 3);
  });

  test('largura nova invalida o cache e remede', () {
    final layout = measured(['x' * 20], 100);
    expect(layout.height(0), 2 * row);

    layout.update(['x' * 20].join('\n'), 50, style);
    expect(layout.height(0), 4 * row);
  });

  test('editar uma linha só muda a altura dela', () {
    final layout = measured(['a', 'b', 'c'], 100);
    expect(layout.totalHeight, 3 * row);

    layout.update(['a', 'x' * 15, 'c'].join('\n'), 100, style);
    expect(layout.height(0), row);
    expect(layout.height(1), 2 * row);
    expect(layout.height(2), row);
    expect(layout.top(2), 3 * row);
  });

  test('largura natural cabe na pane: uma linha visual, sem remedir', () {
    final layout = measured(['x' * 9, 'x' * 25], 100);
    expect(layout.height(0), row);
    expect(layout.height(1), 3 * row);

    // Estreita a pane: só a linha que não cabe muda de altura.
    layout.update(['x' * 9, 'x' * 25].join('\n'), 95, style);
    expect(layout.height(0), row);
    expect(layout.height(1), 3 * row);
  });

  test('mesmo texto, largura e estilo: não muda a revisão', () {
    const text = 'a\nbb';
    final layout = EditorWrapLayout()..update(text, 100, style);
    final rev = layout.revision;
    layout.update(text, 100, style);
    expect(layout.revision, rev);
  });

  test('overview com a tabela: linha e fronteira seguem as alturas reais', () {
    final layout = measured(['a', 'x' * 25, 'b'], 100); // tops 0, 10, 40, 50
    expect(
      overviewContentOffsetForLine(line: 3, lineHeight: row, wrap: layout),
      40,
    );
    expect(
      overviewContentOffsetForBoundary(
        boundary: 3,
        lineHeight: row,
        wrap: layout,
      ),
      50,
    );
    // Sem a tabela, a conta antiga (uma linha visual por linha).
    expect(overviewContentOffsetForLine(line: 3, lineHeight: row), 20);
    expect(
      overviewRulerLineForDy(
        dy: 45,
        trackHeight: 50,
        lineCount: 3,
        lineHeight: row,
        contentExtent: 50,
        wrap: layout,
      ),
      3,
    );
  });
}
