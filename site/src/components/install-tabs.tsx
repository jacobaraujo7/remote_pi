"use client";

import { useState } from "react";
import { useTranslations } from "next-intl";
import { CodeBlock } from "./code-block";

const CURL = "curl -fsSL https://remote-pi.jacobmoura.work/install.sh | bash";
const HAVE_PI = `pi install npm:remote-pi
/remote-pi
/remote-pi pair`;

type Tab = {
  tab: string;
  label: string;
  code: string;
  note: string;
  prompt: boolean;
  disabled?: boolean;
};

type InstallTabsProps = {
  /**
   * Controls the "No Pi yet" curl tab. Defaults to `true` now that the
   * installer ships and the site serves install.sh at the canonical domain.
   * Pass `false` to disable it with a "Coming soon" hint.
   */
  curlReady?: boolean;
};

/**
 * Two-tab install block for the Getting started tutorial, styled to match the
 * home install terminal. "No Pi yet" runs the curl installer; "Already have
 * Pi" adds the plugin to an existing Pi.
 */
export function InstallTabs({ curlReady = true }: InstallTabsProps) {
  const t = useTranslations("InstallTabs");
  const tabs: Record<string, Tab> = {
    fresh: {
      tab: t("tabFresh"),
      label: t("labelFresh"),
      code: CURL,
      prompt: true,
      disabled: !curlReady,
      note: t("noteFresh"),
    },
    hasPi: {
      tab: t("tabHasPi"),
      label: t("labelHasPi"),
      code: HAVE_PI,
      prompt: false,
      note: t("noteHasPi"),
    },
  };
  const keys = Object.keys(tabs);
  const [active, setActive] = useState(
    keys.find((k) => !tabs[k].disabled) ?? keys[0],
  );
  const d = tabs[active];

  return (
    <div className="install-card" style={{ marginTop: 22 }}>
      <div className="tabs" role="tablist" aria-label={t("aria")}>
        {keys.map((k) => (
          <button
            key={k}
            type="button"
            role="tab"
            aria-selected={k === active}
            aria-disabled={tabs[k].disabled || undefined}
            disabled={tabs[k].disabled}
            className={`tab ${k === active ? "active" : ""}`}
            onClick={() => !tabs[k].disabled && setActive(k)}
          >
            {tabs[k].tab}
            {tabs[k].disabled ? t("soon") : ""}
          </button>
        ))}
      </div>
      <CodeBlock label={d.label} code={d.code} prompt={d.prompt} />
      <p className="term-note" style={{ padding: "2px 4px 4px", margin: 0 }}>
        {d.note}
      </p>
    </div>
  );
}
