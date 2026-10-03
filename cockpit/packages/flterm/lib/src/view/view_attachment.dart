part of '../controller/terminal_controller.dart';

/// Owns one Flutter view's attachment to a terminal controller.
///
/// The attachment is the only bridge that subscribes view resources to a
/// controller. It wires focus and text input, frame invalidation, scroll-aware
/// compression, and theme reporting. Input and selection behavior belong to
/// their focused owners. Disposing the attachment releases the controller's
/// single-view lease and every view resource it created.
@internal
final class ViewAttachment extends ChangeNotifier {
  static const _space = 0x20;
  static const _delete = 0x7f;
  static const _macFunctionKeyStart = 0xF700;
  static const _macFunctionKeyEnd = 0xF8FF;
  static const _spacingAcute = 0x00B4;
  static const _combiningStart = 0x0300;
  static const _combiningEnd = 0x036F;

  final Object _viewToken;
  final ChangeNotifier _presentationFrames = ChangeNotifier();
  final links = LinkInteraction();
  final TerminalSession _controller;
  final _textInput = TextInputSession();
  late final SelectionInteraction selectionInput;
  late final CompressionScheduler _compressionScheduler;
  late final ValueNotifier<TerminalInteractionState> _interaction;

  Timer? _blinkTimer;
  Duration _blinkInterval = const CursorTheme().blinkInterval;
  var _blinkVisible = true;
  var _mouseCursorHidden = false;
  MouseAutoHide _mouseAutoHide = .onInput;
  LinkSettings _linkSettings = const .new();
  HyperlinkStyle? _idleLinkStyle;
  CellMetrics? _metrics;
  FocusNode? _focusNode;
  var _preeditText = '';
  var _wasFocused = false;
  ScrollController? _scrollController;
  var _disposed = false;
  var _presentationActive = true;

  factory ViewAttachment(TerminalController controller) =>
      ViewAttachment._(controller as TerminalSession);

  ViewAttachment._(this._controller) : _viewToken = _controller.attachView() {
    _textInput
      ..onTextCommitted = _controller._handleTextCommitted
      ..onDelete = _controller._handleTextDeleted
      ..onNewline = _controller._handleTextNewline
      ..onPreeditChanged = _handlePreeditChanged;
    selectionInput = _controller.createSelectionInteraction();
    _interaction = ValueNotifier(_readInteractionState());
    _compressionScheduler = CompressionScheduler(
      readActivity: () => terminal.compressionActivity,
      compress: terminal.compress,
    );
    _controller.addListener(_handleControllerChanged);
    _controller._frameChanges.addListener(_handleTerminalChanged);
  }

  bool get blinkVisible => _blinkVisible;

  SurfaceGeometry? get committedGeometry => _controller.committedGeometry;

  bool get cursorBlinkEnabled {
    if (!_controller._state.cursorBlinking) return false;
    if (_controller._state.activeScreen == .alternate) return true;

    final scrollController = _scrollController;
    if (scrollController == null || !scrollController.hasClients) {
      return terminal.isViewportActive;
    }
    final position = scrollController.position;
    if (!position.hasContentDimensions) return terminal.isViewportActive;
    return position.pixels >= position.maxScrollExtent - 1.0;
  }

  Listenable get frameChanges => _presentationFrames;

  /// Keep the terminal attached while withholding renderer notifications for
  /// a view that is not currently presented.
  void setPresentationActive(bool active) {
    if (_presentationActive == active) return;
    _presentationActive = active;
    if (active) _presentationFrames.notifyListeners();
  }

  ValueListenable<TerminalInteractionState> get interaction => _interaction;

  set mouseAutoHide(MouseAutoHide value) => _mouseAutoHide = value;

  MouseCursor get mouseCursor {
    if (_mouseCursorHidden) return SystemMouseCursors.none;
    return _controller.mouseTracking == .none
        ? SystemMouseCursors.text
        : SystemMouseCursors.basic;
  }

