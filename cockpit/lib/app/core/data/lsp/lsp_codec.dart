import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/// Framing do LSP sobre stdio: cada mensagem é
/// `Content-Length: <N>\r\n\r\n<N bytes de JSON UTF-8>`. **Diferente** do JSONL
/// do `pi` (uma linha = uma mensagem) — por isso não reusa o `JsonlLineSplitter`.
///
/// Este transformer consome os bytes crus do `stdout` do servidor e emite cada
/// mensagem JSON já decodificada como `Map<String, dynamic>`. Acumula num buffer
/// porque um chunk do stdout pode trazer meia mensagem (ou várias).
///
/// Para **escrever**, use [encodeLspMessage].
class LspMessageDecoder
    extends StreamTransformerBase<List<int>, Map<String, dynamic>> {
  const LspMessageDecoder();

  @override
  Stream<Map<String, dynamic>> bind(Stream<List<int>> stream) {
    final buffer = BytesBuilder(copy: false);
    // Conteúdo acumulado como bytes; parseamos cabeçalhos via ASCII e o corpo
    // via UTF-8 (o JSON pode ter multibyte, então contamos bytes, não chars).
    List<int> pending = const <int>[];

    return stream.transform(
      StreamTransformer<List<int>, Map<String, dynamic>>.fromHandlers(
        handleData: (chunk, sink) {
          buffer.add(chunk);
          pending = buffer.takeBytes();
          // Drena todas as mensagens completas presentes no buffer.
          while (true) {
            final message = _tryParseOne(pending);
            if (message == null) break;
            pending = message.rest;
            if (message.json != null) sink.add(message.json!);
          }
          // Devolve o resto (incompleto) ao buffer pro próximo chunk.
          buffer.add(pending);
          pending = const <int>[];
        },
      ),
    );
  }
}

/// Resultado de uma tentativa de parse: a mensagem (ou `null` se ainda
/// incompleta/inválida) e os bytes restantes a reprocessar.
class _ParsedMessage {
  const _ParsedMessage(this.json, this.rest);
  final Map<String, dynamic>? json;
  final List<int> rest;
}

const int _cr = 13; // \r
const int _lf = 10; // \n

/// Tenta extrair UMA mensagem de [data]. Retorna `null` se ainda não há um
/// cabeçalho + corpo completos (precisa de mais bytes).
_ParsedMessage? _tryParseOne(List<int> data) {
  // Acha o fim do bloco de cabeçalhos: \r\n\r\n.
  final headerEnd = _indexOfHeaderTerminator(data);
  if (headerEnd < 0) return null;

  final headerBytes = data.sublist(0, headerEnd);
  final headers = ascii.decode(headerBytes, allowInvalid: true);
  final contentLength = _contentLengthOf(headers);
  final bodyStart = headerEnd + 4; // pula \r\n\r\n

  if (contentLength == null) {
    // Cabeçalho sem Content-Length válido: descarta o bloco e segue (defensivo).
    return _ParsedMessage(null, data.sublist(bodyStart));
  }
  if (data.length - bodyStart < contentLength) return null; // corpo incompleto

  final bodyBytes = data.sublist(bodyStart, bodyStart + contentLength);
  final rest = data.sublist(bodyStart + contentLength);
  try {
    final decoded = jsonDecode(utf8.decode(bodyBytes));
    if (decoded is Map<String, dynamic>) return _ParsedMessage(decoded, rest);
    return _ParsedMessage(null, rest);
  } catch (_) {
    return _ParsedMessage(null, rest);
  }
}

/// Índice do início de `\r\n\r\n` em [data], ou -1.
int _indexOfHeaderTerminator(List<int> data) {
  for (var i = 0; i + 3 < data.length; i++) {
    if (data[i] == _cr &&
        data[i + 1] == _lf &&
        data[i + 2] == _cr &&
        data[i + 3] == _lf) {
      return i;
    }
  }
  return -1;
}

/// Lê o valor de `Content-Length` do bloco de cabeçalhos (case-insensitive).
int? _contentLengthOf(String headers) {
  for (final line in headers.split('\r\n')) {
    final idx = line.indexOf(':');
    if (idx < 0) continue;
    final name = line.substring(0, idx).trim().toLowerCase();
    if (name == 'content-length') {
      return int.tryParse(line.substring(idx + 1).trim());
    }
  }
  return null;
}

/// Serializa uma mensagem JSON-RPC no framing do LSP (bytes prontos pro stdin).
List<int> encodeLspMessage(Map<String, dynamic> message) {
  final body = utf8.encode(jsonEncode(message));
  final header = ascii.encode('Content-Length: ${body.length}\r\n\r\n');
  return <int>[...header, ...body];
}
