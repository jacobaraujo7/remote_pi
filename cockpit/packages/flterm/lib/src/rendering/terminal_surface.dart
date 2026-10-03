import 'dart:ui';

import 'package:flutter/foundation.dart' show VoidCallback, listEquals;
import 'package:flutter/rendering.dart' show BoxConstraints;
import 'package:flutter/widgets.dart' show EdgeInsets;
import 'package:libghostty/libghostty.dart' hide VoidCallback;

import '../foundation.dart';
import '../links/link_snapshot.dart';
import 'atlas/atlas.dart';
import 'atlas/sprite_buffer.dart';
import 'atlas_pool.dart';
import 'frame_builder.dart';
import 'kitty_image_cache.dart';
import 'kitty_placement_cache.dart';
import 'paint_state.dart';
import 'painters/background_painter.dart';
import 'painters/cursor_painter.dart';
import 'painters/decoration_painter.dart';
import 'painters/emoji_painter.dart';
import 'painters/kitty_graphics_painter.dart';
import 'painters/shaped_run_painter.dart';
import 'painters/sprite_painter.dart';
import 'painters/terminal_text_painter.dart';
import 'painters/underline_painter.dart';

typedef SurfaceGeometryCallback =
    SurfaceGeometry? Function(SurfaceMeasurement measurement);

/// Owns the mutable render state and resources for one terminal surface.
///
/// The render box supplies Flutter lifecycle signals and terminal frame
/// notifications. This class keeps all paint-state mutations, invalidation,
/// atlas rebinding, frame preparation, and painter resources together.
final class TerminalSurface {
  late AtlasPool _atlasPool;
  late AtlasLease _atlasLease;
  final PaintState _state;
  final SpriteBuffer _sprites;
  final KittyImageCache _kittyImageCache;
  final List<KittyPlacementSnapshot> _kittyBelowBackground = [];
  final List<KittyPlacementSnapshot> _kittyBelowText = [];
  final List<KittyPlacementSnapshot> _kittyAboveText = [];
  late final ShapedRunPainter _shapedRunPainter;
  late final BackgroundPainter _backgroundPainter;
  late final DecorationPainter _decorationPainter;
  late final KittyGraphicsPainter _kittyBelowBackgroundPainter;
  late final KittyGraphicsPainter _kittyBelowTextPainter;
  late final KittyGraphicsPainter _kittyAboveTextPainter;
  late final KittyPlacementCache _kittyPlacementCache;
  late EmojiPainter _emojiPainter;
  late SpritePainter _spritePainter;
  late CursorPainter _cursorPainter;
  late TerminalTextPainter _textPainter;
  late UnderlinePainter _underlinePainter;
  late FrameBuilder _frameBuilder;
  late List<Selection> _searchMatches;
  Selection? _selectedSearchMatch;
  late LinkSnapshot _linkSnapshot;
  late String _preeditText;
  var _lastCellHeight = 0.0;
  var _lastCellWidth = 0.0;
  var _lastDevicePixelRatio = 0.0;
  var _lastMeasuredCols = 0;
  var _lastMeasuredRows = 0;
  var _lastSurfacePadding = EdgeInsets.zero;
  var _resizeDeferred = false;
  var _submitGeometry = false;
  var _needsTerminalSync = true;
  var _searchDirty = true;
  var _disposed = false;

