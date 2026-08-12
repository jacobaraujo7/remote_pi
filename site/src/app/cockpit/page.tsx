import type { Metadata } from "next";
import Link from "next/link";
import Image from "next/image";
import { CodeBlock } from "@/components/code-block";
import { RevealController } from "@/components/landing/reveal-controller";
import { IconDownload, IconGithub, IconArrow } from "@/components/landing/icons";

const pageTitle = "Cockpit: Just a terminal. Until your agents need more.";
const pageDescription =
  "A fast, local, multiplexed terminal where an IDE emerges around your agents: code viewer, diagnostics, git, databases.";

export const metadata: Metadata = {
  title: { absolute: pageTitle },
  description: pageDescription,
  openGraph: {
    type: "website",
    url: "https://remote-pi.jacobmoura.work/cockpit",
    title: pageTitle,
    description: pageDescription,
    siteName: "Remote Pi",
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
          {/* ---------------- HERO / JUST A TERMINAL ---------------- */}
          <header className="page-head reveal" style={{ maxWidth: 820 }}>
            <span className="eyebrow">Remote Pi Cockpit</span>
            <h1>Just a terminal. Until your agents need more.</h1>
            <p className="lede">
              A fast, multiplexed terminal, 100% local with no cloud and no
              account, where putting an agent to work makes an IDE emerge
              around it. On your machine.
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
              <a className="btn btn-ghost" href="#agents">
                See it grow <IconArrow />
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
                Any tab can be a live Pi agent: streaming rich markdown, taking
                images, editing your code while you watch the diff.
              </p>
            </div>
            <Shot
              src="/cockpit/agent-diff-diagnostics.png"
              alt="An agent working in a Cockpit tab on a git worktree, with an inline green-and-red diff and new diagnostic issues reported."
              width={3456}
              height={2182}
            />
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

          {/* ---------------- AGENTS DRIVE THE COCKPIT ---------------- */}
          <section id="cli">
            <div className="section-head reveal" style={{ marginTop: 110 }}>
              <span className="eyebrow">An agentic tmux</span>
              <h2>Agents drive the cockpit.</h2>
              <p>
                A built-in <code>cockpit</code> CLI, available only inside its
                terminals, lets an agent open tabs, type into them, read their
                output, run your project&apos;s tasks, and query your databases.
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

# open a file in the viewer, query a database
cockpit open src/app.ts
cockpit db query --db dev-local --sql "SELECT * FROM orders" --limit 50`}
              />
              <p style={{ marginTop: 18, color: "var(--ink-soft)" }}>
                Every command, flag, and id convention lives in the{" "}
                <Link href="/cockpit/docs#cli" className="text-accent underline">
                  Cockpit reference
                </Link>
                .
              </p>
            </div>
          </section>

          {/* ---------------- WORKSPACES & REALMS ---------------- */}
          <section id="workspaces">
            <div className="section-head reveal" style={{ marginTop: 110 }}>
              <span className="eyebrow">Workspaces &amp; realms</span>
              <h2>Every context, one click away.</h2>
              <p>
                Group projects into workspaces, workspaces into realms, and
                fork onto a fresh git worktree with your whole layout recreated.
              </p>
            </div>
          </section>

          {/* ---------------- LAYOUTS & TASKS ---------------- */}
          <section id="layouts">
            <div className="section-head reveal" style={{ marginTop: 110 }}>
              <span className="eyebrow">Committed setup</span>
              <h2>Your environment, in the repo.</h2>
              <p>
                A <code>.ckp</code> file describes the terminals a project
                opens — folders, splits, commands — and can apply itself to
                every new worktree. A <code>.cockpit/tasks.json</code> turns
                your dev servers into play/stop buttons with profiles and
                reload on save, on top of the tasks Cockpit already detects
                from <code>package.json</code> and <code>pubspec.yaml</code>.
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
                the UI, the syntax highlighting, and the terminal palette at
                once, inheriting everything you don&apos;t declare. Pick the
                terminal font family, bind a sound to each agent event — turn
                done, action needed, error — and read the whole interface in
                English, Portuguese, or Spanish.
              </p>
            </div>
          </section>

          {/* ---------------- TURN STATUS ---------------- */}
          <section id="status">
            <div className="section-head reveal" style={{ marginTop: 110 }}>
              <span className="eyebrow">Turn status</span>
              <h2>You always know who&apos;s working.</h2>
              <p>
                Cockpit hooks into Claude Code and Codex CLI, so each tab shows
                whether its agent is working, waiting on you, or done — with a
                chime when the window is focused and a system notification when
                it isn&apos;t. Nothing to configure: a session started outside
                Cockpit simply reports nothing.
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
              Free and open source, for macOS, Windows, and Linux — signed,
              with in-app updates.
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
              <Link className="btn btn-ghost" href="/cockpit/docs">
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
              Part of the <Link href="/">Remote Pi ecosystem</Link>, where daemons,
              schedules, and the agent mesh live there.
            </p>
          </div>
        </div>
      </div>
      <RevealController />
    </div>
  );
}
