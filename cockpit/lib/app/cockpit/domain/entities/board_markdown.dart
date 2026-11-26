part of 'board_document.dart';

/// Markdown v3. Object order is paint order, and a quoted body is a label.
class _CanvasMarkdown {
  static final _breaks = RegExp(r'\r\n|\r|\n');
  static final _ticks = RegExp(r'`{3,}');
  static final _inlineEscape = RegExp(r'\\([\\nr])');
  static final _fence = RegExp(r'^(`{3,})mermaid$');
  static const _strings = {'id', 'color', 'group', 'from', 'to', 'thumbnail'};
  static const _numbers = {'x', 'y', 'width', 'height'};

  static String _inline(String value) => value
      .replaceAll('\\', r'\\')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r');

  static String _restoreInline(String value) {
    if (!value.contains('\\')) return value;
    return value.replaceAllMapped(
      _inlineEscape,
      (m) => switch (m[1]) {
        'n' => '\n',
        'r' => '\r',
        _ => '\\',
      },
    );
  }

  static String write(BoardDocument doc) {
    final lines = [
      '---',
      doc.items.values.any((i) => i.z != 0 || i.strokeWidth != null)
          ? 'version: 4'
          : 'version: 3',
      if (doc.id != null) 'id: ${_inline(doc.id!)}',
      '---',
      '',
      '# Canvas Board',
    ];
    for (final item in doc.items.values) {
      lines.addAll([
        '',
        '## ${item.kind.name}',
        '',
        '- id: ${_inline(item.id)}',
        '- x: ${item.x}',
        '- y: ${item.y}',
        '- width: ${item.width}',
        '- height: ${item.height}',
        if (item.color != null) '- color: ${item.color}',
        if (item.strokeWidth != null) '- stroke: ${item.strokeWidth}',
        if (item.z != 0) '- z: ${item.z}',
        if (item.group != null) '- group: ${_inline(item.group!)}',
        if (item.from != null) '- from: ${_inline(item.from!)}',
        if (item.to != null) '- to: ${_inline(item.to!)}',
        if (item.thumbnail != null) '- thumbnail: ${item.thumbnail}',
        if (item.points.isNotEmpty) '- points:',
        for (final p in item.points) '  - ${p.x}, ${p.y}',
      ]);
      if (item.label.contains('\r')) {
        final endings = _breaks
            .allMatches(item.label)
            .map(
              (m) => switch (m[0]) {
                '\r\n' => 'crlf',
                '\r' => 'cr',
                _ => 'lf',
              },
            )
            .toList();
        lines.add('- line-endings: ${endings.join(' ')}');
      }
      final body = item.label.split(_breaks);
      if (item.kind == BoardKind.mermaid) {
        var length = 3;
        for (final match in _ticks.allMatches(item.label)) {
          length = max(length, match.end - match.start + 1);
        }
        final fence = '`' * length;
        lines.addAll(['', '${fence}mermaid', ...body, fence]);
      } else if (item.label.isNotEmpty) {
        lines.addAll(['', for (final line in body) '> $line']);
      }
    }
    return [...lines, ''].join(doc.eol);
  }

