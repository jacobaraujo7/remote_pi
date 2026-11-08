import 'package:flutter/services.dart';

enum HttpScriptPhase { pre, post }

class HttpScriptSuggestion {
  const HttpScriptSuggestion(this.name, this.detail, {this.method = false});

  final String name;
  final String detail;
  final bool method;
}

class HttpScriptSlot {
  const HttpScriptSlot({
    required this.start,
    required this.end,
    required this.prefix,
    required this.receiver,
    required this.phase,
  });

  final int start;
  final int end;
  final String prefix;
  final String? receiver;
  final HttpScriptPhase phase;

  bool get autoShow => prefix.isNotEmpty || receiver != null;
}

/// Completa apenas a API implementada pelo executor de scripts HTTP, além dos
/// objetos JavaScript padrão mais usados. Fora de `< {%` / `> {%` não interfere
/// no autocomplete de `{{variáveis}}` do arquivo.
class HttpScriptCompletion {
  static final _open = RegExp(r'^[ \t]*([<>])[ \t]*\{%', multiLine: true);
  static final _chain = RegExp(
    r'([A-Za-z_$][A-Za-z0-9_$]*(?:\.[A-Za-z_$][A-Za-z0-9_$]*)*\.?)$',
  );
  static final _identifier = RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$');

  static ({int codeStart, HttpScriptPhase phase})? _blockAt(
    String source,
    int caret,
  ) {
    if (caret < 0 || caret > source.length) return null;
    for (final marker in _open.allMatches(source)) {
      if (marker.start >= caret) break;
      final close = source.indexOf('%}', marker.end);
      if (close < 0 || caret <= close) {
        return (
          codeStart: marker.end,
          phase: marker.group(1) == '<'
              ? HttpScriptPhase.pre
              : HttpScriptPhase.post,
        );
      }
    }
    return null;
  }

  static bool insideBlock(String source, int caret) =>
      _blockAt(source, caret) != null;

  static HttpScriptSlot? slotAt(String source, int caret) {
    final block = _blockAt(source, caret);
    if (block == null || caret < block.codeStart) return null;
    if (_inStringOrComment(source, block.codeStart, caret)) return null;

    final code = source.substring(block.codeStart, caret);
    final match = _chain.firstMatch(code);
    final chain = match?.group(1) ?? '';
    final dot = chain.lastIndexOf('.');
    final receiver = dot < 0 ? null : chain.substring(0, dot);
    final prefix = dot < 0 ? chain : chain.substring(dot + 1);
    final start = caret - prefix.length;
    var end = caret;
    while (end < source.length &&
        RegExp(r'[A-Za-z0-9_$]').hasMatch(source[end])) {
      end++;
    }
    return HttpScriptSlot(
      start: start,
      end: end,
      prefix: prefix,
      receiver: receiver,
      phase: block.phase,
    );
  }

