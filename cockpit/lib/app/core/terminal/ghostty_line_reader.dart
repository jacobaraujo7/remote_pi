import 'package:flterm/flterm.dart' as ghost;
// The pinned flterm does not expose grid content publicly. Keep its adapter
// confined to core/terminal so feature widgets never depend on these internals.
// ignore: implementation_imports, invalid_use_of_internal_member
import 'package:flterm/src/controller/terminal_controller.dart' as internal;
// ignore: implementation_imports, invalid_use_of_internal_member
import 'package:flterm/src/links/logical_line.dart' show LogicalLine;
import 'package:flutter/foundation.dart';
import 'package:libghostty/libghostty.dart' as native;

import 'terminal_context_menu.dart';

/// Session-owned, lazy snapshot of visible logical lines. Output, resize and
/// viewport movement invalidate it; pointer movement only indexes the snapshot.
final class GhosttyLineReader extends ChangeNotifier {
  GhosttyLineReader(ghost.TerminalController controller)
    // ignore: invalid_use_of_internal_member
    : _session = controller as internal.TerminalSession {
    _session.terminal.addListener(_invalidate);
    _session.viewportChanges.addListener(_invalidate);
  }

  // ignore: invalid_use_of_internal_member
  final internal.TerminalSession _session;
  final native.RenderState _renderState = native.RenderState();
  List<TerminalLineHit?>? _lines;
  int? _viewportOffset;

  void _invalidate() {
    _lines = null;
    notifyListeners();
  }

  TerminalLineHit? lineAt(int row) {
    if (row < 0) return null;
    final terminal = _session.terminal;
    final offset = terminal.scrollbar.offset;
    if (_lines == null || _viewportOffset != offset) {
      _renderState.update(terminal);
      final rows = _renderState.rows;
      final cols = _renderState.cols;
      final hits = List<TerminalLineHit?>.filled(rows, null);
      // ignore: invalid_use_of_internal_member
      final logicalLines = LogicalLine.visible(
        terminal,
        rows: rows,
        cols: cols,
      );
      final cursor = _renderState.cursor;
      var lastUsedRow = cursor.viewportHasValue ? cursor.viewportY : -1;
      for (final line in logicalLines) {
        if (line.cells.isEmpty) continue;
        var first = rows;
        var last = -1;
        for (final cell in line.cells) {
          if (cell.row < first) first = cell.row;
          if (cell.row > last) last = cell.row;
        }
        if (last > lastUsedRow) lastUsedRow = last;
        final hit = TerminalLineHit(
          text: line.text,
          firstViewportRow: first,
          lastViewportRow: last,
        );
        for (var i = first; i <= last; i++) {
          hits[i] = hit;
        }
      }
      // Preserve empty lines within output, but reject unused grid padding.
      for (var i = 0; i < rows && i <= lastUsedRow; i++) {
        hits[i] ??= TerminalLineHit(
          text: '',
          firstViewportRow: i,
          lastViewportRow: i,
        );
      }
      _lines = hits;
      _viewportOffset = offset;
    }
    return row < _lines!.length ? _lines![row] : null;
  }

  @override
  void dispose() {
    _session.terminal.removeListener(_invalidate);
    _session.viewportChanges.removeListener(_invalidate);
    _renderState.dispose();
    super.dispose();
  }
}