  static BoardDocument read(String source) {
    final lines = const LineSplitter().convert(source);
    var index = 1;
    final header = <String, String>{};
    while (index < lines.length && lines[index] != '---') {
      final entry = _property(lines[index++]);
      if (!const {'id', 'version'}.contains(entry.key) ||
          header.containsKey(entry.key)) {
        throw const FormatException('Invalid board metadata');
      }
      header[entry.key] = entry.value;
    }
    if (lines.first != '---' ||
        index >= lines.length ||
        !const {'3', '4'}.contains(header['version'])) {
      throw const FormatException('Unsupported board version');
    }
    index++;
    while (index < lines.length && lines[index].isEmpty) {
      index++;
    }
    if (index >= lines.length || lines[index++] != BoardDocument._heading) {
      throw const FormatException('Expected Canvas Board heading');
    }
    final items = <BoardItem>[];
    while (index < lines.length) {
      if (lines[index].trim().isEmpty) {
        index++;
        continue;
      }
      final heading = lines[index++];
      if (!heading.startsWith('## ')) {
        throw const FormatException('Expected object heading');
      }
      final kind = BoardKind.values.byName(heading.substring(3));
      final fields = <String, dynamic>{'kind': kind.name};
      List<String>? body, endings;
      while (index < lines.length && !lines[index].startsWith('## ')) {
        final line = lines[index++];
        if (line.trim().isEmpty) continue;
        if (line.startsWith('- ')) {
          final entry = _property(line, start: 2);
          final key = entry.key;
          if (fields.containsKey(key)) {
            throw FormatException('Duplicate field $key');
          }
          if (_strings.contains(key)) {
            fields[key] = _restoreInline(entry.value);
          } else if (header['version'] == '4' && key == 'stroke') {
            fields[key] = double.parse(entry.value);
          } else if (header['version'] == '4' && key == 'z') {
            fields[key] = int.parse(entry.value);
          } else if (_numbers.contains(key)) {
            fields[key] = double.parse(entry.value);
          } else if (key == 'points' && entry.value.isEmpty) {
            final points = <List<double>>[];
            while (index < lines.length && lines[index].startsWith('  - ')) {
              final point = lines[index++];
              final comma = point.indexOf(',', 4);
              if (comma < 0) {
                throw const FormatException('Expected x, y');
              }
              points.add([
                double.parse(point.substring(4, comma)),
                double.parse(point.substring(comma + 1)),
              ]);
            }
            fields[key] = points;
          } else if (key == 'line-endings' && endings == null) {
            endings = entry.value
                .split(' ')
                .map(
                  (v) => switch (v) {
                    'lf' => '\n',
                    'cr' => '\r',
                    'crlf' => '\r\n',
                    _ => throw const FormatException('Invalid line ending'),
                  },
                )
                .toList();
          } else {
            throw FormatException('Unknown board field $key');
          }
        } else if (line == '>' || line.startsWith('> ')) {
          if (kind == BoardKind.mermaid || body != null) {
            throw const FormatException('Unexpected label');
          }
          body = [line == '>' ? '' : line.substring(2)];
          while (index < lines.length &&
              (lines[index] == '>' || lines[index].startsWith('> '))) {
            final next = lines[index++];
            body.add(next == '>' ? '' : next.substring(2));
          }
        } else {
          final fence = _fence.firstMatch(line);
          if (kind != BoardKind.mermaid || body != null || fence == null) {
            throw const FormatException('Unexpected board content');
          }
          final start = index;
          while (index < lines.length && lines[index] != fence[1]) {
            index++;
          }
          if (index == lines.length) {
            throw const FormatException('Unclosed Mermaid fence');
          }
          body = lines.sublist(start, index++);
        }
      }
      if (kind == BoardKind.mermaid && body == null) {
        throw const FormatException('Expected Mermaid fence');
      }
      final parts = body ?? const <String>[];
      if (endings == null) {
        fields['label'] = parts.join('\n');
      } else {
        if (endings.length + 1 != parts.length) {
          throw const FormatException('Invalid label line endings');
        }
        fields['label'] = [
          for (var i = 0; i < parts.length; i++) ...[
            if (i > 0) endings[i - 1],
            parts[i],
          ],
        ].join();
      }
      items.add(BoardItem.read(fields));
    }
    return BoardDocument(
      items,
      id: header['id'] == null ? null : _restoreInline(header['id']!),
      eol: source.startsWith('---\r\n') ? '\r\n' : '\n',
    );
  }

  static MapEntry<String, String> _property(String line, {int start = 0}) {
    final colon = line.indexOf(':', start);
    if (colon <= start) throw const FormatException('Expected board property');
    final value = colon + 1;
    return MapEntry(
      line.substring(start, colon),
      line.substring(line.startsWith(' ', value) ? value + 1 : value),
    );
  }
}
