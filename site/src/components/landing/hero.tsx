"use client";

import { useEffect, useMemo, useState, Fragment } from "react";
import { useTranslations } from "next-intl";
import {
  IconDownload,
  IconGithub,
  IconChevronLeft,
  IconTerminal,
  IconPaperclip,
  IconStop,
} from "@/components/landing/icons";

const GITHUB_URL = "https://github.com/jacobaraujo7/remote_pi";

/* ---------- living mesh background ---------- */
function HeroMesh() {
  // node positions in a 1000x700 viewBox
  const nodes = [
    { x: 120, y: 110 },
    { x: 300, y: 70 },
    { x: 80, y: 320 },
    { x: 250, y: 430 },
    { x: 470, y: 250 },
    { x: 430, y: 540 },
    { x: 640, y: 130 },
    { x: 760, y: 360 },
    { x: 900, y: 200 },
    { x: 870, y: 500 },
    { x: 600, y: 420 },
  ];
  const links: [number, number][] = [
    [0, 1], [0, 2], [1, 4], [2, 3], [3, 5], [4, 6], [4, 10],
    [6, 8], [7, 8], [7, 9], [10, 7], [5, 10], [1, 6], [3, 4],
  ];
  return (
    <div className="hero-mesh" aria-hidden="true">
      <svg viewBox="0 0 1000 700" preserveAspectRatio="xMidYMid slice">
        <g stroke="rgba(79,195,247,0.16)" fill="none">
          {links.map(([a, b], i) => (
            <line
              key={i}
              x1={nodes[a].x}
              y1={nodes[a].y}
              x2={nodes[b].x}
              y2={nodes[b].y}
              strokeWidth="1.2"
              strokeDasharray="5 9"
              style={{ animation: `dash ${14 + (i % 6) * 3}s linear infinite`, opacity: 0.8 }}
            />
          ))}
        </g>
        {nodes.map((n, i) => (
          <g key={i}>
            <circle cx={n.x} cy={n.y} r="14" fill="rgba(79,195,247,0.05)" />
            <circle
              cx={n.x}
              cy={n.y}
              r="3.4"
              fill="#4fc3f7"
              style={{ animation: `pulseNode ${3 + (i % 5) * 0.6}s ease-in-out ${i * 0.4}s infinite` }}
            />
          </g>
        ))}
      </svg>
    </div>
  );
}

/* ---------- animated phone driving an agent ---------- */
type ChatItem =
  | { type: "user"; text: string }
  | { type: "tool"; kind: string; cmd: string }
  | { type: "md"; text: string };

