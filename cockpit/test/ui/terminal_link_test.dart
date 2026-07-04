// Detecção de link no buffer do terminal: URLs (navegador) e caminhos de
// arquivo (FileViewer), incluindo o sufixo `:linha`.

import 'package:cockpit/app/cockpit/ui/widgets/terminal_link.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

/// Escreve [text] na 1ª linha de um terminal e devolve o link sob a coluna [col].
TerminalLink? _linkAt(String text, int col, {bool detectFiles = true}) {
  final term = Terminal(maxLines: 100);
  term.resize(120, 24);
  term.write(text);
  return TerminalLinkDetector().linkAt(
    term,
    CellOffset(col, 0),
    detectFiles: detectFiles,
  );
}

void main() {
  group('TerminalLinkDetector — arquivos', () {
    test('detecta caminho relativo com extensão', () {
      final link = _linkAt('app/lib/config/dependencies.dart', 5);
      expect(link, isNotNull);
      expect(link!.kind, TerminalLinkKind.file);
      expect(link.target, 'app/lib/config/dependencies.dart');
      expect(link.line, isNull);
    });

    test('extrai o sufixo :linha', () {
      final link = _linkAt('lib/main.dart:42 erro', 3);
      expect(link!.kind, TerminalLinkKind.file);
      expect(link.target, 'lib/main.dart');
      expect(link.line, 42);
    });

    test('extrai :linha:col mas guarda só a linha', () {
      final link = _linkAt('lib/main.dart:42:7', 3);
      expect(link!.target, 'lib/main.dart');
      expect(link.line, 42);
    });

    test('caminho ancorado sem extensão vale', () {
      final link = _linkAt('./bin/run outra coisa', 3);
      expect(link!.kind, TerminalLinkKind.file);
      expect(link.target, './bin/run');
    });

    test('ignora prosa com barra sem extensão nem âncora', () {
      expect(_linkAt('sim and/or não', 5), isNull);
    });

    test('detectFiles=false desliga a detecção de arquivo', () {
      expect(_linkAt('lib/main.dart', 3, detectFiles: false), isNull);
    });
  });

  group('TerminalLinkDetector — URLs têm precedência', () {
    test('URL é detectada como kind url', () {
      final link = _linkAt('veja https://example.com/a/b.dart aqui', 10);
      expect(link!.kind, TerminalLinkKind.url);
      expect(link.target, 'https://example.com/a/b.dart');
    });
  });
}
