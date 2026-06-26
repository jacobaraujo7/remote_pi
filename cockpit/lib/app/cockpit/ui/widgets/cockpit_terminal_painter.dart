// Fork do `TerminalPainter` do xterm (src/ui/painter.dart) pro cockpit. Trazido
// pra dentro pra controlarmos a **pintura de célula** — o último pedaço que ainda
// vivia no pacote. Reusa `palette_builder`, `paragraph_cache` e os glifos
// procedurais (`builtin_glyphs`) do xterm via impl imports; só a lógica que
// precisamos mexer fica aqui.
//
// Mudança vs. o original: **sublinhado desenhado por nós**. O xterm passa
// `underline: true` pro `TextStyle` da fonte e desenha um `Paragraph` por
// caractere — o sublinhado sai segmentado e grosso por célula, "riscando" o texto
// e atrapalhando a leitura (links/títulos do Claude). Aqui o glifo é pintado sem
// decoração e o sublinhado vira uma hairline fina, crisp (`isAntiAlias=false`) e
// contínua (+1px de largura emenda com a célula seguinte), no rodapé da célula.
//
// ignore_for_file: implementation_imports
import 'dart:ui';
import 'package:flutter/painting.dart';

import 'package:xterm/src/ui/builtin_glyphs.dart';
import 'package:xterm/src/ui/palette_builder.dart';
import 'package:xterm/src/ui/paragraph_cache.dart';
import 'package:xterm/xterm.dart';

/// Encapsulates the logic for painting various terminal elements.
class CockpitTerminalPainter {
  CockpitTerminalPainter({
    required TerminalTheme theme,
    required TerminalStyle textStyle,
    required TextScaler textScaler,
    required double devicePixelRatio,
  }) : _textStyle = textStyle,
       _theme = theme,
       _textScaler = textScaler,
       _devicePixelRatio = devicePixelRatio;

  /// A lookup table from terminal colors to Flutter colors.
  late var _colorPalette = PaletteBuilder(_theme).build();

  /// Size of each character in the terminal.
  late var _cellSize = _measureCharSize();

  /// The cached for cells in the terminal. Should be cleared when the same
  /// cell no longer produces the same visual output. For example, when
  /// [_textStyle] is changed, or when the system font changes.
  final _paragraphCache = ParagraphCache(10240);

  TerminalStyle get textStyle => _textStyle;
  TerminalStyle _textStyle;
  set textStyle(TerminalStyle value) {
    if (value == _textStyle) return;
    _textStyle = value;
    _cellSize = _measureCharSize();
    _paragraphCache.clear();
  }

  TextScaler get textScaler => _textScaler;
  TextScaler _textScaler = TextScaler.linear(1.0);
  set textScaler(TextScaler value) {
    if (value == _textScaler) return;
    _textScaler = value;
    _cellSize = _measureCharSize();
    _paragraphCache.clear();
  }

  TerminalTheme get theme => _theme;
  TerminalTheme _theme;
  set theme(TerminalTheme value) {
    if (value == _theme) return;
    _theme = value;
    _colorPalette = PaletteBuilder(value).build();
    _paragraphCache.clear();
  }

