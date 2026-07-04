// Fork do `TerminalView` do xterm (src/terminal_view.dart) pro cockpit. Cópia
// quase literal: toda a fiação de teclado/IME/gestos/scroll/atalhos é a do xterm
// (madura, sem regressão). A ÚNICA diferença é instanciar o nosso
// [CockpitTerminalRender] (com cache de Picture por linha) em vez do
// `RenderTerminal` original — ver cockpit_terminal_render.dart.
//
// Precisamos forkar o view (e não só o render) porque o `_TerminalView` privado
// do xterm cria o `RenderTerminal` concreto lá dentro: não há ponto de injeção
// pra trocar o render mantendo o view do pacote.
//
// ignore_for_file: implementation_imports
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:xterm/src/core/buffer/cell_offset.dart';
import 'package:xterm/src/core/input/keys.dart';
import 'package:xterm/src/terminal.dart';
import 'package:xterm/src/ui/controller.dart';
import 'package:xterm/src/ui/cursor_type.dart';
import 'package:xterm/src/ui/custom_text_edit.dart';
import 'package:xterm/src/ui/input_map.dart';
import 'package:xterm/src/ui/keyboard_listener.dart';
import 'package:xterm/src/ui/keyboard_visibility.dart';
import 'package:xterm/src/ui/scroll_handler.dart';
import 'package:xterm/src/ui/shortcut/actions.dart';
import 'package:xterm/src/ui/shortcut/shortcuts.dart';
import 'package:xterm/src/ui/terminal_text_style.dart';
import 'package:xterm/src/ui/terminal_theme.dart';
import 'package:xterm/src/ui/themes.dart';

import 'cockpit_terminal_gesture.dart';
import 'cockpit_terminal_render.dart';

class CockpitTerminal extends StatefulWidget {
  const CockpitTerminal(
    this.terminal, {
    super.key,
    this.controller,
    this.theme = TerminalThemes.defaultTheme,
    this.textStyle = const TerminalStyle(),
    this.textScaler,
    this.padding,
    this.scrollController,
    this.autoResize = true,
    this.backgroundOpacity = 1,
    this.focusNode,
    this.autofocus = false,
    this.onTapUp,
    this.onSecondaryTapDown,
    this.onSecondaryTapUp,
    this.mouseCursor = SystemMouseCursors.text,
    this.keyboardType = TextInputType.emailAddress,
    this.keyboardAppearance = Brightness.dark,
    this.cursorType = TerminalCursorType.block,
    this.alwaysShowCursor = false,
    this.deleteDetection = false,
    this.shortcuts,
    this.onKeyEvent,
    this.readOnly = false,
    this.hardwareKeyboardOnly = false,
    this.simulateScroll = true,
  });

  /// The underlying terminal that this widget renders.
  final Terminal terminal;

  final TerminalController? controller;

  /// The theme to use for this terminal.
  final TerminalTheme theme;

  /// The style to use for painting characters.
  final TerminalStyle textStyle;

  final TextScaler? textScaler;

  /// Padding around the inner [Scrollable] widget.
  final EdgeInsets? padding;

  /// Scroll controller for the inner [Scrollable] widget.
  final ScrollController? scrollController;

  /// Should this widget automatically notify the underlying terminal when its
  /// size changes. [true] by default.
  final bool autoResize;

  /// Opacity of the terminal background. Set to 0 to make the terminal
  /// background transparent.
  final double backgroundOpacity;

  /// An optional focus node to use as the focus node for this widget.
  final FocusNode? focusNode;

  /// True if this widget will be selected as the initial focus when no other
  /// node in its scope is currently focused.
  final bool autofocus;

  /// Callback for when the user taps on the terminal.
  final void Function(TapUpDetails, CellOffset)? onTapUp;

  /// Function called when the user taps on the terminal with a secondary
  /// button.
  final void Function(TapDownDetails, CellOffset)? onSecondaryTapDown;

  /// Function called when the user stops holding down a secondary button.
  final void Function(TapUpDetails, CellOffset)? onSecondaryTapUp;

  /// The mouse cursor for mouse pointers that are hovering over the terminal.
  /// [SystemMouseCursors.text] by default.
  final MouseCursor mouseCursor;

  /// The type of information for which to optimize the text input control.
  /// [TextInputType.emailAddress] by default.
  final TextInputType keyboardType;

  /// The appearance of the keyboard. [Brightness.dark] by default.
  ///
  /// This setting is only honored on iOS devices.
  final Brightness keyboardAppearance;

  /// The type of cursor to use. [TerminalCursorType.block] by default.
  final TerminalCursorType cursorType;