  static List<HttpScriptSuggestion> options(
    HttpScriptSlot slot, {
    Object? responseBody,
  }) {
    final candidates = switch (slot.receiver) {
      null => [
        const HttpScriptSuggestion(
          'request',
          'Request and environment variables',
        ),
        const HttpScriptSuggestion(
          'client',
          'Tests, logs and global variables',
        ),
        if (slot.phase == HttpScriptPhase.post)
          const HttpScriptSuggestion('response', 'HTTP response'),
        const HttpScriptSuggestion('console', 'Console output'),
        const HttpScriptSuggestion('JSON', 'JavaScript JSON helpers'),
        const HttpScriptSuggestion('Math', 'JavaScript math helpers'),
        const HttpScriptSuggestion('Object', 'JavaScript object helpers'),
        const HttpScriptSuggestion('Array', 'JavaScript array helpers'),
        const HttpScriptSuggestion('Date', 'JavaScript date helpers'),
        const HttpScriptSuggestion('String', 'Convert to string', method: true),
        const HttpScriptSuggestion('Number', 'Convert to number', method: true),
        const HttpScriptSuggestion(
          'Boolean',
          'Convert to boolean',
          method: true,
        ),
        const HttpScriptSuggestion(
          'parseInt',
          'Parse an integer',
          method: true,
        ),
        const HttpScriptSuggestion(
          'parseFloat',
          'Parse a decimal',
          method: true,
        ),
        const HttpScriptSuggestion(
          'encodeURIComponent',
          'Encode a URL value',
          method: true,
        ),
        const HttpScriptSuggestion(
          'decodeURIComponent',
          'Decode a URL value',
          method: true,
        ),
      ],
      'request' => [
        const HttpScriptSuggestion('variables', 'Variables for this request'),
        const HttpScriptSuggestion('environment', 'Selected HTTP environment'),
      ],
      'request.variables' => [
        const HttpScriptSuggestion('set', 'set(name, value)', method: true),
        const HttpScriptSuggestion('get', 'get(name)', method: true),
      ],
      'request.environment' => [
        const HttpScriptSuggestion('get', 'get(name)', method: true),
      ],
      'client' => [
        const HttpScriptSuggestion(
          'global',
          'Shared variables for this app session',
        ),
        const HttpScriptSuggestion(
          'test',
          'test(name, callback)',
          method: true,
        ),
        const HttpScriptSuggestion(
          'assert',
          'assert(condition, message)',
          method: true,
        ),
        const HttpScriptSuggestion('log', 'log(...values)', method: true),
      ],
      'client.global' => [
        const HttpScriptSuggestion('set', 'set(name, value)', method: true),
        const HttpScriptSuggestion('get', 'get(name)', method: true),
      ],
      'response' when slot.phase == HttpScriptPhase.post => [
        const HttpScriptSuggestion('body', 'JSON value or response text'),
        const HttpScriptSuggestion('status', 'HTTP status code'),
        const HttpScriptSuggestion('headers', 'Response headers'),
      ],
      'response.headers' when slot.phase == HttpScriptPhase.post => [
        const HttpScriptSuggestion(
          'valueOf',
          'valueOf(name) · case-insensitive',
          method: true,
        ),
      ],
      'console' => [
        const HttpScriptSuggestion('log', 'log(...values)', method: true),
      ],
      'JSON' => [
        const HttpScriptSuggestion('parse', 'parse(text)', method: true),
        const HttpScriptSuggestion(
          'stringify',
          'stringify(value)',
          method: true,
        ),
      ],
      'Math' => [
        for (final name in [
          'abs',
          'ceil',
          'floor',
          'max',
          'min',
          'random',
          'round',
        ])
          HttpScriptSuggestion(name, 'Math.$name()', method: true),
      ],
      'Object' => [
        for (final name in [
          'assign',
          'entries',
          'fromEntries',
          'keys',
          'values',
        ])
          HttpScriptSuggestion(name, 'Object.$name()', method: true),
      ],
      'Array' => [
        const HttpScriptSuggestion('from', 'from(iterable)', method: true),
        const HttpScriptSuggestion('isArray', 'isArray(value)', method: true),
      ],
      'Date' => [
        const HttpScriptSuggestion('now', 'now() · milliseconds', method: true),
        const HttpScriptSuggestion('parse', 'parse(text)', method: true),
      ],
      _ => _bodyFields(slot.receiver, responseBody),
    };
    final query = slot.prefix.toLowerCase();
    return candidates
        .where((item) => item.name.toLowerCase().startsWith(query))
        .toList(growable: false);
  }

  static List<HttpScriptSuggestion> _bodyFields(
    String? receiver,
    Object? body,
  ) {
    if (receiver == null ||
        (receiver != 'response.body' &&
            !receiver.startsWith('response.body.'))) {
      return const [];
    }
    final parts = receiver.split('.').skip(2);
    Object? current = body;
    for (final part in parts) {
      if (current is! Map || !current.containsKey(part)) return const [];
      current = current[part];
    }
    if (current is Map) {
      return [
        for (final key in current.keys)
          if (key is String && _identifier.hasMatch(key))
            HttpScriptSuggestion(key, _typeOf(current[key])),
      ];
    }
    if (current is List || current is String) {
      return const [HttpScriptSuggestion('length', 'Number of items')];
    }
    return const [];
  }

  static String _typeOf(Object? value) => switch (value) {
    null => 'null',
    String() => 'string',
    num() => 'number',
    bool() => 'boolean',
    List() => 'array',
    Map() => 'object',
    _ => 'value',
  };

  static TextEditingValue complete(
    TextEditingValue value,
    HttpScriptSlot slot,
    HttpScriptSuggestion choice,
  ) {
    final hasParen = value.text.substring(slot.end).trimLeft().startsWith('(');
    final suffix = choice.method && !hasParen ? '()' : '';
    final replacement = '${choice.name}$suffix';
    final text = value.text.replaceRange(slot.start, slot.end, replacement);
    final caret =
        slot.start + choice.name.length + (choice.method && !hasParen ? 1 : 0);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: caret),
    );
  }

  static bool _inStringOrComment(String source, int start, int end) {
    String? quote;
    var lineComment = false;
    var blockComment = false;
    var escaped = false;
    for (var i = start; i < end; i++) {
      final char = source[i];
      final next = i + 1 < end ? source[i + 1] : '';
      if (lineComment) {
        if (char == '\n') lineComment = false;
      } else if (blockComment) {
        if (char == '*' && next == '/') {
          blockComment = false;
          i++;
        }
      } else if (quote != null) {
        if (escaped) {
          escaped = false;
        } else if (char == '\\') {
          escaped = true;
        } else if (char == quote) {
          quote = null;
        }
      } else if (char == '/' && next == '/') {
        lineComment = true;
        i++;
      } else if (char == '/' && next == '*') {
        blockComment = true;
        i++;
      } else if (char == "'" || char == '"' || char == '`') {
        quote = char;
      }
    }
    return quote != null || lineComment || blockComment;
  }
}
