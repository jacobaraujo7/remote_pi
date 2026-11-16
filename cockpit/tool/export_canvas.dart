import 'dart:io';

import 'package:cockpit/app/cockpit/domain/entities/board_document.dart';
import 'package:cockpit/app/cockpit/domain/services/board_svg.dart';

/// Render with the same parser and connector geometry used by the editor.
void main(List<String> args) {
  if (args.length != 2 || !args.last.toLowerCase().endsWith('.svg')) {
    stderr.writeln(
      'Usage: dart run tool/export_canvas.dart drawing.canvas preview.svg',
    );
    exitCode = 64;
    return;
  }

  try {
    final document = BoardDocument.parse(File(args.first).readAsStringSync());
    // Leave room for wide glyphs when rendering without Flutter font metrics.
    final svg = boardSvg(
      document,
      measureLabel: (line) => line.runes.length * 14.0,
    );
    final output = File(args.last);
    output.createSync(exclusive: true);
    try {
      output.writeAsStringSync(svg, flush: true);
    } catch (_) {
      output.deleteSync();
      rethrow;
    }
  } catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}
