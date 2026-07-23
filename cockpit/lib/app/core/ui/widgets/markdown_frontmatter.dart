// Portado do PR jacobaraujo7 → Infinitix-LLC/gpt_markdown#139 (frontmatter),
// que o upstream não absorveu. Pré-processamento local: o `AgentMarkdown` faz
// o split e renderiza a tabela ANTES de entregar o corpo ao GptMarkdown de
// fábrica (pub.dev) — o fork git foi descomissionado (2026-07-19).
import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

/// The YAML frontmatter block found at the very top of a markdown document.
///
/// Frontmatter is a metadata block fenced by `---` lines at the start of a
/// document, widely used by static site generators and, more recently, by AI
/// agent definition files such as `agent.md` and `SKILL.md`:
///
/// ```markdown
/// ---
/// name: code-reviewer
/// description: Reviews diffs for bugs and style issues.
/// tags:
///   - review
///   - quality
/// ---
///
/// # Code Reviewer
/// ...
/// ```
///
/// [MarkdownFrontmatter] detects this block, removes it from the rendered body and —
/// when a `frontmatterBuilder` is supplied — hands the parsed result to that
/// builder so it can be displayed however you like.
///
/// The bundled parser understands the common subset of YAML used in
/// frontmatter: scalars (with `int`/`double`/`bool`/`null` coercion), quoted
/// strings, nested mappings, block and flow sequences, flow mappings, block
/// scalars (`|` and `>`) and `#` comments. It is intentionally dependency-free
/// and does not aim to be a complete YAML implementation.
class MarkdownFrontmatter {
  /// Creates a frontmatter holding the [raw] text and its parsed [fields].
  const MarkdownFrontmatter({required this.raw, required this.fields});

  /// The raw text found between the opening and closing `---` fences.
  final String raw;

  /// The parsed key/value pairs.
  ///
  /// Values may be a [String], [int], [double], [bool], `null`, a [List] or a
  /// nested [Map].
  final Map<String, dynamic> fields;

  /// Whether no fields were parsed.
  bool get isEmpty => fields.isEmpty;

  /// Whether at least one field was parsed.
  bool get isNotEmpty => fields.isNotEmpty;

  /// The parsed keys, in document order.
  Iterable<String> get keys => fields.keys;

  /// Returns the raw value for [key], or `null` when absent.
  dynamic operator [](String key) => fields[key];

  /// Whether [key] is present.
  bool containsKey(String key) => fields.containsKey(key);

  /// Returns [key] coerced to a [String], or `null` when absent.
  String? string(String key) {
    final value = fields[key];
    return value?.toString();
  }

  /// Returns [key] as a list of strings.
  ///
  /// A scalar value becomes a single-element list and a missing key returns an
  /// empty list, so callers never have to null-check.
  List<String> stringList(String key) {
    final value = fields[key];
    if (value == null) return const [];
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    return [value.toString()];
  }

  /// Parses the frontmatter at the start of [source].
  ///
  /// Returns `null` when [source] does not begin with a `---` frontmatter
  /// block. Use [split] when you also need the markdown body.
  static MarkdownFrontmatter? parse(String source) => split(source).frontmatter;

  /// Splits [source] into its leading frontmatter (if any) and markdown body.
  ///
  /// When [source] does not start with a frontmatter block — or starts with a
  /// `---` block that yields no fields (for example two adjacent horizontal
  /// rules) — the returned `frontmatter` is `null` and `body` is [source]
  /// unchanged.
  static ({MarkdownFrontmatter? frontmatter, String body}) split(
    String source,
  ) {
    var text = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    // Drop a leading byte order mark, if present.
    if (text.startsWith('﻿')) {
      text = text.substring(1);
    }
    // Allow blank lines / spaces before the opening fence.
    final lead = RegExp(r'^[ \t\n]*').firstMatch(text)?.group(0) ?? '';
    final candidate = text.substring(lead.length);
    if (!candidate.startsWith('---')) {
      return (frontmatter: null, body: source);
    }
    final lines = candidate.split('\n');
    // The opening line must be exactly '---' (trailing spaces allowed).
    if (lines.first.trimRight() != '---') {
      return (frontmatter: null, body: source);
    }
    // Find the closing fence ('---' or '...').
    int? closeIndex;
    for (var i = 1; i < lines.length; i++) {
      final trimmed = lines[i].trimRight();
      if (trimmed == '---' || trimmed == '...') {
        closeIndex = i;
        break;
      }
    }
    if (closeIndex == null) {
      // No closing fence — not frontmatter, leave the document untouched.
      return (frontmatter: null, body: source);
    }
    final raw = lines.sublist(1, closeIndex).join('\n');
    final fields = _parse(raw);
    // Only treat the block as frontmatter when it actually yields data. This
    // keeps things like `---\n\n---` (two adjacent horizontal rules) rendering
    // as markdown rather than being swallowed as an empty frontmatter block.
    if (fields.isEmpty) {
      return (frontmatter: null, body: source);
    }
    final body = lines.sublist(closeIndex + 1).join('\n');
    return (
      frontmatter: MarkdownFrontmatter(raw: raw, fields: fields),
      body: body,
    );
  }

