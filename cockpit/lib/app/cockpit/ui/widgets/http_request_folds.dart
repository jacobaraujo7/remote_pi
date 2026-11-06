import 'package:cockpit/app/cockpit/domain/entities/http_document.dart';

/// Projeção visual de um arquivo HTTP com chamadas recolhidas.
/// O texto original nunca é alterado por um fold.
class HttpRequestFolds {
  const HttpRequestFolds({
    required this.text,
    required this.foldEnds,
    required this.lineNumbers,
    required this.visibleBySource,
  });

  final String text;
  final Map<int, int> foldEnds;
  final List<int> lineNumbers;
  final Map<int, int> visibleBySource;

  static HttpRequestFolds build(String source, Set<int> foldedStarts) {
    final lines = source.split('\n');
    final doc = HttpDocument.parse(source);
    final ends = <int, int>{};
    for (final request in doc.requests) {
      var end = request.endLine.clamp(0, lines.length);
      while (end > request.requestLine + 1 && lines[end - 1].trim().isEmpty) {
        end--;
      }
      if (end > request.requestLine + 1) ends[request.requestLine] = end;
    }

    final visible = <String>[];
    final numbers = <int>[];
    final bySource = <int, int>{};
    for (var line = 0; line < lines.length; line++) {
      bySource[line] = visible.length;
      numbers.add(line + 1);
      final end = ends[line];
      if (end != null && foldedStarts.contains(line)) {
        final urlContinuation = lines
            .sublist(line + 1, end)
            .map((s) => s.trim())
            .where((s) => s.startsWith('?') || s.startsWith('&'))
            .join(' ');
        visible.add(
          urlContinuation.isEmpty
              ? lines[line]
              : '${lines[line]}    $urlContinuation',
        );
        line = end - 1;
      } else {
        visible.add(lines[line]);
      }
    }
    return HttpRequestFolds(
      text: visible.join('\n'),
      foldEnds: ends,
      lineNumbers: numbers,
      visibleBySource: bySource,
    );
  }
}
