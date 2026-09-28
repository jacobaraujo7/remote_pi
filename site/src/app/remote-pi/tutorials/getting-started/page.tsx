import type { Metadata } from "next";
import Link from "next/link";
import { DocsSection, DocsSubsection, InlineCode } from "@/components/docs-shell";
import { CodeBlock } from "@/components/code-block";
import { InstallTabs } from "@/components/install-tabs";
import { Callout } from "@/components/callout";
import { Pager } from "@/components/pager";
import { RevealController } from "@/components/landing/reveal-controller";

export const metadata: Metadata = {
  title: "Getting started",
  description:
    "Install Remote Pi on Pi, pair your phone, and send your first command to an agent from the app — from install to first prompt.",
};

export default function GettingStartedTutorial() {
  return (
    <div className="page">
      <div className="page-body">
        <div className="wrap">
          <div className="tut">
            <header className="page-head reveal" style={{ maxWidth: "none" }}>
              <span className="eyebrow">Tutorial · 1 of 4</span>
              <h1>Getting started</h1>
              <p className="lede">
                By the end of this guide you&apos;ll have Remote Pi running on
                one machine, your phone paired to it, and your first command
                sent from the app — the agent runs it and the result streams
                back to your pocket. Plan on about five minutes.
              </p>
            </header>

            <article className="prose">
              <DocsSection id="prereqs" title="Before you start">
          <p>You need two things:</p>
          <ul className="ml-6 list-disc space-y-2">
            <li>
              A machine with <strong className="text-fg">Pi</strong> (the coding
              agent) and <strong className="text-fg">Node 20+</strong> installed.
            </li>
            <li>
              The <strong className="text-fg">Remote Pi</strong> app on your
              phone — from the{" "}
              <a
                className="text-accent underline"
                href="https://apps.apple.com/app/remote-pi-coding-agent/id6773499691"
                target="_blank"
                rel="noopener noreferrer"
              >
                App Store
              </a>
              ,{" "}
              <a
                className="text-accent underline"
                href="https://play.google.com/store/apps/details?id=work.jacobmoura.remotepi"
                target="_blank"
                rel="noopener noreferrer"
              >
                Google Play
              </a>
              , or the{" "}
              <Link className="text-accent underline" href="/remote-pi/download">
                Android APK
              </Link>{" "}
              direct download.
            </li>
          </ul>
          <p className="text-sm">
            No Pi yet? The <strong className="text-fg">No Pi yet</strong> tab
            below runs a one-command <InlineCode>curl</InlineCode> installer that
            sets up Pi, the plugin, and the supervisor for you. Already have Pi?
            Use the <strong className="text-fg">Already have Pi</strong> path.
          </p>
        </DocsSection>

        <DocsSection id="install" title="1. Install the plugin">
          <p>
            Remote Pi is a Pi plugin. Add it, run the setup wizard, then show a
            pairing QR:
          </p>
          <InstallTabs />
          <p>Walking through the three commands:</p>
          <DocsSubsection title="pi install npm:remote-pi">
            <p>
              Installs the plugin into Pi. This registers the{" "}
              <InlineCode>/remote-pi</InlineCode> slash command and deploys the
              agent-network skill that teaches the LLM the mesh tools.
            </p>
          </DocsSubsection>
          <DocsSubsection title="/remote-pi">
            <p>
              The first run opens a short wizard that{" "}
              <strong className="text-fg">creates the config for this folder</strong>.
              It asks two questions:
            </p>
            <ol className="ml-6 list-decimal space-y-2">
              <li>
                <strong className="text-fg">Agent name</strong> — how other
                peers address this agent. Defaults to the folder name.
              </li>
              <li>
                <strong className="text-fg">Use the relay?</strong> — answer{" "}
                <InlineCode>Yes</InlineCode> so your phone (and, later, other
                PCs) can reach this agent.
              </li>
            </ol>
            <p>
              When it finishes, the agent has joined the local mesh and the
              relay is connected.
            </p>
          </DocsSubsection>
          <DocsSubsection title="/remote-pi pair">
            <p>
              Prints a QR code (and a copy-paste pairing URI). Leave it on
              screen for the next step. Pairing is{" "}
              <strong className="text-fg">per machine</strong>: once a phone is
              paired, every Pi agent on this machine accepts it.
            </p>
          </DocsSubsection>
          <Callout variant="note" title="Order matters">
            Run <InlineCode>/remote-pi</InlineCode> before{" "}
            <InlineCode>/remote-pi pair</InlineCode>. On a brand-new folder with
            no config, <InlineCode>pair</InlineCode> will tell you to run the
            wizard first — that&apos;s the config step doing its job.
          </Callout>
        </DocsSection>

        <DocsSection id="pair" title="2. Pair your phone">
          <p>With the QR on screen:</p>
          <ol className="ml-6 list-decimal space-y-2">
            <li>Open the Remote Pi app on your phone.</li>
            <li>
              Tap <strong className="text-fg">Pair a device</strong> (or the
              scan button) and point the camera at the QR.
            </li>
            <li>
              The app confirms the pairing and the agent shows up in your
              device list. The Pi terminal footer flips to{" "}
              <InlineCode>🟢 relay</InlineCode> and shows{" "}
              <InlineCode>📱 &lt;shortid&gt;</InlineCode> while the phone is
              connected.
            </li>
          </ol>
          <p className="text-sm">
            Pairing authenticates the two sides to each other with Ed25519, and
            all relay traffic is encrypted in transit (TLS).
          </p>
        </DocsSection>

        <DocsSection id="first-command" title="3. Send your first command">
          <p>
            You&apos;re now driving the agent from your phone. In the app&apos;s
            chat for this agent, type a prompt and send it:
          </p>
          <CodeBlock
            code="List the files in this folder and tell me what this project is."
            label="From the app"
            language="text"
          />
          <p>
            The prompt lands in the Pi session on your machine exactly as if you
            had typed it there. The agent runs, and its response streams back to
            your phone live. That round trip — phone to agent and back — is the
            whole point of Remote Pi.
          </p>
          <p>
            Beyond chatting, the app can drive the session with a few typed
            actions: <strong className="text-fg">compact context</strong>,{" "}
            <strong className="text-fg">new session</strong>,{" "}
            <strong className="text-fg">set model</strong>, and{" "}
            <strong className="text-fg">set thinking</strong> level. The model
            picker reads live from the host, so it always reflects what that
            machine can actually run.
          </p>
        </DocsSection>

        <DocsSection id="next" title="Where to go next">
          <p>
            That&apos;s one agent, one phone. From here you can let multiple
            agents talk to each other, reach across machines, or keep an agent
            running when you walk away:
          </p>
          <ul className="ml-6 list-disc space-y-2">
            <li>
              <Link href="/remote-pi/tutorials/mesh-local" className="text-accent underline">
                Local mesh
              </Link>{" "}
              — two agents on the same machine discovering and messaging each
              other.
            </li>
            <li>
              <Link href="/remote-pi/tutorials/daemon" className="text-accent underline">
                Daemon mode
              </Link>{" "}
              — promote a folder to a 24/7 background agent.
            </li>
          </ul>
        </DocsSection>

            </article>

            <Pager
              next={{ href: "/remote-pi/tutorials/mesh-local", label: "Local mesh" }}
            />
          </div>
        </div>
      </div>
      <RevealController />
    </div>
  );
}