  @override
  String toString() => 'MarkdownFrontmatter($fields)';

  // ---------------------------------------------------------------------------
  // Parsing internals
  // ---------------------------------------------------------------------------

  static Map<String, dynamic> _parse(String raw) {
    final lines = _toLines(raw);
    if (lines.isEmpty) return <String, dynamic>{};
    return _FrontmatterParser(lines).parse();
  }

  /// Splits [raw] into significant lines, dropping blank and comment lines and
  /// recording each line's indentation (tabs count as two spaces).
  static List<_FmLine> _toLines(String raw) {
    final result = <_FmLine>[];
    for (final original in raw.split('\n')) {
      final line = original.replaceAll('\t', '  ');
      final trimmedLeft = line.trimLeft();
      if (trimmedLeft.isEmpty) continue; // blank line
      if (trimmedLeft.startsWith('#')) continue; // comment line
      final indent = line.length - trimmedLeft.length;
      result.add(_FmLine(indent, trimmedLeft.trimRight()));
    }
    return result;
  }

  /// Splits a `key: value` line at the first top-level `:` that is followed by
  /// whitespace or end of line, honouring quotes and flow collections.
  ///
  /// Returns `[key, value]` (the value keeps its leading space) or `null` when
  /// the line is not a key/value pair.
  static List<String>? _splitKeyValue(String s) {
    var inSingle = false;
    var inDouble = false;
    var depth = 0;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (c == "'" && !inDouble) {
        inSingle = !inSingle;
      } else if (c == '"' && !inSingle) {
        inDouble = !inDouble;
      } else if (!inSingle && !inDouble) {
        if (c == '[' || c == '{') {
          depth++;
        } else if (c == ']' || c == '}') {
          if (depth > 0) depth--;
        } else if (c == ':' && depth == 0) {
          if (i + 1 >= s.length) {
            return [s.substring(0, i), ''];
          }
          final next = s[i + 1];
          if (next == ' ' || next == '\t') {
            return [s.substring(0, i), s.substring(i + 1)];
          }
        }
      }
    }
    return null;
  }

  static String _parseKey(String raw) {
    final key = raw.trim();
    if (key.length >= 2) {
      final first = key[0];
      final last = key[key.length - 1];
      if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
        return key.substring(1, key.length - 1);
      }
    }
    return key;
  }

  /// Converts a scalar value into a typed Dart value.
  static dynamic _parseScalar(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;

    // Flow collections.
    if (s.startsWith('[') && s.endsWith(']')) {
      return _parseFlowList(s.substring(1, s.length - 1));
    }
    if (s.startsWith('{') && s.endsWith('}')) {
      return _parseFlowMap(s.substring(1, s.length - 1));
    }

    // Quoted strings.
    if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
      return _unescapeDouble(s.substring(1, s.length - 1));
    }
    if (s.length >= 2 && s.startsWith("'") && s.endsWith("'")) {
      return s.substring(1, s.length - 1).replaceAll("''", "'");
    }

    // Strip a trailing inline comment (" #...").
    final commentIndex = _inlineCommentIndex(s);
    if (commentIndex != -1) {
      s = s.substring(0, commentIndex).trimRight();
    }
    if (s.isEmpty) return null;

    // Null and booleans.
    if (s == '~') return null;
    switch (s.toLowerCase()) {
      case 'null':
        return null;
      case 'true':
        return true;
      case 'false':
        return false;
    }

    // Numbers.
    final asInt = int.tryParse(s);
    if (asInt != null) return asInt;
    final asDouble = double.tryParse(s);
    if (asDouble != null && !s.contains(RegExp(r'[^0-9eE+.\-]'))) {
      return asDouble;
    }

    return s;
  }

  static List<dynamic> _parseFlowList(String inner) {
    return _splitFlow(inner).map<dynamic>(_parseScalar).toList();
  }

  static Map<String, dynamic> _parseFlowMap(String inner) {
    final map = <String, dynamic>{};
    for (final part in _splitFlow(inner)) {
      final p = part.trim();
      if (p.isEmpty) continue;
      final colon = _topLevelColon(p);
      if (colon == -1) {
        map[_parseKey(p)] = null;
        continue;
      }
      final key = _parseKey(p.substring(0, colon));
      final value = p.substring(colon + 1).trim();
      map[key] = value.isEmpty ? null : _parseScalar(value);
    }
    return map;
  }

  /// Splits a flow collection body on top-level commas, honouring nested
  /// brackets/braces and quotes.
  static List<String> _splitFlow(String inner) {
    final result = <String>[];
    final buffer = StringBuffer();
    var depth = 0;
    var inSingle = false;
    var inDouble = false;
    for (var i = 0; i < inner.length; i++) {
      final c = inner[i];
      if (c == "'" && !inDouble) {
        inSingle = !inSingle;
      } else if (c == '"' && !inSingle) {
        inDouble = !inDouble;
      } else if (!inSingle && !inDouble) {
        if (c == '[' || c == '{') {
          depth++;
        } else if (c == ']' || c == '}') {
          if (depth > 0) depth--;
        } else if (c == ',' && depth == 0) {
          result.add(buffer.toString());
          buffer.clear();
          continue;
        }
      }
      buffer.write(c);
    }
    if (buffer.toString().trim().isNotEmpty) {
      result.add(buffer.toString());
    }
    return result;
  }

  static int _topLevelColon(String s) {
    var inSingle = false;
    var inDouble = false;
    var depth = 0;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (c == "'" && !inDouble) {
        inSingle = !inSingle;
      } else if (c == '"' && !inSingle) {
        inDouble = !inDouble;
      } else if (!inSingle && !inDouble) {
        if (c == '[' || c == '{') {
          depth++;
        } else if (c == ']' || c == '}') {
          if (depth > 0) depth--;
        } else if (c == ':' && depth == 0) {
          return i;
        }
      }
    }
    return -1;
  }

  static int _inlineCommentIndex(String s) {
    var inSingle = false;
    var inDouble = false;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (c == "'" && !inDouble) {
        inSingle = !inSingle;
      } else if (c == '"' && !inSingle) {
        inDouble = !inDouble;
      } else if (c == '#' && !inSingle && !inDouble) {
        if (i == 0 || s[i - 1] == ' ' || s[i - 1] == '\t') {
          return i;
        }
      }
    }
    return -1;
  }

  static String _unescapeDouble(String s) {
    if (!s.contains(r'\')) return s;
    final buffer = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (c == r'\' && i + 1 < s.length) {
        final n = s[i + 1];
        switch (n) {
          case 'n':
            buffer.write('\n');
            break;
          case 't':
            buffer.write('\t');
            break;
          case 'r':
            buffer.write('\r');
            break;
          case '"':
            buffer.write('"');
            break;
          case r'\':
            buffer.write(r'\');
            break;
          case '0':
            buffer.write('\x00');
            break;
          default:
            buffer.write(n);
        }
        i++;
      } else {
        buffer.write(c);
      }
    }
    return buffer.toString();
  }
}

/// The default renderer for [MarkdownFrontmatter] — a bordered two-column
/// table of `key | value` rows, similar to how editors such as VS Code display
/// the frontmatter of `agent.md` / `SKILL.md` files.
///
/// [MarkdownFrontmatter] uses this automatically whenever a document has frontmatter
/// and no custom `frontmatterBuilder` is supplied. You can also use it directly
/// from a `frontmatterBuilder`:
///
/// ```dart
/// GptMarkdown(
///   agentMarkdown,
///   frontmatterBuilder: (context, frontmatter) =>
///       MarkdownFrontmatterTable(frontmatter: frontmatter),
/// )
/// ```
class MarkdownFrontmatterTable extends StatelessWidget {
  const MarkdownFrontmatterTable({
    super.key,
    required this.frontmatter,
    this.style,
  });

  /// The parsed frontmatter to display.
  final MarkdownFrontmatter frontmatter;

  /// Base text style for the table cells. Keys are rendered bold.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final entries = frontmatter.fields.entries.toList();
    if (entries.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final gptTheme = GptMarkdownTheme.of(context);
    final baseStyle = style ?? DefaultTextStyle.of(context).style;
    final keyStyle = baseStyle.copyWith(fontWeight: FontWeight.bold);
    final borderColor = gptTheme.hrLineColor;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Table(
        border: TableBorder.all(color: borderColor, width: 1),
        columnWidths: const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth()},
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          for (final entry in entries)
            TableRow(
              children: [
                _cell(
                  entry.key,
                  keyStyle,
                  background: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.4),
                ),
                _cell(_stringify(entry.value), baseStyle),
              ],
            ),
        ],
      ),
    );
  }

  Widget _cell(String text, TextStyle textStyle, {Color? background}) {
    final content = Container(
      color: background,
      alignment: background != null ? Alignment.centerLeft : null,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Text(text, style: textStyle),
    );
    // Colored (key) cells must stretch to the full row height so the
    // background fills the whole cell — not just the text line when the value
    // in the same row wraps onto several lines.
    if (background != null) {
      return TableCell(
        verticalAlignment: TableCellVerticalAlignment.fill,
        child: content,
      );
    }
    return content;
  }

  static String _stringify(dynamic value) {
    if (value == null) return '';
    if (value is List) return value.map(_stringify).join(', ');
    if (value is Map) {
      return value.entries
          .map((e) => '${e.key}: ${_stringify(e.value)}')
          .join(', ');
    }
    return value.toString();
  }
}