  bool get mouseCursorHidden => _mouseCursorHidden;

  String get preeditText => _preeditText;

  bool get resizeDeferred => _controller.isResizeDeferred;

  Terminal get terminal => _controller.terminal;

  Listenable get viewportChanges => _controller.viewportChanges;

  Mods get _currentMods {
    var mods = readPointerModifiers(_controller._virtualMods);
    final lockModes = HardwareKeyboard.instance.lockModesEnabled;
    if (lockModes.contains(KeyboardLockMode.capsLock)) {
      mods |= const Mods.capsLock();
    }
    if (lockModes.contains(KeyboardLockMode.numLock)) {
      mods |= const Mods.numLock();
    }
    return mods;
  }

  bool get _isDesktopPlatform {
    if (kIsWeb) return false;
    return switch (defaultTargetPlatform) {
      .linux || .macOS || .windows => true,
      .android || .fuchsia || .iOS => false,
    };
  }

  void applyTheme(TerminalTheme theme, {bool initial = false}) {
    final blinkIntervalChanged = _blinkInterval != theme.cursor.blinkInterval;
    _blinkInterval = theme.cursor.blinkInterval;
    final background = _controller.applyColorDefaults(
      foreground: _rgb(theme.foreground),
      background: _rgb(theme.background),
      cursor: theme.cursor.color?.fixedColor == null
          ? null
          : _rgb(theme.cursor.color!.fixedColor!),
      palette: [for (var i = 0; i < 256; i++) _rgb(theme.palette[i])],
      initial: initial,
    );
    final Brightness brightness = colorPerceivedLuminance(background) > 0.5
        ? .light
        : .dark;
    _textInput.keyboardAppearance = brightness;
    if (blinkIntervalChanged) _syncBlink();
  }

  void attach(
    FocusNode focusNode,
    ScrollController scrollController, {
    required int viewId,
  }) {
    _scrollController?.removeListener(_handleScrollChanged);
    _scrollController = scrollController;
    scrollController.addListener(_handleScrollChanged);
    _attachInput(focusNode, viewId: viewId);
    _syncBlink();
    if (scrollController.hasClients) _compressionScheduler.schedule();
  }

  SurfaceGeometry? commitGeometry(SurfaceMeasurement measurement) {
    final geometry = _controller.handleResize(measurement);
    if (!_disposed && !_controller.isDisposed) _syncLinks();
    return geometry;
  }

  void configureLinks({
    required LinkSettings settings,
    required HyperlinkStyle idleStyle,
    required CellMetrics metrics,
  }) {
    if (_metrics != metrics) links.cancel();
    _linkSettings = settings;
    _idleLinkStyle = idleStyle;
    _metrics = metrics;
    _syncLinks();
  }

  void detach() {
    _compressionScheduler.cancel();
    _scrollController?.removeListener(_handleScrollChanged);
    _scrollController = null;
    _detachInput();
    _syncBlink();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _blinkTimer?.cancel();
    if (!_controller.isDisposed) {
      _controller.removeListener(_handleControllerChanged);
      _controller._frameChanges.removeListener(_handleTerminalChanged);
    }
    _scrollController?.removeListener(_handleScrollChanged);
    links.dispose();
    _compressionScheduler.dispose();
    selectionInput.dispose();
    _detachInput();
    _interaction.dispose();
    _presentationFrames.dispose();
    _controller.detachView(_viewToken);
    super.dispose();
  }

  void handleHover(Offset position) {
    if (_mouseCursorHidden) {
      _mouseCursorHidden = false;
      notifyListeners();
    }
    final metrics = _metrics;
    if (metrics == null) return;
    links.handleHover(
      localPosition: position,
      metrics: metrics,
      virtualMods: readVirtualMods(),
    );
  }

