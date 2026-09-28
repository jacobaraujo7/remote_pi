import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/cockpit/data/tasks/project_paths.dart';
import 'package:cockpit/app/cockpit/domain/entities/task_definition.dart';
import 'package:cockpit/app/core/data/jsonc.dart';
import 'package:yaml/yaml.dart';

enum ComposeEngine { docker, dockerLegacy, podman, podmanLegacy }

extension ComposeEngineCommand on ComposeEngine {
  String get command => switch (this) {
    ComposeEngine.docker => 'docker',
    ComposeEngine.dockerLegacy => 'docker-compose',
    ComposeEngine.podman => 'podman',
    ComposeEngine.podmanLegacy => 'podman-compose',
  };
  List<String> get prefix => switch (this) {
    ComposeEngine.docker || ComposeEngine.podman => const ['compose'],
    _ => const [],
  };
  bool get isDocker =>
      this == ComposeEngine.docker || this == ComposeEngine.dockerLegacy;
}

class ComposeFile {
  const ComposeFile(this.path, this.services);
  final String path;
  final List<String> services;
}

class ComposeFileParser {
  const ComposeFileParser();

  Future<ComposeFile?> parse(String path, String workspace) async {
    final lower = path.toLowerCase();
    if (!(lower.endsWith('.yaml') || lower.endsWith('.yml'))) return null;
    final normalizedRoot = Directory(workspace).absolute.path;
    final normalizedPath = File(path).absolute.path;
    if (normalizedPath != normalizedRoot &&
        !normalizedPath.startsWith(
          '$normalizedRoot${Platform.pathSeparator}',
        )) {
      return null;
    }
    try {
      final yaml = loadYaml(await File(normalizedPath).readAsString());
      if (yaml is! YamlMap || yaml['services'] is! YamlMap) return null;
      final services = (yaml['services'] as YamlMap).keys
          .map((e) => '$e')
          .toList();
      if (services.isEmpty) return null;
      final parent = await _includingParent(normalizedPath, normalizedRoot);
      return ComposeFile(parent ?? normalizedPath, services);
    } catch (_) {
      return null;
    }
  }

