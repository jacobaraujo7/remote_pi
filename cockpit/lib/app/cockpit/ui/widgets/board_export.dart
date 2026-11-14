import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../domain/entities/board_document.dart';
import '../../domain/services/board_svg.dart';
import 'board_painter.dart';

String boardSvgExport(BoardDocument board, {Set<String>? selected}) {
  final painter = TextPainter(textDirection: TextDirection.ltr);
  try {
    return boardSvg(
      board,
      selected: selected,
      measureLabel: (line) {
        painter.text = TextSpan(
          text: line,
          style: const TextStyle(fontFamily: 'sans-serif', fontSize: 14),
        );
        painter.layout();
        return painter.width;
      },
    );
  } finally {
    painter.dispose();
  }
}

String boardHtml(BoardDocument board, {Set<String>? selected}) =>
    '<!doctype html><html><head><meta charset="utf-8">'
    '<meta name="viewport" content="width=device-width,initial-scale=1">'
    '<title>Canvas Board</title><style>body{margin:1rem;background:white}'
    'svg{max-width:100%;height:auto}</style></head><body>'
    '${boardSvgExport(board, selected: selected)}</body></html>';

Future<Uint8List> boardPng(BoardDocument board, {Set<String>? selected}) async {
  final items = board.paintOrder
      .where((i) => selected == null || selected.contains(i.id))
      .toList();
  if (items.isEmpty) throw const FormatException('Empty selection');
  List<Offset> route(BoardItem edge) {
    final endpoints = boardEdgeEndpoints(board, edge);
    return boardRouteOffsets(endpoints);
  }

  final area = boardExportBounds(board, items);
  final bounds = Rect.fromLTWH(area.left, area.top, area.width, area.height);
  final width = bounds.width.ceil(), height = bounds.height.ceil();
  if (width * height > 32000000 || math.max(width, height) > 16384) {
    throw const FormatException('Canvas exceeds image size limit');
  }
  final thumbnails = <BoardItem, ui.Image>{};
  try {
    for (final item in items.where((i) => i.thumbnail != null)) {
      final codec = await ui.instantiateImageCodec(item.thumbnailBytes!);
      try {
        thumbnails[item] = (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..translate(-bounds.left, -bounds.top);
    canvas.drawRect(bounds, Paint()..color = Colors.white);
    BoardPainter(
      items,
      route,
      {},
      Colors.black,
      Colors.white,
      Colors.amber,
      const TextStyle(fontFamily: 'sans-serif', fontSize: 14),
      thumbnails: thumbnails,
    ).paint(canvas, bounds.size);
    final picture = recorder.endRecording();
    try {
      final bitmap = await picture.toImage(width, height);
      try {
        final bytes = await bitmap.toByteData(format: ui.ImageByteFormat.png);
        if (bytes == null) throw StateError('PNG encoding failed');
        return bytes.buffer.asUint8List(
          bytes.offsetInBytes,
          bytes.lengthInBytes,
        );
      } finally {
        bitmap.dispose();
      }
    } finally {
      picture.dispose();
    }
  } finally {
    for (final image in thumbnails.values) {
      image.dispose();
    }
  }
}

Future<Uint8List> boardPdf(BoardDocument board, {Set<String>? selected}) async {
  final image = pw.MemoryImage(await boardPng(board, selected: selected));
  final pdf = pw.Document(title: 'Canvas Board');
  final page = image.width! >= image.height!
      ? PdfPageFormat.a4.landscape
      : PdfPageFormat.a4;
  pdf.addPage(
    pw.Page(
      pageFormat: page,
      margin: const pw.EdgeInsets.all(18),
      build: (_) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
    ),
  );
  return pdf.save();
}
