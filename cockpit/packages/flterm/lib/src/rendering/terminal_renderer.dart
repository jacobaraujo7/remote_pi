import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart'
    show
        MouseCursor,
        MouseTrackerAnnotation,
        PointerEnterEventListener,
        PointerExitEventListener,
        SystemMouseCursors;
import 'package:flutter/widgets.dart';
import 'package:libghostty/libghostty.dart' hide Listenable;
import 'package:meta/meta.dart';

import '../foundation.dart';
import '../input/text_input_session.dart' show TextInputGeometryChanged;
import '../links/link_interaction.dart';
import '../view/terminal_scroll_controller.dart';
import 'atlas_pool.dart';
import 'terminal_surface.dart';

/// Renders a terminal screen with cell backgrounds, styled text, cursors,
/// and selection overlays.
///
/// This is the core rendering widget used internally by [TerminalView].
/// It owns a [TerminalRenderBox] that orchestrates grid measurement, geometry
/// intent reporting, frame sync, and surface painting. The controller, not the
/// renderer, validates and commits resize intents to the terminal engine.
///
/// Sizing is determined by the parent constraints and cell metrics: the
/// widget computes how many columns and rows fit, then sizes itself to
/// exactly that grid. When the grid, physical cell dimensions, or surface
/// padding change, [onGeometryChanged] reports the geometry intent to the
/// owner.
///
/// ```dart
/// TerminalRenderer(
///   terminal: terminal,
///   frameChanges: frameChanges,
///   theme: TerminalTheme.dark(),
///   metrics: measureCellMetrics(fontFamily: 'monospace', fontSize: 14),
///   offset: ViewportOffset.zero(),
///   focused: true,
/// )
/// ```
@internal
final class TerminalRenderer extends LeafRenderObjectWidget {
  /// Terminal state borrowed from the owning session.
  final Terminal terminal;

  /// Publishes frame changes after the owning session updates its state.
  final Listenable frameChanges;

  /// Whether this renderer's mounted view is currently presented.
  final bool presentationActive;

  /// Search matches intersecting the viewport.
  final List<Selection> searchMatches;

  /// Search match selected by navigation, if any.
  final Selection? selectedSearchMatch;

  /// Visual style applied to the terminal.
  ///
  /// When changed, the glyph atlas is updated if font properties changed and
  /// a full repaint is scheduled. The owning view applies terminal colors.
  final TerminalTheme theme;

  /// Cell pixel dimensions used for grid sizing and coordinate conversion.
  ///
  /// When changed, layout is recalculated and a matching glyph atlas is
  /// selected. A geometry change triggers [onGeometryChanged].
  final CellMetrics metrics;

  /// Padding around the rendered terminal surface in logical pixels.
  ///
  /// This is carried to the resize callback so surface-space mouse
  /// coordinates can be converted consistently with the terminal engine's
  /// physical surface size.
  final EdgeInsets surfacePadding;

  /// Scroll offset provided by a [Scrollable] ancestor.
  ///
  /// At `pixels == 0`, the oldest scrollback row is visible.
  /// At `pixels == maxScrollExtent`, the live screen is visible.
  final ViewportOffset offset;

  /// Whether the terminal view currently has focus.
  ///
  /// The owning view supplies this value from its [FocusNode]. Changes
  /// trigger a repaint to update cursor appearance.
  final bool focused;

  /// Whether the cursor blink is currently in the visible phase.
  ///
  /// When false, the cursor and blinking text (SGR 5) are hidden.
  /// Toggled by the owning view's attachment.
  final bool blinkVisible;

  /// Whether layout preserves the terminal grid while reporting view geometry.
  final bool resizeDeferred;

  /// IME preedit text to draw at the cursor before it is committed.
  final String preeditText;

  /// Supplies link state when the render object prepares a frame.
  @internal
  final LinkInteraction? links;

  /// Whether the platform cursor is hidden while terminal input is active.
  @internal
  final bool mouseCursorHidden;

