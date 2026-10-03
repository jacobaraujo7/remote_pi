import 'dart:async';

import 'package:flutter/foundation.dart' hide Key;
import 'package:libghostty/libghostty.dart' hide Listenable, ValueGetter;

/// Controls search for one terminal controller.
///
/// Obtain this object from `TerminalController.search`. flterm owns the
/// underlying libghostty search and advances incremental work automatically.
/// Opening and closing search UI remains application state; [query] is null
/// until [search] receives a non-empty value and becomes null again after
/// [clear]. The owning terminal controller disposes this object; operations
/// throw [StateError] afterward.
///
/// Results are ordered newest to oldest. Returned [Selection] values contain
/// short-lived grid-reference snapshots and must not be reused after the
/// terminal changes. Obtain fresh values from this controller after each
/// notification. While flterm refreshes invalidated results, result getters
/// return empty or null values rather than stale snapshots.
///
/// ```dart
/// final search = controller.search;
/// search.search('error');
/// search.next();
/// ```
abstract interface class TerminalSearchController implements Listenable {
  /// Whether flterm is still discovering matches for [query].
  ///
  /// False when [query] is null and after the search catches up with the
  /// current terminal contents.
  bool get isSearching;

  /// All matches discovered so far, ordered newest to oldest.
  ///
  /// Empty while terminal changes are being incorporated.
  List<Selection> get matches;

  /// The current search text, or null when no search query is set.
  String? get query;

  /// The scroll policy applied by [next] and [previous].
  ///
  /// Defaults to [SearchScroll.ifNeeded].
  SearchScroll get scrollPolicy;

  /// Sets the scroll policy applied by [next] and [previous].
  set scrollPolicy(SearchScroll value);

  /// The selected match index in [matches], or null when none is selected.
  int? get selectedIndex;

  /// The selected match, or null when none is selected.
  Selection? get selectedMatch;

  /// The number of matches discovered so far on the active screen.
  ///
  /// On the primary screen this includes matches in scrollback. Returns zero
  /// while terminal changes are being incorporated.
  int get totalMatches;

  /// Matches on terminal pages that cover the current viewport.
  ///
  /// Page boundaries mean this can include matches slightly outside the
  /// visible rows. Use `TerminalViewGeometry.selectionRects` to clip them when
  /// positioning UI. Empty while terminal changes are being incorporated.
  List<Selection> get viewportMatches;

  /// Clears the query, results, and selected match.
  void clear();

  /// Selects the next older match, wrapping at the oldest match.
  ///
  /// Pending search work is completed first so navigation includes every
  /// match known for the current terminal state.
  ///
  /// ```dart
  /// controller.search
  ///   ..scrollPolicy = .ifNeeded
  ///   ..next();
  /// ```
  void next();

  /// Selects the previous newer match, wrapping at the newest match.
  ///
  /// Pending search work is completed first so navigation includes every
  /// match known for the current terminal state.
  ///
  /// ```dart
  /// controller.search
  ///   ..scrollPolicy = .none
  ///   ..previous();
  /// ```
  void previous();

  /// Starts or replaces the current search.
  ///
  /// Matching is byte-exact except that ASCII letters are case-insensitive.
  /// Resubmitting an equivalent query preserves existing results and the
  /// selected match. An empty [query] is equivalent to [clear].
  ///
  /// Visible matches refresh before the first notification, while remaining
  /// search work proceeds in bounded asynchronous steps. Listeners are
  /// notified when the query, progress, results, selection, scroll policy, or
  /// viewport changes.
  ///
  /// ```dart
  /// void onQueryChanged(String value) {
  ///   controller.search.search(value);
  /// }
  /// ```
  void search(String query);
}

