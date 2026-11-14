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

  test('standalone HTML embeds SVG and escapes user labels', () {
    final html = boardHtml(document);
    expect(html, startsWith('<!doctype html>'));
    expect(html, contains('<svg'));
    expect(html, contains('&lt;script'));
    expect(html, isNot(contains('<script>')));
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
