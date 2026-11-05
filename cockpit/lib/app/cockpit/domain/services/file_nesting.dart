import 'package:cockpit/app/cockpit/domain/entities/file_node.dart';

/// A rule maps a parent filename glob to comma-separated child filename globs.
/// Patterns use the same glob and `${capture}` syntax as VS Code. Only sibling
/// files participate; folders remain independent.
Map<String, List<FileNode>> nestFiles(
  List<FileNode> nodes,
  Map<String, String> patterns,
) {
  final files = nodes.where((n) => !n.isDirectory).toList();
  final children = <String, List<FileNode>>{};
  final owner = <String, String>{};
  for (final parent in files) {
    for (final rule in patterns.entries) {
      final capture = _capture(rule.key, parent.name);
      if (capture == null) continue;
      for (final childPattern in rule.value.split(',')) {
        final glob = childPattern.trim();
        if (glob.isEmpty) continue;
        final expanded = glob.replaceAll(r'${capture}', capture);
        for (final child in files) {
          if (child.path == parent.path || owner.containsKey(child.path)) {
            continue;
          }
          if (!_matches(expanded, child.name)) continue;
          // A child may itself be a parent. Keep the resulting forest acyclic.
          var ancestor = parent.path;
          var cycle = false;
          while (owner.containsKey(ancestor)) {
            ancestor = owner[ancestor]!;
            if (ancestor == child.path) {
              cycle = true;
              break;
            }
          }
          if (cycle) continue;
          owner[child.path] = parent.path;
          children.putIfAbsent(parent.path, () => []).add(child);
        }
      }
    }
  }
  return children;
}

String? _capture(String glob, String name) {
  final star = glob.indexOf('*');
  if (star < 0) return glob == name ? '' : null;
  final prefix = glob.substring(0, star);
  final suffix = glob.substring(star + 1);
  if (!name.startsWith(prefix) || !name.endsWith(suffix)) return null;
  if (name.length < prefix.length + suffix.length) return null;
  return name.substring(prefix.length, name.length - suffix.length);
}

bool _matches(String glob, String name) {
  final parts = glob.split('*');
  if (parts.length == 1) return glob == name;
  if (!name.startsWith(parts.first) || !name.endsWith(parts.last)) return false;
  var cursor = parts.first.length;
  for (final part in parts.skip(1).take(parts.length - 2)) {
    final next = name.indexOf(part, cursor);
    if (next < 0) return false;
    cursor = next + part.length;
  }
  return cursor <= name.length - parts.last.length;
}
