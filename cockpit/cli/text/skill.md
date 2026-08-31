---
name: cockpit-cli
description: Drive Cockpit's multiplexed terminals from inside a tab. Use when you (an agent running in a Cockpit terminal) need to open a new terminal tab or split pane, type text or press keys into your own or another tab, read another tab's or a task's output, list the open tabs/workspaces/tasks, query the workspace's databases (SQL over registered connections / .dbq files), or drive the built-in browser tab (read/click/type/screenshot/eval on a page). Triggers on tmux-like control needs — split-window/new-window, send-keys, run a command in another tab, read a tab's scrollback, inspect a task run's output, discover tab or task ids — on database needs: run a SQL query, inspect a schema, list connections, execute a .dbq file — and on browser needs: fill and submit a form, click a link/button, read what's on a page, take a screenshot, run arbitrary JS against a page. Also covers pane-layout orchestration: applying a `.ckp` layout file (open several terminals/splits and run their commands) via `cockpit orchestrate`.
---

# cockpit — Cockpit's internal CLI

You are running inside a **Cockpit** terminal (an IDE that multiplexes
terminals). The `cockpit` command talks to the app and lets you **inject
text/keys** into any tab and **list** tabs/workspaces. It only exists inside
Cockpit tabs (it is not on the global PATH).

`ck` is the same binary under a shorter name — use whichever you prefer
(`ck list-tabs` == `cockpit list-tabs`). Every example below works with both.

> **Tab vs pane.** A **tab** is a single terminal/agent session — that's the
> unit this CLI addresses (`--tab-id`). A **pane** is the split leaf that can
> hold several tabs; the CLI does not address it. `list-panes`/`read-pane` and
> `$COCKPIT_PANE_ID` are **legacy aliases** of `list-tabs`/`read-tab`/
> `$COCKPIT_TAB_ID` — prefer the new names.

## Verbs

- `cockpit send [--tab-id <id>] [--enter] <text>` — type literal text; add
  `--enter` to submit it (equivalent to a `send-key Enter` right after).
  `--focused` targets whichever tab the human is looking at (the app resolves
  it) — meant for tools driven by the human, not for agent orchestration, where
  an explicit `--tab-id` is what keeps you from typing into the wrong tab.
- `cockpit send-key [--tab-id <id>] <Key>...` — press key(s): `Enter`, `Tab`,
  `Escape`, `Space`, `BSpace`, `Up`/`Down`/`Left`/`Right`, `Home`/`End`,
  `PageUp`/`PageDown`, `Delete`, and `C-<letter>` (e.g. `C-c` = Ctrl+C).
- `cockpit new-tab [--cwd <dir>] [--title <name>] [--split h|v]` — open a new
  **terminal tab** in the app and print its id (`t12`). `--cwd` defaults to
  your current directory; `--title` sets the stable tab label (so `send`/
  `read-tab` can target it by name). Without `--split` the tab opens in the
  same pane (next to yours); `--split h` (or `right`) splits side by side,
  `--split v` (or `down`) stacks — tmux semantics. Capture the id to drive it:

  ```sh
  id=$(cockpit new-tab --cwd ~/proj --title Worker --split h)
  cockpit send --tab-id "$id" --enter "npm test"
  ```
- `cockpit close-tab [<label|tab-id>]` — close a tab and print its id: the
  counterpart of `new-tab`. **Without a target it closes YOUR OWN tab**, which
  ends the shell you are typing in — pass the target explicitly unless that is
  what you mean. Closing the last tab of a split removes the split; closing the
  last tab of a workspace leaves an empty tab behind (same as the tab's "x").

  ```sh
  id=$(cockpit new-tab --cwd ~/proj --title Worker)
  cockpit close-tab "$id"     # or: cockpit close-tab Worker
  ```
- `cockpit open [--tab-id <id>] <file>` — open the file in the app's viewer
  (tab next to the terminal). `cockpit <file>` is the shortcut. The path is
  resolved against the tab cwd (relative, `~` and absolute all work). Any type
  opens as text — including extensionless ones (`.zprofile`, `Makefile`).
- `cockpit browse <url> [--json]` — open the app's built-in **browser tab** at
  `<url>` (e.g. a dev server you just started: `cockpit browse
  http://localhost:3000`). A browser tab already open on the same host:port is
  reused (it navigates/reloads instead of duplicating). Schemeless URLs get
  `http://` for localhost targets and `https://` otherwise. On platforms
  without an inline webview (Linux) the URL opens in the system browser —
  `--json` output tells you which happened: `{"mode":"inline"|"system","url":…}`.
  To then **read or interact with** what's on that tab (click, type, screenshot,
  run JS), see `cockpit browser …` below.