  /// Whether to always show the cursor. This is useful for debugging.
  /// [false] by default.
  final bool alwaysShowCursor;

  /// Workaround to detect delete key for platforms and IMEs that does not
  /// emit hardware delete event. Prefered on mobile platforms. [false] by
  /// default.
  final bool deleteDetection;

  /// Shortcuts for this terminal. This has higher priority than input handler
  /// of the terminal If not provided, [defaultTerminalShortcuts] will be used.
  final Map<ShortcutActivator, Intent>? shortcuts;

  /// Keyboard event handler of the terminal. This has higher priority than
  /// [shortcuts] and input handler of the terminal.
  final FocusOnKeyEventCallback? onKeyEvent;

  /// True if no input should send to the terminal.
  final bool readOnly;

  /// True if only hardware keyboard events should be used as input. This will
  /// also prevent any on-screen keyboard to be shown.
  final bool hardwareKeyboardOnly;

  /// If true, when the terminal is in alternate buffer (for example running
  /// vim, man, etc), if the application does not declare that it can handle
  /// scrolling, the terminal will simulate scrolling by sending up/down arrow
  /// keys to the application. This is standard behavior for most terminal
  /// emulators. True by default.
  final bool simulateScroll;

  @override
  State<CockpitTerminal> createState() => CockpitTerminalState();
}

class CockpitTerminalState extends State<CockpitTerminal> {
  late FocusNode _focusNode;

  late final ShortcutManager _shortcutManager;

  final _customTextEditKey = GlobalKey<CustomTextEditState>();

  final _scrollableKey = GlobalKey<ScrollableState>();

  final _viewportKey = GlobalKey();

  String? _composingText;

  late TerminalController _controller;

  late ScrollController _scrollController;

  /// True quando a app (claude/vim) declarou mouse reporting com scroll
  /// (`MouseMode.reportScroll`): nesse caso **ela** dona o scroll, então
  /// desligamos o nosso `Scrollable` (vira `NeverScrollableScrollPhysics`) e
  /// deixamos o [TerminalPane] encaminhar o wheel pra app. Atualizado por um
  /// listener no terminal porque o mouse mode muda via sequência de escape.
  bool _appOwnsScroll = false;

  CockpitTerminalRender get renderTerminal =>
      _viewportKey.currentContext!.findRenderObject() as CockpitTerminalRender;

  @override
  void initState() {
    _focusNode = widget.focusNode ?? FocusNode();
    _controller = widget.controller ?? TerminalController();
    _scrollController = widget.scrollController ?? ScrollController();
    _shortcutManager = ShortcutManager(
      shortcuts: widget.shortcuts ?? defaultTerminalShortcuts,
    );
    _appOwnsScroll = widget.terminal.mouseMode.reportScroll;
    widget.terminal.addListener(_onTerminalMouseModeMaybeChanged);
    super.initState();
  }

  /// O mouse mode da app muda via escape (DECSET 1000/1002/1006…), processado em
  /// `terminal.write`, que notifica os listeners. Só reconstruímos quando o bit
  /// de "app dona o scroll" realmente vira — não a cada frame de output.
  void _onTerminalMouseModeMaybeChanged() {
    final owns = widget.terminal.mouseMode.reportScroll;
    if (owns != _appOwnsScroll) {
      setState(() => _appOwnsScroll = owns);
    }
  }

