import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:libghostty/libghostty.dart' show GridRef, Position, Selection;

import '../controller/terminal_controller.dart';
import '../foundation.dart';
import '../foundation/viewport_selection.dart';
import '../input/interaction_region.dart';
import '../links/link_settings.dart';
import '../rendering.dart';
import 'shortcut_scope.dart';
import 'terminal_scope.dart';
import 'terminal_scroll_controller.dart';

part 'terminal_view_geometry.dart';

/// Displays a terminal and handles user interaction.
///
/// Pair with a [TerminalController] to create a working terminal. The
/// controller owns the terminal state; the view handles rendering,
/// scrolling, gestures, focus, and keyboard shortcuts.
///
/// Fills the available space and computes the grid dimensions (columns
/// and rows) from the font metrics and pixel area. A controller can be attached
/// to only one view at a time. The view releases that attachment when removed
/// or when [controller] changes, but it never disposes the controller.
///
/// ```dart
/// final controller = TerminalController()
///   ..onOutput = (bytes) => pty.write(bytes);
///
/// TerminalView(
///   controller: controller,
///   theme: TerminalTheme.dark(),
///   autofocus: true,
/// );
/// ```
class TerminalView extends StatefulWidget {
  /// The controller that owns the terminal instance.
  ///
  /// Can be swapped at runtime; the view releases the old controller and binds
  /// its local focus, input, scroll, and rendering adapters to the new one. The
  /// new controller must not already be attached to another [TerminalView].
  final TerminalController controller;

  /// Suspends renderer notifications while this mounted view is hidden.
  /// Reactivation synchronizes layout and paint with the current terminal.
  final bool presentationActive;

  /// Visual style. Defaults to [TerminalTheme.dark()].
  ///
  /// Changing the font family or size recalculates cell metrics and
  /// may resize the grid.
  final TerminalTheme? theme;

  /// Focus node for this terminal. Created internally when null.
  ///
  /// Supply your own to manage focus externally (e.g. for tab switching
  /// or split pane navigation).
  final FocusNode? focusNode;

  /// Whether to request focus when first inserted into the tree.
  final bool autofocus;

  /// Whether to show the soft keyboard when focus is gained.
  ///
  /// When false, focus does not request that the soft keyboard be shown.
  /// The view still attaches a platform text-input connection for text editing
  /// and IME composition while focused.
  final bool showKeyboard;

  /// When to auto-hide the mouse cursor.
  final MouseAutoHide mouseAutoHide;

  /// Controls which selection gestures are enabled and how they behave.
  final TerminalGestureSettings gestureSettings;

  /// Controls terminal link detection, styling, and activation callbacks.
  final LinkSettings linkSettings;

  /// Padding around the terminal grid.
  ///
  /// Filled with the theme background color. The grid is sized from
  /// the remaining space after padding. Mouse coordinates are translated
  /// through this inset when reported to terminal applications. Defaults to
  /// 8px on all sides.
  final EdgeInsets padding;

  /// Scroll physics for scrollback and terminal scroll gestures.
  ///
  /// The platform default is used when null. The same physics controls touch
  /// and trackpad momentum when gestures are forwarded to a terminal program.
  final ScrollPhysics? scrollPhysics;

  /// Scroll controller for programmatic scrollback access.
  ///
  /// Created internally when null.
  final TerminalScrollController? scrollController;

  /// Builds application-defined content over the complete terminal surface.
  ///
  /// The builder receives cell-aware geometry in the overlay's coordinate
  /// system. Use it for any application-defined content that belongs over the
  /// terminal, including controls, annotations, status UI, or effects.
  /// It rebuilds when the overlay constraints, search state, or terminal
  /// viewport changes. The returned subtree owns any additional state, layout,
  /// input, and semantics.
  ///
  /// ```dart
  /// overlayBuilder: (context, geometry) => Stack(
  ///   children: [
  ///     Positioned(
  ///       left: geometry.gridBounds.left,
  ///       top: geometry.gridBounds.top,
  ///       child: const TerminalStatusBadge(),
  ///     ),
  ///   ],
  /// ),
  /// ```
  final TerminalOverlayBuilder? overlayBuilder;

  /// Shortcut bindings merged over platform defaults.
  ///
  /// Defaults: Command+C/V/A/K on macOS and iOS,
  /// Control+Shift+C/V/A/K on Linux and Fuchsia, and Control+C/V/A/K on
  /// Windows and Android. Custom entries with the same activator replace the
  /// corresponding default.
  final Map<ShortcutActivator, Intent>? shortcuts;