- `cockpit db <list|schema|query|run|execute>` — query the workspace's
  databases. Connections are registered in `.cockpit/databases.json` (Database
  panel); SQLite files in the repo are auto-detected. Output is **one JSON
  line**: `{"ok":{columns,rows,rowCount,truncated,elapsedMs}}` or
  `{"error":{kind,message}}` (exit 1). The app executes everything — you never
  see credentials. Examples:
  - `cockpit db list` — available connections (name, engine, target).
  - `cockpit db schema --db dev-local` / `… --db dev-local orders` — tables /
    columns of a table.
  - `cockpit db query --db dev-local --sql "SELECT …" [--limit N]` — rows are
    arrays (column order matches `columns`); `truncated: true` means the limit
    cut the cursor — raise `--limit` if you need more.
  - `cockpit db execute --db dev-local --sql "UPDATE …"` — returns
    `affectedRows`. **Connections are read-only for agents by default**: any
    write is rejected with kind `read_only_connection` until the human enables
    "Allow writes (agents)" on the connection in the Database panel — if you
    hit it, ask the human instead of working around it. `db list` shows each
    connection's `access` field (`read` | `readwrite`).
  - `cockpit db run <file.dbq>` — runs a `.dbq` file (SQL with `-- db:` /
    `-- limit:` comment frontmatter). Prefer writing a `.dbq` when the human
    should see the result too: the app shows it as a query tab and re-runs it
    every time you save the file.
  - Outside a Cockpit tab, add `--workspace <id|path>`.
- `cockpit http <list|run> <file.http>` — runs HTTP requests written in a
  `.http` file (REST Client / JetBrains HTTP Client syntax: `###` separates
  requests, `@name = value` declares a variable, `{{name}}` interpolates it).
  - `cockpit http list api/users.http` — the requests in the file, with their
    index, name, method and URL.
  - `cockpit http run api/users.http [--request <name|index>]` — runs one
    (default: the first). Output is one JSON line: `{"ok":{"status":200,
    "headers":{…},"elapsedMs":12,"json":{…}}}`; the body comes back as `json`
    when it parses as JSON, otherwise as `body`. A 4xx/5xx is a normal
    response — check `status`, not the exit code.
  - Prefer writing a `.http` when the human should see the request too: the app
    renders the same file as a request tab (editor + response), so they can
    re-run and tweak it themselves.
  - Outside a Cockpit tab, add `--workspace <id|path>`.
- `cockpit redis --db <conn> <CMD> [args...]` — Redis/cache command. One
  JSON line reply. e.g. `cockpit redis --db cache HGETALL user:42`. Covers
  Redis/Valkey/KeyDB.
- `cockpit mongo --db <conn> [--database <name>] --command '<json>'` — MongoDB
  runCommand. The command is a runCommand document, e.g.
  `cockpit mongo --db app --command '{"find":"users","filter":{"active":true}}'`.
  Output: one JSON line `{"ok": <reply>}` / `{"error":{kind,message}}`.
  Documents use relaxed extended JSON (`{"$oid":…}`, `{"$date":…}`) both ways.
  - **Which database it runs against**: the one in the connection URL's path,
    if it has one; otherwise the one the human picked in the Database panel;
    otherwise the command fails and the error lists the databases available.
    `--database <name>` overrides all of it **for that call only** — it never
    changes what the human is looking at, so prefer it whenever you are not
    sure. Atlas URLs (`mongodb+srv://…/?…`) carry no database, so a connection
    can legitimately have none until someone picks one.
  - Discover databases with `--command '{"listDatabases":1}'` (routed to
    `admin` for you — that is the only database the server accepts it on), then
    collections with
    `--database <name> --command '{"listCollections":1,"nameOnly":true}'`.
    Running `listCollections` without knowing the database is the classic
    mistake: you get `system.users`/`system.roles`/`system.version` back, which
    is the `admin` database answering — not an empty deployment.
