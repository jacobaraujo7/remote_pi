import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:cockpit/app/cockpit/domain/entities/board_document.dart';
import 'package:cockpit/app/cockpit/ui/widgets/board_export.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final document = BoardDocument([
    const BoardItem(
      'a',
      BoardKind.process,
      -20,
      10,
      color: '#FF0000',
      label: '<script>',
    ),
    const BoardItem('b', BoardKind.decision, 220, 10),
    const BoardItem('edge', BoardKind.arrow, 0, 0, from: 'a', to: 'b'),
  ]);

  test(
    'PNG crops selection, paints its fill, and PDF contains a page',
    () async {
      final png = await boardPng(document, selected: {'a'});
      final codec = await ui.instantiateImageCodec(png);
      final image = (await codec.getNextFrame()).image;
      try {
        expect(image.width, 160);
        expect(image.height, 88);
        final bytes = (await image.toByteData())!;
        final offset = (image.width * 25 + 30) * 4;
        expect(Uint8List.sublistView(bytes, offset, offset + 4), [
          255,
          0,
          0,
          255,
        ]);
      } finally {
        image.dispose();
        codec.dispose();
      }
      final pdf = latin1.decode(await boardPdf(document));
      expect(pdf, startsWith('%PDF-'));
      expect(pdf, contains('/Type/Page'));
      expect(pdf.trimRight(), endsWith('%%EOF'));
    },
  );

  test(
    'a Mermaid thumbnail respects the stacking order in PNG and HTML',
    () async {
      final recorder = ui.PictureRecorder();
      ui.Canvas(
        recorder,
      ).drawColor(const ui.Color(0xff0000ff), ui.BlendMode.src);
      final picture = recorder.endRecording();
      final blue = await picture.toImage(8, 8);
      final thumbnail = base64Encode(
        (await blue.toByteData(
          format: ui.ImageByteFormat.png,
        ))!.buffer.asUint8List(),
      );
      blue.dispose();
      picture.dispose();
      final diagram = BoardItem(
        'diagram',
        BoardKind.mermaid,
        0,
        0,
        width: 80,
        height: 80,
        label: 'flowchart LR',
        thumbnail: thumbnail,
      );
      const note = BoardItem(
        'note',
        BoardKind.note,
        40,
        0,
        width: 80,
        height: 80,
        color: '#FF0000',
      );
      for (final front in [true, false]) {
        final board = BoardDocument(front ? [note, diagram] : [diagram, note]);
        final html = boardHtml(board);
        expect(html.indexOf('<image') > html.indexOf('<rect'), front);
        final codec = await ui.instantiateImageCodec(await boardPng(board));
        final image = (await codec.getNextFrame()).image;
        try {
          final rgba = (await image.toByteData())!;
          // 12 px export padding, then a point inside both items.
          final pixel = (image.width * 32 + 72) * 4;
          expect(rgba.getUint32(pixel), front ? 0x0000ffff : 0xff0000ff);
        } finally {
          image.dispose();
          codec.dispose();
        }
      }
    },
  );
  test(
    'the swimlane template paints connectors over lanes and behind services',
    () async {
      final source = await File(
        'cli/skills/cockpit-canvas/templates/swimlanes.canvas',
      ).readAsString();
      final board = BoardDocument.parse(source);
      final html = boardHtml(board);
      // The finance branch exits below the decision, clear of the "Não" label.
      expect(html, contains('M 355.0 143.0 V 211.5 H 572.5 V 280.0'));
      final backdrop = html.indexOf('#B3E3CB');
      final arrow = html.indexOf('stroke="#216C46"');
      expect(backdrop, greaterThanOrEqualTo(0));
      expect(arrow, greaterThan(backdrop));
      expect(html.indexOf('Agendar pagamento'), greaterThan(arrow));
      final codec = await ui.instantiateImageCodec(await boardPng(board));
      final image = (await codec.getNextFrame()).image;
      try {
        final data = (await image.toByteData())!;
        // In the middle of the first horizontal connector, between its shapes.
        final pixel = ((105 - 8) * image.width + (250 - 8)) * 4;
        expect(data.getUint8(pixel), lessThan(150));
      } finally {
        image.dispose();
        codec.dispose();
      }
    },
  );
  test('standalone HTML embeds SVG and escapes user labels', () {
    final html = boardHtml(document);
    expect(html, startsWith('<!doctype html>'));
    expect(html, contains('<svg'));
    expect(html, contains('&lt;script'));
    expect(html, isNot(contains('<script>')));
  });

  test('a pale connector label has a dark backing in SVG and PNG', () async {
    final board = BoardDocument([
      ...document.items.values.where((item) => item.id != 'edge'),
      const BoardItem(
        'edge',
        BoardKind.arrow,
        0,
        0,
        from: 'a',
        to: 'b',
        label: 'Sim',
        color: '#FFFF00',
      ),
    ]);
    final svg = boardSvgExport(board, selected: {'edge'});
    expect(svg, contains('fill="#FFFF00" stroke="#000000"'));
    final codec = await ui.instantiateImageCodec(
      await boardPng(board, selected: {'edge'}),
    );
    final image = (await codec.getNextFrame()).image;
    try {
      final data = (await image.toByteData())!;
      // Inside the backing, above the connector and below the glyphs.
      final pixel =
          ((image.height ~/ 2 + 9) * image.width + image.width ~/ 2) * 4;
      expect(data.getUint32(pixel), 0x000000ff);
    } finally {
      image.dispose();
      codec.dispose();
    }
  });

  test(
    'exporting just a connector crops both ends at the shape boundaries',
    () async {
      const selection = {'edge'};
      final html = boardHtml(document, selected: selection);
      expect(html, contains('viewBox="104.0 30.0 128.0 24.0"'));
      expect(html, isNot(contains('&lt;script')));
      final codec = await ui.instantiateImageCodec(
        await boardPng(document, selected: selection),
      );
      final image = (await codec.getNextFrame()).image;
      try {
        expect([image.width, image.height], [128, 24]);
      } finally {
        image.dispose();
        codec.dispose();
      }
    },
  );
}
