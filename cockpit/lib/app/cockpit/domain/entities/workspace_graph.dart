import 'dart:ui';

/// A graph box is identified independently of the terminal backing it. This
/// keeps links stable when a session is replaced or the box is moved.
class GraphBox {
  const GraphBox({
    required this.id,
    required this.title,
    required this.role,
    required this.harness,
    required this.model,
    required this.position,
    this.tabId,
  });

  final String id;
  final String title;
  final String role;
  final String harness;
  final String model;
  final Offset position;
  final String? tabId;

  GraphBox copyWith({
    String? title,
    Offset? position,
    String? tabId,
    String? role,
    String? harness,
    String? model,
  }) => GraphBox(
    id: id,
    title: title ?? this.title,
    role: role ?? this.role,
    harness: harness ?? this.harness,
    model: model ?? this.model,
    position: position ?? this.position,
    tabId: tabId ?? this.tabId,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'role': role,
    'harness': harness,
    'model': model,
    'x': position.dx,
    'y': position.dy,
    'tabId': tabId,
  };

  static GraphBox? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final title = raw['title'];
    if (id is! String || title is! String) return null;
    return GraphBox(
      id: id,
      title: title,
      role: raw['role'] is String ? raw['role'] as String : '',
      harness: raw['harness'] is String ? raw['harness'] as String : '',
      model: raw['model'] is String ? raw['model'] as String : '',
      position: Offset(
        (raw['x'] as num?)?.toDouble() ?? 0,
        (raw['y'] as num?)?.toDouble() ?? 0,
      ),
      tabId: raw['tabId'] is String ? raw['tabId'] as String : null,
    );
  }
}

class GraphLink {
  const GraphLink({required this.from, required this.to});
  final String from;
  final String to;

  Map<String, String> toJson() => {'from': from, 'to': to};

  static GraphLink? fromJson(Object? raw) {
    if (raw is! Map || raw['from'] is! String || raw['to'] is! String) {
      return null;
    }
    return GraphLink(from: raw['from'] as String, to: raw['to'] as String);
  }
}

class GraphObservedLink {
  const GraphObservedLink({
    required this.fromTabId,
    required this.toTabId,
    required this.observedAt,
  });
  final String fromTabId;
  final String toTabId;
  final DateTime observedAt;
}

/// A Claude recipient whose address cannot yet be matched to a Cockpit tab.
/// It is runtime-only and must never be represented as a terminal session.
class GraphUnresolvedPeer {
  const GraphUnresolvedPeer({
    required this.projectId,
    required this.ownerTabId,
    required this.address,
    required this.observedAt,
  });

  final String projectId;
  final String ownerTabId;
  final String address;
  final DateTime observedAt;

  String get id => '$ownerTabId::peer::$address';
}

/// A running child owned by a terminal tab. Never written to workspace layout.
class GraphSubagent {
  const GraphSubagent({
    required this.projectId,
    required this.ownerTabId,
    required this.agentId,
    required this.agentType,
    required this.harness,
    required this.startedAt,
  });

  final String projectId;
  final String ownerTabId;
  final String agentId;
  final String agentType;
  final String harness;
  final DateTime startedAt;

  String get id => '$ownerTabId::$agentId';
}

/// Keeps repeated start/resume hooks idempotent and removes children on stop.
class GraphSubagentRegistry {
  final Map<String, GraphSubagent> _active = {};
  final Map<String, DateTime> _stoppedAt = {};

  List<GraphSubagent> forProject(String? projectId) => [
    for (final child in _active.values)
      if (child.projectId == projectId) child,
  ];

  bool start(GraphSubagent child) {
    final key = child.id;
    final stoppedAt = _stoppedAt[key];
    if (stoppedAt != null && !child.startedAt.isAfter(stoppedAt)) return false;
    if (_active.containsKey(key)) return false;
    _active[key] = child;
    return true;
  }

  bool stop(String ownerTabId, String agentId, DateTime occurredAt) {
    final key = '$ownerTabId::$agentId';
    final previous = _stoppedAt[key];
    if (previous == null || occurredAt.isAfter(previous)) {
      _stoppedAt[key] = occurredAt;
    }
    if (_stoppedAt.length > 256) _stoppedAt.remove(_stoppedAt.keys.first);
    final active = _active[key];
    if (active == null || active.startedAt.isAfter(occurredAt)) return false;
    _active.remove(key);
    return true;
  }

  bool clearOwner(String ownerTabId) {
    final count = _active.length;
    _active.removeWhere((_, child) => child.ownerTabId == ownerTabId);
    _stoppedAt.removeWhere((key, _) => key.startsWith('$ownerTabId::'));
    return _active.length != count;
  }
}
