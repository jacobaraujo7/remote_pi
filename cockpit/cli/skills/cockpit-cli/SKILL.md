---
name: cockpit-cli
description: Drive Cockpit's terminal tabs from inside one. Use when you (an agent in a Cockpit terminal) need to open, split, type into, read or close tabs, run a shell line through the app (`cockpit exec`), start or read a task run, or list tabs and workspaces. Triggers on tmux-like needs (new window, send keys, read another tab's output, interrupt a stuck process) and on "where am I / what is open" questions. Databases, telemetry and the files the human reads (.panel, .kanban, .notebook, .ckp, .http) have their own skills: cockpit-db, cockpit-telemetry, cockpit-design.
---

# cockpit — Cockpit's internal CLI

You are running inside a **Cockpit** terminal (an IDE that multiplexes
terminals). The `cockpit` command talks to the app and lets you **inject
text/keys** into any tab, **read** what tabs and tasks printed, and **list**
tabs/workspaces. It only exists inside Cockpit tabs (it is not on the global
PATH). `ck` is the same binary under a shorter name.

> **Tab vs pane.** A **tab** is a single terminal/agent session, the unit this
> CLI addresses (`--tab-id`). A **pane** is the split leaf that holds tabs; the
> CLI does not address it. `list-panes`/`read-pane`/`$COCKPIT_PANE_ID` are
> legacy aliases of `list-tabs`/`read-tab`/`$COCKPIT_TAB_ID`.

## Verbs at a glance

| Verb | What |
|---|---|
| `send [--tab-id] [--enter] <text>` | type text; `--enter` submits |
| `send-key [--tab-id] <Key>...` | `Enter`, `Tab`, `Escape`, arrows, `C-c`... |
| `new-tab [--cwd] [--title] [--split h\|v]` | open a terminal tab, prints its id |
| `close-tab [<label\|id>]` | close a tab (**no target = your own tab**) |
| `open <file>` / `cockpit <file>` | open a file in the app's viewer |
| `exec [--cwd] [--timeout] [--json] -- <cmd>` | run a shell line through the app (on the host, in a remote workspace) |
| `browse <url>` | open the built-in browser tab |
| `read-tab [<label\|id>] [--lines N]` | a tab's rendered output, tail by default |
| `list-tasks` · `run-task` · `stop-task` · `restart-task` · `send-task-key` · `read-task` | drive and read the Tasks panel |
| `list-tabs` · `list-workspaces` | what is open (ids change every boot) |
| `new-workspace <path> [--host]` · `close-workspace` · `rename-workspace` | the rail |
| `orchestrate <file.ckp> [--append]` | apply a pane layout (format: cockpit-design, `references/ckp.md`) |
| `panel new --template <t> <file>` · `panel screenshot [<target>]` | scaffold a `.panel`, see it as a PNG (cockpit-design) |

Flags, output shapes and edge cases of every verb: **read `references/verbs.md`**
before using a verb for the first time.

Other skills, when the task is one of these:
- SQL / Redis / Mongo / `.dbq` / connections: **cockpit-db**.
- Errors, logs, "why did it fail", instrumenting a project: **cockpit-telemetry**.
- Writing a `.panel`, `.html`, `.kanban`, `.notebook`, `.ckp` or `.http` the
  human will open: **cockpit-design**.

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
