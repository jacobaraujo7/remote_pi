part of 'terminal_controller.dart';

enum _KeyDisposition { ignored, handled, deferred }

extension on TerminalSession {
  static const _cr = 0x0d;

  static final _appCursorDown = Uint8List.fromList([0x1b, 0x4f, 0x42]);
  static final _appCursorUp = Uint8List.fromList([0x1b, 0x4f, 0x41]);
  static final _crBytes = Uint8List.fromList([_cr]);
  static final _cursorDown = Uint8List.fromList([0x1b, 0x5b, 0x42]);
  static final _cursorUp = Uint8List.fromList([0x1b, 0x5b, 0x41]);

  bool _emitKeyPress(Key key, {required Mods mods}) {
    final result = _encoder.encodeKeyPress(key, mods: mods);
    if (result.isEmpty) return false;

    _emitOutput(utf8.encode(result));
    return true;
  }

  bool _extendSelection(Key key) {
    _checkNotDisposed();
    return _selection.extend(key);
  }

  void _handleFocusChanged({required bool focused}) {
    _checkNotDisposed();
    if (!focused) clearVirtualMods();

    if (_terminal.modeGet(const TerminalMode.focusEvent())) {
      final event = focused ? FocusEvent.gained : FocusEvent.lost;
      _emitOutput(utf8.encode(event.encode()));
    }
  }

  _KeyDisposition _handleKey(KeyInput input, {required bool deferToTextInput}) {
    _checkNotDisposed();
    final encoded = _encoder.encodeKey(input);
    if (encoded.isEmpty) return input.composing ? .handled : .ignored;
    if (deferToTextInput && encoded == input.character) {
      _onTextInput();
      return .deferred;
    }

    clearVirtualMods();
    _emitOutput(utf8.encode(encoded));
    if (!isDisposed) _onTextInput();
    return .handled;
  }

  void _handleMouseEvent(MouseInput input) {
    _checkNotDisposed();
    final result = _encoder.encodeMouse(input, geometry: _committedGeometry);
    if (result.isEmpty) return;
    _emitOutput(utf8.encode(result));
  }

  void _handleTerminalScroll(ScrollInput input) {
    _checkNotDisposed();
    if (input.horizontal == 0 && input.vertical == 0) return;

    final state = _state;
    if (input.reportMouse) {
      if (state.mouseTracking == .none) return;
      _sendScrollButtons(
        input.vertical,
        negativeButton: .four,
        positiveButton: .five,
        input: input,
      );
      if (isDisposed) return;
      _sendScrollButtons(
        input.horizontal,
        negativeButton: .six,
        positiveButton: .seven,
        input: input,
      );
      return;
    }

    if (state.mouseTracking != .none ||
        state.activeScreen != .alternate ||
        !state.alternateScroll ||
        input.vertical == 0) {
      return;
    }

    final up = state.cursorKeyApplication ? _appCursorUp : _cursorUp;
    final down = state.cursorKeyApplication ? _appCursorDown : _cursorDown;
    final key = input.vertical < 0 ? up : down;
    _emitOutput(_repeatBytes(key, input.vertical.abs()));
  }

  void _handleTextCommitted(String text) {
    _checkNotDisposed();
    if (_virtualMods.isEmpty) {
      if (!_emitOutput(utf8.encode(text))) return;
      _onTextInput();
      return;
    }

    if (text.length == 1) {
      final key = keyFromCodepoint(text.codeUnitAt(0));
      if (key != null) {
        _sendKey(key, mods: const .none());
        return;
      }
    }

    if (!_emitOutput(utf8.encode(text))) return;
    clearVirtualMods();
    _onTextInput();
  }

  void _handleTextCompositionChanged({required bool active}) {
    _checkNotDisposed();
    if (active) _onTextInput();
  }

  void _handleTextDeleted(int count) {
    _checkNotDisposed();
    if (count <= 0) return;

    var emitted = false;
    for (var i = 0; i < count; i++) {
      emitted = _emitKeyPress(.backspace, mods: _virtualMods) || emitted;
      if (isDisposed) return;
    }
    if (!emitted) return;

    clearVirtualMods();
    _onTextInput();
  }

  void _handleTextNewline() {
    _checkNotDisposed();
    if (!_emitOutput(_crBytes)) return;
    clearVirtualMods();
    _onTextInput();
  }

  void _sendKey(Key key, {required Mods mods}) {
    _checkNotDisposed();
    final result = _encoder.encodeKeyPress(key, mods: mods | _virtualMods);
    if (result.isEmpty) return;
    if (!_emitOutput(utf8.encode(result))) return;
    clearVirtualMods();
  }

  void _sendScrollButtons(
    int steps, {
    required MouseButton negativeButton,
    required MouseButton positiveButton,
    required ScrollInput input,
  }) {
    if (steps == 0) return;
    final button = steps < 0 ? negativeButton : positiveButton;
    final result = _encoder.encodeScrollButton(
      input,
      button: button,
      geometry: _committedGeometry,
    );
    if (result.isEmpty) return;
    _emitOutput(_repeatBytes(utf8.encode(result), steps.abs()));
  }

  static Uint8List _repeatBytes(List<int> value, int count) {
    final bytes = Uint8List(value.length * count);
    for (var i = 0; i < count; i++) {
      bytes.setRange(i * value.length, (i + 1) * value.length, value);
    }
    return bytes;
  }
}
