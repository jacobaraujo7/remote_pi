"use client";

import { useEffect, useState, type ReactNode } from "react";
import { useTranslations } from "next-intl";

export type TocItem = {
  id: string;
  label: ReactNode;
  sub?: { id: string; label: ReactNode }[];
};

/**
 * Sticky table of contents for the docs page, with scrollspy. Measures each
 * heading document-relative (getBoundingClientRect + scrollY) so the active
 * entry is correct even though sections carry a transform during reveal.
 */
export function DocsToc({ items }: { items: TocItem[] }) {
  const t = useTranslations("DocsShared");
  const ids = items.flatMap((item) => [item.id, ...(item.sub?.map((s) => s.id) ?? [])]);
  const [active, setActive] = useState(ids[0]);

  useEffect(() => {
    const headings = ids
      .map((id) => document.getElementById(id))
      .filter((el): el is HTMLElement => el !== null);
    const onScroll = () => {
      const y = window.scrollY + 120;
      let current = headings.length ? headings[0].id : ids[0];
      for (const h of headings) {
        const top = h.getBoundingClientRect().top + window.scrollY;
        if (top <= y) current = h.id;
      }
      setActive(current);
    };
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ids.join(",")]);

  const link = (id: string, label: ReactNode, sub: boolean) => (
    <li key={id} className={sub ? "sub" : ""}>
      <a href={`#${id}`} className={active === id ? "active" : ""}>
        {label}
      </a>
    </li>
  );

  return (
    <aside className="toc">
      <div className="toc-label">{t("tocOnThisPage")}</div>
      <ul className="toc-list">
        {items.map((item) => [
          link(item.id, item.label, false),
          ...(item.sub ? item.sub.map((s) => link(s.id, s.label, true)) : []),
        ])}
      </ul>
    </aside>
  );
}