/// A significant frontmatter line: its indentation and trimmed content.
class _FmLine {
  const _FmLine(this.indent, this.content);

  final int indent;
  final String content;

  /// Whether this line begins a block-sequence entry (`- ...` or a bare `-`).
  bool get isSeqItem => content == '-' || content.startsWith('- ');
}

/// A small recursive descent parser for the YAML subset used in frontmatter.
class _FrontmatterParser {
  _FrontmatterParser(this.lines);

  final List<_FmLine> lines;
  int _i = 0;

  Map<String, dynamic> parse() {
    if (lines.isEmpty) return <String, dynamic>{};
    // Frontmatter roots are always mappings.
    return _parseMap(lines.first.indent);
  }

  Map<String, dynamic> _parseMap(int indent) {
    final map = <String, dynamic>{};
    while (_i < lines.length) {
      final line = lines[_i];
      if (line.indent < indent) break;
      if (line.indent > indent) {
        // Orphan deeper line without a parent key — skip to stay safe.
        _i++;
        continue;
      }
      if (line.isSeqItem) break; // a sequence is not part of this mapping
      final kv = MarkdownFrontmatter._splitKeyValue(line.content);
      if (kv == null) {
        _i++;
        continue;
      }
      final key = MarkdownFrontmatter._parseKey(kv[0]);
      final valueText = kv[1].trim();
      _i++;
      if (valueText.isEmpty) {
        map[key] = _parseChild(indent);
      } else if (_isBlockScalarHeader(valueText)) {
        map[key] = _parseBlockScalar(indent, fold: valueText[0] == '>');
      } else {
        map[key] = MarkdownFrontmatter._parseScalar(valueText);
      }
    }
    return map;
  }

