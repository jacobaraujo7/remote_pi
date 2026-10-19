import type { Metadata } from "next";
import type { ReactNode } from "react";
import { getTranslations, setRequestLocale } from "next-intl/server";
import { pageAlternates } from "@/i18n/alternates";
import { Link } from "@/i18n/navigation";
import { DocsSection, InlineCode } from "@/components/docs-shell";
import { CodeBlock } from "@/components/code-block";
import { Callout } from "@/components/callout";
import { Pager } from "@/components/pager";
import { RevealController } from "@/components/landing/reveal-controller";

type Props = { params: Promise<{ locale: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { locale } = await params;
  const t = await getTranslations({
    locale,
    namespace: "CockpitTutorials.layouts",
  });
  return {
    title: t("meta.title"),
    description: t("meta.description"),
    alternates: pageAlternates(locale, "/tutorials/cockpit-layouts"),
  };
}

const TREE = `my-app/
├── .cockpit/
│   └── tasks.json     # what runs
├── dev.ckp            # what opens
├── api/
│   └── package.json
└── web/
    └── package.json`;

const CKP_FIRST = `panes:
  - name: Agent
    cwd: .
    command: claude`;

const CKP_FULL = `# dev.ckp — one layout, committed with the project
autorun: worktree
panes:
  - name: Agent
    cwd: .
    command: claude
  - name: API
    cwd: api
    split: right
  - name: Web
    cwd: web
    split: down`;

const TASKS = `{
  // .cockpit/tasks.json — JSONC: comments and trailing commas are fine
  "tasks": [
    {
      "label": "api",
      "cwd": "api",
      "command": "npm",
      "args": ["run", "dev"],
      "kind": "watch",
      "interactiveKeys": [
        { "key": "q", "label": "Quit", "icon": "stop" }
      ]
    },
    {
      "label": "web",
      "cwd": "web",
      "command": "npm",
      "args": ["run", "dev"],
      "kind": "watch",
      "profiles": [
        { "name": "dev" },
        { "name": "staging", "env": { "API_URL": "https://staging.example.com" } }
      ]
    }
  ]
}`;

/* Inline tags used by the messages: <code1>, <a2>... Handlers live here so
   each message just spreads TAGS. Contents of <code*> are never translated. */
const TAGS = {
  code1: (c: ReactNode) => <InlineCode>{c}</InlineCode>,
  link1: (c: ReactNode) => (
    <Link href="/tutorials/cockpit-team" className="text-accent underline">
      {c}
    </Link>
  ),
  strong1: (c: ReactNode) => <strong className="text-fg">{c}</strong>,
  link2: (c: ReactNode) => (
    <Link href="/download" className="text-accent underline">
      {c}
    </Link>
  ),
  strong2: (c: ReactNode) => <strong>{c}</strong>,
  link3: (c: ReactNode) => (
    <Link href="/docs#cli" className="text-accent underline">
      {c}
    </Link>
  ),
  link4: (c: ReactNode) => (
    <Link href="/docs" className="text-accent underline">
      {c}
    </Link>
  ),
};

export default async function CockpitLayoutsTutorial({ params }: Props) {
  const { locale } = await params;
  setRequestLocale(locale);
  const t = await getTranslations({
    locale,
    namespace: "CockpitTutorials.layouts",
  });
  return (
    <div className="page">
      <div className="page-body">
        <div className="wrap">
          <div className="tut">
            <header className="page-head reveal" style={{ maxWidth: "none" }}>
              <div className="flex flex-wrap items-center gap-3">
                <span className="inline-flex items-center rounded-full border border-accent/40 bg-accent/15 px-3 py-1 text-xs font-semibold uppercase tracking-[0.15em] text-accent">
                  {t("intro.span1")}
                </span>
              </div>
              <span className="eyebrow" style={{ marginTop: 14 }}>
                {t("intro.span2")}
              </span>
              <h1>{t("intro.h11")}</h1>
              <p className="lede">{t.rich("intro.p1", TAGS)}</p>
            </header>

            <article className="prose">
              <DocsSection id="what" title={t("what.title")}>
                <p>{t("what.p1")}</p>
                <CodeBlock
                  code={TREE}
                  label={t("what.label1")}
                  language="text"
                />
                <p>{t.rich("what.p2", TAGS)}</p>
              </DocsSection>

              <DocsSection id="prereqs" title={t("prereqs.title")}>
                <ul className="ml-6 list-disc space-y-2">
                  <li>{t.rich("prereqs.li1", TAGS)}</li>
                  <li>{t.rich("prereqs.li2", TAGS)}</li>
                </ul>
              </DocsSection>

              <DocsSection id="first-layout" title={t("firstLayout.title")}>
                <p>{t.rich("firstLayout.p1", TAGS)}</p>
                <CodeBlock code={CKP_FIRST} label="dev.ckp" language="yaml" />
                <p>{t.rich("firstLayout.p2", TAGS)}</p>
                <Callout variant="tip" title={t("firstLayout.callout1")}>
                  <p>{t.rich("firstLayout.p3", TAGS)}</p>
                </Callout>
              </DocsSection>

              <DocsSection id="splits" title={t("splits.title")}>
                <p>{t.rich("splits.p1", TAGS)}</p>
                <CodeBlock code={CKP_FULL} label="dev.ckp" language="yaml" />
                <p>{t("splits.p2")}</p>
                <CodeBlock
                  code="cockpit orchestrate dev.ckp"
                  label={t("splits.label1")}
                  prompt
                />
                <Callout variant="note" title={t("splits.callout1")}>
                  <p>{t("splits.p3")}</p>
                </Callout>
              </DocsSection>

              <DocsSection id="tasks" title={t("tasks.title")}>
                <p>{t.rich("tasks.p1", TAGS)}</p>
                <CodeBlock
                  code={TASKS}
                  label=".cockpit/tasks.json"
                  language="jsonc"
                />
                <p>{t.rich("tasks.p2", TAGS)}</p>
                <p>{t.rich("tasks.p3", TAGS)}</p>
                <Callout variant="tip" title={t("tasks.callout1")}>
                  <p>{t.rich("tasks.p4", TAGS)}</p>
                </Callout>
              </DocsSection>

              <DocsSection id="agents" title={t("agents.title")}>
                <p>{t.rich("agents.p1", TAGS)}</p>
                <CodeBlock
                  label={t("agents.label1")}
                  prompt
                  code={`# what can I run here?
cockpit list-tasks

# tail the dev server's output
cockpit read-task json:api --lines 80

# open a worker tab beside me and drive it
id=$(cockpit new-tab --cwd web --title Web --split h)
cockpit send --tab-id "$id" --enter "npm run build"`}
                />
                <p>{t.rich("agents.p2", TAGS)}</p>
              </DocsSection>

              <DocsSection id="commit" title={t("commit.title")}>
                <p>{t.rich("commit.p1", TAGS)}</p>
                <p>{t.rich("commit.p2", TAGS)}</p>
              </DocsSection>
            </article>

            <Pager
              prev={{ href: "/", label: t("pager.prev") }}
              next={{
                href: "/tutorials/cockpit-team",
                label: t("pager.next"),
              }}
            />
          </div>
        </div>
      </div>
      <RevealController />
    </div>
  );
}
