import '../entities/board_document.dart';

/// All replacements are checked against the objects captured when editing
/// started. Unrelated edits survive applying and undoing the edit.
class BoardEdit {
  BoardEdit(this.before, this.after, {this.originalOrder = const []});
  final List<String> originalOrder;
  final Map<String, BoardItem?> before, after;
  BoardEdit get inverse =>
      BoardEdit(after, before, originalOrder: originalOrder);
  BoardDocument apply(BoardDocument current) {
    final next = {...current.items};
    for (final id in before.keys) {
      final actual = current.items[id], expected = before[id];
      if (!identical(actual, expected) &&
          (actual == null ||
              expected == null ||
              !actual.sameContent(expected))) {
        throw StateError('Board selection has changed');
      }
      final replacement = after[id];
      if (replacement == null) {
        next.remove(id);
      } else {
        next[id] = replacement;
      }
    }
    final restoring = {
      for (final id in before.keys)
        if (before[id] == null && after[id] != null) id,
    };
    if (restoring.isNotEmpty && originalOrder.isNotEmpty) {
      final aheadOf = <String?, List<BoardItem>>{};
      String? anchor;
      for (final id in originalOrder.reversed) {
        if (restoring.contains(id)) {
          (aheadOf[anchor] ??= []).add(next[id]!);
        } else if (next.containsKey(id)) {
          anchor = id;
        }
      }
      return BoardDocument(
        [
          for (final item in current.items.values) ...[
            ...?aheadOf[item.id]?.reversed,
            if (next[item.id] != null) next[item.id]!,
          ],
          ...?aheadOf[null]?.reversed,
        ],
        id: current.id,
        eol: current.eol,
      );
    }
    return BoardDocument(next.values, id: current.id, eol: current.eol);
  }

  factory BoardEdit.replace(BoardDocument doc, BoardItem item) =>
      BoardEdit({item.id: doc.items[item.id]}, {item.id: item});
  factory BoardEdit.remove(BoardDocument doc, String id) =>
      BoardEdit.removeMany(doc, {id});

  factory BoardEdit.removeMany(BoardDocument doc, Set<String> ids) {
    final removed = {
      for (final e in doc.items.values)
        if (ids.contains(e.id) || ids.contains(e.from) || ids.contains(e.to))
          e.id: e,
    };
    return BoardEdit(removed, {
      for (final key in removed.keys) key: null,
    }, originalOrder: doc.items.keys.toList());
  }

  factory BoardEdit.reorder(
    BoardDocument doc,
    Set<String> ids, {
    required bool front,
  }) {
    final order = doc.paintOrder;
    final chosen = order.where((i) => ids.contains(i.id)).toList();
    final others = order.where((i) => !ids.contains(i.id)).toList();
    if (chosen.isEmpty || others.isEmpty) return BoardEdit({}, {});
    var z = front ? others.last.z : others.first.z - chosen.length - 1;
    return BoardEdit(
      {for (final item in chosen) item.id: item},
      {for (final item in chosen) item.id: item.edited(z: ++z)},
    );
  }
}
