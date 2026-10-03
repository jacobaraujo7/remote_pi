import 'package:flutter/foundation.dart' show immutable, mapEquals;
import 'package:libghostty/libghostty.dart';

/// When to auto-scroll the viewport to the bottom.
///
/// Controls whether new output or user input causes the terminal to jump
/// to the latest content. Set via [TerminalConfig.scrollToBottom].
enum ScrollToBottom {
  /// Scroll to bottom when the user presses a key.
  onKeystroke,

  /// Scroll to bottom when new output arrives from the terminal.
  onOutput,

  /// Scroll to bottom on both keystroke and output.
  both,

  /// Never auto-scroll. The user must scroll manually.
  never,
}

/// Terminal behavior configuration.
///
/// Immutable value object passed to [TerminalController] at creation or
/// replaced at runtime via [TerminalController.config]. Replacing the
/// config applies its modes, limits, cursor defaults, query responses, and
/// input policies without recreating the terminal. [cols] and [rows] apply
/// only when the controller is created; measured [TerminalView] geometry owns
/// the live grid size. Lower resource limits can prune scrollback or protocol
/// data.
///
/// All defaults produce standard terminal behavior out of the box.
///
/// ```dart
/// final controller = TerminalController(
///   config: TerminalConfig(
///     scrollbackMaxBytes: 5_000_000,
///     cursorBlink: true,
///     modes: {
///       ...TerminalConfig.defaultModes,
///       const TerminalMode.autoWrap(): false,
///     },
///   ),
/// );
/// ```
@immutable
class TerminalConfig {
  /// Default terminal modes.
  ///
  /// Includes grapheme cluster mode for proper multi-codepoint character
  /// handling. Applied on terminal init and restored when the alternate
  /// screen exits back to the primary screen.
  ///
  /// Spread and override to change individual defaults:
  ///
  /// ```dart
  /// const config = TerminalConfig(
  ///   modes: {
  ///     ...TerminalConfig.defaultModes,
  ///     const TerminalMode.autoWrap(): false,
  ///   },
  /// );
  /// ```
  static const defaultModes = <TerminalMode, bool>{
    .srm(): true,
    .autoWrap(): true,
    .cursorBlinking(): true,
    .cursorVisible(): true,
    .alternateScroll(): true,
    .numlockKeypad(): true,
    .altEscPrefix(): true,
    .graphemeCluster(): true,
  };

  /// Default APC payload buffer limit.
  static const defaultApcBufferLimit = 65 * 1024 * 1024;

  /// Initial terminal width in cells.
  ///
  /// Must be positive. Replacing [TerminalController.config] does not resize an
  /// existing terminal; [TerminalView] supplies its measured live dimensions.
  final int cols;

  /// Initial terminal height in cells.
  ///
  /// Must be positive. Replacing [TerminalController.config] does not resize an
  /// existing terminal; [TerminalView] supplies its measured live dimensions.
  final int rows;

  /// Maximum number of unfinished VT or UTF-8 bytes retained for snapshots.
  ///
  /// Defaults to zero, which disables continuation tracking. Valid values range
  /// from zero through `0xffffffff` for consistent native and WebAssembly
  /// behavior. Set a positive limit before writing input that may be unfinished
  /// when [TerminalController.snapshot] is called.
  final int continuationMaxBytes;

  /// Maximum scrollback buffer size in bytes.
  ///
  /// Defaults to 10,000 bytes. Set to null for no limit, or 0 to disable
  /// scrollback and erase retained history. The limit is approximate because
  /// libghostty allocates and prunes complete pages. When this and
  /// [scrollbackMaxLines] are set, the oldest eligible pages are discarded
  /// when either limit is reached. Lowering the value can prune immediately.
  final int? scrollbackMaxBytes;

  /// Maximum number of physical scrollback rows.
  ///
  /// Defaults to no limit. The limit is approximate because libghostty
  /// allocates and prunes complete pages, so the retained count is generally
  /// somewhat higher. When this and [scrollbackMaxBytes] are set, the oldest
  /// eligible pages are discarded when either limit is reached. Lowering the
  /// value can prune immediately.
  final int? scrollbackMaxLines;