  /// When this file is included by a top-level Compose file, use that parent
  /// for execution. Docker labels only the parent and it owns project_directory
  /// and root .env semantics.
  Future<String?> _includingParent(String child, String workspace) async {
    var dir = File(child).parent;
    while (dir.path == workspace ||
        dir.path.startsWith('$workspace${Platform.pathSeparator}')) {
      for (final name in const [
        'compose.yaml',
        'compose.yml',
        'docker-compose.yaml',
        'docker-compose.yml',
      ]) {
        final candidate = File(joinPath(dir.path, name));
        if (!await candidate.exists() || candidate.absolute.path == child) {
          continue;
        }
        try {
          final yaml = loadYaml(await candidate.readAsString());
          if (yaml is YamlMap && _includes(yaml['include'], child, dir.path)) {
            return candidate.absolute.path;
          }
        } catch (_) {}
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return null;
  }

  bool _includes(Object? value, String child, String base) {
    if (value is! YamlList) return false;
    for (final item in value) {
      final raw = item is String
          ? item
          : item is YamlMap
          ? item['path']
          : null;
      if (raw is String && File(resolveCwd(base, raw)).absolute.path == child) {
        return true;
      }
    }
    return false;
  }
}

class ComposeEngineResolver {
  const ComposeEngineResolver();

  Future<List<ComposeEngine>> available() async {
    final out = <ComposeEngine>[];
    for (final engine in ComposeEngine.values) {
      final args = [...engine.prefix, 'version'];
      try {
        final result = await Process.run(engine.command, args);
        if (result.exitCode == 0) out.add(engine);
      } catch (_) {}
    }
    return out;
  }

  Future<Set<String>> runningServices(ComposeEngine engine, String file) async {
    final cwd = File(file).parent.path;
    final base = [...engine.prefix, '-f', file, 'ps', '--services'];
    ProcessResult result;
    try {
      result = await Process.run(engine.command, [
        ...base,
        '--status',
        'running',
      ], workingDirectory: cwd);
      if (result.exitCode != 0) {
        result = await Process.run(engine.command, base, workingDirectory: cwd);
      }
    } catch (_) {
      return _runningFromLabels(engine, file);
    }
    final direct = result.exitCode == 0
        ? LineSplitter.split(
            '${result.stdout}',
          ).map((e) => e.trim()).where((e) => e.isNotEmpty).toSet()
        : <String>{};
    return {...direct, ...await _runningFromLabels(engine, file)};
  }

  Future<Set<String>> _runningFromLabels(
    ComposeEngine engine,
    String file,
  ) async {
    final runtime = engine.isDocker ? 'docker' : 'podman';
    try {
      final result = await Process.run(runtime, const [
        'ps',
        '--filter',
        'label=com.docker.compose.service',
        '--format',
        '{{.Label "com.docker.compose.project.working_dir"}}\t{{.Label "com.docker.compose.project.config_files"}}\t{{.Label "com.docker.compose.service"}}',
      ]);
      if (result.exitCode != 0) return const {};
      final target = File(file).absolute.path;
      final targetDir = File(target).parent.path;
      final services = <String>{};
      for (final line in LineSplitter.split('${result.stdout}')) {
        final fields = line.split('\t');
        if (fields.length < 3 || fields[2].isEmpty) continue;
        final working = fields[0];
        final configs = fields[1].split(',').map((p) => File(p).absolute.path);
        final sameConfig = configs.contains(target);
        final relatedWorkspace =
            working.isNotEmpty &&
            (_isWithin(targetDir, working) || _isWithin(working, targetDir));
        if (sameConfig || relatedWorkspace) services.add(fields[2]);
      }
      return services;
    } catch (_) {
      return const {};
    }
  }

  bool _isWithin(String path, String root) =>
      path == root || path.startsWith('$root${Platform.pathSeparator}');
}

class ComposeTask {
  const ComposeTask({
    required this.engine,
    required this.file,
    required this.service,
  });
  final ComposeEngine engine;
  final String file;
  final String service;
}

class ComposeTaskRecognizer {
  const ComposeTaskRecognizer();

  ComposeTask? recognize(TaskDefinition def) {
    final executable = def.command.replaceAll('\\', '/').split('/').last;
    final ComposeEngine? engine = switch (executable) {
      'docker' => ComposeEngine.docker,
      'docker-compose' => ComposeEngine.dockerLegacy,
      'podman' => ComposeEngine.podman,
      'podman-compose' => ComposeEngine.podmanLegacy,
      _ => null,
    };
    if (engine == null) return null;
    final args = def.args;
    var i = 0;
    if (engine.prefix.isNotEmpty) {
      if (args.isEmpty || args.first != 'compose') return null;
      i = 1;
    }
    String? file;
    while (i < args.length) {
      final a = args[i];
      if ((a == '-f' || a == '--file') && i + 1 < args.length) {
        if (file != null) return null;
        file = args[++i];
      } else if (a.startsWith('--file=')) {
        if (file != null) return null;
        file = a.substring(7);
      }
      i++;
    }
    if (file == null) return null;
    final services = <String>{};
    for (final p in def.profiles) {
      final s = _service(p.args);
      if (s == null) return null;
      services.add(s);
    }
    if (services.length != 1) return null;
    return ComposeTask(
      engine: engine,
      file: isAbsolutePath(file) ? file : resolveCwd(def.cwd, file),
      service: services.single,
    );
  }

  String? _service(List<String> args) {
    if (args.isEmpty || !const {'up', 'build'}.contains(args.first)) {
      return null;
    }
    final values = args.skip(1).where((a) => !a.startsWith('-')).toList();
    return values.length == 1 ? values.single : null;
  }
}

class ComposeTaskGenerator {
  const ComposeTaskGenerator();

  Map<String, Object?> taskMap(
    ComposeEngine engine,
    String file,
    String service,
    String workspace,
  ) {
    final dir = File(file).parent.path;
    final relDir = _relative(dir, workspace);
    final relFile = _relative(file, dir);
    final base = [...engine.prefix, '-f', relFile];
    return {
      'label': service,
      'cwd': relDir,
      'command': engine.command,
      'args': base,
      'kind': 'watch',
      'preview': false,
      'profiles': [
        {
          'name': 'up',
          'args': ['up', '-d', service],
        },
        {
          'name': 'build',
          'args': ['build', service],
        },
        {
          'name': 'recreate',
          'args': ['up', '-d', '--force-recreate', '--no-deps', service],
        },
        {
          'name': 'recreate-deps',
          'args': [
            'up',
            '-d',
            '--force-recreate',
            '--always-recreate-deps',
            service,
          ],
        },
      ],
    };
  }

  String _relative(String path, String base) {
    final prefix = base.endsWith(Platform.pathSeparator)
        ? base
        : '$base${Platform.pathSeparator}';
    if (path == base) return '.';
    return path.startsWith(prefix) ? path.substring(prefix.length) : path;
  }
}

class ComposeMergeResult {
  const ComposeMergeResult({required this.content, this.conflicts = const []});
  final String content;
  final List<String> conflicts;
}

/// JSONC-preserving merger. Existing text is retained byte-for-byte except for
/// recognized Compose objects, which are replaced, and new objects appended.
class ComposeTasksJsonMerger {
  const ComposeTasksJsonMerger();

  ComposeMergeResult merge(
    String existing,
    List<Map<String, Object?>> generated,
    String workspace,
  ) {
    if (existing.trim().isEmpty) existing = '{\n  "tasks": []\n}\n';
    Object? decoded;
    try {
      decoded = jsonDecode(stripJsonc(existing));
    } catch (_) {
      throw const FormatException('Invalid tasks.json');
    }
    if (decoded is! Map) throw const FormatException('Invalid tasks.json');
    if (!decoded.containsKey('tasks')) {
      final close = existing.lastIndexOf('}');
      if (close < 0) throw const FormatException('Invalid tasks.json');
      final prefix = existing.substring(0, close).trimRight();
      final hasFields = decoded.isNotEmpty;
      existing =
          '$prefix${hasFields ? ',' : ''}\n  "tasks": []\n${existing.substring(close)}';
      decoded = {...decoded, 'tasks': <Object?>[]};
    }
    final bounds = _tasksArray(existing);
    if (bounds == null) throw const FormatException('tasks must be an array');
    final spans = _objectSpans(existing, bounds.$1, bounds.$2);
    final recognizer = const ComposeTaskRecognizer();
    final loaderTasks = <TaskDefinition>[];
    final rawTasks = decoded['tasks'];
    if (rawTasks is! List) {
      throw const FormatException('tasks must be an array');
    }
    // Pair parsed task maps with textual object spans (both preserve array order).
    for (final raw in rawTasks) {
      if (raw is Map && raw['label'] is String && raw['command'] is String) {
        final profiles = <TaskProfile>[];
        if (raw['profiles'] is List) {
          for (final p in raw['profiles'] as List) {
            if (p is Map && p['name'] is String) {
              profiles.add(
                TaskProfile(
                  name: p['name'] as String,
                  args: (p['args'] as List? ?? const [])
                      .map((e) => '$e')
                      .toList(),
                ),
              );
            }
          }
        }
        loaderTasks.add(
          TaskDefinition(
            id: 'json:${raw['label']}',
            label: raw['label'] as String,
            cwd: resolveCwd(workspace, raw['cwd'] as String?),
            command: raw['command'] as String,
            args: (raw['args'] as List? ?? const []).map((e) => '$e').toList(),
            profiles: profiles,
          ),
        );
      } else {
        loaderTasks.add(
          const TaskDefinition(id: '', label: '', cwd: '', command: ''),
        );
      }
    }
    final conflicts = <String>[];
    final replacements = <int, String>{};
    final additions = <Map<String, Object?>>[];
    for (final next in generated) {
      final label = next['label'] as String;
      final nextDef = _definition(next, workspace);
      final nextCompose = recognizer.recognize(nextDef)!;
      var matched = false;
      for (var i = 0; i < loaderTasks.length && i < spans.length; i++) {
        if (loaderTasks[i].label != label) continue;
        final current = recognizer.recognize(loaderTasks[i]);
        if (current == null ||
            current.service != nextCompose.service ||
            !_sameOrIncludedFile(current.file, nextCompose.file)) {
          conflicts.add(label);
          matched = true;
          break;
        }
        replacements[i] = _pretty(next, spans[i].indent);
        matched = true;
        break;
      }
      if (!matched) additions.add(next);
    }
    var body = existing;
    for (final e in replacements.entries.toList().reversed) {
      final s = spans[e.key];
      body = body.replaceRange(s.start, s.end, e.value);
    }
    if (additions.isNotEmpty) {
      final refreshed = _tasksArray(body)!;
      final before = body.substring(0, refreshed.$2).trimRight();
      final hasValues = _objectSpans(
        body,
        refreshed.$1,
        refreshed.$2,
      ).isNotEmpty;
      final text = additions.map((e) => _pretty(e, '    ')).join(',\n');
      body =
          '$before${hasValues && !before.endsWith(',') ? ',' : ''}\n$text\n  ${body.substring(refreshed.$2)}';
    }
    return ComposeMergeResult(content: body, conflicts: conflicts);
  }

  bool _sameOrIncludedFile(String a, String b) {
    final left = _canonical(a);
    final right = _canonical(b);
    if (left == right) return true;
    return _fileIncludes(left, right) || _fileIncludes(right, left);
  }

  String _canonical(String path) {
    try {
      return File(path).resolveSymbolicLinksSync();
    } catch (_) {
      return File(path).absolute.path;
    }
  }

  bool _fileIncludes(String parent, String child) {
    try {
      final yaml = loadYaml(File(parent).readAsStringSync());
      if (yaml is! YamlMap || yaml['include'] is! YamlList) return false;
      for (final item in yaml['include'] as YamlList) {
        final raw = item is String
            ? item
            : item is YamlMap
            ? item['path']
            : null;
        if (raw is String &&
            _canonical(resolveCwd(File(parent).parent.path, raw)) == child) {
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  TaskDefinition _definition(Map<String, Object?> raw, String workspace) {
    final profiles = <TaskProfile>[];
    for (final p in raw['profiles'] as List? ?? const []) {
      if (p is Map && p['name'] is String) {
        profiles.add(
          TaskProfile(
            name: p['name'] as String,
            args: (p['args'] as List? ?? const []).map((e) => '$e').toList(),
          ),
        );
      }
    }
    return TaskDefinition(
      id: 'json:${raw['label']}',
      label: raw['label'] as String,
      cwd: resolveCwd(workspace, raw['cwd'] as String?),
      command: raw['command'] as String,
      args: (raw['args'] as List? ?? const []).map((e) => '$e').toList(),
      profiles: profiles,
    );
  }

  String _pretty(Map<String, Object?> value, String indent) =>
      const JsonEncoder.withIndent('  ')
          .convert(value)
          .split('\n')
          .map((l) => '$indent$l')
          .join('\n')
          .substring(indent.length);

  (int, int)? _tasksArray(String s) {
    final m = RegExp(r'"tasks"\s*:').firstMatch(stripJsonc(s));
    if (m == null) return null;
    // Comments preserve length only by line, so locate the real key then scan.
    final real = RegExp(r'"tasks"\s*:').firstMatch(s);
    if (real == null) return null;
    final open = s.indexOf('[', real.end);
    if (open < 0) return null;
    final close = _matching(s, open, '[', ']');
    return close < 0 ? null : (open + 1, close);
  }

  List<({int start, int end, String indent})> _objectSpans(
    String s,
    int start,
    int end,
  ) {
    final out = <({int start, int end, String indent})>[];
    var i = start;
    while (i < end) {
      if (s[i] == '{') {
        final close = _matching(s, i, '{', '}');
        if (close < 0) break;
        final line = s.lastIndexOf('\n', i) + 1;
        final prefix = s.substring(line, i);
        out.add((
          start: i,
          end: close + 1,
          indent: prefix.trim().isEmpty ? prefix : '    ',
        ));
        i = close + 1;
      } else {
        i++;
      }
    }
    return out;
  }

  int _matching(String s, int open, String left, String right) {
    var depth = 0, string = false, escape = false;
    for (var i = open; i < s.length; i++) {
      final c = s[i];
      if (string) {
        if (escape) {
          escape = false;
        } else if (c == '\\') {
          escape = true;
        } else if (c == '"') {
          string = false;
        }
        continue;
      }
      if (c == '"') {
        string = true;
        continue;
      }
      if (c == left) depth++;
      if (c == right && --depth == 0) return i;
    }
    return -1;
  }
}

class ComposeTasksWriter {
  const ComposeTasksWriter();
  Future<ComposeMergeResult> write(
    String workspace,
    List<Map<String, Object?>> tasks,
  ) async {
    final path = joinPath(joinPath(workspace, '.cockpit'), 'tasks.json');
    final file = File(path);
    final existing = await file.exists() ? await file.readAsString() : '';
    final result = const ComposeTasksJsonMerger().merge(
      existing,
      tasks,
      workspace,
    );
    await file.parent.create(recursive: true);
    final temp = File('$path.tmp.$pid');
    await temp.writeAsString(result.content, flush: true);
    await temp.rename(path);
    return result;
  }
}
