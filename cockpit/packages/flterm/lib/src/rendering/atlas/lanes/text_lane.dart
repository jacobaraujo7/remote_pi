import 'dart:math' show min;
import 'dart:ui';

import '../atlas_entry.dart';
import 'paragraph_lane.dart';

/// Rasterizes font-backed text glyphs into the text atlas.
class TextLane extends ParagraphLane {
  TextLane({super.initialSize, super.maxSize}) : super(entryLane: .text);

  /// Builds a paragraph for [text], packs it into the atlas, and returns
  /// an [AtlasEntry] with its source coordinates.
  ///
  /// The glyph is not composited into the atlas image until [ensureImage]
  /// is called. [span] controls how many cell widths the glyph occupies
  /// (2 for wide/CJK characters).
  AtlasEntry rasterizeText(
    String text, {
    required bool bold,
    required bool italic,
    int span = 1,
    bool centerInFirstCell = false,
    double sourcePadding = 0.0,
  }) {
    final pxCellWidth = (this.pxCellWidth * span).ceil().toDouble();
    final pxHeight = pxCellHeight.ceil().toDouble();

    // The sprite is positioned at the cell origin; the overhang width
    // overlaps into the adjacent cell's space without shifting the glyph.
    final overhang = italic ? pxItalicOverhang : 0.0;
    final pxWidth = pxCellWidth + overhang;

    final paragraph = buildParagraph(
      text,
      bold: bold,
      italic: italic,
      size: pxFontSize,
      width: double.infinity,
    );

    final isSingleCodepoint =
        text.length == 1 ||
        (text.length == 2 &&
            text.codeUnitAt(0) >= 0xD800 &&
            text.codeUnitAt(0) <= 0xDBFF &&
            text.codeUnitAt(1) >= 0xDC00 &&
            text.codeUnitAt(1) <= 0xDFFF);
    final textWidth = paragraph.maxIntrinsicWidth;
    final fitsConstrainedGlyph =
        span > 1 || (isSingleCodepoint && text.runes.first >= 0x80);
    final widthConstraint = fitsConstrainedGlyph && textWidth > pxCellWidth
        ? pxCellWidth / textWidth
        : 1.0;
    final heightConstraint =
        centerInFirstCell && isSingleCodepoint && paragraph.height > pxHeight
        ? pxHeight / paragraph.height
        : 1.0;
    // Oversized fallback symbols must fit without distorting their shape.
    final widthScale = isSingleCodepoint
        ? min(widthConstraint, heightConstraint)
        : widthConstraint;
    final heightScale = isSingleCodepoint ? widthScale : 1.0;
    final alignmentWidth = centerInFirstCell ? this.pxCellWidth : pxCellWidth;
    final paintedWidth = textWidth * widthScale;
    final bearingX = span > 1 && paintedWidth > 0.0
        ? ((alignmentWidth - paintedWidth) / 2).clamp(0.0, double.infinity)
        : 0.0;
    final bearingY = pxBaseline - paragraph.alphabeticBaseline * heightScale;
    final paintOffset = Offset(
      sourcePadding + bearingX,
      sourcePadding + bearingY,
    );
    late final AtlasEntry entry;
    try {
      entry = allocate(
        width: pxWidth + sourcePadding * 2,
        height: pxHeight + sourcePadding * 2,
        bearingX: -sourcePadding,
        bearingY: -sourcePadding,
      );
    } catch (_) {
      paragraph.dispose();
      rethrow;
    }

    addPendingParagraph(
      paragraph,
      entry,
      widthScale: widthScale,
      heightScale: heightScale,
      paintOffset: paintOffset,
    );
    return entry;
  }
}
