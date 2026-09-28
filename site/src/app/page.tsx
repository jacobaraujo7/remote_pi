import type { Metadata } from "next";
import Link from "next/link";
import Image from "next/image";
import { CodeBlock } from "@/components/code-block";
import { RevealController } from "@/components/landing/reveal-controller";
import { IconDownload, IconGithub, IconArrow } from "@/components/landing/icons";

const pageTitle = "Cockpit: a terminal that grew an IDE around your agents";
const pageDescription =
  "Run Claude Code, Codex, Pi or anything else in real terminals, local or on any machine over SSH, with the viewer, diagnostics, git, worktrees and databases they need to work.";

export const metadata: Metadata = {
  title: { absolute: pageTitle },
  description: pageDescription,
  openGraph: {
    type: "website",
    url: "https://remote-pi.jacobmoura.work",
    title: pageTitle,
    description: pageDescription,
    siteName: "Remote Pi Cockpit",
  },
  twitter: {
    card: "summary_large_image",
    title: pageTitle,
    description: pageDescription,
  },
};

const GITHUB_URL = "https://github.com/jacobaraujo7/remote_pi";

/* visual-first section: eyebrow + short headline + max one sentence + big shot */
function Shot({
  src,
  alt,
  width,
  height,
  maxWidth,
}: {
  src: string;
  alt: string;
  width: number;
  height: number;
  maxWidth?: number;
}) {
  return (
    <div
      className="ck-shot reveal"
      style={maxWidth ? { maxWidth, marginLeft: "auto", marginRight: "auto" } : undefined}
    >
      <Image
        src={src}
        alt={alt}
        width={width}
        height={height}
        sizes="(max-width: 1180px) 100vw, 1180px"
        style={{ width: "100%", height: "auto" }}
      />
    </div>
  );
}

