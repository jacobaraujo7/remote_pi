// `cockpit` — CLI **interna** do Cockpit. Fica visível apenas dentro dos
// terminais que o app spawna (o app prependa `~/.cockpit/bin` no PATH só dessas
// abas) e fala com o app pelo **mesmo socket** do `cockpit-hook`
// (`COCKPIT_STATUS_SOCK` no POSIX; `COCKPIT_STATUS_PORT`+`COCKPIT_STATUS_TOKEN`
// no Windows), discriminando `type:"cmd"` no wire (request/response).
//
// Nomenclatura: a unidade que a CLI endereça é uma **tab** (uma sessão de
// terminal/agente). Um **pane** é a folha do split que agrupa várias tabs — a
// CLI não o endereça. Por isso o vocabulário é "tab"; `list-panes`/`read-pane`
// e `COCKPIT_PANE_ID` ficam como **aliases legados** dos novos `list-tabs`/
// `read-tab`/`COCKPIT_TAB_ID`.
//
// Verbos:
//   cockpit send      [--tab-id <id>] <texto>     digita texto literal (sem \r)
//   cockpit send-key  [--tab-id <id>] <Key>...    pressiona tecla(s) nomeada(s)
//   cockpit open      [--tab-id <id>] <arquivo>   abre o arquivo no viewer
//   cockpit <arquivo>                             atalho de `open`
//   cockpit read-tab  [<label|tab-id>] [--lines N] [--offset N] [--from-start]
//                                                 lê o output de uma tab
//                                                 (alias: read-pane)
//   cockpit read-task <task-id> [--lines N] [--offset N] [--from-start]
//                                                 lê o output de uma task
//   cockpit list-tabs       [--json]              tabs ativas (alias: list-panes)
//   cockpit list-workspaces [--json]              workspaces (projetos) abertos
//   cockpit install-skill   [--force]             instala a skill do Claude Code
//   cockpit --help | --version
//
// `--tab-id` default = $COCKPIT_TAB_ID (a tab que emitiu; fallback: o legado
// $COCKPIT_PANE_ID). Tab ids (t0, t1…) são sequenciais e **resetam a cada boot
// do app** → descubra-os com list-tabs antes de mirar cross-tab.
//
// Compilar: dart compile exe tool/cockpit_cli.dart -o <dest>/cockpit-cli

import 'dart:convert';
import 'dart:io';

const String _version = '0.3.0';

/// Id da própria tab: `COCKPIT_TAB_ID` (novo) com fallback pro legado
/// `COCKPIT_PANE_ID`. O app injeta os dois; o fallback cobre binário novo com
/// app antigo (só PANE_ID) e vice-versa.
String? _selfTabId() =>
    Platform.environment['COCKPIT_TAB_ID'] ??
    Platform.environment['COCKPIT_PANE_ID'];

Future<void> main(List<String> argv) async {
  final args = List<String>.from(argv);
  if (args.isEmpty) {
    _printHelp(stderr);
    exit(2);
  }
  final first = args.first;
  if (first == '--help' || first == '-h' || first == 'help') {
    _printHelp(stdout);
    exit(0);
  }
  if (first == '--version' || first == '-v') {
    stdout.writeln('cockpit $_version');
    exit(0);
  }

  final cmd = args.removeAt(0);
  switch (cmd) {
    case 'send':
      await _cmdSend(args);
    case 'send-key':
    case 'send-keys':
      await _cmdSendKey(args);
    case 'open':
      await _cmdOpen(args);
    case 'list-tabs':
    case 'list-panes': // alias legado
      // Mantém o comando de wire 'list-panes' (protocolo estável); só o nome do
      // verbo mudou na superfície.
      await _cmdList('list-panes', args);
    case 'list-workspaces':
      await _cmdList('list-workspaces', args);
    case 'read-tab':
    case 'read-pane': // alias legado
      await _cmdRead('read-pane', args);
    case 'read-task':
      await _cmdRead('read-task', args);
    case 'install-skill':
      await _cmdInstallSkill(args);
    default:
      // Atalho: `cockpit <arquivo>` (sem verbo) abre o arquivo — o token
      // desconhecido é tratado como caminho. `cockpit open <arquivo>` é a
      // forma explícita.
      await _cmdOpen([cmd, ...args]);
  }
}

