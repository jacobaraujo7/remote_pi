import type { Metadata } from "next";
import Link from "next/link";
import { DocsSection, InlineCode } from "@/components/docs-shell";
import { CodeBlock } from "@/components/code-block";
import { Callout } from "@/components/callout";
import { Pager } from "@/components/pager";
import { RevealController } from "@/components/landing/reveal-controller";

export const metadata: Metadata = {
  title: "An agent team in Cockpit",
  description:
    "Run an orchestrator and two worker agents as terminal tabs in one Cockpit window, each in its own folder, coordinated with the internal cockpit CLI.",
};

/* ---- example briefs (one per folder) ---- */
const ORCHESTRATOR_MD = `# Orchestrator

You coordinate two workers that run in other Cockpit tabs: \`Backend\` and
\`Frontend\`. You do not write app code yourself. You split the work, dispatch
it, and integrate the results.

## How you work
- Dispatch with the internal CLI, one instruction per worker:
  \`cockpit send --tab-id <tab> --enter "<instruction>"\`
- Read a worker back with \`cockpit read-tab <label> --lines 80\` instead of
  asking the human what it printed.
- A worker is busy while \`working\` is true in \`cockpit list-tabs --json\`.
  Wait for it to flip to false before reading the final answer.
- Reconcile mismatches (the API shape against what the UI needs) and report
  back to the human.

Keep each instruction small and explicit: say what you want and what "done"
looks like.`;

const BACKEND_MD = `# Backend

You own the server and API in this folder. You work only here.

## How you work
- The orchestrator types instructions straight into your terminal. Treat them
  as prompts from the human.
- Keep the API contract (routes, payloads) explicit, and print it when you are
  done, because the orchestrator reads your output to pass it on.
- If an instruction is ambiguous, say what is missing instead of guessing.`;

const FRONTEND_MD = `# Frontend

You own the UI in this folder. You work only here.

## How you work
- Build against the contract the backend printed. If you need a route or a
  field that does not exist, say so and stop: the orchestrator coordinates it.
- When you are done, print what changed, in one short list.`;

const TEAM_CKP = `panes:
  - name: Orchestrator
    cwd: orchestrator
    command: claude
  - name: Backend
    cwd: backend
    split: right
    command: claude
  - name: Frontend
    cwd: frontend
    split: down
    command: claude`;

