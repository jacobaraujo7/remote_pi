import '../entities/board_document.dart';

/// All replacements are checked against the objects captured when editing
/// started. Unrelated edits survive applying and undoing the edit.
class BoardEdit {
  BoardEdit(this.before, this.after);
  final Map<String, BoardItem?> before, after;
  BoardEdit get inverse => BoardEdit(after, before);
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
    return BoardDocument(next.values, id: current.id, eol: current.eol);
  }

  factory BoardEdit.replace(BoardDocument doc, BoardItem item) =>
      BoardEdit({item.id: doc.items[item.id]}, {item.id: item});
  factory BoardEdit.remove(BoardDocument doc, String id) {
    final removed = {
      for (final e in doc.items.values)
        if (e.id == id || e.from == id || e.to == id) e.id: e,
    };
    return BoardEdit(removed, {for (final key in removed.keys) key: null});
  }
}
