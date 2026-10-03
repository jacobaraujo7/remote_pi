part of 'terminal_scroll_controller.dart';

/// Coordinates Flutter scrolling with the terminal's logical viewport.
///
/// This internal coordinator also adapts arbitrary [ViewportOffset] values;
/// native terminal positions reuse their existing coordinator instance.
final class TerminalViewportCoordinator extends ViewportOffset {
  final ValueSetter<double> _correctPixels;
  final ViewportOffset _source;
  final bool _adaptsSource;

  bool _applyingLayout;
  bool _applyingViewportIntent;
  double _cellHeight;
  int _engineViewportRow;
  int _lastScrollbackRows;
  ValueChanged<int>? _onViewportRowChanged;
  double? _pendingPixelCorrection;
  int? _pendingViewportRow;
  ({double logicalRow, bool stickToBottom})? _primarySnapshot;
  int _scrollbackRows;
  TerminalScreen _screen = .primary;
  bool _screenLayoutPending;
  bool _stickToBottom;

  TerminalViewportCoordinator(
    ViewportOffset source,
    ValueSetter<double> correctPixels,
  ) : this._(source, correctPixels, adaptsSource: false);

  factory TerminalViewportCoordinator.bind(
    ViewportOffset source,
    ValueChanged<int> onViewportRowChanged,
  ) {
    if (source case final _TerminalScrollPosition position) {
      position._viewport.onViewportRowChanged = onViewportRowChanged;
      return position._viewport;
    }
    final coordinator = TerminalViewportCoordinator._(
      source,
      (value) => source.correctBy(value - source.pixels),
      adaptsSource: true,
    );
    coordinator.onViewportRowChanged = onViewportRowChanged;
    return coordinator;
  }

  TerminalViewportCoordinator._(
    this._source,
    this._correctPixels, {
    required this._adaptsSource,
  }) : _applyingLayout = false,
       _applyingViewportIntent = false,
       _cellHeight = 0,
       _engineViewportRow = 0,
       _lastScrollbackRows = 0,
       _scrollbackRows = 0,
       _screenLayoutPending = false,
       _stickToBottom = true,
       super() {
    if (_adaptsSource) _source.addListener(_handleSourceChanged);
  }

  @override
  bool get allowImplicitScrolling => _source.allowImplicitScrolling;

  @override
  bool get hasPixels => _source.hasPixels;

  ViewportOffset get offset => _adaptsSource ? this : _source;

  set onViewportRowChanged(ValueChanged<int>? value) {
    _onViewportRowChanged = value;
  }

  @override
  double get pixels => _source.pixels;

  @override
  ScrollDirection get userScrollDirection => _source.userScrollDirection;

  void absorb(TerminalViewportCoordinator previous) {
    _cellHeight = previous._cellHeight;
    _engineViewportRow = previous._engineViewportRow;
    _lastScrollbackRows = previous._lastScrollbackRows;
    _pendingPixelCorrection = previous._pendingPixelCorrection;
    _pendingViewportRow = previous._pendingViewportRow;
    _primarySnapshot = previous._primarySnapshot;
    _scrollbackRows = previous._scrollbackRows;
    _screen = previous._screen;
    _screenLayoutPending = previous._screenLayoutPending;
    _stickToBottom = previous._stickToBottom;
  }