  @override
  void didUpdateWidget(CockpitTerminal oldWidget) {
    if (oldWidget.terminal != widget.terminal) {
      oldWidget.terminal.removeListener(_onTerminalMouseModeMaybeChanged);
      widget.terminal.addListener(_onTerminalMouseModeMaybeChanged);
      _appOwnsScroll = widget.terminal.mouseMode.reportScroll;
    }
    if (oldWidget.focusNode != widget.focusNode) {
      if (oldWidget.focusNode == null) {
        _focusNode.dispose();
      }
      _focusNode = widget.focusNode ?? FocusNode();
    }
    if (oldWidget.controller != widget.controller) {
      if (oldWidget.controller == null) {
        _controller.dispose();
      }
      _controller = widget.controller ?? TerminalController();
    }
    if (oldWidget.scrollController != widget.scrollController) {
      if (oldWidget.scrollController == null) {
        _scrollController.dispose();
      }
      _scrollController = widget.scrollController ?? ScrollController();
    }
    _shortcutManager.shortcuts = widget.shortcuts ?? defaultTerminalShortcuts;
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    widget.terminal.removeListener(_onTerminalMouseModeMaybeChanged);
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    if (widget.controller == null) {
      _controller.dispose();
    }
    if (widget.scrollController == null) {
      _scrollController.dispose();
    }
    _shortcutManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget child = Scrollable(
      key: _scrollableKey,
      controller: _scrollController,
      // App dona o scroll (claude/vim com mouse reporting) → não rolamos o nosso
      // scrollback; o wheel é encaminhado pra app pelo [TerminalPane].
      physics: _appOwnsScroll ? const NeverScrollableScrollPhysics() : null,
      viewportBuilder: (context, offset) {
        return _CockpitTerminalLeaf(
          key: _viewportKey,
          terminal: widget.terminal,
          controller: _controller,
          offset: offset,
          padding: MediaQuery.of(context).padding,
          autoResize: widget.autoResize,
          textStyle: widget.textStyle,
          textScaler: widget.textScaler ?? MediaQuery.textScalerOf(context),
          theme: widget.theme,
          focusNode: _focusNode,
          cursorType: widget.cursorType,
          alwaysShowCursor: widget.alwaysShowCursor,
          devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
          onEditableRect: _onEditableRect,
          composingText: _composingText,
        );
      },
    );

    // Quando a app dona o scroll (claude/vim com mouse reporting), o [TerminalPane]
    // é a única autoridade do wheel — ele encaminha em ambos os buffers. Nesse
    // modo NÃO montamos o TerminalScrollGestureHandler do xterm: no alt-buffer ele
    // criaria um segundo `Scrollable` (InfiniteScrollView) que disputa o mesmo
    // pointer signal com o nosso `Listener` — a disputa dos dois scrollables era o
    // que travava o scroll (e pesava no gesture arena). Fora desse modo (shell
    // normal, `less`/`man` sem mouse reporting) o handler do xterm segue ativo pra
    // rolar o scrollback / simular setas no alt-buffer.
    if (!_appOwnsScroll) {
      child = TerminalScrollGestureHandler(
        terminal: widget.terminal,
        simulateScroll: widget.simulateScroll,
        getCellOffset: (offset) => renderTerminal.getCellOffset(offset),
        getLineHeight: () => renderTerminal.lineHeight,
        child: child,
      );
    }

    if (!widget.hardwareKeyboardOnly) {
      child = CustomTextEdit(
        key: _customTextEditKey,
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        inputType: widget.keyboardType,
        keyboardAppearance: widget.keyboardAppearance,
        deleteDetection: widget.deleteDetection,
        onInsert: _onInsert,
        onDelete: () {
          _scrollToBottom();
          widget.terminal.keyInput(TerminalKey.backspace);
        },
        onComposing: _onComposing,
        onAction: (action) {
          _scrollToBottom();
          if (action == TextInputAction.done) {
            widget.terminal.keyInput(TerminalKey.enter);
          }
        },
        onKeyEvent: _handleKeyEvent,
        readOnly: widget.readOnly,
        child: child,
      );
    } else if (!widget.readOnly) {
      // Only listen for key input from a hardware keyboard.
      child = CustomKeyboardListener(
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        onInsert: _onInsert,
        onComposing: _onComposing,
        onKeyEvent: _handleKeyEvent,
        child: child,
      );
    }

    child = TerminalActions(
      terminal: widget.terminal,
      controller: _controller,
      child: child,
    );

    child = KeyboardVisibilty(onKeyboardShow: _onKeyboardShow, child: child);

    child = CockpitTerminalGestureHandler(
      terminalView: this,
      terminalController: _controller,
      onTapUp: _onTapUp,
      onTapDown: _onTapDown,
      onSecondaryTapDown: widget.onSecondaryTapDown != null
          ? _onSecondaryTapDown
          : null,
      onSecondaryTapUp: widget.onSecondaryTapUp != null
          ? _onSecondaryTapUp
          : null,
      readOnly: widget.readOnly,
      child: child,
    );

    child = MouseRegion(cursor: widget.mouseCursor, child: child);

    child = Container(
      color: widget.theme.background.withValues(
        alpha: widget.backgroundOpacity,
      ),
      padding: widget.padding,
      child: child,
    );

    return child;
  }

  void requestKeyboard() {
    _customTextEditKey.currentState?.requestKeyboard();
  }

  void closeKeyboard() {
    _customTextEditKey.currentState?.closeKeyboard();
  }

  Rect get cursorRect {
    return renderTerminal.cursorOffset & renderTerminal.cellSize;
  }

  Rect get globalCursorRect {
    return renderTerminal.localToGlobal(renderTerminal.cursorOffset) &
        renderTerminal.cellSize;
  }

  void _onTapUp(TapUpDetails details) {
    final offset = renderTerminal.getCellOffset(details.localPosition);
    widget.onTapUp?.call(details, offset);
  }

