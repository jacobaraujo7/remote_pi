import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Offset;
import '../../domain/entities/orchestration_document.dart';
import '../../domain/entities/workspace_graph.dart';

class OrchestrationTerminal {
  const OrchestrationTerminal(this.id, this.title, this.directory);
  final String id, title, directory;
}

/// One serialized reconciliation queue per document, independent of the UI's
/// currently selected project. No tool command is part of this interface.
class OrchestrationController extends ChangeNotifier {
  OrchestrationController({
    required this.read,
    required this.write,
    required this.createShell,
    required this.closeTerminal,
    required this.terminals,
    required this.newBoxId,
    this.flushLocalState,
    Map<String, String>? bindings,
  }) : bindings = {...?bindings} {
    _instances.add(this);
  }
  static final Set<OrchestrationController> _instances = {};
  static Future<void> flushAll() async {
    for (final controller in _instances.toList()) {
      await controller.settle();
      if (!controller._disposed) await controller.flushLocalState?.call();
    }
  }

  final Future<void> Function()? flushLocalState;

  /// Local startup restoration must settle before file reconciliation. Retried
  /// loads use this same gate after a temporary host/native failure.
  Future<void> Function()? beforeReconcile;
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
  String? _lastDiskText;
  Timer? _pollTimer;
  bool _polling = false;
  bool _reconcileSavedSnapshot = false;
  void startPolling({Duration interval = const Duration(seconds: 5)}) {
    if (_disposed) return;
    _pollTimer ??= Timer.periodic(interval, (_) => poll());
  }

  Future<void> poll() async {
    if (_disposed || _polling || busy) return;
    _polling = true;
    try {
      if (dirty) {
        await load();
        return;
      }
      final text = await read();
      if (!_disposed && (text != _lastDiskText || error != null)) await load();
    } catch (e) {
      if (!_disposed) reportError(e);
    } finally {
      _polling = false;
    }
  }

