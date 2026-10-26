// Named parameters bound to private fields can't use initializing formals
// (an underscore-named parameter is illegal), so the lint's suggestion doesn't
// apply to XtermTerminalFind's constructor.
// ignore_for_file: prefer_initializing_formals

import 'package:flterm/flterm.dart' as ghost;
import 'package:flutter/widgets.dart';

import 'xterm/xterm.dart' as xterm;

/// A match in the terminal buffer: [line] is the absolute buffer-line index,
/// [column] the start column, [length] the match length (in characters).
class TerminalMatch {
  const TerminalMatch(this.line, this.column, this.length);
  final int line;
  final int column;
  final int length;
}

/// Case-insensitive, non-overlapping substring search over [lines], returned
/// top-to-bottom, left-to-right. Pure and engine-independent (the xterm engine
/// drives it; ghostty has its own matcher inside flterm).
List<TerminalMatch> findTerminalMatches(List<String> lines, String query) {
  if (query.isEmpty) return const [];
  final needle = query.toLowerCase();
  final matches = <TerminalMatch>[];
  for (var y = 0; y < lines.length; y++) {
    final haystack = lines[y].toLowerCase();
    var from = 0;
    while (true) {
      final index = haystack.indexOf(needle, from);
      if (index < 0) break;
      matches.add(TerminalMatch(y, index, query.length));
      from = index + query.length;
    }
  }
  return matches;
}

/// Engine-agnostic "find in the terminal buffer" controller. [Listenable] so the
/// find bar rebuilds its "N of M" counter as matches/selection change.
abstract class TerminalFind implements Listenable {
  /// Starts or replaces the search. An empty query clears it.
  void search(String query);

  /// Selects the next match (wraps).
  void next();

  /// Selects the previous match (wraps).
  void previous();

  /// Clears the query, matches and any match highlighting.
  void clear();

  /// Total number of matches.
  int get matchCount;

  /// 1-based index of the selected match, or 0 when there is none.
  int get currentIndex;

  /// True while the engine is still discovering matches (ghostty is async).
  bool get isSearching;

  void dispose();
}

/// Ghostty/flterm find: delegates to flterm's built-in search controller, which
/// also paints matches and scrolls to the selection on its own.
class GhosttyTerminalFind extends ChangeNotifier implements TerminalFind {
  GhosttyTerminalFind(this._search) {
    _search.addListener(notifyListeners);
  }

  final ghost.TerminalSearchController _search;

  // Our own 1-based display position (0 = none). flterm's selectedIndex has
  // surprising semantics (it isn't a plain 0..N-1 into the match list and is
  // null right after search), so instead of mapping it we drive the position
  // ourselves, in lockstep with the next()/previous() we send to flterm.
  int _pos = 0;

  @override
  void search(String query) {
    _search.search(query);
    if (query.isEmpty) {
      _pos = 0;
      return;
    }
    // next() completes flterm's pending (incremental/scrollback) search before
    // selecting, so the count is final here — then reveal the first match and
    // call it position 1.
    _search.next();
    _pos = _search.totalMatches == 0 ? 0 : 1;
  }

  @override
  void next() {
    _search.next();
    final total = _search.totalMatches;
    _pos = total == 0 ? 0 : (_pos >= total ? 1 : _pos + 1);
  }

  @override
  void previous() {
    _search.previous();
    final total = _search.totalMatches;
    _pos = total == 0 ? 0 : (_pos <= 1 ? total : _pos - 1);
  }

  @override
  void clear() {
    _search.clear();
    _pos = 0;
  }

  @override
  int get matchCount => _search.totalMatches;

  @override
  int get currentIndex => _pos.clamp(0, _search.totalMatches);

  @override
  bool get isSearching => _search.isSearching;

  @override
  void dispose() {
    _search.removeListener(notifyListeners);
    super.dispose();
  }
}

/// One painted xterm match: its highlight plus the two anchors we created and
/// therefore must dispose (the highlight does not own them).
class _XtermHighlight {
  _XtermHighlight(this.highlight, this.a1, this.a2);
  final xterm.TerminalHighlight highlight;
  final xterm.CellAnchor a1;
  final xterm.CellAnchor a2;
  void dispose() {
    highlight.dispose();
    a1.dispose();
    a2.dispose();
  }
}