  List<dynamic> _parseSeq(int indent) {
    final list = <dynamic>[];
    while (_i < lines.length) {
      final line = lines[_i];
      if (line.indent < indent) break;
      if (line.indent > indent) {
        _i++;
        continue;
      }
      if (!line.isSeqItem) break;
      final rest = line.content == '-' ? '' : line.content.substring(2).trim();
      if (rest.isEmpty) {
        // The item's value lives on the following, more-indented lines.
        _i++;
        list.add(_parseChild(indent));
      } else if (MarkdownFrontmatter._splitKeyValue(rest) != null) {
        // Compact mapping inside a sequence: "- key: value". Rewrite the dash
        // line as a normal mapping entry past the dash, then let _parseMap
        // absorb it together with any aligned continuation lines.
        lines[_i] = _FmLine(indent + 2, rest);
        list.add(_parseMap(indent + 2));
      } else {
        _i++;
        list.add(MarkdownFrontmatter._parseScalar(rest));
      }
    }
    return list;
  }

  /// Parses the block value (mapping or sequence) belonging to a key whose own
  /// line is at [keyIndent]. A block sequence may share the key's indentation.
  dynamic _parseChild(int keyIndent) {
    if (_i >= lines.length) return null;
    final next = lines[_i];
    if (next.isSeqItem && next.indent >= keyIndent) {
      return _parseSeq(next.indent);
    }
    if (next.indent > keyIndent) {
      if (next.isSeqItem) return _parseSeq(next.indent);
      return _parseMap(next.indent);
    }
    return null;
  }

  bool _isBlockScalarHeader(String value) {
    if (value.isEmpty) return false;
    final indicator = value[0];
    if (indicator != '|' && indicator != '>') return false;
    final rest = value.substring(1);
    // Allow chomping/keep indicators like `|-`, `>+`.
    return rest.isEmpty || rest == '-' || rest == '+';
  }

  String _parseBlockScalar(int parentIndent, {required bool fold}) {
    final parts = <String>[];
    int? base;
    while (_i < lines.length) {
      final line = lines[_i];
      if (line.indent <= parentIndent) break;
      base ??= line.indent;
      final dedent = line.indent - base;
      parts.add((dedent > 0 ? ' ' * dedent : '') + line.content);
      _i++;
    }
    return fold ? parts.join(' ') : parts.join('\n');
  }
}