  KeyEventResult handleKeyEvent(KeyEvent event) {
    if (_disposed || _controller.isDisposed) return .ignored;
    final result = _dispatchKeyEvent(event);
    if (_disposed || _controller.isDisposed) return result;
    if (result == .handled || result == .skipRemainingHandlers) {
      _syncBlink();
      if (_mouseAutoHide == .onInput && !_mouseCursorHidden) {
        _mouseCursorHidden = true;
        notifyListeners();
      }
    }
    _refreshHover();
    return result;
  }

  void handleViewportRowChanged(int row) {
    _controller.scrollToRow(row);
    _compressionScheduler.notifyActivity();
  }

  void onMouseInput(MouseInput event) {
    if (_controller.isDisposed || (_disposed && event.action != .release)) {
      return;
    }
    _controller._handleMouseEvent(event);
  }

  void onScrollInput(ScrollInput event) {
    if (_disposed || _controller.isDisposed) return;
    _controller._handleTerminalScroll(event);
  }

  Mods readVirtualMods() =>
      _controller.isDisposed ? const .none() : _controller.virtualMods;

  void requestFocus() => _focusNode?.requestFocus();

  void showKeyboard() {
    _focusNode?.requestFocus();
    if (_focusNode?.hasFocus ?? false) _textInput.show();
  }

  TextInputGeometryChanged get updateTextInputGeometry =>
      _textInput.updateGeometry;

  void _attachInput(FocusNode focusNode, {required int viewId}) {
    final previousFocusNode = _focusNode;
    final wasFocused = _wasFocused;
    previousFocusNode?.removeListener(_handleFocusChanged);
    if (previousFocusNode != null && !identical(previousFocusNode, focusNode)) {
      _textInput.detach();
    }
    _focusNode = focusNode;
    _wasFocused = focusNode.hasFocus;
    focusNode.addListener(_handleFocusChanged);
    _textInput.viewId = viewId;
    if (_wasFocused) {
      if (!wasFocused) _controller._handleFocusChanged(focused: true);
      _textInput.ensureAttached();
    }
  }

  void _detachInput() {
    if (_wasFocused && !_controller.isDisposed) {
      _controller._handleFocusChanged(focused: false);
    }
    _focusNode?.removeListener(_handleFocusChanged);
    _focusNode = null;
    _wasFocused = false;
    _preeditText = '';
    _textInput.detach();
  }

  KeyEventResult _dispatchKeyEvent(KeyEvent event) {
    final action = switch (event) {
      KeyDownEvent() => KeyAction.press,
      KeyUpEvent() => KeyAction.release,
      KeyRepeatEvent() => KeyAction.repeat,
      _ => null,
    };
    if (action == null) return .ignored;

    final key = keyFromPhysical(event.physicalKey);
    final unshiftedCodepoint = unshiftedCodepointForKey(key);
    final character = _encoderCharacter(event.character);
    final virtualMods = _controller._virtualMods;
    final mods = _currentMods;
    final physicalConsumedMods = consumedModifiersFor(
      character,
      unshiftedCodepoint: unshiftedCodepoint,
      mods: mods,
    );
    final consumedMods =
        physicalConsumedMods ^ (physicalConsumedMods & virtualMods);
    final terminalMods = consumedMods.hasCtrl ? mods ^ const Mods.ctrl() : mods;
    final composing =
        _textInput.hasActiveComposition || _preeditText.isNotEmpty;
    final input = KeyInput(
      key: key,
      action: action,
      mods: terminalMods,
      character: character,
      composing: composing,
      consumedMods: consumedMods,
      unshiftedCodepoint: unshiftedCodepoint,
    );

    if (_shouldIgnoreDeadKey(input)) return .ignored;

    if (_shouldIgnoreSuperShortcut(input)) return .ignored;

    if (_shouldForwardCompositionKey(input)) return .skipRemainingHandlers;

    final routeToTextInput = _shouldRouteToTextInput(input);
    final forwardDeletionToTextInput = _shouldForwardDeletion(input);
    if (!input.composing &&
        (input.action == .press || input.action == .repeat) &&
        input.mods.hasShift &&
        _controller._extendSelection(input.key)) {
      return .handled;
    }

    final result = _controller._handleKey(
      input,
      deferToTextInput: routeToTextInput,
    );
    return switch (result) {
      .ignored => .ignored,
      .deferred => .skipRemainingHandlers,
      .handled =>
        forwardDeletionToTextInput ? .skipRemainingHandlers : .handled,
    };
  }

