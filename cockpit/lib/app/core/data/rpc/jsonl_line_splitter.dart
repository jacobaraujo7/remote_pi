import 'dart:async';
import 'dart:convert';

/// Quebra um stream de bytes em linhas JSONL conforme o protocolo do
/// `pi --mode rpc`: **LF (`\n`) é o único delimitador**; um `\r` final é
/// removido (aceita `\r\n`).
///
/// Por que não usar `LineSplitter`: o doc do RPC (rpc.md) avisa que leitores
/// genéricos quebram em separadores Unicode (`U+2028`/`U+2029`), que são
/// válidos *dentro* de strings JSON. Este splitter quebra só em `\n`.
///
/// O `utf8.decoder` (chunked) é aplicado antes, então sequências multibyte
/// partidas entre chunks são montadas corretamente.
class JsonlLineSplitter extends StreamTransformerBase<List<int>, String> {
  const JsonlLineSplitter();

  @override
  Stream<String> bind(Stream<List<int>> stream) async* {
    final pending = StringBuffer();
    await for (final text in stream.transform(utf8.decoder)) {
      var start = 0;
      var index = text.indexOf('\n');
      while (index != -1) {
        pending.write(text.substring(start, index));
        var line = pending.toString();
        pending.clear();
        if (line.endsWith('\r')) {
          line = line.substring(0, line.length - 1);
        }
        if (line.isNotEmpty) yield line;
        start = index + 1;
        index = text.indexOf('\n', start);
      }
      if (start < text.length) pending.write(text.substring(start));
    }
    var tail = pending.toString();
    if (tail.endsWith('\r')) tail = tail.substring(0, tail.length - 1);
    if (tail.isNotEmpty) yield tail;
  }
}
