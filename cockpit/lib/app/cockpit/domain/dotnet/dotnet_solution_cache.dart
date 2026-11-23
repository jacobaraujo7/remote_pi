import 'dart:convert';

import 'package:cockpit/app/cockpit/domain/dotnet/dotnet_solution.dart';
import 'package:cockpit/app/cockpit/domain/dotnet/dotnet_solution_parser.dart';
import 'package:crypto/crypto.dart';

/// Cache de processo. A chave é o caminho absoluto, então worktrees diferentes
/// não compartilham modelo, expansão nem solução ativa.
class DotnetSolutionCache {
  DotnetSolutionCache();

  static final instance = DotnetSolutionCache();

  final Map<String, _CachedModel> _models = {};
  final Map<String, Set<String>> _expanded = {};
  final Map<String, String?> _selected = {};
  final Map<String, bool> _modes = {};
  final Map<String, String> _active = {};

  DotnetSolutionSnapshot? peek(String solutionPath) =>
      _models[solutionPath]?.snapshot;

  DotnetSolutionSnapshot? modelIfFresh(
    String solutionPath,
    String fingerprint,
  ) {
    final cached = _models[solutionPath];
    if (cached == null || cached.fingerprint != fingerprint) return null;
    return cached.snapshot;
  }

  void putModel(
    String solutionPath,
    String fingerprint,
    DotnetSolutionSnapshot snapshot,
  ) {
    _models[solutionPath] = _CachedModel(fingerprint, snapshot);
  }

  bool hasExpansion(String solutionPath) => _expanded.containsKey(solutionPath);

  Set<String> expansion(String solutionPath) =>
      _expanded.putIfAbsent(solutionPath, () => <String>{});

  void toggleExpanded(String solutionPath, String id) {
    final ids = expansion(solutionPath);
    if (!ids.add(id)) ids.remove(id);
  }

  void seedExpansion(String solutionPath, Set<String> ids) {
    _expanded[solutionPath] = {...ids};
  }

  void collapse(String solutionPath) {
    _expanded[solutionPath] = <String>{};
  }

  String? selectedNode(String solutionPath) => _selected[solutionPath];

  void setSelectedNode(String solutionPath, String? id) {
    _selected[solutionPath] = id;
  }

  bool solutionMode(String root) => _modes[root] ?? false;

  void setSolutionMode(String root, bool value) {
    _modes[root] = value;
  }

  String? activeSolution(String root) => _active[root];

  void setActiveSolution(String root, String path) {
    _active[root] = path;
  }

  void clear() {
    _models.clear();
    _expanded.clear();
    _selected.clear();
    _modes.clear();
    _active.clear();
  }
}

class _CachedModel {
  const _CachedModel(this.fingerprint, this.snapshot);
  final String fingerprint;
  final DotnetSolutionSnapshot snapshot;
}

String dotnetContentFingerprint(
  String solutionText,
  Map<String, String> projects,
) {
  final keys = projects.keys.toList()..sort();
  final buffer = StringBuffer(solutionText)..write('\u0000');
  for (final key in keys) {
    buffer
      ..write(key)
      ..write('\u0000')
      ..write(projects[key])
      ..write('\u0000');
  }
  return sha256.convert(utf8.encode(buffer.toString())).toString();
}

/// Relê a solução e os projetos. Fingerprint igual devolve o modelo cacheado
/// sem chamar o parser de novo.
Future<DotnetSolutionSnapshot?> loadCachedDotnetSolution({
  required DotnetSolutionCache cache,
  required String path,
  required Future<String?> Function(String path) read,
  DotnetSolutionParser parser = const DotnetSolutionParser(),
}) async {
  final text = await read(path);
  if (text == null) return null;
  final projectPaths = parser.projectFiles(
    solutionPath: path,
    solutionText: text,
  );
  final texts = <String, String>{};
  for (final project in projectPaths) {
    texts[project] = await read(project) ?? '';
  }
  final fingerprint = dotnetContentFingerprint(text, texts);
  final fresh = cache.modelIfFresh(path, fingerprint);
  if (fresh != null) return fresh;
  final parsed = parser.parse(
    solutionPath: path,
    solutionText: text,
    projectTexts: texts,
  );
  if (parsed == null) return null;
  final stored = parsed.withFingerprint(fingerprint);
  cache.putModel(path, fingerprint, stored);
  return stored;
}
