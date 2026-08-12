import type { Metadata } from "next";
import Link from "next/link";
import {
  DocsSection,
  DocsSubsection,
  InlineCode,
  DocsTable,
} from "@/components/docs-shell";
import { CodeBlock } from "@/components/code-block";
import { Callout } from "@/components/callout";
import { DocsToc, type TocItem } from "@/components/docs-toc";
import { RevealController } from "@/components/landing/reveal-controller";

export const metadata: Metadata = {
  title: "Cockpit reference",
  description:
    "Reference for Remote Pi Cockpit: the internal CLI, .ckp pane layouts, .cockpit/tasks.json Task Run, the theme format, agent turn status hooks, and databases.",
};

const GITHUB_URL = "https://github.com/jacobaraujo7/remote_pi";
const COCKPIT_DOCS =
  "https://github.com/jacobaraujo7/remote_pi/tree/main/cockpit/docs";
const THEME_SCHEMA =
  "https://raw.githubusercontent.com/jacobaraujo7/remote_pi/main/cockpit/docs/theme.schema.json";
const TASKS_SCHEMA =
  "https://github.com/jacobaraujo7/remote_pi/blob/main/cockpit/docs/tasks.schema.json";
const THEME_EXAMPLE =
  "https://github.com/jacobaraujo7/remote_pi/blob/main/cockpit/docs/theme.example.json";

const DOCS_TOC: TocItem[] = [
  { id: "install", label: "Install" },
  {
    id: "cli",
    label: <>The <InlineCode>cockpit</InlineCode> CLI</>,
    sub: [
      { id: "cli-targets", label: "Targets & ids" },
      { id: "cli-commands", label: "Command reference" },
      { id: "cli-read", label: "Reading output" },
    ],
  },
  {
    id: "layouts",
    label: <><InlineCode>.ckp</InlineCode> pane layouts</>,
    sub: [
      { id: "layouts-fields", label: "Fields" },
      { id: "layouts-merge", label: "Merge semantics" },
    ],
  },
  {
    id: "tasks",
    label: "Task Run",
    sub: [
      { id: "tasks-file", label: "tasks.json" },
      { id: "tasks-fields", label: "Fields" },
    ],
  },
  {
    id: "databases",
    label: "Databases",
  },
  {
    id: "themes",
    label: "Themes",
    sub: [
      { id: "themes-file", label: "Theme file" },
      { id: "themes-tokens", label: "Tokens" },
    ],
  },
  {
    id: "turn-status",
    label: "Agent turn status",
    sub: [
      { id: "turn-status-events", label: "Event mapping" },
      { id: "turn-status-resume", label: "Resuming a session" },
    ],
  },
  { id: "sounds", label: "Sounds & notifications" },
  { id: "language", label: "Language" },
  { id: "links", label: "Links" },
];

const CKP_EXAMPLE = `# dev.ckp — anywhere in the project; cwd is relative to this file
autorun: worktree        # optional
panes:
  - name: Frontend       # required, unique — becomes the tab's stable label
    cwd: frontend        # relative to this file, always with "/"
    command: claude      # optional: typed into the shell after the tab opens
  - name: Backend
    cwd: backend
    split: right         # tab (default) | right (side by side) | down (stacked)
    command: npm run dev
  - name: Sign
    cwd: .
    command: ./sign.sh
    platforms: [macos]   # optional: macos | windows | linux (string or list)`;

const TASKS_EXAMPLE = `{
  "tasks": [
    {
      "label": "run",
      "cwd": "app",                 // relative to the tasks.json folder
      "command": "flutter",
      "args": ["run"],
      "kind": "watch",
      "interactiveKeys": [
        { "key": "r", "label": "Hot reload", "icon": "refresh", "primary": true },
        { "key": "R", "label": "Hot restart", "icon": "restart", "primary": true },
        { "key": "q", "label": "Quit", "icon": "stop" }
      ],
      "watch": {
        "paths": ["lib", "assets"],
        "ignore": ["build", ".dart_tool"],
        "onChange": "Hot reload",   // an interactiveKey label, or "__restart__"
        "debounceMs": 300
      },
      "progressPatterns": [
        { "begin": "Performing hot reload", "end": "Reloaded .* in .*ms" }
      ],
      "profiles": [
        { "name": "default" },
        { "name": "web", "args": ["-d", "chrome"] }
      ]
    },
    {
      "label": "api",
      "cwd": "backend",             // monorepo: another subfolder
      "command": "dart",
      "args": ["run", "bin/server.dart"],
      "kind": "watch"
    }
  ]
}`;

const THEME_SHAPE = `{
  "$schema": "${THEME_SCHEMA}",
  "id": "acme.aurora",
  "name": "Aurora",
  "author": "Acme",
  "version": "1.0.0",
  "extends": "cockpit",
  "variants": {
    "dark":  { "ui": {}, "syntax": {}, "terminal": {} },
    "light": { "ui": {}, "syntax": {}, "terminal": {} }
  }
}`;

const THEME_MINIMAL = `{
  "$schema": "${THEME_SCHEMA}",
  "id": "acme.violet",
  "name": "Violet",
  "variants": {
    "dark":  { "ui": { "accent": "#8B5CF6", "accentSoft": "#8B5CF633", "accentText": "#C4B5FD" } },
    "light": { "ui": { "accent": "#7C3AED", "accentSoft": "#7C3AED22", "accentText": "#5B21B6" } }
  }
}`;

