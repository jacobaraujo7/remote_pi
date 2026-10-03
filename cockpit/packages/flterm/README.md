<p align="center">
  <img src="screenshots/banner.png" alt="Ghostty's full VT engine, as a Flutter widget" width="100%">
</p>

<p align="center">
  <a href="https://pub.dev/packages/flterm"><img alt="pub package" src="https://img.shields.io/pub/v/flterm"></a>
  <a href="https://github.com/elias8/libghostty/actions"><img alt="ci" src="https://github.com/elias8/libghostty/actions/workflows/build.yml/badge.svg"></a>
  <a href="https://github.com/sponsors/elias8"><img alt="sponsor" src="https://img.shields.io/github/sponsors/elias8?logo=githubsponsors&label=sponsor"></a>
</p>

Flutter terminal widget on top of [Ghostty](https://ghostty.org)'s
libghostty-vt engine.

| Android | iOS | Linux | macOS | Web | Windows |
|:-------:|:---:|:-----:|:-----:|:---:|:-------:|
|    ✓    |  ✓  |   ✓   |   ✓   |  ✓  |    ✓    |

## Overview

- Adapts to the host: mouse and keyboard on desktop, touch and soft
  keyboard on mobile, both on web.
- `TerminalController` owns the terminal and connects to a backend
  (PTY, SSH, socket) via output/resize/bell/title callbacks. Helpers
  for I/O, selection, scrolling, paste, and mode toggling.
- Drag, double-click, triple-click, and Alt+drag selection over wide
  characters (CJK, emoji, VS16, combining marks) with cell-snapped
  boundaries.
- Built-in copy, paste, select all, and clear shortcuts with
  platform-aware defaults. Extend or replace with any Flutter
  `Intent`.
- Themes for ANSI 16, 256-color, and truecolor palettes; cursor;
  hyperlinks; fonts. Immutable and `lerp`-able.
- Links for OSC 8 metadata, text URLs, file paths, and custom regex
  rules with activation callbacks.

## Getting started

```yaml
dependencies:
  flterm: ^0.0.5
```

On web, initialize the wasm module once before mounting any terminal:

```dart
import 'package:flterm/flterm.dart';
import 'package:flutter/foundation.dart';

if (kIsWeb) {
  await initializeForWeb(Uri.parse('assets/libghostty.wasm'));
}
```

## Usage

A `TerminalController` owns the terminal and talks to your I/O. A
`TerminalView` renders it.

```dart
import 'package:flterm/flterm.dart';

final controller = TerminalController()
  ..onOutput = (bytes) => pty.write(bytes)
  ..onResize = (cols, rows) => pty.resize(cols, rows)
  ..onBell = playSound;

ptyOutputStream.listen(controller.write);

TerminalView(
  controller: controller,
  theme: TerminalTheme.dark(),
);
```

Attach a controller to only one `TerminalView` at a time. The view does not
dispose it; remove the view, dispose any formatters created by the controller,
then dispose the controller when the terminal session ends. Resize callbacks
begin after the view has measured and committed its first grid.

The same controller drives the terminal programmatically:

```dart
// I/O
controller.sendText('ls -la\n');

// Selection
controller.selectAll();
print(controller.selectedText());

// Clipboard
controller.paste('hello');

// Reset
controller.clear();
```

Links are configured on the view. Built-in detection covers OSC 8
metadata, text URLs, and file paths.

```dart
TerminalView(
  controller: controller,
  linkSettings: LinkSettings(
    onActivate: (link) {
      if (link.uri case final uri?) openUri(uri);
      if (link.file case final file?) openFile(file);
    },
  ),
);
```

Custom matchers can add project-specific selectors:

```dart
TerminalView(
  controller: controller,
  linkSettings: LinkSettings(
    rules: [
      .regex(
        id: 'issue',
        pattern: RegExp(r'#(\d+)'),
      ),
    ],
    onActivate: (link) {
      if (link.id == 'issue') openIssue(link.text.substring(1));
    },
  ),
);
```

> **Note**: Idle link styling and custom rules with `LinkHighlightMode.always`
> scan visible content after terminal updates. The cost grows with output rate,
> visible rows, and line length, which can impact rendering performance and
> frame rate. Avoid always-on or idle highlighting unless that extra scanning
> is acceptable.

Custom themes are constructed directly:

```dart
TerminalView(
  controller: controller,
  theme: TerminalTheme(
    palette: ColorPalette(
      ansiColors: const [/* 16 ANSI colors */],
      background: const Color(0xFF1D1F21),
      foreground: const Color(0xFFC5C8C6),
    ),
    fontFamily: 'JetBrains Mono',
    fontSize: 14,
    cursor: const CursorTheme(shape: CursorShape.bar),
  ),
);
```

## Snapshots

Capture terminal state with `controller.snapshot()` and restore it into a new
controller:

```dart
final snapshot = controller.snapshot();
final session = TerminalController.fromSnapshot(snapshot)
  ..onOutput = backend.write;
final view = TerminalView(controller: session);
await session.restored;
```

The terminal is available immediately while older scrollback loads. Read
`session.restoration` for lifecycle state, or await `session.restored` for
completion and late errors. Enable `TerminalConfig.continuationMaxBytes` before
writing unfinished VT or UTF-8 input that must be captured.

## License

MIT. See [LICENSE](LICENSE).