  /// Maximum bytes of Kitty graphics image storage.
  ///
  /// Caps the in-memory footprint of images transmitted via the Kitty
  /// graphics protocol. Defaults to 64 MiB. Set to 0 to reject every
  /// image payload and delete stored Kitty images and placements.
  final int kittyImageStorageLimit;

  /// Maximum bytes buffered for APC payloads.
  ///
  /// Caps incoming APC control-string payloads before they are parsed.
  /// Defaults to 65 MiB. Set to 0 to reject APC payload data.
  final int apcBufferLimit;

  /// Maximum decoded bytes accepted in one Kitty clipboard write.
  ///
  /// Defaults to libghostty's 64 MiB limit. Set to null to restore that
  /// default.
  final int? clipboardWriteMaxBytes;

  /// Whether Glyph Protocol APC handling is enabled.
  ///
  /// Defaults to false. Enable to parse Glyph Protocol image payloads in
  /// addition to Kitty graphics.
  final bool glyphProtocol;

  /// Initial cursor shape. Terminal programs can override via DECSCUSR.
  final CursorShape cursorStyle;

  /// Cursor blink policy.
  ///
  /// Three-state to separate user preference from program control:
  /// - `null`: blink by default, respect DEC mode 12 from programs.
  /// - `true`: always blink, ignore DEC mode 12 (DECSCUSR still respected).
  /// - `false`: never blink, ignore DEC mode 12 (DECSCUSR still respected).
  final bool? cursorBlink;

  /// Terminal modes applied on init and primary screen restore.
  ///
  /// Every map entry is written; omitting a mode does not reset its live value.
  /// Programs can change modes at runtime via escape sequences. Use
  /// [TerminalController.modeGet] and [TerminalController.modeSet] to
  /// query or override the live state.
  ///
  /// Treat the supplied map as immutable. To change configured modes, supply
  /// a new map in a replacement configuration.
  final Map<TerminalMode, bool> modes;

  /// When to auto-scroll the viewport to the bottom.
  final ScrollToBottom scrollToBottom;

  /// Whether typing clears the current selection.
  ///
  /// When true, any keystroke that produces terminal input dismisses the
  /// active selection. Modifier-only keypresses do not clear.
  final bool selectionClearOnTyping;

  /// Response string sent when the terminal receives an ENQ character (0x05).
  ///
  /// Most terminals respond with an empty string. Set to a non-empty value
  /// for legacy systems that probe for terminal identity via ENQ.
  final String enquiryResponse;

  /// Device attributes response for DA1/DA2/DA3 queries.
  ///
  /// Controls what the terminal reports when a program sends a device
  /// attributes request.
  final DeviceAttributesResponse deviceAttributes;

  const TerminalConfig({
    this.cols = 80,
    this.rows = 24,
    this.continuationMaxBytes = 0,
    this.cursorBlink,
    this.glyphProtocol = false,
    this.apcBufferLimit = defaultApcBufferLimit,
    this.clipboardWriteMaxBytes,
    this.enquiryResponse = '',
    this.modes = defaultModes,
    this.cursorStyle = .block,
    this.scrollbackMaxBytes = 10_000,
    this.scrollbackMaxLines,
    this.kittyImageStorageLimit = 64 * 1024 * 1024,
    this.selectionClearOnTyping = true,
    this.scrollToBottom = .onKeystroke,
    this.deviceAttributes = const DeviceAttributesResponse(),
  }) : assert(cols > 0, 'cols must be positive'),
       assert(rows > 0, 'rows must be positive'),
       assert(
         continuationMaxBytes >= 0,
         'continuationMaxBytes must be non-negative',
       ),
       assert(
         continuationMaxBytes <= 0xffffffff,
         'continuationMaxBytes must fit an unsigned 32-bit integer',
       ),
       assert(
         scrollbackMaxBytes == null || scrollbackMaxBytes >= 0,
         'scrollbackMaxBytes must be non-negative',
       ),
       assert(
         scrollbackMaxLines == null || scrollbackMaxLines >= 0,
         'scrollbackMaxLines must be non-negative',
       ),
       assert(
         kittyImageStorageLimit >= 0,
         'kittyImageStorageLimit must be non-negative',
       ),
       assert(apcBufferLimit >= 0, 'apcBufferLimit must be non-negative'),
       assert(
         clipboardWriteMaxBytes == null || clipboardWriteMaxBytes >= 0,
         'clipboardWriteMaxBytes must be non-negative',
       );

