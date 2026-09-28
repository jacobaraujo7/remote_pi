import 'package:cockpit/app/cockpit/ui/states/panel_drag_sizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const min = 220.0;
  const max = 620.0;

  double drag(PanelDragSizer s, double dx) => s.update(dx, min: min, max: max);

  test('arraste dentro dos limites segue o ponteiro', () {
    final s = PanelDragSizer()..begin(300);
    expect(drag(s, 50), 350);
    expect(drag(s, 50), 400);
    expect(drag(s, -100), 300);
  });

  test('passar do máximo não descarta o excedente: o divisor volta a coincidir '
      'com o ponteiro na posição onde o limite foi atingido', () {
    final s = PanelDragSizer()..begin(600);
    expect(drag(s, 100), max, reason: 'clampa em 620');
    expect(drag(s, 100), max, reason: 'segue clampado (total = +200)');
    // O ponteiro volta 180px: o total vira +20, ou seja 620 — ainda no limite,
    // que é exatamente onde o ponteiro estava quando o clamp começou.
    expect(drag(s, -180), max);
    // Mais um pixel para dentro e a largura acompanha na hora.
    expect(drag(s, -1), 619);
  });

  test('mesma coisa no mínimo', () {
    final s = PanelDragSizer()..begin(240);
    expect(drag(s, -100), min);
    expect(drag(s, -100), min);
    expect(drag(s, 180), min);
    expect(drag(s, 1), 221);
  });

  test('begin refotografa a largura e zera o total', () {
    final s = PanelDragSizer()..begin(300);
    expect(drag(s, 500), max);
    s.begin(400);
    expect(drag(s, 10), 410);
  });
}
