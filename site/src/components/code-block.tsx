"use client";

import { useState } from "react";
import { useTranslations } from "next-intl";
import { IconCopy, IconCheck } from "@/components/landing/icons";

type CodeBlockProps = {
  code: string;
  label?: string;
  /** Kept for call-site compatibility; shown next to the label when present. */
  language?: string;
  /** Show a leading `$` prompt. Defaults to false (most snippets aren't shell). */
  prompt?: boolean;
};

/**
 * Terminal-style code block: macOS lights, a label, a copy button, and a
 * monospace body. Shared across docs and tutorials; matches the home install
 * terminal so the whole site reads as one product.
 */
export function CodeBlock({ code, label, language, prompt = false }: CodeBlockProps) {
  const t = useTranslations("Common");
  const [copied, setCopied] = useState(false);
  const tlabel = [label, language].filter(Boolean).join(" — ");

  const copy = () => {
    if (navigator.clipboard) navigator.clipboard.writeText(code);
    setCopied(true);
    setTimeout(() => setCopied(false), 1600);
  };

  return (
    <div className="terminal">
      <div className="term-bar">
        <span className="lights">
          <i />
          <i />
          <i />
        </span>
        <span className="tlabel">{tlabel}</span>
        <button
          type="button"
          className={`copy-btn ${copied ? "copied" : ""}`}
          onClick={copy}
        >
          {copied ? <IconCheck /> : <IconCopy />} {copied ? t("copied") : t("copy")}
        </button>
      </div>
      <div className="term-body">
        <div className="term-line">
          {prompt ? <span className="pr">$</span> : null}
          <pre className="cmd">{code}</pre>
        </div>
      </div>
    </div>
  );
}
