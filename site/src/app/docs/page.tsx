import type { Metadata } from "next";
import Link from "next/link";
import {
  DocsSection,
  DocsSubsection,
  InlineCode,
  DocsTable,
} from "@/components/docs-shell";
import { CodeBlock } from "@/components/code-block";
import { DocsToc, type TocItem } from "@/components/docs-toc";
import { RevealController } from "@/components/landing/reveal-controller";

export const metadata: Metadata = {
  title: "Docs",
  description:
    "Reference for Remote Pi: the relay, protocol & security, the full command reference, configuration files, and troubleshooting.",
};

const GITHUB_URL = "https://github.com/jacobaraujo7/remote_pi";
const PI_URL = "https://github.com/earendil-works/pi";
const RELAY_README_URL =
  "https://github.com/jacobaraujo7/remote_pi/blob/main/relay/README.md";
const ISSUES_URL = "https://github.com/jacobaraujo7/remote_pi/issues";

const DOCS_TOC: TocItem[] = [
  { id: "quick-start", label: "Quick start" },
  { id: "what-it-does", label: "What it does" },
  { id: "install", label: "Install" },
  { id: "using-remote-pi", label: <>Using <InlineCode>/remote-pi</InlineCode></> },
  { id: "pairing", label: "Pairing a mobile device" },
  { id: "quick-actions", label: "Quick actions from the phone" },
  { id: "agent-network", label: "Agent network" },
  { id: "daemon-mode", label: "Daemon mode" },
  {
    id: "relay",
    label: "The relay",
    sub: [
      { id: "community-relay", label: "Community relay" },
      { id: "self-host", label: "Self-host" },
      { id: "point-pi", label: "Point Pi at your relay" },
    ],
  },
  { id: "protocol", label: "Protocol & Security" },
  {
    id: "commands",
    label: "Command reference",
    sub: [
      { id: "commands-local", label: "Local session" },
      { id: "commands-daemon", label: "Daemon fleet" },
      { id: "commands-cron", label: "Daemon cron" },
    ],
  },
  { id: "config", label: "Configuration files" },
  {
    id: "troubleshooting",
    label: "Troubleshooting",
    sub: [
      { id: "footer-stuck", label: "Stuck on pairing" },
      { id: "timeout-mobile", label: "Mobile times out" },
      { id: "timeout-request", label: "Reply never arrives" },
      { id: "one-pi-per-cwd", label: "One Pi per cwd" },
    ],
  },
  { id: "links", label: "Links" },
];