  TerminalSurface({
    required AtlasPool atlasPool,
    required TerminalTheme theme,
    required CellMetrics metrics,
    required double devicePixelRatio,
    List<Selection> searchMatches = const [],
    Selection? selectedSearchMatch,
    String preeditText = '',
    LinkSnapshot linkSnapshot = .empty,
    bool focused = true,
    bool blinkVisible = true,
    bool resizeDeferred = false,
    required VoidCallback onImageReady,
  }) : _state = PaintState(theme, metrics),
       _kittyImageCache = KittyImageCache(onImageReady: onImageReady),
       _sprites = SpriteBuffer() {
    _state
      ..devicePixelRatio = devicePixelRatio
      ..cursorFocused = focused
      ..blinkVisible = blinkVisible;
    _resizeDeferred = resizeDeferred;
    _atlasPool = atlasPool;
    _searchMatches = searchMatches;
    _selectedSearchMatch = selectedSearchMatch;
    _preeditText = preeditText;
    _linkSnapshot = linkSnapshot;
    _atlasLease = _atlasPool.acquireAtlas(_atlasConfig);
    final atlas = _atlasLease.atlas;
    _frameBuilder = FrameBuilder(atlas, _sprites, _state);
    _shapedRunPainter = ShapedRunPainter(_sprites.shaped);
    _backgroundPainter = BackgroundPainter(_state, _sprites);
    _decorationPainter = DecorationPainter(_sprites);
    _kittyPlacementCache = KittyPlacementCache(
      state: _state,
      images: _kittyImageCache,
    );
    _kittyBelowBackgroundPainter = KittyGraphicsPainter(
      state: _state,
      cache: _kittyImageCache,
      snapshots: _kittyBelowBackground,
    );
    _kittyBelowTextPainter = KittyGraphicsPainter(
      state: _state,
      cache: _kittyImageCache,
      snapshots: _kittyBelowText,
    );
    _kittyAboveTextPainter = KittyGraphicsPainter(
      state: _state,
      cache: _kittyImageCache,
      snapshots: _kittyAboveText,
    );
    _bindAtlas(atlas);
  }

  bool get blinkVisible => _state.blinkVisible;

  int get cols => _state.cols;

  double get devicePixelRatio => _state.devicePixelRatio;

  bool get focused => _state.cursorFocused;

  CellMetrics get metrics => _state.metrics;

  int get rows => _state.rows;

  Rect get textInputCaretRect {
    final metrics = _state.metrics;
    final rows = _state.rows;
    final cols = _state.cols;
    final cursor = _state.cursor;
    if (rows <= 0 || cols <= 0 || !cursor.viewportHasValue) {
      return Offset.zero & Size(metrics.cellWidth, metrics.cellHeight);
    }

    final row = cursor.viewportY.clamp(0, rows - 1);
    final rawCol = cursor.wideTail && cursor.viewportX > 0
        ? cursor.viewportX - 1
        : cursor.viewportX;
    final col = rawCol.clamp(0, cols - 1);
    return metrics.cellRect(Position(row: row, col: col), .zero);
  }

  TerminalTheme get theme => _state.theme;

  AtlasConfig get _atlasConfig => .fromTheme(
    theme: _state.theme,
    metrics: _state.metrics,
    devicePixelRatio: _state.devicePixelRatio,
  );

