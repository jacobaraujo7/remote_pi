import type { Metadata } from "next";
import Link from "next/link";
import { DocsSection, InlineCode } from "@/components/docs-shell";
import { CodeBlock } from "@/components/code-block";
import { Callout } from "@/components/callout";
import { Pager } from "@/components/pager";
import { RevealController } from "@/components/landing/reveal-controller";

export const metadata: Metadata = {
  title: "Local mesh",
  description:
    "Run two Pi agents on the same machine and have them discover each other and exchange messages over the local broker with list_peers, agent_send, and get_messages.",
};

export default function MeshLocalTutorial() {
  return (
    <div className="page">
      <div className="page-body">
        <div className="wrap">
          <div className="tut">
            <header className="page-head reveal" style={{ maxWidth: "none" }}>
              <span className="eyebrow">Tutorial · 2 of 4</span>
              <h1>Local mesh</h1>
              <p className="lede">
                Two agents running side by side on one machine can see each
                other and trade messages — no network involved. Here
                you&apos;ll start a second agent, have the first one find it,
                and watch a message go from one to the other and back.
              </p>
            </header>

            <article className="prose">
              <DocsSection id="how" title="How local discovery works">
          <p>
            Every agent that runs <InlineCode>/remote-pi</InlineCode> on a
            machine joins the same local session, named{" "}
            <InlineCode>local</InlineCode>. They meet through a Unix domain
            socket — a local broker at{" "}
            <InlineCode>~/.pi/remote/sessions/local/broker.sock</InlineCode> —
            so messages never leave the box. The first agent to start hosts the
            broker; the rest connect to it. If the host exits, another agent
            takes over automatically.
          </p>
          <Callout variant="note" title="One agent per folder">
            A lock allows exactly one Pi agent per directory. To run two agents
            at once, put them in <strong className="text-fg">two different
            folders</strong> — each gets its own workspace, both meet in the{" "}
            <InlineCode>local</InlineCode> session.
          </Callout>
        </DocsSection>

        <DocsSection id="start" title="1. Start a second agent">
          <p>
            You already have one agent from the{" "}
            <Link href="/remote-pi/tutorials/getting-started" className="text-accent underline">
              getting started
            </Link>{" "}
            guide. Open a second terminal in a{" "}
            <strong className="text-fg">different</strong> folder and start
            Remote Pi there too:
          </p>
          <CodeBlock
            code={`cd ~/code/service-b
pi            # then run /remote-pi and answer the wizard`}
            label="Second terminal"
            language="bash"
          />
          <p>
            Say the first agent is named <InlineCode>agent-a</InlineCode> and
            the second <InlineCode>agent-b</InlineCode> (the wizard defaults to
            the folder name). Both are now in the <InlineCode>local</InlineCode>{" "}
            session.
          </p>
        </DocsSection>

        <DocsSection id="tools" title="2. The three mesh tools">
          <p>
            The agent-network skill gives the LLM three tools. You don&apos;t
            call them by hand — you ask the agent in plain language and it calls
            them for you.
          </p>
          <ul className="ml-6 list-disc space-y-2">
            <li>
              <InlineCode>list_peers()</InlineCode> — who is online right now.
              Returns the peer names, one per line.
            </li>
            <li>
              <InlineCode>agent_send({`{ to, body, re? }`})</InlineCode> — send a
              message and wait for an ACK. Set <InlineCode>re</InlineCode> when
              you&apos;re replying to an earlier message.
            </li>
            <li>
              <InlineCode>get_messages()</InlineCode> — drain this agent&apos;s
              inbox. The agent checks it at the start of each turn, so incoming
              messages surface on its next reply.
            </li>
          </ul>
        </DocsSection>

        <DocsSection id="exchange" title="3. Send a message across">
          <p>
            In <InlineCode>agent-a</InlineCode>&apos;s terminal, ask it to find
            its peers:
          </p>
          <CodeBlock
            code="List the other agents available."
            label="agent-a · prompt"
            language="text"
          />
          <p>The LLM calls the tool and gets back the roster:</p>
          <CodeBlock
            code={`list_peers()
→ agent-b`}
            label="agent-a · tool call"
            language="text"
          />
          <p>Now have it send something:</p>
          <CodeBlock
            code="Send agent-b a ping with the current time."
            label="agent-a · prompt"
            language="text"
          />
          <CodeBlock
            code={`agent_send({
  to: "agent-b",
  body: { type: "ping", at: "2026-05-31T14:02:00Z" }
})
→ Delivered to agent-b`}
            label="agent-a · tool call"
            language="text"
          />
          <p>
            <InlineCode>Delivered</InlineCode> means{" "}
            <InlineCode>agent-b</InlineCode>&apos;s inbox accepted the envelope.
            On its next turn, <InlineCode>agent-b</InlineCode> sees it. Ask it:
          </p>
          <CodeBlock
            code="Any new messages? If so, reply to the sender."
            label="agent-b · prompt"
            language="text"
          />
          <CodeBlock
            code={`get_messages()
→ [2026-05-31T14:02:00Z] from=agent-a
  id=ab12cd34
  { "type": "ping", "at": "2026-05-31T14:02:00Z" }

agent_send({
  to: "agent-a",
  body: { type: "pong" },
  re: "ab12cd34"        // reply to the ping's id
})
→ Delivered to agent-a`}
            label="agent-b · tool calls"
            language="text"
          />
          <p>
            Back in <InlineCode>agent-a</InlineCode>, the{" "}
            <InlineCode>pong</InlineCode> shows up on its next turn, carrying{" "}
            <InlineCode>re=ab12cd34</InlineCode> so the agent knows which message
            it answers. The whole exchange is event-driven — nothing blocks
            waiting for a reply.
          </p>
        </DocsSection>

        <DocsSection id="acks" title="Reading the ACK">
          <p>
            <InlineCode>agent_send</InlineCode> tells you what happened to the
            envelope:
          </p>
          <ul className="ml-6 list-disc space-y-2">
            <li>
              <InlineCode>Delivered</InlineCode> — the peer&apos;s inbox accepted
              it.
            </li>
            <li>
              <InlineCode>busy</InlineCode> — the peer is mid-turn; the message
              was dropped. Retry shortly.
            </li>
            <li>
              <InlineCode>denied</InlineCode> — the peer refused it. Don&apos;t
              retry.
            </li>
            <li>
              <strong className="text-fg">No ACK (timeout)</strong> — the peer
              may be offline.
            </li>
          </ul>
          <Callout variant="note" title="A send is not a request">
            <InlineCode>agent_send</InlineCode> is fire-and-ACK, not RPC. There
            is no obligation for the other agent to reply. If you need an
            answer, the prompt to the receiver has to ask for one — like{" "}
            <InlineCode>reply to the sender</InlineCode> above.
          </Callout>
        </DocsSection>

            </article>

            <Pager
              prev={{ href: "/remote-pi/tutorials/getting-started", label: "Getting started" }}
              next={{ href: "/remote-pi/tutorials/mesh-remote", label: "Remote mesh" }}
            />
          </div>
        </div>
      </div>
      <RevealController />
    </div>
  );
}
