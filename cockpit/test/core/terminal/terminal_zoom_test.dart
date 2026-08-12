import 'package:cockpit/app/core/terminal/terminal_zoom.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Captura as constraints que o filho recebeu, para verificar em que espaço
/// lógico ele foi layoutado.
class _ProbeChild extends StatelessWidget {
  const _ProbeChild(this.onConstraints);
  final void Function(BoxConstraints) onConstraints;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      onConstraints(constraints);
      return const SizedBox.expand();
    },
  );
}

void main() {
  /// Monta a caixa dentro de um espaço fixo e devolve (constraints do filho,
  /// tamanho externo ocupado).
  Future<(BoxConstraints, Size)> pump(WidgetTester tester, double scale) async {
    late BoxConstraints childConstraints;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 400,
            height: 300,
            child: TerminalUnzoomBox(
              key: const Key('unzoom'),
              scale: scale,
              child: _ProbeChild((c) => childConstraints = c),
            ),
          ),
        ),
      ),
    );
    return (childConstraints, tester.getSize(find.byKey(const Key('unzoom'))));
  }

  testWidgets('sem zoom o filho é layoutado na caixa original', (tester) async {
    final (constraints, size) = await pump(tester, 1.0);

    expect(constraints.maxWidth, 400);
    expect(constraints.maxHeight, 300);
    expect(size, const Size(400, 300));
  });

  testWidgets('com zoom o filho recebe a caixa ampliada por scale', (
    tester,
  ) async {
    // 16/14: o mesmo que "Interface size" 16 produz no _AppZoom.
    final scale = 16 / 14;
    final (constraints, size) = await pump(tester, scale);

    // O filho pensa numa área MAIOR — é a área lógica real da janela, antes do
    // zoom global tê-la encolhido. É isso que faz o terminal medir a célula na
    // resolução física certa em vez de ampliar bitmap.
    expect(constraints.maxWidth, closeTo(400 * scale, 0.001));
    expect(constraints.maxHeight, closeTo(300 * scale, 0.001));

    // E, visto de fora, nada mudou: a caixa continua ocupando o mesmo espaço,
    // então nenhum ancestral corta a subárvore.
    expect(size, const Size(400, 300));
  });

  testWidgets('sem caixa definida devolve o filho intacto', (tester) async {
    late BoxConstraints childConstraints;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: [
            // Largura ilimitada: o SizedBox interno daria infinito.
            TerminalUnzoomBox(
              scale: 1.5,
              child: SizedBox(
                width: 50,
                height: 50,
                child: _ProbeChild((c) => childConstraints = c),
              ),
            ),
          ],
        ),
      ),
    );

    expect(childConstraints.hasBoundedWidth, isTrue);
    expect(childConstraints.maxWidth, 50);
  });
}
