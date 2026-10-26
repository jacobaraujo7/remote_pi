import 'dart:convert';
import 'dart:typed_data';

import 'package:cockpit/app/core/terminal/terminal_controller.dart';
import 'package:flterm/flterm.dart' as ghost;
import 'package:flutter_test/flutter_test.dart';

ghost.ClipboardWrite _write(
  ghost.ClipboardLocation location,
  List<(String, String)> entries,
) => ghost.ClipboardWrite(
  name: 'test',
  granted: false,
  canRemember: false,
  location: location,
  contents: [
    for (final (mime, text) in entries)
      ghost.ClipboardContent(
        mime: mime,
        data: Uint8List.fromList(utf8.encode(text)),
      ),
  ],
);

void main() {
  test('OSC 52 pro clipboard padrão copia o text/plain', () {
    String? got;
    final r = GhosttyTerminalController.handleClipboardWrite(
      _write(ghost.ClipboardLocation.standard, [('text/plain', 'olá')]),
      writeClipboard: (t) => got = t,
    );
    expect(r, ghost.ClipboardWriteResult.success);
    expect(got, 'olá');
  });

  test('selection/primary (X11) não são suportados', () {
    var called = false;
    final r = GhosttyTerminalController.handleClipboardWrite(
      _write(ghost.ClipboardLocation.primary, [('text/plain', 'x')]),
      writeClipboard: (_) => called = true,
    );
    expect(r, ghost.ClipboardWriteResult.unsupported);
    expect(called, isFalse);
  });

  test('sem representação de texto → unsupported', () {
    final r = GhosttyTerminalController.handleClipboardWrite(
      _write(ghost.ClipboardLocation.standard, [('image/png', 'bin')]),
      writeClipboard: (_) {},
    );
    expect(r, ghost.ClipboardWriteResult.unsupported);
  });

  test('sem conteúdo = limpar', () {
    String? got;
    final r = GhosttyTerminalController.handleClipboardWrite(
      _write(ghost.ClipboardLocation.standard, const []),
      writeClipboard: (t) => got = t,
    );
    expect(r, ghost.ClipboardWriteResult.success);
    expect(got, '');
  });
}
