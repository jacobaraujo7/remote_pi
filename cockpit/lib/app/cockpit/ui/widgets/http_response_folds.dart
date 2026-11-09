/// Projeção de uma resposta estruturada com blocos recolhidos. O conteúdo
/// original permanece intacto para copiar e salvar.
enum HttpResponseFoldSyntax { json, xml, html }

class HttpResponseFolds {
  const HttpResponseFolds({
    required this.text,
    required this.foldEnds,
    required this.lineNumbers,
    required this.visibleBySource,
  });

  final String text;
  final Map<int, int> foldEnds; // linha final exclusiva, base 0
  final List<int> lineNumbers; // números originais, base 1
  final Map<int, int> visibleBySource;

  static HttpResponseFolds build(
    String source,
    HttpResponseFoldSyntax? syntax,
    Set<int> foldedStarts,
  ) {
    final lines = source.split('\n');
    final ranges = switch (syntax) {
      HttpResponseFoldSyntax.json => _jsonRanges(source, lines),
      HttpResponseFoldSyntax.xml => _markupRanges(source, lines, html: false),
      HttpResponseFoldSyntax.html => _markupRanges(source, lines, html: true),
      null => <int, _FoldRange>{},
    };
    final visible = <String>[];
    final numbers = <int>[];
    final bySource = <int, int>{};
    for (var line = 0; line < lines.length; line++) {
      bySource[line] = visible.length;
      numbers.add(line + 1);
      final range = ranges[line];
      if (range != null && foldedStarts.contains(line)) {
        visible.add(range.preview);
        line = range.end;
      } else {
        visible.add(lines[line]);
      }
    }
    return HttpResponseFolds(
      text: visible.join('\n'),
      foldEnds: {
        for (final entry in ranges.entries) entry.key: entry.value.end + 1,
      },
      lineNumbers: numbers,
      visibleBySource: bySource,
    );
  }

