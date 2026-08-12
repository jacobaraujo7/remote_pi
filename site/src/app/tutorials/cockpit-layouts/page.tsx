import type { Metadata } from "next";
import Link from "next/link";
import { DocsSection, InlineCode } from "@/components/docs-shell";
import { CodeBlock } from "@/components/code-block";
import { Callout } from "@/components/callout";
import { Pager } from "@/components/pager";
import { RevealController } from "@/components/landing/reveal-controller";

export const metadata: Metadata = {
  title: "Layouts and tasks in Cockpit",
  description:
    "Commit your working setup: a .ckp layout that opens the right terminals in the right folders, and a .cockpit/tasks.json that runs your dev servers with reload on save.",
};

const TREE = `my-app/
├── .cockpit/
│   └── tasks.json     # what runs
├── dev.ckp            # what opens
├── api/
│   └── package.json
└── web/
    └── package.json`;

const CKP_FIRST = `panes:
  - name: Agent
    cwd: .
    command: claude`;

const CKP_FULL = `# dev.ckp — one layout, committed with the project
autorun: worktree
panes:
  - name: Agent
    cwd: .
    command: claude
  - name: API
    cwd: api
    split: right
  - name: Web
    cwd: web
    split: down`;

const TASKS = `{
  // .cockpit/tasks.json — JSONC: comments and trailing commas are fine
  "tasks": [
    {
      "label": "api",
      "cwd": "api",
      "command": "npm",
      "args": ["run", "dev"],
      "kind": "watch",
      "interactiveKeys": [
        { "key": "q", "label": "Quit", "icon": "stop" }
      ]
    },
    {
      "label": "web",
      "cwd": "web",
      "command": "npm",
      "args": ["run", "dev"],
      "kind": "watch",
      "profiles": [
        { "name": "dev" },
        { "name": "staging", "env": { "API_URL": "https://staging.example.com" } }
      ]
    }
  ]
}`;

