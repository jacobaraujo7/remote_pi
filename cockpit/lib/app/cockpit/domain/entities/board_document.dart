import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

part 'board_markdown.dart';

enum BoardKind {
  process,
  decision,
  note,
  text,
  service,
  container,
  lane,
  stroke,
  arrow,
  mermaid,
}

typedef BoardPoint = ({double x, double y});

class BoardItem {
  const BoardItem(
    this.id,
    this.kind,
    this.x,
    this.y, {
    this.color,
    this.label = '',
    this.thumbnail,
    this.group,
    this.from,
    this.to,
    this.points = const [],
    this.width = 136,
    this.height = 64,
  });
  final String id, label;
  final String? color;
  bool get usesInkColor =>
      kind == BoardKind.text ||
      kind == BoardKind.arrow ||
      kind == BoardKind.stroke;
  String get contrastInk {
    if (color == null) return '#202020';
    double channel(int offset) {
      final c =
          int.parse(color!.substring(offset, offset + 2), radix: 16) / 255;
      return c <= .04045 ? c / 12.92 : pow((c + .055) / 1.055, 2.4).toDouble();
    }

    return .2126 * channel(1) + .7152 * channel(3) + .0722 * channel(5) > .179
        ? '#000000'
        : '#FFFFFF';
  }

  static String? rgb(Object? value) =>
      value is String && RegExp(r'^#[a-fA-F0-9]{6}$').hasMatch(value)
      ? value.toUpperCase()
      : null;

  bool get isBackdrop => kind == BoardKind.lane || kind == BoardKind.container;
  final BoardKind kind;
  final double x, y, width, height;
  final String? from, to, thumbnail, group;
  // Offscreen diagrams need not keep a second copy of the encoded image.
  static final _decodedThumbnails = Expando<WeakReference<Uint8List>>();
  Uint8List? get thumbnailBytes {
    final source = thumbnail;
    if (source == null) return null;
    final cached = _decodedThumbnails[this]?.target;
    if (cached != null) return cached;
    final bytes = base64Decode(source).asUnmodifiableView();
    _decodedThumbnails[this] = WeakReference(bytes);
    return bytes;
  }

  final List<BoardPoint> points;

  bool sameContent(BoardItem other) {
    if (id != other.id ||
        kind != other.kind ||
        x != other.x ||
        y != other.y ||
        width != other.width ||
        height != other.height ||
        color != other.color ||
        label != other.label ||
        group != other.group ||
        from != other.from ||
        to != other.to ||
        thumbnail != other.thumbnail ||
        points.length != other.points.length) {
      return false;
    }
    if (!identical(points, other.points)) {
      for (var index = 0; index < points.length; index++) {
        if (points[index] != other.points[index]) return false;
      }
    }
    return true;
  }

  BoardItem edited({
    double? x,
    double? y,
    String? label,
    String? thumbnail,
    String? group,
    String? color,
    bool clearColor = false,
    bool ungroup = false,
  }) {
    final copy = BoardItem(
      id,
      kind,
      x ?? this.x,
      y ?? this.y,
      label: label ?? this.label,
      thumbnail:
          thumbnail ??
          (kind == BoardKind.mermaid && label != null && label != this.label
              ? null
              : this.thumbnail),
      color: clearColor ? null : color ?? this.color,
      group: ungroup ? null : group ?? this.group,
      width: width,
      height: height,
      from: from,
      to: to,
      points: points,
    );
    if (this.thumbnail != null && copy.thumbnail == this.thumbnail) {
      _decodedThumbnails[copy] = _decodedThumbnails[this];
    }
    return copy;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    if (color != null) 'color': color,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'label': label,
    if (group != null) 'group': group,
    if (thumbnail != null) 'thumbnail': thumbnail,
    if (from != null) 'from': from,
    if (to != null) 'to': to,
    if (points.isNotEmpty)
      'points': [
        for (final p in points) [p.x, p.y],
      ],
  };

