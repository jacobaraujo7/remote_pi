import type { Metadata } from "next";
import Link from "next/link";
import { IconArrow, IconStar } from "@/components/landing/icons";
import { RevealController } from "@/components/landing/reveal-controller";

export const metadata: Metadata = {
  title: "Tutorials",
  description:
    "Hands-on guides for Cockpit: commit the layout and tasks your project opens with, and run a team of agents in one window.",
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
    tag: "01 / 03",
    title: "Layouts and tasks",
    href: "/tutorials/cockpit-layouts",
    desc: "Commit a .ckp layout that opens your terminals and a tasks.json that runs your dev servers, with profiles and reload on save.",
  },
  {
    n: "2",
    tag: "02 / 03",
    title: "An agent team",
    href: "/tutorials/cockpit-team",
    desc: "Run an orchestrator, a backend and a frontend as three agent tabs, each in its own folder, coordinated with the internal cockpit CLI.",
  },
  {
    n: "3",
    tag: "03 / 03",
    title: "Telemetry for agents",
    href: "/tutorials/cockpit-telemetry",
    desc: "A per-workspace error store agents query instead of reading terminals: grouped cases, triage, one CLI.",
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
            <h1>Learn Cockpit by doing.</h1>
            <p className="lede">
              Two hands-on guides that take the app past a plain terminal. For
              every command, file format and flag, the{" "}
              <Link href="/docs">reference</Link> has the whole picture. Looking
              for the Remote Pi guides (pairing, mesh, daemons)? They live at{" "}
              <Link href="/remote-pi/tutorials">/remote-pi/tutorials</Link>.
            </p>
          </header>

          <div className="card-list">
            {STEPS.map((s) => (
              <StepCard key={s.href} s={s} />
            ))}
          </div>
        </div>
      </div>
      <RevealController />
    </div>
  );
}