// ---- comandos ---------------------------------------------------------------

Future<void> _cmdSend(List<String> args) async {
  final parsed = _Flags.parse(args);
  final text = parsed.positionals.join(' ');
  if (text.isEmpty) {
    stderr.writeln('cockpit send: missing text to send');
    exit(2);
  }
  await _writeToTab(parsed.tabId, text);
}

Future<void> _cmdSendKey(List<String> args) async {
  final parsed = _Flags.parse(args);
  if (parsed.positionals.isEmpty) {
    stderr.writeln('cockpit send-key: missing key (e.g. Enter, C-c, Escape)');
    exit(2);
  }
  final buf = StringBuffer();
  for (final name in parsed.positionals) {
    final resolved = _resolveKey(name);
    if (resolved == null) {
      stderr.writeln('cockpit send-key: unknown key "$name"');
      exit(2);
    }
    buf.write(resolved);
  }
  await _writeToTab(parsed.tabId, buf.toString());
}

Future<void> _cmdOpen(List<String> args) async {
  final parsed = _Flags.parse(args);
  if (parsed.positionals.isEmpty) {
    stderr.writeln('cockpit open: missing file path');
    exit(2);
  }
  // O app tem cwd próprio — resolve pro caminho absoluto no cwd deste pane
  // (onde a CLI está rodando) antes de mandar.
  final abs = _resolvePath(parsed.positionals.first);
  final tabId = parsed.tabId ?? _selfTabId();
  final req = <String, dynamic>{
    'cmd': 'open',
    'args': <String, dynamic>{'path': abs},
  };
  if (tabId != null && tabId.isNotEmpty) req['tabId'] = tabId;
  final resp = await _request(req);
  if (resp['ok'] != true) {
    stderr.writeln('cockpit: ${resp['error'] ?? 'failed'}');
    exit(1);
  }
  exit(0);
}

/// Expande `~` e resolve caminhos relativos contra o cwd atual → absoluto.
String _resolvePath(String path) {
  var p = path;
  if (p == '~' || p.startsWith('~/')) {
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home != null && home.isNotEmpty) {
      p = p == '~' ? home : '$home/${p.substring(2)}';
    }
  }
  return File(p).absolute.path;
}

Future<void> _cmdList(String cmd, List<String> args) async {
  final parsed = _Flags.parse(args);
  final resp = await _request(<String, dynamic>{'cmd': cmd});
  if (resp['ok'] != true) {
    stderr.writeln('cockpit: ${resp['error'] ?? 'failed'}');
    exit(1);
  }
  final data = (resp['data'] as List?) ?? const [];
  if (parsed.json) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(data));
    exit(0);
  }
  if (data.isEmpty) {
    stdout.writeln('(none)');
    exit(0);
  }
  if (cmd == 'list-panes') {
    // (comando de wire estável; a superfície é `list-tabs`)
    for (final e in data.cast<Map>()) {
      final flag = e['working'] == true ? '●' : ' ';
      // Rótulo manual (nome estável) vence o título dinâmico; `⚲` sinaliza que
      // está travado. Sem rótulo, mostra o título automático.
      final label = e['label'];
      final name = (label is String && label.isNotEmpty)
          ? '⚲ $label'
          : (e['title'] ?? '').toString();
      stdout.writeln(
        '$flag ${_pad(e['id']?.toString(), 6)} '
        '${_pad(e['kind']?.toString(), 9)} '
        '${_pad(e['workspaceId']?.toString(), 8)} $name',
      );
    }
  } else {
    for (final e in data.cast<Map>()) {
      // `tabs` é o campo novo; `panes` fica como fallback (app antigo).
      final n = e['tabs'] ?? e['panes'] ?? 0;
      stdout.writeln(
        '${_pad(e['id']?.toString(), 10)} '
        '${_pad('$n tabs', 10)} ${e['name'] ?? ''}',
      );
    }
  }
  exit(0);
}