  void _onTapDown(_) {
    if (_controller.selection != null) {
      _controller.clearSelection();
    } else {
      if (!widget.hardwareKeyboardOnly) {
        _customTextEditKey.currentState?.requestKeyboard();
      } else {
        _focusNode.requestFocus();
      }
    }
  }

  void _onSecondaryTapDown(TapDownDetails details) {
    final offset = renderTerminal.getCellOffset(details.localPosition);
    widget.onSecondaryTapDown?.call(details, offset);
  }

  void _onSecondaryTapUp(TapUpDetails details) {
    final offset = renderTerminal.getCellOffset(details.localPosition);
    widget.onSecondaryTapUp?.call(details, offset);
  }

  bool get hasInputConnection {
    return _customTextEditKey.currentState?.hasInputConnection == true;
  }

  void _onInsert(String text) {
    final key = charToTerminalKey(text.trim());

    // On mobile platforms there is no guarantee that virtual keyboard will
    // generate hardware key events. So we need first try to send the key
    // as a hardware key event. If it fails, then we send it as a text input.
    final consumed = key == null ? false : widget.terminal.keyInput(key);

    if (!consumed) {
      widget.terminal.textInput(text);
    }

    _scrollToBottom();
  }

  void _onComposing(String? text) {
    setState(() => _composingText = text);
  }

  KeyEventResult _handleKeyEvent(FocusNode focusNode, KeyEvent event) {
    final resultOverride = widget.onKeyEvent?.call(focusNode, event);
    if (resultOverride != null && resultOverride != KeyEventResult.ignored) {
      return resultOverride;
    }

    // ignore: invalid_use_of_protected_member
    final shortcutResult = _shortcutManager.handleKeypress(
      focusNode.context!,
      event,
    );

    if (shortcutResult != KeyEventResult.ignored) {
      return shortcutResult;
    }

    if (event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }

    final key = keyToTerminalKey(event.logicalKey);

    if (key == null) {
      return KeyEventResult.ignored;
    }

    final handled = widget.terminal.keyInput(
      key,
      ctrl: HardwareKeyboard.instance.isControlPressed,
      alt: HardwareKeyboard.instance.isAltPressed,
      shift: HardwareKeyboard.instance.isShiftPressed,
    );

    if (handled) {
      _scrollToBottom();
    }

    return handled ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  void _onKeyboardShow() {
    if (_focusNode.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
    }
  }

  void _onEditableRect(Rect rect, Rect caretRect) {
    _customTextEditKey.currentState?.setEditableRect(rect, caretRect);
  }

  void _scrollToBottom() {
    final position = _scrollableKey.currentState?.position;
    if (position != null) {
      position.jumpTo(position.maxScrollExtent);
    }
  }
}

class _CockpitTerminalLeaf extends LeafRenderObjectWidget {
  const _CockpitTerminalLeaf({
    super.key,
    required this.terminal,
    required this.controller,
    required this.offset,
    required this.padding,
    required this.autoResize,
    required this.textStyle,
    required this.textScaler,
    required this.theme,
    required this.focusNode,
    required this.cursorType,
    required this.alwaysShowCursor,
    required this.devicePixelRatio,
    this.onEditableRect,
    this.composingText,
  });

  final Terminal terminal;

  final TerminalController controller;

  final ViewportOffset offset;

  final EdgeInsets padding;

  final bool autoResize;

  final TerminalStyle textStyle;

  final TextScaler textScaler;

  final TerminalTheme theme;

  final FocusNode focusNode;

  final TerminalCursorType cursorType;

  final bool alwaysShowCursor;

  final double devicePixelRatio;

  final EditableRectCallback? onEditableRect;

  final String? composingText;

  @override
  CockpitTerminalRender createRenderObject(BuildContext context) {
    return CockpitTerminalRender(
      terminal: terminal,
      controller: controller,
      offset: offset,
      padding: padding,
      autoResize: autoResize,
      textStyle: textStyle,
      textScaler: textScaler,
      theme: theme,
      focusNode: focusNode,
      cursorType: cursorType,
      alwaysShowCursor: alwaysShowCursor,
      devicePixelRatio: devicePixelRatio,
      onEditableRect: onEditableRect,
      composingText: composingText,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    CockpitTerminalRender renderObject,
  ) {
    renderObject
      ..terminal = terminal
      ..controller = controller
      ..offset = offset
      ..padding = padding
      ..autoResize = autoResize
      ..textStyle = textStyle
      ..textScaler = textScaler
      ..theme = theme
      ..focusNode = focusNode
      ..cursorType = cursorType
      ..alwaysShowCursor = alwaysShowCursor
      ..devicePixelRatio = devicePixelRatio
      ..onEditableRect = onEditableRect
      ..composingText = composingText;
  }
}