export default function CockpitDocsPage() {
  return (
    <div className="page">
      <div className="page-body">
        <div className="wrap">
          <header className="page-head reveal">
            <span className="eyebrow">Documentation · Cockpit</span>
            <h1>Cockpit reference</h1>
            <div className="meta-line">
              <span>Last updated: 2026-08-11</span>
              <span>License: MIT</span>
            </div>
            <p className="lede">
              Everything the desktop app reads from your repository or writes to
              your machine: the internal <InlineCode>cockpit</InlineCode> CLI
              that agents use to drive tabs, the{" "}
              <InlineCode>.ckp</InlineCode> pane layouts, the{" "}
              <InlineCode>.cockpit/tasks.json</InlineCode> Task Run file, the
              theme format, and the harness hooks behind the turn status. For
              the product tour, see the{" "}
              <Link href="/cockpit" className="text-accent underline">
                Cockpit page
              </Link>
              ; for the mesh, daemons, and the relay, see the{" "}
              <Link href="/docs" className="text-accent underline">
                Remote Pi docs
              </Link>
              .
            </p>
          </header>

          <div className="docs-layout">
            <DocsToc items={DOCS_TOC} />

            <article className="prose docs-article">
              {/* ── INSTALL ─────────────────────────────────────────────── */}

              <DocsSection id="install" title="Install">
                <p>
                  Cockpit ships for macOS, Windows, and Linux. macOS builds are
                  signed and notarized, and every platform that supports it gets
                  in-app updates. Grab a build from the{" "}
                  <Link href="/download" className="text-accent underline">
                    download page
                  </Link>{" "}
                  — <InlineCode>.dmg</InlineCode>,{" "}
                  <InlineCode>.exe</InlineCode>,{" "}
                  <InlineCode>.deb</InlineCode> and{" "}
                  <InlineCode>.rpm</InlineCode> (x64 and arm64), each with a
                  published SHA-256.
                </p>
                <p>
                  Cockpit is a terminal first: it needs no account, no cloud,
                  and no Remote Pi setup to be useful. The mesh, pairing, and
                  daemon features light up only once you install the{" "}
                  <InlineCode>remote-pi</InlineCode> extension described in the{" "}
                  <Link href="/docs#install" className="text-accent underline">
                    main docs
                  </Link>
                  .
                </p>
              </DocsSection>

              {/* ── CLI ─────────────────────────────────────────────────── */}

              <DocsSection id="cli" title="The cockpit CLI">
                <p>
                  Cockpit materializes a small binary at{" "}
                  <InlineCode>~/.cockpit/bin/cockpit</InlineCode> and puts that
                  folder on the <InlineCode>PATH</InlineCode> of the terminals
                  it spawns — and only those. So the CLI exists for anything
                  running inside Cockpit (you, a script, an agent) and does not
                  leak into the rest of your shell environment. It talks to the
                  app over a local socket: a Unix socket on macOS and Linux, a
                  loopback TCP port plus a token on Windows.
                </p>
                <p>
                  This is what makes Cockpit an <em>agentic</em> multiplexer:
                  an agent in one tab can open another tab, type into it, read
                  what it printed, run a project task, or query a database —
                  the same verbs a human uses, with no screen scraping.
                </p>

                <DocsSubsection id="cli-targets" title="Targets & ids">
                  <p>
                    The unit the CLI addresses is a <strong>tab</strong> (one
                    terminal or agent session). A <strong>pane</strong> is the
                    split leaf that groups tabs and is not addressable —{" "}
                    <InlineCode>list-panes</InlineCode> and{" "}
                    <InlineCode>read-pane</InlineCode> survive as legacy
                    aliases.
                  </p>
                  <DocsTable
                    headers={["Flag", "What it does"]}
                    rows={[
                      [
                        <InlineCode key="t">--tab-id &lt;id&gt;</InlineCode>,
                        <>
                          Target another tab. Defaults to{" "}
                          <InlineCode>$COCKPIT_TAB_ID</InlineCode> (the current
                          tab; legacy fallback{" "}
                          <InlineCode>$COCKPIT_PANE_ID</InlineCode>).
                        </>,
                      ],
                      [
                        <InlineCode key="f">--focused</InlineCode>,
                        <>
                          Target whatever tab you are looking at, resolved by
                          the app. Works from outside a Cockpit terminal too
                          (dictation tools, scripts): with no env inherited the
                          CLI finds the app through{" "}
                          <InlineCode>~/.cockpit/status.sock</InlineCode>. Wins
                          over <InlineCode>--tab-id</InlineCode>.
                        </>,
                      ],
                      [
                        <InlineCode key="e">--enter</InlineCode>,
                        <>
                          (<InlineCode>send</InlineCode> only) press Enter right
                          after the text, as a separate keystroke — a{" "}
                          <InlineCode>send</InlineCode> plus a{" "}
                          <InlineCode>send-key Enter</InlineCode> in one call.
                        </>,
                      ],
                    ]}
                  />
                  <Callout variant="warning" title="Tab ids reset on boot">
                    <p>
                      Ids (<InlineCode>t0</InlineCode>,{" "}
                      <InlineCode>t1</InlineCode>…) are assigned per app boot,
                      so never hardcode one. Discover them with{" "}
                      <InlineCode>cockpit list-tabs</InlineCode>, or give a tab
                      a <strong>stable label</strong> (double-click the tab, or{" "}
                      <InlineCode>new-tab --title</InlineCode>) and address it
                      by name. Labels persist across boots; workspace ids are
                      opaque UUIDs, so use <InlineCode>workspacePath</InlineCode>{" "}
                      / <InlineCode>path</InlineCode> when you need the folder
                      on disk.
                    </p>
                  </Callout>
                </DocsSubsection>

                <DocsSubsection id="cli-commands" title="Command reference">
                  <DocsTable
                    headers={["Command", "What it does"]}
                    rows={[
                      [
                        <InlineCode key="c">
                          send [--tab-id id] [--enter] &lt;text&gt;
                        </InlineCode>,
                        "Type text into a tab.",
                      ],
                      [
                        <InlineCode key="c">
                          send-key [--tab-id id] &lt;Key&gt;…
                        </InlineCode>,
                        <>
                          Press named keys:{" "}
                          <InlineCode>Enter Tab Escape Space BSpace Up Down
                          Left Right Home End PageUp PageDown Delete</InlineCode>{" "}
                          and <InlineCode>C-&lt;letter&gt;</InlineCode> (e.g.{" "}
                          <InlineCode>C-c</InlineCode>).
                        </>,
                      ],
                      [
                        <InlineCode key="c">open &lt;file&gt;</InlineCode>,
                        <>
                          Open a file in the app&apos;s viewer. Bare{" "}
                          <InlineCode>cockpit &lt;file&gt;</InlineCode> is a
                          shortcut for it, relative to the tab&apos;s cwd.
                        </>,
                      ],
                      [
                        <InlineCode key="c">
                          new-tab [--cwd dir] [--title name] [--split h|v]
                        </InlineCode>,
                        <>
                          Open a terminal tab and print its id.{" "}
                          <InlineCode>h</InlineCode>/<InlineCode>right</InlineCode>{" "}
                          splits side by side,{" "}
                          <InlineCode>v</InlineCode>/<InlineCode>down</InlineCode>{" "}
                          stacks; omit to open as a tab in the same pane.
                          Anchored at the emitting tab&apos;s pane.
                        </>,
                      ],
                      [
                        <InlineCode key="c">
                          read-tab [label|tab-id]
                        </InlineCode>,
                        <>
                          Read a tab&apos;s rendered output. No target = the
                          current tab. Alias:{" "}
                          <InlineCode>read-pane</InlineCode>.
                        </>,
                      ],
                      [
                        <InlineCode key="c">read-task &lt;task-id&gt;</InlineCode>,
                        "Read a task's output, even with no tab open for it.",
                      ],
                      [
                        <InlineCode key="c">list-tabs [--json]</InlineCode>,
                        <>
                          List active tabs (alias:{" "}
                          <InlineCode>list-panes</InlineCode>). The JSON carries{" "}
                          <InlineCode>label</InlineCode>,{" "}
                          <InlineCode>workspacePath</InlineCode>,{" "}
                          <InlineCode>working</InlineCode> and, for task output
                          tabs, <InlineCode>taskId</InlineCode>.
                        </>,
                      ],
                      [
                        <InlineCode key="c">list-workspaces [--json]</InlineCode>,
                        "List workspaces (projects) and their paths.",
                      ],
                      [
                        <InlineCode key="c">list-tasks [--json]</InlineCode>,
                        <>
                          List this workspace&apos;s tasks.{" "}
                          <InlineCode>[output]</InlineCode> marks tasks whose
                          output <InlineCode>read-task</InlineCode> can read
                          (ran this boot); ● marks tasks running right now.
                        </>,
                      ],
                      [
                        <InlineCode key="c">
                          db &lt;list|schema|query|run|execute&gt;
                        </InlineCode>,
                        <>
                          SQL databases registered in the workspace — see{" "}
                          <a href="#databases" className="text-accent underline">
                            Databases
                          </a>
                          .
                        </>,
                      ],
                      [
                        <InlineCode key="c">redis [browse] --db conn</InlineCode>,
                        "Run a Redis command, or open the key table for a human.",
                      ],
                      [
                        <InlineCode key="c">
                          mongo [browse] --db conn [--database name]
                        </InlineCode>,
                        "Run a MongoDB command, or open the collection browser.",
                      ],
                      [
                        <InlineCode key="c">
                          orchestrate &lt;file.ckp&gt; [--json]
                        </InlineCode>,
                        <>
                          Apply a pane layout — see{" "}
                          <a href="#layouts" className="text-accent underline">
                            <InlineCode>.ckp</InlineCode> layouts
                          </a>
                          .
                        </>,
                      ],
                      [
                        <InlineCode key="c">install-skill [--force]</InlineCode>,
                        "Install the Claude Code skill that teaches this CLI.",
                      ],
                    ]}
                  />
                  <CodeBlock
                    label="Cockpit terminal"
                    prompt
                    code={`# open a worker tab beside you, then drive it
id=$(cockpit new-tab --cwd ~/proj --title Worker --split h)
cockpit send --tab-id "$id" --enter "npm test"

# read what it printed
cockpit read-tab Worker --lines 50

# run and follow a project task
cockpit list-tasks
cockpit read-task npm:dev --lines 80

# open a file in the viewer, query a database
cockpit open ~/.gitconfig
cockpit db query --db dev-local --sql "SELECT * FROM orders LIMIT 5"`}
                  />
                </DocsSubsection>

                <DocsSubsection id="cli-read" title="Reading output">
                  <p>
                    <InlineCode>read-tab</InlineCode> and{" "}
                    <InlineCode>read-task</InlineCode> share a windowing model.
                    Output is always chronological (top to bottom); the flags
                    only pick which window you get.
                  </p>
                  <DocsTable
                    headers={["Flag", "Default", "What it does"]}
                    rows={[
                      [
                        <InlineCode key="l">--lines N</InlineCode>,
                        "100",
                        "How many lines to return (server cap: 2000).",
                      ],
                      [
                        <InlineCode key="o">--offset N</InlineCode>,
                        "0",
                        "Skip N lines from the anchor — this is your pagination.",
                      ],
                      [
                        <InlineCode key="s">--from-start</InlineCode>,
                        "off",
                        "Anchor at the start of the buffer instead of the tail.",
                      ],
                    ]}
                  />
                  <p>
                    Task ids are stable per workspace:{" "}
                    <InlineCode>npm:&lt;script&gt;</InlineCode> from{" "}
                    <InlineCode>package.json</InlineCode>,{" "}
                    <InlineCode>flutter:run</InlineCode> /{" "}
                    <InlineCode>flutter:test</InlineCode>, and{" "}
                    <InlineCode>json:&lt;label&gt;</InlineCode> from{" "}
                    <InlineCode>.cockpit/tasks.json</InlineCode>.
                  </p>
                </DocsSubsection>
              </DocsSection>

              {/* ── .ckp LAYOUTS ────────────────────────────────────────── */}

              <DocsSection id="layouts" title=".ckp pane layouts">
                <p>
                  A <InlineCode>.ckp</InlineCode> file is a versionable YAML
                  that describes the terminals to open in a workspace — the
                  equivalent of a tmuxinator layout. One file is one layout, and
                  the file name is the layout name (
                  <InlineCode>dev.ckp</InlineCode> → layout &ldquo;dev&rdquo;).
                  Commit it, and a teammate gets your working geometry on
                  clone.
                </p>
                <p>There are three ways to apply one:</p>
                <ul>
                  <li>
                    <strong>GUI</strong> — right-click the{" "}
                    <InlineCode>.ckp</InlineCode> file in the tree →{" "}
                    <strong>Open layout</strong>.
                  </li>
                  <li>
                    <strong>CLI</strong> —{" "}
                    <InlineCode>cockpit orchestrate dev.ckp</InlineCode> from
                    inside a tab.
                  </li>
                  <li>
                    <strong>Worktree autorun</strong> —{" "}
                    <InlineCode>autorun: worktree</InlineCode> in the file: the
                    layout is applied by itself whenever you create a worktree
                    of the workspace. The worktree is born empty, so the
                    geometry comes out exact.
                  </li>
                </ul>
                <CodeBlock label="dev.ckp" language="yaml" code={CKP_EXAMPLE} />

                <DocsSubsection id="layouts-fields" title="Fields">
                  <p>
                    <strong>Root:</strong> <InlineCode>panes</InlineCode>{" "}
                    (required) is the list of panes in creation order.{" "}
                    <InlineCode>autorun</InlineCode> (optional) accepts only{" "}
                    <InlineCode>worktree</InlineCode>; with two or more autorun
                    files at the root, none of them runs — ambiguity is never
                    guessed.
                  </p>
                  <DocsTable
                    headers={["Field", "Required", "Default", "Description"]}
                    rows={[
                      [
                        <InlineCode key="n">name</InlineCode>,
                        "yes",
                        "—",
                        "Unique (case-insensitive). Becomes the tab's manual label and the merge key.",
                      ],
                      [
                        <InlineCode key="c">cwd</InlineCode>,
                        "no",
                        <InlineCode key="d">.</InlineCode>,
                        <>
                          Relative to the file&apos;s folder, forward slashes
                          only. Absolute paths and{" "}
                          <InlineCode>\</InlineCode> are rejected for
                          portability.
                        </>,
                      ],
                      [
                        <InlineCode key="s">split</InlineCode>,
                        "no",
                        <InlineCode key="d">tab</InlineCode>,
                        <>
                          Where it is born, relative to the{" "}
                          <em>previously created</em> pane:{" "}
                          <InlineCode>tab</InlineCode>,{" "}
                          <InlineCode>right</InlineCode>,{" "}
                          <InlineCode>down</InlineCode>.
                        </>,
                      ],
                      [
                        <InlineCode key="cm">command</InlineCode>,
                        "no",
                        "—",
                        "Typed into the terminal and run by the tab's shell (resolved through the machine's PATH).",
                      ],
                      [
                        <InlineCode key="p">platforms</InlineCode>,
                        "no",
                        "all",
                        <>
                          <InlineCode>macos</InlineCode> /{" "}
                          <InlineCode>windows</InlineCode> /{" "}
                          <InlineCode>linux</InlineCode>, string or list — same
                          semantics as in <InlineCode>tasks.json</InlineCode>.
                        </>,
                      ],
                    ]}
                  />
                </DocsSubsection>

                <DocsSubsection id="layouts-merge" title="Merge semantics">
                  <ul>
                    <li>
                      A pane whose <InlineCode>name</InlineCode> already exists
                      as a tab label or title in the workspace is{" "}
                      <strong>skipped</strong> — applying a layout twice is a
                      no-op. Nothing is ever closed.
                    </li>
                    <li>
                      <InlineCode>split</InlineCode> anchors on the pane created
                      previously <em>in this run</em>; if that one was skipped
                      by the merge, the next opens as a plain tab. Perfect
                      geometry is guaranteed only in an empty workspace — which
                      is exactly the worktree autorun case.
                    </li>
                    <li>
                      A missing <InlineCode>cwd</InlineCode> or invalid YAML
                      gives a readable error (dialog in the GUI, stderr in the
                      CLI); nothing is applied halfway from the failing pane on.
                    </li>
                    <li>
                      <InlineCode>command</InlineCode> is typed ~700 ms after
                      the tab opens, so the shell has time to finish booting,
                      with Enter at the end.
                    </li>
                  </ul>
                  <p>
                    Cockpit treats <InlineCode>.ckp</InlineCode> as YAML for
                    highlighting and shows the Cockpit logo as the file icon in
                    the tree.
                  </p>
                </DocsSubsection>
              </DocsSection>

              {/* ── TASK RUN ────────────────────────────────────────────── */}

              <DocsSection id="tasks" title="Task Run">
                <p>
                  Task Run executes your project&apos;s build and dev commands (
                  <InlineCode>npm run dev</InlineCode>,{" "}
                  <InlineCode>flutter run</InlineCode>,{" "}
                  <InlineCode>go run</InlineCode>,{" "}
                  <InlineCode>make</InlineCode>…) with streamed output, a visual
                  lifecycle (play / stop / restart), interactive keys, and
                  reload-on-save. Two sources coexist:
                </p>
                <ul>
                  <li>
                    <strong>Auto-detected</strong> — on opening a project,
                    Cockpit reads the manifests (
                    <InlineCode>package.json</InlineCode> scripts,{" "}
                    <InlineCode>pubspec.yaml</InlineCode>) and shows tasks with
                    no config at all.
                  </li>
                  <li>
                    <strong>Declared</strong> —{" "}
                    <InlineCode>.cockpit/tasks.json</InlineCode>, for
                    customizing, adding tasks, or describing a monorepo. JSON
                    tasks take precedence over a detected task with the same
                    id.
                  </li>
                </ul>
                <Callout variant="note" title="The runner is generic">
                  <p>
                    It knows only <InlineCode>command</InlineCode>,{" "}
                    <InlineCode>args</InlineCode>, and{" "}
                    <InlineCode>env</InlineCode>. There are no stack-specific
                    keys (flavor, dart-define, <InlineCode>NODE_ENV</InlineCode>
                    ) — all of that is expressed as{" "}
                    <InlineCode>args</InlineCode> and{" "}
                    <InlineCode>env</InlineCode>.
                  </p>
                </Callout>

                <DocsSubsection id="tasks-file" title="Where the file lives">
                  <p>
                    At the <strong>root of the workspace you open</strong>.
                    Discovery is literal — Cockpit does not walk up the tree.
                    For a single package, open the package folder. For a{" "}
                    <strong>monorepo</strong>, open the root and let one{" "}
                    <InlineCode>.cockpit/tasks.json</InlineCode> drive the
                    subpackages through a per-task{" "}
                    <InlineCode>cwd</InlineCode>.
                  </p>
                  <p>
                    The file is <strong>JSONC</strong>: comments (
                    <InlineCode>{"//"}</InlineCode> and{" "}
                    <InlineCode>{"/* */"}</InlineCode>) and trailing commas are
                    allowed, just like VSCode&apos;s{" "}
                    <InlineCode>tasks.json</InlineCode>. Point{" "}
                    <InlineCode>$schema</InlineCode> at{" "}
                    <a
                      className="text-accent underline"
                      href={TASKS_SCHEMA}
                      target="_blank"
                      rel="noopener noreferrer"
                    >
                      <InlineCode>docs/tasks.schema.json</InlineCode>
                    </a>{" "}
                    for editor autocomplete; Cockpit ignores the field when
                    running.
                  </p>
                  <CodeBlock
                    label=".cockpit/tasks.json"
                    language="jsonc"
                    code={TASKS_EXAMPLE}
                  />
                </DocsSubsection>

                <DocsSubsection id="tasks-fields" title="Fields">
                  <p>
                    Root: <InlineCode>tasks</InlineCode> (required) and{" "}
                    <InlineCode>cwd</InlineCode> (optional) — a default{" "}
                    <InlineCode>cwd</InlineCode> for every task, which each task
                    may override.
                  </p>
                  <DocsTable
                    headers={["Field", "Required", "Default", "Description"]}
                    rows={[
                      [
                        <InlineCode key="l">label</InlineCode>,
                        "yes",
                        "—",
                        <>
                          Short display name. The task id is derived from it:{" "}
                          <InlineCode>json:&lt;label&gt;</InlineCode>.
                        </>,
                      ],
                      [
                        <InlineCode key="c">command</InlineCode>,
                        "yes",
                        "—",
                        "Base executable (npm, flutter, dart…).",
                      ],
                      [
                        <InlineCode key="a">args</InlineCode>,
                        "no",
                        <InlineCode key="d">[]</InlineCode>,
                        "Base args, placed before the profile's args.",
                      ],
                      [
                        <InlineCode key="w">cwd</InlineCode>,
                        "no",
                        "root",
                        <>
                          Run folder, relative to the{" "}
                          <InlineCode>tasks.json</InlineCode> folder (absolute
                          also accepted). Falls back to the top-level{" "}
                          <InlineCode>cwd</InlineCode>, then the root.
                        </>,
                      ],
                      [
                        <InlineCode key="p">platforms</InlineCode>,
                        "no",
                        "all",
                        <>
                          OSes where the task is visible:{" "}
                          <InlineCode>macos</InlineCode>,{" "}
                          <InlineCode>windows</InlineCode>,{" "}
                          <InlineCode>linux</InlineCode>.
                        </>,
                      ],
                      [
                        <InlineCode key="k">kind</InlineCode>,
                        "no",
                        <InlineCode key="d">oneShot</InlineCode>,
                        <>
                          <InlineCode>watch</InlineCode> (long-lived process,
                          e.g. a dev server) or{" "}
                          <InlineCode>oneShot</InlineCode> (runs and exits).
                        </>,
                      ],
                      [
                        <InlineCode key="i">interactiveKeys</InlineCode>,
                        "no",
                        <InlineCode key="d">[]</InlineCode>,
                        <>
                          Buttons that write to the process&apos; stdin:{" "}
                          <InlineCode>key</InlineCode>,{" "}
                          <InlineCode>label</InlineCode>, optional{" "}
                          <InlineCode>icon</InlineCode> (
                          <InlineCode>refresh</InlineCode>,{" "}
                          <InlineCode>restart</InlineCode>,{" "}
                          <InlineCode>stop</InlineCode>,{" "}
                          <InlineCode>bolt</InlineCode>) and{" "}
                          <InlineCode>primary</InlineCode>.
                        </>,
                      ],
                      [
                        <InlineCode key="wa">watch</InlineCode>,
                        "no",
                        <InlineCode key="d">null</InlineCode>,
                        <>
                          Reload on save:{" "}
                          <InlineCode>paths</InlineCode>,{" "}
                          <InlineCode>ignore</InlineCode>,{" "}
                          <InlineCode>onChange</InlineCode> (required — an{" "}
                          <InlineCode>interactiveKeys</InlineCode> label or{" "}
                          <InlineCode>&quot;__restart__&quot;</InlineCode>) and{" "}
                          <InlineCode>debounceMs</InlineCode> (300). Leave it
                          out for tools that already watch (Vite, Next).
                        </>,
                      ],
                      [
                        <InlineCode key="pp">progressPatterns</InlineCode>,
                        "no",
                        <InlineCode key="d">[]</InlineCode>,
                        <>
                          <InlineCode>begin</InlineCode> /{" "}
                          <InlineCode>end</InlineCode> regexes that swing the
                          badge between <em>building</em> and <em>running</em>.
                        </>,
                      ],
                      [
                        <InlineCode key="pr">profiles</InlineCode>,
                        "no",
                        <InlineCode key="d">[]</InlineCode>,
                        <>
                          Named run variants (launch configs):{" "}
                          <InlineCode>name</InlineCode>, extra{" "}
                          <InlineCode>args</InlineCode> appended after the
                          task&apos;s, and <InlineCode>env</InlineCode> merged
                          into the process environment. A chip cycles them
                          before you hit play.
                        </>,
                      ],
                    ]}
                  />
                  <Callout variant="warning" title="Two known limits">
                    <p>
                      For an argument value containing spaces, use{" "}
                      <strong>separate items</strong> in{" "}
                      <InlineCode>args</InlineCode> (
                      <InlineCode>
                        [&quot;--dart-define&quot;, &quot;MSG=hello
                        world&quot;]
                      </InlineCode>
                      ). And the output tab does not survive an app restart —
                      the task dies with it.
                    </p>
                  </Callout>
                </DocsSubsection>
              </DocsSection>

              {/* ── DATABASES ───────────────────────────────────────────── */}

              <DocsSection id="databases" title="Databases">
                <p>
                  Connections live per workspace in{" "}
                  <InlineCode>.cockpit/databases.json</InlineCode>, plus any
                  SQLite files Cockpit auto-detects in the project. SQLite,
                  Postgres, MySQL, SQL Server, Redis, and MongoDB open as tabs:
                  a table view for SQL and Redis, a collection browser for
                  MongoDB. A <InlineCode>.dbq</InlineCode> file is a saved query
                  you can commit and re-run.
                </p>
                <p>
                  The same connections are reachable from the CLI, and the
                  output is <strong>one JSON line</strong> — built to be parsed
                  by an agent, not read by a human.
                </p>
                <CodeBlock
                  label="Cockpit terminal"
                  prompt
                  code={`cockpit db list
cockpit db schema --db dev-local orders
cockpit db query --db dev-local --sql "SELECT * FROM orders LIMIT 5"
cockpit db run reports/daily.dbq

# non-SQL engines have their own verbs
cockpit redis --db cache --command "SCAN 0 COUNT 20"
cockpit mongo --db atlas --database shop --command '{"find":"orders","limit":5}'

# open the same thing visually for a human
cockpit redis browse --db cache
cockpit mongo browse --db atlas --database shop`}
                />
                <Callout variant="note" title="Per-connection guardrails">
                  <p>
                    Each connection carries an{" "}
                    <InlineCode>access</InlineCode> level (
                    <InlineCode>read</InlineCode> — the default, including for
                    connections created before the field existed — or{" "}
                    <InlineCode>readwrite</InlineCode>) and an{" "}
                    <InlineCode>agents</InlineCode> flag. A connection with{" "}
                    <InlineCode>agents: false</InlineCode> is invisible to the
                    CLI. The gates are enforced on the CLI surface: what you do
                    by hand in the GUI is never blocked, but what an agent can
                    reach is yours to decide. Run{" "}
                    <InlineCode>cockpit db --help</InlineCode> for the full
                    surface.
                  </p>
                </Callout>
              </DocsSection>

              {/* ── THEMES ──────────────────────────────────────────────── */}

              <DocsSection id="themes" title="Themes">
                <p>
                  Cockpit ships nine built-in themes —{" "}
                  <InlineCode>cockpit</InlineCode>,{" "}
                  <InlineCode>cockpit.2</InlineCode>,{" "}
                  <InlineCode>violet</InlineCode>,{" "}
                  <InlineCode>violet.2</InlineCode>,{" "}
                  <InlineCode>midnight</InlineCode>,{" "}
                  <InlineCode>rose</InlineCode>, <InlineCode>sun</InlineCode>,{" "}
                  <InlineCode>flexoki</InlineCode> and{" "}
                  <InlineCode>pantera</InlineCode> — each with a light and a
                  dark variant. Beyond those, a theme is{" "}
                  <strong>a single JSON file</strong> that paints all three
                  layers at once: the app UI, the code viewer&apos;s syntax
                  highlighting, and the terminal palette.
                </p>

                <DocsSubsection id="themes-file" title="The theme file">
                  <ul>
                    <li>
                      Import with <strong>Settings → Appearance → Theme →
                      Import…</strong>
                    </li>
                    <li>
                      Themes live in{" "}
                      <InlineCode>&lt;data folder&gt;/themes/</InlineCode> (the
                      same root as the &ldquo;Storage&rdquo; setting), one file
                      per theme, named after its <InlineCode>id</InlineCode>.
                      Copying a <InlineCode>.json</InlineCode> in there installs
                      it too.
                    </li>
                    <li>
                      Export produces a <strong>complete</strong> file (every
                      token, no <InlineCode>extends</InlineCode>) — a good
                      starting point for hand editing.
                    </li>
                  </ul>
                  <CodeBlock
                    label="theme.json — shape"
                    language="json"
                    code={THEME_SHAPE}
                  />
                  <DocsTable
                    headers={["Field", "Required", "What it is"]}
                    rows={[
                      [
                        <InlineCode key="i">id</InlineCode>,
                        "yes",
                        <>
                          Stable, namespaced identity (
                          <InlineCode>publisher.name</InlineCode>). It is what
                          gets stored in preferences, so renaming{" "}
                          <InlineCode>name</InlineCode> never loses the
                          user&apos;s choice. Cannot collide with a built-in id.
                        </>,
                      ],
                      [
                        <InlineCode key="n">name</InlineCode>,
                        "yes",
                        "What shows up in the picker.",
                      ],
                      [
                        <InlineCode key="a">author</InlineCode>,
                        "no",
                        "Metadata.",
                      ],
                      [
                        <InlineCode key="v">version</InlineCode>,
                        "no",
                        "Metadata.",
                      ],
                      [
                        <InlineCode key="e">extends</InlineCode>,
                        "no",
                        <>
                          Id of a built-in theme to inherit from. Absent =
                          inherits from <InlineCode>cockpit</InlineCode>.
                        </>,
                      ],
                      [
                        <InlineCode key="va">variants</InlineCode>,
                        "yes",
                        <>
                          At least one of <InlineCode>dark</InlineCode> /{" "}
                          <InlineCode>light</InlineCode>. A dark-only theme is
                          applied in light mode too — better than mixing half a
                          light theme with half a dark one.
                        </>,
                      ],
                    ]}
                  />
                  <p>
                    <strong>Inheritance is the point.</strong> Every token you
                    do not declare comes from the base, so a useful theme can be
                    five lines long:
                  </p>
                  <CodeBlock
                    label="acme.violet.json"
                    language="json"
                    code={THEME_MINIMAL}
                  />
                  <p>
                    Colors are CSS-style hex —{" "}
                    <InlineCode>#RGB</InlineCode>,{" "}
                    <InlineCode>#RRGGBB</InlineCode> or{" "}
                    <InlineCode>#RRGGBBAA</InlineCode>,{" "}
                    <strong>alpha last</strong>. It is not Dart&apos;s{" "}
                    <InlineCode>0xAARRGGBB</InlineCode>. On a bad import the
                    parser points at the <strong>field path</strong> that broke
                    (<InlineCode>variants.dark.ui.accent</InlineCode>), and
                    validation runs before the copy, so an invalid file never
                    reaches the themes folder.
                  </p>
                </DocsSubsection>

                <DocsSubsection id="themes-tokens" title="Tokens">
                  <DocsTable
                    headers={["Group", "Tokens"]}
                    rows={[
                      [
                        <>
                          <InlineCode>ui</InlineCode> (25)
                        </>,
                        <>
                          Surfaces <InlineCode>bg</InlineCode>{" "}
                          <InlineCode>panel</InlineCode>{" "}
                          <InlineCode>panel2</InlineCode>{" "}
                          <InlineCode>panel3</InlineCode> · strokes{" "}
                          <InlineCode>border</InlineCode>{" "}
                          <InlineCode>border2</InlineCode> · text{" "}
                          <InlineCode>text</InlineCode>{" "}
                          <InlineCode>text2</InlineCode>{" "}
                          <InlineCode>text3</InlineCode>{" "}
                          <InlineCode>text4</InlineCode> · brand{" "}
                          <InlineCode>accent</InlineCode>{" "}
                          <InlineCode>accentSoft</InlineCode>{" "}
                          <InlineCode>accentText</InlineCode> · state{" "}
                          <InlineCode>online</InlineCode>{" "}
                          <InlineCode>ok</InlineCode>{" "}
                          <InlineCode>error</InlineCode>{" "}
                          <InlineCode>warn</InlineCode> · editing{" "}
                          <InlineCode>edited</InlineCode>{" "}
                          <InlineCode>editedBg</InlineCode> · git{" "}
                          <InlineCode>gitStaged</InlineCode>{" "}
                          <InlineCode>gitUntracked</InlineCode>{" "}
                          <InlineCode>gitDeleted</InlineCode>{" "}
                          <InlineCode>gitConflict</InlineCode> · overlay{" "}
                          <InlineCode>scrim</InlineCode>{" "}
                          <InlineCode>shadow</InlineCode>
                        </>,
                      ],
                      [
                        <>
                          <InlineCode>syntax</InlineCode> (12)
                        </>,
                        <>
                          <InlineCode>background</InlineCode>{" "}
                          <InlineCode>base</InlineCode>{" "}
                          <InlineCode>comment</InlineCode>{" "}
                          <InlineCode>keyword</InlineCode>{" "}
                          <InlineCode>string</InlineCode>{" "}
                          <InlineCode>number</InlineCode>{" "}
                          <InlineCode>class</InlineCode>{" "}
                          <InlineCode>builtin</InlineCode>{" "}
                          <InlineCode>function</InlineCode>{" "}
                          <InlineCode>variable</InlineCode>{" "}
                          <InlineCode>meta</InlineCode>{" "}
                          <InlineCode>deletion</InlineCode>
                        </>,
                      ],
                      [
                        <>
                          <InlineCode>terminal</InlineCode> (23)
                        </>,
                        <>
                          <InlineCode>cursor</InlineCode>{" "}
                          <InlineCode>selection</InlineCode>{" "}
                          <InlineCode>foreground</InlineCode>{" "}
                          <InlineCode>background</InlineCode>, the 8 normal ANSI
                          colors, their 8 <InlineCode>bright*</InlineCode>{" "}
                          counterparts, and{" "}
                          <InlineCode>searchHitBackground</InlineCode>{" "}
                          <InlineCode>searchHitBackgroundCurrent</InlineCode>{" "}
                          <InlineCode>searchHitForeground</InlineCode>
                        </>,
                      ],
                    ]}
                  />
                  <p>
                    Text drawn <em>on top of</em>{" "}
                    <InlineCode>accent</InlineCode> and{" "}
                    <InlineCode>error</InlineCode> is not a token: it is derived
                    from the color&apos;s luminance, so a light accent
                    automatically gets dark text.
                  </p>
                  <p>
                    <InlineCode>syntax.background</InlineCode> has a special
                    default. The code viewer, the editor, and the terminal are
                    all content inside a tab, so they share the field: when a
                    theme declares neither{" "}
                    <InlineCode>syntax.background</InlineCode> nor{" "}
                    <InlineCode>terminal.background</InlineCode>, the three
                    follow <InlineCode>ui.panel</InlineCode> of{" "}
                    <em>this</em> theme, not of the base. Declare the field if
                    your code palette needs a surface of its own.
                  </p>
                  <p>
                    The <InlineCode>$schema</InlineCode> URL lives in the
                    repository, versioned next to the code that implements it,
                    so the app and the schema can never drift apart. Cockpit
                    ignores the field when reading a theme — it only serves your
                    editor. See{" "}
                    <a
                      className="text-accent underline"
                      href={THEME_EXAMPLE}
                      target="_blank"
                      rel="noopener noreferrer"
                    >
                      <InlineCode>theme.example.json</InlineCode>
                    </a>{" "}
                    for a commented file with every group filled in.
                  </p>
                </DocsSubsection>
              </DocsSection>

              {/* ── TURN STATUS ─────────────────────────────────────────── */}

              <DocsSection id="turn-status" title="Agent turn status">
                <p>
                  When an agent runs in a tab, Cockpit shows whether it is{" "}
                  <strong>working</strong>, <strong>waiting</strong> for you, or{" "}
                  <strong>idle</strong> — as a spinner, a badge, a chime, and an
                  OS notification when the window is unfocused. Supported
                  harnesses today: <strong>Claude Code</strong> and{" "}
                  <strong>Codex CLI</strong> (0.147+).
                </p>
                <p>How it works:</p>
                <ol>
                  <li>
                    At boot, Cockpit materializes the internal CLI at{" "}
                    <InlineCode>~/.cockpit/bin/cockpit</InlineCode> and
                    registers <InlineCode>cockpit hook</InlineCode> on the
                    harness&apos; lifecycle events.
                  </li>
                  <li>
                    On each event the harness runs the hook, passing a JSON
                    payload on stdin.
                  </li>
                  <li>
                    The hook translates it into a status and sends it to the app
                    over the local socket. (A socket rather than an escape
                    sequence on the PTY: harnesses run hooks with no controlling
                    terminal, and writing to <InlineCode>/dev/tty</InlineCode>{" "}
                    fails with <InlineCode>ENXIO</InlineCode>.)
                  </li>
                  <li>
                    Routing is by the <InlineCode>COCKPIT_PANE_ID</InlineCode>{" "}
                    env var, which the app injects into the tab&apos;s PTY. An
                    agent session started <em>outside</em> Cockpit does not have
                    it, so the hook is a no-op there. Nothing to configure,
                    nothing to disable.
                  </li>
                </ol>
                <DocsTable
                  headers={["Harness", "File", "Format"]}
                  rows={[
                    [
                      "Claude Code",
                      <InlineCode key="c">~/.claude/settings.json</InlineCode>,
                      <>
                        <InlineCode>hooks.&lt;Event&gt;[]</InlineCode>, each
                        item{" "}
                        <InlineCode>
                          {"{matcher, hooks:[{type, command}]}"}
                        </InlineCode>
                      </>,
                    ],
                    [
                      "Codex CLI",
                      <InlineCode key="x">~/.codex/hooks.json</InlineCode>,
                      <>
                        Same shape, <strong>plus</strong> a trust block in{" "}
                        <InlineCode>~/.codex/config.toml</InlineCode> (Codex
                        silently ignores an untrusted hook, so Cockpit computes
                        and writes the trust hash for you, between{" "}
                        <InlineCode>{"# >>> cockpit hooks"}</InlineCode>{" "}
                        delimiters).
                      </>,
                    ],
                  ]}
                />
                <p>
                  Both installers do an <strong>idempotent append</strong> of a
                  marked entry (<InlineCode>_cockpit: v1</InlineCode>):
                  re-running removes our old entry and re-adds it, never
                  rewriting the list — your own hooks, and those of plugins or
                  iTerm2, survive untouched.
                </p>

                <DocsSubsection id="turn-status-events" title="Event mapping">
                  <DocsTable
                    headers={["Event", "Claude", "Codex", "Status"]}
                    rows={[
                      [
                        <InlineCode key="e">UserPromptSubmit</InlineCode>,
                        "✓",
                        "✓",
                        <>
                          <InlineCode>working</InlineCode> (turn starts)
                        </>,
                      ],
                      [
                        <InlineCode key="e">PreToolUse</InlineCode>,
                        "✓",
                        "✓",
                        <>
                          <InlineCode>working</InlineCode> — except for
                          Claude&apos;s blocking tools (below)
                        </>,
                      ],
                      [
                        <InlineCode key="e">PostToolUse</InlineCode>,
                        "✓",
                        "✓",
                        <InlineCode key="s">working</InlineCode>,
                      ],
                      [
                        <InlineCode key="e">Notification</InlineCode>,
                        "✓",
                        "—",
                        <>
                          <InlineCode>waiting</InlineCode> /{" "}
                          <InlineCode>idle</InlineCode> (heuristic on the text)
                        </>,
                      ],
                      [
                        <InlineCode key="e">PermissionRequest</InlineCode>,
                        "—",
                        "✓",
                        <InlineCode key="s">waiting</InlineCode>,
                      ],
                      [
                        <InlineCode key="e">Stop</InlineCode>,
                        "✓",
                        "✓",
                        <InlineCode key="s">idle</InlineCode>,
                      ],
                      [
                        <>
                          <InlineCode>SessionStart</InlineCode> /{" "}
                          <InlineCode>SessionEnd</InlineCode>
                        </>,
                        "✓",
                        "✓",
                        <InlineCode key="s">idle</InlineCode>,
                      ],
                      [
                        <>
                          <InlineCode>SubagentStart/Stop</InlineCode>,{" "}
                          <InlineCode>PreCompact/PostCompact</InlineCode>
                        </>,
                        "—",
                        "✓",
                        <strong key="s">ignored</strong>,
                      ],
                    ]}
                  />
                  <p>
                    Two asymmetries matter. On <strong>Claude</strong>, tools
                    that block waiting for the user (
                    <InlineCode>AskUserQuestion</InlineCode>,{" "}
                    <InlineCode>ExitPlanMode</InlineCode>) emit no{" "}
                    <InlineCode>Notification</InlineCode>; the last hook before
                    the block is <InlineCode>PreToolUse</InlineCode>, so that
                    one maps to <InlineCode>waiting</InlineCode> for those two —
                    otherwise the tab would spin forever with no chime. On{" "}
                    <strong>Codex</strong>, approval has its own event, so there
                    is no text heuristic and no detour.
                  </p>
                </DocsSubsection>

                <DocsSubsection
                  id="turn-status-resume"
                  title="Resuming a session"
                >
                  <p>
                    Cockpit persists the{" "}
                    <InlineCode>session_id</InlineCode> that arrived through the
                    hook, and on restoring the tab it types the command that
                    reattaches the conversation. A session id alone does not say
                    which harness it belongs to, and the commands differ —{" "}
                    <InlineCode>claude --resume &lt;id&gt;</InlineCode> versus{" "}
                    <InlineCode>codex resume &lt;id&gt;</InlineCode> — so the
                    installer registers the hook as{" "}
                    <InlineCode>cockpit hook --harness &lt;name&gt;</InlineCode>{" "}
                    and the layout stores the harness next to the id. Entries
                    written by older versions pass no flag and are assumed to be
                    Claude, which is what they all were.
                  </p>
                  <Callout variant="warning" title="Codex trust is index-keyed">
                    <p>
                      The Codex trust key includes the hook&apos;s group index.
                      If you add a hook of your own <em>before</em> ours on the
                      same event — or edit{" "}
                      <InlineCode>hooks.json</InlineCode> by hand — the hash
                      stops matching and the hook silently stops running. The
                      installer repairs it on the next boot, because it
                      recomputes the indices from the final file.
                    </p>
                  </Callout>
                </DocsSubsection>
              </DocsSection>

              {/* ── SOUNDS ──────────────────────────────────────────────── */}

              <DocsSection id="sounds" title="Sounds & notifications">
                <p>
                  Turn status drives audio too. Under{" "}
                  <strong>Settings → Notifications</strong> you can bind a sound
                  per event — <strong>turn done</strong>,{" "}
                  <strong>action needed</strong>, <strong>error</strong> — pick
                  a custom audio file for each, and set the volume. With the
                  window focused you get the chime; unfocused, an OS
                  notification. Since an agent started outside Cockpit never
                  reports status, nothing fires for sessions the app is not
                  hosting.
                </p>
              </DocsSection>

              {/* ── LANGUAGE ────────────────────────────────────────────── */}

              <DocsSection id="language" title="Language">
                <p>
                  Cockpit&apos;s interface is fully localized in{" "}
                  <strong>English</strong>, <strong>Portuguese (Brazil)</strong>{" "}
                  and <strong>Spanish</strong>, down to the native application
                  menu. Switch it in{" "}
                  <strong>Settings → General → Language</strong>; the choice is
                  independent of the OS locale.
                </p>
              </DocsSection>

              {/* ── LINKS ───────────────────────────────────────────────── */}

              <DocsSection id="links" title="Links">
                <ul>
                  <li>
                    <Link href="/cockpit" className="text-accent underline">
                      Cockpit product page
                    </Link>{" "}
                    — the tour.
                  </li>
                  <li>
                    <Link
                      href="/tutorials/cockpit-layouts"
                      className="text-accent underline"
                    >
                      Tutorial: layouts and tasks
                    </Link>{" "}
                    — build a <InlineCode>.ckp</InlineCode> and a{" "}
                    <InlineCode>tasks.json</InlineCode> from scratch.
                  </li>
                  <li>
                    <Link
                      href="/tutorials/cockpit-team"
                      className="text-accent underline"
                    >
                      Tutorial: an agent team in Cockpit
                    </Link>
                    .
                  </li>
                  <li>
                    <Link href="/docs" className="text-accent underline">
                      Remote Pi docs
                    </Link>{" "}
                    — mesh, relay, daemons, pairing.
                  </li>
                  <li>
                    <a
                      className="text-accent underline"
                      href={COCKPIT_DOCS}
                      target="_blank"
                      rel="noopener noreferrer"
                    >
                      Source docs &amp; JSON schemas
                    </a>{" "}
                    in the repository.
                  </li>
                  <li>
                    <a
                      className="text-accent underline"
                      href={GITHUB_URL}
                      target="_blank"
                      rel="noopener noreferrer"
                    >
                      GitHub
                    </a>{" "}
                    — issues and source.
                  </li>
                </ul>
              </DocsSection>
            </article>
          </div>
        </div>
      </div>
      <RevealController />
    </div>
  );
}
