import type { Metadata } from "next";
import Link from "next/link";
import { DocsSection, DocsSubsection, InlineCode } from "@/components/docs-shell";
import { CodeBlock } from "@/components/code-block";
import { Callout } from "@/components/callout";
import { Pager } from "@/components/pager";
import { RevealController } from "@/components/landing/reveal-controller";

export const metadata: Metadata = {
  title: "Daemon mode",
  description:
    "Keep a Pi agent alive 24/7: install the supervisor (launchd / systemd --user), register a folder as a daemon, and manage the fleet from one CLI.",
};

export default function DaemonTutorial() {
  return (
    <div className="page">
      <div className="page-body">
        <div className="wrap">
          <div className="tut">
            <header className="page-head reveal" style={{ maxWidth: "none" }}>
              <span className="eyebrow">Tutorial · 4 of 4</span>
              <h1>Daemon mode</h1>
              <p className="lede">
                So far your agents only run while a terminal is open. Daemon
                mode keeps a folder running as a background agent that survives
                logout, restarts on crash, and answers your phone at 3am. This
                is the <em>how</em>; for the <em>why</em> — and how it compares
                to all-in-one platforms — see <Link href="/remote-pi/why">Why Pi</Link>.
              </p>
            </header>

            <article className="prose">
              <DocsSection id="model" title="The shape of it">
          <p>
            One <strong className="text-fg">supervisor</strong> runs per
            machine. Under it sit N background agents — one per folder you
            promote. The supervisor is a normal user service:{" "}
            <InlineCode>launchd</InlineCode> on macOS,{" "}
            <InlineCode>systemd --user</InlineCode> on Linux. It starts at login,
            survives reboots, and respawns any agent that crashes.
          </p>
          <Callout variant="warning" title="Lock down tool permissions first">
            A daemon inherits the same Pi tool permissions your interactive
            session has — <InlineCode>Bash</InlineCode>,{" "}
            <InlineCode>Edit</InlineCode>, <InlineCode>Write</InlineCode> all run{" "}
            <strong className="text-fg">without a prompt</strong>, because no one
            is at the keyboard to approve them. Configure Pi&apos;s tool
            permissions to taste <em className="text-fg">before</em> you promote
            a folder to a 24/7 daemon. A tool-approval gate is on the roadmap.
          </Callout>
        </DocsSection>

        <DocsSection id="install" title="1. Install the supervisor (once per machine)">
          <p>From inside Pi:</p>
          <CodeBlock code="/remote-pi install" label="In Pi" language="text" />
          <p>That single command does two things:</p>
          <ul className="ml-6 list-disc space-y-2">
            <li>
              Installs and activates the user-level supervisor service (
              <InlineCode>launchd</InlineCode> /{" "}
              <InlineCode>systemd --user</InlineCode>), so it auto-starts at
              login and after reboot.
            </li>
            <li>
              Symlinks the <InlineCode>remote-pi</InlineCode> and{" "}
              <InlineCode>pi-supervisord</InlineCode> CLIs into{" "}
              <InlineCode>~/.local/bin/</InlineCode> so you can manage daemons
              from any shell. If that directory isn&apos;t on your{" "}
              <InlineCode>$PATH</InlineCode>, the command prints the line to add.
            </li>
          </ul>
          <p className="text-sm">
            This is a separate, explicit opt-in — it is{" "}
            <strong className="text-fg">not</strong> part of the regular setup
            wizard. You only run it on machines where you want 24/7 agents.
          </p>
        </DocsSection>

        <DocsSection id="create" title="2. Promote a folder to a daemon">
          <p>
            No per-folder setup is needed first — <InlineCode>create</InlineCode>{" "}
            registers any folder and the supervisor injects the daemon&apos;s
            config at spawn (a fixed <InlineCode>assistent</InlineCode>{" "}
            workspace, relay on), so the folder needs no{" "}
            <InlineCode>.pi/remote-pi/</InlineCode> of its own. To reach the
            daemon from your phone, just make sure this machine has been paired
            once — pairing is per-machine, so any earlier{" "}
            <InlineCode>/remote-pi pair</InlineCode> on it counts. Then register:
          </p>
          <CodeBlock
            code={`remote-pi create ~/Movies --name "Video Editor"
# → Daemon registered: id=4e39152d name="Video Editor" cwd=/Users/you/Movies · started`}
            label="Shell"
            language="bash"
          />
          <p>
            The id is a stable hash of the folder path (
            <InlineCode>sha256(realpath)[:8]</InlineCode>), so it survives moves
            and is the same on every machine. With the supervisor running,{" "}
            <InlineCode>create</InlineCode>{" "}
            <strong className="text-fg">starts the daemon right away</strong> —
            there is no separate start step. It restarts on crash and comes back
            after a reboot on its own.
          </p>
          <Callout variant="note" title="One daemon per folder">
            The by-path id rejects a second daemon in the same directory at{" "}
            <InlineCode>create</InlineCode> time. Pairing stays interactive — a
            daemon reuses the keypair and paired devices already set up on this
            machine; it doesn&apos;t show a QR itself.
          </Callout>
        </DocsSection>

        <DocsSection id="fleet" title="3. Manage the fleet">
          <p>
            Every command works as a Pi slash command (
            <InlineCode>/remote-pi …</InlineCode>) and, once the CLI is linked,
            as a plain shell command (<InlineCode>remote-pi …</InlineCode>):
          </p>
          <CodeBlock
            code={`remote-pi daemons                  # list registered daemons + state
remote-pi daemon status            # pid, uptime, restart count
remote-pi daemon send 4e39152d "Cut the first 30s of the latest clip"
remote-pi daemon restart 4e39152d  # restart one daemon by id
remote-pi daemon restart           # ...or the whole fleet (no id)
remote-pi daemon stop 4e39152d     # stop one
remote-pi daemon stop              # stop all`}
            label="Fleet commands"
            language="bash"
          />
          <p>
            A daemon receives a prompt as if a user typed it; its response flows
            back through the same mesh and relay you configured — your phone
            sees it live, and other agents on the machine see it over the local
            mesh.
          </p>
          <DocsSubsection title="Where the logs are">
            <CodeBlock
              code={`# Linux
journalctl --user -u remote-pi-supervisord -f

# macOS
tail -f ~/.pi/remote/supervisord.log`}
              label="Logs"
              language="bash"
            />
            <p>
              Each daemon&apos;s output is forwarded into the supervisor log with
              a <InlineCode>[&lt;cwd&gt;]</InlineCode> prefix, so one stream shows
              the whole fleet.
            </p>
          </DocsSubsection>
        </DocsSection>

        <DocsSection id="cron" title="4. Schedule recurring prompts (cron)">
          <p>
            A daemon only acts when something prompts it.{" "}
            <InlineCode>cron</InlineCode> lets the supervisor be that something on
            a schedule — &ldquo;every weekday at 9am, summarize the new
            PRs&rdquo; — with no one at the keyboard. Jobs target a daemon by id
            and survive reboots along with the supervisor.
          </p>
          <Callout
            variant="warning"
            title="Cron needs the supervisor installed as a service"
          >
            The scheduler runs <em>inside</em> the supervisor, so it only fires
            when the supervisor is installed as a user service. Run{" "}
            <InlineCode>/remote-pi install</InlineCode> (step 1) first — without
            it, <InlineCode>cron add</InlineCode> warns instead of pretending to
            schedule. It is the same launchd / systemd service that keeps your
            daemons alive; there is no second scheduler.
          </Callout>
          <p>
            With a daemon registered (step 2) and the supervisor running, add a
            job. The first argument is the daemon id, then a standard five-field
            cron expression, then the prompt:
          </p>
          <CodeBlock
            code={`# every weekday at 9am, São Paulo time
remote-pi cron add 4e39152d "0 9 * * 1-5" "Summarize the new PRs" --tz America/Sao_Paulo
# → Cron j_ab12 added → daemon 4e39152d: "0 9 * * 1-5" (America/Sao_Paulo). Next run: …`}
            label="Schedule a prompt"
            language="bash"
          />
          <p>
            Runs must be at least <strong className="text-fg">60 seconds</strong>{" "}
            apart — a more frequent expression is rejected with a clear message,
            since every fire spends tokens. Flags on{" "}
            <InlineCode>cron add</InlineCode>:
          </p>
          <ul className="ml-6 list-disc space-y-2">
            <li>
              <InlineCode>--tz Area/City</InlineCode> — run in a specific,
              DST-aware timezone (e.g. <InlineCode>America/Sao_Paulo</InlineCode>
              ). Defaults to the machine&apos;s local time.
            </li>
            <li>
              <InlineCode>--wake</InlineCode> — if the daemon is stopped when the
              job fires, start it first, then send. Default: skip (logged as{" "}
              <InlineCode>skipped_down</InlineCode>).
            </li>
            <li>
              <InlineCode>--no-skip-busy</InlineCode> — send even if the daemon is
              mid-turn. By default a fire is skipped while the daemon is still
              working (<InlineCode>skipped_busy</InlineCode>) so prompts
              don&apos;t pile up on an unfinished turn.
            </li>
            <li>
              <InlineCode>--catchup</InlineCode> — after the supervisor was down,
              fire <em>one</em> missed run on startup. Default off; never replays
              the whole backlog.
            </li>
          </ul>
          <p>
            Each job gets an id like <InlineCode>j_ab12</InlineCode> (printed by{" "}
            <InlineCode>cron add</InlineCode> and <InlineCode>cron list</InlineCode>
            ). Inspect, test, and audit the fleet&apos;s schedule:
          </p>
          <CodeBlock
            code={`remote-pi cron list                # schedule, enabled, last run/status, next run
remote-pi cron run j_ab12          # fire one now, ignoring its schedule
remote-pi cron disable j_ab12      # pause without deleting (enable to resume)
remote-pi cron log --tail 20       # recent fires AND skips
remote-pi cron remove j_ab12       # delete the job`}
            label="Inspect & audit"
            language="bash"
          />
          <p>
            The agent&apos;s reply is fire-and-forget into the mesh — your phone
            and other agents see it live, exactly like a manual{" "}
            <InlineCode>daemon send</InlineCode>. Cron itself only audits the{" "}
            <em>trigger</em>: every fire and every skip appends one line to{" "}
            <InlineCode>~/.pi/remote/cron.jsonl</InlineCode>, which{" "}
            <InlineCode>cron log</InlineCode> tails. Full subcommand reference is
            in the{" "}
            <Link href="/remote-pi/docs#commands-cron" className="text-accent underline">
              docs
            </Link>
            .
          </p>
        </DocsSection>

        <DocsSection id="cleanup" title="Removing a daemon">
          <CodeBlock
            code={`remote-pi remove <id>              # unregister one daemon (folder config kept)
remote-pi uninstall                # remove the supervisor service (registry kept)`}
            label="Cleanup"
            language="bash"
          />
          <p>
            <InlineCode>uninstall</InlineCode> is reversible — re-running{" "}
            <InlineCode>/remote-pi install</InlineCode> later brings every
            registered daemon back. Full flags and paths are in the{" "}
            <Link href="/remote-pi/docs#daemon-mode" className="text-accent underline">
              reference docs
            </Link>
            .
          </p>
        </DocsSection>

            </article>

            <Pager
              prev={{ href: "/remote-pi/tutorials/mesh-remote", label: "Remote mesh" }}
            />
          </div>
        </div>
      </div>
      <RevealController />
    </div>
  );
}
