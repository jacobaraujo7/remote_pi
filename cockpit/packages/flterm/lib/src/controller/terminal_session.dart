part of 'terminal_controller.dart';

typedef _TerminalSessionState = ({
  TerminalScreen activeScreen,
  MouseTracking mouseTracking,
  bool alternateScroll,
  bool cursorKeyApplication,
  bool cursorBlinking,
});

/// Owns one terminal session and its renderer-neutral behavior.
///
/// Flutter lifecycle and device events reach this implementation only after
/// view-side adapters normalize them into terminal values. Native encoders,
/// terminal selection resources, geometry commitment, and public callback
/// effects remain inside this session boundary.
@internal
final class TerminalSession extends TerminalController with ChangeNotifier {
  static const _formFeed = 0x0c;

  static final _clearScrollback = utf8.encode('\x1b[3J');
  static final _formFeedBytes = Uint8List.fromList([_formFeed]);
  static final _alreadyRestored = Future<void>.value();

  final Terminal _terminal;
  final bool _deferResize;
  final bool _preserveSnapshotColors;
  final _viewportChanges = ChangeNotifier();
  final _frameChanges = ChangeNotifier();
  var _geometryCommitDepth = 0;
  var _geometryRevision = 0;
  var _stateNotificationPending = false;
  var _viewportNotificationPending = false;
  var _frameNotificationPending = false;
  late final InputEncoder _encoder;
  late final SelectionSession _selection;
  late final TerminalSearchControllerImpl _search;

  ColorScheme _colorScheme = .dark;
  SurfaceGeometry? _committedGeometry;
  SurfaceGeometry? _deferredGeometry;
  TerminalConfig _config;
  var _disposed = false;
  var _selectionChangeDepth = 0;
  late _TerminalSessionState _state;
  ClipboardWriteCallback? _onClipboardWrite;
  ClipboardReadCallback? _onClipboardRead;
  ValueChanged<Uint8List>? _onOutput;
  VoidCallback? _onPwdChanged;
  OnResize? _onResize;
  var _pwd = '';
  var _pwdChanged = false;
  Completer<void>? _restorationCompletion;
  var _restorationState = RestorationState.none;
  Timer? _restorationWork;
  SnapshotDecoder? _snapshotDecoder;
  Object? _viewToken;
  Mods _virtualMods = const .none();

  factory TerminalSession({TerminalConfig config = const TerminalConfig()}) {
    final terminal = Terminal(cols: config.cols, rows: config.rows);
    try {
      return TerminalSession._new(terminal, config);
    } catch (_) {
      terminal.dispose();
      rethrow;
    }
  }

  factory TerminalSession.fromSnapshot(
    Uint8List bytes, {
    bool progressive = true,
    int? maxContinuationBytes,
    bool retainContinuation = false,
    bool deferResize = true,
    bool preserveSnapshotColors = true,
  }) {
    final decoder = SnapshotDecoder(
      bytes,
      maxContinuationBytes: maxContinuationBytes,
      retainContinuation: retainContinuation,
    );
    try {
      final terminal = progressive ? decoder.ready() : decoder.decode();
      try {
        final controller = TerminalSession._restored(
          terminal,
          deferResize: deferResize,
          preserveSnapshotColors: preserveSnapshotColors,
        ).._snapshotDecoder = decoder;
        controller._restorationCompletion = Completer<void>();
        controller._restorationCompletion!.future.ignore();
        if (progressive) {
          controller._restorationState = .restoring;
          controller._scheduleRestoration();
        } else {
          controller._restorationState = .complete;
          controller._releaseSnapshotDecoder();
          controller._restorationCompletion!.complete();
        }
        return controller;
      } catch (_) {
        terminal.dispose();
        rethrow;
      }
    } catch (_) {
      decoder.dispose();
      rethrow;
    }
  }

  TerminalSession._new(this._terminal, this._config)
    : _deferResize = false,
      _preserveSnapshotColors = false,
      super._() {
    _initialize(applyConfig: true);
  }

