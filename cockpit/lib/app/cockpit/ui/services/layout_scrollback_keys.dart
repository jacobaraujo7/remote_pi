/// Scrollback referenced by saved workspace layouts, including app-owned
/// terminals. This is a retention pass only: it must never reconcile sessions
/// or interpret a portable document as local runtime state.
Set<String> layoutScrollbackKeys(Iterable<Map<String, dynamic>?> layouts) {
  final keep = <String>{};
  void keepTerminals(Object? raw) {
    if (raw is! Map) return;
    for (final entry in raw.entries) {
      final descriptor = entry.value;
      if (entry.key is String &&
          descriptor is Map &&
          descriptor['type'] == 'terminal') {
        keep.add(entry.key as String);
      }
    }
  }

  for (final layout in layouts) {
    final sessions = layout?['sessions'];
    if (sessions is! Map) continue;
    keepTerminals(sessions);
    for (final descriptor in sessions.values) {
      if (descriptor is! Map) continue;
      if (descriptor['type'] == 'task_output' &&
          descriptor['taskId'] is String) {
        keep.add(descriptor['taskId'] as String);
      } else if (descriptor['type'] == 'orchestration') {
        // Retain known child descriptors even for an unsupported local-state
        // version. A future/invalid app layout must not delete recoverable
        // history before restoration can report its error.
        keepTerminals(descriptor['sessions']);
      }
    }
  }
  return keep;
}
