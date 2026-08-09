import 'package:flutter/widgets.dart';

/// Cancela o zoom global do app para a subárvore do terminal.
///
/// O `_AppZoom` (app_widget.dart) faz o app inteiro ser layoutado numa tela
/// lógica menor (`size / scale`) e depois amplia tudo com um `FittedBox`. Para
/// vetor isso é perfeito (o Skia re-rasteriza); para o terminal não, porque o
/// flterm pinta a partir de um atlas de glifos **já rasterizado**, e ampliar
/// bitmap borra. Medido num monitor de DPR 1: 1.14x de ampliação.
///
/// Aqui a operação inversa é aplicada: o filho é layoutado numa caixa [scale]
/// vezes MAIOR (ou seja, de volta ao tamanho lógico real da janela) e reduzido
/// por `1/scale`. Composto com o zoom externo a matriz resultante é a
/// identidade, então nada é reamostrado. Quem repõe o tamanho visual é o
/// **tamanho da fonte**, multiplicado por [scale] pelo chamador.
///
/// `FittedBox` e não `Transform.scale` pela mesma razão documentada no
/// `_AppZoom`: ele reporta ao pai o tamanho da caixa, e não o do filho
/// ampliado, então nenhum ancestral corta a subárvore. Hit-test e gestos são
/// convertidos para o espaço do filho automaticamente.
class TerminalUnzoomBox extends StatelessWidget {
  const TerminalUnzoomBox({
    super.key,
    required this.scale,
    required this.child,
  });

  /// Zoom do `_AppZoom` a desfazer (`interfaceSize / 14`). `1.0` é no-op.
  final double scale;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if ((scale - 1.0).abs() < 0.001) return child;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Sem caixa definida não há o que compensar (e o SizedBox abaixo daria
        // infinito). Devolver o filho intacto degrada para o render de antes,
        // que é ruim mas não quebrado.
        if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) {
          return child;
        }
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        return SizedBox(
          width: width,
          height: height,
          child: FittedBox(
            fit: BoxFit.fill,
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width * scale,
              height: height * scale,
              child: child,
            ),
          ),
        );
      },
    );
  }
}