/// Xterm find: xterm.dart has no search, so this computes matches over the
/// buffer text, paints them with [TerminalController.highlight], and drives the
/// view's [ScrollController] to reveal the selected match.
class XtermTerminalFind extends ChangeNotifier implements TerminalFind {
  XtermTerminalFind({
    required xterm.Terminal terminal,
    required xterm.TerminalController controller,
    required ScrollController scroll,
    required Color matchColor,
    required Color currentColor,
  }) : _terminal = terminal,
       _controller = controller,
       _scroll = scroll,
       _matchColor = matchColor,
       _currentColor = currentColor;

  final xterm.Terminal _terminal;
  final xterm.TerminalController _controller;
  final ScrollController _scroll;
  final Color _matchColor;
  final Color _currentColor;

  /// Cap on painted highlights (matchCount still reports every match) — avoids
  /// thousands of anchors on a pathological query.
  static const _maxPainted = 500;

  final List<_XtermHighlight> _painted = [];
  _XtermHighlight? _current;
  List<TerminalMatch> _matches = const [];
  int _index = -1;
  String _query = '';

  @override
  int get matchCount => _matches.length;

  @override
  int get currentIndex => _index < 0 ? 0 : _index + 1;

  @override
  bool get isSearching => false;

  @override
  void search(String query) {
    _query = query;
    _recompute();
  }

  void _recompute() {
    _removeHighlights();
    _matches = findTerminalMatches(_bufferLines(), _query);
    if (_matches.isEmpty) {
      _index = -1;
      notifyListeners();
      return;
    }
    final buffer = _terminal.buffer;
    for (var i = 0; i < _matches.length && i < _maxPainted; i++) {
      _painted.add(_paint(buffer, _matches[i], _matchColor));
    }
    _index = 0;
    _selectCurrent();
  }

  @override
  void next() {
    if (_matches.isEmpty) return;
    _index = (_index + 1) % _matches.length;
    _selectCurrent();
  }

  @override
  void previous() {
    if (_matches.isEmpty) return;
    _index = (_index - 1 + _matches.length) % _matches.length;
    _selectCurrent();
  }

  void _selectCurrent() {
    _current?.dispose();
    _current = null;
    if (_index >= 0 && _index < _matches.length) {
      _current = _paint(_terminal.buffer, _matches[_index], _currentColor);
      _scrollTo(_matches[_index]);
    }
    notifyListeners();
  }

  @override
  void clear() {
    _query = '';
    _matches = const [];
    _index = -1;
    _removeHighlights();
    notifyListeners();
  }

  void _removeHighlights() {
    _current?.dispose();
    _current = null;
    for (final highlight in _painted) {
      highlight.dispose();
    }
    _painted.clear();
  }

  _XtermHighlight _paint(xterm.Buffer buffer, TerminalMatch match, Color color) {
    final a1 = buffer.createAnchor(match.column, match.line);
    final a2 = buffer.createAnchor(match.column + match.length, match.line);
    final highlight = _controller.highlight(p1: a1, p2: a2, color: color);
    return _XtermHighlight(highlight, a1, a2);
  }

  List<String> _bufferLines() {
    final lines = _terminal.buffer.lines;
    return [for (var i = 0; i < lines.length; i++) lines[i].getText()];
  }

  void _scrollTo(TerminalMatch match) {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final total = _terminal.buffer.height;
    final view = _terminal.viewHeight;
    if (total <= view || position.maxScrollExtent <= 0) return;
    // The scrollable extent spans the lines above the viewport; derive the
    // per-line pixel height from it and center the match in view.
    final lineHeight = position.maxScrollExtent / (total - view);
    final target = ((match.line - view ~/ 2) * lineHeight).clamp(
      0.0,
      position.maxScrollExtent,
    );
    _scroll.jumpTo(target);
  }

  @override
  void dispose() {
    _removeHighlights();
    super.dispose();
  }
}
