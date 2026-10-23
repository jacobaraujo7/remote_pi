import 'package:flutter/widgets.dart';

/// Folga que o `RenderEditable` tira da largura antes de quebrar o texto
/// (`_caretMargin` = gap de 1px + `cursorWidth` 2px do `TextField`). Medir as
/// linhas na largura cheia do campo deixaria a tabela quebrar 3px depois do
/// campo e desalinhar o gutter.
const double kEditorWrapCaretMargin = 3;

/// Geometria vertical por **linha lógica** quando o editor quebra linha.
///
/// Sem quebra, cada linha lógica ocupa uma linha visual e `idx * lineHeight`
/// basta. Com quebra, uma linha ocupa N linhas visuais: esta tabela mede cada
/// uma num [TextPainter] na largura de quebra do campo e acumula os tops, para
/// o gutter (`itemExtentBuilder`), o reveal, o hover e o overview.
///
/// A quebra recomeça a cada `\n`, então medir linha a linha dá o mesmo layout
/// do campo. Cache por **texto** da linha: digitar só remede a linha que mudou.
/// A largura natural (sem quebra) de cada linha não depende da largura da
/// pane: numa mudança de largura (arrastar o split) só as linhas mais largas
/// que a pane são remedidas — as demais ocupam uma linha visual.
class EditorWrapLayout {
  double _width = -1;
  TextStyle? _style;
  double _rowHeight = 0;
  final Map<String, double> _heightByText = <String, double>{};
  final Map<String, double> _naturalWidthByText = <String, double>{};
  List<double> _tops = const <double>[0, 0];

  /// Recalcula os tops de [lines] quebradas em [width] (largura do campo, já
  /// sem [kEditorWrapCaretMargin]). [rowHeight] = altura de uma linha visual.
  void update(
    List<String> lines,
    double width,
    TextStyle style,
    double rowHeight,
  ) {
    if (style != _style || rowHeight != _rowHeight) {
      _naturalWidthByText.clear();
      _heightByText.clear();
      _style = style;
      _rowHeight = rowHeight;
    }
    if (width != _width) {
      _heightByText.clear();
      _width = width;
    }
    // Cache limitado: textos de linhas apagadas/editadas acumulam.
    final cap = lines.length * 4 + 64;
    if (_naturalWidthByText.length > cap) _naturalWidthByText.clear();
    if (_heightByText.length > cap) _heightByText.clear();
    final tops = List<double>.filled(lines.length + 1, 0);
    for (var i = 0; i < lines.length; i++) {
      tops[i + 1] = tops[i] + _heightOf(lines[i]);
    }
    if (!_sameTops(tops, _tops)) _revision++;
    _tops = tops;
  }

  static bool _sameTops(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  int _revision = 0;

  /// Sobe quando algum top muda — quem pinta a partir da tabela (overview)
  /// compara a revisão, já que o objeto é mutável e a referência não muda.
  int get revision => _revision;

  double _heightOf(String line) {
    if (line.isEmpty) return _rowHeight;
    final natural = _naturalWidthByText[line] ??= _naturalWidth(line);
    if (natural <= _width) return _rowHeight;
    final cached = _heightByText[line];
    if (cached != null) return cached;
    final painter = TextPainter(
      text: TextSpan(text: line, style: _style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: _width.clamp(1.0, double.infinity));
    // Nunca menos que uma linha visual (mesma métrica do campo sem quebra).
    final h = painter.height < _rowHeight ? _rowHeight : painter.height;
    painter.dispose();
    return _heightByText[line] = h;
  }

  double _naturalWidth(String line) {
    final painter = TextPainter(
      text: TextSpan(text: line, style: _style),
      textDirection: TextDirection.ltr,
    )..layout();
    final w = painter.width;
    painter.dispose();
    return w;
  }

  /// Nº de linhas lógicas medidas.
  int get lineCount => _tops.length - 1;

  /// Y (conteúdo) do topo da linha lógica [line] (base 0).
  double top(int line) => _tops[line.clamp(0, lineCount)];

  /// Altura da linha lógica [line] (base 0) = N linhas visuais.
  double height(int line) {
    if (line < 0 || line >= lineCount) return _rowHeight;
    return _tops[line + 1] - _tops[line];
  }

  /// Altura total do conteúdo (sem folgas).
  double get totalHeight => _tops.last;

  /// Linha lógica (base 0) que contém o y [y] do conteúdo — busca binária nos
  /// tops. Fora do conteúdo, satura na primeira/última linha.
  int lineAtY(double y) {
    if (lineCount <= 0 || y <= 0) return 0;
    var lo = 0;
    var hi = lineCount - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_tops[mid] <= y) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }
}