  void _handleControllerChanged() {
    _interaction.value = _readInteractionState();
    if (_disposed || _controller.isDisposed) return;
    links.invalidateContent();
    _syncLinks();
    _refreshHover();
    _syncBlink();
    if (!_disposed && !_controller.isDisposed) notifyListeners();
  }

  void _handleFocusChanged() {
    final focused = _focusNode?.hasFocus ?? false;
    if (focused == _wasFocused) return;
    _wasFocused = focused;
    _controller._handleFocusChanged(focused: focused);
    if (_disposed || _controller.isDisposed) return;
    _syncBlink();
    notifyListeners();
    if (focused) {
      _textInput.ensureAttached();
    } else {
      _textInput.hide();
    }
  }

  void _handlePreeditChanged(String value) {
    if (_preeditText == value) return;
    _preeditText = value;
    _controller._handleTextCompositionChanged(active: value.isNotEmpty);
    notifyListeners();
  }

  void _handleScrollChanged() {
    links.invalidateContent();
    _syncBlink();
  }

  void _handleTerminalChanged() {
    links.invalidateContent();
    _compressionScheduler.notifyActivity();
    if (_presentationActive) _presentationFrames.notifyListeners();
  }

  TerminalInteractionState _readInteractionState() {
    final state = _controller._state;
    return TerminalInteractionState(
      activeScreen: state.activeScreen,
      mouseTracking: state.mouseTracking,
      alternateScroll: state.alternateScroll,
    );
  }

  void _refreshHover() {
    final metrics = _metrics;
    if (metrics != null) {
      links.refreshHover(metrics: metrics, virtualMods: readVirtualMods());
    }
  }

  /// Whether a printable key press is a dead key that the IME must compose.
  ///
  /// A dead key (acute, grave, tilde) fires a key-down for a printable key
  /// before the platform has composed a character, so [KeyInput.character] is
  /// null (some embedders instead deliver the bare accent, U+00B4 or a
  /// combining diacritic). Under the Kitty keyboard protocol the encoder would
  /// otherwise turn that press into an escape sequence and send it to the PTY,
  /// stealing the accent from composition. Returning it as ignored leaves the
  /// event for the text-input path so the accented character composes normally.
  ///
  /// Only unmodified presses of printable keys qualify: Enter, Tab, arrows and
  /// other non-character keys report a zero unshifted codepoint, and any
  /// Ctrl/Alt/Super combination (or an active virtual modifier) is a real
  /// terminal chord that must still be encoded.
  bool _shouldIgnoreDeadKey(KeyInput input) {
    if (!_isDesktopPlatform) return false;
    if (input.action != .press && input.action != .repeat) return false;
    if (input.unshiftedCodepoint <= 0) return false;
    if (!_controller._virtualMods.isEmpty) return false;
    final mods = input.mods;
    if (mods.hasCtrl || mods.hasAlt || mods.hasSuper) return false;
    return _isDeadKeyCharacter(input.character);
  }

  bool _isDeadKeyCharacter(String? character) {
    if (character == null) return true;
    final runes = character.runes;
    if (runes.length != 1) return false;
    final rune = runes.first;
    return rune == _spacingAcute ||
        (rune >= _combiningStart && rune <= _combiningEnd);
  }

