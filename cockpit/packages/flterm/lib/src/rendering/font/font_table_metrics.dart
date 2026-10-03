import 'dart:typed_data';

import 'package:meta/meta.dart';

/// Parses font table metrics from raw TrueType/OpenType font file bytes.
///
/// Reads the `head`, `hhea`, `post`, and `OS/2` tables to extract exact
/// decoration metrics. Returns `null` if the data is malformed or missing
/// required tables (`head` and `hhea`).
///
/// Zero-valued thickness fields (underline or strikethrough) are treated
/// as broken and returned as `null`, since they signal a degenerate font
/// table that should fall back to heuristic estimation.
///
/// ```dart
/// final metrics = parseFontTableMetrics(fontBytes);
/// if (metrics != null) {
///   final ppu = fontSize / metrics.unitsPerEm;
///   final thickness = metrics.underlineThickness! * ppu;
/// }
/// ```
FontTableMetrics? parseFontTableMetrics(Uint8List data) {
  if (data.length < 12) return null;

  final byteData = ByteData.sublistView(data);

  final numTables = byteData.getUint16(4);
  if (data.length < 12 + numTables * 16) return null;

  final tables = _readTableDirectory(data, byteData, numTables);
  if (tables == null) return null;

  final head = tables.head;
  final hhea = tables.hhea;

  if (head == null || hhea == null) return null;
  if (head.length < 20 || hhea.length < 10) return null;

  // head: unitsPerEm (uint16 @ +18).
  final unitsPerEm = byteData.getUint16(head.offset + 18);
  if (unitsPerEm == 0) return null;

  // hhea: ascent (int16 @ +4), descent (int16 @ +6), lineGap (int16 @ +8).
  final ascent = byteData.getInt16(hhea.offset + 4);
  final descent = byteData.getInt16(hhea.offset + 6);
  final lineGap = byteData.getInt16(hhea.offset + 8);

  final underline = _readUnderlineMetrics(byteData, tables.post);
  final strike = _readOs2Metrics(byteData, tables.os2);

  return FontTableMetrics(
    unitsPerEm: unitsPerEm,
    ascent: ascent,
    descent: descent,
    lineGap: lineGap,
    underlinePosition: underline.position,
    underlineThickness: underline.thickness,
    strikethroughPosition: strike.position,
    strikethroughThickness: strike.thickness,
    capHeight: strike.capHeight,
    exHeight: strike.exHeight,
  );
}

({int? position, int? thickness, int? capHeight, int? exHeight})
_readOs2Metrics(ByteData byteData, _FontTableSlice? table) {
  if (table == null || table.length < 30) {
    return (position: null, thickness: null, capHeight: null, exHeight: null);
  }

  final os2Version = byteData.getUint16(table.offset);
  final rawThickness = byteData.getInt16(table.offset + 26);
  final rawPosition = byteData.getInt16(table.offset + 28);
  int? capHeight;
  int? exHeight;
  if (os2Version >= 2 && table.length >= 90) {
    final rawExHeight = byteData.getInt16(table.offset + 86);
    final rawCapHeight = byteData.getInt16(table.offset + 88);
    if (rawExHeight > 0) exHeight = rawExHeight;
    if (rawCapHeight > 0) capHeight = rawCapHeight;
  }

  return (
    position: rawThickness != 0 || rawPosition != 0 ? rawPosition : null,
    thickness: rawThickness != 0 ? rawThickness : null,
    capHeight: capHeight,
    exHeight: exHeight,
  );
}

({
  _FontTableSlice? head,
  _FontTableSlice? hhea,
  _FontTableSlice? post,
  _FontTableSlice? os2,
})?
_readTableDirectory(Uint8List data, ByteData byteData, int numTables) {
  _FontTableSlice? head;
  _FontTableSlice? hhea;
  _FontTableSlice? post;
  _FontTableSlice? os2;

  for (var i = 0; i < numTables; i++) {
    final entryOffset = 12 + i * 16;
    final tag = String.fromCharCodes(data, entryOffset, entryOffset + 4);
    final offset = byteData.getUint32(entryOffset + 8);
    final length = byteData.getUint32(entryOffset + 12);
    if (offset > data.length || length > data.length - offset) return null;

    switch (tag) {
      case 'head':
        head = (offset: offset, length: length);
      case 'hhea':
        hhea = (offset: offset, length: length);
      case 'post':
        post = (offset: offset, length: length);
      case 'OS/2':
        os2 = (offset: offset, length: length);
    }
  }

  return (head: head, hhea: hhea, post: post, os2: os2);
}

({int? position, int? thickness}) _readUnderlineMetrics(
  ByteData byteData,
  _FontTableSlice? table,
) {
  if (table == null || table.length < 12) {
    return (position: null, thickness: null);
  }

  final rawPosition = byteData.getInt16(table.offset + 8);
  final rawThickness = byteData.getInt16(table.offset + 10);
  return (
    position: rawThickness != 0 || rawPosition != 0 ? rawPosition : null,
    thickness: rawThickness != 0 ? rawThickness : null,
  );
}

typedef _FontTableSlice = ({int offset, int length});

/// Metrics extracted from a TrueType/OpenType font's binary tables.
///
/// Parsed from the `head`, `hhea`, `post`, and `OS/2` tables. All values
/// are in font design units; convert to pixels with
/// `value * fontSize / unitsPerEm`.
///
/// See also:
/// - [parseFontTableMetrics], which creates this from raw font bytes.
@immutable
final class FontTableMetrics {
  /// Font design units per em square.
  final int unitsPerEm;

  /// Typographic ascent in font units (positive, above baseline).
  final int ascent;

  /// Typographic descent in font units (negative, below baseline).
  final int descent;

  /// Line gap in font units.
  final int lineGap;

  /// Underline position in font units (negative = below baseline).
  /// Null if the font's `post` table has a degenerate value.
  final int? underlinePosition;

  /// Underline thickness in font units.
  /// Null if the font's `post` table has a degenerate value.
  final int? underlineThickness;

  /// Strikethrough position in font units (positive = above baseline).
  /// Null if the font's `OS/2` table has a degenerate value.
  final int? strikethroughPosition;

  /// Strikethrough thickness in font units.
  /// Null if the font's `OS/2` table has a degenerate value.
  final int? strikethroughThickness;

  /// Cap height in font units. Null if not available (OS/2 version < 2).
  final int? capHeight;

  /// x-height in font units. Null if not available (OS/2 version < 2).
  final int? exHeight;

  const FontTableMetrics({
    required this.unitsPerEm,
    required this.ascent,
    required this.descent,
    required this.lineGap,
    this.underlinePosition,
    this.underlineThickness,
    this.strikethroughPosition,
    this.strikethroughThickness,
    this.capHeight,
    this.exHeight,
  });
}