  @override
  int get hashCode => Object.hash(
    cols,
    rows,
    continuationMaxBytes,
    scrollbackMaxBytes,
    scrollbackMaxLines,
    kittyImageStorageLimit,
    apcBufferLimit,
    clipboardWriteMaxBytes,
    glyphProtocol,
    cursorStyle,
    cursorBlink,
    .hashAllUnordered(modes.entries.map((e) => .hash(e.key, e.value))),
    scrollToBottom,
    selectionClearOnTyping,
    enquiryResponse,
    deviceAttributes,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TerminalConfig &&
          cols == other.cols &&
          rows == other.rows &&
          continuationMaxBytes == other.continuationMaxBytes &&
          scrollbackMaxBytes == other.scrollbackMaxBytes &&
          scrollbackMaxLines == other.scrollbackMaxLines &&
          kittyImageStorageLimit == other.kittyImageStorageLimit &&
          apcBufferLimit == other.apcBufferLimit &&
          clipboardWriteMaxBytes == other.clipboardWriteMaxBytes &&
          glyphProtocol == other.glyphProtocol &&
          cursorStyle == other.cursorStyle &&
          cursorBlink == other.cursorBlink &&
          mapEquals(modes, other.modes) &&
          scrollToBottom == other.scrollToBottom &&
          selectionClearOnTyping == other.selectionClearOnTyping &&
          enquiryResponse == other.enquiryResponse &&
          identical(deviceAttributes, other.deviceAttributes);

  /// Returns a copy with the given fields replaced.
  TerminalConfig copyWith({
    int? cols,
    int? rows,
    int? continuationMaxBytes,
    int? scrollbackMaxBytes,
    int? scrollbackMaxLines,
    int? kittyImageStorageLimit,
    int? apcBufferLimit,
    int? clipboardWriteMaxBytes,
    bool? glyphProtocol,
    CursorShape? cursorStyle,
    bool? cursorBlink,
    Map<TerminalMode, bool>? modes,
    ScrollToBottom? scrollToBottom,
    bool? selectionClearOnTyping,
    String? enquiryResponse,
    DeviceAttributesResponse? deviceAttributes,
  }) {
    return TerminalConfig(
      cols: cols ?? this.cols,
      rows: rows ?? this.rows,
      continuationMaxBytes: continuationMaxBytes ?? this.continuationMaxBytes,
      scrollbackMaxBytes: scrollbackMaxBytes ?? this.scrollbackMaxBytes,
      scrollbackMaxLines: scrollbackMaxLines ?? this.scrollbackMaxLines,
      kittyImageStorageLimit:
          kittyImageStorageLimit ?? this.kittyImageStorageLimit,
      apcBufferLimit: apcBufferLimit ?? this.apcBufferLimit,
      clipboardWriteMaxBytes:
          clipboardWriteMaxBytes ?? this.clipboardWriteMaxBytes,
      glyphProtocol: glyphProtocol ?? this.glyphProtocol,
      cursorStyle: cursorStyle ?? this.cursorStyle,
      cursorBlink: cursorBlink ?? this.cursorBlink,
      modes: modes ?? this.modes,
      scrollToBottom: scrollToBottom ?? this.scrollToBottom,
      selectionClearOnTyping:
          selectionClearOnTyping ?? this.selectionClearOnTyping,
      enquiryResponse: enquiryResponse ?? this.enquiryResponse,
      deviceAttributes: deviceAttributes ?? this.deviceAttributes,
    );
  }

  @override
  String toString() =>
      'TerminalConfig('
      'cols: $cols, rows: $rows, '
      'continuationMaxBytes: $continuationMaxBytes, '
      'scrollbackMaxBytes: $scrollbackMaxBytes, '
      'scrollbackMaxLines: $scrollbackMaxLines, '
      'modes: ${modes.length} entries)';
}
