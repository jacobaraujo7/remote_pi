import 'dart:async';
import 'dart:collection';

import 'package:cockpit/app/cockpit/domain/entities/content_search.dart';
import 'package:flutter/widgets.dart';

typedef ContentSearchFn =
    Stream<FileMatches> Function(
      String term, {
      bool caseSensitive,
      bool wholeWord,
      bool regex,
    });

/// Session-only find-in-files state. The owner binds [search] and [changes] to
/// one workspace root, never to the currently selected workspace.
class ContentSearchController extends ChangeNotifier {
  ContentSearchController({
    required this.root,
    required this.search,
    this.changes,
  }) {
    query.addListener(_onQueryChanged);
  }

  final String root;
  final ContentSearchFn search;
  final Stream<void>? changes;
  final TextEditingController query = TextEditingController();
  final List<FileMatches> _results = [];
  late final List<FileMatches> results = UnmodifiableListView(_results);
  final Set<String> _collapsed = {};
  bool isCollapsed(String path) => _collapsed.contains(path);
  bool caseSensitive = false;
  bool wholeWord = false;
  bool regex = false;
  bool searching = false;
  bool invalidRegex = false;
  double scrollOffset = 0;
  int scrollRevision = 0;
  int get totalMatches => _results.fold(0, (sum, f) => sum + f.matchCount);

  Timer? _debounce;
  StreamSubscription<FileMatches>? _subscription;
  StreamSubscription<void>? _watch;
  int _generation = 0;
  int _watchGeneration = 0;
  int _views = 0;
  bool _disposed = false;
  bool _dirty = false;
  String _term = '';

  void attach() {
    _views++;
    _startWatch();
    if (_dirty) _schedule();
  }

  void detach() {
    if (--_views == 0) {
      _stopWatch();
      _debounce?.cancel();
    }
  }

  void _startWatch() {
    if (_views == 0 || _watch != null || _term.trim().isEmpty) return;
    final generation = ++_watchGeneration;
    // watchTree is re-listenable: its first snapshot compares with the last
    // active signature, without keeping a watcher or poll alive while hidden.
    _watch = changes?.listen((_) {
      if (!_disposed && _views > 0 && generation == _watchGeneration) {
        _filesChanged();
      }
    });
  }

  void _stopWatch() {
    _watchGeneration++;
    unawaited(_watch?.cancel());
    _watch = null;
  }

  void _onQueryChanged() {
    if (_term == query.text) return; // caret/selection changes aren't searches
    _term = query.text;
    _collapsed.clear();
    scrollOffset = 0;
    scrollRevision++;
    if (_term.trim().isEmpty) {
      _stopWatch();
    } else {
      _startWatch();
    }
    _invalidate();
    _schedule();
  }

  void setOptions({bool? caseSensitive, bool? wholeWord, bool? regex}) {
    this.caseSensitive = caseSensitive ?? this.caseSensitive;
    this.wholeWord = wholeWord ?? this.wholeWord;
    this.regex = regex ?? this.regex;
    _collapsed.clear();
    scrollOffset = 0;
    scrollRevision++;
    _invalidate();
    runSearch();
  }

  void toggleCollapsed(String path) {
    if (!_collapsed.remove(path)) _collapsed.add(path);
    notifyListeners();
  }

  void _invalidate() {
    _generation++;
    _debounce?.cancel();
    unawaited(_subscription?.cancel());
    _subscription = null;
    _results.clear(); // never allow navigation using obsolete line numbers
    searching = false;
    invalidRegex = false;
    _dirty = _term.trim().isNotEmpty;
    notifyListeners();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), runSearch);
  }

  void _filesChanged() {
    if (_disposed || _term.trim().isEmpty) return;
    _invalidate();
    if (_views > 0) _schedule();
  }

  void runSearch() {
    if (_disposed) return;
    _debounce?.cancel();
    _generation++;
    final generation = _generation;
    unawaited(_subscription?.cancel());
    _subscription = null;
    _results.clear();
    invalidRegex = false;
    _dirty = false;
    searching = _term.trim().isNotEmpty;
    if (!searching) {
      _stopWatch();
      _collapsed.clear();
      scrollOffset = 0;
      notifyListeners();
      return;
    }
    // Start before the scan so modifications during a scan invalidate it too.
    _startWatch();
    notifyListeners();
    try {
      _subscription =
          search(
            _term,
            caseSensitive: caseSensitive,
            wholeWord: wholeWord,
            regex: regex,
          ).listen(
            (file) {
              if (_disposed || generation != _generation) return;
              _results.add(file);
              notifyListeners();
            },
            onError: (Object _) {
              if (_disposed || generation != _generation) return;
              invalidRegex = regex;
              searching = false;
              notifyListeners();
            },
            onDone: () {
              if (_disposed || generation != _generation) return;
              searching = false;
              notifyListeners();
            },
          );
    } on Object {
      invalidRegex = regex;
      searching = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _debounce?.cancel();
    unawaited(_subscription?.cancel());
    _stopWatch();
    query.dispose();
    super.dispose();
  }
}