Future<void> _writeToTab(String? tabIdFlag, String text) async {
  final tabId = tabIdFlag ?? _selfTabId();
  if (tabId == null || tabId.isEmpty) {
    stderr.writeln(
      'cockpit: no target — pass --tab-id <id> or run inside a Cockpit '
      'terminal (COCKPIT_TAB_ID is unset). Use `cockpit list-tabs`.',
    );
    exit(2);
  }
  final resp = await _request(<String, dynamic>{
    'cmd': 'write',
    'tabId': tabId,
    'args': <String, dynamic>{'data': base64.encode(utf8.encode(text))},
  });
  if (resp['ok'] != true) {
    stderr.writeln('cockpit: ${resp['error'] ?? 'failed'}');
    exit(1);
  }
  exit(0);
}

/// `read-pane [<label|tab-id>]` / `read-task <task-id>` — lê uma janela do
/// output do alvo. `--lines N` (default 100), `--offset N` (pula N a partir da
/// âncora), `--from-start` (âncora no começo; default = tail). A saída é sempre
/// cronológica (de cima pra baixo) — as flags só escolhem a janela. Payload
/// volta base64 numa linha (framing do socket é uma-linha-por-conexão).
Future<void> _cmdRead(String cmd, List<String> args) async {
  final parsed = _Flags.parse(args);
  final target = parsed.positionals.isNotEmpty ? parsed.positionals.first : '';
  if (cmd == 'read-task' && target.isEmpty) {
    stderr.writeln('cockpit read-task: missing task id');
    exit(2);
  }
  final req = <String, dynamic>{
    'cmd': cmd,
    'args': <String, dynamic>{
      if (target.isNotEmpty) 'target': target,
      if (parsed.lines != null) 'lines': parsed.lines,
      if (parsed.offset != null) 'offset': parsed.offset,
      if (parsed.fromStart) 'fromStart': true,
    },
  };
  // Sem alvo posicional, o server cai na própria tab ($COCKPIT_TAB_ID).
  final tabId = parsed.tabId ?? _selfTabId();
  if (tabId != null && tabId.isNotEmpty) req['tabId'] = tabId;
  final resp = await _request(req);
  if (resp['ok'] != true) {
    stderr.writeln('cockpit: ${resp['error'] ?? 'failed'}');
    exit(1);
  }
  final data = (resp['data'] as Map?) ?? const {};
  String text;
  try {
    text = utf8.decode(base64.decode((data['text'] ?? '').toString()));
  } catch (_) {
    stderr.writeln('cockpit: malformed payload');
    exit(1);
  }
  if (text.isNotEmpty) stdout.writeln(text);
  if (data['truncated'] == true) {
    stderr.writeln(
      'cockpit: output truncated (server cap 2000 lines/read — page with '
      '--offset)',
    );
  }
  exit(0);
}

// ---- transporte (socket) ----------------------------------------------------

Future<Map<String, dynamic>> _request(Map<String, dynamic> req) async {
  final env = Platform.environment;
  final sock = env['COCKPIT_STATUS_SOCK'];
  final port = int.tryParse(env['COCKPIT_STATUS_PORT'] ?? '');
  if ((sock == null || sock.isEmpty) && port == null) {
    stderr.writeln(
      'cockpit: not inside a Cockpit terminal (COCKPIT_STATUS_SOCK is unset)',
    );
    exit(3);
  }
  req['type'] = 'cmd';
  final tok = env['COCKPIT_STATUS_TOKEN'];
  if (tok != null) req['tok'] = tok;

  Socket socket;
  try {
    socket = (sock != null && sock.isNotEmpty)
        ? await Socket.connect(
            InternetAddress(sock, type: InternetAddressType.unix),
            0,
          )
        : await Socket.connect(InternetAddress.loopbackIPv4, port!);
  } catch (e) {
    stderr.writeln('cockpit: could not connect to app: $e');
    exit(3);
  }

  socket.add(utf8.encode('${jsonEncode(req)}\n'));
  await socket.flush();
  // O servidor escreve uma linha JSON e fecha → basta juntar até o EOF.
  final raw = await socket
      .cast<List<int>>()
      .transform(utf8.decoder)
      .join()
      .timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          socket.destroy();
          return '';
        },
      );
  socket.destroy();
  final line = raw.trim();
  if (line.isEmpty) {
    return <String, dynamic>{'ok': false, 'error': 'no response from app'};
  }
  try {
    final decoded = jsonDecode(line);
    return decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{'ok': false, 'error': 'malformed response'};
  } catch (_) {
    return <String, dynamic>{'ok': false, 'error': 'resposta malformada'};
  }
}