export default function CockpitPage() {
  return (
    <div className="page">
      <div className="page-body">
        <div className="wrap">
          {/* ---------------- HERO ---------------- */}
          <header className="page-head reveal" style={{ maxWidth: 860 }}>
            <span className="eyebrow">Remote Pi Cockpit 2.0</span>
            <h1>A terminal that grew an IDE around your agents.</h1>
            <p className="lede">
              Run Claude Code, Codex, Pi or anything else in real terminals, on
              your machine or on any host over SSH, with the viewer,
              diagnostics, git, worktrees and databases they need to work.
            </p>
            <div
              style={{
                display: "flex",
                gap: 14,
                flexWrap: "wrap",
                marginTop: 32,
              }}
            >
              <Link className="btn btn-primary" href="/download">
                <IconDownload /> Download
              </Link>
              <a className="btn btn-ghost" href="#remote">
                What 2.0 brings <IconArrow />
              </a>
            </div>
          </header>

          <div className="ck-shot reveal">
            <Image
              src="/cockpit/hero-terminals.png"
              alt="Remote Pi Cockpit as a multiplexed terminal: several real shells split across panes, with a workspace sidebar and file tree."
              width={3456}
              height={2168}
              priority
              sizes="(max-width: 1180px) 100vw, 1180px"
              style={{ width: "100%", height: "auto" }}
            />
          </div>

          {/* ---------------- AGENTS LIVE IN TABS ---------------- */}
          <section id="agents">
            <div className="section-head reveal" style={{ marginTop: 110 }}>
              <span className="eyebrow">Agents</span>
              <h2>Agents live in tabs.</h2>
              <p>
                A tab is a real terminal, so you run the harness you already
                use: Claude Code, Codex CLI, Pi, OpenCode. Cockpit adds what a
                terminal never had. Each tab shows whether its agent is working,
                waiting on you or done, with a chime when the window is focused
                and a system notification when it is not, and Restart replaces
                the process in place, keeping the scrollback, the folder and the
                session it was running. Nothing to configure: a session started
                outside Cockpit simply reports nothing.
              </p>
            </div>
            <Shot
              src="/cockpit/agent-diff-diagnostics.png"
              alt="An agent working in a Cockpit tab on a git worktree, with an inline green-and-red diff and new diagnostic issues reported."
              width={3456}
              height={2182}
            />
          </section>

          {/* ---------------- 1. REMOTE OVER SSH ---------------- */}
          <section id="remote">
            <div className="section-head reveal" style={{ marginTop: 110 }}>
              <span className="eyebrow">New in 2.0 · Remote</span>
              <h2>Your workspace, on any machine.</h2>
              <p>
                Open a folder on another computer and work in it exactly like a
                local one: the terminals, the file tree, the editor, source
                control and the databases all run on the host. A Raspberry Pi,
                an ARM VM, a beefy Linux box, a Mac or a Windows machine are all
                first-class hosts, from any client.
              </p>
              <p>
                It is plain SSH, and SSH is the only door: Cockpit talks to a
                small <code>cockpit-server</code> on the host through a tunnel,
                with nothing exposed on the network. A new host shows you its
                fingerprint and asks; a host whose key changed is refused. A
                database password stays next to the database it opens, on the
                host, and never travels to your laptop.
              </p>
            </div>
          </section>

          {/* ---------------- 2. SESSIONS OUTLIVE THE CLIENT ---------------- */}
          <section id="sessions">
            <div className="section-head reveal" style={{ marginTop: 110 }}>
              <span className="eyebrow">New in 2.0 · Sessions</span>
              <h2>Close the laptop. The agent keeps working.</h2>
              <p>
                Sessions belong to the host, not to the window you opened them
                from. Disconnect, walk away, come back from another machine, and
                the terminal picks up where it stopped. When the connection
                drops, a banner says so and Cockpit retries: the terminals
                freeze instead of dying.
              </p>
            </div>
          </section>

          {/* ---------------- 3. A VPS WITH ONE CURL ---------------- */}
          <section id="vps">
            <div className="section-head reveal" style={{ marginTop: 110 }}>
              <span className="eyebrow">New in 2.0 · Any Linux box</span>
              <h2>One curl turns a VPS into a host.</h2>
              <p>
                No desktop, no sudo, idempotent, on Linux x86_64 and arm64. The
                flag <code>--service</code> registers a{" "}
                <code>systemd --user</code> unit so the host is ready right
                after a reboot; without it the client starts the server on
                demand over SSH.
              </p>
            </div>
            <div className="reveal" style={{ marginTop: 28, maxWidth: 760 }}>
              <CodeBlock
                label="on the host"
                prompt
                code={`curl -fsSL https://remote-pi.jacobmoura.work/cockpit-server.sh | bash`}
              />
              <p style={{ marginTop: 18, color: "var(--ink-soft)" }}>
                The whole recipe, including pinning a version and keeping the
                server in step with the app, is on the{" "}
                <Link href="/download#vps" className="text-accent underline">
                  download page
                </Link>{" "}
                and in the{" "}
                <Link href="/docs#remote" className="text-accent underline">
                  remote hosts reference
                </Link>
                .
              </p>
            </div>
          </section>

          {/* ---------------- 4. MOBILE CLIENT ---------------- */}
          <section id="mobile">
            <div className="section-head reveal" style={{ marginTop: 110 }}>
              <span className="eyebrow">New in 2.0 · Mobile</span>
              <h2>The same workspace, from a tablet.</h2>
              <p>
                Cockpit on an iPad or an Android tablet is a pure remote client:
                it connects to a host and works there, so the agents run on a
                real machine while you drive them from the couch. Panels become
                drawers on a narrow screen, tabs scroll and reorder by touch,
                and a key bar gives you what a touch keyboard lacks: ESC, Tab,
                Ctrl+C, the arrows and F1 to F12, plus copy and paste.
              </p>
              <p>
                It ships as a direct Android APK, built and signed by the same
                release pipeline as the desktop builds. Grab it on the{" "}
                <Link href="/download#android" className="text-accent underline">
                  download page
                </Link>
                . Prepare the host first, from a desktop Cockpit or with the
                installer above.
              </p>
            </div>
          </section>

          {/* ---------------- 5. DOCUMENTS AS TABS ---------------- */}
          <section id="documents">
            <div className="section-head reveal" style={{ marginTop: 110 }}>
              <span className="eyebrow">New in 2.0 · Documents</span>
              <h2>Your notes, requests and boards are tabs now.</h2>
              <p>
                Next to the terminal where your agent works, Cockpit opens the
                documents the work produces, and your agent writes to the same
                files:
              </p>
              <ul className="ck-list">
                <li>
                  <strong>Notebook</strong>: a <code>.notebook</code> folder of
                  plain markdown notes with tags, <code>[[wiki links]]</code>,
                  inline images and live formatting. Git, Obsidian and your
                  agent see the same files, and{" "}
                  <code>cockpit note add</code> lets the agent leave you one.
                </li>
                <li>
                  <strong>HTTP requests</strong>: write one in the REST Client
                  syntax in a <code>.http</code> file, press ⌘↵ and read the
                  response as JSON, headers or raw text.{" "}
                  <code>cockpit http run</code> fires the same request for the
                  agent.
                </li>
                <li>
                  <strong>Kanban boards</strong> with dependencies between
                  cards, filters by title and label, drag and drop, and markdown
                  in comments.
                </li>
                <li>
                  <strong>Mermaid diagrams</strong> rendered in the markdown
                  preview, offline, in your theme.
                </li>
                <li>
                  <strong>Document window</strong>: open any file in its own
                  light window, from the app or straight from Finder, Explorer
                  or your Linux file manager.
                </li>
                <li>
                  <strong>Gallery</strong>: one click creates and opens any of
                  them, on a local or a remote workspace.
                </li>
              </ul>
            </div>
          </section>

          {/* ---------------- 6. SECRETS ---------------- */}
          <section id="secrets">
            <div className="section-head reveal" style={{ marginTop: 110 }}>
              <span className="eyebrow">New in 2.0 · Secrets</span>
              <h2>Stop pasting tokens into your agent&apos;s prompt.</h2>
              <p>
                A <code>.env.cockpit</code> at the workspace root feeds every
                terminal Cockpit opens there, on local and remote workspaces
                alike. The values it injects are replaced by{" "}
                <code>***</code> in the terminal, in the saved scrollback and in{" "}
                <code>cockpit read-tab</code>, so a secret does not reach the
                screen your agent is reading.
              </p>
            </div>
            <div className="reveal" style={{ marginTop: 28, maxWidth: 760 }}>
              <CodeBlock
                label=".env.cockpit"
                code={`OPENAI_API_KEY=sk-...
GITHUB_TOKEN=ghp_...`}
              />
              <p style={{ marginTop: 18, color: "var(--ink-soft)" }}>
                Keys that change who runs what are never injected (
                <code>PATH</code>, <code>SHELL</code>, <code>HOME</code>,{" "}
                <code>LD_*</code>, <code>DYLD_*</code> and friends), and when the
                file came with the repository, new terminals print a notice
                listing the key names it injected, never the values.
              </p>
            </div>
          </section>

          {/* ---------------- 7. THE AGENT DRIVES THE COCKPIT ---------------- */}
          <section id="cli">
            <div className="section-head reveal" style={{ marginTop: 110 }}>
              <span className="eyebrow">An agentic tmux</span>
              <h2>The agent drives the cockpit.</h2>
              <p>
                A built-in <code>cockpit</code> CLI, on the PATH of its
                terminals and nowhere else, lets an agent open tabs and splits,
                type into another tab, read what it printed, run your
                project&apos;s tasks, query your databases and write notes.
                Local or over SSH, always handled by the Cockpit that owns the
                tab. Database connections are read-only by default and can be
                hidden from the CLI entirely, so an agent queries what you
                allow.
              </p>
            </div>
            <div className="reveal" style={{ marginTop: 28, maxWidth: 760 }}>
              <CodeBlock
                label="Cockpit terminal"
                prompt
                code={`# open a worker beside you and steer it
id=$(cockpit new-tab --cwd ~/proj --title Worker --split h)
cockpit send --tab-id "$id" --enter "pnpm test"

# read what it printed
cockpit read-tab Worker --lines 60

# run and follow the project's tasks
cockpit list-tasks
cockpit read-task npm:dev --lines 80

# open a file, query a database, fire a request, leave a note
cockpit open src/app.ts
cockpit db query --db dev-local --sql "SELECT * FROM orders" --limit 50
cockpit http run api/users.http
cockpit note add notes.notebook --title "What I changed" --body -`}
              />
              <p style={{ marginTop: 18, color: "var(--ink-soft)" }}>
                Every command, flag, and id convention lives in the{" "}
                <Link href="/docs#cli" className="text-accent underline">
                  Cockpit reference
                </Link>
                .
              </p>
            </div>
          </section>

          {/* ---------------- THE IDE EMERGES ---------------- */}
          <section id="ide">
            <div className="section-head reveal" style={{ marginTop: 110 }}>
              <span className="eyebrow">The IDE emerges</span>
              <h2>Viewer, diagnostics, git. When you need them.</h2>
              <p>
                Syntax-highlighted code in ~190 languages, live diagnostics and
                formatting from any language server on your PATH (Dart,
                TypeScript, Python, Go, Rust and more), plus git status and
                one-click worktrees. The agent edits; you review.
              </p>
            </div>
            <Shot
              src="/cockpit/code-viewer.png"
              alt="Cockpit's code viewer showing a Dart file with syntax highlighting, styled documentation comments, and a file path breadcrumb."
              width={2270}
              height={2080}
            />
          </section>

          {/* ---------------- DATABASES AS TABS ---------------- */}
          <section id="database">
            <div className="section-head reveal" style={{ marginTop: 110 }}>
              <span className="eyebrow">Databases</span>
              <h2>Databases as tabs.</h2>
              <p>
                SQLite, Postgres, MySQL, SQL Server, Redis and MongoDB: open
                them as tabs, query them, and let agents do the same through{" "}
                <code>cockpit db</code>.
              </p>
            </div>
            <Shot
              src="/cockpit/database-panel.png"
              alt="Cockpit's Database panel listing Postgres, MySQL, SQL Server, Redis, MongoDB, and an auto-detected SQLite connection."
              width={1116}
              height={1150}
              maxWidth={620}
            />
          </section>

          {/* ---------------- WORKSPACES & REALMS ---------------- */}
          <section id="workspaces">
            <div className="section-head reveal" style={{ marginTop: 110 }}>
              <span className="eyebrow">Workspaces &amp; realms</span>
              <h2>Every context, one click away.</h2>
              <p>
                Group projects into workspaces, workspaces into realms, and fork
                onto a fresh git worktree with your whole layout recreated. Point
                at a folder of repositories and you get a sectioned tree, an
                aggregate git badge and per-repo actions, locally and over SSH.
              </p>
            </div>
          </section>

          {/* ---------------- LAYOUTS & TASKS ---------------- */}
          <section id="layouts">
            <div className="section-head reveal" style={{ marginTop: 110 }}>
              <span className="eyebrow">Committed setup</span>
              <h2>Your environment, in the repo.</h2>
              <p>
                A <code>.ckp</code> file describes the terminals a project opens
                (folders, splits, commands) and can apply itself to every new
                worktree. A <code>.cockpit/tasks.json</code> turns your dev
                servers into play and stop buttons with profiles and reload on
                save, on top of the tasks Cockpit already detects from{" "}
                <code>package.json</code> and <code>pubspec.yaml</code>.
              </p>
            </div>
            <div className="reveal" style={{ marginTop: 28, maxWidth: 760 }}>
              <CodeBlock
                label="dev.ckp"
                code={`autorun: worktree
panes:
  - name: Agent
    cwd: .
    command: claude
  - name: API
    cwd: api
    split: right
    command: npm run dev`}
              />
              <p style={{ marginTop: 18, color: "var(--ink-soft)" }}>
                Build both from scratch in the{" "}
                <Link
                  href="/tutorials/cockpit-layouts"
                  className="text-accent underline"
                >
                  layouts and tasks tutorial
                </Link>
                .
              </p>
            </div>
          </section>

          {/* ---------------- MAKE IT YOURS ---------------- */}
          <section id="yours">
            <div className="section-head reveal" style={{ marginTop: 110 }}>
              <span className="eyebrow">Make it yours</span>
              <h2>Themes, sounds, your language.</h2>
              <p>
                Nine built-in themes, or write your own: one JSON file paints
                the UI, the syntax highlighting and the terminal palette at
                once, inheriting everything you don&apos;t declare. Pick the
                terminal font family, bind a sound to each agent event (turn
                done, action needed, error), and read the whole interface in
                English, Portuguese or Spanish.
              </p>
            </div>
          </section>

          {/* ---------------- PLATFORMS + FINAL CTA ---------------- */}
          <div
            className="reveal"
            style={{
              textAlign: "center",
              maxWidth: 680,
              margin: "120px auto 0",
              paddingBottom: 8,
            }}
          >
            <span className="eyebrow">Get Cockpit</span>
            <h2
              style={{
                fontFamily: "var(--ff-display)",
                fontWeight: 600,
                color: "var(--ink)",
                fontSize: "clamp(30px, 4.4vw, 48px)",
                letterSpacing: "-0.02em",
                lineHeight: 1.04,
                margin: "14px 0 0",
              }}
            >
              Start with a terminal.
            </h2>
            <p
              style={{
                color: "var(--ink-soft)",
                fontSize: 18,
                margin: "16px auto 0",
                maxWidth: 520,
              }}
            >
              Free and open source, for macOS, Windows and Linux, with in-app
              updates on macOS and Windows. Any Linux box becomes a host, and an
              Android tablet becomes a client.
            </p>
            <div
              style={{
                display: "flex",
                gap: 14,
                justifyContent: "center",
                flexWrap: "wrap",
                marginTop: 30,
              }}
            >
              <Link className="btn btn-primary" href="/download">
                <IconDownload /> Download
              </Link>
              <Link className="btn btn-ghost" href="/docs">
                Reference <IconArrow />
              </Link>
              <a
                className="btn btn-ghost"
                href={GITHUB_URL}
                target="_blank"
                rel="noopener noreferrer"
              >
                <IconGithub /> GitHub
              </a>
            </div>
            <p
              style={{
                color: "var(--muted)",
                fontSize: 14,
                marginTop: 40,
              }}
            >
              Part of the <Link href="/remote-pi">Remote Pi</Link> project, which
              is where the phone app, the daemons and the agent mesh live.
            </p>
          </div>
        </div>
      </div>
      <RevealController />
    </div>
  );
}