  /// Raw TTF/OTF font file bytes for exact metric extraction.
  ///
  /// When provided, takes priority over automatic font resolution. The
  /// font's `post` and `OS/2` tables are parsed to get exact underline
  /// and strikethrough thickness and position values.
  ///
  /// When null (the default), the widget automatically resolves font
  /// data by searching asset bundles and system font directories via
  /// [FontDataResolver]. If auto-resolution also fails, heuristic
  /// fallbacks are used.
  final Uint8List? fontData;

  const TerminalView({
    super.key,
    required this.controller,
    this.presentationActive = true,
    this.theme,
    this.fontData,
    this.focusNode,
    this.shortcuts,
    this.scrollPhysics,
    this.scrollController,
    this.overlayBuilder,
    this.autofocus = false,
    this.showKeyboard = true,
    this.padding = const .all(8),
    this.mouseAutoHide = .onInput,
    this.linkSettings = const LinkSettings(),
    this.gestureSettings = const TerminalGestureSettings(),
  });

  @override
  State<TerminalView> createState() => _TerminalViewState();
}

final class _TerminalViewState extends State<TerminalView>
    with WidgetsBindingObserver {
  late ViewAttachment _attachment;
  late Listenable _overlayChanges;
  var _devicePixelRatio = 1.0;
  late FocusNode _focusNode;
  late ScrollPhysics _gestureScrollPhysics;
  late CellMetrics _metrics;
  late bool _resizeDeferred;
  Uint8List? _resolvedFontData;
  late TerminalScrollController _scrollController;
  late TerminalTheme _theme;
  var _active = true;
  int? _viewId;

  TerminalController get _controller => widget.controller;

  @override
  void activate() {
    super.activate();
    _active = true;
    WidgetsBinding.instance.addObserver(this);
    _initializeAttachment(initial: false);
    _attachment.attach(_focusNode, _scrollController, viewId: _viewId!);
  }

  @override
  Widget build(BuildContext context) {
    final surface = Builder(
      builder: (context) {
        final atlasPool = terminalScopeAtlasPoolOf(context)!;
        final viewport = ListenableBuilder(
          listenable: _attachment.interaction,
          builder: (context, _) {
            final interaction = _attachment.interaction.value;
            final scrollPhysics = interaction.activeScreen == .alternate
                ? const NeverScrollableScrollPhysics()
                : widget.scrollPhysics;
            final content = Focus(
              focusNode: _focusNode,
              autofocus: widget.autofocus,
              onFocusChange: _handleFocusChange,
              child: Scrollable(
                controller: _scrollController,
                physics: scrollPhysics,
                viewportBuilder: (_, offset) => InteractionRegion(
                  links: _attachment.links,
                  metrics: _metrics,
                  readVirtualMods: _attachment.readVirtualMods,
                  onMouseInput: _attachment.onMouseInput,
                  onScrollInput: _attachment.onScrollInput,
                  settings: widget.gestureSettings,
                  interaction: _attachment.interaction,
                  scrollPhysics: _gestureScrollPhysics,
                  selection: _attachment.selectionInput,
                  terminalBackground: _theme.background,
                  onLinkActivate: widget.linkSettings.onActivate,
                  onViewportRowChanged: _attachment.handleViewportRowChanged,
                  child: ListenableBuilder(
                    listenable: _controller.search,
                    builder: (context, _) {
                      final search = _controller.search;
                      final matches = search.viewportMatches;
                      final selected = search.selectedMatch;
                      return ListenableBuilder(
                        listenable: _attachment,
                        builder: (context, _) => TerminalRenderer(
                          theme: _theme,
                          offset: offset,
                          metrics: _metrics,
                          focused: _focusNode.hasFocus,
                          terminal: _attachment.terminal,
                          frameChanges: _attachment.frameChanges,
                          presentationActive: widget.presentationActive,
                          searchMatches: matches,
                          selectedSearchMatch: selected,
                          atlasPool: atlasPool,
                          surfacePadding: widget.padding,
                          devicePixelRatio: _devicePixelRatio,
                          preeditText: _attachment.preeditText,
                          blinkVisible: _attachment.blinkVisible,
                          resizeDeferred: _resizeDeferred,
                          links: _attachment.links,
                          mouseCursorHidden: _attachment.mouseCursorHidden,
                          onTextInputGeometryChanged:
                              _attachment.updateTextInputGeometry,
                          onGeometryChanged: _attachment.commitGeometry,
                          onViewportRowChanged:
                              _attachment.handleViewportRowChanged,
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
            return ListenableBuilder(
              listenable: _attachment,
              child: content,
              builder: (context, child) => MouseRegion(
                onHover: _handleMouseHover,
                onExit: _handleMouseExit,
                cursor: _attachment.mouseCursor,
                child: child,
              ),
            );
          },
        );
        return GestureDetector(
          behavior: .translucent,
          onTap: _attachment.requestFocus,
          child: ColoredBox(
            color: _theme.background.withValues(
              alpha: _theme.backgroundOpacity,
            ),
            child: Stack(
              fit: .expand,
              children: [
                Padding(
                  padding: widget.padding,
                  child: Focus(
                    onKeyEvent: _handleKeyEvent,
                    child: ShortcutScope(
                      onPaste: _handlePaste,
                      controller: _controller,
                      shortcuts: widget.shortcuts,
                      enableSelectAll: widget.gestureSettings.selectAllShortcut,
                      child: viewport,
                    ),
                  ),
                ),
                if (widget.overlayBuilder case final builder?)
                  Positioned.fill(
                    child: ListenableBuilder(
                      listenable: _overlayChanges,
                      builder: (context, _) => LayoutBuilder(
                        builder: (context, constraints) => builder(
                          context,
                          TerminalViewGeometry._fromConstraints(
                            metrics: _metrics,
                            padding: widget.padding,
                            constraints: constraints,
                            committed: _attachment.committedGeometry,
                            viewportOffset: _controller.scrollbar.offset,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
    return terminalScopeAtlasPoolOf(context) == null
        ? TerminalScope(child: surface)
        : surface;
  }

  @override
  void deactivate() {
    _active = false;
    WidgetsBinding.instance.removeObserver(this);
    _disposeAttachment();
    super.deactivate();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateGestureScrollPhysics();

    final viewId = View.of(context).viewId;
    if (_viewId != viewId) {
      _viewId = viewId;
      _attachment.attach(_focusNode, _scrollController, viewId: viewId);
    }

    final devicePixelRatio = View.of(context).devicePixelRatio;
    if (_devicePixelRatio == devicePixelRatio) return;
    _devicePixelRatio = devicePixelRatio;
    _metrics = _measureMetrics();
    _syncLinkInteraction();
  }

  @override
  void didChangeMetrics() {
    if (!_active) return;
    final devicePixelRatio = View.of(context).devicePixelRatio;
    if (_devicePixelRatio == devicePixelRatio) return;
    setState(() {
      _devicePixelRatio = devicePixelRatio;
      _metrics = _measureMetrics();
    });
    _syncLinkInteraction();
  }

  @override
  void didUpdateWidget(TerminalView oldWidget) {
    super.didUpdateWidget(oldWidget);

    final controllerChanged = _syncViewResources(oldWidget);
    if (controllerChanged ||
        widget.presentationActive != oldWidget.presentationActive) {
      _attachment.setPresentationActive(widget.presentationActive);
    }
    _syncAppearance(oldWidget, controllerChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_active) _disposeAttachment();
    if (widget.focusNode == null) _focusNode.dispose();
    if (widget.scrollController == null) _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _focusNode = widget.focusNode ?? FocusNode();
    _theme = widget.theme ?? TerminalTheme.dark();
    _metrics = _measureMetrics();

    if (widget.fontData == null) unawaited(_resolveFontData(_theme.fontFamily));

    _scrollController = widget.scrollController ?? TerminalScrollController();
    setTerminalScrollControllerActiveScreen(
      _scrollController,
      _controller.activeScreen,
    );
    _initializeAttachment(initial: true);
  }

  void _bindViewListenables() {
    _overlayChanges = Listenable.merge([
      _controller.search,
      _attachment.viewportChanges,
    ]);
  }

  void _disposeAttachment() {
    _attachment.removeListener(_onControllerChanged);
    _attachment.dispose();
  }

  void _handleFocusChange(bool focused) {
    if (focused && widget.showKeyboard) _attachment.showKeyboard();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) =>
      _attachment.handleKeyEvent(event);

  void _handleMouseExit(PointerExitEvent event) =>
      _attachment.links.cancelHover();

  void _handleMouseHover(PointerHoverEvent event) {
    _attachment.handleHover(event.localPosition);
  }

  Future<void> _handlePaste() async {
    final attachment = _attachment;
    final controller = _controller;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted || !identical(attachment, _attachment)) return;
    if (data?.text == null || data!.text!.isEmpty) return;
    controller.paste(data.text!);
  }

  void _initializeAttachment({required bool initial}) {
    _attachment = ViewAttachment(_controller);
    _attachment.setPresentationActive(widget.presentationActive);
    _attachment.applyTheme(_theme, initial: initial);
    _attachment.mouseAutoHide = widget.mouseAutoHide;
    _resizeDeferred = _attachment.resizeDeferred;
    _attachment.addListener(_onControllerChanged);
    _bindViewListenables();
    _syncLinkInteraction();
  }

  CellMetrics _measureMetrics({Uint8List? fontData}) {
    return measureCellMetrics(
      fontSize: _theme.fontSize,
      fontWeight: _theme.fontWeight,
      fontFamily: _theme.fontFamily,
      fontFamilyFallback: _theme.fontFamilyFallback,
      fontData: fontData ?? widget.fontData ?? _resolvedFontData,
      devicePixelRatio: _devicePixelRatio,
    );
  }

  void _onControllerChanged() {
    final resizeDeferred = _attachment.resizeDeferred;
    if (_resizeDeferred != resizeDeferred) {
      setState(() => _resizeDeferred = resizeDeferred);
    }
    final activeScreen = _controller.activeScreen;
    if (_scrollController.activeScreen != activeScreen) {
      setTerminalScrollControllerActiveScreen(_scrollController, activeScreen);
    }
  }

  /// Asynchronously resolves font data and recomputes metrics when found.
  Future<void> _resolveFontData(String fontFamily) async {
    if (!mounted ||
        widget.fontData != null ||
        _theme.fontFamily != fontFamily) {
      return;
    }
    final data = await FontDataResolver.resolve(fontFamily);
    if (data == null ||
        !mounted ||
        widget.fontData != null ||
        _theme.fontFamily != fontFamily) {
      return;
    }

    _resolvedFontData = data;
    _metrics = _measureMetrics(fontData: data);
    _syncLinkInteraction();
    setState(() {});
  }

  void _syncAppearance(TerminalView oldWidget, bool controllerChanged) {
    _attachment.mouseAutoHide = widget.mouseAutoHide;
    final oldTheme = _theme;
    final themeChanged = widget.theme != oldWidget.theme;
    if (themeChanged) {
      _theme = widget.theme ?? TerminalTheme.dark();
    }
    if (controllerChanged) {
      _attachment.applyTheme(_theme, initial: true);
    } else if (themeChanged) {
      _attachment.applyTheme(_theme);
    }

    final fontDataChanged = widget.fontData != oldWidget.fontData;
    final fontFamilyChanged = _theme.fontFamily != oldTheme.fontFamily;
    if (fontFamilyChanged) _resolvedFontData = null;

    final fontMetricsChanged =
        fontDataChanged ||
        _theme.fontSize != oldTheme.fontSize ||
        _theme.fontWeight != oldTheme.fontWeight ||
        fontFamilyChanged ||
        _theme.fontFamilyFallback != oldTheme.fontFamilyFallback;
    if (fontMetricsChanged) {
      _metrics = _measureMetrics();
    }

    if (widget.fontData == null &&
        (fontFamilyChanged || (fontDataChanged && _resolvedFontData == null))) {
      unawaited(_resolveFontData(_theme.fontFamily));
    }

    _syncLinkInteraction();
  }

  void _syncLinkInteraction() {
    _attachment.configureLinks(
      settings: widget.linkSettings,
      idleStyle: _theme.hyperlink.idle,
      metrics: _metrics,
    );
  }

  bool _syncViewResources(TerminalView oldWidget) {
    final controllerChanged = widget.controller != oldWidget.controller;
    final focusNodeChanged = widget.focusNode != oldWidget.focusNode;
    final scrollControllerChanged =
        widget.scrollController != oldWidget.scrollController;

    if (controllerChanged) {
      _attachment.removeListener(_onControllerChanged);
      _attachment.dispose();
    } else if (focusNodeChanged) {
      _attachment.detach();
    }

    if (focusNodeChanged) {
      if (oldWidget.focusNode == null) _focusNode.dispose();
      _focusNode = widget.focusNode ?? FocusNode();
    }

    if (scrollControllerChanged) {
      if (oldWidget.scrollController == null) _scrollController.dispose();
      _scrollController = widget.scrollController ?? TerminalScrollController();
    }

    if (widget.scrollPhysics != oldWidget.scrollPhysics) {
      _updateGestureScrollPhysics();
    }

    if (controllerChanged) {
      _attachment = ViewAttachment(_controller);
      _attachment.setPresentationActive(widget.presentationActive);
      _attachment.addListener(_onControllerChanged);
      _resizeDeferred = _attachment.resizeDeferred;
    }

    if (controllerChanged || focusNodeChanged || scrollControllerChanged) {
      _bindViewListenables();
      setTerminalScrollControllerActiveScreen(
        _scrollController,
        _controller.activeScreen,
      );
      _attachment.attach(_focusNode, _scrollController, viewId: _viewId!);
    }

    return controllerChanged;
  }

  void _updateGestureScrollPhysics() {
    final behavior = ScrollConfiguration.of(context);
    final defaultPhysics = behavior.getScrollPhysics(context);
    _gestureScrollPhysics =
        widget.scrollPhysics?.applyTo(defaultPhysics) ?? defaultPhysics;
  }
}