  TerminalSession._restored(
    this._terminal, {
    required this._deferResize,
    required this._preserveSnapshotColors,
  }) : _config = TerminalConfig(
         cols: _terminal.geometry.cols,
         rows: _terminal.geometry.rows,
         scrollbackMaxBytes: _terminal.scrollbackMaxBytes,
         scrollbackMaxLines: _terminal.scrollbackMaxLines,
         continuationMaxBytes: _terminal.continuationMaxBytes,
         modes: const {},
       ),
       super._() {
    _initialize(applyConfig: false);
  }

  @override
  TerminalScreen get activeScreen {
    _checkNotDisposed();
    return _state.activeScreen;
  }

  SurfaceGeometry? get committedGeometry {
    _checkNotDisposed();
    return _committedGeometry;
  }

  @override
  TerminalConfig get config {
    _checkNotDisposed();
    return _config;
  }

  @override
  set config(TerminalConfig value) {
    _checkNotDisposed();
    if (_config == value) return;
    _config = value;
    _applyModes();
    _applyTerminalOptions();
    _search.refresh();
    _wireTerminalCallbacks();
    _state = _readState();
    notifyListeners();
  }

  @override
  bool get hasSelection {
    _checkNotDisposed();
    return _selection.hasSelection;
  }

  bool get isDisposed => _disposed;

  bool get isResizeDeferred => _deferResize && _restorationState == .restoring;

  @override
  MouseTracking get mouseTracking {
    _checkNotDisposed();
    return _state.mouseTracking;
  }

  @override
  set onBell(VoidCallback? value) {
    _checkNotDisposed();
    _terminal.onBell = value;
  }

  @override
  set onClipboardRead(ClipboardReadCallback? value) {
    _checkNotDisposed();
    if (identical(_onClipboardRead, value)) return;
    _onClipboardRead = value;
    _terminal.onClipboardRead = value;
  }

  @override
  set onClipboardWrite(ClipboardWriteCallback? value) {
    _checkNotDisposed();
    if (identical(_onClipboardWrite, value)) return;
    _onClipboardWrite = value;
    _terminal.onClipboardWrite = value;
  }

  @override
  set onDesktopNotification(ValueChanged<DesktopNotification>? value) {
    _checkNotDisposed();
    _terminal.onDesktopNotification = value;
  }

  @override
  set onOutput(ValueChanged<Uint8List>? value) {
    _checkNotDisposed();
    _onOutput = value;
    _terminal.onWritePty = value;
  }

  @override
  set onProgressReport(ValueChanged<TerminalProgress>? value) {
    _checkNotDisposed();
    _terminal.onProgressReport = value;
  }

  @override
  set onPwdChanged(VoidCallback? value) {
    _checkNotDisposed();
    _onPwdChanged = value;
  }

  @override
  set onResize(OnResize? value) {
    _checkNotDisposed();
    _onResize = value;
    if (value == null || isResizeDeferred) return;

    final geometry = _committedGeometry;
    if (geometry != null) value(geometry.cols, geometry.rows);
  }

  @override
  set onTitleChanged(VoidCallback? value) {
    _checkNotDisposed();
    _terminal.onTitleChanged = value;
  }

  @override
  String get pwd {
    _checkNotDisposed();
    return _pwd;
  }

  @override
  RestorationState get restoration {
    _checkNotDisposed();
    return _restorationState;
  }

  @override
  Future<void> get restored {
    _checkNotDisposed();
    return _restorationCompletion?.future ?? _alreadyRestored;
  }

  @override
  int get scrollbackRows {
    _checkNotDisposed();
    return _terminal.scrollbackRows;
  }

  @override
  Scrollbar get scrollbar {
    _checkNotDisposed();
    return _terminal.scrollbar;
  }

  @override
  TerminalSearchController get search {
    _checkNotDisposed();
    return _search;
  }

  Terminal get terminal {
    _checkNotDisposed();
    return _terminal;
  }

  @override
  String get title {
    _checkNotDisposed();
    return _terminal.title;
  }

  @override
  int get totalRows {
    _checkNotDisposed();
    return _terminal.totalRows;
  }

  Listenable get viewportChanges {
    _checkNotDisposed();
    return _viewportChanges;
  }

  @override
  Mods get virtualMods {
    _checkNotDisposed();
    return _virtualMods;
  }