- **Browse commands open a view for the human — they return no data.** Use
  them to *show* what you found (after investigating with the commands above),
  not to query:
  - `cockpit redis browse --db <conn> [--pattern 'user:*']` — opens the
    editable Redis key table, pre-filtered. On an already-open table the
    pattern **replaces** the current filter.
  - `cockpit mongo browse --db <conn> [--database <name>] <collection>
    [--filter '<json>']` — here `--database` **does** change the connection's
    current database, because the tab you open becomes what the human sees —
    opens the Mongo collection browser (JSON document cards) pre-filtered.
    The filter lands in the visible filter bar, editable by the human.
- **Registering a connection** (`.cockpit/databases.json` at the workspace
  root — the file behind `cockpit db list` and the Database panel):

  ```json
  {
    "databases": [
      {"name": "dev-local", "url": "sqlite:./app.db", "savePassword": false},
      {"name": "app", "url": "postgres://user@localhost:5432/appdb", "savePassword": false},
      {"name": "cache", "url": "redis://localhost:6379/0", "savePassword": false},
      {"name": "docs", "url": "mongodb://localhost:27017/appdb", "savePassword": false}
    ]
  }
  ```

  The URL never carries the password — the human enters it in the Database
  panel (stored in the OS keychain when `savePassword` is on). A personal,
  gitignored overlay lives in `.cockpit/databases.local.json` (same shape,
  merged on top by name). The panel picks up edits on reload; `cockpit db
  list` confirms what's registered.
- **Connecting through a bastion (SSH tunnel)** — a connection may carry an
  optional `ssh` block. The app opens the tunnel and points the driver at a
  local port; every `cockpit db|redis|mongo` command works unchanged.

  ```json
  {
    "databases": [
      {
        "name": "prod",
        "url": "postgres://appuser@localhost:5432/appdb",
        "savePassword": true,
        "ssh": {
          "host": "bastion.acme.dev",
          "port": 22,
          "user": "deploy",
          "keyPath": "~/.ssh/id_ed25519",
          "savePassphrase": false
        }
      }
    ]
  }
  ```

  With a tunnel, the database `host`/`port` are resolved **from the SSH
  server** — `localhost` means the bastion itself, not your machine.
  Authentication is **key only**; the block never holds a secret (the
  passphrase, when the key has one, lives in the OS keychain).

  **Agents need the credential pre-saved.** If the key is passphrase-protected
  and the human hasn't enabled "Save passphrase" on the connection, your
  command fails fast with kind `ssh_credential_required` — there is no prompt
  on the CLI path. Ask the human to enable it rather than working around it.
  Other SSH failures come back as `ssh_host_key_unknown` (first connection
  must be approved once in the UI), `ssh_host_key_changed`, `ssh_auth_failed`,
  `ssh_key_missing` and `ssh_connect_failed`.

  **How the tunnel routes**, which matters when you read a failure: SQL engines
  and Redis go through a local **port forward** (they speak to one address).
  MongoDB goes through a local **SOCKS5 proxy** instead, because the driver
  discovers replica set members via `hello` and then dials the hostnames the
  server announces — a fixed local port would only ever reach the first node,
  and `mongodb+srv://` not even that. With SOCKS the driver picks each
  destination and the tunnel just routes, so Atlas/SRV and replica sets work
  unchanged. This requires a MongoDB driver built with SOCKS5 support; without
  it the driver rejects `proxyHost` loudly rather than connecting directly.
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
  even if no task-output tab is open, but only for tasks that ran this boot.
  Discover ids with `cockpit list-tasks` (never guess them).
