import 'dart:convert';
import 'package:flutter/widgets.dart' show Offset;
import 'workspace_graph.dart';

/// Portable configuration. Process IDs, transcripts and credentials never
/// belong here; bindings to live sessions are stored in the local layout.
class OrchestrationBox {
  const OrchestrationBox({required this.box, this.directory = '.'});
  final GraphBox box;
  final String directory;
  Map<String, Object?> toJson() => {
    ...box.toJson()..remove('tabId'),
    'directory': directory,
  };
}

class OrchestrationDocument {
  const OrchestrationDocument({
    this.boxes = const [],
    this.links = const [],
    this.extra = const {},
  });

  /// Canonical short extension; the previous extension remains readable.
  static bool isFilePath(String file) {
    final lower = file.toLowerCase();
    return lower.endsWith('.orc') || lower.endsWith('.orchestration');
  }

  /// A fresh app starts with three unassigned blank shells. Existing documents
  /// (including explicitly empty ones) are never filled to this count on load.
  factory OrchestrationDocument.defaultTerminals({
    required String Function() newId,
  }) => OrchestrationDocument(
    boxes: [
      for (var i = 0; i < 3; i++)
        OrchestrationBox(
          box: GraphBox(
            id: newId(),
            title: 'Terminal ${i + 1}',
            role: '',
            harness: '',
            model: '',
            position: Offset(80.0 + i * 280.0, 190),
          ),
        ),
    ],
  );

  final List<OrchestrationBox> boxes;
  final List<GraphLink> links;
  final Map<String, Object?> extra;
  String encode() =>
      '${const JsonEncoder.withIndent('  ').convert({...extra, 'version': 1, 'boxes': boxes.map((b) => b.toJson()).toList(), 'links': links.map((l) => l.toJson()).toList()})}\n';
  static OrchestrationDocument parse(String source) {
    final raw = jsonDecode(source);
    if (raw is! Map ||
        raw['version'] != 1 ||
        raw['boxes'] is! List ||
        raw['links'] is! List) {
      throw const FormatException(
        'Expected orchestration version 1, boxes and links',
      );
    }
    final boxes = <OrchestrationBox>[];
    final ids = <String>{};
    for (final item in raw['boxes'] as List) {
      final box = GraphBox.fromJson(item);
      if (box == null || box.id.isEmpty || !ids.add(box.id)) {
        throw const FormatException('Invalid or duplicate box ID');
      }
      final dir = (item as Map)['directory'] ?? '.';
      if (dir is! String ||
          dir.isEmpty ||
          dir.contains('\\') ||
          dir.startsWith('/') ||
          RegExp(r'^[A-Za-z]:').hasMatch(dir) ||
          dir.split('/').contains('..')) {
        throw const FormatException(
          'Box directory must be relative to the worktree',
        );
      }
      if (!box.position.dx.isFinite || !box.position.dy.isFinite) {
        throw const FormatException('Invalid graph position');
      }
      boxes.add(
        OrchestrationBox(
          box: GraphBox(
            id: box.id,
            title: box.title,
            role: box.role,
            harness: box.harness,
            model: box.model,
            position: Offset(box.position.dx, box.position.dy),
          ),
          directory: dir,
        ),
      );
    }
    final links = <GraphLink>[];
    for (final item in raw['links'] as List) {
      final link = GraphLink.fromJson(item);
      if (link == null ||
          link.from == link.to ||
          !ids.contains(link.from) ||
          !ids.contains(link.to)) {
        throw const FormatException('Connection refers to an unknown box');
      }
      if (!links.any((l) => l.from == link.from && l.to == link.to)) {
        links.add(link);
      }
    }
    return OrchestrationDocument(
      boxes: List.unmodifiable(boxes),
      links: List.unmodifiable(links),
      extra: Map<String, Object?>.from(raw)
        ..remove('version')
        ..remove('boxes')
        ..remove('links'),
    );
  }
}
