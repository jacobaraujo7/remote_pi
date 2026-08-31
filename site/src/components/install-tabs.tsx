"use client";

import { useState } from "react";
import { useTranslations } from "next-intl";
import { CodeBlock } from "./code-block";

const CURL = "curl -fsSL https://remote-pi.jacobmoura.work/install.sh | bash";
const HAVE_PI = `pi install npm:remote-pi
/remote-pi
/remote-pi pair`;

type Tab = {
  key: "fresh" | "hasPi";
  tabLabel: string;
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
  const t = useTranslations("DocsShared");
  const tabs: Tab[] = [
    {
      key: "fresh",
      tabLabel: t("installTabsFreshTab"),
      label: t("installTabsFreshLabel"),
      code: CURL,
      prompt: true,
      disabled: !curlReady,
      note: t("installTabsFreshNote"),
    },
    {
      key: "hasPi",
      tabLabel: t("installTabsHasPiTab"),
      label: t("installTabsHasPiLabel"),
      code: HAVE_PI,
      prompt: false,
      note: t("installTabsHasPiNote"),
    },
  ];
  const [active, setActive] = useState(
    tabs.find((tab) => !tab.disabled)?.key ?? tabs[0].key,
  );
  const d = tabs.find((tab) => tab.key === active) ?? tabs[0];

  return (
    <div className="install-card" style={{ marginTop: 22 }}>
      <div className="tabs" role="tablist" aria-label={t("installTabsAriaLabel")}>
        {tabs.map((tab) => (
          <button
            key={tab.key}
            type="button"
            role="tab"
            aria-selected={tab.key === active}
            aria-disabled={tab.disabled || undefined}
            disabled={tab.disabled}
            className={`tab ${tab.key === active ? "active" : ""}`}
            onClick={() => !tab.disabled && setActive(tab.key)}
          >
            {tab.tabLabel}
            {tab.disabled ? ` · ${t("installTabsSoon")}` : ""}
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