- `cockpit list-tasks [--json]` — tasks of **your workspace** (the one owning
  the current tab, or `--tab-id`'s): `id`, `label`, `kind` (watch|oneShot),
  `source` (detected|manual), `running`, `hasOutput` (`read-task` has output
  to read). Ids are stable per workspace: `npm:<script>` (package.json
  scripts), `flutter:run`/`flutter:test`, `json:<label>`
  (`.cockpit/tasks.json`).
- `cockpit list-tabs [--json]` (alias: `list-panes`) — active tabs: `id`,
  `kind` (terminal|agent|file|task), `title` (dynamic), `label` (manual stable
  name, or null), `workspaceId` (opaque UUID), `workspacePath` (workspace root
  on disk), `working`, and `taskId` on task-output tabs (the id `read-task`
  accepts). Resolve a tab by its stable `label`, not the dynamic `title`.
- `cockpit list-workspaces [--json]` — open projects: `id` (opaque UUID),
  `name`, `path` (root on disk), `tabs`.
- `cockpit orchestrate <file.ckp> [--json]` — apply a **pane layout** to the
  current workspace: opens the terminals/splits declared in the file and types
  each pane's `command`. Idempotent merge: a pane whose `name` already exists
  as a tab label is skipped (running it twice is a no-op). Prints
  `created:`/`skipped:` (or `{"created":[],"skipped":[]}` with `--json`).

## Layout files (`*.ckp`)

A `.ckp` file is a versionable YAML describing terminals to open in a
workspace — the Cockpit equivalent of a tmuxinator layout. One file = one
layout; the layout takes the file's name.

```yaml
# dev.ckp — lives anywhere in the project (usually the root)
autorun: worktree        # optional: auto-apply when a worktree of this
                         # workspace is created (the only autorun trigger)
panes:
  - name: Frontend       # required, unique; becomes the tab's stable label
    cwd: frontend        # relative to this file, forward slashes ONLY
    command: claude      # optional; typed into the shell after it boots
  - name: Backend
    cwd: backend
    split: right         # tab (default) | right (side by side) | down (stack)
    command: npm run dev
    platforms: [macos, linux]   # optional; omit = all OSes
```

Rules:
- `cwd` must be **relative** with `/` separators — absolute paths and `\`
  are rejected so the same committed file works on macOS, Linux and Windows.
- `split` is relative to the **previous pane created in this run**; if that
  one was skipped (merge), the next opens as a plain tab.
- `platforms` accepts a string or list of `macos`/`windows`/`linux`.
- In the app, right-click a `.ckp` file → **Open layout** does the same as
  `cockpit orchestrate`.

## Browser control (`cockpit browser`)

Once a browser tab is open (`cockpit browse <url>`), `cockpit browser
<read|click|type|screenshot|eval>` reads and drives it — the Cockpit
equivalent of a browser-automation extension, but for the app's **built-in**
webview. Mechanism: injected JavaScript (`evaluateJavascript`), not the
Chrome DevTools Protocol — WKWebView (macOS) has no public automation
protocol. Consequence: synthetic clicks/inputs are **not** `isTrusted:
true` — works on the overwhelming majority of sites, but won't fool an
explicit `event.isTrusted` check.

Targets the workspace's **single** open browser tab by default (the normal
case). If more than one is open, pass `--tab-id <id>` (find it with
`cockpit list-tabs` — browser tabs have `"kind":"browser"`).

- `cockpit browser read [--full]` — lists visible interactive elements
  (links, buttons, inputs, textareas, selects, `[role=button]`, `[onclick]`,
  `[tabindex]`) as one JSON line:
  `{"ok":[{"id":"1-3","role":"textbox","text":"Email","rect":{...}},...]}`.
  `role` comes from an explicit `role=` attribute or is inferred from the
  tag. `--full` also includes hidden/off-screen elements (debugging only —
  you can't usefully click something the user can't see).

  **Ids are ephemeral**: an id is only valid against the `read` that
  produced it. Read again after any navigation, or after a `click`/`type`
  that might have changed the page — reusing an old id fails with kind
  `stale_element_id`, not a silent no-op.
- `cockpit browser click <id>` — scrolls the element into view and
  dispatches a synthetic click.
- `cockpit browser type <id> <text>` — focuses the element and sets its
  value (`input`/`change` fired); works on `input`, `textarea` and
  `contenteditable`.
- `cockpit browser screenshot [--out <path>]` — without `--out`, prints the
  PNG as base64 (`{"ok":{"base64":"..."}}`); with `--out`, writes the PNG to
  `<path>` and prints it (`{"ok":{"path":"/abs/shot.png"}}`).
- `cockpit browser eval <js>` — escape hatch: runs `<js>` and returns the
  serializable result (`{"ok":<value>}`). Last resort — prefer
  `read`/`click`/`type`, which don't require you to hand-write a CSS
  selector against a page you haven't inspected.

Error kinds (`{"error":{"kind","message"}}`, exit 1): `no_browser_tab` (open
one first with `cockpit browse`), `tab_closed` (the tab was closed —
open/navigate again), `stale_element_id` (`read` again), `eval_failed`
(bad JS, or the page rejected it), `ambiguous_browser_tab` (more than one
browser tab open — pass `--tab-id`).

Fill and submit a form — the canonical chained flow (`read` → pick an id →
`click`/`type`):

```sh
cockpit browse http://localhost:3000/login
cockpit browser read
# {"ok":[{"id":"1-1","role":"textbox","text":"Email","rect":{...}},
#        {"id":"1-2","role":"textbox","text":"Password","rect":{...}},
#        {"id":"1-3","role":"button","text":"Sign in","rect":{...}}]}
cockpit browser type 1-1 "user@example.com"
cockpit browser type 1-2 "hunter2"
cockpit browser click 1-3
```

## Target (--tab-id)

Without `--tab-id`, the command acts on **your own tab** (via `$COCKPIT_TAB_ID`,
legacy fallback `$COCKPIT_PANE_ID`). To drive **another** tab, pass
`--tab-id <id>`.

> Ids (`t0`, `t1`…) are sequential and **change on every app boot**. Never
> guess an id: run `cockpit list-tabs` first and use the `id` from there.

## Usage pattern

To run a command in a tab, use `--enter` (the text alone is only typed, not
submitted):

```sh
cockpit send --enter "npm test"
```

`--enter` presses Enter as a separate keystroke right after the text, which is
what TUIs expect. The two-step form still works when you need to type something
and press a different key:

```sh
cockpit send "npm test"
cockpit send-key Enter
```

Cross-tab (drive another tab):

```sh
cockpit list-tabs                        # find the target id, e.g. t4
cockpit send --tab-id t4 --enter "git status"
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
```

Read a task run's output (dev server, build, test — the Task Run feature):

```sh
cockpit list-tasks                        # ids: ● = running, [output] = readable
cockpit read-task npm:dev --lines 80      # tail of the "npm:dev" task output
```

Typical loop — dispatch work to a tab, wait, then read the result:

```sh
cockpit send --tab-id t4 --enter "npm test"
# poll `cockpit list-tabs --json` until t4 shows "working": false, then:
cockpit read-tab t4 --lines 60
```

## Common errors

- "COCKPIT_STATUS_SOCK is unset" → you are not inside a Cockpit terminal.
- "tab ... does not exist" → stale id (app reboot). Run `list-tabs` again.
- "tab ... is not a terminal" → the target is an agent/file tab, not a shell.
- "has no readable output" → read-tab target is an agent/file tab; only
  terminal and task-output tabs are readable.
- "no output recorded for task ..." → the task never ran this app boot, or the
  id is wrong — check both with `cockpit list-tasks` (`[output]` = readable).
- `no_browser_tab` (`cockpit browser …`) → no browser tab open in this
  workspace; open one with `cockpit browse <url>` first.
- `stale_element_id` (`cockpit browser click|type`) → the id is from an old
  `read`, or the page navigated since. Run `cockpit browser read` again.
- `ambiguous_browser_tab` → more than one browser tab open; pass `--tab-id
  <id>` (see `cockpit list-tabs`, kind `"browser"`).
