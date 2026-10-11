---
name: cockpit-telemetry
description: Find out why something failed or what a process printed without reading terminals: Cockpit keeps a per-workspace store of errors (grouped by fingerprint), JSON logs and raw lines from every task and from any command run through `cockpit telemetry <cmd>`. Use when the task is debugging a failure, checking a test or build run, watching a dev server for a regression, or instrumenting a project's logging. Also covers the app's own errors (`--app`).
---

# cockpit telemetry — the error store

The app keeps a structured, per-workspace store of what the workspace's
processes print: errors grouped by fingerprint (type + normalized message +
first project frame), JSON log lines with their fields, and raw lines with a
guessed level. **Every task the app runs feeds it by default.** Anything you
run yourself enters it only through the wrapper.

### Rule of thumb

- If a task exists for what you want to run: `cockpit run-task <id>` (already
  observed). Otherwise **prefix the command**: `cockpit telemetry flutter test`,
  `cockpit telemetry --name api npm run dev`. Works from your own shell
  (pipes) and from a terminal tab (nested PTY, keys and colors preserved).
- Never `read-tab` thousands of lines when a run exists. The wrapper prints a
  summary line at exit; follow it:

  ```
  telemetry: run r_42 · 3 errors · 12 warnings · cockpit telemetry errors --run r_42
  ```

### The loop

```sh
cockpit telemetry flutter test            # run → summary line
cockpit telemetry errors --run r_42       # grouped cases, ids e_xxxx
cockpit telemetry show e_3f2a             # stack (project frames flagged), the
                                          # JSON log right before it, context lines
# fix the code, then either run again, or on a dev server with hot reload:
cockpit telemetry wait --fingerprint e_3f2a --absent 30s   # ok | hit | inconclusive
cockpit telemetry resolve e_3f2a --reason "off-by-one in CartService.add"
```

Useful filters: `--new` (never seen in earlier runs of the same command),
`--since-edit` (since the human's last editor save), `--since 10m`,
`--before ev_xxxx --window 5s`, `--project <root>`, `--text <words>`,
`--probe <name>`. Replies are capped: `"truncated": true` comes with a `hint`.
Human triage is respected: resolved/ignored cases are hidden unless you pass
`--include-resolved` / `--include-ignored`. A resolved case that comes back is
flagged `"regression": true`.

Permanent instrumentation of a project (JSON logger recipes per stack, message
shapes that group well, temporary probes, per-task opt-out): **read
`references/instrumentation.md`**.

### The app's own errors (`--app`)

The app is a source too: one run per boot ("Cockpit", `source: app`) holds
the errors its global handlers caught and the warnings its fallbacks emit.
When something in Cockpit itself misbehaves (a tab that would not restore, a
remote listing that came back empty, a slow spawn), look there before
guessing:

```sh
cockpit telemetry errors --app                # framework/async errors, grouped
cockpit telemetry logs --app --level warn     # fallbacks the app took
cockpit telemetry show e_xxxx --app
```

`--app` works with every query verb. The store only fills while
**Settings → General → Developer mode** is on (it is off by default); with
it on, performance metrics land in the same run and
`cockpit telemetry perf --app` prints P50/P95/max per metric.
