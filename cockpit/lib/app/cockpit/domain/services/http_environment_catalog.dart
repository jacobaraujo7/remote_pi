import 'dart:convert';

import 'package:path/path.dart' as p;

/// Ambientes nomeados encontrados entre a raiz do projeto e um arquivo `.http`.
class HttpEnvironmentCatalog {
  const HttpEnvironmentCatalog(
    this.environments, [
    this.definitions = const {},
  ]);

  final Map<String, Map<String, String>> environments;
  final Map<String, Map<String, HttpEnvironmentDefinition>> definitions;

  List<String> get names => environments.keys.toList()..sort();

  Map<String, String> valuesFor(String? name) =>
      name == null ? const {} : environments[name] ?? const {};

  HttpEnvironmentDefinition? definitionFor(String? environment, String name) =>
      definitions[environment]?[name];

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
    final definitions = <String, Map<String, HttpEnvironmentDefinition>>{};
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
        final lines = _JsonKeyLines(content).read();
        for (final entry in decoded.entries) {
          if (entry.value is! Map<String, dynamic>) continue;
          final values = merged.putIfAbsent(entry.key, () => {});
          final origins = definitions.putIfAbsent(entry.key, () => {});
          _flatten(entry.value as Map<String, dynamic>, values);
          for (final name in _flattenedNames(
            entry.value as Map<String, dynamic>,
          )) {
            final line = lines[entry.key]?[name];
            if (line != null) {
              origins[name] = HttpEnvironmentDefinition(
                paths.join(folder, filename),
                line,
              );
            }
          }
        }
      }
    }
    return HttpEnvironmentCatalog(merged, definitions);
  }

  static Iterable<String> _flattenedNames(
    Map<String, dynamic> source, [
    String prefix = '',
  ]) sync* {
    for (final entry in source.entries) {
      final key = prefix.isEmpty ? entry.key : '$prefix.${entry.key}';
      if (entry.value is Map<String, dynamic>) {
        yield* _flattenedNames(entry.value as Map<String, dynamic>, key);
      } else {
        yield key;
      }
    }
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

class HttpEnvironmentDefinition {
  const HttpEnvironmentDefinition(this.path, this.line);

  final String path;
  final int line; // base 1
}

/// Localiza chaves no JSON válido preservando a estrutura dos objetos.
/// `jsonDecode` valida o conteúdo antes de este leitor ser chamado.
class _JsonKeyLines {
  _JsonKeyLines(this.source);

  final String source;
  int cursor = 0;
  final Map<String, Map<String, int>> result = {};

  Map<String, Map<String, int>> read() {
    _value(null, '', 0);
    return result;
  }

  void _space() {
    while (cursor < source.length &&
        (source[cursor] == ' ' ||
            source[cursor] == '\n' ||
            source[cursor] == '\r' ||
            source[cursor] == '\t')) {
      cursor++;
    }
  }

  String _string() {
    final start = cursor++;
    while (cursor < source.length) {
      if (source[cursor] == '\\') {
        cursor += 2;
      } else if (source[cursor++] == '"') {
        break;
      }
    }
    return jsonDecode(source.substring(start, cursor)) as String;
  }

  void _value(String? environment, String prefix, int depth) {
    _space();
    if (cursor >= source.length) return;
    if (source[cursor] == '{') {
      cursor++;
      _space();
      while (cursor < source.length && source[cursor] != '}') {
        final keyOffset = cursor;
        final key = _string();
        _space();
        cursor++; // :
        final childEnvironment = depth == 0 ? key : environment;
        final childPrefix = depth == 0
            ? ''
            : prefix.isEmpty
            ? key
            : '$prefix.$key';
        _space();
        final nested = source[cursor] == '{';
        if (depth > 0 && !nested && childEnvironment != null) {
          result.putIfAbsent(childEnvironment, () => {})[childPrefix] =
              '\n'.allMatches(source.substring(0, keyOffset)).length + 1;
        }
        _value(childEnvironment, childPrefix, depth + 1);
        _space();
        if (source[cursor] == ',') {
          cursor++;
          _space();
        }
      }
      cursor++; // }
    } else if (source[cursor] == '[') {
      cursor++;
      _space();
      while (cursor < source.length && source[cursor] != ']') {
        _value(environment, prefix, depth + 1);
        _space();
        if (source[cursor] == ',') cursor++;
        _space();
      }
      cursor++; // ]
    } else if (source[cursor] == '"') {
      _string();
    } else {
      while (cursor < source.length && !',}] \n\r\t'.contains(source[cursor])) {
        cursor++;
      }
    }
  }
}