  RgbColor applyColorDefaults({
    required RgbColor foreground,
    required RgbColor background,
    required RgbColor? cursor,
    required List<RgbColor> palette,
    bool initial = false,
  }) {
    _checkNotDisposed();
    final preserve = initial && _preserveSnapshotColors;
    final effectiveBackground = preserve
        ? _terminal.background ?? background
        : background;
    _colorScheme = colorPerceivedLuminance(effectiveBackground) > 0.5
        ? .light
        : .dark;
    if (preserve) return effectiveBackground;

    _terminal
      ..foreground = foreground
      ..background = effectiveBackground
      ..cursorColor = cursor
      ..palette = palette;
    return effectiveBackground;
  }

  Object attachView() {
    _checkNotDisposed();
    if (_viewToken != null) {
      throw StateError('TerminalController already has an active view.');
    }
    final token = Object();
    _viewToken = token;
    return token;
  }

  @override
  void clear() {
    _checkNotDisposed();
    if (_state.activeScreen == .alternate) return;
    clearSelection();
    _terminal.write(_clearScrollback);
    if (_disposed) return;
    _emitOutput(_formFeedBytes);
  }

  @override
  void clearSelection() {
    _checkNotDisposed();
    _selection.clear(notify: true);
  }

  @override
  void clearVirtualMods() {
    _checkNotDisposed();
    if (_virtualMods.isEmpty) return;
    _virtualMods = const .none();
    notifyListeners();
  }

  @override
  Formatter createFormatter({
    required FormatterFormat format,
    bool unwrap = false,
    bool trim = false,
    FormatterExtra extra = const FormatterExtra(),
  }) {
    _checkNotDisposed();
    return Formatter(
      terminal: _terminal,
      format: format,
      unwrap: unwrap,
      trim: trim,
      extra: extra,
    );
  }

  SelectionInteraction createSelectionInteraction() {
    _checkNotDisposed();
    if (_viewToken == null) {
      throw StateError('TerminalController has no active view.');
    }
    final interaction = _selection.createInteraction();
    final geometry = _committedGeometry;
    if (geometry != null) _selection.updateGeometry(geometry);
    return interaction;
  }

