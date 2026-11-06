import 'dart:convert';

import 'package:path/path.dart' as p;

/// Ambientes nomeados encontrados entre a raiz do projeto e um arquivo `.http`.
class HttpEnvironmentCatalog {
  const HttpEnvironmentCatalog(this.environments);

  final Map<String, Map<String, String>> environments;

  List<String> get names => environments.keys.toList()..sort();

  Map<String, String> valuesFor(String? name) =>
      name == null ? const {} : environments[name] ?? const {};

  static List<String> directoriesFor(String httpPath, String rootPath) {
    final paths = p.Context(
      style: httpPath.startsWith('/') ? p.Style.posix : p.Style.windows,
    );
    final dir = paths.normalize(paths.dirname(httpPath));
    final root = paths.normalize(rootPath);
    final folders = <String>[];
    var cursor = dir;
    while (true) {
      folders.add(cursor);
      if (cursor == root) break;
      final parent = paths.dirname(cursor);
      if (parent == cursor ||
          (!paths.isWithin(root, parent) && parent != root)) {
        break;
      }
      cursor = parent;
    }
    return folders.reversed.toList();
  }

  /// Lê do ancestral mais distante até a pasta do arquivo. Em cada pasta, o
  /// privado vence o público; entre pastas, a mais próxima vence as anteriores.
  static Future<HttpEnvironmentCatalog> load({
    required String httpPath,
    required String rootPath,
    required Future<String?> Function(String path) readText,
  }) async {
    final paths = p.Context(
      style: httpPath.startsWith('/') ? p.Style.posix : p.Style.windows,
    );
    final merged = <String, Map<String, String>>{};
    for (final folder in directoriesFor(httpPath, rootPath)) {
      for (final filename in [
        'http-client.env.json',
        'http-client.private.env.json',
      ]) {
        String? content;
        try {
          content = await readText(paths.join(folder, filename));
        } on Object {
          continue; // arquivo ausente, inacessível ou host desconectado
        }
        if (content == null) continue;
        Object? decoded;
        try {
          decoded = jsonDecode(content);
        } on FormatException {
          continue; // arquivo parcialmente escrito; watcher recarrega depois
        }
        if (decoded is! Map<String, dynamic>) continue;
        for (final entry in decoded.entries) {
          if (entry.value is! Map<String, dynamic>) continue;
          final values = merged.putIfAbsent(entry.key, () => {});
          _flatten(entry.value as Map<String, dynamic>, values);
        }
      }
    }
    return HttpEnvironmentCatalog(merged);
  }

  static void _flatten(
    Map<String, dynamic> source,
    Map<String, String> out, [
    String prefix = '',
  ]) {
    for (final entry in source.entries) {
      final key = prefix.isEmpty ? entry.key : '$prefix.${entry.key}';
      final value = entry.value;
      if (value is Map<String, dynamic>) {
        _flatten(value, out, key);
      } else {
        out[key] = value is String ? value : jsonEncode(value);
      }
    }
  }
}
