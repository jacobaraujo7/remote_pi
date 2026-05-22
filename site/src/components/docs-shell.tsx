import type { ReactNode } from "react";

type DocsShellProps = {
  title: string;
  lastUpdated: string;
  intro?: ReactNode;
  sidebar?: ReactNode;
  children: ReactNode;
};

export function DocsShell({
  title,
  lastUpdated,
  intro,
  sidebar,
  children,
}: DocsShellProps) {
  const article = (
    <article className="docs-prose flex flex-col gap-12">
      <header className="flex flex-col gap-3 border-b border-border-soft pb-8">
        <p className="text-xs font-semibold uppercase tracking-[0.2em] text-accent">
          Documentation
        </p>
        <h1 className="text-balance text-4xl font-semibold tracking-tight text-fg sm:text-5xl">
          {title}
        </h1>
        <p className="text-sm text-muted">Last updated: {lastUpdated}</p>
        {intro ? (
          <div className="text-base leading-relaxed text-muted">{intro}</div>
        ) : null}
      </header>
      {children}
    </article>
  );

  if (!sidebar) {
    return (
      <div className="mx-auto w-full max-w-3xl px-6 py-16 sm:py-20">
        {article}
      </div>
    );
  }

  return (
    <div className="mx-auto w-full max-w-[1120px] px-6 py-16 sm:py-20">
      <div className="lg:grid lg:grid-cols-[220px_minmax(0,1fr)] lg:gap-14">
        <aside className="mb-10 lg:mb-0">
          <details className="group rounded-2xl border border-border-soft bg-surface lg:hidden">
            <summary className="flex cursor-pointer list-none items-center justify-between px-5 py-4 text-sm font-semibold text-fg">
              <span>Table of contents</span>
              <svg
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth={2}
                strokeLinecap="round"
                strokeLinejoin="round"
                className="h-4 w-4 text-muted transition-transform group-open:rotate-180"
                aria-hidden="true"
              >
                <path d="m6 9 6 6 6-6" />
              </svg>
            </summary>
            <div className="border-t border-border-soft px-5 py-4">
              {sidebar}
            </div>
          </details>
          <div className="hidden lg:block lg:sticky lg:top-24 lg:max-h-[calc(100vh-7rem)] lg:overflow-y-auto lg:pr-2">
            {sidebar}
          </div>
        </aside>
        <div className="min-w-0">{article}</div>
      </div>
    </div>
  );
}

type DocsSectionProps = {
  id: string;
  title: string;
  children: ReactNode;
};

export function DocsSection({ id, title, children }: DocsSectionProps) {
  return (
    <section id={id} className="flex flex-col gap-4 scroll-mt-24">
      <h2 className="text-2xl font-semibold tracking-tight text-fg sm:text-3xl">
        {title}
      </h2>
      <div className="flex flex-col gap-4 text-[15px] leading-[1.75] text-muted">
        {children}
      </div>
    </section>
  );
}

export function DocsSubsection({
  id,
  title,
  children,
}: {
  id?: string;
  title: string;
  children: ReactNode;
}) {
  return (
    <div id={id} className="flex flex-col gap-3 scroll-mt-24">
      <h3 className="text-lg font-semibold text-fg sm:text-xl">{title}</h3>
      <div className="flex flex-col gap-3">{children}</div>
    </div>
  );
}

export function InlineCode({ children }: { children: ReactNode }) {
  return (
    <code className="rounded bg-surface px-1.5 py-0.5 font-mono text-[0.85em] text-fg">
      {children}
    </code>
  );
}

export function DocsTable({
  headers,
  rows,
}: {
  headers: string[];
  rows: ReactNode[][];
}) {
  return (
    <div className="overflow-x-auto rounded-2xl border border-border-soft">
      <table className="w-full border-collapse text-left text-sm">
        <thead className="bg-surface">
          <tr>
            {headers.map((h) => (
              <th
                key={h}
                className="border-b border-border-soft px-4 py-3 font-semibold text-fg"
              >
                {h}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((cells, i) => (
            <tr
              key={i}
              className="border-t border-border-soft/60 align-top text-muted"
            >
              {cells.map((cell, j) => (
                <td key={j} className="px-4 py-3">
                  {cell}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