// ---- teclas nomeadas --------------------------------------------------------

/// Resolve um nome de tecla na sua sequência de bytes (como String de code
/// points < 128 → UTF-8 idêntico). `null` se o nome é desconhecido.
String? _resolveKey(String name) {
  switch (name.toLowerCase()) {
    case 'enter':
    case 'return':
    case 'cr':
      return '\r';
    case 'tab':
      return '\t';
    case 'escape':
    case 'esc':
      return '\x1b';
    case 'space':
      return ' ';
    case 'bspace':
    case 'backspace':
      return '\x7f';
    case 'up':
      return '\x1b[A';
    case 'down':
      return '\x1b[B';
    case 'right':
      return '\x1b[C';
    case 'left':
      return '\x1b[D';
    case 'home':
      return '\x1b[H';
    case 'end':
      return '\x1b[F';
    case 'pageup':
    case 'ppage':
      return '\x1b[5~';
    case 'pagedown':
    case 'npage':
      return '\x1b[6~';
    case 'delete':
    case 'del':
      return '\x1b[3~';
  }
  // Ctrl: C-<letra> → byte de controle (a=0x01 … z=0x1a).
  final ctrl = RegExp(r'^c-(.)$', caseSensitive: false).firstMatch(name);
  if (ctrl != null) {
    final ch = ctrl.group(1)!.toLowerCase().codeUnitAt(0);
    if (ch >= 0x61 && ch <= 0x7a) return String.fromCharCode(ch - 0x60);
  }
  // Nome de 1 caractere → literal (ex.: `cockpit send-key a`).
  if (name.length == 1) return name;
  return null;
}

// ---- flags ------------------------------------------------------------------

class _Flags {
  _Flags(
    this.positionals,
    this.tabId,
    this.json,
    this.force,
    this.lines,
    this.offset,
    this.fromStart,
  );
  final List<String> positionals;
  final String? tabId;
  final bool json;
  final bool force;
  final int? lines;
  final int? offset;
  final bool fromStart;

  static int _intValue(String flag, String raw) {
    final v = int.tryParse(raw);
    if (v == null || v < 0) {
      stderr.writeln('cockpit: $flag requires a non-negative integer');
      exit(2);
    }
    return v;
  }

  static _Flags parse(List<String> args) {
    final positionals = <String>[];
    String? tabId;
    var json = false;
    var force = false;
    int? lines;
    int? offset;
    var fromStart = false;
    for (var i = 0; i < args.length; i++) {
      final a = args[i];
      if (a == '--lines' || a == '-n') {
        if (i + 1 >= args.length) {
          stderr.writeln('cockpit: --lines requires a value');
          exit(2);
        }
        lines = _intValue('--lines', args[++i]);
      } else if (a.startsWith('--lines=')) {
        lines = _intValue('--lines', a.substring('--lines='.length));
      } else if (a == '--offset') {
        if (i + 1 >= args.length) {
          stderr.writeln('cockpit: --offset requires a value');
          exit(2);
        }
        offset = _intValue('--offset', args[++i]);
      } else if (a.startsWith('--offset=')) {
        offset = _intValue('--offset', a.substring('--offset='.length));
      } else if (a == '--from-start') {
        fromStart = true;
      } else if (a == '--tab-id' || a == '-t') {
        if (i + 1 >= args.length) {
          stderr.writeln('cockpit: --tab-id requires a value');
          exit(2);
        }
        tabId = args[++i];
      } else if (a.startsWith('--tab-id=')) {
        tabId = a.substring('--tab-id='.length);
      } else if (a == '--json') {
        json = true;
      } else if (a == '--force' || a == '-f') {
        force = true;
      } else if (a == '--') {
        positionals.addAll(args.sublist(i + 1));
        break;
      } else {
        positionals.add(a);
      }
    }
    return _Flags(positionals, tabId, json, force, lines, offset, fromStart);
  }
}

// ---- install-skill ----------------------------------------------------------