@internal
final class TerminalSearchControllerImpl extends ChangeNotifier
    implements TerminalSearchController {
  final Terminal _terminal;
  final Listenable _viewportChanges;
  final ValueGetter<bool> _shouldRefreshTerminalChange;
  late final Search _search;

  Timer? _work;
  var _generation = 0;
  var _disposed = false;
  var _needsFeed = false;
  var _selecting = false;

  TerminalSearchControllerImpl(
    this._terminal,
    this._viewportChanges,
    this._shouldRefreshTerminalChange,
  ) {
    _search = Search(_terminal);
    _terminal.addListener(_handleTerminalChanged);
    _viewportChanges.addListener(_handleViewportChanged);
  }

  @override
  bool get isSearching {
    _checkNotDisposed();
    return _hasQuery && (_needsFeed || _search.status != .complete);
  }

  @override
  List<Selection> get matches {
    _checkNotDisposed();
    if (_needsFeed) return const [];
    return _search.matches;
  }

  @override
  String? get query {
    _checkNotDisposed();
    return _search.needle;
  }

  @override
  SearchScroll get scrollPolicy {
    _checkNotDisposed();
    return _search.selectScroll;
  }

  @override
  set scrollPolicy(SearchScroll value) {
    _checkNotDisposed();
    if (_search.selectScroll == value) return;
    _search.selectScroll = value;
    notifyListeners();
  }

  @override
  int? get selectedIndex {
    _checkNotDisposed();
    if (_needsFeed) return null;
    return _search.selectedIndex;
  }

  @override
  Selection? get selectedMatch {
    _checkNotDisposed();
    if (_needsFeed) return null;
    return _search.selectedMatch;
  }

  @override
  int get totalMatches {
    _checkNotDisposed();
    if (_needsFeed) return 0;
    return _search.totalMatches;
  }

  @override
  List<Selection> get viewportMatches {
    _checkNotDisposed();
    if (_needsFeed) return const [];
    return _search.viewportMatches;
  }

  bool get _hasQuery => _search.needle != null;

  @override
  void clear() {
    _checkNotDisposed();
    if (!_hasQuery) return;
    _cancelWork();
    _search.setNeedle(null);
    _needsFeed = false;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cancelWork();
    _terminal.removeListener(_handleTerminalChanged);
    _viewportChanges.removeListener(_handleViewportChanged);
    _search.dispose();
    super.dispose();
  }

  @override
  void next() => _selectMatch(_search.selectNext);

  @override
  void previous() => _selectMatch(_search.selectPrevious);

  void refresh() => _handleTerminalChanged();

  @override
  void search(String query) {
    _checkNotDisposed();
    if (query.isEmpty) {
      clear();
      return;
    }
    _cancelWork();
    _search.setNeedle(query);
    if (_search.status == .feedRequired) _search.feed();
    _needsFeed = false;
    notifyListeners();
    if (isSearching) _scheduleWork();
  }

  void _cancelWork() {
    _generation++;
    _work?.cancel();
    _work = null;
  }

  void _checkNotDisposed() {
    if (_disposed) throw StateError('TerminalSearchController is disposed.');
  }

  void _completePendingWork() {
    _cancelWork();
    _search.run();
    _needsFeed = false;
  }

  void _handleTerminalChanged() {
    if (_disposed || !_hasQuery) return;
    if (_selecting) return;
    if (!_shouldRefreshTerminalChange()) return;
    _needsFeed = true;
    notifyListeners();
    _scheduleWork();
  }

  void _handleViewportChanged() {
    if (_disposed || !_hasQuery) return;
    notifyListeners();
  }

  void _runWork(int generation) {
    _work = null;
    if (_disposed || generation != _generation || !_hasQuery) return;

    var status = _search.status;
    if (_needsFeed || status == .feedRequired) {
      _needsFeed = false;
      status = _search.feed();
    }
    if (status == .running) status = _search.tick();
    notifyListeners();
    if (status != .complete) _scheduleWork();
  }

  void _scheduleWork() {
    if (_disposed || _work != null || !_hasQuery) return;
    final generation = _generation;
    _work = Timer(Duration.zero, () => _runWork(generation));
  }

  void _selectMatch(VoidCallback select) {
    _checkNotDisposed();
    if (!_hasQuery) return;
    _completePendingWork();
    _selecting = true;
    try {
      select();
    } finally {
      _selecting = false;
    }
    notifyListeners();
  }
}
