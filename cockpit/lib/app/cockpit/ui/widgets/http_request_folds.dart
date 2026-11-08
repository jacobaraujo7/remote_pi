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

  /// Mantém os folds ligados às linhas correspondentes após uma edição.
  /// Edições comuns alteram apenas um trecho; o prefixo e o sufixo intactos
  /// dão uma âncora estável mesmo quando linhas são inseridas antes do fold.
  static Set<int> remapStarts(
    String previous,
    String current,
    Set<int> foldedStarts,
  ) {
    if (foldedStarts.isEmpty || previous == current) return {...foldedStarts};
    final oldLines = previous.split('\n');
    final newLines = current.split('\n');
    var prefix = 0;
    while (prefix < oldLines.length &&
        prefix < newLines.length &&
        oldLines[prefix] == newLines[prefix]) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < oldLines.length - prefix &&
        suffix < newLines.length - prefix &&
        oldLines[oldLines.length - suffix - 1] ==
            newLines[newLines.length - suffix - 1]) {
      suffix++;
    }
    final oldEnd = oldLines.length - suffix;
    final newEnd = newLines.length - suffix;
    final delta = newLines.length - oldLines.length;
    final available = build(current, const {}).foldEnds.keys.toSet();
    return {
      for (final start in foldedStarts)
        if (start < prefix && available.contains(start))
          start
        else if (start >= oldEnd && available.contains(start + delta))
          start + delta
        else if (start >= prefix &&
            start < oldEnd &&
            start - prefix < newEnd - prefix &&
            available.contains(start))
          start,
    };
  }

  static HttpRequestFolds build(String source, Set<int> foldedStarts) {
    final lines = source.split('\n');
    final doc = HttpDocument.parse(source);
    final ends = <int, int>{};
    final scriptStarts = <int>{};
    for (final request in doc.requests) {
      var end = request.endLine.clamp(0, lines.length);
      while (end > request.requestLine + 1 && lines[end - 1].trim().isEmpty) {
        end--;
      }
      if (end > request.requestLine + 1) ends[request.requestLine] = end;
    }
    final scriptOpen = RegExp(r'^[ \t]*[<>][ \t]*\{%');
    for (var line = 0; line < lines.length; line++) {
      final start = scriptOpen.firstMatch(lines[line]);
      if (start == null) continue;
      if (lines[line].indexOf('%}', start.end) >= 0) continue;
      for (var end = line + 1; end < lines.length; end++) {
        if (!lines[end].contains('%}')) continue;
        ends[line] = end + 1;
        scriptStarts.add(line);
        line = end;
        break;
      }
    }

    final visible = <String>[];
    final numbers = <int>[];
    final bySource = <int, int>{};
    for (var line = 0; line < lines.length; line++) {
      bySource[line] = visible.length;
      numbers.add(line + 1);
      final end = ends[line];
      if (end != null && foldedStarts.contains(line)) {
        if (scriptStarts.contains(line)) {
          final prefix = lines[line].substring(
            0,
            scriptOpen.firstMatch(lines[line])!.end,
          );
          visible.add('$prefix ... %}');
          line = end - 1;
          continue;
        }
        final urlContinuation = lines
            .sublist(line + 1, end)
            .map((s) => s.trim())
            .where((s) => s.startsWith('?') || s.startsWith('&'))
            .join();
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
