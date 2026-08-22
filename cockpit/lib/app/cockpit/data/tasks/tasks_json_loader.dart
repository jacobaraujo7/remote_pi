import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/core/data/jsonc.dart';
import 'package:cockpit/app/cockpit/data/tasks/project_paths.dart';
import 'package:cockpit/app/cockpit/domain/entities/task_definition.dart';

/// Lê o `.cockpit/tasks.json` (manual, versionável) de um workspace e o traduz
/// em [TaskDefinition]s genéricas. É o espelho 1:1 das entities — não conhece
/// stack nenhuma; flavor/dart-define do usuário entram como `args` crus.
///
/// Resolução de `cwd`: relativa à **raiz do workspace** (a pasta que contém o
/// `.cockpit/`), per-task; top-level `cwd` é só default. Ver plano 48.
class TasksJsonLoader {
  const TasksJsonLoader({this.hostOs});

  /// SO usado no filtro de `platforms` — só sobrescrito em teste.
  final String? hostOs;

  String get _os => hostOs ?? Platform.operatingSystem;

  /// Caminho do arquivo a partir da raiz do workspace.
  static String pathFor(String workspaceCwd) =>
      joinPath(joinPath(workspaceCwd, '.cockpit'), 'tasks.json');

  /// Tasks declaradas no JSON. Lista vazia se o arquivo não existe ou é
  /// inválido (a descoberta segue só com os adapters).
  Future<List<TaskDefinition>> load(String workspaceCwd) async {
    if (workspaceCwd.isEmpty) return const [];
    final file = File(pathFor(workspaceCwd));
    if (!await file.exists()) return const [];
    return parseContent(await file.readAsString(), workspaceCwd);
  }

  /// Parseia o conteúdo JSONC de um `tasks.json` (sem tocar no filesystem) —
  /// reusado pela descoberta REMOTA (plano 58), que lê o arquivo do host via
  /// `fs.read`. [workspaceCwd] é a raiz onde os `cwd` relativos das tasks
  /// resolvem (no remoto, a pasta do host).
  List<TaskDefinition> parseContent(String content, String workspaceCwd) {
    final Object? decoded;
    try {
      // JSONC: aceita comentários (// e /* */) e vírgulas finais.
      decoded = jsonDecode(stripJsonc(content));
    } catch (_) {
      return const []; // JSON malformado → ignora silenciosamente
    }
    if (decoded is! Map) return const [];

    final defaultCwd = decoded['cwd'] as String?;
    final rawTasks = decoded['tasks'];
    if (rawTasks is! List) return const [];

    final tasks = <TaskDefinition>[];
    for (final raw in rawTasks) {
      if (raw is! Map) continue;
      final def = _parseTask(raw, workspaceCwd, defaultCwd);
      if (def != null) tasks.add(def);
    }
    return tasks;
  }

  TaskDefinition? _parseTask(
    Map<dynamic, dynamic> m,
    String workspaceCwd,
    String? defaultCwd,
  ) {
    final label = m['label'] as String?;
    final command = m['command'] as String?;
    if (label == null || command == null) return null; // mínimos obrigatórios
    if (!_visibleOnThisOs(m['platforms'])) return null;

    final cwd = resolveCwd(workspaceCwd, (m['cwd'] as String?) ?? defaultCwd);

    return TaskDefinition(
      id: 'json:$label',
      label: label,
      cwd: cwd,
      command: command,
      args: _strList(m['args']),
      kind: _kind(m['kind']),
      source: TaskSource.manual,
      profiles: _profiles(m['profiles']),
      interactiveKeys: _keys(m['interactiveKeys']),
      watch: _watch(m['watch']),
      progressPatterns: _patterns(m['progressPatterns']),
      // `preview`: false desliga o auto-open do navegador; string = URL fixa.
      previewEnabled: m['preview'] != false,
      previewUrl: m['preview'] is String ? m['preview'] as String : null,
      previewOpen: _previewOpen(m['previewOpen']),
    );
  }

  /// `platforms`: string ou lista de `"macos"|"windows"|"linux"` (nomes do
  /// `Platform.operatingSystem`). Ausente/vazio/tipo errado → visível em todos.
  bool _visibleOnThisOs(Object? v) {
    final List<String> platforms;
    if (v is String) {
      platforms = [v];
    } else if (v is List) {
      platforms = v.map((e) => e.toString()).toList();
    } else {
      return true;
    }
    if (platforms.isEmpty) return true;
    return platforms.any((p) => p.toLowerCase() == _os);
  }

  // --- parsers de campo (tolerantes: tipo errado → default) --------------

  List<String> _strList(Object? v) =>
      v is List ? v.map((e) => e.toString()).toList() : const [];

  TaskKind _kind(Object? v) => v == 'watch' ? TaskKind.watch : TaskKind.oneShot;

  /// `previewOpen`: `always` (default) | `start` | `never`. Ausente, tipo errado
  /// ou valor desconhecido → `always`, o comportamento histórico.
  TaskPreviewOpen _previewOpen(Object? v) => switch (v) {
    'start' => TaskPreviewOpen.start,
    'never' => TaskPreviewOpen.never,
    _ => TaskPreviewOpen.always,
  };

  List<TaskProfile> _profiles(Object? v) {
    if (v is! List) return const [];
    final out = <TaskProfile>[];
    for (final raw in v) {
      if (raw is! Map) continue;
      final name = raw['name'] as String?;
      if (name == null) continue;
      out.add(
        TaskProfile(
          name: name,
          args: _strList(raw['args']),
          env: _strMap(raw['env']),
        ),
      );
    }
    return out;
  }

  Map<String, String> _strMap(Object? v) {
    if (v is! Map) return const {};
    return {for (final e in v.entries) e.key.toString(): e.value.toString()};
  }

  List<InteractiveKey> _keys(Object? v) {
    if (v is! List) return const [];
    final out = <InteractiveKey>[];
    for (final raw in v) {
      if (raw is! Map) continue;
      final key = raw['key'] as String?;
      final label = raw['label'] as String?;
      if (key == null || label == null) continue;
      out.add(
        InteractiveKey(
          key: key,
          label: label,
          icon: raw['icon'] as String?,
          primary: raw['primary'] == true,
        ),
      );
    }
    return out;
  }

  TaskWatch? _watch(Object? v) {
    if (v is! Map) return null;
    final onChange = v['onChange'] as String?;
    if (onChange == null) return null;
    return TaskWatch(
      paths: _strList(v['paths']),
      ignore: _strList(v['ignore']),
      onChange: onChange,
      debounceMs: (v['debounceMs'] as num?)?.toInt() ?? 300,
    );
  }

  List<ProgressPattern> _patterns(Object? v) {
    if (v is! List) return const [];
    final out = <ProgressPattern>[];
    for (final raw in v) {
      if (raw is! Map) continue;
      final begin = raw['begin'] as String?;
      final end = raw['end'] as String?;
      if (begin == null || end == null) continue;
      out.add(ProgressPattern(begin: begin, end: end));
    }
    return out;
  }
}