  @override
  Future<void> animateTo(
    double to, {
    required Duration duration,
    required Curve curve,
  }) => _source.animateTo(to, duration: duration, curve: curve);

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    return _source.applyContentDimensions(minScrollExtent, maxScrollExtent);
  }

  @override
  bool applyViewportDimension(double viewportDimension) {
    return _source.applyViewportDimension(viewportDimension);
  }

  @override
  void correctBy(double correction) => _source.correctBy(correction);

  void handlePixelsChanged() {
    if (_applyingLayout || _screen == .alternate || _cellHeight <= 0) return;
    if (_scrollbackRows <= 0) return;

    final maxExtent = _scrollbackRows * _cellHeight;
    final pixels = _source.pixels.clamp(0.0, maxExtent);
    _stickToBottom = maxExtent <= 0 || pixels >= maxExtent - _cellHeight;

    final targetRow = (pixels / _cellHeight).floor();
    if (targetRow == _engineViewportRow) return;
    _requestViewportRow(targetRow);
  }

  @override
  void jumpTo(double pixels) => _source.jumpTo(pixels);

  void releaseBinding() {
    if (_adaptsSource) {
      _source.removeListener(_handleSourceChanged);
      super.dispose();
    } else {
      onViewportRowChanged = null;
    }
  }

  void reset(TerminalScreen screen) {
    _cellHeight = 0;
    _engineViewportRow = 0;
    _lastScrollbackRows = 0;
    _pendingPixelCorrection = null;
    _pendingViewportRow = null;
    _primarySnapshot = null;
    _scrollbackRows = 0;
    _screen = screen;
    _screenLayoutPending = true;
    _stickToBottom = true;
    if (screen == .alternate && _source.hasPixels) _correctPixels(0);
  }

  void setScreen(TerminalScreen value) {
    if (_screen == value) return;
    if (value == .alternate) {
      if (_source.hasPixels) {
        final logicalRow = _cellHeight > 0
            ? _source.pixels / _cellHeight
            : _source.pixels;
        _primarySnapshot ??= (
          logicalRow: logicalRow,
          stickToBottom: _stickToBottom,
        );
        _correctPixels(0);
      }
      _pendingPixelCorrection = null;
      _pendingViewportRow = null;
      _stickToBottom = true;
    } else if (_cellHeight <= 0) {
      final snapshot = _primarySnapshot;
      if (snapshot != null) {
        _correctPixels(snapshot.logicalRow);
        _stickToBottom = snapshot.stickToBottom;
        _primarySnapshot = null;
      }
    }
    _screen = value;
    _screenLayoutPending = true;
  }

  bool submitFrame({
    required TerminalScreen screen,
    required int viewportRow,
    required int scrollbackRows,
    required double cellHeight,
  }) {
    final screenChanged = screen != _screen || _screenLayoutPending;
    setScreen(screen);
    _engineViewportRow = viewportRow;
    _scrollbackRows = scrollbackRows;
    _cellHeight = cellHeight;

    if (_applyingViewportIntent) return false;
    if (screen == .primary && _primarySnapshot != null) return true;

    final flutterRow = (_source.pixels / cellHeight).floor();
    final addedRows = scrollbackRows - _lastScrollbackRows;
    if (addedRows > 0 && viewportRow == flutterRow + addedRows) {
      _pendingPixelCorrection = addedRows * cellHeight;
      _pendingViewportRow = null;
      _stickToBottom = scrollbackRows <= 0 || viewportRow >= scrollbackRows;
    } else if (flutterRow != viewportRow) {
      _pendingViewportRow = viewportRow;
      _stickToBottom = scrollbackRows <= 0 || viewportRow >= scrollbackRows;
    }

    return screenChanged ||
        scrollbackRows != _lastScrollbackRows ||
        _pendingViewportRow != null;
  }

  void submitLayout({
    required TerminalScreen screen,
    required int viewportRow,
    required int scrollbackRows,
    required double cellHeight,
    required double viewportDimension,
  }) {
    setScreen(screen);
    _screenLayoutPending = false;
    _engineViewportRow = viewportRow;
    _scrollbackRows = scrollbackRows;
    _cellHeight = cellHeight;
    _applyingLayout = true;
    try {
      _source.applyViewportDimension(viewportDimension);

      if (screen == .alternate) {
        _source.applyContentDimensions(0, 0);
        _lastScrollbackRows = 0;
        return;
      }

      final effectiveViewportRow = _restorePrimarySnapshot(
        viewportRow,
        scrollbackRows,
        cellHeight,
      );

      final maxExtent = scrollbackRows * cellHeight;
      _applyCorrections(
        scrollbackRows,
        cellHeight,
        effectiveViewportRow,
        maxExtent,
      );
      _source.applyContentDimensions(0, maxExtent);
      _lastScrollbackRows = scrollbackRows;
      _stickToBottom =
          maxExtent <= 0 || _source.pixels >= maxExtent - cellHeight;
    } finally {
      _applyingLayout = false;
    }
  }

  bool wraps(ViewportOffset source) => identical(_source, source);

  void _applyCorrections(
    int scrollbackRows,
    double cellHeight,
    int effectiveViewportRow,
    double maxExtent,
  ) {
    final pendingPixelCorrection = _pendingPixelCorrection;
    _pendingPixelCorrection = null;
    if (pendingPixelCorrection != null) {
      _source.correctBy(pendingPixelCorrection);
    }

    final pendingViewportRow = _pendingViewportRow;
    _pendingViewportRow = null;
    if (pendingViewportRow != null) {
      final targetPixels =
          pendingViewportRow.clamp(0, scrollbackRows) * cellHeight;
      final correction = targetPixels - _source.pixels;
      if (correction.abs() > 0.01) _source.correctBy(correction);
    }
    if (!_stickToBottom &&
        scrollbackRows > 0 &&
        effectiveViewportRow >= scrollbackRows) {
      _stickToBottom = true;
    }
    if (_stickToBottom && maxExtent > 0) {
      final correction = maxExtent - _source.pixels;
      if (correction.abs() > 0.01) _source.correctBy(correction);
      if (effectiveViewportRow < scrollbackRows) {
        _requestViewportRow(scrollbackRows);
      }
    }
  }

  void _handleSourceChanged() {
    notifyListeners();
    handlePixelsChanged();
  }

  void _requestViewportRow(int row) {
    final callback = _onViewportRowChanged;
    if (callback == null) return;
    _applyingViewportIntent = true;
    try {
      callback(row);
      _engineViewportRow = row;
    } finally {
      _applyingViewportIntent = false;
    }
  }

  int _restorePrimarySnapshot(
    int viewportRow,
    int scrollbackRows,
    double cellHeight,
  ) {
    final snapshot = _primarySnapshot;
    if (snapshot == null) return viewportRow;

    final targetPixels = snapshot.logicalRow * cellHeight;
    final correction = targetPixels - _source.pixels;
    if (correction.abs() > 0.01) _source.correctBy(correction);
    _stickToBottom = snapshot.stickToBottom;
    _primarySnapshot = null;
    final effectiveViewportRow = snapshot.logicalRow.floor().clamp(
      0,
      scrollbackRows,
    );
    if (!_stickToBottom && effectiveViewportRow != viewportRow) {
      _requestViewportRow(effectiveViewportRow);
    }
    return effectiveViewportRow;
  }
}