function parseSegs(text: string) {
  return text
    .split(/(`[^`]+`)/g)
    .filter(Boolean)
    .map((p) =>
      p.startsWith("`") && p.endsWith("`")
        ? { code: true, str: p.slice(1, -1) }
        : { code: false, str: p },
    );
}

function TypedMd({ text }: { text: string }) {
  const segs = useMemo(() => parseSegs(text), [text]);
  const total = segs.reduce((a, s) => a + s.str.length, 0);
  const [n, setN] = useState(0);
  useEffect(() => {
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    let i = 0;
    const id = setInterval(
      () => {
        i = reduce ? total : i + 1;
        setN(i);
        if (i >= total) clearInterval(id);
      },
      reduce ? 0 : 24,
    );
    return () => clearInterval(id);
  }, [text, total]);

  let left = n;
  const out: React.ReactNode[] = [];
  segs.forEach((s, i) => {
    if (left <= 0) return;
    const take = Math.min(left, s.str.length);
    const piece = s.str.slice(0, take);
    left -= take;
    out.push(s.code ? <code key={i}>{piece}</code> : <Fragment key={i}>{piece}</Fragment>);
  });
  return (
    <div className="md-response">
      {out}
      <span className="caret" />
    </div>
  );
}

function ToolCard({ kind, cmd }: { kind: string; cmd: string }) {
  return (
    <div className="tool">
      <div className="tool-head">
        <span className="l">
          <span className="ticon">
            <IconTerminal />
          </span>
          {kind}
        </span>
        <span className="status">DONE</span>
      </div>
      <div className="tool-code">{cmd}</div>
      <div className="tool-done">✓ Done</div>
    </div>
  );
}

function PhoneHero() {
  const t = useTranslations("Hero");
  const chatItems: ChatItem[] = useMemo(
    () => [
      { type: "user", text: t("demoUserMessage") },
      { type: "tool", kind: "READ", cmd: "$ path=~/.pi/skills/agent-network/SKILL.md" },
      { type: "tool", kind: "BASH", cmd: '$ find ~/.pi -name "pair*" -o -name "join*" | head -20' },
      { type: "md", text: t("demoMdMessage") },
    ],
    [t],
  );

  const [step, setStep] = useState(1);
  useEffect(() => {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      const id = setTimeout(() => setStep(chatItems.length), 0);
      return () => clearTimeout(id);
    }
    let timer: ReturnType<typeof setTimeout>;
    let s = 1;
    const durFor = (idx: number) => {
      const it = chatItems[idx];
      if (!it) return 1400;
      if (it.type === "md") return it.text.length * 24 + 2600;
      if (it.type === "tool") return 1300;
      return 1100;
    };
    const advance = () => {
      timer = setTimeout(() => {
        if (s >= chatItems.length) {
          s = 1;
          setStep(1);
        } else {
          s += 1;
          setStep(s);
        }
        advance();
      }, durFor(s - 1));
    };
    advance();
    return () => clearTimeout(timer);
  }, [chatItems]);

  const shown = chatItems.slice(0, step);

  return (
    <div className="phone-stage">
      <div className="float-chip c1">
        <span className="led" /> {t("demoAgentsMesh")}
      </div>
      <div className="float-chip c3">
        <span className="led" /> {t("demoDaemon")}
      </div>

      <div className="phone">
        <div className="phone-screen">
          <div className="phone-statusbar">
            <span>9:21</span>
            <span className="dots">
              <i />
              <i />
              <i />
            </span>
          </div>

          <div className="app-bar">
            <span className="back">
              <IconChevronLeft />
            </span>
            <div className="ab-title">
              <div className="t">{t("demoChatTitle")}</div>
              <div className="sub">
                <span className="host">{t("demoChatHost")}</span>
                <span className="dot" />
                <span className="state">{t("demoChatState")}</span>
              </div>
            </div>
          </div>

          <div className="chat-body">
            {shown.map((m, i) => {
              if (m.type === "user") return <div key={i} className="bubble me">{m.text}</div>;
              if (m.type === "tool") return <ToolCard key={i} kind={m.kind} cmd={m.cmd} />;
              return <TypedMd key={"md" + step} text={m.text} />;
            })}
          </div>

          <div className="app-input">
            <span className="clip">
              <IconPaperclip />
            </span>
            <span className="field">{t("demoWaiting")}</span>
            <span className="stop">
              <IconStop />
            </span>
          </div>
        </div>
      </div>
    </div>
  );
}

export function Hero() {
  const t = useTranslations("Hero");
  return (
    <section className="hero">
      <HeroMesh />
      <div className="wrap">
        <div className="hero-grid">
          <div className="hero-copy">
            <span className="eyebrow">{t("eyebrow")}</span>
            <h1>
              {t("titleLine1")}
              <br />
              {t("titleLine2")} <span className="pocket">{t("titlePocket")}</span>
            </h1>
            <p className="hero-sub">{t("sub")}</p>
            <div className="hero-cta">
              <a className="btn btn-primary" href="#install">
                <IconDownload /> {t("install")}
              </a>
              <a
                className="btn btn-ghost"
                href={GITHUB_URL}
                target="_blank"
                rel="noopener noreferrer"
              >
                <IconGithub /> {t("github")}
              </a>
            </div>
            <div className="hero-meta">
              <span>{t("metaInstall")}</span>
              <span>{t("metaAccounts")}</span>
              <span>{t("metaLicense")}</span>
            </div>
          </div>
          <PhoneHero />
        </div>
      </div>
    </section>
  );
}