  void detachView(Object token) {
    if (_disposed) return;
    if (!identical(_viewToken, token)) return;
    try {
      _selection.disposeInteraction();
    } finally {
      _viewToken = null;
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final wasRestoring = _restorationState == .restoring;
    if (wasRestoring) {
      _restorationState = .failed;
    }
    _releaseSnapshotDecoder();
    final completion = _restorationCompletion;
    if (wasRestoring && completion != null && !completion.isCompleted) {
      completion.completeError(
        StateError(
          'TerminalController was disposed during snapshot restoration.',
        ),
      );
    }
    _viewToken = null;
    _terminal.removeListener(_onTerminalChanged);
    _selection.disposeInteraction();
    _search.dispose();
    _viewportChanges.dispose();
    _frameChanges.dispose();
    _encoder.dispose();
    _terminal.dispose();
    super.dispose();
  }

  SurfaceGeometry? handleResize(SurfaceMeasurement measurement) {
    _checkNotDisposed();
    final geometry = SurfaceGeometry.tryFrom(measurement);
    if (geometry == null) return null;
    if (isResizeDeferred) {
      _deferredGeometry = geometry;
      final saved = _terminal.geometry;
      final inputGeometry = SurfaceGeometry.tryFrom(
        SurfaceMeasurement(
          cols: saved.cols,
          rows: saved.rows,
          cellWidth: measurement.cellWidth,
          cellHeight: measurement.cellHeight,
          paddingLeft: measurement.paddingLeft,
          paddingRight: measurement.paddingRight,
          paddingTop: measurement.paddingTop,
          paddingBottom: measurement.paddingBottom,
          devicePixelRatio: measurement.devicePixelRatio,
        ),
      );
      if (inputGeometry != null) {
        _encoder.updateGeometry(inputGeometry);
        _selection.updateGeometry(inputGeometry);
        _committedGeometry = inputGeometry;
      }
      return inputGeometry;
    }
    if (geometry == _committedGeometry) return geometry;

    final previous = _committedGeometry;
    _commitGeometry(geometry);
    if (_disposed || _committedGeometry != geometry) return _committedGeometry;
    if (previous == null ||
        previous.cols != geometry.cols ||
        previous.rows != geometry.rows) {
      _onResize?.call(geometry.cols, geometry.rows);
    }
    return _committedGeometry;
  }

  @override
  bool modeGet(TerminalMode mode) {
    _checkNotDisposed();
    return _terminal.modeGet(mode);
  }

  @override
  void modeSet(TerminalMode mode, {required bool value}) {
    _checkNotDisposed();
    _terminal.modeSet(mode, value: value);
    _publishState();
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    if (_geometryCommitDepth > 0) {
      _stateNotificationPending = true;
      return;
    }
    super.notifyListeners();
  }

  @override
  void paste(String text) {
    _checkNotDisposed();
    if (text.isEmpty) return;
    final bracketed = _terminal.modeGet(const .bracketedPaste());
    if (!_emitOutput(pasteEncode(text, bracketed: bracketed))) return;
    _scrollToBottomOnInput();
  }

  @override
  void scrollToBottom() {
    _checkNotDisposed();
    if (_state.activeScreen == .alternate) return;
    final previousOffset = _terminal.scrollbar.offset;
    _terminal.scrollToBottom();
    if (_terminal.scrollbar.offset != previousOffset) {
      _publishViewportChange();
    }
  }

  void scrollToRow(int row) {
    _checkNotDisposed();
    final previousOffset = _terminal.scrollbar.offset;
    _terminal.scrollToRow(row);
    if (_terminal.scrollbar.offset != previousOffset) {
      _publishViewportChange();
    }
  }

  @override
  void scrollToTop() {
    _checkNotDisposed();
    if (_state.activeScreen == .alternate) return;
    final previousOffset = _terminal.scrollbar.offset;
    _terminal.scrollToTop();
    if (_terminal.scrollbar.offset != previousOffset) {
      _publishViewportChange();
    }
  }

  @override
  void selectAll() {
    _checkNotDisposed();
    _selection.selectAll();
  }

  @override
  String selectedText({FormatterFormat format = .plain}) {
    _checkNotDisposed();
    return _selection.selectedText(format: format);
  }

  @override
  void selectRange({
    required Position start,
    required Position end,
    PointTag pointTag = .screen,
    bool rectangle = false,
  }) {
    _checkNotDisposed();
    _selection.selectRange(
      start: start,
      end: end,
      pointTag: pointTag,
      rectangle: rectangle,
    );
  }

  @override
  void sendKey(Key key, {Mods mods = const .none()}) {
    _sendKey(key, mods: mods);
  }

  @override
  void sendText(String text) {
    _checkNotDisposed();
    if (text.isEmpty) return;
    if (!_emitOutput(utf8.encode(text))) return;
    clearVirtualMods();
  }

  @override
  Uint8List snapshot() {
    _checkNotDisposed();
    return _terminal.encodeSnapshot();
  }

  @override
  void toggleMod(Mods mod) {
    _checkNotDisposed();
    _virtualMods = _virtualMods ^ mod;
    notifyListeners();
  }

  @override
  void write(Uint8List data) {
    _checkNotDisposed();
    _terminal.write(data);
    if (_disposed) return;
    _scrollToBottomOnOutput();
  }

  void _applyModes() {
    _checkNotDisposed();
    for (final entry in _config.modes.entries) {
      _terminal.modeSet(entry.key, value: entry.value);
    }
  }

  void _applyTerminalOptions() {
    _terminal.continuationMaxBytes = _config.continuationMaxBytes;
    _terminal.scrollbackMaxBytes = _config.scrollbackMaxBytes;
    _terminal.scrollbackMaxLines = _config.scrollbackMaxLines;
    _terminal.kittyImageStorageLimit = _config.kittyImageStorageLimit;
    _terminal.clipboardWriteMaxBytes = _config.clipboardWriteMaxBytes;
    _terminal.setApcBufferLimit(_config.apcBufferLimit);
    _terminal.setGlyphProtocol(enabled: _config.glyphProtocol);
    _terminal.defaultCursorShape = .fromValue(_config.cursorStyle.value);
    _terminal.defaultCursorBlink = _config.cursorBlink;
  }

  void _checkNotDisposed() {
    if (_disposed) throw StateError('TerminalController is disposed.');
  }

  void _commitGeometry(SurfaceGeometry geometry) {
    final revision = ++_geometryRevision;
    _geometryCommitDepth++;
    try {
      final current = _terminal.geometry;
      final gridChanged =
          current.cols != geometry.cols || current.rows != geometry.rows;
      final pixelGeometryChanged =
          current.widthPx != geometry.cols * geometry.cellWidthPx ||
          current.heightPx != geometry.rows * geometry.cellHeightPx;
      if (gridChanged || pixelGeometryChanged) {
        _terminal.resize(
          cols: geometry.cols,
          rows: geometry.rows,
          cellWidthPx: geometry.cellWidthPx,
          cellHeightPx: geometry.cellHeightPx,
        );
        if (_disposed || revision != _geometryRevision) return;
      }

      _encoder.updateGeometry(geometry);
      _selection.updateGeometry(geometry);

      _committedGeometry = geometry;
    } finally {
      _geometryCommitDepth--;
      if (_geometryCommitDepth == 0 && !_disposed) {
        _flushGeometryNotifications();
      }
    }
  }

  bool _effectiveCursorBlinking() {
    return _config.cursorBlink ?? _terminal.modeGet(const .cursorBlinking());
  }

  bool _emitOutput(Uint8List bytes) {
    if (_disposed) return false;
    _onOutput?.call(bytes);
    return !_disposed;
  }

  void _finishRestoration({Object? error, StackTrace? stackTrace}) {
    _releaseSnapshotDecoder();
    final geometry = _deferredGeometry;
    _deferredGeometry = null;
    var failure = error;
    var failureStackTrace = stackTrace;
    _restorationState = failure == null ? .complete : .failed;
    try {
      if (geometry != null) {
        try {
          _commitGeometry(geometry);
          if (!_disposed && _committedGeometry == geometry) {
            _onResize?.call(geometry.cols, geometry.rows);
          }
        } on Object catch (commitError, commitStackTrace) {
          failure ??= commitError;
          failureStackTrace ??= commitStackTrace;
        }
      }
      _restorationState = failure == null ? .complete : .failed;
      final completion = _restorationCompletion!;
      if (completion.isCompleted) return;
      if (failure != null) {
        completion.completeError(failure, failureStackTrace);
      } else {
        completion.complete();
      }
    } finally {
      if (!_disposed) _publishViewportChange();
      if (!_disposed) notifyListeners();
    }
  }

  void _flushGeometryNotifications() {
    final viewportChanged = _viewportNotificationPending;
    final frameChanged = _frameNotificationPending;
    final stateChanged = _stateNotificationPending;
    _viewportNotificationPending = false;
    _frameNotificationPending = false;
    _stateNotificationPending = false;
    if (viewportChanged) _viewportChanges.notifyListeners();
    if (viewportChanged || frameChanged) _publishFrameChange();
    if (stateChanged) notifyListeners();
  }

  void _handlePwdChanged() {
    // The terminal listener publishes the final state after the write ends.
    _pwd = _terminal.pwd;
    _pwdChanged = true;
    _onPwdChanged?.call();
  }

  TerminalSizeInfo _handleSizeQuery() {
    _checkNotDisposed();
    final geometry = _terminal.geometry;
    final committed = _committedGeometry;
    final cellWidth = geometry.cols > 0 && geometry.widthPx > 0
        ? geometry.widthPx ~/ geometry.cols
        : committed?.cellWidthPx ?? 0;
    final cellHeight = geometry.rows > 0 && geometry.heightPx > 0
        ? geometry.heightPx ~/ geometry.rows
        : committed?.cellHeightPx ?? 0;
    return TerminalSizeInfo(
      rows: geometry.rows,
      columns: geometry.cols,
      cellWidth: cellWidth,
      cellHeight: cellHeight,
    );
  }

  void _initialize({required bool applyConfig}) {
    var inputInitialized = false;
    var searchInitialized = false;
    try {
      _encoder = InputEncoder(_terminal);
      inputInitialized = true;
      _search = TerminalSearchControllerImpl(
        _terminal,
        _viewportChanges,
        () => _selectionChangeDepth == 0,
      );
      searchInitialized = true;
      _selection = SelectionSession(
        _terminal,
        notifyListeners,
        () => _selectionChangeDepth++,
        () => _selectionChangeDepth--,
      );
      installDefaultKittyPngDecoder();
      _wireTerminalCallbacks();
      if (applyConfig) {
        _applyModes();
        _applyTerminalOptions();
      }
      _pwd = _terminal.pwd;
      _state = _readState();
      _terminal.addListener(_onTerminalChanged);
    } catch (_) {
      if (searchInitialized) _search.dispose();
      if (inputInitialized) _encoder.dispose();
      _viewportChanges.dispose();
      _frameChanges.dispose();
      rethrow;
    }
  }

  void _onTerminalChanged() {
    if (_disposed) return;
    final pwdChanged = _pwdChanged;
    _pwdChanged = false;
    final previous = _state;
    var next = _readState();
    if (previous.activeScreen != next.activeScreen &&
        next.activeScreen == .primary) {
      _applyModes();
      next = _readState();
    }
    _state = next;
    if (previous.activeScreen != next.activeScreen) {
      _selection.notifyNativeSelectionChanged();
      if (_disposed) return;
    }

    if (pwdChanged || previous != next) notifyListeners();
    _publishFrameChange();
  }

  void _onTextInput() {
    if (_config.selectionClearOnTyping) clearSelection();
    _scrollToBottomOnInput();
  }

  void _publishFrameChange() {
    if (_disposed) return;
    if (_geometryCommitDepth > 0) {
      _frameNotificationPending = true;
      return;
    }
    _frameChanges.notifyListeners();
  }

  void _publishState() {
    final next = _readState();
    if (_state == next) return;
    _state = next;
    notifyListeners();
  }

  void _publishViewportChange() {
    if (_disposed) return;
    if (_geometryCommitDepth > 0) {
      _viewportNotificationPending = true;
      return;
    }
    _viewportChanges.notifyListeners();
    _publishFrameChange();
  }

  _TerminalSessionState _readState() => (
    activeScreen: _terminal.activeScreen,
    mouseTracking: _terminal.mouseTracking,
    alternateScroll: _terminal.modeGet(const .alternateScroll()),
    cursorKeyApplication: _terminal.modeGet(const .cursorKeys()),
    cursorBlinking: _effectiveCursorBlinking(),
  );

  void _releaseSnapshotDecoder() {
    _restorationWork?.cancel();
    _restorationWork = null;
    _snapshotDecoder?.dispose();
    _snapshotDecoder = null;
  }

  void _restoreHistory() {
    _restorationWork = null;
    final decoder = _snapshotDecoder!;
    SnapshotProgress? progress;
    try {
      progress = decoder.next();
    } on Object catch (error, stackTrace) {
      _finishRestoration(error: error, stackTrace: stackTrace);
      return;
    }
    if (progress == null) {
      _finishRestoration();
      return;
    }
    _scheduleRestoration();
    if (progress.rows > 0) _search.refresh();
    if (!_disposed) _publishViewportChange();
    if (!_disposed) notifyListeners();
  }

  void _scheduleRestoration() {
    _restorationWork = Timer(const Duration(milliseconds: 1), _restoreHistory);
  }

  void _scrollToBottomOnInput() {
    if (_state.activeScreen == .alternate) return;
    final policy = _config.scrollToBottom;
    if (policy == .onKeystroke || policy == .both) scrollToBottom();
  }

  void _scrollToBottomOnOutput() {
    if (_state.activeScreen == .alternate) return;
    final policy = _config.scrollToBottom;
    if (policy == .onOutput || policy == .both) scrollToBottom();
  }

  void _wireTerminalCallbacks() {
    _terminal.onColorScheme = () => _colorScheme;
    _terminal.onSize = _handleSizeQuery;
    _terminal.onPwdChanged = _handlePwdChanged;
    _terminal.onDeviceAttributes = () => _config.deviceAttributes;
    final enquiry = _config.enquiryResponse;
    _terminal.onEnquiry = enquiry.isEmpty
        ? null
        : () => .fromList(utf8.encode(enquiry));
  }
}
