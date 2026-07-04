import type { Metadata } from "next";
import Link from "next/link";
import Image from "next/image";
import { Callout } from "@/components/callout";
import { CodeBlock } from "@/components/code-block";
import { RevealController } from "@/components/landing/reveal-controller";
import { IconDownload, IconGithub, IconArrow } from "@/components/landing/icons";

export const metadata: Metadata = {
  title: "Cockpit",
  description:
    "Remote Pi Cockpit — a desktop command center for Pi. Run a fleet of AI agents and real terminals side by side, each in its own folder, in one window.",
};

const GITHUB_URL = "https://github.com/jacobaraujo7/remote_pi";

/* requires-Pi line shown next to each download CTA (honest onboarding note) */
function RequiresPi() {
  return (
    <p className="ck-note">Requires the Pi CLI — guided setup on first launch.</p>
  );
}

/* ---------------- features (brief §2, benefit-first) ---------------- */
const FEATURES: { title: string; body: string }[] = [
  {
    title: "Many agents, one window",
    body: "Split the canvas into as many panes as you want — agents, terminals, and files, side by side or stacked. One agent streaming never blocks the others, and your whole layout comes back exactly as you left it.",
  },
  {
    title: "A composer that keeps up",
    body: "Paste or drag images, switch the model, dial reasoning from off to high, type @ to reference files and / to fire the agent's commands. Every choice is remembered per tab.",
  },
  {
    title: "Real terminals",
    body: "Open a genuine shell in any pane — your default shell on macOS and Linux, PowerShell or cmd on Windows. Full color, resize, copy/paste, and tab titles that track what's running.",
  },
  {
    title: "An agent-aware file tree",
    body: "Browse the project on demand with per-type icons. Right-click any folder to spawn an agent or terminal right there, or drag a file straight into the conversation.",
  },
  {
    title: "Read what the agent touches",
    body: "Open Markdown, syntax-highlighted code, images, and SVG inline — hundreds of languages. The viewer reads; the agent does the editing.",
  },
  {
    title: "Sessions you can resume",
    body: "Every agent is a live Pi session in the folder you chose. Watch text, thinking, and tool calls stream in — and reopen a past conversation right where it stopped.",
  },
  {
    title: "Native notifications",
    body: "When an agent finishes a turn and the window is in the background, your OS lets you know. The sidebar also counts agents with new replies, per workspace.",
  },
  {
    title: "Light or dark, your call",
    body: "System, light, or dark theme; careful interface and code fonts; syntax palettes; and zoom for the whole UI when you need it bigger.",
  },
  {
    title: "Multi-project workspaces",
    body: "Open any folder as a workspace and switch in a click without losing state — agents keep running in the background. Each shows its git branch and whether there are uncommitted changes.",
  },
];

