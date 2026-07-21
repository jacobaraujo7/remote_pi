import 'dart:convert';

import 'package:cockpit/app/core/terminal/terminal_controller.dart';
import 'package:cockpit/app/core/terminal/xterm/xterm.dart' as xterm;

/// Extrai uma janela de linhas do buffer ativo de um [Terminal] pra CLI
/// `cockpit read-pane`/`read-task` (cobre o alt-screen de TUIs — lê o que está
/// pintado, texto plano sem ANSI). Cap duro de 2000 linhas por leitura. Linhas
/// em branco no rabo do viewport são descartadas antes de ancorar (senão o
/// tail de um shell parado viria vazio). `fromStart` ancora a janela no começo
/// do buffer; default = fim (tail). `offset` pula N linhas a partir da âncora.
/// A saída é sempre cronológica — os args só escolhem a janela.
Map<String, dynamic> readTerminalWindow(
  Object term,
  Map<String, dynamic> args,
) {
  const maxLines = 2000;
  final requested = switch (args['lines']) {
    final int n when n > 0 => n,
    _ => 100,
  };
  final lines = requested > maxLines ? maxLines : requested;
  final offset = switch (args['offset']) {
    final int n when n > 0 => n,
    _ => 0,
  };
  final fromStart = args['fromStart'] == true;

  final buf = switch (term) {
    final CockpitTerminalController controller => controller.plainLines(),
    final xterm.Terminal terminal => [
      for (var i = 0; i < terminal.buffer.lines.length; i++)
        terminal.buffer.lines[i].getText(),
    ],
    _ => throw ArgumentError.value(term, 'term', 'unsupported terminal'),
  };
  // Total efetivo: ignora o vazio do viewport abaixo da última linha escrita.
  var total = buf.length;
  while (total > 0 && buf[total - 1].isEmpty) {
    total--;
  }

  final start = fromStart
      ? (offset < total ? offset : total)
      : (total - offset - lines).clamp(0, total);
  final end = (start + lines).clamp(0, total);
  final out = StringBuffer();
  for (var i = start; i < end; i++) {
    if (i > start) out.write('\n');
    out.write(buf[i]);
  }
  return <String, dynamic>{
    'text': base64.encode(utf8.encode(out.toString())),
    'lines': end - start,
    'total': total,
    'truncated': requested > maxLines,
  };
}
