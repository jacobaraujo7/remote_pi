import type { Metadata } from "next";
import Link from "next/link";
import { Callout } from "@/components/callout";
import { IconDownload, IconGithub } from "@/components/landing/icons";
import { RevealController } from "@/components/landing/reveal-controller";

export const metadata: Metadata = {
  title: "Why Pi",
  description:
    "Deciding how to run an always-on coding agent? remote-pi keeps Pi alive 24/7 and puts it in your pocket. Here's when that's the right shape — and when an all-in-one platform isn't.",
};

const GITHUB_URL = "https://github.com/jacobaraujo7/remote_pi";

const highlights = [
  {
    title: "Alive 24/7",
    description:
      "A per-machine supervisor (launchd on macOS, systemd on Linux) keeps every paired folder running as a background agent — survives logout, restarts on crash, answers at 3am.",
  },
  {
    title: "Lightweight",
    description:
      "Pi is a small coding agent, not a platform. It boots fast and runs only what you add to it — nothing you didn't ask for.",
  },
  {
    title: "You assemble it",
    description:
      "Extend Pi with the skills, plugins, and per-folder agents you actually need. The agent is yours to shape until it fits your work exactly.",
  },
  {
    title: "Driven from your phone",
    description:
      "Pair once with a QR. Send prompts, switch models, start a fresh session, or compact context from iOS or Android — wherever you are.",
  },
  {
    title: "A mesh when you need it",
    description:
      "Agents reach each other on one machine over a local socket, or across PCs through the relay. One Owner key, one mesh, no central server.",
  },
  {
    title: "Open source, self-hostable",
    description:
      "MIT licensed. Run the community relay or host your own; traffic is encrypted in transit, and self-hosting keeps it on infrastructure you control.",
  },
];

export default function WhyPage() {
  return (
    <div className="page">
      <div className="page-body">
        <div className="wrap">
          <header className="page-head reveal" style={{ maxWidth: 760 }}>
            <span className="eyebrow">Why Pi</span>
            <h1>An always-on agent you assemble yourself.</h1>
            <p className="lede">
              remote-pi turns Pi into a background agent that never logs off —
              and a phone in your pocket that drives it. This page is about that
              choice: keeping a coding agent alive 24/7, and whether building it
              up from something small is the shape you want.
            </p>
          </header>

          <div className="section-head reveal" style={{ marginTop: 64 }}>
            <span className="eyebrow">What you get</span>
            <h2>Pi, kept alive and put in your pocket.</h2>
          </div>
          <div
            className="reveal"
            style={{
              display: "grid",
              gridTemplateColumns: "repeat(auto-fit, minmax(248px, 1fr))",
              gap: 18,
              marginTop: 28,
            }}
          >
            {highlights.map((h) => (
              <div className="feat-card" key={h.title}>
                <h3>{h.title}</h3>
                <p>{h.description}</p>
              </div>
            ))}
          </div>

          <div className="section-head reveal" style={{ marginTop: 80 }}>
            <span className="eyebrow">The honest version</span>
            <h2>What about OpenClaw and Hermes Agent?</h2>
          </div>
          <div
            className="compare reveal"
            style={{ maxWidth: 760, marginTop: 28 }}
          >
            <p className="sub">
              They&apos;re excellent. <strong>OpenClaw</strong> and{" "}
              <strong>Hermes Agent</strong> are first-class always-on,
              open-source agents. If you want a batteries-included platform that
              ships ready to run, you should look hard at them — this page
              won&apos;t pretend otherwise.
            </p>
            <p>
              remote-pi makes a different bet. It starts from Pi — a lightweight
              coding agent — and adds just the always-on layer: a supervisor
              that keeps it running and a phone that drives it. Everything else,
              you assemble. The trade is real: less out of the box, more
              that&apos;s exactly yours.
            </p>
            <Callout title="The choice">
              Want a complete, all-in-one platform, ready out of the box?
              OpenClaw and Hermes Agent are great places to start. Want a
              lightweight coding agent you assemble, keep alive 24/7, and
              control from your phone? That&apos;s Pi with remote-pi.
            </Callout>
            <p style={{ fontSize: 14 }}>
              One note on scope: this comparison is about the{" "}
              <em>always-on layer</em> — remote-pi&apos;s daemon mode — not
              coding agents in general. It&apos;s the part where keeping an agent
              alive and reachable is the whole job, and where OpenClaw and Hermes
              Agent shine too.
            </p>
          </div>

          <div
            className="reveal"
            style={{
              textAlign: "center",
              maxWidth: 680,
              margin: "96px auto 0",
              paddingBottom: 24,
            }}
          >
            <span className="eyebrow">Get started</span>
            <h2
              style={{
                fontFamily: "var(--ff-display)",
                fontWeight: 600,
                color: "var(--ink)",
                fontSize: "clamp(28px, 4vw, 44px)",
                letterSpacing: "-0.02em",
                lineHeight: 1.05,
                margin: "14px 0 0",
              }}
            >
              Build yours and leave it running.
            </h2>
            <p
              style={{
                color: "var(--ink-soft)",
                fontSize: 17,
                margin: "16px auto 0",
                maxWidth: 520,
              }}
            >
              Add the plugin to Pi, pair your phone, and promote a folder to a
              24/7 daemon. The how-to walks every step.
            </p>
            <div
              style={{
                display: "flex",
                gap: 14,
                justifyContent: "center",
                flexWrap: "wrap",
                marginTop: 28,
              }}
            >
              <Link className="btn btn-primary" href="/remote-pi#install">
                <IconDownload /> Install
              </Link>
              <Link className="btn btn-ghost" href="/remote-pi/tutorials/daemon">
                Daemon how-to →
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
          </div>
        </div>
      </div>
      <RevealController />
    </div>
  );
}