export default function CockpitPage() {
  return (
    <div className="page">
      <div className="page-body">
        <div className="wrap">
          {/* ---------------- HERO ---------------- */}
          <header className="page-head reveal" style={{ maxWidth: 820 }}>
            <span className="eyebrow">Remote Pi Cockpit</span>
            <h1>Run a fleet of agents, side by side.</h1>
            <p className="lede">
              Cockpit is a desktop command center for Pi. Open your projects and
              run as many AI agents and real terminals as you want — each in its
              own folder, all in one window. It runs on your machine, with your
              files.
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
              <a className="btn btn-ghost" href="#features">
                Explore the features <IconArrow />
              </a>
            </div>
            <RequiresPi />
          </header>

          <div className="ck-shot reveal">
            <Image
              src="/cockpit-hero.png"
              alt="Remote Pi Cockpit showing three AI agents and a terminal running side by side across panes, with a workspace sidebar and file tree."
              width={1550}
              height={904}
              priority
              sizes="(max-width: 1180px) 100vw, 1180px"
              style={{ width: "100%", height: "auto" }}
            />
          </div>

          {/* ---------------- FEATURES ---------------- */}
          <section id="features">
            <div className="section-head reveal" style={{ marginTop: 110 }}>
              <span className="eyebrow">What&apos;s inside</span>
              <h2>A multiplexer for agents and terminals.</h2>
              <p>
                Not a chat next to an editor — a workspace where shells and AI
                live together, on your own machine.
              </p>
            </div>
            <div
              className="reveal"
              style={{
                display: "grid",
                gridTemplateColumns: "repeat(auto-fit, minmax(264px, 1fr))",
                gap: 18,
                marginTop: 32,
              }}
            >
              {FEATURES.map((f) => (
                <div className="feat-card" key={f.title}>
                  <h3>{f.title}</h3>
                  <p>{f.body}</p>
                </div>
              ))}
            </div>
          </section>

          {/* ---------------- SPOTLIGHT: WORKTREES ---------------- */}
          <section id="worktrees">
            <div className="section-head reveal" style={{ marginTop: 110 }}>
              <span className="eyebrow">Worktrees</span>
              <h2>A new branch, fully set up, in one click.</h2>
              <p>
                Fork your project onto a fresh branch without breaking your flow.
                Cockpit uses git worktrees under the hood — and recreates your
                exact pane-and-tab layout pointed at the new folder.
              </p>
            </div>
            <div
              className="reveal"
              style={{
                display: "grid",
                gridTemplateColumns: "repeat(auto-fit, minmax(280px, 1fr))",
                gap: 18,
                marginTop: 28,
                maxWidth: 760,
              }}
            >
              <div className="feat-card">
                <h3>One click to branch off</h3>
                <p>
                  Spin up a worktree on a new branch and Cockpit rebuilds the same
                  agents, terminals, and tabs — already aimed at the new
                  directory, so you keep working instead of setting up.
                </p>
              </div>
              <div className="feat-card">
                <h3>Clean removal, no surprises</h3>
                <p>
                  Done with it? Removing a worktree warns you first if the branch
                  isn&apos;t merged yet, then tidies up both the folder and the
                  branch for you.
                </p>
              </div>
            </div>
          </section>

          {/* ---------------- SPOTLIGHT: DAEMONS + CRON ---------------- */}
          <section id="daemons">
            <div className="section-head reveal" style={{ marginTop: 110 }}>
              <span className="eyebrow">Always on</span>
              <h2>Agents that outlive the window.</h2>
              <p>
                The same always-on layer behind Remote Pi — now with a desk. Keep
                agents working around the clock and put them on a schedule,
                managed right in the app.
              </p>
            </div>
            <div
              className="reveal"
              style={{
                display: "grid",
                gridTemplateColumns: "repeat(auto-fit, minmax(280px, 1fr))",
                gap: 18,
                marginTop: 28,
                maxWidth: 760,
              }}
            >
              <div className="feat-card">
                <h3>24/7 daemons</h3>
                <p>
                  Promote work to background daemons that run nonstop — create,
                  start, stop, restart, rename, and remove them in-app, with a
                  live &ldquo;supervisor online&rdquo; indicator.
                </p>
              </div>
              <div className="feat-card">
                <h3>Recurring schedules</h3>
                <p>
                  Run agents cron-style: pick the daemon, the time, and the
                  prompt, with skip-if-busy and time zones. Toggle them, run one
                  now, and read the execution log.
                </p>
              </div>
            </div>
          </section>

          {/* ---------------- MESH (honest framing) ---------------- */}
          <section id="mesh">
            <div className="section-head reveal" style={{ marginTop: 110 }}>
              <span className="eyebrow">Mesh</span>
              <h2>Your agents can talk to each other — across machines.</h2>
              <p>
                Cockpit&apos;s onboarding sets up the <code>remote-pi</code>{" "}
                extension, which hands every agent the mesh tools. So an agent in
                one pane can reach another — in the next pane, or paired in from a
                different machine — and they collaborate over the Remote Pi mesh.
                That&apos;s exactly what the screenshot up top is doing.
              </p>
            </div>
            <div className="reveal" style={{ marginTop: 24, maxWidth: 760 }}>
              <Callout title="What this is — and isn't">
                <p>
                  The mesh is a capability of the Remote Pi ecosystem — Pi plus
                  the <code>remote-pi</code> extension — shown off inside Cockpit,
                  not a separate feature of the app. Cockpit doesn&apos;t draw a
                  network map, and you don&apos;t drive its panes from your phone:
                  the agents themselves do the talking.
                </p>
              </Callout>
            </div>
          </section>

          {/* ---------------- CLI ---------------- */}
          <section id="cli">
            <div className="section-head reveal" style={{ marginTop: 110 }}>
              <span className="eyebrow">CLI</span>
              <h2>Drive the panes from inside a pane.</h2>
              <p>
                Cockpit ships a small <code>cockpit</code> command — a control
                mode for its terminals. From any shell in the app, an agent (or
                you) can type into another pane, press keys, open files in the
                viewer, and list what&apos;s open. It&apos;s on the{" "}
                <code>PATH</code> only inside Cockpit&apos;s own terminals, so it
                never leaks into your global shell.
              </p>
            </div>

            <div className="reveal" style={{ marginTop: 28, maxWidth: 760 }}>
              <Callout title="Where it lives">
                <p>
                  The binary is app-managed under <code>~/.cockpit/bin</code> and
                  added to the <code>PATH</code> of Cockpit&apos;s terminals only.
                  Commands target the current pane by default (
                  <code>$COCKPIT_PANE_ID</code>) — pass <code>--tab-id</code> to
                  reach another one.
                </p>
              </Callout>
            </div>

            <div
              className="reveal"
              style={{
                display: "grid",
                gridTemplateColumns: "repeat(auto-fit, minmax(280px, 1fr))",
                gap: 18,
                marginTop: 28,
                maxWidth: 760,
              }}
            >
              <div className="feat-card">
                <h3>Type across panes</h3>
                <p>
                  <code>send</code> writes literal text into a terminal and{" "}
                  <code>send-key</code> presses named keys — <code>Enter</code>,{" "}
                  <code>Tab</code>, <code>Escape</code>, <code>C-c</code> — so one
                  agent can steer another&apos;s shell.
                </p>
              </div>
              <div className="feat-card">
                <h3>Open files in the viewer</h3>
                <p>
                  <code>open &lt;file&gt;</code> (or just <code>cockpit
                  &lt;file&gt;</code>) resolves the path against the pane&apos;s
                  working directory and opens it in a viewer tab beside the
                  terminal.
                </p>
              </div>
              <div className="feat-card">
                <h3>See what&apos;s open</h3>
                <p>
                  <code>list-panes</code> and <code>list-workspaces</code> report
                  the pane and workspace ids you need to target — the same ids{" "}
                  <code>--tab-id</code> accepts.
                </p>
              </div>
            </div>

            <div className="reveal" style={{ marginTop: 28, maxWidth: 760 }}>
              <CodeBlock
                label="Cockpit terminal"
                prompt
                code={`# type a command into this pane and run it
cockpit send "pnpm test"
cockpit send-key Enter

# steer another pane by id
cockpit list-panes
cockpit send --tab-id 2 "git status"
cockpit send-key --tab-id 2 Enter

# open a file in the viewer, next to the terminal
cockpit open src/app/page.tsx`}
              />
            </div>
          </section>

          {/* ---------------- PLATFORMS ---------------- */}
          <section id="platforms">
            <div className="section-head reveal" style={{ marginTop: 110 }}>
              <span className="eyebrow">Platforms</span>
              <h2>macOS today, Windows and Linux too.</h2>
              <p>
                Cockpit ships signed and notarized on macOS, with Windows{" "}
                (<code>.exe</code>) and Linux (<code>.deb</code>/<code>.rpm</code>)
                installers from the same release pipeline. It drives a local Pi
                install rather than bundling one — the first-launch onboarding
                checks your setup and guides anything that&apos;s missing.
              </p>
            </div>
          </section>

          {/* ---------------- FINAL CTA ---------------- */}
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
              Bring your whole fleet into one window.
            </h2>
            <p
              style={{
                color: "var(--ink-soft)",
                fontSize: 18,
                margin: "16px auto 0",
                maxWidth: 520,
              }}
            >
              Free and open source. Download the build for your platform and pair
              it with the Pi you already run.
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
              <a
                className="btn btn-ghost"
                href={GITHUB_URL}
                target="_blank"
                rel="noopener noreferrer"
              >
                <IconGithub /> GitHub
              </a>
            </div>
            <div style={{ display: "flex", justifyContent: "center" }}>
              <RequiresPi />
            </div>
          </div>
        </div>
      </div>
      <RevealController />
    </div>
  );
}