  factory BoardItem.read(Map<String, dynamic> json) {
    double number(dynamic n) {
      if (n is! num || !n.isFinite) {
        throw const FormatException('Invalid coordinate');
      }
      return n.toDouble();
    }

    final kind = BoardKind.values.byName(json['kind'] as String);
    final color = rgb(json['color']);
    if (json['color'] != null && color == null) {
      throw const FormatException('Invalid board color');
    }
    final item = BoardItem(
      json['id'] as String,
      kind,
      number(json['x']),
      number(json['y']),
      width: number(json['width']),
      height: number(json['height']),
      color: color,
      label: json['label'] as String,
      thumbnail: json['thumbnail'] as String?,
      group: json['group'] as String?,
      from: json['from'] as String?,
      to: json['to'] as String?,
      points: [
        for (final p in json['points'] as List? ?? [])
          (x: number(p[0]), y: number(p[1])),
      ],
    );
    if (item.thumbnail != null) {
      if (kind != BoardKind.mermaid) {
        throw const FormatException('Unexpected board thumbnail');
      }
      item.thumbnailBytes;
    }
    if (item.id.isEmpty ||
        item.width <= 0 ||
        item.height <= 0 ||
        (kind == BoardKind.stroke && item.points.isEmpty)) {
      throw const FormatException('Invalid board item');
    }
    return item;
  }
}

class BoardDocument {
  BoardDocument(Iterable<BoardItem> elements, {this.id, this.eol = '\n'})
    : items = Map.unmodifiable({for (final e in elements) e.id: e}) {
    if (items.length != elements.length) {
      throw const FormatException('Duplicate board item');
    }
    for (final e in items.values.where((i) => i.kind == BoardKind.arrow)) {
      if (!items.containsKey(e.from) ||
          !items.containsKey(e.to) ||
          items[e.from]!.kind == BoardKind.arrow ||
          items[e.to]!.kind == BoardKind.arrow) {
        throw const FormatException('Missing connector endpoint');
      }
    }
  }
  final Map<String, BoardItem> items;
  late final List<BoardItem> paintOrder = List.unmodifiable([
    ...items.values.where((i) => i.isBackdrop),
    ...items.values.where((i) => i.kind == BoardKind.arrow),
    ...items.values.where((i) => !i.isBackdrop && i.kind != BoardKind.arrow),
  ]);
  final String? id;
  final String eol;
  static final _rng = Random.secure();
  static String newId() => List.generate(
    16,
    (_) => _rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  static const _heading = '# Canvas Board';
  static final _field = RegExp(r'^- ([a-z]+): (.+)$', dotAll: true);
  static final _mermaidFence = RegExp(r'^(`{3,})mermaid$');
  static const _itemFields = {
    'id',
    'color',
    'x',
    'y',
    'width',
    'height',
    'label',
    'group',
    'thumbnail',
    'from',
    'to',
    'points',
  };

  String encode() => _CanvasMarkdown.write(this);

  static BoardDocument _readLegacyMarkdown(String source) {
    final lines = const LineSplitter().convert(source);
    if (lines.isEmpty || lines.first != _heading) {
      throw const FormatException('Expected Canvas Board heading');
    }
    final metadata = <String, dynamic>{};
    final records = <Map<String, dynamic>>[];
    var fields = metadata;
    for (var i = 1; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().isEmpty) continue;
      if (line.startsWith('## ')) {
        fields = {'kind': BoardKind.values.byName(line.substring(3)).name};
        records.add(fields);
        continue;
      }
      final fence = _mermaidFence.firstMatch(line);
      if (fence != null &&
          fields['kind'] == 'mermaid' &&
          !fields.containsKey('label')) {
        final start = ++i;
        while (i < lines.length && lines[i] != fence[1]) {
          i++;
        }
        if (i == lines.length) {
          throw const FormatException('Unclosed Mermaid fence');
        }
        fields['label'] = lines.sublist(start, i).join('\n');
        continue;
      }
      final field = _field.firstMatch(line);
      final key = field?[1];
      final allowed = identical(fields, metadata)
          ? const {'version', 'id'}
          : _itemFields;
      if (key == null || !allowed.contains(key) || fields.containsKey(key)) {
        throw FormatException('Invalid Canvas Board field on line ${i + 1}');
      }
      fields[key] = jsonDecode(field![2]!);
    }
    if (metadata['version'] != 2) {
      throw const FormatException('Unsupported board version');
    }
    return BoardDocument(
      records.map(BoardItem.read).toList(),
      id: metadata['id'] as String?,
    );
  }

  factory BoardDocument.parse(String source) {
    try {
      source = source.replaceFirst(RegExp('^\uFEFF'), '').trimLeft();
      if (source.startsWith('---')) return _CanvasMarkdown.read(source);
      if (!source.startsWith('{')) return _readLegacyMarkdown(source);
      final map = jsonDecode(source);
      if (map['version'] != 1) {
        throw const FormatException('Unsupported board version');
      }
      return BoardDocument([
        for (final e in map['items'] as List)
          BoardItem.read(e as Map<String, dynamic>),
      ], id: map['id'] as String?);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Invalid board document');
    }
  }
}