export default function CockpitLayoutsTutorial() {
  return (
    <div className="page">
      <div className="page-body">
        <div className="wrap">
          <div className="tut">
            <header className="page-head reveal" style={{ maxWidth: "none" }}>
              <div className="flex flex-wrap items-center gap-3">
                <span className="inline-flex items-center rounded-full border border-accent/40 bg-accent/15 px-3 py-1 text-xs font-semibold uppercase tracking-[0.15em] text-accent">
                  Cockpit · workflow
                </span>
              </div>
              <span className="eyebrow" style={{ marginTop: 14 }}>
                Tutorial · Cockpit
              </span>
              <h1>Layouts and tasks in Cockpit</h1>
              <p className="lede">
                Two small files turn &ldquo;set up my environment&rdquo; into
                one click: a <InlineCode>.ckp</InlineCode> layout that opens the
                right terminals in the right folders, and a{" "}
                <InlineCode>.cockpit/tasks.json</InlineCode> that runs your dev
                servers with buttons, profiles, and reload on save. Both live in
                the repository, so your teammates — and every new git worktree —
                get the same setup for free.
              </p>
            </header>

            <article className="prose">
              <DocsSection id="what" title="What you'll build">
                <p>
                  A small monorepo with an API and a web app. By the end, opening
                  the project gives you three terminals in the right folders, a
                  task list with both servers ready to play, and a new worktree
                  that recreates the whole thing by itself.
                </p>
                <CodeBlock code={TREE} label="project layout" language="text" />
                <p>
                  Everything here is Cockpit-local: no account, no mesh, no
                  agents required. If you want agents on top of this, follow{" "}
                  <Link
                    href="/tutorials/cockpit-team"
                    className="text-accent underline"
                  >
                    An agent team in Cockpit
                  </Link>{" "}
                  next.
                </p>
              </DocsSection>

              <DocsSection id="prereqs" title="Before you start">
                <ul className="ml-6 list-disc space-y-2">
                  <li>
                    <strong className="text-fg">Cockpit installed</strong> —
                    macOS, Windows, or Linux, from the{" "}
                    <Link href="/download" className="text-accent underline">
                      download page
                    </Link>
                    .
                  </li>
                  <li>
                    A project folder open as a workspace. Anything with a couple
                    of subfolders works; the commands below assume{" "}
                    <InlineCode>npm</InlineCode>, but the runner is generic.
                  </li>
                </ul>
              </DocsSection>

              <DocsSection id="first-layout" title="1. Write your first layout">
                <p>
                  Create <InlineCode>dev.ckp</InlineCode> at the root of the
                  project. A layout is YAML, and the smallest useful one is
                  three lines:
                </p>
                <CodeBlock code={CKP_FIRST} label="dev.ckp" language="yaml" />
                <p>
                  Right-click the file in Cockpit&apos;s tree and choose{" "}
                  <strong>Open layout</strong>. A tab named{" "}
                  <InlineCode>Agent</InlineCode> opens at the project root and
                  types <InlineCode>claude</InlineCode> for you. Apply it again:
                  nothing happens. A pane whose <InlineCode>name</InlineCode>{" "}
                  already exists is skipped, so a layout is safe to re-run and
                  never closes anything.
                </p>
                <Callout variant="tip" title="The name is the label">
                  <p>
                    <InlineCode>name</InlineCode> becomes the tab&apos;s{" "}
                    <strong>stable label</strong> — the one the{" "}
                    <InlineCode>cockpit</InlineCode> CLI can address by name
                    instead of by a boot-scoped id, and the same label you would
                    otherwise set by double-clicking the tab.
                  </p>
                </Callout>
              </DocsSection>

              <DocsSection id="splits" title="2. Add splits and folders">
                <p>
                  Now the real geometry. <InlineCode>cwd</InlineCode> is relative
                  to the <InlineCode>.ckp</InlineCode> file (forward slashes
                  only, so the file works on every OS), and{" "}
                  <InlineCode>split</InlineCode> says where each pane is born
                  relative to the one created before it:{" "}
                  <InlineCode>tab</InlineCode> (default),{" "}
                  <InlineCode>right</InlineCode>, or{" "}
                  <InlineCode>down</InlineCode>.
                </p>
                <CodeBlock code={CKP_FULL} label="dev.ckp" language="yaml" />
                <p>
                  You can also apply it from inside any Cockpit terminal, which
                  is how an agent sets up its own workspace:
                </p>
                <CodeBlock
                  code="cockpit orchestrate dev.ckp"
                  label="Cockpit terminal"
                  prompt
                />
                <Callout variant="note" title="autorun: worktree">
                  <p>
                    That one line is the payoff. Every time you fork the
                    workspace onto a fresh git worktree, Cockpit applies the
                    layout by itself — and since a new worktree starts empty, the
                    splits come out exactly as written. Keep a single autorun
                    file at the root: with two or more, none of them runs, because
                    ambiguity is never guessed.
                  </p>
                </Callout>
              </DocsSection>

              <DocsSection id="tasks" title="3. Declare your tasks">
                <p>
                  Cockpit already detects tasks from{" "}
                  <InlineCode>package.json</InlineCode> and{" "}
                  <InlineCode>pubspec.yaml</InlineCode> with no configuration —
                  open the Tasks panel and your scripts are there. You write{" "}
                  <InlineCode>.cockpit/tasks.json</InlineCode> when you want more
                  than that: a monorepo, interactive keys, environment profiles.
                </p>
                <CodeBlock
                  code={TASKS}
                  label=".cockpit/tasks.json"
                  language="jsonc"
                />
                <p>
                  The file goes at the root of the workspace you open — discovery
                  is literal, with no walking up the tree. Each task&apos;s{" "}
                  <InlineCode>cwd</InlineCode> is relative to that file, which is
                  what lets one file at the monorepo root drive every subpackage.
                  Hit play and the output streams into its own tab, with stop and
                  restart controls and any{" "}
                  <InlineCode>interactiveKeys</InlineCode> you declared as
                  buttons that write straight to the process&apos; stdin.
                </p>
                <p>
                  <InlineCode>profiles</InlineCode> are launch configs: a chip
                  cycles them before you press play, appending{" "}
                  <InlineCode>args</InlineCode> and merging{" "}
                  <InlineCode>env</InlineCode>. The runner stays generic on
                  purpose — a Flutter flavor or a{" "}
                  <InlineCode>--dart-define</InlineCode> is just more{" "}
                  <InlineCode>args</InlineCode>.
                </p>
                <Callout variant="tip" title="Reload on save">
                  <p>
                    For a process that does not watch files itself (
                    <InlineCode>flutter run</InlineCode> is the classic case),
                    add a <InlineCode>watch</InlineCode> block:{" "}
                    <InlineCode>paths</InlineCode> to observe,{" "}
                    <InlineCode>ignore</InlineCode> to keep build folders from
                    looping, and <InlineCode>onChange</InlineCode> pointing at an{" "}
                    <InlineCode>interactiveKeys</InlineCode> label (
                    <InlineCode>&quot;Hot reload&quot;</InlineCode>) or{" "}
                    <InlineCode>&quot;__restart__&quot;</InlineCode>. Skip it for
                    Vite or Next, which already reload on their own.
                  </p>
                </Callout>
              </DocsSection>

              <DocsSection id="agents" title="4. Let an agent use them">
                <p>
                  Both files are reachable from the internal{" "}
                  <InlineCode>cockpit</InlineCode> CLI, which exists only inside
                  Cockpit&apos;s terminals. That means an agent in one tab can
                  start your dev server, read what it printed, and open a file
                  for you to look at — without a screenshot or a screen scrape.
                </p>
                <CodeBlock
                  label="Cockpit terminal"
                  prompt
                  code={`# what can I run here?
cockpit list-tasks

# tail the dev server's output
cockpit read-task json:api --lines 80

# open a worker tab beside me and drive it
id=$(cockpit new-tab --cwd web --title Web --split h)
cockpit send --tab-id "$id" --enter "npm run build"`}
                />
                <p>
                  Task ids are stable per workspace:{" "}
                  <InlineCode>json:&lt;label&gt;</InlineCode> for the ones you
                  declared, <InlineCode>npm:&lt;script&gt;</InlineCode> and{" "}
                  <InlineCode>flutter:run</InlineCode> for detected ones. The
                  full command surface is in the{" "}
                  <Link href="/cockpit/docs#cli" className="text-accent underline">
                    Cockpit reference
                  </Link>
                  .
                </p>
              </DocsSection>

              <DocsSection id="commit" title="5. Commit them">
                <p>
                  Both files belong in git. <InlineCode>dev.ckp</InlineCode> is
                  your working geometry, and{" "}
                  <InlineCode>.cockpit/tasks.json</InlineCode> is how the project
                  is run — the same reason a{" "}
                  <InlineCode>Makefile</InlineCode> is committed. A teammate
                  clones, opens the folder in Cockpit, and gets your terminals
                  and your task list. Point{" "}
                  <InlineCode>$schema</InlineCode> at{" "}
                  <InlineCode>tasks.schema.json</InlineCode> from the repository
                  and their editor will autocomplete the fields as well; Cockpit
                  ignores the field when running.
                </p>
                <p>
                  From here:{" "}
                  <Link
                    href="/tutorials/cockpit-team"
                    className="text-accent underline"
                  >
                    put a team of agents
                  </Link>{" "}
                  into those panes, or read the{" "}
                  <Link href="/cockpit/docs" className="text-accent underline">
                    Cockpit reference
                  </Link>{" "}
                  for every field, flag, and the theme format.
                </p>
              </DocsSection>
            </article>

            <Pager
              prev={{ href: "/cockpit", label: "Meet Cockpit" }}
              next={{
                href: "/tutorials/cockpit-team",
                label: "An agent team in Cockpit",
              }}
            />
          </div>
        </div>
      </div>
      <RevealController />
    </div>
  );
}
