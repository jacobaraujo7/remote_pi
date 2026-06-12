import 'dart:async';
import 'dart:convert';

import 'package:cockpit/domain/contracts/terminal_gateway.dart';
import 'package:cockpit/ui/cockpit/session/pane_item.dart';
import 'package:xterm/xterm.dart';

/// Uma aba de terminal: um shell num PTY ([TerminalGateway]) ligado a um
/// emulador [Terminal] do xterm. O `TerminalView` (na PaneView) renderiza
/// `terminal`. Mata o PTY no `dispose` (sem órfão).
class TerminalSession extends PaneItem {
  TerminalSession({
    required this.id,
    required this.projectId,
    required this.workingDirectory,
    required TerminalGateway gateway,
    String? title,
  }) : _gateway = gateway,
       _title = title ?? 'New terminal' {
    terminal = Terminal(maxLines: 10000);

    // Sobe o shell e liga os dois lados. O `.cast<List<int>>()` re-vincula o
    // tipo do stream (o PTY emite Uint8List) para o `utf8.decoder` aceitar e
    // decodificar em streaming (trata multibyte partido entre chunks).
    _gateway.start(workingDirectory: workingDirectory, rows: 25, columns: 80);
    _sub = _gateway.output
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(terminal.write);
    terminal.onOutput = (data) => _gateway.write(utf8.encode(data));
    terminal.onResize = (width, height, pixelWidth, pixelHeight) =>
        _gateway.resize(height, width);
    // Programas mudam o título da janela via OSC 0/2 (ex.: shell mostra o cwd,
    // `vim`/`ssh` mostram o arquivo/host). Refletimos isso no nome da aba.
    terminal.onTitleChange = (osc) => rename(_shortTitle(osc));
  }

  /// Encurta títulos longos pra caber melhor na aba. Caminhos viram o último
  /// segmento; `~` é mantido; o resto vai como veio (a aba ainda faz ellipsis).
  String _shortTitle(String raw) {
    final t = raw.trim();
    if (t.isEmpty || !t.contains('/')) return t;
    final segments = t.split('/').where((s) => s.isNotEmpty).toList();
    return segments.isEmpty ? t : segments.last;
  }

  @override
  final String id;
  @override
  final String projectId;
  @override
  final String workingDirectory;

  final TerminalGateway _gateway;
  String _title;
  late final Terminal terminal;
  StreamSubscription<String>? _sub;

  @override
  String get title => _title;

  void rename(String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty || trimmed == _title) return;
    _title = trimmed;
    notifyListeners();
  }

  /// Insere [text] diretamente no PTY como se o usuário tivesse digitado/colado
  /// (ex.: caminho de arquivo arrastado até o terminal).
  void insertText(String text) => _gateway.write(utf8.encode(text));

  @override
  Future<void> dispose() async {
    await _sub?.cancel();
    await _gateway.kill();
    super.dispose();
  }
}