  Size computeSize(BoxConstraints constraints) {
    final maxW = constraints.hasBoundedWidth ? constraints.maxWidth : 0.0;
    final maxH = constraints.hasBoundedHeight ? constraints.maxHeight : 0.0;
    final (cols, rows) = _state.metrics.gridSize(maxW, maxH);
    return constraints.constrain(
      Size(cols * _state.metrics.cellWidth, rows * _state.metrics.cellHeight),
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _kittyImageCache.dispose();
    _frameBuilder.dispose();
    _sprites.dispose();
    _atlasLease.release();
  }

  void draw(
    Canvas canvas,
    Terminal terminal, {
    LinkSnapshot linkSnapshot = .empty,
  }) {
    if (_lastMeasuredRows <= 0 ||
        _lastMeasuredCols <= 0 ||
        _state.rows <= 0 ||
        _state.cols <= 0) {
      return;
    }
    _prepare(terminal, linkSnapshot: linkSnapshot);
    _paint(canvas);
  }

  void invalidateGeometry() {
    _submitGeometry = true;
    _needsTerminalSync = true;
  }

  bool layout({
    required Terminal terminal,
    required BoxConstraints constraints,
    required EdgeInsets surfacePadding,
    required SurfaceGeometryCallback onGeometryChanged,
  }) {
    final metrics = _state.metrics;
    final maxW = constraints.hasBoundedWidth ? constraints.maxWidth : 0.0;
    final maxH = constraints.hasBoundedHeight ? constraints.maxHeight : 0.0;
    final (measuredCols, measuredRows) = metrics.gridSize(maxW, maxH);
    final dpr = _state.devicePixelRatio;
    final atlasReconfigured = _ensureAtlas();
    final measuredGridChanged =
        measuredCols != _lastMeasuredCols || measuredRows != _lastMeasuredRows;
    final logicalMetricsChanged =
        metrics.cellWidth != _lastCellWidth ||
        metrics.cellHeight != _lastCellHeight;
    final devicePixelRatioChanged = dpr != _lastDevicePixelRatio;
    final geometryChanged =
        measuredGridChanged ||
        logicalMetricsChanged ||
        devicePixelRatioChanged ||
        surfacePadding != _lastSurfacePadding;
    final shouldSubmitGeometry = geometryChanged || _submitGeometry;
    final acceptedGeometry =
        shouldSubmitGeometry && measuredCols > 0 && measuredRows > 0
        ? onGeometryChanged(
            SurfaceMeasurement(
              cols: measuredCols,
              rows: measuredRows,
              cellWidth: metrics.cellWidth,
              cellHeight: metrics.cellHeight,
              paddingLeft: surfacePadding.left,
              paddingRight: surfacePadding.right,
              paddingTop: surfacePadding.top,
              paddingBottom: surfacePadding.bottom,
              devicePixelRatio: dpr,
            ),
          )
        : null;
    _submitGeometry = false;
    final nativeGeometry = terminal.geometry;
    final renderCols = acceptedGeometry?.cols ?? nativeGeometry.cols;
    final renderRows = acceptedGeometry?.rows ?? nativeGeometry.rows;
    final gridChanged = _updateGrid(renderRows, renderCols);
    if (geometryChanged) {
      _lastCellWidth = metrics.cellWidth;
      _lastCellHeight = metrics.cellHeight;
      _lastDevicePixelRatio = dpr;
      _lastMeasuredCols = measuredCols;
      _lastMeasuredRows = measuredRows;
    }
    _lastSurfacePadding = surfacePadding;
    final needsPaint = shouldSubmitGeometry || gridChanged || atlasReconfigured;
    if (needsPaint) _needsTerminalSync = true;
    return needsPaint;
  }

  void requestTerminalSync() => _needsTerminalSync = true;

  bool updateAtlasPool(AtlasPool value) {
    if (identical(value, _atlasPool)) return false;
    _atlasPool = value;
    _rebindAtlas(_atlasPool.acquireAtlas(_atlasConfig));
    return true;
  }

  bool updateBlinkVisible({required bool visible}) {
    if (_state.blinkVisible == visible) return false;
    _state.blinkVisible = visible;
    _frameBuilder
      ..markBlinkRowsDirty()
      ..refreshCursorGlyph();
    return true;
  }

  bool updateDevicePixelRatio(double value) {
    if (_state.devicePixelRatio == value) return false;
    _state.devicePixelRatio = value;
    return true;
  }

  bool updateFocused({required bool focused}) {
    if (_state.cursorFocused == focused) return false;
    _state.cursorFocused = focused;
    _frameBuilder.refreshCursorGlyph();
    return true;
  }

  bool updateMetrics(CellMetrics value) {
    if (_state.metrics == value) return false;
    _state.metrics = value;
    return true;
  }

  bool updatePreeditText(String value) {
    if (_preeditText == value) return false;
    _preeditText = value;
    return true;
  }

  bool updateResizeDeferred({required bool deferred}) {
    if (_resizeDeferred == deferred) return false;
    if (_resizeDeferred && !deferred) _submitGeometry = true;
    _resizeDeferred = deferred;
    return true;
  }

  bool updateSearchMatches(List<Selection> value) {
    if (identical(_searchMatches, value)) return false;
    _searchMatches = value;
    _searchDirty = true;
    return true;
  }

  bool updateSelectedSearchMatch(Selection? value) {
    if (_selectedSearchMatch == value) return false;
    _selectedSearchMatch = value;
    _searchDirty = true;
    return true;
  }

  /// Updates the theme and returns whether atlas-affecting font data changed.
  bool updateTheme(TerminalTheme value) {
    if (_state.theme == value) return false;
    final previous = _state.theme;
    final fontChanged =
        previous.fontSize != value.fontSize ||
        previous.fontWeight != value.fontWeight ||
        previous.fontFamily != value.fontFamily ||
        !listEquals(previous.fontFamilyFallback, value.fontFamilyFallback);
    _state.updateTheme(value);
    _frameBuilder.markAllRowsDirty();
    _needsTerminalSync = true;
    return fontChanged;
  }

  void _bindAtlas(Atlas atlas) {
    _textPainter = TerminalTextPainter(atlas, _sprites.wide, _sprites.regular);
    _spritePainter = SpritePainter(atlas, _sprites);
    _cursorPainter = CursorPainter(_state, atlas);
    _emojiPainter = EmojiPainter(atlas, _sprites);
    _underlinePainter = UnderlinePainter(atlas, _sprites);
  }

  /// Acquires the atlas matching the current theme, metrics, and DPR.
  ///
  /// Returns whether the atlas changed.
  bool _ensureAtlas() {
    final config = _atlasConfig;
    if (config == _atlasLease.config) return false;
    _rebindAtlas(_atlasPool.acquireAtlas(config));
    return true;
  }

  void _markLinkRowsDirty(CellRange? range) {
    if (range == null || _state.rows <= 0) return;
    final start = range.start.row.clamp(0, _state.rows);
    final end = (range.end.row + 1).clamp(0, _state.rows);
    _frameBuilder.markRowsDirty(start, end);
  }

  void _markLinkSnapshotRowsDirty(LinkSnapshot snapshot) {
    _markLinkRowsDirty(snapshot.highlighted);
    for (final match in snapshot.matches) {
      _markLinkRowsDirty(match.link.range);
    }
  }

  void _paint(Canvas canvas) {
    _kittyBelowBackgroundPainter.paint(canvas);
    _backgroundPainter.paint(canvas);
    _kittyBelowTextPainter.paint(canvas);
    _underlinePainter.paint(canvas);
    _textPainter.paint(canvas);
    _shapedRunPainter.paint(canvas);
    _spritePainter.paint(canvas);
    _cursorPainter.paint(canvas);
    _emojiPainter.paint(canvas);
    _decorationPainter.paint(canvas);
    _kittyAboveTextPainter.paint(canvas);
  }

  void _prepare(Terminal terminal, {LinkSnapshot linkSnapshot = .empty}) {
    if (_state.rows == 0) return;

    _updateLinkSnapshot(linkSnapshot);
    final terminalDirty = _needsTerminalSync;
    _needsTerminalSync = false;
    final searchDirty = _searchDirty;
    _searchDirty = false;
    _frameBuilder.sync(
      terminal,
      terminalDirty: terminalDirty,
      searchDirty: searchDirty,
      searchMatches: _searchMatches,
      selectedSearchMatch: _selectedSearchMatch,
      preeditText: _preeditText,
      linkSnapshot: _linkSnapshot,
    );
    final graphics = KittyGraphics.of(terminal);
    if (!_kittyPlacementCache.sync(graphics, geometryDirty: terminalDirty)) {
      return;
    }
    _kittyBelowBackground.clear();
    _kittyBelowText.clear();
    _kittyAboveText.clear();
    for (final snapshot in _kittyPlacementCache.snapshots) {
      if (snapshot.z >= 0) {
        _kittyAboveText.add(snapshot);
      } else if (snapshot.z < -1 << 30) {
        _kittyBelowBackground.add(snapshot);
      } else {
        _kittyBelowText.add(snapshot);
      }
    }
  }

  void _rebindAtlas(AtlasLease nextLease) {
    final previousLease = _atlasLease;
    final previousBuilder = _frameBuilder;
    _atlasLease = nextLease;
    final atlas = nextLease.atlas;
    _frameBuilder = FrameBuilder(atlas, _sprites, _state);
    if (_state.rows > 0 && _state.cols > 0) {
      _frameBuilder
        ..configure(_state.rows, _state.cols)
        ..markAllRowsDirty();
    }
    _bindAtlas(atlas);
    previousBuilder.dispose();
    previousLease.release();
    _needsTerminalSync = true;
    _searchDirty = true;
  }

  bool _updateGrid(int rows, int cols) {
    if (_state.rows == rows && _state.cols == cols) return false;
    _state
      ..rows = rows
      ..cols = cols;
    _frameBuilder
      ..configure(rows, cols)
      ..markAllRowsDirty();
    _needsTerminalSync = true;
    _searchDirty = true;
    return true;
  }

  void _updateLinkSnapshot(LinkSnapshot value) {
    if (_linkSnapshot == value) return;
    final previous = _linkSnapshot;
    _linkSnapshot = value;
    if (identical(previous.matches, value.matches)) {
      _markLinkRowsDirty(previous.highlighted);
      _markLinkRowsDirty(value.highlighted);
    } else {
      _markLinkSnapshotRowsDirty(previous);
      _markLinkSnapshotRowsDirty(value);
    }
  }
}
