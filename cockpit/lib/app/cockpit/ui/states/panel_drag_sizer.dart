/// Largura de um painel lateral durante o arraste da alça (card k38).
///
/// A regra é uma só, e é o conserto: o acumulado guarda **o quanto o ponteiro
/// andou desde o início do arraste**, e o clamp é aplicado só na leitura. O
/// clamp nunca volta para o acumulado.
///
/// Antes, cada update fazia `largura = (largura + dx).clamp(min, max)`. Ao
/// bater no limite, o excedente era jogado fora a cada frame: o ponteiro
/// continuava andando e a alça ficava parada, e daí em diante os dois andavam
/// separados — o divisor deixava de estar embaixo do cursor, que é a sensação
/// de "mouse preso". Guardando o total, o divisor volta a coincidir com o
/// ponteiro exatamente quando ele retorna à posição onde o limite foi atingido.
class PanelDragSizer {
  double _base = 0;
  double _total = 0;

  /// Largura no início do arraste (fotografada no `onHorizontalDragStart`).
  void begin(double width) {
    _base = width;
    _total = 0;
  }

  /// Soma [delta] ao total percorrido e devolve a largura resultante, clampada.
  /// [delta] já vem com o sinal certo pro lado do painel (ver `handleOnLeft`).
  double update(double delta, {required double min, required double max}) {
    _total += delta;
    return (_base + _total).clamp(min, max);
  }
}