  /// Whether a Cmd+character chord is an application shortcut the terminal
  /// must leave alone.
  ///
  /// On macOS a Cmd chord that produces a character (Cmd+`, Cmd+1, Cmd+K) is
  /// never shell input: iTerm2, Terminal.app and Ghostty only pass Cmd through
  /// when a keybinding explicitly maps it. Flutter still delivers the
  /// key-down to the focused terminal even when a global HardwareKeyboard
  /// handler already consumed it, and the encoder would then emit the bare
  /// character (legacy mode) or a CSI u sequence (Kitty) to the PTY. Returning
  /// it as ignored lets the app-level shortcut win; if nothing claims it the
  /// platform just beeps, matching native terminals.
  ///
  /// Ctrl chords (Ctrl+C, Ctrl+Cmd+...) and non-character keys (Cmd+arrows,
  /// which the encoder still emits as modified cursor sequences) are
  /// untouched.
  bool _shouldIgnoreSuperShortcut(KeyInput input) {
    if (!_isDesktopPlatform) return false;
    if (input.action != .press && input.action != .repeat) return false;
    final mods = input.mods;
    if (!mods.hasSuper || mods.hasCtrl) return false;
    return input.character != null;
  }

  bool _shouldForwardCompositionKey(KeyInput input) {
    return input.composing &&
        _textInput.isAttached &&
        _isDesktopPlatform &&
        !_shouldRouteToTextInput(input);
  }

  bool _shouldForwardDeletion(KeyInput input) {
    if (!_isDesktopPlatform || !_controller._virtualMods.isEmpty) return false;
    if (input.action != .press && input.action != .repeat) return false;
    if (input.key != .backspace && input.key != .delete) return false;
    final mods = input.mods;
    if (mods.hasShift || mods.hasCtrl || mods.hasAlt || mods.hasSuper) {
      return false;
    }
    return _textInput.consumeCommittedCompositionEdit();
  }

  bool _shouldRouteToTextInput(KeyInput input) {
    if (input.character == null || input.composing) return false;
    if (!_textInput.isAttached || !_isDesktopPlatform) return false;
    if (input.action != .press && input.action != .repeat) return false;
    if (!_controller._virtualMods.isEmpty) return false;
    final mods = input.mods;
    final consumedMods = input.consumedMods;
    return !(mods.hasCtrl && !consumedMods.hasCtrl) &&
        !(mods.hasAlt && !consumedMods.hasAlt) &&
        !mods.hasSuper;
  }

  void _syncBlink() {
    _blinkTimer?.cancel();
    if (_disposed || _controller.isDisposed) return;
    _blinkTimer = (_focusNode?.hasFocus ?? false) && cursorBlinkEnabled
        ? Timer.periodic(_blinkInterval, (_) {
            _blinkVisible = !_blinkVisible;
            notifyListeners();
          })
        : null;
    if (!_blinkVisible) {
      _blinkVisible = true;
      notifyListeners();
    }
  }

  void _syncLinks() {
    final idleStyle = _idleLinkStyle;
    if (idleStyle == null) return;
    final cwd = terminal.pwd;
    final grid = terminal.geometry;
    links.update(
      context: LinkContext(
        terminal: terminal,
        rows: grid.rows,
        cols: grid.cols,
        cwd: cwd.isEmpty ? null : cwd,
      ),
      settings: _linkSettings,
      idleStyle: idleStyle,
    );
  }

  static String? _encoderCharacter(String? character) {
    if (character == null || character.isEmpty) return null;
    final code = character.codeUnitAt(0);
    if (code < _space || code == _delete) return null;
    if (code >= _macFunctionKeyStart && code <= _macFunctionKeyEnd) return null;
    return character;
  }

  static RgbColor _rgb(Color color) => RgbColor(
    (color.r * 255).round().clamp(0, 255),
    (color.g * 255).round().clamp(0, 255),
    (color.b * 255).round().clamp(0, 255),
  );
}
