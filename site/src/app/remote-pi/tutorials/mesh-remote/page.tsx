import type { Metadata } from "next";
import Link from "next/link";
import { DocsSection, DocsSubsection, InlineCode } from "@/components/docs-shell";
import { CodeBlock } from "@/components/code-block";
import { Callout } from "@/components/callout";
import { Pager } from "@/components/pager";
import { RevealController } from "@/components/landing/reveal-controller";

const GITHUB_URL = "https://github.com/jacobaraujo7/remote_pi";

export const metadata: Metadata = {
  title: "Remote mesh",
  description:
    "Route messages between agents on different PCs through the relay, address peers as pc_label:peer, and understand what an ACK does and does not guarantee.",
};

export default function MeshRemoteTutorial() {
  return (
    <div className="page">
      <div className="page-body">
        <div className="wrap">
          <div className="tut">
            <header className="page-head reveal" style={{ maxWidth: "none" }}>
              <span className="eyebrow">Tutorial · 3 of 4</span>
              <h1>Remote mesh</h1>
              <p className="lede">
                The{" "}
                <Link href="/remote-pi/tutorials/mesh-local">local mesh</Link> stops at
                one machine. Turn on the relay and the same{" "}
                <InlineCode>agent_send</InlineCode> reaches agents on other PCs
                — your laptop talking to your desktop, a build box, a server.
                The tools are identical; only the addressing changes.
              </p>
            </header>

            <article className="prose">
              <DocsSection id="setup" title="1. Put both machines on one mesh">
          <p>
            Cross-PC routing rides the relay. Every machine paired under the
            same <strong className="text-fg">Owner key</strong> forms one
            logical mesh — there is no central server, just a relay forwarding
            between paired peers. To get there:
          </p>
          <ul className="ml-6 list-disc space-y-2">
            <li>
              On each machine, run <InlineCode>/remote-pi</InlineCode> and answer{" "}
              <strong className="text-fg">Yes</strong> to using the relay.
            </li>
            <li>
              Pair both machines to the{" "}
              <strong className="text-fg">same Owner</strong> so they share one
              mesh. The mesh-membership details — how the Owner key signs the
              device list — live in{" "}
              <a
                className="text-accent underline"
                href={`${GITHUB_URL}/blob/main/PROTOCOL.md`}
                target="_blank"
                rel="noopener noreferrer"
              >
                PROTOCOL.md
              </a>
              .
            </li>
          </ul>
          <p>
            Point both machines at the same relay. The default is the community
            relay; for your own, see{" "}
            <Link href="/remote-pi/docs#relay" className="text-accent underline">
              the relay reference
            </Link>
            .
          </p>
        </DocsSection>

        <DocsSection id="addressing" title="2. Address peers across PCs">
          <p>
            Once both machines are on the mesh,{" "}
            <InlineCode>list_peers()</InlineCode> shows local agents plus remote
            ones, each prefixed with the source machine&apos;s label:
          </p>
          <CodeBlock
            code={`list_peers()
→ frontend                 # local — same machine
  MacMini:backend          # remote — agent "backend" on PC "MacMini"
  build-box:tests          # remote — agent "tests" on PC "build-box"`}
            label="any agent · tool call"
            language="text"
          />
          <p>
            To message a remote peer, use its full{" "}
            <InlineCode>pc_label:peer</InlineCode> name verbatim — that&apos;s
            the only difference from a local send:
          </p>
          <CodeBlock
            code={`agent_send({
  to: "MacMini:backend",
  body: { task: "run the integration suite and report failures" }
})
→ Delivered to MacMini:backend`}
            label="frontend · tool call"
            language="text"
          />
          <p>
            The reply arrives the same way a local one does — in your inbox on a
            future turn, carrying <InlineCode>re=&lt;your-send-id&gt;</InlineCode>.
          </p>
        </DocsSection>

        <DocsSection id="delivered" title='3. "Delivered" is not "alive"'>
          <p>
            This is the one thing to internalize about remote sends. A{" "}
            <InlineCode>Delivered</InlineCode> ACK means{" "}
            <strong className="text-fg">the remote broker accepted the
            envelope</strong> — nothing more. It does{" "}
            <em className="text-fg">not</em> mean the peer is alive, processed
            the message, or will ever answer.
          </p>
          <Callout variant="warning" title="Validate by roundtrip">
            Don&apos;t treat <InlineCode>Delivered</InlineCode> as proof the
            other agent is working. <InlineCode>list_peers</InlineCode> can even
            list a peer that has gone stale. The only real confirmation is a{" "}
            <strong className="text-fg">reply you actually receive</strong>: ask
            the remote agent to respond, then wait for that envelope in your
            inbox. If it never comes, the peer may be offline regardless of what
            the ACK said.
          </Callout>
          <p>
            When a forwarded message genuinely can&apos;t be delivered, the
            relay returns a <InlineCode>transport_error</InlineCode> envelope
            with <InlineCode>re=&lt;your-send-id&gt;</InlineCode> — watch your
            inbox for that too.
          </p>
        </DocsSection>

        <DocsSection id="trust" title="What the relay sees">
          <p>
            The relay is the only network-touching piece, so it&apos;s worth
            being precise about what it protects and what it doesn&apos;t:
          </p>
          <Callout variant="warning" title="Encrypted in transit — payloads are not">
            Connections to the relay are{" "}
            <strong className="text-fg">encrypted in transit (TLS)</strong>, and
            devices authenticate each other with{" "}
            <strong className="text-fg">Ed25519 pairing</strong>. But message
            payloads are <strong className="text-fg">not</strong> encrypted at
            the application layer — the relay operator could in principle read
            plaintext in memory while forwarding. If you need confidentiality
            from the relay operator,{" "}
            <Link href="/remote-pi/docs#self-host" className="text-accent underline">
              self-host the relay
            </Link>{" "}
            behind a VPN.
          </Callout>
          <p className="text-sm">
            The community relay does not log, persist, or inspect payloads, but
            self-hosting is the way to get cryptographic-grade isolation. The
            full trust model is in{" "}
            <a
              className="text-accent underline"
              href={`${GITHUB_URL}/blob/main/PROTOCOL.md`}
              target="_blank"
              rel="noopener noreferrer"
            >
              PROTOCOL.md
            </a>
            .
          </p>
        </DocsSection>

        <DocsSection id="uses" title="What it's for">
          <p>
            Cross-PC messaging lets you split work across roles that live on
            different machines — a <InlineCode>frontend</InlineCode> on your
            laptop handing tasks to a <InlineCode>backend</InlineCode> on a
            beefier box, or a <InlineCode>tests</InlineCode> agent on a build
            server reporting back. Same tools, same envelope; the relay just
            carries it between machines.
          </p>
          <DocsSubsection title="Keep them reachable">
            <p>
              Cross-PC coordination is most useful when the remote agents are
              always up. That&apos;s the next guide:{" "}
              <Link href="/remote-pi/tutorials/daemon" className="text-accent underline">
                run them as 24/7 daemons
              </Link>
              .
            </p>
          </DocsSubsection>
        </DocsSection>

            </article>

            <Pager
              prev={{ href: "/remote-pi/tutorials/mesh-local", label: "Local mesh" }}
              next={{ href: "/remote-pi/tutorials/daemon", label: "Daemon mode" }}
            />
          </div>
        </div>
      </div>
      <RevealController />
    </div>
  );
}