  /// Reports terminal geometry changes discovered during layout.
  ///
  /// The callback receives the complete measured geometry. The owner must
  /// apply the transaction before notifying its backend.
  final SurfaceGeometryCallback onGeometryChanged;

  /// Device pixel ratio of the Flutter view hosting this renderer.
  final double devicePixelRatio;

  /// Publishes the final render geometry to the focused platform input owner.
  @internal
  final TextInputGeometryChanged? onTextInputGeometryChanged;

  /// Internal atlas pool used to share compatible rendering state.
  final AtlasPool atlasPool;

  /// Requests a terminal viewport row derived from Flutter scroll layout.
  final ValueChanged<int> onViewportRowChanged;

  const TerminalRenderer({
    super.key,
    required this.terminal,
    required this.frameChanges,
    this.presentationActive = true,
    this.searchMatches = const [],
    this.selectedSearchMatch,
    required this.theme,
    required this.metrics,
    this.surfacePadding = EdgeInsets.zero,
    required this.offset,
    required this.focused,
    required this.atlasPool,
    this.devicePixelRatio = 1,
    this.blinkVisible = true,
    this.resizeDeferred = false,
    this.preeditText = '',
    this.links,
    this.mouseCursorHidden = false,
    required this.onGeometryChanged,
    required this.onViewportRowChanged,
    this.onTextInputGeometryChanged,
  });

  @override
  TerminalRenderBox createRenderObject(BuildContext context) {
    return TerminalRenderBox(
      theme: theme,
      offset: offset,
      metrics: metrics,
      surfacePadding: surfacePadding,
      terminal: terminal,
      frameChanges: frameChanges,
      initialPresentationActive: presentationActive,
      searchMatches: searchMatches,
      selectedSearchMatch: selectedSearchMatch,
      atlasPool: atlasPool,
      devicePixelRatio: devicePixelRatio,
      onGeometryChanged: onGeometryChanged,
      onViewportRowChanged: onViewportRowChanged,
      blinkVisible: blinkVisible,
      resizeDeferred: resizeDeferred,
      preeditText: preeditText,
      links: links,
      mouseCursorHidden: mouseCursorHidden,
      focused: focused,
      onTextInputGeometryChanged: onTextInputGeometryChanged,
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<Terminal>('terminal', terminal))
      ..add(DiagnosticsProperty<TerminalTheme>('theme', theme))
      ..add(DiagnosticsProperty<CellMetrics>('metrics', metrics))
      ..add(DiagnosticsProperty<ViewportOffset>('offset', offset))
      ..add(
        FlagProperty(
          'blinkVisible',
          value: blinkVisible,
          ifTrue: 'blink visible',
        ),
      )
      ..add(StringProperty('preeditText', preeditText, defaultValue: ''));
  }

  @override
  void updateRenderObject(
    BuildContext context,
    TerminalRenderBox renderObject,
  ) {
    renderObject
      ..terminal = terminal
      ..frameChanges = frameChanges
      ..presentationActive = presentationActive
      ..searchMatches = searchMatches
      ..selectedSearchMatch = selectedSearchMatch
      ..theme = theme
      ..atlasPool = atlasPool
      ..offset = offset
      ..metrics = metrics
      ..surfacePadding = surfacePadding
      ..devicePixelRatio = devicePixelRatio
      ..onGeometryChanged = onGeometryChanged
      ..onViewportRowChanged = onViewportRowChanged
      ..focused = focused
      ..blinkVisible = blinkVisible
      ..resizeDeferred = resizeDeferred
      ..preeditText = preeditText
      ..links = links
      ..mouseCursorHidden = mouseCursorHidden
      ..onTextInputGeometryChanged = onTextInputGeometryChanged;
  }
}

