import { useTranslations } from "next-intl";
import { Link } from "@/i18n/navigation";

type PagerLink = {
  href: string;
  label: string;
};

type PagerProps = {
  prev?: PagerLink;
  next?: PagerLink;
};

/**
 * Previous / next navigation for the tutorials section, styled as two cards to
 * match the home. Either side is optional; a missing side stays as an invisible
 * placeholder so the present one keeps its column.
 */
export function Pager({ prev, next }: PagerProps) {
  const t = useTranslations("DocsShared");
  return (
    <nav aria-label={t("pagerAriaLabel")} className="pager reveal">
      {prev ? (
        <Link className="pager-card" href={prev.href}>
          <span className="dir">← {t("pagerPrev")}</span>
          <span className="ttl">{prev.label}</span>
        </Link>
      ) : (
        <span className="pager-card empty" />
      )}
      {next ? (
        <Link className="pager-card next" href={next.href}>
          <span className="dir">{t("pagerNext")} →</span>
          <span className="ttl">{next.label}</span>
        </Link>
      ) : (
        <span className="pager-card empty" />
      )}
    </nav>
  );
}