export default function DocsPage() {
  return (
    <div className="page">
      <div className="page-body">
        <div className="wrap">
          <header className="page-head reveal">
            <span className="eyebrow">Documentation</span>
            <h1>Remote Pi docs</h1>
            <div className="meta-line">
              <span>Last updated: 2026-05-31</span>
              <span>License: MIT</span>
            </div>
            <p className="lede">
              This is the <strong className="text-fg">reference</strong>. Remote
              Pi is a mesh for coding agents: agents on the same machine talk
              through a local UDS broker, agents on different machines reach each
              other through an open-source relay, and your phone authenticates
              new peers and drives sessions. The first supported harness is the{" "}
              <a
                className="text-accent underline"
                href={PI_URL}
                target="_blank"
                rel="noopener noreferrer"
              >
                Pi coding agent
              </a>
              ; <InlineCode>/remote-pi</InlineCode> wires everything up. To{" "}
              <strong className="text-fg">learn by doing</strong>, start with
              the{" "}
              <Link href="/tutorials" className="text-accent underline">
                tutorials
              </Link>
              ; for <strong className="text-fg">why</strong> it works this way,
              see{" "}
              <Link href="/why" className="text-accent underline">
                Why Pi
              </Link>
              . The pages below are for looking things up.
            </p>
          </header>

          <div className="docs-layout">
            <DocsToc items={DOCS_TOC} />

            <article className="prose docs-article">
              {/* ── Pointers into the tutorials ─────────────────────────── */}

              <DocsSection id="quick-start" title="Quick start">
        <p>
          Install the plugin, run the setup wizard, and pair your phone in a few
          commands — then send your first prompt from the app. The full
          walkthrough, including the mobile side, is a tutorial.
        </p>
        <p>
          →{" "}
          <Link href="/tutorials/getting-started" className="text-accent underline">
            See the Getting started tutorial
          </Link>
          .
        </p>
      </DocsSection>

      <DocsSection id="what-it-does" title="What it does">
        <p>
          Remote Pi adds two independent layers on top of Pi. The{" "}
          <strong className="text-fg">agent network</strong> lets agents
          discover and message each other — over a local socket on one machine,
          or through the relay across PCs. The{" "}
          <strong className="text-fg">mobile control plane</strong> is your
          phone: it authenticates new peers into the mesh and drives sessions.
          Each is covered hands-on:
        </p>
        <ul className="ml-6 list-disc space-y-2">
          <li>
            <Link href="/tutorials/mesh-local" className="text-accent underline">
              Local mesh
            </Link>{" "}
            — agents discovering and messaging on the same machine.
          </li>
          <li>
            <Link href="/tutorials/mesh-remote" className="text-accent underline">
              Remote mesh
            </Link>{" "}
            — routing between agents on different PCs.
          </li>
          <li>
            <Link href="/tutorials/getting-started" className="text-accent underline">
              Getting started
            </Link>{" "}
            — pairing your phone and driving an agent from it.
          </li>
        </ul>
      </DocsSection>

      <DocsSection id="install" title="Install">
        <p>
          Requirements: Node 20+ and Pi (the host coding agent). Remote Pi
          installs as a Pi plugin with{" "}
          <InlineCode>pi install npm:remote-pi</InlineCode>, which self-registers
          the <InlineCode>/remote-pi</InlineCode> slash command and deploys the
          agent-network skill. The complete setup — wizard, pairing, first
          command — is in the tutorial.
        </p>
        <p>
          →{" "}
          <Link href="/tutorials/getting-started" className="text-accent underline">
            See the Getting started tutorial
          </Link>
          . Daemon mode has its own one-time install — see{" "}
          <a href="#daemon-mode" className="text-accent underline">
            Daemon mode
          </a>{" "}
          below.
        </p>
      </DocsSection>

      <DocsSection id="using-remote-pi" title="Using /remote-pi">
        <p>
          <InlineCode>/remote-pi</InlineCode> is the everyday entry point. The
          first run opens a short wizard (agent name, whether to use the relay)
          that creates the per-folder config; later runs join the local mesh and
          start the relay automatically. Re-run the wizard with{" "}
          <InlineCode>/remote-pi setup</InlineCode>. Every subcommand is in the{" "}
          <a href="#commands" className="text-accent underline">
            command reference
          </a>
          .
        </p>
        <p>
          →{" "}
          <Link href="/tutorials/getting-started" className="text-accent underline">
            See the Getting started tutorial
          </Link>{" "}
          for the guided flow.
        </p>
      </DocsSection>

      <DocsSection id="pairing" title="Pairing a mobile device">
        <p>
          <InlineCode>/remote-pi pair</InlineCode> prints a QR (and a copy-paste
          URI); scan it with the Remote Pi app. Pairing is{" "}
          <strong className="text-fg">per machine</strong> — once a device is
          paired, every Pi process on that machine accepts it. Manage devices
          with <InlineCode>/remote-pi devices</InlineCode> and{" "}
          <InlineCode>/remote-pi revoke &lt;shortid&gt;</InlineCode> (see the{" "}
          <a href="#commands" className="text-accent underline">
            command reference
          </a>
          ).
        </p>
        <p>
          →{" "}
          <Link href="/tutorials/getting-started" className="text-accent underline">
            See the Getting started tutorial
          </Link>
          .
        </p>
      </DocsSection>

      <DocsSection id="quick-actions" title="Quick actions from the phone">
        <p>
          Beyond chatting, the app drives a session with a small set of typed
          actions — <strong className="text-fg">compact context</strong>,{" "}
          <strong className="text-fg">new session</strong>,{" "}
          <strong className="text-fg">set model</strong>, and{" "}
          <strong className="text-fg">set thinking</strong> level. The model
          picker reads live from the host, so it always reflects what that
          machine can run. The full vocabulary, wire format, and fallback
          semantics live in{" "}
          <a
            className="text-accent underline"
            href={`${GITHUB_URL}/blob/main/PROTOCOL.md`}
            target="_blank"
            rel="noopener noreferrer"
          >
            PROTOCOL.md
          </a>{" "}
          (the <em>App actions</em> section).
        </p>
        <p>
          →{" "}
          <Link href="/tutorials/getting-started" className="text-accent underline">
            See the Getting started tutorial
          </Link>
          .
        </p>
      </DocsSection>

      <DocsSection id="agent-network" title="Agent network">
        <p>
          Each agent is a peer in a mesh. The LLM gets three tools —{" "}
          <InlineCode>list_peers</InlineCode> (who is online),{" "}
          <InlineCode>agent_send</InlineCode> (send with an ACK), and{" "}
          <InlineCode>get_messages</InlineCode> (drain the inbox). On one
          machine, peers talk over a Unix-domain-socket broker; across machines,
          the same <InlineCode>agent_send</InlineCode> routes through the relay,
          addressing remote peers as <InlineCode>pc_label:peer</InlineCode>. Both
          paths are covered hands-on:
        </p>
        <ul className="ml-6 list-disc space-y-2">
          <li>
            <Link href="/tutorials/mesh-local" className="text-accent underline">
              Local mesh
            </Link>{" "}
            — the broker, the three tools, a concrete exchange.
          </li>
          <li>
            <Link href="/tutorials/mesh-remote" className="text-accent underline">
              Remote mesh
            </Link>{" "}
            — cross-PC addressing and what an ACK does (and doesn&apos;t)
            guarantee.
          </li>
        </ul>
      </DocsSection>

      <DocsSection id="daemon-mode" title="Daemon mode">
        <p>
          Promote a folder to a 24/7 background agent: run{" "}
          <InlineCode>/remote-pi install</InlineCode> once per machine to install
          the supervisor (launchd on macOS,{" "}
          <InlineCode>systemd --user</InlineCode> on Linux) and link the CLI,
          then <InlineCode>remote-pi create &lt;folder&gt; --name &quot;…&quot;</InlineCode>{" "}
          to register and start a daemon. One supervisor per machine, N daemons
          under it. Every command is in the{" "}
          <a href="#commands" className="text-accent underline">
            command reference
          </a>{" "}
          below.
        </p>
        <p>
          → <Link href="/tutorials/daemon" className="text-accent underline">
            See the Daemon mode tutorial
          </Link>{" "}
          for the full how-to; the <em>why</em> (and how it compares to
          all-in-one platforms) is{" "}
          <Link href="/why" className="text-accent underline">
            Why Pi
          </Link>
          .
        </p>
      </DocsSection>

      {/* ── Reference ───────────────────────────────────────────────────── */}

      <DocsSection id="relay" title="The relay">
        <p>
          The relay is the only network-touching piece of Remote Pi. In the
          current MVP it sees both message payloads (forwarded but never logged
          or inspected by the community operator) and connection metadata: which
          keypair is online, which room/cwd identifiers exist, message timing,
          sizes. Traffic is encrypted in transit (TLS) and peers authenticate
          with Ed25519 pairing, but payloads are not encrypted at the
          application layer — see{" "}
          <a href="#protocol" className="text-accent underline">
            Protocol &amp; Security
          </a>{" "}
          and the Privacy Policy, section 9, for the full picture.
        </p>
        <p>
          The relay also <strong className="text-fg">persists a small SQLite
          table</strong> called <InlineCode>mesh_versions</InlineCode> — blobs
          signed by your Owner key listing the Pi devices that belong to your
          mesh (a few KB per Owner). The relay verifies the Ed25519
          signature on every <InlineCode>POST /mesh/&lt;owner_pk_hash&gt;</InlineCode>{" "}
          and stores what you signed; it never decides membership itself.
          New devices restoring your Owner key recover their peer list from
          this blob. A relay compromise means DoS, not impersonation. See the{" "}
          <a
            className="text-accent underline"
            href={`${GITHUB_URL}/blob/main/PROTOCOL.md`}
            target="_blank"
            rel="noopener noreferrer"
          >
            PROTOCOL.md
          </a>{" "}
          mesh-membership section for the wire format.
        </p>
        <p>You have two options.</p>

        <DocsSubsection id="community-relay" title="Option A — Use the community relay">
          <p>
            <InlineCode>https://relay-rp1.jacobmoura.work</InlineCode> (default).
            Zero setup. Good for trying things out or for casual use.
            (Internally the extension uses the WebSocket form{" "}
            <InlineCode>wss://…</InlineCode> — both schemes point at the same
            endpoint.)
          </p>
          <p>Caveats:</p>
          <ul className="ml-6 list-disc space-y-2">
            <li>Shared infrastructure — availability is best-effort.</li>
            <li>
              <strong className="text-fg">TLS in transit is the only network protection</strong>
              {" "}— the relay operator sees plaintext envelopes (payloads,
              routing metadata, peer pubkeys, timing). Self-host for
              confidentiality from the operator.
            </li>
            <li>
              <strong className="text-fg">No IP allow-listing or VPN gating</strong>{" "}
              built in. Anyone with a paired keypair can connect; layer a
              VPN on top via Option B if you want network-level isolation.
            </li>
          </ul>
        </DocsSubsection>

        <DocsSubsection id="self-host" title="Option B — Self-host (recommended for privacy)">
          <p>
            Run the relay yourself in Docker and put it behind a VPN like{" "}
            <a className="text-accent underline" href="https://tailscale.com" target="_blank" rel="noopener noreferrer">Tailscale</a>,{" "}
            <a className="text-accent underline" href="https://www.wireguard.com" target="_blank" rel="noopener noreferrer">WireGuard</a>,
            or your own VPC. Because the relay&apos;s network-level protection
            is just TLS + keypair authentication, layering a VPN on top means{" "}
            <strong className="text-fg">only your devices</strong> can even
            reach the WebSocket port — defense in depth.
          </p>
          <p>
            Quick Docker outline (see the{" "}
            <a className="text-accent underline" href={`${RELAY_README_URL}#self-hosted-relay-recommended-for-privacy`} target="_blank" rel="noopener noreferrer">
              relay README
            </a>{" "}
            for the full setup, environment variables, and reverse-proxy
            guidance):
          </p>
          <CodeBlock
            code={`docker run -d \\
  --name remote-pi-relay \\
  -p 3000:3000 \\
  -v remote-pi-data:/data \\
  --restart unless-stopped \\
  jacobmoura7/remote-pi-relay`}
            label="On your relay host"
            language="bash"
          />
          <p>
            The <InlineCode>-v remote-pi-data:/data</InlineCode> mount is
            required — that&apos;s where the relay keeps{" "}
            <InlineCode>mesh.db</InlineCode> (the Owner-signed mesh blobs).
            Skip the volume and the table is wiped on every container restart,
            forcing every client to re-publish.
          </p>
          <p>
            The relay serves the WebSocket upgrade,{" "}
            <InlineCode>/health</InlineCode>, and{" "}
            <InlineCode>/mesh/&lt;owner_pk_hash&gt;</InlineCode> on the same
            port (default 3000) — point your reverse proxy at one upstream
            and you&apos;re done. Use <InlineCode>/health</InlineCode> for
            liveness probes (Coolify, Kubernetes, Fly health checks).
          </p>
          <p>
            Bind the container to your VPN interface, terminate TLS in a reverse
            proxy, and point both your Pi and your phone at the resulting{" "}
            <InlineCode>https://…</InlineCode> URL.
          </p>
        </DocsSubsection>

        <DocsSubsection id="point-pi" title="Pointing Pi at your own relay">
          <p>Once your relay is reachable, tell the extension:</p>
          <CodeBlock
            code="/remote-pi set-relay https://relay.yourdomain.tld"
            label="In Pi"
            language="text"
          />
          <p>
            The URL must be <InlineCode>http://</InlineCode> or{" "}
            <InlineCode>https://</InlineCode> —{" "}
            <InlineCode>wss://</InlineCode> / <InlineCode>ws://</InlineCode>{" "}
            are rejected at validation. The extension converts to the
            WebSocket form internally when it opens the connection, so you
            can paste whatever URL your reverse proxy or PaaS dashboard
            exposes.
          </p>
          <p>
            This writes <InlineCode>~/.pi/remote/config.json</InlineCode> with{" "}
            <InlineCode>{`{ "relay": "..." }`}</InlineCode>. Resolution order
            (highest precedence first):
          </p>
          <ol className="ml-6 list-decimal space-y-2">
            <li>
              <InlineCode>REMOTE_PI_RELAY</InlineCode> environment variable
              (CI / one-off overrides)
            </li>
            <li><InlineCode>~/.pi/remote/config.json</InlineCode></li>
            <li>
              The built-in default (
              <InlineCode>https://relay-rp1.jacobmoura.work</InlineCode>)
            </li>
          </ol>
          <p>Verify the active URL and its source with:</p>
          <CodeBlock code="/remote-pi config" label="In Pi" language="text" />
          <p>
            To switch URLs while connected: <InlineCode>/remote-pi stop</InlineCode>{" "}
            then <InlineCode>/remote-pi</InlineCode> again. The mobile app has
            its own relay-URL setting in its preferences pane — keep both
            pointing at the same relay.
          </p>
        </DocsSubsection>
      </DocsSection>

      <DocsSection id="protocol" title="Protocol & Security">
        <p>
          The canonical spec for everything wire-level — envelope format,
          identity model (Owner key + per-device subkeys), ACK protocol,
          cross-PC routing, mesh membership, trust model, and failure modes
          — lives in{" "}
          <a
            className="text-accent underline"
            href={`${GITHUB_URL}/blob/main/PROTOCOL.md`}
            target="_blank"
            rel="noopener noreferrer"
          >
            PROTOCOL.md
          </a>{" "}
          on GitHub. It is the source of truth that the Pi extension, the
          mobile apps, and the relay all implement against. Read it when you
          need exact behavior or when writing a new harness adapter.
        </p>
        <p>
          <strong className="text-fg">Security posture, in short.</strong>{" "}
          Connections to the relay are{" "}
          <strong className="text-fg">encrypted in transit (TLS)</strong>, and
          devices authenticate each other with{" "}
          <strong className="text-fg">Ed25519 pairing</strong>, so paired peers
          verify identity cryptographically. Message payloads are{" "}
          <strong className="text-fg">not</strong> encrypted at the application
          layer — the relay operator could in principle read plaintext in memory
          while forwarding. If you need confidentiality from the relay operator,{" "}
          <a href="#self-host" className="text-accent underline">
            self-host the relay
          </a>{" "}
          behind a VPN. The Privacy Policy, section 9, restates this in plain
          language, and PROTOCOL.md is the deep dive that matches the code.
        </p>
      </DocsSection>

      <DocsSection id="commands" title="Command reference">
        <p>
          Every command works as a Pi slash command (interactive) and as a
          shell-level <InlineCode>remote-pi &lt;subcommand&gt;</InlineCode>{" "}
          when the package is installed globally (
          <InlineCode>npm install -g remote-pi</InlineCode>).
        </p>

        <DocsSubsection
          id="commands-local"
          title="Local session — one Pi, one terminal"
        >
          <DocsTable
            headers={["Command", "Description"]}
            rows={[
              [
                <InlineCode key="c">/remote-pi</InlineCode>,
                "Connect (join local mesh + start relay), or run setup on first use",
              ],
              [
                <InlineCode key="c">/remote-pi setup</InlineCode>,
                "Run the setup wizard and update local config",
              ],
              [
                <InlineCode key="c">/remote-pi status</InlineCode>,
                "Show local mesh + relay status",
              ],
              [
                <InlineCode key="c">/remote-pi peers</InlineCode>,
                "List local and cross-PC mesh peers, grouped by PC label",
              ],
              [
                <InlineCode key="c">/remote-pi stop</InlineCode>,
                <>Stop everything for <em>this</em> terminal (mesh + relay)</>,
              ],
              [
                <InlineCode key="c">/remote-pi pair [--ttl &lt;seconds&gt;]</InlineCode>,
                "Show QR + copy-paste pairing URI for a new mobile device (QR valid 60s by default; --ttl clamps to 10–600s)",
              ],
              [
                <InlineCode key="c">/remote-pi devices</InlineCode>,
                "List paired mobile devices (online/offline per device)",
              ],
              [
                <InlineCode key="c">/remote-pi revoke &lt;shortid&gt;</InlineCode>,
                "Revoke a paired device by its shortid (brings the relay up first, like pair, to notify the device)",
              ],
              [
                <InlineCode key="c">/remote-pi set-relay &lt;url&gt;</InlineCode>,
                "Persist a new relay URL (http:// or https://)",
              ],
            ]}
          />
        </DocsSubsection>

        <DocsSubsection
          id="commands-daemon"
          title="Daemon fleet — one supervisor, N background Pis"
        >
          <p className="text-sm">
            See <a href="#daemon-mode" className="text-accent underline">Daemon mode</a> for the overview and the{" "}
            <Link href="/tutorials/daemon" className="text-accent underline">Daemon mode tutorial</Link> for the full how-to.
          </p>
          <DocsTable
            headers={["Command", "Description"]}
            rows={[
              [
                <InlineCode key="c">/remote-pi create &lt;cwd&gt; [--name X]</InlineCode>,
                "Register a folder as a daemon (starts it when the supervisor is running)",
              ],
              [
                <InlineCode key="c">/remote-pi remove &lt;id&gt;</InlineCode>,
                "Unregister a daemon (local config preserved)",
              ],
              [
                <InlineCode key="c">/remote-pi daemons</InlineCode>,
                "List registered daemons + state",
              ],
              [
                <InlineCode key="c">/remote-pi daemon start [&lt;id&gt;]</InlineCode>,
                "Start one daemon by id, or every registered daemon with no id",
              ],
              [
                <InlineCode key="c">/remote-pi daemon stop [&lt;id&gt;]</InlineCode>,
                <>
                  Stop one daemon by id, or every running daemon with no id (
                  <InlineCode>/remote-pi stop</InlineCode> stops only the local
                  terminal)
                </>,
              ],
              [
                <InlineCode key="c">/remote-pi daemon restart [&lt;id&gt;]</InlineCode>,
                "Restart one daemon by id, or every daemon with no id",
              ],
              [
                <InlineCode key="c">/remote-pi daemon status</InlineCode>,
                "Detailed runtime status (pid, uptime, restart count)",
              ],
              [
                <InlineCode key="c">/remote-pi daemon send &lt;id&gt; &quot;&lt;text&gt;&quot;</InlineCode>,
                "Send a prompt to a specific daemon",
              ],
              [
                <InlineCode key="c">/remote-pi install</InlineCode>,
                <>
                  Install <InlineCode>pi-supervisord</InlineCode> as a system
                  service <strong className="text-fg">and</strong> symlink the{" "}
                  <InlineCode>remote-pi</InlineCode> CLI into{" "}
                  <InlineCode>~/.local/bin/</InlineCode>
                </>,
              ],
              [
                <InlineCode key="c">/remote-pi uninstall</InlineCode>,
                <>
                  Remove the system service <strong className="text-fg">and</strong>{" "}
                  the <InlineCode>~/.local/bin</InlineCode> symlinks (daemon
                  registry preserved)
                </>,
              ],
            ]}
          />
        </DocsSubsection>

        <DocsSubsection
          id="commands-cron"
          title="Daemon cron — scheduled prompts"
        >
          <p className="text-sm">
            Schedule recurring prompts to a daemon. The scheduler runs{" "}
            <strong className="text-fg">inside the supervisor</strong>, so it
            only fires when the supervisor is installed as a service (
            <a href="#daemon-mode" className="text-accent underline">
              Daemon mode
            </a>{" "}
            / <InlineCode>/remote-pi install</InlineCode>) — otherwise{" "}
            <InlineCode>cron add</InlineCode> warns instead of scheduling. See
            the{" "}
            <Link href="/tutorials/daemon#cron" className="text-accent underline">
              Daemon mode tutorial
            </Link>{" "}
            for the walkthrough.
          </p>
          <DocsTable
            headers={["Command", "Description"]}
            rows={[
              [
                <InlineCode key="c">
                  /remote-pi cron add &lt;id&gt; &quot;&lt;expr&gt;&quot;
                  &quot;&lt;prompt&gt;&quot; [--tz Area/City] [--wake]
                  [--no-skip-busy] [--catchup]
                </InlineCode>,
                "Schedule a recurring prompt to a daemon (5-field cron expression; runs must be ≥60s apart)",
              ],
              [
                <InlineCode key="c">/remote-pi cron list</InlineCode>,
                "List jobs: schedule, enabled, last run / status, next run",
              ],
              [
                <InlineCode key="c">/remote-pi cron run &lt;jobId&gt;</InlineCode>,
                "Fire a job now, ignoring its schedule",
              ],
              [
                <InlineCode key="c">/remote-pi cron enable &lt;jobId&gt;</InlineCode>,
                "Resume a paused job",
              ],
              [
                <InlineCode key="c">/remote-pi cron disable &lt;jobId&gt;</InlineCode>,
                "Pause a job without deleting it",
              ],
              [
                <InlineCode key="c">/remote-pi cron remove &lt;jobId&gt;</InlineCode>,
                "Delete a job",
              ],
              [
                <InlineCode key="c">/remote-pi cron log [&lt;jobId&gt;] [--tail N]</InlineCode>,
                <>
                  Tail the fire / skip audit log (default N = 20), optionally for
                  one job
                </>,
              ],
            ]}
          />
          <ul className="ml-6 list-disc space-y-2">
            <li>
              <strong className="text-fg">Minimum interval 60s.</strong> A more
              frequent expression is rejected (each fire spends tokens). Croner
              syntax — five fields (
              <InlineCode>min hour day-of-month month day-of-week</InlineCode>),
              plus an optional seconds field, still bounded by the 60s floor.
            </li>
            <li>
              <strong className="text-fg">Timezone per job.</strong>{" "}
              <InlineCode>--tz Area/City</InlineCode> resolves DST; without it a
              job runs in the machine&apos;s local time.
            </li>
            <li>
              <strong className="text-fg">Overlap &amp; downtime.</strong> A fire
              is skipped while the daemon is mid-turn (
              <InlineCode>--no-skip-busy</InlineCode> overrides), skipped if the
              daemon is down (<InlineCode>--wake</InlineCode> starts it first),
              and at most one missed run is replayed on startup (
              <InlineCode>--catchup</InlineCode>, off by default).
            </li>
            <li>
              <strong className="text-fg">Audit.</strong> Every fire{" "}
              <em>and</em> every skip appends one line to{" "}
              <InlineCode>~/.pi/remote/cron.jsonl</InlineCode> with a{" "}
              <InlineCode>result</InlineCode> of{" "}
              <InlineCode>delivered</InlineCode>,{" "}
              <InlineCode>deliver_failed</InlineCode>,{" "}
              <InlineCode>woke_and_delivered</InlineCode>,{" "}
              <InlineCode>skipped_busy</InlineCode>,{" "}
              <InlineCode>skipped_down</InlineCode>, or{" "}
              <InlineCode>skipped_disabled</InlineCode>. The agent&apos;s reply
              itself is fire-and-forget into the mesh — cron records the trigger,
              not the response.
            </li>
          </ul>
        </DocsSubsection>
        <p>The footer in the Pi TUI reflects state live:</p>
        <ul className="ml-6 list-disc space-y-2">
          <li>
            <InlineCode>📡 local (N)</InlineCode> — local mesh session and
            peer count
          </li>
          <li>
            <InlineCode>🟢 relay</InlineCode> — relay connected, at least one
            device paired on this machine
          </li>
          <li>
            <InlineCode>🟡 relay waiting for pairing</InlineCode> — relay
            connected, no device paired yet
          </li>
          <li>
            <InlineCode>📱 &lt;shortid&gt;</InlineCode> — a mobile device is
            actively connected right now
          </li>
        </ul>
        <p>
          The window title is two parts —{" "}
          <InlineCode>&lt;agent-name&gt; · On</InlineCode> when the relay is
          up or <InlineCode>&lt;agent-name&gt; · Off</InlineCode> otherwise —
          so you can tell your terminal tabs apart at a glance.
        </p>
      </DocsSection>

      <DocsSection id="config" title="Configuration files">
        <DocsTable
          headers={["Path", "Scope", "What's in it"]}
          rows={[
            [
              <InlineCode key="p">&lt;cwd&gt;/.pi/remote-pi/config.json</InlineCode>,
              "Per-directory",
              <>
                <InlineCode>agent_name</InlineCode>,{" "}
                <InlineCode>auto_start_relay</InlineCode>
              </>,
            ],
            [
              <InlineCode key="p">~/.pi/remote/config.json</InlineCode>,
              "Per-user",
              <><InlineCode>relay</InlineCode> URL</>,
            ],
            [
              <InlineCode key="p">~/.pi/remote/peers.json</InlineCode>,
              "Per-machine",
              "Paired mobile devices",
            ],
            [
              <InlineCode key="p">~/.pi/remote/daemons.json</InlineCode>,
              "Per-machine",
              <>Daemon registry (list of <InlineCode>{`{ cwd, name }`}</InlineCode> entries)</>,
            ],
            [
              <InlineCode key="p">~/.pi/remote/identity.json</InlineCode>,
              "Per-machine",
              <>
                Pi-secret fallback when the OS keyring is unavailable
                (headless Linux). Stored with{" "}
                <InlineCode>chmod 0600</InlineCode>. See{" "}
                <a
                  className="text-accent underline"
                  href={`${GITHUB_URL}/blob/main/PROTOCOL.md`}
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  PROTOCOL.md
                </a>{" "}
                for the keyring details.
              </>,
            ],
            [
              <InlineCode key="p">~/.pi/remote/sessions/local/</InlineCode>,
              "Per-machine",
              <>Broker socket + <InlineCode>audit.jsonl</InlineCode></>,
            ],
            [
              <InlineCode key="p">~/.pi/remote/skills/agent-network/SKILL.md</InlineCode>,
              "Per-user",
              "Agent skill the LLM reads",
            ],
          ]}
        />
        <p>Override the relay for a single run without persisting:</p>
        <CodeBlock
          code="REMOTE_PI_RELAY=https://staging.example.tld pi"
          label="Shell"
          language="bash"
        />
        <p className="text-sm">
          Only <InlineCode>http://</InlineCode> /{" "}
          <InlineCode>https://</InlineCode> are accepted —{" "}
          <InlineCode>wss://</InlineCode> / <InlineCode>ws://</InlineCode> are
          rejected at validation, the extension converts to the WebSocket
          form internally when it opens the connection.
        </p>
        <p className="text-sm">
          Daemons don&apos;t read the per-directory file at all — the supervisor
          injects their whole config inline via the{" "}
          <InlineCode>REMOTE_PI_DIRECT_CONFIG</InlineCode> environment variable
          at spawn (a fixed <InlineCode>assistent</InlineCode> workspace with
          the relay on), so a daemon folder needs no{" "}
          <InlineCode>.pi/remote-pi/</InlineCode> of its own. You can set the
          same variable yourself to override{" "}
          <InlineCode>&lt;cwd&gt;/.pi/remote-pi/config.json</InlineCode> for a
          single run — an escape hatch for CI, ops, and the Cockpit desktop
          client:
        </p>
        <CodeBlock
          code={`REMOTE_PI_DIRECT_CONFIG='{"agent_name":"ci","auto_start_relay":true}' pi`}
          label="Shell"
          language="bash"
        />
      </DocsSection>

      <DocsSection id="troubleshooting" title="Troubleshooting">
        <DocsSubsection id="footer-stuck" title="Footer says 🟡 relay waiting for pairing even though I paired a device">
          <p>
            The icon reflects whether <em>any</em> device has been paired on
            this machine, not whether one is connected right now. If you really
            have a paired device in <InlineCode>/remote-pi devices</InlineCode>,
            restart Pi — the cache may be stale (fixed in current release;
            report a bug if it recurs).
          </p>
        </DocsSubsection>
        <DocsSubsection id="timeout-mobile" title="Mobile app times out connecting">
          <p>
            Verify the same relay URL is configured on both sides. If you
            self-host behind a VPN, your phone must also be on the VPN
            (Tailscale on iOS/Android works fine).
          </p>
        </DocsSubsection>
        <DocsSubsection id="timeout-request" title="Reply never arrives">
          <p>
            <InlineCode>agent_send</InlineCode> returned{" "}
            <InlineCode>{`{ status: "received" }`}</InlineCode> but no reply
            ever lands in your inbox. Possible causes:
          </p>
          <ul className="ml-6 list-disc space-y-2">
            <li>
              <strong className="text-fg">Receiver crashed or never processed.</strong>{" "}
              Run <InlineCode>/remote-pi peers</InlineCode> to see whether the
              peer is still online.
            </li>
            <li>
              <strong className="text-fg">The receiver chose not to reply.</strong>{" "}
              <InlineCode>agent_send</InlineCode> is not RPC — there&apos;s no
              obligation to respond. If the conversation needs a reply, the
              prompt to the receiver must say so explicitly.
            </li>
            <li>
              <strong className="text-fg">Cross-PC: peer went offline.</strong>{" "}
              Look in your inbox for a <InlineCode>transport_error</InlineCode>{" "}
              envelope with <InlineCode>re=&lt;your-send-id&gt;</InlineCode>{" "}
              — the relay returns one when a forwarded message can&apos;t be
              delivered. A <InlineCode>Delivered</InlineCode> ACK only means the
              remote broker accepted the envelope, not that the peer is alive —
              validate by roundtrip.
            </li>
          </ul>
          <p className="text-sm">
            <strong className="text-fg">Note:</strong>{" "}
            <InlineCode>agent_request</InlineCode> is deprecated (still
            available as a wrapper for backward compat, emits a warning).
            New agents call <InlineCode>agent_send</InlineCode> and observe
            the inbox in a future turn.
          </p>
        </DocsSubsection>
        <DocsSubsection
          id="one-pi-per-cwd"
          title="Two Pi processes can't share a directory"
        >
          <p>
            A cwd lock allows{" "}
            <strong className="text-fg">one Pi process per directory</strong>.
            If you try to run <InlineCode>/remote-pi</InlineCode> in a second
            terminal that&apos;s already in the same folder, the second start
            is rejected (and the relay, separately, refuses a duplicate room
            with <InlineCode>RoomAlreadyOpenError</InlineCode>).
          </p>
          <p>
            <strong className="text-fg">To run two agents side by side:</strong>{" "}
            put them in two different directories — each gets its own workspace
            and both meet in the same <InlineCode>local</InlineCode> session.
            See the{" "}
            <Link href="/tutorials/mesh-local" className="text-accent underline">
              Local mesh tutorial
            </Link>
            .
          </p>
          <p>
            If you actually wanted a second terminal at the same workspace
            (e.g. just to read state), stop the running Pi first or open a
            shell that does <em>not</em> launch Pi.
          </p>
        </DocsSubsection>
      </DocsSection>

      <DocsSection id="links" title="Links">
        <ul className="ml-6 list-disc space-y-2">
          <li>
            Homepage:{" "}
            <Link href="/" className="text-accent underline">
              remote-pi.jacobmoura.work
            </Link>
          </li>
          <li>
            Tutorials:{" "}
            <Link href="/tutorials" className="text-accent underline">
              hands-on guides
            </Link>
          </li>
          <li>
            Cockpit reference:{" "}
            <Link href="/cockpit/docs" className="text-accent underline">
              CLI, layouts, tasks, themes
            </Link>
          </li>
          <li>
            Source:{" "}
            <a className="text-accent underline" href={GITHUB_URL} target="_blank" rel="noopener noreferrer">
              github.com/jacobaraujo7/remote_pi
            </a>
          </li>
          <li>
            Protocol spec:{" "}
            <a
              className="text-accent underline"
              href={`${GITHUB_URL}/blob/main/PROTOCOL.md`}
              target="_blank"
              rel="noopener noreferrer"
            >
              PROTOCOL.md
            </a>
          </li>
          <li>
            Pi coding agent:{" "}
            <a className="text-accent underline" href={PI_URL} target="_blank" rel="noopener noreferrer">
              github.com/earendil-works/pi
            </a>
          </li>
          <li>
            Relay (self-hosting guide):{" "}
            <a className="text-accent underline" href={RELAY_README_URL} target="_blank" rel="noopener noreferrer">
              relay/README.md
            </a>
          </li>
          <li>
            Issues / bugs:{" "}
            <a className="text-accent underline" href={ISSUES_URL} target="_blank" rel="noopener noreferrer">
              github.com/jacobaraujo7/remote_pi/issues
            </a>
          </li>
        </ul>
        <p className="text-sm">License: MIT.</p>
      </DocsSection>
            </article>
          </div>
        </div>
      </div>
      <RevealController />
    </div>
  );
}