  Future<void> _queue = Future.value();
  Future<void> _run(Future<void> Function() action) {
    if (_disposed) return Future.value();
    final done = _queue.then((_) async {
      busy = true;
      try {
        await beforeReconcile?.call();
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

  /// Seed validated local state only at startup, before polling/reconciliation.
  /// The caller restores owned native sessions separately; this never spawns.
  void restoreSnapshot({
    required OrchestrationDocument? savedDocument,
    required Map<String, String> savedBindings,
    OrchestrationDocument? savedPendingRemovals,
    bool wasDirty = false,
  }) {
    if (_disposed || document != null || bindings.isNotEmpty) {
      throw StateError('Controller restoration must precede loading');
    }
    document = savedDocument;
    bindings.addAll(savedBindings);
    pendingRemovals.addAll({
      for (final b in savedPendingRemovals?.boxes ?? const <OrchestrationBox>[])
        b.box.id: b,
    });
    dirty = wasDirty;
    _reconcileSavedSnapshot = true;
    notifyListeners();
  }

  void switchDocument(Map<String, String> nextBindings) {
    _lastDiskText = null;
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
      // Ordinary failed-write retries remain write-only. Startup is different:
      // some saved shells may still be absent after a partial recovery.
      if (!_reconcileSavedSnapshot) return;
    }
    _reconcileSavedSnapshot = false;
    final diskText = await read();
    final next = OrchestrationDocument.parse(diskText);
    _lastDiskText = diskText;
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
  });

  /// Explicit creation is the only way to register a new box. Inventory events
  /// must never turn an unrelated workspace terminal into document content.
  Future<void> addBox(OrchestrationBox box) => _run(() async {
    final doc = document;
    if (doc == null) throw StateError('Document unavailable');
    if (doc.boxes.any((b) => b.box.id == box.box.id)) {
      if (dirty) await _save();
      return;
    }
    if (pendingRemovals.containsKey(box.box.id)) {
      throw StateError('Box removal is pending confirmation');
    }
    // Validate the complete prospective document before allocating a PTY.
    OrchestrationDocument.parse(
      OrchestrationDocument(
        boxes: [...doc.boxes, box],
        links: doc.links,
        extra: doc.extra,
      ).encode(),
    );
    final current = bindings[box.box.id];
    if (current == null || !terminals().any((t) => t.id == current)) {
      bindings[box.box.id] = await createShell(box);
    }
    document = OrchestrationDocument(
      boxes: [...doc.boxes, box],
      links: doc.links,
      extra: doc.extra,
    );
    dirty = true;
    await _save();
  });

  /// Replacing an exited session is serialized with file reconciliation.
  /// An expected binding makes repeated concurrent restart requests idempotent.
  Future<void> restartShell(String boxId, {required String expectedTabId}) =>
      _run(() async {
        if (bindings[boxId] != expectedTabId) return;
        final box = document?.boxes.where((b) => b.box.id == boxId).firstOrNull;
        if (box == null) throw StateError('Box not found');
        final replacement = await createShell(box);
        bindings[boxId] = replacement;
        try {
          await closeTerminal(expectedTabId);
        } catch (e, st) {
          // A disconnect may prevent the old session from closing after the
          // replacement exists. Keep both represented instead of orphaning it.
          final doc = document!;
          if (terminals().any((t) => t.id == expectedTabId)) {
            final historyId = newBoxId();
            bindings[historyId] = expectedTabId;
            document = OrchestrationDocument(
              boxes: [
                ...doc.boxes,
                OrchestrationBox(
                  box: GraphBox(
                    id: historyId,
                    title: '${box.box.title} (${doc.boxes.length + 1})',
                    role: box.box.role,
                    harness: box.box.harness,
                    model: box.box.model,
                    position: autoPosition(doc.boxes.length),
                  ),
                  directory: box.directory,
                ),
              ],
              links: doc.links,
              extra: doc.extra,
            );
            dirty = true;
            await _save();
          }
          Error.throwWithStackTrace(e, st);
        }
      });

  Future<void> handoff(String boxId, {required String historyTitle}) =>
      _run(() async {
        final doc = document;
        final box = doc?.boxes.where((b) => b.box.id == boxId).firstOrNull;
        if (doc == null || box == null) throw StateError('Box not found');
        final previous = bindings[boxId];
        final replacement = await createShell(box);
        bindings[boxId] = replacement;
        if (previous != null && terminals().any((t) => t.id == previous)) {
          final historyId = newBoxId();
          bindings[historyId] = previous;
          document = OrchestrationDocument(
            boxes: [
              ...doc.boxes,
              OrchestrationBox(
                box: GraphBox(
                  id: historyId,
                  title: historyTitle,
                  role: box.box.role,
                  harness: box.box.harness,
                  model: box.box.model,
                  position: autoPosition(doc.boxes.length),
                ),
                directory: box.directory,
              ),
            ],
            links: doc.links,
            extra: doc.extra,
          );
          dirty = true;
          await _save();
        }
      });

  /// Compute against the latest queued document, so simultaneous inspector,
  /// reorder and graph edits cannot overwrite each other's stale snapshots.
  Future<void> mutate(
    OrchestrationDocument Function(OrchestrationDocument current) edit,
  ) => _run(() async {
    final doc = document;
    if (doc == null) throw StateError('Document unavailable');
    final next = OrchestrationDocument.parse(edit(doc).encode());
    document = next;
    dirty = true;
    await _save();
  });

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
    final encoded = document!.encode();
    await write(encoded);
    _lastDiskText = encoded;
    dirty = false;
  }

  // Keep newly created nodes below the graph controls/legend, like the
  // default document. Saved positions are never passed through this function.
  static Offset autoPosition(int index) =>
      Offset(80 + (index % 4) * 270.0, 190 + (index ~/ 4) * 190.0);
  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    unawaited(settle().whenComplete(() => _instances.remove(this)));
    super.dispose();
  }
}