export default function CockpitTeamTutorial() {
  return (
    <div className="page">
      <div className="page-body">
        <div className="wrap">
          <div className="tut">
            <header className="page-head reveal" style={{ maxWidth: "none" }}>
              <div className="flex flex-wrap items-center gap-3">
                <span className="inline-flex items-center rounded-full border border-accent/40 bg-accent/15 px-3 py-1 text-xs font-semibold uppercase tracking-[0.15em] text-accent">
                  Cockpit · multi-agent
                </span>
              </div>
              <span className="eyebrow" style={{ marginTop: 14 }}>
                Tutorial · Cockpit
              </span>
              <h1>An agent team in Cockpit</h1>
              <p className="lede">
                Cockpit&apos;s real power is the multiplexer: many agents in one
                window, each in its own folder. Here you wire up three,
                an <strong className="text-fg">orchestrator</strong>, a{" "}
                <strong className="text-fg">backend</strong> and a{" "}
                <strong className="text-fg">frontend</strong>, and let the
                orchestrator drive the other two with the internal{" "}
                <InlineCode>cockpit</InlineCode> CLI.
              </p>
            </header>

            <article className="prose">
              <DocsSection id="what" title="What you'll build">
                <p>
                  Three agent tabs, side by side in a single Cockpit workspace.
                  Each one is an ordinary terminal running your harness of
                  choice (this tutorial uses{" "}
                  <InlineCode>claude</InlineCode>; <InlineCode>codex</InlineCode>{" "}
                  or <InlineCode>pi</InlineCode> work the same way), started in
                  its own subfolder so it picks up that folder&apos;s brief and
                  boots into a role.
                </p>
                <p>
                  They coordinate through Cockpit itself. The orchestrator opens
                  the worker tabs, types instructions into them and reads their
                  output back, using the <InlineCode>cockpit</InlineCode> CLI
                  that exists inside every Cockpit terminal. No network, no
                  account, no extra service: it is the app you already have
                  open, driven by the same verbs a human uses.
                </p>
                <Callout variant="note" title="Worth reading first">
                  The CLI reference lives in the{" "}
                  <Link
                    href="/docs#cli"
                    className="text-accent underline"
                  >
                    Cockpit docs
                  </Link>
                  , and{" "}
                  <Link
                    href="/tutorials/cockpit-layouts"
                    className="text-accent underline"
                  >
                    Layouts and tasks
                  </Link>{" "}
                  shows how a <InlineCode>.ckp</InlineCode> file recreates a
                  window like this one on any machine.
                </Callout>
              </DocsSection>

              <DocsSection id="prereqs" title="Before you start">
                <ul className="ml-6 list-disc space-y-2">
                  <li>
                    <strong className="text-fg">Cockpit installed</strong>, from
                    the{" "}
                    <Link href="/download" className="text-accent underline">
                      download page
                    </Link>
                    . Nothing else is required: Cockpit needs no account and no
                    cloud.
                  </li>
                  <li>
                    <strong className="text-fg">A harness on your PATH</strong>,
                    the one you already use. Cockpit runs it as a normal
                    process, so whatever works in your terminal works in a tab.
                  </li>
                </ul>
              </DocsSection>

              <DocsSection id="folders" title="1. Lay out the folders">
                <p>
                  An agent&apos;s identity comes from where it starts, so give
                  each teammate a folder with its own brief:
                </p>
                <CodeBlock
                  code={`my-app/
├── orchestrator/
│   └── AGENTS.md
├── backend/
│   └── AGENTS.md
└── frontend/
    └── AGENTS.md`}
                  label="project layout"
                  language="text"
                />
                <p>
                  <InlineCode>AGENTS.md</InlineCode> is the standing brief an
                  agent reads when it starts in a folder (Claude Code also reads{" "}
                  <InlineCode>CLAUDE.md</InlineCode>). Give each one a clear job,
                  and tell the orchestrator how to reach the others.
                </p>
                <CodeBlock
                  code={ORCHESTRATOR_MD}
                  label="orchestrator/AGENTS.md"
                  language="markdown"
                />
                <CodeBlock
                  code={BACKEND_MD}
                  label="backend/AGENTS.md"
                  language="markdown"
                />
                <CodeBlock
                  code={FRONTEND_MD}
                  label="frontend/AGENTS.md"
                  language="markdown"
                />
                <Callout variant="note" title="One folder, one teammate">
                  Keeping each agent in its own subfolder is what keeps the
                  briefs, the histories and the edits apart. Three folders,
                  three tabs, three roles.
                </Callout>
              </DocsSection>

              <DocsSection id="tabs" title="2. Open the three tabs">
                <p>
                  Open <InlineCode>my-app/</InlineCode> as a workspace. Then open
                  a terminal in each subfolder and start your harness there. The
                  fastest way is from the Files panel: right-click a folder and
                  open a terminal in it, then run <InlineCode>claude</InlineCode>
                  .
                </p>
                <p>
                  Split the canvas so all three are visible at once, the
                  orchestrator on one side and the workers on the other, and
                  rename each tab by double-clicking it:{" "}
                  <InlineCode>Orchestrator</InlineCode>,{" "}
                  <InlineCode>Backend</InlineCode>,{" "}
                  <InlineCode>Frontend</InlineCode>. Those labels are how the
                  CLI addresses a tab, and unlike ids they survive a restart of
                  the app.
                </p>
                <p>
                  Do it once by hand, or commit the whole geometry as a{" "}
                  <InlineCode>team.ckp</InlineCode> and let Cockpit build the
                  window for you:
                </p>
                <CodeBlock code={TEAM_CKP} label="team.ckp" language="yaml" />
                <CodeBlock
                  label="any Cockpit terminal"
                  prompt
                  code="cockpit orchestrate team.ckp"
                />
                <Callout variant="tip" title="Labels, not ids">
                  Tab ids (<InlineCode>t0</InlineCode>,{" "}
                  <InlineCode>t1</InlineCode>…) are handed out per app boot, so
                  never hardcode one in a brief or a script. Address a tab by
                  its label, or discover the id of the moment with{" "}
                  <InlineCode>cockpit list-tabs</InlineCode>.
                </Callout>
              </DocsSection>

              <DocsSection id="wiring" title="3. Teach the orchestrator the CLI">
                <p>
                  Every terminal Cockpit opens has{" "}
                  <InlineCode>cockpit</InlineCode> on its{" "}
                  <InlineCode>PATH</InlineCode>, and only those terminals do. So
                  the orchestrator can already drive its teammates; it just
                  needs to know the verbs. Ask it to look around:
                </p>
                <CodeBlock
                  code="Run `cockpit list-tabs --json` and tell me which tabs you can reach."
                  label="Orchestrator · prompt"
                  language="text"
                />
                <CodeBlock
                  code={`$ cockpit list-tabs --json
[
  { "id": "t0", "label": "Orchestrator", "workspacePath": "/Users/me/my-app", "working": true  },
  { "id": "t1", "label": "Backend",      "workspacePath": "/Users/me/my-app", "working": false },
  { "id": "t2", "label": "Frontend",     "workspacePath": "/Users/me/my-app", "working": false }
]`}
                  label="Orchestrator · tool call"
                  language="text"
                />
                <p>
                  Four verbs are enough to run a team. If you use Claude Code,{" "}
                  <InlineCode>cockpit install-skill</InlineCode> installs a skill
                  that teaches all of them, so the brief can stay short.
                </p>
                <CodeBlock
                  label="the four verbs"
                  prompt
                  code={`# dispatch an instruction and press Enter for it
cockpit send --tab-id Backend --enter "Expose GET /todos and POST /todos"

# see who is still thinking (working: true) and who is done
cockpit list-tabs --json

# read a worker's answer without touching its window
cockpit read-tab Backend --lines 80

# open a worker beside you, mid-flight, if the work needs one more pair of hands
cockpit new-tab --cwd ./docs --title Docs --split v`}
                />
                <Callout variant="warning" title="Enter is a keystroke">
                  A bare <InlineCode>cockpit send</InlineCode> types the text and
                  leaves it in the composer. Use{" "}
                  <InlineCode>--enter</InlineCode> (or a separate{" "}
                  <InlineCode>cockpit send-key Enter</InlineCode>) to submit it,
                  because a newline inside the text is a line break for the
                  harness, not a send.
                </Callout>
              </DocsSection>

              <DocsSection id="run" title="4. Run the orchestration">
                <p>
                  Now give the orchestrator something real. You talk only to it;
                  it talks to the others.
                </p>
                <CodeBlock
                  code={`Add a "todos" feature: an API to list and create todos, and a page
that shows them with a form to add one. Coordinate Backend and Frontend.`}
                  label="Orchestrator · prompt"
                  language="text"
                />
                <p>
                  It breaks the work in two and types one instruction into each
                  worker. The send returns as soon as the text is delivered, so
                  it is a dispatch, not a blocking call:
                </p>
                <CodeBlock
                  code={`$ cockpit send --tab-id Backend --enter \\
    "Expose GET /todos and POST /todos (title:string). Print the JSON shape when done."
sent

$ cockpit send --tab-id Frontend --enter \\
    "Build a Todos page: list todos and a form to add one. Wait for the API shape first."
sent`}
                  label="Orchestrator · tool calls"
                  language="text"
                />
                <p>
                  Each worker sees the instruction in its own tab, does the work{" "}
                  <em>in its own folder</em>, and prints the result. The
                  orchestrator polls for the turn to end, then reads the answer:
                </p>
                <CodeBlock
                  code={`$ cockpit list-tabs --json | grep -A1 Backend
  { "id": "t1", "label": "Backend", "working": false }

$ cockpit read-tab Backend --lines 40
  Added GET /todos and POST /todos.
  Todo: { id: string, title: string, done: bool }`}
                  label="Orchestrator · tool calls"
                  language="text"
                />
                <p>
                  With the contract in hand it unblocks the frontend, forwarding
                  the exact shape, and reports the finished feature back to you.
                  Three agents, three folders, one coordinated change, and you
                  watched all of it happen.
                </p>
                <Callout variant="note" title="Who is working right now">
                  You do not have to poll to know: each tab shows its own turn
                  status (working, waiting on you, done), with a chime when the
                  window is focused and a system notification when it is not.
                  The same signal the orchestrator reads from{" "}
                  <InlineCode>working</InlineCode> in{" "}
                  <InlineCode>list-tabs --json</InlineCode>.
                </Callout>
              </DocsSection>

              <DocsSection id="why" title="Why do this in Cockpit">
                <p>
                  You could run three terminals, but then nothing connects them.
                  Here the whole team lives in one window: every agent streams
                  its own work in its own tab, the orchestrator dispatches and
                  reads without you copying text around, and the layout comes
                  back when you reopen the app. Add a terminal tab for the dev
                  server, and the build, the agents and their traffic are all in
                  front of you at once.
                </p>
                <p>
                  From here: commit the{" "}
                  <InlineCode>.ckp</InlineCode> and a{" "}
                  <InlineCode>.cockpit/tasks.json</InlineCode> so a teammate gets
                  the same window on clone (
                  <Link
                    href="/tutorials/cockpit-layouts"
                    className="text-accent underline"
                  >
                    Layouts and tasks
                  </Link>
                  ), or move the team onto a bigger machine and keep driving it
                  over SSH (
                  <Link
                    href="/docs#remote"
                    className="text-accent underline"
                  >
                    Remote hosts
                  </Link>
                  ).
                </p>
              </DocsSection>
            </article>

            <Pager
              prev={{
                href: "/tutorials/cockpit-layouts",
                label: "Layouts and tasks",
              }}
              next={{
                href: "/tutorials/cockpit-telemetry",
                label: "Telemetry for agents",
              }}
            />
          </div>
        </div>
      </div>
      <RevealController />
    </div>
  );
}
