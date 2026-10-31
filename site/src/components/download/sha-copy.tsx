"use client";

import { useState } from "react";
import { useTranslations } from "next-intl";
import { IconCopy, IconCheck } from "@/components/landing/icons";

/**
 * SHA-256 checksum with a copy button. The hash is shown truncated (the full
 * value is in the title attr and is what gets copied) so it never blows out
 * the card width. Mirrors the copy-button affordance used in CodeBlock.
 */
export function ShaCopy({ sha256 }: { sha256: string }) {
  const t = useTranslations("Common");
  const tw = useTranslations("DownloadWidgets.sha");
  const [copied, setCopied] = useState(false);

  const copy = () => {
    if (navigator.clipboard) navigator.clipboard.writeText(sha256);
    setCopied(true);
    setTimeout(() => setCopied(false), 1600);
  };

  const short =
    sha256.length > 22 ? `${sha256.slice(0, 10)}…${sha256.slice(-10)}` : sha256;

  return (
    <div className="dl-sha">
      <span className="dl-sha-key">SHA-256</span>
      <code className="dl-sha-val" title={sha256}>
        {short}
      </code>
      <button
        type="button"
        className={`copy-btn ${copied ? "copied" : ""}`}
        onClick={copy}
        aria-label={tw("copyAria")}
      >
        {copied ? <IconCheck /> : <IconCopy />} {copied ? t("copied") : t("copy")}
      </button>
    </div>
  );
}
