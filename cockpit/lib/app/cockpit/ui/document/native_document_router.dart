import 'dart:async';
import 'package:path/path.dart' as paths;
import '../../domain/entities/orchestration_document.dart';
import '../../domain/entities/project.dart';

/// Native files can arrive before workspace restoration. Only orchestration
/// files wait for the main workspace; ordinary document windows keep their flow.
class NativeDocumentRouter {
  NativeDocumentRouter({required this.openDocument});
  final Future<void> Function(String) openDocument;
  final _pending = <({String path, Completer<void> completion})>[];
  Future<void> Function(String)? _openOrchestration;
  bool _draining = false;

  Future<void> open(String path) {
    if (!OrchestrationDocument.isFilePath(path)) return openDocument(path);
    final completion = Completer<void>();
    _pending.add((path: path, completion: completion));
    unawaited(_drain());
    return completion.future;
  }

  void Function() attach(Future<void> Function(String) openOrchestration) {
    _openOrchestration = openOrchestration;
    unawaited(_drain());
    return () {
      if (identical(_openOrchestration, openOrchestration)) {
        _openOrchestration = null;
      }
    };
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_pending.isNotEmpty && _openOrchestration != null) {
        final open = _openOrchestration!;
        final request = _pending.removeAt(0);
        try {
          await open(request.path);
          request.completion.complete();
        } on Object catch (error, stack) {
          request.completion.completeError(error, stack);
        }
      }
    } finally {
      _draining = false;
    }
  }
}

/// OS file paths are local. Prefer the nearest containing worktree; neither a
/// remote pin with a coincident path nor an unrelated selected project qualifies.
Project? nativeOrchestrationProject(
  String file,
  Iterable<Project> projects, {
  required String realmId,
  String? selectedProjectId,
  paths.Context? context,
}) {
  final p = context ?? paths.context;
  final absolute = p.normalize(p.absolute(file));
  final candidates = projects.where((project) {
    if (project.isSystemTerminal ||
        project.isRemoteTerminal ||
        project.remoteHostId != null ||
        project.path.isEmpty) {
      return false;
    }
    final root = p.normalize(p.absolute(project.effectiveRoot));
    return p.isWithin(root, absolute);
  }).toList();
  candidates.sort((a, b) {
    var order = p
        .normalize(p.absolute(b.effectiveRoot))
        .length
        .compareTo(p.normalize(p.absolute(a.effectiveRoot)).length);
    if (order != 0) return order;
    order = (b.realmId == realmId ? 1 : 0).compareTo(
      a.realmId == realmId ? 1 : 0,
    );
    if (order != 0) return order;
    order = (b.id == selectedProjectId ? 1 : 0).compareTo(
      a.id == selectedProjectId ? 1 : 0,
    );
    return order != 0 ? order : a.id.compareTo(b.id);
  });
  return candidates.firstOrNull;
}