/// Render object orchestrating terminal layout, state sync, and painting.
///
/// Three phases per frame:
///
/// 1. **Layout**: computes grid size from constraints and [CellMetrics],
///    configures the glyph atlas for the current DPR, reports geometry intent
///    when measurements change, and updates scroll extents.
///
/// 2. **Sync** (start of paint): snapshots terminal cells, resolves colors
///    (including OSC 10/11 overrides, bold-is-bright, inverse, faint),
///    builds frame data for text/backgrounds/decorations, resolves
///    the cursor cell glyph, and collects Kitty graphics placements.
///
/// 3. **Paint**: delegates to [TerminalSurface], which owns painter instances,
///    Kitty image snapshots, and z-order.
///
/// Created and managed by [TerminalRenderer]. Not intended for direct use.
@internal
final class TerminalRenderBox extends RenderBox
    implements MouseTrackerAnnotation {
  late final TerminalSurface _surface;

  Terminal _terminal;
  Listenable _frameChanges;
  bool _presentationActive;
  LinkInteraction? _links;
  var _mouseCursorHidden = false;
  TextInputGeometryChanged? _onTextInputGeometryChanged;
  VoidCallback? _cancelTextInputCompositionCallback;
  late TerminalViewportCoordinator _viewport;
  SurfaceGeometryCallback _onGeometryChanged;
  ValueChanged<int> _onViewportRowChanged;
  var _performingLayout = false;

  var _surfacePadding = EdgeInsets.zero;

  TerminalRenderBox({
    required this._terminal,
    required this._frameChanges,
    bool initialPresentationActive = true,
    List<Selection> searchMatches = const [],
    Selection? selectedSearchMatch,
    required TerminalTheme theme,
    required CellMetrics metrics,
    this._surfacePadding = EdgeInsets.zero,
    required ViewportOffset offset,
    required bool focused,
    required AtlasPool atlasPool,
    required double devicePixelRatio,
    bool blinkVisible = true,
    bool resizeDeferred = false,
    LinkInteraction? links,
    bool mouseCursorHidden = false,
    String preeditText = '',
    required this._onGeometryChanged,
    required ValueChanged<int> onViewportRowChanged,
    this._onTextInputGeometryChanged,
  }) : _presentationActive = initialPresentationActive,
       _onViewportRowChanged = onViewportRowChanged {
    _viewport = TerminalViewportCoordinator.bind(offset, onViewportRowChanged);
    _links = links;
    _mouseCursorHidden = mouseCursorHidden;
    _surface = TerminalSurface(
      atlasPool: atlasPool,
      theme: theme,
      metrics: metrics,
      devicePixelRatio: devicePixelRatio,
      searchMatches: searchMatches,
      selectedSearchMatch: selectedSearchMatch,
      preeditText: preeditText,
      focused: focused,
      blinkVisible: blinkVisible,
      resizeDeferred: resizeDeferred,
      onImageReady: markNeedsPaint,
    );
  }

  set atlasPool(AtlasPool value) {
    if (_surface.updateAtlasPool(value)) _markFrameDirty();
  }

  bool get blinkVisible => _surface.blinkVisible;

  set blinkVisible(bool value) {
    if (_surface.updateBlinkVisible(visible: value)) markNeedsPaint();
  }

  @override
  MouseCursor get cursor {
    return _mouseCursorHidden || _links?.highlighted == null
        ? MouseCursor.defer
        : SystemMouseCursors.click;
  }

  @visibleForTesting
  ({int cols, int rows}) get debugGridSize =>
      (cols: _surface.cols, rows: _surface.rows);

  set devicePixelRatio(double value) {
    if (_surface.updateDevicePixelRatio(value)) markNeedsLayout();
  }

  bool get focused => _surface.focused;

  set focused(bool value) {
    if (!_surface.updateFocused(focused: value)) return;
    if (!value) {
      _cancelTextInputCompositionCallback?.call();
      _cancelTextInputCompositionCallback = null;
    }
    markNeedsPaint();
  }

  set frameChanges(Listenable value) {
    if (identical(_frameChanges, value)) return;
    if (attached) _frameChanges.removeListener(_onFrameChanged);
    _frameChanges = value;
    if (attached) _frameChanges.addListener(_onFrameChanged);
    _surface.requestTerminalSync();
    markNeedsLayout();
  }

  set presentationActive(bool value) {
    if (_presentationActive == value) return;
    _presentationActive = value;
    if (value) {
      _surface.requestTerminalSync();
      markNeedsLayout();
    }
  }

  @override
  bool get isRepaintBoundary => true;

  set links(LinkInteraction? value) {
    if (identical(_links, value)) return;
    if (attached) _links?.removeListener(_onLinksChanged);
    _links = value;
    if (attached) _links?.addListener(_onLinksChanged);
    markNeedsPaint();
  }

  set metrics(CellMetrics value) {
    if (_surface.updateMetrics(value)) markNeedsLayout();
  }

  set mouseCursorHidden(bool value) {
    if (_mouseCursorHidden == value) return;
    _mouseCursorHidden = value;
    markNeedsPaint();
  }

  set offset(ViewportOffset value) {
    if (_viewport.wraps(value)) return;
    if (attached) _viewport.offset.removeListener(_onScroll);
    _viewport.releaseBinding();
    _viewport = TerminalViewportCoordinator.bind(value, _onViewportRowChanged);
    if (attached) _viewport.offset.addListener(_onScroll);
    markNeedsLayout();
  }

  @override
  PointerEnterEventListener? get onEnter => null;

  @override
  PointerExitEventListener? get onExit => null;

  set onGeometryChanged(SurfaceGeometryCallback value) {
    _onGeometryChanged = value;
  }

  set onTextInputGeometryChanged(TextInputGeometryChanged? value) {
    if (identical(_onTextInputGeometryChanged, value)) return;
    _cancelTextInputCompositionCallback?.call();
    _cancelTextInputCompositionCallback = null;
    _onTextInputGeometryChanged = value;
    markNeedsPaint();
  }

  set onViewportRowChanged(ValueChanged<int> value) {
    _onViewportRowChanged = value;
    _viewport.onViewportRowChanged = value;
  }

  set preeditText(String value) {
    if (_surface.updatePreeditText(value)) markNeedsPaint();
  }

  set resizeDeferred(bool value) {
    if (!_surface.updateResizeDeferred(deferred: value)) return;
    markNeedsLayout();
  }

  set searchMatches(List<Selection> value) {
    if (_surface.updateSearchMatches(value)) markNeedsPaint();
  }

  set selectedSearchMatch(Selection? value) {
    if (_surface.updateSelectedSearchMatch(value)) markNeedsPaint();
  }

  set surfacePadding(EdgeInsets value) {
    if (_surfacePadding == value) return;
    _surfacePadding = value;
    markNeedsLayout();
  }

  set terminal(Terminal value) {
    if (identical(_terminal, value)) return;
    _terminal = value;
    _viewport.reset(_terminal.activeScreen);
    _surface.invalidateGeometry();
    markNeedsLayout();
  }

  /// Current terminal input caret rect in this render box's local coordinates.
  Rect get textInputCaretRect => _surface.textInputCaretRect;

  /// Current terminal composing rect in this render box's local coordinates.
  Rect get textInputComposingRect => textInputCaretRect;

  TerminalTheme get theme => _surface.theme;

  /// Updates the theme, clearing the atlas only if font properties changed.
  ///
  /// Color-only changes (palette, foreground, background) use markNeedsPaint
  /// which repaints with the existing atlas. Font changes (size, weight,
  /// family) use markNeedsLayout which reconfigures the atlas, re-measures
  /// the grid, and pre-seeds glyphs.
  set theme(TerminalTheme value) {
    if (_surface.theme == value) return;
    final fontChanged = _surface.updateTheme(value);

    if (fontChanged) {
      markNeedsLayout();
    } else {
      markNeedsPaint();
    }
  }

  @override
  bool get validForMouseTracker => attached;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _viewport.offset.addListener(_onScroll);
    _frameChanges.addListener(_onFrameChanged);
    _links?.addListener(_onLinksChanged);
    markNeedsLayout();
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(IntProperty('cols', _surface.cols))
      ..add(IntProperty('rows', _surface.rows))
      ..add(DiagnosticsProperty<TerminalTheme>('theme', _surface.theme))
      ..add(DiagnosticsProperty<CellMetrics>('metrics', _surface.metrics))
      ..add(
        FlagProperty(
          'blinkVisible',
          value: _surface.blinkVisible,
          ifTrue: 'cursor visible',
        ),
      );
  }

  @override
  void detach() {
    _cancelTextInputCompositionCallback?.call();
    _cancelTextInputCompositionCallback = null;
    _viewport.offset.removeListener(_onScroll);
    _frameChanges.removeListener(_onFrameChanged);
    _links?.removeListener(_onLinksChanged);
    super.detach();
  }

  @override
  void dispose() {
    _cancelTextInputCompositionCallback?.call();
    _cancelTextInputCompositionCallback = null;
    _surface.dispose();
    _viewport.releaseBinding();
    super.dispose();
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void paint(PaintingContext context, Offset offset) {
    final onTextInputGeometryChanged = _onTextInputGeometryChanged;
    if (onTextInputGeometryChanged != null && _surface.focused) {
      _cancelTextInputCompositionCallback ??= context.addCompositionCallback((
        _,
      ) {
        if (!attached || !hasSize || !_surface.focused) return;
        onTextInputGeometryChanged(
          editableSize: size,
          transform: getTransformTo(null),
          caretRect: _surface.textInputCaretRect,
          composingRect: _surface.textInputCaretRect,
        );
      });
    }

    final canvas = context.canvas;

    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    _surface.draw(
      canvas,
      _terminal,
      linkSnapshot: _links?.snapshot() ?? .empty,
    );
    canvas.restore();
  }

  @override
  void performLayout() {
    _performingLayout = true;
    try {
      final metrics = _surface.metrics;
      size = _surface.computeSize(constraints);
      final needsPaint = _surface.layout(
        terminal: _terminal,
        constraints: constraints,
        surfacePadding: _surfacePadding,
        onGeometryChanged: _onGeometryChanged,
      );
      final scrollbar = _terminal.scrollbar;
      _viewport.submitLayout(
        screen: _terminal.activeScreen,
        viewportRow: scrollbar.offset,
        scrollbackRows: scrollbar.total - scrollbar.visible,
        cellHeight: metrics.cellHeight,
        viewportDimension: size.height,
      );

      if (needsPaint) {
        markNeedsPaint();
      }
    } finally {
      _performingLayout = false;
    }
  }

  void _markFrameDirty() {
    _surface.requestTerminalSync();
    markNeedsPaint();
  }

  // Handles terminal change notifications.
  //
  // When scrollback length changes, a layout pass is needed because scroll
  // extents must be recalculated. For normal output (same scrollback
  // length), only a repaint is needed.
  void _onFrameChanged() {
    if (_surface.rows == 0 || _performingLayout) return;
    final scrollbar = _terminal.scrollbar;
    final scrollbackLen = scrollbar.total - scrollbar.visible;
    final needsLayout = _viewport.submitFrame(
      screen: _terminal.activeScreen,
      viewportRow: scrollbar.offset,
      scrollbackRows: scrollbackLen,
      cellHeight: _surface.metrics.cellHeight,
    );
    if (needsLayout) {
      _surface.requestTerminalSync();
      markNeedsLayout();
      return;
    }

    _markFrameDirty();
  }

  void _onLinksChanged() => markNeedsPaint();

  void _onScroll() {
    if (_performingLayout) return;
    _markFrameDirty();
  }
}