  static Map<int, _FoldRange> _jsonRanges(String source, List<String> lines) {
    final ranges = <int, _FoldRange>{};
    final stack = <({int char, int line, int offset})>[];
    var line = 0;
    var inString = false;
    var escaped = false;
    for (var i = 0; i < source.length; i++) {
      final char = source.codeUnitAt(i);
      if (char == 0x0A) {
        line++;
        continue;
      }
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (char == 0x5C) {
          escaped = true;
        } else if (char == 0x22) {
          inString = false;
        }
        continue;
      }
      if (char == 0x22) {
        inString = true;
      } else if (char == 0x7B || char == 0x5B) {
        stack.add((char: char, line: line, offset: i));
      } else if (char == 0x7D || char == 0x5D) {
        if (stack.isEmpty) continue;
        final open = stack.removeLast();
        if ((open.char == 0x7B && char != 0x7D) ||
            (open.char == 0x5B && char != 0x5D) ||
            open.line >= line) {
          continue;
        }
        final openEnd = source.indexOf('\n', open.offset);
        final closeStart = source.lastIndexOf('\n', i - 1) + 1;
        if (openEnd < 0 ||
            source.substring(open.offset + 1, openEnd).trim().isNotEmpty ||
            source.substring(closeStart, i).trim().isNotEmpty) {
          continue;
        }
        _putRange(
          ranges,
          open.line,
          line,
          // Preserve JSON validity while collapsed. A bare ellipsis makes the
          // highlighter parse the rest of the document as malformed JSON.
          '${lines[open.line].trimRight()}${lines[line].trimLeft()}',
        );
      }
    }
    return ranges;
  }

  static Map<int, _FoldRange> _markupRanges(
    String source,
    List<String> lines, {
    required bool html,
  }) {
    final ranges = <int, _FoldRange>{};
    final stack = <({String name, int line, int endOffset})>[];
    final lowerSource = html ? source.toLowerCase() : source;
    var line = 0;
    var i = 0;
    while (i < source.length) {
      if (source.codeUnitAt(i) == 0x0A) {
        line++;
        i++;
        continue;
      }
      if (source.codeUnitAt(i) != 0x3C) {
        i++;
        continue;
      }
      final start = i;
      final startLine = line;
      if (source.startsWith('<!--', i)) {
        final end = source.indexOf('-->', i + 4);
        i = end < 0 ? source.length : end + 3;
      } else if (source.startsWith('<![CDATA[', i)) {
        final end = source.indexOf(']]>', i + 9);
        i = end < 0 ? source.length : end + 3;
      } else {
        final end = _tagEnd(source, i);
        if (end < 0) break;
        final inside = source.substring(i + 1, end).trim();
        i = end + 1;
        if (inside.startsWith('!') || inside.startsWith('?')) {
          line += _newlines(source, start, i);
          continue;
        }
        final closing = inside.startsWith('/');
        final nameMatch = RegExp(
          r'^/?\s*([A-Za-z][\w:.-]*)',
        ).firstMatch(inside);
        if (nameMatch == null) {
          line += _newlines(source, start, i);
          continue;
        }
        final name = html
            ? nameMatch.group(1)!.toLowerCase()
            : nameMatch.group(1)!;
        if (closing) {
          final match = stack.lastIndexWhere((item) => item.name == name);
          if (match >= 0) {
            final open = stack[match];
            stack.removeRange(match, stack.length);
            final endLine = startLine + _newlines(source, start, i);
            final openLineEnd = source.indexOf('\n', open.endOffset);
            final closeLineStart = source.lastIndexOf('\n', start - 1) + 1;
            final closeLineEnd = source.indexOf('\n', end);
            if (open.line < startLine &&
                openLineEnd >= 0 &&
                source
                    .substring(open.endOffset + 1, openLineEnd)
                    .trim()
                    .isEmpty &&
                source.substring(closeLineStart, start).trim().isEmpty &&
                source
                    .substring(
                      end + 1,
                      closeLineEnd < 0 ? source.length : closeLineEnd,
                    )
                    .trim()
                    .isEmpty) {
              _putRange(
                ranges,
                open.line,
                startLine,
                '${lines[open.line].trimRight()} … ${lines[startLine].trimLeft()}',
              );
            }
            line = endLine;
            continue;
          }
        } else if (!inside.endsWith('/') &&
            (!html || !_htmlVoidElements.contains(name))) {
          stack.add((name: name, line: startLine, endOffset: end));
          if (html && (name == 'script' || name == 'style')) {
            final close = lowerSource.indexOf('</$name', i);
            if (close >= 0) {
              line += _newlines(source, start, close);
              i = close;
              continue;
            }
          }
        }
      }
      line += _newlines(source, start, i);
    }
    return ranges;
  }

  static int _tagEnd(String source, int start) {
    var quote = 0;
    for (var i = start + 1; i < source.length; i++) {
      final char = source.codeUnitAt(i);
      if (quote != 0) {
        if (char == quote) quote = 0;
      } else if (char == 0x22 || char == 0x27) {
        quote = char;
      } else if (char == 0x3E) {
        return i;
      }
    }
    return -1;
  }

  static int _newlines(String source, int from, int to) {
    var count = 0;
    for (var i = from; i < to; i++) {
      if (source.codeUnitAt(i) == 0x0A) count++;
    }
    return count;
  }

  static void _putRange(
    Map<int, _FoldRange> ranges,
    int start,
    int end,
    String preview,
  ) {
    if (ranges[start] case final existing? when existing.end >= end) return;
    ranges[start] = _FoldRange(end, preview);
  }

  static const _htmlVoidElements = <String>{
    'area',
    'base',
    'br',
    'col',
    'embed',
    'hr',
    'img',
    'input',
    'link',
    'meta',
    'param',
    'source',
    'track',
    'wbr',
  };
}

class _FoldRange {
  const _FoldRange(this.end, this.preview);
  final int end;
  final String preview;
}
