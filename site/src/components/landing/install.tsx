"use client";

import { useState, type ReactNode } from "react";
import { useTranslations } from "next-intl";
import { IconCopy, IconCheck } from "@/components/landing/icons";

type TermLine = { p: string; c: string };
type InstallTab = {
  key: "fresh" | "hasPi";
  label: string;
  tabLabel: string;
  lines: TermLine[];
  copy: string;
  note: ReactNode;
};

const CURL = "curl -fsSL https://remote-pi.jacobmoura.work/install.sh | bash";

export function Install() {
  const t = useTranslations("Install");
  const tabs: InstallTab[] = [
    {
      key: "fresh",
      tabLabel: t("tabFresh"),
      label: t("labelFresh"),
      lines: [{ p: "$", c: CURL }],
      copy: CURL,
      note: t.rich("noteFresh", {
        b: (chunks) => <b>{chunks}</b>,
      }),
    },
    {
      key: "hasPi",
      tabLabel: t("tabHasPi"),
      label: t("labelHasPi"),
      lines: [
        { p: "$", c: "pi install npm:remote-pi" },
        { p: "›", c: "/remote-pi" },
        { p: "›", c: "/remote-pi pair" },
      ],
      copy: "pi install npm:remote-pi",
      note: t.rich("noteHasPi", {
        b: (chunks) => <b>{chunks}</b>,
        code: (chunks) => <code>{chunks}</code>,
      }),
    },
  ];
  const [active, setActive] = useState(tabs[0].key);
  const [copied, setCopied] = useState(false);
  const data = tabs.find((tab) => tab.key === active) ?? tabs[0];

  const copy = () => {
    if (navigator.clipboard) navigator.clipboard.writeText(data.copy);
    setCopied(true);
    setTimeout(() => setCopied(false), 1600);
  };

  return (
    <section className="section" id="install">
      <div className="wrap">
        <div className="section-head reveal">
          <span className="eyebrow">{t("eyebrow")}</span>
          <h2>{t("title")}</h2>
          <p>{t("sub")}</p>
        </div>

        <div className="install-card reveal">
          <div className="tabs" role="tablist" aria-label="Install Remote Pi">
            {tabs.map((tab) => (
              <button
                key={tab.key}
                type="button"
                role="tab"
                aria-selected={tab.key === active}
                className={`tab ${tab.key === active ? "active" : ""}`}
                onClick={() => {
                  setActive(tab.key);
                  setCopied(false);
                }}
              >
                {tab.tabLabel}
              </button>
            ))}
          </div>

          <div className="terminal">
            <div className="term-bar">
              <span className="lights">
                <i />
                <i />
                <i />
              </span>
              <span className="tlabel">{data.label}</span>
              <button
                type="button"
                className={`copy-btn ${copied ? "copied" : ""}`}
                onClick={copy}
              >
                {copied ? <IconCheck /> : <IconCopy />} {copied ? t("copied") : t("copy")}
              </button>
            </div>
            <div className="term-body">
              {data.lines.map((line, i) => (
                <div className="term-line" key={i}>
                  <span className="pr">{line.p}</span>
                  <span className="cmd">{line.c}</span>
                </div>
              ))}
            </div>
            <p className="term-note">{data.note}</p>
          </div>
        </div>
      </div>
    </section>
  );
}
