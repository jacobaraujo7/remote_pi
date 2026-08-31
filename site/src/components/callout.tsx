import type { ReactNode } from "react";
import { useTranslations } from "next-intl";

type CalloutVariant = "note" | "warning" | "tip";

type CalloutProps = {
  variant?: CalloutVariant;
  /** Tag shown in the callout header. Defaults to Note / Warning by variant. */
  title?: string;
  children: ReactNode;
};

/**
 * Heads-up card. Shared across the home, the docs, and the tutorials. The
 * `note` and `tip` variants share the accent style; `warning` is amber.
 * Presentational only — safe as a server component.
 */
export function Callout({ variant = "note", title, children }: CalloutProps) {
  const t = useTranslations("DocsShared");
  const cls = variant === "warning" ? "callout warning" : "callout";
  const tag = title ?? (variant === "warning" ? t("calloutWarning") : t("calloutNote"));
  return (
    <div className={cls}>
      <div className="ctag">{tag}</div>
      {children}
    </div>
  );
}
