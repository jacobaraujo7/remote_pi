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
  return (
    <nav aria-label="Tutorial navigation" className="pager reveal">
      {prev ? (
        <Link className="pager-card" href={prev.href}>
          <span className="dir">← Previous</span>
          <span className="ttl">{prev.label}</span>
        </Link>
      ) : (
        <span className="pager-card empty" />
      )}
      {next ? (
        <Link className="pager-card next" href={next.href}>
          <span className="dir">Next →</span>
          <span className="ttl">{next.label}</span>
        </Link>
      ) : (
        <span className="pager-card empty" />
      )}
    </nav>
  );
}
