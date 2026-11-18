import 'package:cockpit/app/cockpit/domain/entities/http_document.dart';
import 'package:cockpit/app/cockpit/ui/widgets/http_pair_editing.dart';
import 'package:flutter/services.dart';

enum _BodyType { json, xml, html }

/// Autoclose apenas no body da requisição corrente, segundo seu Content-Type.
class HttpBodyEditingFormatter extends TextInputFormatter {
  const HttpBodyEditingFormatter() : memory = null;

  HttpBodyEditingFormatter.live() : memory = HttpAutocloseMemory();

  final HttpAutocloseMemory? memory;

  static const _jsonPairs = {'{': '}', '[': ']', '"': '"'};
  static const _attributePairs = {'"': '"', "'": "'"};
  static final _method = RegExp(
    r'^[ \t]*(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS|TRACE)\s+\S',
    caseSensitive: false,
  );
  static final _script = RegExp(r'^[ \t]*[<>][ \t]*\{%');
  static final _contentType = RegExp(
    r'^[ \t]*content-type[ \t]*:[ \t]*([^;\s]+)',
    caseSensitive: false,
  );
  static final _tagName = RegExp(r'^<([A-Za-z_][A-Za-z0-9_:.-]*)(?:\s|$)');
  static const _voidTags = {
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
  static const _rawTags = {'script', 'style', 'textarea', 'title'};

  static ({int start, _BodyType type})? _bodyAt(String source, int caret) {
    if (caret < 0 || caret > source.length) return null;
    var hasRequest = false;
    var inScript = false;
    var imported = false;
    String? contentType;
    int? bodyStart;
    var offset = 0;
    for (final line in source.split('\n')) {
      if (offset > caret) break;
      final lineEnd = offset + line.length;
      if (inScript) {
        final close = line.indexOf('%}');
        if (close >= 0 && offset + close + 2 <= caret) inScript = false;
      } else if (_script.hasMatch(line)) {
        final open = _script.firstMatch(line)!;
        final close = line.indexOf('%}', open.end);
        inScript = close < 0 || offset + close + 2 > caret;
        // O próprio delimitador também não faz parte do body.
        if (caret <= lineEnd) return null;
      } else if (RegExp(r'^[ \t]*###+').hasMatch(line)) {
        hasRequest = false;
        contentType = null;
        bodyStart = null;
        imported = false;
      } else if (bodyStart == null && _method.hasMatch(line)) {
        hasRequest = true;
        contentType = null;
        imported = false;
      } else if (hasRequest && bodyStart == null) {
        final header = _contentType.firstMatch(line);
        if (header != null) contentType = header.group(1)!.toLowerCase();
        if (RegExp(r'^[ \t]*<[ \t]+').hasMatch(line)) imported = true;
        if (line.trim().isEmpty && lineEnd < source.length) {
          bodyStart = lineEnd + 1;
        }
      } else if (bodyStart != null &&
          HttpDocument.scriptFileAtLine(line) != null) {
        if (caret <= lineEnd) return null;
      }
      offset = lineEnd + 1;
    }
    if (!hasRequest ||
        imported ||
        inScript ||
        bodyStart == null ||
        caret < bodyStart) {
      return null;
    }
    final type = switch (contentType) {
      'application/json' || 'text/json' => _BodyType.json,
      'application/xml' || 'text/xml' => _BodyType.xml,
      'text/html' => _BodyType.html,
      final String mime when mime.endsWith('+json') => _BodyType.json,
      final String mime when mime.endsWith('+xml') => _BodyType.xml,
      _ => null,
    };
    return type == null ? null : (start: bodyStart, type: type);
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final retained = memory?.retain(oldValue, newValue);
    if (retained != null) return retained;
    final plain = newValue;
    oldValue = HttpPairEditing.beforeCommittedQuote(oldValue, newValue);
    if (!oldValue.selection.isValid ||
        !newValue.selection.isValid ||
        !newValue.selection.isCollapsed ||
        !newValue.composing.isCollapsed) {
      return newValue;
    }
    final offset = oldValue.selection.start;
    final body = _bodyAt(oldValue.text, offset);
    if (body == null) return newValue;
    final prefix = oldValue.text.substring(body.start, offset);
    final selectionEnd = _bodyAt(oldValue.text, oldValue.selection.end);
    final sameBody =
        selectionEnd == body &&
        !oldValue.selection
            .textInside(oldValue.text)
            .contains(RegExp(r'^[ \t]*[<>][ \t]*\{%', multiLine: true));
    if (body.type == _BodyType.json) {
      final context = _jsonContext(prefix);
      final paired = HttpPairEditing.pairs(
        oldValue,
        newValue,
        pairs: _jsonPairs,
        context: context,
        allowSelection: sameBody,
      );
      if (paired != null) {
        memory?.remember(plain, paired);
        return paired;
      }
      if (HttpPairEditing.isInsertion(oldValue, newValue) &&
          oldValue.selection.isCollapsed &&
          newValue.text[offset] == '\n' &&
          context.quote == null) {
        final before = prefix.substring(prefix.lastIndexOf('\n') + 1);
        final last = before.trimRight();
        final closing = last.isEmpty ? null : _jsonPairs[last[last.length - 1]];
        return HttpPairEditing.indent(
          newValue,
          baseIndent: RegExp(r'^[ \t]*').firstMatch(before)!.group(0)!,
          increase: closing == '}' || closing == ']',
          splitClosing:
              closing != null &&
              oldValue.text
                  .substring(offset)
                  .split('\n')
                  .first
                  .trimLeft()
                  .startsWith(closing),
        );
      }
      return newValue;
    }

    final markup = _markupContext(prefix, html: body.type == _BodyType.html);
    final paired = HttpPairEditing.pairs(
      oldValue,
      newValue,
      pairs: _attributePairs,
      context: (
        quote: markup.quote,
        comment: markup.literal || markup.tagStart == null,
        escaped: false,
      ),
      allowSelection: sameBody,
    );
    if (paired != null) {
      memory?.remember(plain, paired);
      return paired;
    }
    if (!oldValue.selection.isCollapsed ||
        !HttpPairEditing.isInsertion(oldValue, newValue) ||
        markup.literal) {
      return newValue;
    }
    final inserted = newValue.text[offset];
    if (inserted == '>' && markup.tagStart != null && markup.quote == null) {
      final tag = prefix.substring(markup.tagStart!);
      var value = newValue;
      final caret = newValue.selection.start;
      if (oldValue.text.substring(offset).startsWith('>')) {
        value = value.copyWith(
          text: value.text.replaceRange(caret, caret + 1, ''),
        );
      }
      final name = _openingName(tag, html: body.type == _BodyType.html);
      if (name == null ||
          _alreadyClosed(
            value.text,
            body.start,
            caret,
            name,
            html: body.type == _BodyType.html,
          )) {
        return value;
      }
      return value.copyWith(
        text: value.text.replaceRange(caret, caret, '</$name>'),
      );
    }
    if (inserted == '\n' && markup.quote == null) {
      final before = prefix.substring(prefix.lastIndexOf('\n') + 1);
      final opening = RegExp(r'<[^<>]+>\s*$').firstMatch(before);
      final tag = opening?.group(0)?.trimRight();
      final name = tag == null
          ? null
          : _openingName(
              tag.substring(0, tag.length - 1),
              html: body.type == _BodyType.html,
            );
      return HttpPairEditing.indent(
        newValue,
        baseIndent: RegExp(r'^[ \t]*').firstMatch(before)!.group(0)!,
        increase: name != null,
        splitClosing:
            name != null &&
            _hasClosing(
              oldValue.text.substring(offset).split('\n').first,
              name,
              html: body.type == _BodyType.html,
            ),
      );
    }
    return newValue;
  }

  static HttpPairContext _jsonContext(String code) {
    String? quote;
    var escaped = false;
    for (var i = 0; i < code.length; i++) {
      if (quote == null) {
        if (code[i] == '"') quote = '"';
      } else if (escaped) {
        escaped = false;
      } else if (code[i] == '\\') {
        escaped = true;
      } else if (code[i] == '"') {
        quote = null;
      }
    }
    return (quote: quote, comment: false, escaped: escaped);
  }

  static String? _openingName(String tag, {required bool html}) {
    if (tag.trimRight().endsWith('/')) return null;
    final name = _tagName.firstMatch(tag)?.group(1);
    if (name == null || html && _voidTags.contains(name.toLowerCase())) {
      return null;
    }
    return name;
  }

  static bool _hasClosing(String suffix, String name, {required bool html}) =>
      RegExp(
        '^\\s*</${RegExp.escape(name)}\\s*>',
        caseSensitive: !html,
      ).hasMatch(suffix);

  static bool _alreadyClosed(
    String source,
    int bodyStart,
    int caret,
    String name, {
    required bool html,
  }) {
    final suffix = source.substring(caret);
    if (!_hasClosing(suffix, name, html: html)) return false;
    final boundary = RegExp(
      r'^[ \t]*(?:###+|[<>][ \t]*\{%)',
      multiLine: true,
    ).firstMatch(suffix);
    final body = source.substring(
      bodyStart,
      caret + (boundary?.start ?? suffix.length),
    );
    // O fechamento do ancestral não deve ser reutilizado para uma tag filha
    // com o mesmo nome.
    return _markupContext(body, html: html, countName: name).balance <= 0;
  }

  static ({int? tagStart, String? quote, bool literal, int balance})
  _markupContext(String prefix, {required bool html, String? countName}) {
    int? tagStart;
    String? quote;
    String? rawTag;
    var balance = 0;
    bool matches(String? name) =>
        name != null &&
        countName != null &&
        (html
            ? name.toLowerCase() == countName.toLowerCase()
            : name == countName);
    for (var i = 0; i < prefix.length; i++) {
      if (rawTag != null) {
        final close = RegExp(
          '</${RegExp.escape(rawTag)}(?=[\\s>])',
          caseSensitive: false,
        ).firstMatch(prefix.substring(i));
        if (close == null) {
          return (tagStart: null, quote: null, literal: true, balance: balance);
        }
        i += close.start;
        rawTag = null;
      }
      final char = prefix[i];
      if (tagStart != null) {
        if (quote != null) {
          if (char == quote) quote = null;
        } else if (char == '"' || char == "'") {
          quote = char;
        } else if (char == '>') {
          final name = _openingName(prefix.substring(tagStart, i), html: html);
          if (matches(name)) balance++;
          final closing = RegExp(
            r'^</([A-Za-z_][A-Za-z0-9_:.-]*)\s*$',
          ).firstMatch(prefix.substring(tagStart, i));
          if (matches(closing?.group(1))) balance--;
          if (html && name != null && _rawTags.contains(name.toLowerCase())) {
            rawTag = name;
          }
          tagStart = null;
        }
      } else if (char == '<') {
        String? close;
        if (prefix.startsWith('<!--', i)) close = '-->';
        if (prefix.startsWith('<![CDATA[', i)) close = ']]>';
        if (prefix.startsWith('<?', i)) close = '?>';
        if (close != null) {
          final end = prefix.indexOf(close, i + 2);
          if (end < 0) {
            return (
              tagStart: null,
              quote: null,
              literal: true,
              balance: balance,
            );
          }
          i = end + close.length - 1;
        } else {
          tagStart = i;
        }
      }
    }
    return (
      tagStart: tagStart,
      quote: quote,
      literal: rawTag != null,
      balance: balance,
    );
  }
}
