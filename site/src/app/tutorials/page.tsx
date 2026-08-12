import type { Metadata } from "next";
import Link from "next/link";
import { IconArrow, IconStar } from "@/components/landing/icons";
import { RevealController } from "@/components/landing/reveal-controller";

export const metadata: Metadata = {
  title: "Tutorials",
  description:
    "Hands-on guides for Remote Pi: get started with the app, run a local mesh, route across PCs, and keep an agent alive 24/7.",
};

type Step = {
  n?: string;
  star?: boolean;
  tag: string;
  title: string;
  href: string;
  desc: string;
};

const STEPS: Step[] = [
  {
    n: "1",
    tag: "01 / 04",
    title: "Getting started",
    href: "/tutorials/getting-started",
    desc: "Install Remote Pi, pair your phone, and drive your first agent from the app.",
  },
  {
    n: "2",
    tag: "02 / 04",
    title: "Local mesh",
    href: "/tutorials/mesh-local",
    desc: "Let two agents on the same machine discover each other and trade messages.",
  },
  {
    n: "3",
    tag: "03 / 04",
    title: "Remote mesh",
    href: "/tutorials/mesh-remote",
    desc: "Route messages between agents on different PCs through the relay.",
  },
  {
    n: "4",
    tag: "04 / 04",
    title: "Daemon mode",
    href: "/tutorials/daemon",
    desc: "Keep an agent alive 24/7 with the supervisor, then manage the fleet.",
  },
];

const EXTRAS: Step[] = [
  {
    star: true,
    tag: "extra",
    title: "Layouts and tasks in Cockpit",
    href: "/tutorials/cockpit-layouts",
    desc: "Commit a .ckp layout that opens your terminals and a tasks.json that runs your dev servers — with profiles and reload on save.",
  },
  {
    star: true,
    tag: "extra",
    title: "An agent team in Cockpit",
    href: "/tutorials/cockpit-team",
    desc: "Run an orchestrator, backend, and frontend as three panes in Cockpit — each its own folder and AGENTS.md, talking over the remote-pi mesh.",
  },
  {
    star: true,
    tag: "extra",
    title: "Claude in the mesh",
    href: "/tutorials/claude-mesh",
    desc: "Put Claude Code on the agent mesh next to Pi — advanced, terminal-only (not in the app yet).",
  },
];

function StepCard({ s }: { s: Step }) {
  return (
    <Link className="step-card reveal" href={s.href}>
      <div className="sc-top">
        <span className="sc-num">{s.star ? <IconStar /> : s.n}</span>
        <span className="sc-tag">{s.tag}</span>
      </div>
      <h3>{s.title}</h3>
      <p>{s.desc}</p>
      <span className="sc-link">
        Open tutorial <IconArrow />
      </span>
    </Link>
  );
}

export default function TutorialsIndexPage() {
  return (
    <div className="page">
      <div className="page-body">
        <div className="wrap">
          <header className="page-head reveal">
            <span className="eyebrow">Tutorials</span>
            <h1>Learn Remote Pi by doing.</h1>
            <p className="lede">
              Four hands-on guides, in order. Start with the app, then add
              agents, cross-PC routing, and a 24/7 supervisor as you need them.
              For the <em>why</em> behind it,{" "}
              <Link href="/why">read Why Pi</Link>; for exact flags and config,
              the <Link href="/docs">reference docs</Link>.
            </p>
          </header>

          <div className="card-list">
            {STEPS.map((s) => (
              <StepCard key={s.href} s={s} />
            ))}
          </div>

          <div className="group-label reveal">Extras</div>
          <div className="card-list">
            {EXTRAS.map((s) => (
              <StepCard key={s.href} s={s} />
            ))}
          </div>
        </div>
      </div>
      <RevealController />
    </div>
  );
}
