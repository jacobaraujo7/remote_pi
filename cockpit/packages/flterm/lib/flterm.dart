/// Flutter terminal renderer and widget APIs.
///
/// ```dart
/// import 'package:flterm/flterm.dart';
/// ```
library;

export 'package:libghostty/libghostty.dart'
    show
        ClipboardContent,
        ClipboardLocation,
        ClipboardReadReply,
        ClipboardReadRequest,
        ClipboardReadResult,
        ClipboardWrite,
        ClipboardWriteCallback,
        ClipboardWriteResult,
        CursorShape,
        DesktopNotification,
        DeviceAttributesResponse,
        Formatter,
        FormatterExtra,
        FormatterFormat,
        GridRef,
        Key,
        Mods,
        MouseTracking,
        PointTag,
        Position,
        Scrollbar,
        SearchScroll,
        Selection,
        SelectionGestureBehavior,
        SelectionGestureBehaviors,
        TerminalMode,
        TerminalProgress,
        TerminalProgressState,
        TerminalScreen,
        UnderlineStyle,
        initializeForWeb;

export 'src/controller/terminal_controller.dart'
    show OnResize, RestorationState, TerminalController;
export 'src/controller/terminal_search_controller.dart'
    show TerminalSearchController;
export 'src/foundation/cell_range.dart' show CellRange;
export 'src/foundation/color_palette.dart' show ColorPalette;
export 'src/foundation/dynamic_color.dart' show DynamicColor;
export 'src/foundation/input_types.dart' show MouseAutoHide;
export 'src/foundation/terminal_config.dart'
    show ScrollToBottom, TerminalConfig;
export 'src/foundation/terminal_gesture_settings.dart'
    show
        GestureModifier,
        LineSelectMode,
        TerminalGestureSettings,
        TerminalSelectionShape;
export 'src/foundation/terminal_theme.dart'
    show
        CursorTheme,
        HyperlinkStyle,
        HyperlinkTheme,
        SearchTheme,
        SelectionTheme,
        TerminalTheme;
export 'src/links/activation_modifier.dart' show ActivationModifier;
export 'src/links/link_settings.dart'
    show
        ActivatedLink,
        LinkHighlightMode,
        LinkRule,
        LinkSettings,
        LinkType,
        LinkedFile;
export 'src/view/terminal_scope.dart' show TerminalScope;
export 'src/view/terminal_scroll_controller.dart' show TerminalScrollController;
export 'src/view/terminal_view.dart'
    show TerminalOverlayBuilder, TerminalView, TerminalViewGeometry;
