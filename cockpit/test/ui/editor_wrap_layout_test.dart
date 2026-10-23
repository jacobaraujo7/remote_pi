import 'package:cockpit/app/cockpit/ui/widgets/editor_wrap_layout.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Fonte de teste (FlutterTest): todo glifo é um quadrado de `fontSize` px,
  // então 10 caracteres = 100px e a altura de linha = 10px.
  const style = TextStyle(fontSize: 10, height: 1);
  const row = 10.0;

  test('linha longa ocupa N linhas visuais; vazia e curta ocupam uma', () {
    final layout = EditorWrapLayout()
      ..update(['', 'abc', 'x' * 35], 100, style, row);

    expect(layout.height(0), row);
    expect(layout.height(1), row);
    expect(layout.height(2), 4 * row); // 35 chars em 100px = 4 linhas
    expect(layout.top(2), 2 * row);
    expect(layout.totalHeight, 6 * row);
  });

  test('lineAtY cai na linha lógica certa, inclusive nas bordas', () {
    final layout = EditorWrapLayout()
      ..update(['a', 'x' * 25, 'b'], 100, style, row);
    // tops: 0, 10, 40, 50

    expect(layout.lineAtY(-5), 0);
    expect(layout.lineAtY(0), 0);
    expect(layout.lineAtY(9.9), 0);
    expect(layout.lineAtY(10), 1);
    expect(layout.lineAtY(39.9), 1);
    expect(layout.lineAtY(40), 2);
    expect(layout.lineAtY(500), 2);
  });

  test('largura nova invalida o cache e remede', () {
    final layout = EditorWrapLayout()..update(['x' * 20], 100, style, row);
    expect(layout.height(0), 2 * row);

    layout.update(['x' * 20], 50, style, row);
    expect(layout.height(0), 4 * row);
  });

  test('editar uma linha só muda a altura dela', () {
    final layout = EditorWrapLayout()..update(['a', 'b', 'c'], 100, style, row);
    expect(layout.totalHeight, 3 * row);

    layout.update(['a', 'x' * 15, 'c'], 100, style, row);
    expect(layout.height(0), row);
    expect(layout.height(1), 2 * row);
    expect(layout.height(2), row);
    expect(layout.top(2), 3 * row);
  });
}
