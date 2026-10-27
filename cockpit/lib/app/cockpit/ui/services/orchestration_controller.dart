import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Offset;
import '../../domain/entities/orchestration_document.dart';
import '../../domain/entities/workspace_graph.dart';

class OrchestrationTerminal {
  const OrchestrationTerminal(this.id, this.title, this.directory);
  final String id, title, directory;
}

/// One serialized reconciliation queue per worktree, independent of the UI's
/// currently selected project. No tool command is part of this interface.
class OrchestrationController extends ChangeNotifier {
  OrchestrationController({
    required this.read,
    required this.write,
    required this.createShell,
    required this.closeTerminal,
    required this.terminals,
    required this.newBoxId,
    Map<String, String>? bindings,
  }) : bindings = {...?bindings} {
    _instances.add(this);
  }
  static final Set<OrchestrationController> _instances = {};
  static Future<void> flushAll() async {
    for (final controller in _instances.toList()) {
      await controller.settle();
    }
  }

  final Future<String> Function() read;
  final Future<void> Function(String) write;
  final Future<String> Function(OrchestrationBox) createShell;
  final Future<void> Function(String) closeTerminal;
  final List<OrchestrationTerminal> Function() terminals;
  final String Function() newBoxId;
  final Map<String, String> bindings;
  final Map<String, OrchestrationBox> pendingRemovals = {};
  OrchestrationDocument? document;
  String? error;
  bool dirty = false;
  bool busy = false;
  bool _disposed = false;
  Future<void> _queue = Future.value();
  Future<void> _run(Future<void> Function() action) {
    if (_disposed) return Future.value();
    final done = _queue.then((_) async {
      busy = true;
      try {
        await action();
        error = null;
      } catch (e) {
        error = e.toString();
      } finally {
        busy = false;
        if (!_disposed) notifyListeners();
      }
    });
    _queue = done;
    return done;
  }

  List<GraphBox> get graphBoxes => [
    for (final b in document?.boxes ?? const <OrchestrationBox>[])
      b.box.copyWith(tabId: bindings[b.box.id] ?? ''),
    for (final b in pendingRemovals.values)
      b.box.copyWith(tabId: bindings[b.box.id] ?? ''),
  ];
  void reportError(Object failure) {
    error = failure.toString();
    if (!_disposed) notifyListeners();
  }

  Future<void> settle() async {
    while (true) {
      final pending = _queue;
      await pending;
      if (identical(pending, _queue)) return;
    }
  }

  void switchDocument(Map<String, String> nextBindings) {
    document = null;
    pendingRemovals.clear();
    error = null;
    dirty = false;
    bindings
      ..clear()
      ..addAll(nextBindings);
  }

  Future<void> load() => _run(() async {
    // A failed save is retried rather than overwritten by an old watcher echo.
    if (dirty && document != null) {
      await _save();
      return;
    }
    final next = OrchestrationDocument.parse(await read());
    final live = {for (final t in terminals()) t.id};
    for (final old in document?.boxes ?? const <OrchestrationBox>[]) {
      if (!next.boxes.any((b) => b.box.id == old.box.id) &&
          live.contains(bindings[old.box.id])) {
        pendingRemovals[old.box.id] = old;
      }
    }
    pendingRemovals.removeWhere(
      (id, _) => next.boxes.any((b) => b.box.id == id),
    );
    document = next;
    // Retain each binding as soon as its shell exists, including if a later
    // shell fails. Retrying therefore cannot duplicate the successful ones.
    for (final b in next.boxes) {
      if (!live.contains(bindings[b.box.id])) {
        final id = await createShell(b);
        bindings[b.box.id] = id;
        live.add(id);
      }
    }
    await _discover();
  });
  Future<void> _discover() async {
    final doc = document;
    if (doc == null) return;
    final bound = bindings.values.toSet();
    final boxes = [...doc.boxes];
    for (final t in terminals()) {
      if (bound.contains(t.id)) continue;
      final id = newBoxId();
      boxes.add(
        OrchestrationBox(
          box: GraphBox(
            id: id,
            title: t.title,
            role: '',
            harness: '',
            model: '',
            position: autoPosition(boxes.length),
          ),
          directory: t.directory,
        ),
      );
      bindings[id] = t.id;
      bound.add(t.id);
    }
    if (boxes.length != doc.boxes.length) {
      document = OrchestrationDocument(
        boxes: boxes,
        links: doc.links,
        extra: doc.extra,
      );
      dirty = true;
      await _save();
    }
  }

  Future<void> discover() => _run(_discover);
  Future<void> update(List<OrchestrationBox> boxes, List<GraphLink> links) =>
      _run(() async {
        final doc = document;
        if (doc == null) return;
        document = OrchestrationDocument(
          boxes: boxes,
          links: links,
          extra: doc.extra,
        );
        dirty = true;
        await _save();
      });
  Future<void> forgetTerminal(String tabId) => _run(() async {
    final ids = bindings.entries
        .where((e) => e.value == tabId)
        .map((e) => e.key)
        .toSet();
    for (final id in ids) {
      bindings.remove(id);
      pendingRemovals.remove(id);
    }
    final doc = document;
    if (doc == null || ids.isEmpty) return;
    document = OrchestrationDocument(
      boxes: doc.boxes.where((b) => !ids.contains(b.box.id)).toList(),
      links: doc.links
          .where((l) => !ids.contains(l.from) && !ids.contains(l.to))
          .toList(),
      extra: doc.extra,
    );
    dirty = true;
    await _save();
  });
  Future<void> resolveRemoval(String boxId, {required bool close}) =>
      _run(() async {
        final old = pendingRemovals[boxId];
        if (old == null) return;
        if (close) {
          final tabId = bindings[boxId];
          if (tabId != null) await closeTerminal(tabId);
          bindings.remove(boxId);
          pendingRemovals.remove(boxId);
        } else {
          final doc = document!;
          document = OrchestrationDocument(
            boxes: [...doc.boxes, old],
            links: doc.links,
            extra: doc.extra,
          );
          dirty = true;
          await _save();
          pendingRemovals.remove(boxId);
        }
      });
  Future<void> _save() async {
    await write(document!.encode());
    dirty = false;
  }

  static Offset autoPosition(int index) =>
      Offset(80 + (index % 4) * 270.0, 80 + (index ~/ 4) * 190.0);
  @override
  void dispose() {
    _disposed = true;
    unawaited(settle().whenComplete(() => _instances.remove(this)));
    super.dispose();
  }
}
