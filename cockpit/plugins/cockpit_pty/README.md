# cockpit_pty

[![ci](https://github.com/cesarmod2017/cockpit_pty/actions/workflows/ci.yml/badge.svg)](https://github.com/cesarmod2017/cockpit_pty/actions/workflows/ci.yml)
[![pub points](https://badges.bar/cockpit_pty/pub%20points)](https://pub.dev/packages/cockpit_pty)

Pty for Flutter. Spawn a child process attached to a **pseudo-terminal** (PTY)
so it behaves exactly like it would inside a real terminal: line editing, ANSI
colors, cursor control, job control, and resize all work.

It implements the PTY in native code (instead of pure FFI + blocking isolates),
which makes it more stable than the older [`pty`](https://pub.dev/packages/pty)
package. It pairs naturally with [`xterm`](https://pub.dev/packages/xterm) to
render a fully interactive terminal widget in your app.

## Platforms

| Linux | macOS | Windows | Android |
| :---: | :---: | :-----: | :-----: |
|   ✔️   |   ✔️   |    ✔️    |    ✔️    |

> On Windows the PTY is backed by ConPTY, so Windows 10 (1809+) or later is
> required.
>
> **Web:** browsers can't spawn processes, so there's no *native* PTY on web.
> Instead, attach to a PTY running on another machine over a remote transport —
> the example ships a ready-to-use WebSocket transport + server (see
> [Pluggable backends](#pluggable-backends-local-pty-vs-remote-stream)).

## Install

```yaml
dependencies:
  cockpit_pty: ^0.4.2
```

```sh
flutter pub add cockpit_pty
```

No extra platform setup is needed — the native library is built and bundled
automatically as an FFI plugin.

## Quick start

```dart
import 'dart:convert';
import 'package:cockpit_pty/cockpit_pty.dart';

// Start a shell inside a pseudo-terminal.
final pty = Pty.start(
  Platform.isWindows ? 'cmd.exe' : 'bash',
  columns: 80,
  rows: 25,
);

// Read everything the process prints (stdout AND stderr share one stream).
pty.output
    .cast<List<int>>()
    .transform(const Utf8Decoder())
    .listen((text) => print(text));

// Send input, exactly like typing it at a prompt. Don't forget the newline.
pty.write(const Utf8Encoder().convert('ls -al\n'));

// React when the process ends.
pty.exitCode.then((code) => print('exited with $code'));

// Tell the PTY when the viewport changes size (rows, cols).
pty.resize(30, 100);

// Terminate it.
pty.kill();
```

## Configuration

All configuration is done through `Pty.start`:

```dart
final pty = Pty.start(
  'bash',                          // executable to run (positional)
  arguments: ['-l'],               // process arguments
  workingDirectory: '/home/me',    // cwd of the child (null = inherit)
  environment: {                   // extra env vars (merged, see note below)
    'FOO': 'bar',
  },
  rows: 25,                        // initial terminal height
  columns: 80,                     // initial terminal width
  ackRead: false,                  // flow control, see "Backpressure"
);
```

### Environment

`cockpit_pty` always sets `TERM=xterm-256color` and `LANG=en_US.UTF-8` (so tools
like `vi` emit UTF-8-friendly sequences), and copies a small set of variables
from the parent process: `LOGNAME`, `USER`, `DISPLAY`, `LC_TYPE`, `HOME`,
`PATH`. Anything you pass in `environment` is merged on top.

If you want the child to see the **full** parent environment (recommended for a
real terminal — on Windows the minimal subset misses `Path`, `SystemRoot`,
`APPDATA`, etc., which breaks resolving external commands), pass it explicitly:

```dart
final pty = Pty.start(
  shell,
  environment: Map<String, String>.from(Platform.environment),
);
```

### Picking the shell per platform

```dart
String get defaultShell {
  if (Platform.isWindows) {
    return Platform.environment['COMSPEC'] ?? 'cmd.exe';
  }
  return Platform.environment['SHELL'] ?? 'bash';
}
```

## API reference

| Member | Description |
| --- | --- |
| `Pty.start(executable, {...})` | Spawn `executable` in a new pseudo-terminal. |
| `Stream<Uint8List> output` | Combined stdout/stderr bytes from the process. |
| `Future<int> exitCode` | Completes with the exit code when the process ends. |
| `int pid` | Process id of the child. |
| `void write(Uint8List data)` | Write bytes to the PTY (the child's stdin). |
| `void resize(int rows, int cols)` | Inform the PTY of a new viewport size. |
| `bool kill([ProcessSignal signal])` | Send a signal (default `SIGTERM`) to the process. |
| `void ackRead()` | Acknowledge a chunk when `ackRead: true` (see below). |

> A PTY does **not** distinguish stdout from stderr — both arrive on `output`.

### Exit codes

On Linux/macOS a normal exit is `0..255`; a process killed by a signal reports
the negative signal number (e.g. `-11` for `SIGSEGV`). On Windows any 32-bit
value is possible and is returned as a signed int (e.g. an access violation
`0xc0000005` comes back as `-1073741819`). There's no guarantee `output` has
drained when `exitCode` completes — wait for the stream's `done` event if you
need every last byte.

## Using it with `xterm` (full terminal widget)

This is the common case: render an interactive terminal in Flutter. Wire the
`Pty` to an xterm `Terminal` in both directions.

```dart
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:cockpit_pty/cockpit_pty.dart';
import 'package:xterm/xterm.dart';

class TerminalWidget extends StatefulWidget {
  const TerminalWidget({super.key});
  @override
  State<TerminalWidget> createState() => _TerminalWidgetState();
}

class _TerminalWidgetState extends State<TerminalWidget> {
  final terminal = Terminal(maxLines: 10000);
  late final Pty pty;

  @override
  void initState() {
    super.initState();

    pty = Pty.start(
      Platform.isWindows ? 'cmd.exe' : 'bash',
      columns: terminal.viewWidth,
      rows: terminal.viewHeight,
      environment: Map<String, String>.from(Platform.environment),
    );

    // PTY output → terminal emulator (it does the ANSI/VT parsing).
    pty.output
        .cast<List<int>>()
        .transform(const Utf8Decoder())
        .listen(terminal.write);

    pty.exitCode.then((code) {
      terminal.write('\r\n[process exited: $code]\r\n');
    });

    // Keyboard / paste from the widget → PTY stdin.
    terminal.onOutput = (data) {
      pty.write(const Utf8Encoder().convert(data));
    };

    // The view reports its size in cells → forward to the PTY.
    terminal.onResize = (w, h, pw, ph) => pty.resize(h, w);
  }

  @override
  void dispose() {
    pty.kill();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TerminalView(terminal);
}
```

The runnable version of this — with tabs, multiple sessions, scroll-to-bottom,
OSC title handling, a styled theme, a command bar and pluggable backends —
lives in [`example/`](example/).

## Keyboard & input rules

Input flows **terminal → `onOutput` → `pty.write`**. A few things matter for it
to feel right:

| Key / gesture | Behavior |
| --- | --- |
| Typing | Sent to the PTY's stdin as-is. |
| **Enter** | Sends `\r` (carriage return) — that's what the line discipline expects, *not* `\n`. |
| **Ctrl+C** | With a selection → copies. With no selection → passes through as `SIGINT`. |
| **Ctrl+Shift+C / Ctrl+Shift+V** | Copy / paste (xterm defaults). |
| Mouse selection | Selects text; right-click / shortcuts copy it. |
| Resize | `onResize(w, h, …)` → `pty.resize(h, w)` (note the **rows, cols** order). |

### Desktop vs. mobile keyboards

`xterm`'s `TerminalView` can take input two ways, and the right choice depends
on the platform:

```dart
TerminalView(
  terminal,
  // Desktop (Windows/macOS/Linux): read characters straight from hardware key
  // events (event.character). Reliable typing, no on-screen keyboard.
  hardwareKeyboardOnly: true,
)
```

* **Desktop** → `hardwareKeyboardOnly: true`. The platform IME/text-input
  connection can be flaky for a custom client; reading `event.character` from
  hardware key events is robust. (If you only see `Enter` register but no
  letters, this is the fix.)
* **Mobile (Android/iOS)** → leave it `false` (the default) so the **on-screen
  keyboard / IME** shows and works.

```dart
final bool isMobile = Platform.isAndroid || Platform.isIOS;
TerminalView(terminal, hardwareKeyboardOnly: !isMobile);
```

### Sending a whole command programmatically

Besides live typing, you often want to push a full command (a "type this and
run it" button, or input coming from elsewhere). Just write the line followed by
Enter:

```dart
void sendCommand(Pty pty, String command) {
  pty.write(const Utf8Encoder().convert('$command\r'));
}

sendCommand(pty, 'git status');
```

The example wraps this in `PtySession.sendCommand` / `sendText` and exposes a
command bar at the bottom of each terminal.

## Pluggable backends: local PTY vs. remote stream

A terminal is just two byte streams (out/in) plus a resize signal. The `xterm`
`Terminal` doesn't care **where** those bytes come from. That lets you run the
*same* UI in two very different setups:

* **Local** — the shell runs on *this* machine; bytes come from `cockpit_pty`.
* **Remote** — the shell runs on *another* machine (and you're watching from a
  phone, say). Bytes arrive over the network (e.g. a gRPC stream), and your
  keystrokes are sent back to the host, which executes them. The relay in the
  middle is yours (the example author uses gRPC + Redis on the server).

The example models this with a small interface so the widget code is identical
either way:

```dart
abstract class TerminalBackend {
  Stream<String> get output;          // bytes FROM the process (UTF-8 decoded)
  void write(String data);            // input TO the process
  void resize(int rows, int cols);    // viewport size changed
  Future<void> get done;              // process / stream ended
  int? get pid;
  int? get exitCode;
  ValueListenable<bool> get inputEnabled; // false = read-only (no control lease)
  void dispose();
}
```

### Local backend (this machine)

`LocalPtyBackend` simply wraps `Pty`. Note the **streaming** UTF-8 decode — a
multi-byte glyph (box-drawing `─ │ ┌`, accents) can be split across two output
chunks, so decode with a stream transform, never `utf8.decode` per chunk:

```dart
_pty.output
    .cast<List<int>>()
    .transform(const Utf8Decoder(allowMalformed: true)) // buffers partials
    .listen(_output.add);

@override
void write(String data) => _pty.write(const Utf8Encoder().convert(data));

@override
void resize(int rows, int cols) => _pty.resize(rows, cols);
```

### Remote backend (another machine / mobile)

On mobile you do **not** spawn a PTY on the phone — there's nothing to spawn.
Instead you implement a transport that talks to the host, and feed its frames to
the same `Terminal`. The example ships `RemotePtyBackend` + a `RemotePtyTransport`
interface (no gRPC dependency baked in) that you implement against your own RPC
layer:

```dart
abstract class RemotePtyTransport {
  Stream<RemotePtyFrame> streamPty();                 // server → client output
  Future<String?> acquireControl({bool force});       // input lease (token)
  Future<void> releaseControl(String token);
  Future<void> sendInput(String token, List<int> data);
  Future<void> resize(String token, {required int cols, required int rows});
}
```

A `RemotePtyBackend` built on that handles the things a naive wiring gets wrong:

* **snapshot/replay** — on (re)connect the server sends the buffered screen with
  `isSnapshot: true`; reset the emulator (`\x1b[2J\x1b[3J\x1b[H`) before writing
  it so reconnects don't stack;
* **sequence dedup** — ignore frames whose `seq` you've already seen;
* **streaming UTF-8** — decode with a *stateful* chunked converter so glyphs
  split across frames don't turn into ``;
* **control lease** — input is disabled until `acquireControl()` succeeds; bind
  `TerminalView.readOnly` to `inputEnabled`, and remember the lease has a TTL on
  the server (refreshed by each input/resize) — pure viewers stay read-only.

```dart
// Sketch: implement RemotePtyTransport over your own gRPC client.
class GrpcPtyTransport implements RemotePtyTransport {
  GrpcPtyTransport(this._client, this.taskId, this.workspaceId);
  // ...
  @override
  Stream<RemotePtyFrame> streamPty() => _client
      .streamPty(StreamPtyRequest(taskId: taskId, workspaceId: workspaceId))
      .map((f) => RemotePtyFrame(
            data: f.data,
            seq: f.seq.toInt(),
            isSnapshot: f.isSnapshot,
            closed: f.closed,
            controlHolderUserId: f.controlHolderUserId,
          ));

  @override
  Future<void> sendInput(String token, List<int> data) =>
      _client.sendPtyInput(PtyInputRequest(
        taskId: taskId, workspaceId: workspaceId, controlToken: token, data: data,
      ));
  // acquireControl / releaseControl / resize map the same way.
}
```

Then the session is created the same way as a local one — only the backend
differs:

```dart
// Local (desktop)
PtySession.local(id: 1);

// Remote (mobile / another machine)
PtySession.remote(
  id: 2,
  backendBuilder: (cols, rows) =>
      RemotePtyBackend(GrpcPtyTransport(client, taskId, workspaceId)),
);
```

See `example/lib/terminal_backend.dart`, `example/lib/remote_pty_backend.dart`
and `example/lib/pty_session.dart` for the full, commented implementation.

### What your backend must provide (server side)

The Flutter app is only the *viewer/controller*. For the remote mode to work,
**your backend is responsible for actually owning the PTY and relaying it.**
This package doesn't ship that — here's the contract it has to satisfy. (The
transport can be anything: gRPC, WebSocket, SignalR… The reference setup uses
gRPC for the edge + Redis pub/sub to fan out across server instances.)

#### Data flow

```
   ┌─────────── host machine (agent) ───────────┐        ┌──── server/relay ────┐        ┌── client(s) ──┐
   │  real PTY  (cockpit_pty / node-pty / …)     │        │  pub/sub + buffer     │        │  Flutter app   │
   │                                             │        │  (e.g. Redis)         │        │  (xterm)       │
   │  stdout/stderr ──────────────────────────────────▶  fan-out  ───────────────────────▶  StreamPty      │
   │  stdin        ◀──────────────────────────────────  publish  ◀───────────────────────  SendPtyInput    │
   │  resize       ◀──────────────────────────────────  publish  ◀───────────────────────  ResizePty       │
   └─────────────────────────────────────────────┘        └──────────────────────┘        └────────────────┘
```

#### The backend MUST:

1. **Own the real PTY on the host.** Spawn the shell/process in a pseudo-terminal
   *on the target machine* (this is where `cockpit_pty` itself can run, or
   node-pty, etc.). The phone never spawns anything.
2. **Stream output in real time.** Expose a **server-stream** endpoint
   (`StreamPty`) that pushes every chunk of PTY output to all subscribed clients
   as it's produced. Output bytes are raw — do **not** re-encode; let the client
   decode UTF-8 in streaming mode.
3. **Send a snapshot on (re)connect.** Keep a rolling buffer of recent output
   (capped, e.g. last N KB) and, as the **first** frame of every new stream,
   send it with `is_snapshot = true`. This is what lets a phone that joins late —
   or reconnects after a drop — immediately see the current screen instead of a
   blank one.
4. **Tag frames with a sequence number.** A monotonic `seq` per PTY lets clients
   drop duplicates and detect gaps (important with pub/sub redelivery).
5. **Accept input** (`SendPtyInput`): take bytes from a client and write them to
   the PTY's stdin **on the host**. Keystrokes, pastes and whole commands all
   arrive here.
6. **Accept resize** (`ResizePty`): apply `cols`/`rows` to the host PTY so the
   remote program reflows correctly.
7. **Enforce a single writer (control lease).** Many viewers, **one** typist:
   * `AcquirePtyControl` → hand out a short-lived **control token** (TTL, e.g.
     30 s). If someone already holds it, deny (unless `force`).
   * Require that token on every `SendPtyInput`/`ResizePty`; **reject** stale or
     missing tokens. Refresh the TTL on each accepted input/resize.
   * `ReleasePtyControl` → free the lease. Without a token, the client is
     read-only.
8. **Signal end of session.** When the host process exits, emit a final frame
   with `closed = true` (and stop the stream) so clients can show "encerrado".
9. **Authenticate & authorize.** Validate who's connecting (the example checks
   task/workspace membership) and gate *input* behind a permission (owner/admin
   or an explicit flag) — viewing can be broader than typing.
10. **Fan out + clean up.** Support multiple concurrent subscribers per PTY, and
    unsubscribe/release on disconnect so you don't leak streams or leave a
    dangling control lease.

#### What the client expects per frame

Each output frame the backend sends maps to `RemotePtyFrame`:

| Field | Meaning | Client behavior |
| --- | --- | --- |
| `data` | raw PTY output bytes | decoded (streaming UTF-8) → `terminal.write` |
| `seq` | monotonic counter | drop if `seq <= lastSeen` |
| `is_snapshot` | full-buffer replay | reset screen (`\x1b[2J\x1b[3J\x1b[H`) then write |
| `closed` | process ended | mark session finished |
| `control_holder_user_id` | who holds the lease | show read-only banner |

#### Minimum vs. nice-to-have

* **Minimum to function:** output stream + input + resize.
* **Needed for good UX:** snapshot/replay, `seq` dedup, the control lease, and
  the `closed` signal — without these you get blank reconnects, duplicated
  output, multiple people fighting over the keyboard, and no "session ended".

> The example author's implementation of exactly this lives server-side as a
> gRPC `TerminalStreamService` (`StreamPty`/`SendPtyInput`/`ResizePty`/
> `AcquirePtyControl`/`ReleasePtyControl`) backed by Redis for the snapshot
> buffer, the input channel, and the control-token lease.

### WebSocket transport — batteries included (incl. web)

gRPC is great when you already run it. For everything else — and especially for
**web**, where a browser can't spawn a process at all — the example ships a
ready-to-use **WebSocket** transport *and* a matching server, so you can stand up
a remote terminal with zero backend infrastructure:

* `example/lib/pty_websocket_server.dart` — `PtyWebSocketServer`: runs on the
  **host** (a desktop app using cockpit_pty), spawns a real `Pty`, and serves it
  over a WebSocket. Uses only `dart:io` (no extra deps).
* `example/lib/websocket_pty_transport.dart` — `WebSocketPtyTransport`: the
  **client** (web / mobile / another desktop). Implements `RemotePtyTransport`,
  so it drops straight into `RemotePtyBackend` and inherits snapshot reset, seq
  dedup, streaming UTF-8 and read-only gating.

This is the capability packages like `portable_pty` expose for web; here it's
integrated with the same pluggable backend, so the *exact same UI* renders a
local PTY or a remote one.

#### Wire protocol

One WebSocket per session. Output stays on binary frames (no base64 on the hot
path); control is human-readable JSON.

| Direction | Frame | Meaning |
| --- | --- | --- |
| host → client | **binary** | raw PTY output |
| host → client | `{"type":"snapshot","dataB64":"…"}` | buffered screen, sent once on connect |
| host → client | `{"type":"exit","code":0}` | process ended |
| client → host | **binary** | raw stdin (typing / paste / commands) |
| client → host | `{"type":"resize","cols":80,"rows":24}` | viewport resized |

#### Host (the machine running the shell)

```dart
import 'package:cockpit_pty_example/pty_websocket_server.dart';

final server = PtyWebSocketServer(
  // shell: 'bash',                 // defaults to the platform shell
  // arguments: ['/k', 'claude'],   // e.g. launch Claude on connect (Windows)
  address: InternetAddress.anyIPv4, // omit for localhost-only
  port: 8080,
);
await server.start();   // now serving ws://<host>:8080/
// ...
await server.stop();    // kills the PTY, closes clients
```

#### Client (web / mobile / another desktop)

```dart
import 'package:cockpit_pty_example/pty_session.dart';
import 'package:cockpit_pty_example/remote_pty_backend.dart';
import 'package:cockpit_pty_example/websocket_pty_transport.dart';

final session = PtySession.remote(
  id: 1,
  label: 'remote',
  backendBuilder: (cols, rows) =>
      RemotePtyBackend(WebSocketPtyTransport('ws://192.168.0.10:8080')),
);
// drop session.terminal into a TerminalView — typing, output, resize and the
// command bar all work exactly like the local case.
```

> ⚠️ `PtyWebSocketServer` is intentionally minimal: **one shared session, no
> auth, every client can type.** It's perfect for a LAN / demo. For the
> internet you want TLS (`wss://`), authentication, and the single-writer
> control lease — that's where the gRPC + Redis backend (above) earns its keep.
> The client (`RemotePtyBackend`) is identical either way.
>
> On **web**, only the client half runs (browsers can't bind a server); host a
> `PtyWebSocketServer` on a real machine and point the browser at it.

#### Running the web demo end-to-end

The example ships three ready-to-run entrypoints:

| Entrypoint | What it is | Run on |
| --- | --- | --- |
| `lib/main.dart` | the full **local** terminal (tabs, command bar, Claude button) | desktop |
| `lib/main_host.dart` | a **host**: starts `PtyWebSocketServer` and serves a PTY over `ws://…:8080` | desktop (the machine you want to drive) |
| `lib/main_web.dart` | the **web client**: connects to a host and renders the terminal in the browser | web (and mobile/desktop) |

**Prerequisites** (already set up in `example/`):

```sh
cd example

# 1. Web platform support (creates web/). One-time.
flutter create --platforms=web .

# 2. Deps: web_socket_channel (cross-platform WS, incl. web) is in pubspec.
flutter pub get
```

> The terminal font (`CascadiaMono`) is bundled as an asset so it renders as a
> crisp monospace **on web too** — Flutter's web canvas does not use
> system-installed fonts, so without a bundled font the terminal falls back to a
> proportional font squeezed into monospace cells (the "spaced-out" look).

**Step 1 — start the host** on the machine whose shell you want to drive:

```sh
flutter run -d windows -t lib/main_host.dart     # or -d macos / -d linux
```

It auto-starts and prints `Servindo um PTY em ws://localhost:8080`. To reach it
from another machine / a phone it already binds `InternetAddress.anyIPv4`; just
open TCP **8080** in the firewall and use the host's LAN IP.

**Step 2 — run the web client.** Either way works:

```sh
# A) Normal Flutter web (debug): opens Chrome and hot-reloads.
flutter run -d chrome -t lib/main_web.dart

# B) Release build + static server (use this if `flutter run -d chrome` is
#    unavailable, e.g. a restricted/CI environment missing the web SDK):
flutter build web -t lib/main_web.dart
cd build/web && python -m http.server 5599
#    then open http://localhost:5599 in any browser
```

**Step 3 — connect.** The web client auto-connects to `ws://localhost:8080`
(editable in the connect bar). When it goes 🟢 **ao vivo**, you're typing into
the host's PTY from the browser — output, resize, paste and full TUIs (vim,
`claude`, …) all stream live.

For a phone or another machine, change the URL to `ws://<host-LAN-IP>:8080`.
For anything beyond a trusted LAN, front it with TLS (`wss://`), authentication
and the single-writer control lease — i.e. the gRPC + Redis backend.

> **Keyboard on web/mobile:** the web client leaves `hardwareKeyboardOnly`
> **off** so the browser / on-screen keyboard works. Only the desktop local
> terminal sets `hardwareKeyboardOnly: true` (reads `event.character` directly).
> See [Keyboard & input rules](#keyboard--input-rules).

## Backpressure (`ackRead`)

By default the PTY streams output as fast as the process produces it. If your
consumer can't keep up (e.g. heavy rendering), start with `ackRead: true`: the
PTY then pauses after each chunk until you call `pty.ackRead()`, giving you
explicit flow control.

```dart
final pty = Pty.start('bash', ackRead: true);

pty.output.listen((chunk) {
  render(chunk);
  pty.ackRead(); // request the next chunk
});
```

## Lifecycle & cleanup

Always tear the session down to avoid leaking the native process and the output
subscription:

```dart
final sub = pty.output.listen(...);
// ...
await sub.cancel();
pty.kill(); // best-effort; no-op if already exited
```

When integrating with widgets, do this in `dispose()`. If you also own xterm
`ScrollController`/`TerminalController`, dispose them *after* the `TerminalView`
has unmounted to avoid "used after dispose" errors — see the example's
`PtySession.dispose` for the pattern.

## How it works

* `src/` — native PTY implementation (`forkpty` on Unix, ConPTY on Windows) plus
  a `CMakeLists.txt` to build it into a dynamic library.
* `lib/` — the Dart API in `cockpit_pty.dart`, calling the native library via
  `dart:ffi`. Bindings in `lib/src/cockpit_pty_bindings_generated.dart` are
  generated from `src/cockpit_pty.h` by [`package:ffigen`](https://pub.dev/packages/ffigen)
  (`flutter pub run ffigen --config ffigen.yaml`).
* platform folders (`android`, `ios`, `windows`, …) — build glue that compiles
  and bundles the native library with your app.

## Contributing / regenerating bindings

After editing the native header `src/cockpit_pty.h`, regenerate the FFI
bindings:

```sh
flutter pub run ffigen --config ffigen.yaml
```

## License

See [LICENSE](LICENSE).