  /// Densidade física da tela (pode mudar ao arrastar a janela entre monitores).
  /// O [cellSize] é encaixado nesse grid (ver [_snapToDevicePixel]); o glifo
  /// (Paragraph) é independente de DPR, então o cache de parágrafo não precisa
  /// ser limpo aqui — só re-medimos a célula.
  double get devicePixelRatio => _devicePixelRatio;
  double _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (value == _devicePixelRatio) return;
    _devicePixelRatio = value;
    _cellSize = _measureCharSize();
  }

  /// Arredonda uma dimensão lógica pro pixel físico mais próximo. Assim a largura
  /// de célula × DPR vira inteiro → toda origem de célula (`i * cellWidth`) cai
  /// num pixel inteiro do device. É o que iTerm2/Ghostty fazem; sem isso a
  /// métrica fracionária do xterm perde fatias de cobertura → blocos pálidos e
  /// costurados, texto mais borrado.
  double _snapToDevicePixel(double logical) {
    final dpr = _devicePixelRatio;
    if (dpr <= 0) return logical;
    final snapped = (logical * dpr).roundToDouble() / dpr;
    return snapped <= 0 ? logical : snapped;
  }

  Size _measureCharSize() {
    const test = 'mmmmmmmmmm';

    final textStyle = _textStyle.toTextStyle();
    final builder = ParagraphBuilder(textStyle.getParagraphStyle());
    builder.pushStyle(textStyle.getTextStyle(textScaler: _textScaler));
    builder.addText(test);

    final paragraph = builder.build();
    paragraph.layout(ParagraphConstraints(width: double.infinity));

    final result = Size(
      _snapToDevicePixel(paragraph.maxIntrinsicWidth / test.length),
      _snapToDevicePixel(paragraph.height),
    );

    paragraph.dispose();
    return result;
  }

  /// The size of each character in the terminal.
  Size get cellSize => _cellSize;

  /// When the set of font available to the system changes, call this method to
  /// clear cached state related to font rendering.
  void clearFontCache() {
    _cellSize = _measureCharSize();
    _paragraphCache.clear();
  }

  /// Paints the cursor based on the current cursor type.
  void paintCursor(
    Canvas canvas,
    Offset offset, {
    required TerminalCursorType cursorType,
    bool hasFocus = true,
  }) {
    final paint = Paint()
      ..color = _theme.cursor
      ..strokeWidth = 1;

    if (!hasFocus) {
      paint.style = PaintingStyle.stroke;
      canvas.drawRect(offset & _cellSize, paint);
      return;
    }

    switch (cursorType) {
      case TerminalCursorType.block:
        paint.style = PaintingStyle.fill;
        canvas.drawRect(offset & _cellSize, paint);
        return;
      case TerminalCursorType.underline:
        return canvas.drawLine(
          Offset(offset.dx, _cellSize.height - 1),
          Offset(offset.dx + _cellSize.width, _cellSize.height - 1),
          paint,
        );
      case TerminalCursorType.verticalBar:
        return canvas.drawLine(
          Offset(offset.dx, 0),
          Offset(offset.dx, _cellSize.height),
          paint,
        );
    }
  }

  @pragma('vm:prefer-inline')
  void paintHighlight(Canvas canvas, Offset offset, int length, Color color) {
    final endOffset = offset.translate(
      length * _cellSize.width,
      _cellSize.height,
    );

    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    canvas.drawRect(Rect.fromPoints(offset, endOffset), paint);
  }

  /// Paints [line] to [canvas] at [offset]. The x offset of [offset] is usually
  /// 0, and the y offset is the top of the line.
  void paintLine(Canvas canvas, Offset offset, BufferLine line) {
    final cellData = CellData.empty();
    final cellWidth = _cellSize.width;

    for (var i = 0; i < line.length; i++) {
      line.getCellData(i, cellData);

      final charWidth = cellData.content >> CellContent.widthShift;
      final cellOffset = offset.translate(i * cellWidth, 0);

      paintCell(canvas, cellOffset, cellData);

      if (charWidth == 2) {
        i++;
      }
    }
  }

  @pragma('vm:prefer-inline')
  void paintCell(Canvas canvas, Offset offset, CellData cellData) {
    paintCellBackground(canvas, offset, cellData);
    paintCellForeground(canvas, offset, cellData);
  }

  /// Paints the character in the cell represented by [cellData] to [canvas] at
  /// [offset].
  @pragma('vm:prefer-inline')
  void paintCellForeground(Canvas canvas, Offset offset, CellData cellData) {
    final charCode = cellData.content & CellContent.codepointMask;
    final cellFlags = cellData.flags;
    final underlined = cellFlags & CellFlags.underline != 0;

    // Célula vazia (nunca escrita): nada — nem sublinhado, pra a linha não vazar
    // pra além do texto. Espaços de verdade (0x20) têm content != 0 e caem no
    // caminho normal, então o sublinhado emenda entre palavras.
    if (charCode == 0) return;

    if (paintBuiltinGlyph(
      canvas,
      offset,
      _cellSize,
      charCode,
      _resolveForegroundColor(cellData),
    )) {
      if (underlined) _paintUnderline(canvas, offset, cellData);
      return;
    }

    final cacheKey = cellData.getHash() ^ _textScaler.hashCode;
    var paragraph = _paragraphCache.getLayoutFromCache(cacheKey);

    if (paragraph == null) {
      final color = _resolveForegroundColor(cellData);

      // Sem `underline:` aqui de propósito — nós o desenhamos em
      // [_paintUnderline], contínuo e fino. (Por isso some o workaround
      // 0x20→0xA0 do original: a fonte não pinta mais sublinhado.)
      final style = _textStyle.toTextStyle(
        color: color,
        bold: cellFlags & CellFlags.bold != 0,
        italic: cellFlags & CellFlags.italic != 0,
      );

      final char = String.fromCharCode(charCode);

      paragraph = _paragraphCache.performAndCacheLayout(
        char,
        style,
        _textScaler,
        cacheKey,
      );
    }

    canvas.drawParagraph(paragraph, offset);

    if (underlined) _paintUnderline(canvas, offset, cellData);
  }

  /// Sublinhado próprio: hairline fina, crisp e contínua no rodapé da célula.
  /// Substitui a decoração por-célula da fonte (segmentada/grossa). `+1` na
  /// largura emenda com a célula seguinte; `isAntiAlias=false` mantém 1px nítido.
  @pragma('vm:prefer-inline')
  void _paintUnderline(Canvas canvas, Offset offset, CellData cellData) {
    final thickness = (_cellSize.height / 14).clamp(1.0, 2.0).floorToDouble();
    final paint = Paint()
      ..color = _resolveForegroundColor(cellData)
      ..isAntiAlias = false;
    canvas.drawRect(
      Rect.fromLTWH(
        offset.dx,
        offset.dy + _cellSize.height - thickness,
        _cellSize.width + 1,
        thickness,
      ),
      paint,
    );
  }

  /// The effective foreground color of [cellData], honoring the inverse and
  /// faint flags. Shared by the font and the procedural ([paintBuiltinGlyph])
  /// rendering paths.
  Color _resolveForegroundColor(CellData cellData) {
    final cellFlags = cellData.flags;
    var color = cellFlags & CellFlags.inverse == 0
        ? resolveForegroundColor(cellData.foreground)
        : resolveBackgroundColor(cellData.background);
    if (cellFlags & CellFlags.faint != 0) {
      color = color.withValues(alpha: 0.5);
    }
    return color;
  }

  /// Paints the background of a cell represented by [cellData] to [canvas] at
  /// [offset].
  @pragma('vm:prefer-inline')
  void paintCellBackground(Canvas canvas, Offset offset, CellData cellData) {
    late Color color;
    final colorType = cellData.background & CellColor.typeMask;

    if (cellData.flags & CellFlags.inverse != 0) {
      color = resolveForegroundColor(cellData.foreground);
    } else if (colorType == CellColor.normal) {
      return;
    } else {
      color = resolveBackgroundColor(cellData.background);
    }

    final paint = Paint()..color = color;
    final doubleWidth = cellData.content >> CellContent.widthShift == 2;
    final widthScale = doubleWidth ? 2 : 1;
    final size = Size(_cellSize.width * widthScale + 1, _cellSize.height);
    canvas.drawRect(offset & size, paint);
  }

  /// Get the effective foreground color for a cell from information encoded in
  /// [cellColor].
  @pragma('vm:prefer-inline')
  Color resolveForegroundColor(int cellColor) {
    final colorType = cellColor & CellColor.typeMask;
    final colorValue = cellColor & CellColor.valueMask;

    switch (colorType) {
      case CellColor.normal:
        return _theme.foreground;
      case CellColor.named:
      case CellColor.palette:
        return _colorPalette[colorValue];
      case CellColor.rgb:
      default:
        return Color(colorValue | 0xFF000000);
    }
  }

  /// Get the effective background color for a cell from information encoded in
  /// [cellColor].
  @pragma('vm:prefer-inline')
  Color resolveBackgroundColor(int cellColor) {
    final colorType = cellColor & CellColor.typeMask;
    final colorValue = cellColor & CellColor.valueMask;

    switch (colorType) {
      case CellColor.normal:
        return _theme.background;
      case CellColor.named:
      case CellColor.palette:
        return _colorPalette[colorValue];
      case CellColor.rgb:
      default:
        return Color(colorValue | 0xFF000000);
    }
  }
}