Future<void> _cmdInstallSkill(List<String> args) async {
  final parsed = _Flags.parse(args);
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  if (home == null || home.isEmpty) {
    stderr.writeln('cockpit: HOME not resolved');
    exit(1);
  }
  final dir = Directory('$home/.claude/skills/cockpit-cli');
  final file = File('${dir.path}/SKILL.md');
  if (await file.exists() && !parsed.force) {
    final current = await file.readAsString();
    if (current == _skillMarkdown) {
      stdout.writeln('cockpit: skill already installed (${file.path})');
      exit(0);
    }
  }
  await dir.create(recursive: true);
  await file.writeAsString(_skillMarkdown);
  stdout.writeln('cockpit: skill installed at ${file.path}');
  exit(0);
}

// ---- help -------------------------------------------------------------------

void _printHelp(IOSink out) {
  out.writeln(
    r'''cockpit — Cockpit's internal CLI (visible only inside the app's terminals)

A **tab** is a terminal/agent session (what this CLI addresses). A **pane** is
the split leaf that groups tabs — not addressed here. `list-panes`/`read-pane`
are legacy aliases of `list-tabs`/`read-tab`.

USAGE:
  cockpit send      [--tab-id <id>] <text>     type literal text (no Enter)
  cockpit send-key  [--tab-id <id>] <Key>...   press named key(s)
  cockpit open      [--tab-id <id>] <file>     open the file in the app's viewer
  cockpit <file>                               shortcut for `open` (e.g. cockpit .zprofile)
  cockpit read-tab  [<label|tab-id>]           read a tab's rendered output (alias: read-pane)
  cockpit read-task <task-id>                  read a task's output (even w/o tab)
  cockpit list-tabs       [--json]             list active tabs (alias: list-panes)
  cockpit list-workspaces [--json]             list workspaces (projects)
  cockpit install-skill   [--force]            install the Claude Code skill
  cockpit --help | --version

READ (read-tab / read-task):
  --lines N     how many lines (default 100, server cap 2000)
  --offset N    skip N lines from the anchor (pagination)
  --from-start  anchor at the start of the buffer (default: tail/end)
  Output is always chronological (top→bottom); flags only pick the window.
  read-tab without a target reads the CURRENT tab; a target may be a stable
  tab label or a tab-id.

TARGET:
  --tab-id <id>   target tab. Default = $COCKPIT_TAB_ID (the current tab;
                  legacy fallback $COCKPIT_PANE_ID). Ids (t0, t1…) reset on every
                  app boot → find them with `cockpit list-tabs` before targeting
                  another tab (cross-tab).

KEYS (send-key):
  Enter Tab Escape Space BSpace Up Down Left Right Home End
  PageUp PageDown Delete   |   C-<letter> (e.g. C-c = Ctrl+C)

EXAMPLES:
  cockpit send "echo hi" && cockpit send-key Enter
  cockpit send-key C-c
  cockpit send --tab-id t3 "ls" ; cockpit send-key --tab-id t3 Enter
  cockpit .zprofile          # opens the file in the viewer (relative to tab cwd)
  cockpit open ~/.gitconfig
  cockpit read-tab Extension --lines 50        # last 50 lines of tab "Extension"
  cockpit read-tab t4 --lines 200 --from-start
  cockpit read-task test --lines 80            # tail of task "test" output''',
  );
}

String _pad(String? s, int n) {
  final v = s ?? '';
  return v.length >= n ? v : v + ' ' * (n - v.length);
}

// ---- conteúdo da skill (versiona junto com o binário) -----------------------

