import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../domain/entities/board_document.dart';
import '../../domain/services/board_svg.dart';
import 'board_painter.dart';

String boardHtml(BoardDocument board, {Set<String>? selected}) =>
    '<!doctype html><html><head><meta charset="utf-8">'
    '<meta name="viewport" content="width=device-width,initial-scale=1">'
    '<title>Canvas Board</title><style>body{margin:1rem;background:white}'
    'svg{max-width:100%;height:auto}</style></head><body>'
    '${boardSvg(board, selected: selected)}</body></html>';

Future<Uint8List> boardPng(BoardDocument board, {Set<String>? selected}) async {
  final items = board.items.values
      .where((i) => selected == null || selected.contains(i.id))
      .toList();
  if (items.isEmpty) throw const FormatException('Empty selection');
  Rect boundsOf(BoardItem i) => Rect.fromLTWH(i.x, i.y, i.width, i.height);
  List<Offset> route(BoardItem edge) {
    final a = boundsOf(board.items[edge.from]!);
    final b = boundsOf(board.items[edge.to]!);
    final right = a.center.dx <= b.center.dx;
    final start = right ? a.centerRight : a.centerLeft;
    final end = right ? b.centerLeft : b.centerRight;
    final mid = (start.dx + end.dx) / 2;
    return [start, Offset(mid, start.dy), Offset(mid, end.dy), end];
  }

  final bounds = items
      .map((i) {
        if (i.kind != BoardKind.arrow) return boundsOf(i);
        final path = route(i);
        return Rect.fromPoints(path.first, path.last).expandToInclude(
          Rect.fromCenter(
            center: Offset.lerp(path[1], path[2], .5)!,
            width: 120,
            height: 34,
          ),
        );
      })
      .reduce((a, b) => a.expandToInclude(b))
      .inflate(12);
  final width = bounds.width.ceil(), height = bounds.height.ceil();
  if (width * height > 32000000 || math.max(width, height) > 16384) {
    throw const FormatException('Canvas exceeds image size limit');
  }
  final thumbnails = <BoardItem, ui.Image>{};
  try {
    for (final item in items.where((i) => i.thumbnail != null)) {
      final codec = await ui.instantiateImageCodec(
        base64Decode(item.thumbnail!),
      );
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
    ).paint(canvas, bounds.size);
    for (final entry in thumbnails.entries) {
      paintImage(
        canvas: canvas,
        rect: boundsOf(entry.key),
        image: entry.value,
        fit: BoxFit.contain,
      );
    }
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
