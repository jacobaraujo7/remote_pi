import 'package:flutter/widgets.dart';

/// Linha lógica apontada no terminal. Os identificadores de linha incluem
/// todos os trechos criados apenas por quebra visual e usam o espaço de
/// coordenadas nativo do respectivo renderizador.
class TerminalLineHit {
  const TerminalLineHit({
    required this.text,
    required this.firstViewportRow,
    required this.lastViewportRow,
  });

  final String text;
  final int firstViewportRow;
  final int lastViewportRow;
}

class TerminalContextMenuRequest {
  const TerminalContextMenuRequest({
    required this.globalPosition,
    required this.selectedText,
    required this.line,
  });

  final Offset globalPosition;
  final String selectedText;
  final TerminalLineHit? line;
}

typedef TerminalContextMenuCallback =
    void Function(TerminalContextMenuRequest request);