const String _skillMarkdown = r'''---
name: cockpit-cli
description: Drive Cockpit's multiplexed terminals from inside a tab. Use when you (an agent running in a Cockpit terminal) need to type text or press keys into your own or another tab, read another tab's or a task's output, or list the open tabs/workspaces. Triggers on tmux-like control needs: send-keys, run a command in another tab, read a tab's scrollback, inspect a task run's output, discover tab ids.
---

# cockpit — Cockpit's internal CLI

You are running inside a **Cockpit** terminal (an IDE that multiplexes
terminals). The `cockpit` command talks to the app and lets you **inject
text/keys** into any tab and **list** tabs/workspaces. It only exists inside
Cockpit tabs (it is not on the global PATH).

> **Tab vs pane.** A **tab** is a single terminal/agent session — that's the
> unit this CLI addresses (`--tab-id`). A **pane** is the split leaf that can
> hold several tabs; the CLI does not address it. `list-panes`/`read-pane` and
> `$COCKPIT_PANE_ID` are **legacy aliases** of `list-tabs`/`read-tab`/
> `$COCKPIT_TAB_ID` — prefer the new names.

## Verbs

- `cockpit send [--tab-id <id>] <text>` — type literal text (no Enter).
- `cockpit send-key [--tab-id <id>] <Key>...` — press key(s): `Enter`, `Tab`,
  `Escape`, `Space`, `BSpace`, `Up`/`Down`/`Left`/`Right`, `Home`/`End`,
  `PageUp`/`PageDown`, `Delete`, and `C-<letter>` (e.g. `C-c` = Ctrl+C).
- `cockpit open [--tab-id <id>] <file>` — open the file in the app's viewer
  (tab next to the terminal). `cockpit <file>` is the shortcut. The path is
  resolved against the tab cwd (relative, `~` and absolute all work). Any type
  opens as text — including extensionless ones (`.zprofile`, `Makefile`).
- `cockpit read-tab [<label|tab-id>] [--lines N] [--offset N] [--from-start]`
  (alias: `read-pane`) — read a tab's **rendered output** as plain text (no
  ANSI escapes; covers TUIs on the alt-screen too). Without a target it reads
  your **own** tab; a target may be a stable tab `label` or a tab-id. Default
  window: the **last 100 lines** (tail). `--lines N` sets the window size
  (server cap 2000); `--from-start` anchors at the beginning of the buffer
  instead of the end; `--offset N` skips N lines from the chosen anchor
  (pagination: read the last 100, then `--lines 100 --offset 100` for the 100
  before those). Output is always chronological (top→bottom) — the flags only
  pick the window.
- `cockpit read-task <task-id> [--lines N] [--offset N] [--from-start]` — same
  windowed read, but for a **task run's** output (the Task Run feature). Works
  even if no task-output tab is open. The task id is the task's `key`/id (e.g.
  from `.cockpit/tasks.json` or the task list in the UI).
- `cockpit list-tabs [--json]` (alias: `list-panes`) — active tabs: `id`,
  `kind`, `title` (dynamic), `label` (manual stable name, or null),
  `workspaceId`, `working`. Resolve a tab by its stable `label`, not the
  dynamic `title`.
- `cockpit list-workspaces [--json]` — open projects: `id`, `name`, `tabs`.

## Target (--tab-id)

Without `--tab-id`, the command acts on **your own tab** (via `$COCKPIT_TAB_ID`,
legacy fallback `$COCKPIT_PANE_ID`). To drive **another** tab, pass
`--tab-id <id>`.

> Ids (`t0`, `t1`…) are sequential and **change on every app boot**. Never
> guess an id: run `cockpit list-tabs` first and use the `id` from there.

## Usage pattern

To run a command in a tab, **send the text and then Enter** (`send` does not
add a line break):

```sh
cockpit send "npm test"
cockpit send-key Enter
```

Cross-tab (drive another tab):

```sh
cockpit list-tabs                        # find the target id, e.g. t4
cockpit send --tab-id t4 "git status"
cockpit send-key --tab-id t4 Enter
```

Interrupt a stuck process in another tab:

```sh
cockpit send-key --tab-id t4 C-c
```

Read what another tab printed (e.g. check on a worker, debug a failure):

```sh
cockpit read-tab t4 --lines 50            # last 50 lines of t4
cockpit read-tab Extension                # by stable label (last 100 lines)
cockpit read-tab t4 --lines 100 --offset 100   # the 100 lines before those
cockpit read-task test --lines 80         # tail of task "test" output
```

Typical loop — dispatch work to a tab, wait, then read the result:

```sh
cockpit send --tab-id t4 "npm test" && cockpit send-key --tab-id t4 Enter
# poll `cockpit list-tabs --json` until t4 shows "working": false, then:
cockpit read-tab t4 --lines 60
```

## Common errors

- "COCKPIT_STATUS_SOCK is unset" → you are not inside a Cockpit terminal.
- "tab ... does not exist" → stale id (app reboot). Run `list-tabs` again.
- "tab ... is not a terminal" → the target is an agent/file tab, not a shell.
- "has no readable output" → read-tab target is an agent/file tab; only
  terminal and task-output tabs are readable.
- "no output recorded for task ..." → the task never ran this app boot (or the
  id is wrong).
''';
