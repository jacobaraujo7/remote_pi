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
    namespace: "CockpitTutorials.team",
  });
  return {
    title: t("meta.title"),
    description: t("meta.description"),
    alternates: pageAlternates(locale, "/tutorials/cockpit-team"),
  };
}

/* ---- example briefs (one per folder) ---- */
const ORCHESTRATOR_MD = `# Orchestrator

You coordinate two workers that run in other Cockpit tabs: \`Backend\` and
\`Frontend\`. You do not write app code yourself. You split the work, dispatch
it, and integrate the results.

## How you work
- Dispatch with the internal CLI, one instruction per worker:
  \`cockpit send --tab-id <tab> --enter "<instruction>"\`
- Read a worker back with \`cockpit read-tab <label> --lines 80\` instead of
  asking the human what it printed.
- A worker is busy while \`working\` is true in \`cockpit list-tabs --json\`.
  Wait for it to flip to false before reading the final answer.
- Reconcile mismatches (the API shape against what the UI needs) and report
  back to the human.

Keep each instruction small and explicit: say what you want and what "done"
looks like.`;

const BACKEND_MD = `# Backend

You own the server and API in this folder. You work only here.

## How you work
- The orchestrator types instructions straight into your terminal. Treat them
  as prompts from the human.
- Keep the API contract (routes, payloads) explicit, and print it when you are
  done, because the orchestrator reads your output to pass it on.
- If an instruction is ambiguous, say what is missing instead of guessing.`;

const FRONTEND_MD = `# Frontend

You own the UI in this folder. You work only here.

## How you work
- Build against the contract the backend printed. If you need a route or a
  field that does not exist, say so and stop: the orchestrator coordinates it.
- When you are done, print what changed, in one short list.`;

const TEAM_CKP = `panes:
  - name: Orchestrator
    cwd: orchestrator
    command: claude
  - name: Backend
    cwd: backend
    split: right
    command: claude
  - name: Frontend
    cwd: frontend
    split: down
    command: claude`;

/* Inline tags used by the messages: <code1>, <a2>... Handlers live here so
   each message just spreads TAGS. Contents of <code*> are never translated. */
const TAGS = {
  strong1: (c: ReactNode) => <strong className="text-fg">{c}</strong>,
  code1: (c: ReactNode) => <InlineCode>{c}</InlineCode>,
  link1: (c: ReactNode) => (
    <Link href="/docs#cli" className="text-accent underline">
      {c}
    </Link>
  ),
  link2: (c: ReactNode) => (
    <Link href="/tutorials/cockpit-layouts" className="text-accent underline">
      {c}
    </Link>
  ),
  link3: (c: ReactNode) => (
    <Link href="/download" className="text-accent underline">
      {c}
    </Link>
  ),
  em1: (c: ReactNode) => <em>{c}</em>,
  link4: (c: ReactNode) => (
    <Link href="/docs#remote" className="text-accent underline">
      {c}
    </Link>
  ),
};

export default async function CockpitTeamTutorial({ params }: Props) {
  const { locale } = await params;
  setRequestLocale(locale);
  const t = await getTranslations({
    locale,
    namespace: "CockpitTutorials.team",
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
                <p>{t.rich("what.p1", TAGS)}</p>
                <p>{t.rich("what.p2", TAGS)}</p>
                <Callout variant="note" title={t("what.callout1")}>
                  {t.rich("what.callout2", TAGS)}
                </Callout>
              </DocsSection>

              <DocsSection id="prereqs" title={t("prereqs.title")}>
                <ul className="ml-6 list-disc space-y-2">
                  <li>{t.rich("prereqs.li1", TAGS)}</li>
                  <li>{t.rich("prereqs.li2", TAGS)}</li>
                </ul>
              </DocsSection>

              <DocsSection id="folders" title={t("folders.title")}>
                <p>{t("folders.p1")}</p>
                <CodeBlock
                  code={`my-app/
├── orchestrator/
│   └── AGENTS.md
├── backend/
│   └── AGENTS.md
└── frontend/
    └── AGENTS.md`}
                  label={t("folders.label1")}
                  language="text"
                />
                <p>{t.rich("folders.p2", TAGS)}</p>
                <CodeBlock
                  code={ORCHESTRATOR_MD}
                  label="orchestrator/AGENTS.md"
                  language="markdown"
                />
                <CodeBlock
                  code={BACKEND_MD}
                  label="backend/AGENTS.md"
                  language="markdown"
                />
                <CodeBlock
                  code={FRONTEND_MD}
                  label="frontend/AGENTS.md"
                  language="markdown"
                />
                <Callout variant="note" title={t("folders.callout1")}>
                  {t("folders.callout2")}
                </Callout>
              </DocsSection>

              <DocsSection id="tabs" title={t("tabs.title")}>
                <p>{t.rich("tabs.p1", TAGS)}</p>
                <p>{t.rich("tabs.p2", TAGS)}</p>
                <p>{t.rich("tabs.p3", TAGS)}</p>
                <CodeBlock code={TEAM_CKP} label="team.ckp" language="yaml" />
                <CodeBlock
                  label={t("tabs.label1")}
                  prompt
                  code="cockpit orchestrate team.ckp"
                />
                <Callout variant="tip" title={t("tabs.callout1")}>
                  {t.rich("tabs.callout2", TAGS)}
                </Callout>
              </DocsSection>

              <DocsSection id="wiring" title={t("wiring.title")}>
                <p>{t.rich("wiring.p1", TAGS)}</p>
                <CodeBlock
                  code="Run `cockpit list-tabs --json` and tell me which tabs you can reach."
                  label={t("wiring.label1")}
                  language="text"
                />
                <CodeBlock
                  code={`$ cockpit list-tabs --json
[
  { "id": "t0", "label": "Orchestrator", "workspacePath": "/Users/me/my-app", "working": true  },
  { "id": "t1", "label": "Backend",      "workspacePath": "/Users/me/my-app", "working": false },
  { "id": "t2", "label": "Frontend",     "workspacePath": "/Users/me/my-app", "working": false }
]`}
                  label={t("wiring.label2")}
                  language="text"
                />
                <p>{t.rich("wiring.p2", TAGS)}</p>
                <CodeBlock
                  label={t("wiring.label3")}
                  prompt
                  code={`# dispatch an instruction and press Enter for it
cockpit send --tab-id Backend --enter "Expose GET /todos and POST /todos"

# see who is still thinking (working: true) and who is done
cockpit list-tabs --json

# read a worker's answer without touching its window
cockpit read-tab Backend --lines 80

# open a worker beside you, mid-flight, if the work needs one more pair of hands
cockpit new-tab --cwd ./docs --title Docs --split v`}
                />
                <Callout variant="warning" title={t("wiring.callout1")}>
                  {t.rich("wiring.callout2", TAGS)}
                </Callout>
              </DocsSection>

              <DocsSection id="run" title={t("run.title")}>
                <p>{t("run.p1")}</p>
                <CodeBlock
                  code={`Add a "todos" feature: an API to list and create todos, and a page
that shows them with a form to add one. Coordinate Backend and Frontend.`}
                  label={t("run.label1")}
                  language="text"
                />
                <p>{t("run.p2")}</p>
                <CodeBlock
                  code={`$ cockpit send --tab-id Backend --enter \\
    "Expose GET /todos and POST /todos (title:string). Print the JSON shape when done."
sent

$ cockpit send --tab-id Frontend --enter \\
    "Build a Todos page: list todos and a form to add one. Wait for the API shape first."
sent`}
                  label={t("run.label2")}
                  language="text"
                />
                <p>{t.rich("run.p3", TAGS)}</p>
                <CodeBlock
                  code={`$ cockpit list-tabs --json | grep -A1 Backend
  { "id": "t1", "label": "Backend", "working": false }

$ cockpit read-tab Backend --lines 40
  Added GET /todos and POST /todos.
  Todo: { id: string, title: string, done: bool }`}
                  label={t("run.label3")}
                  language="text"
                />
                <p>{t("run.p4")}</p>
                <Callout variant="note" title={t("run.callout1")}>
                  {t.rich("run.callout2", TAGS)}
                </Callout>
              </DocsSection>

              <DocsSection id="why" title={t("why.title")}>
                <p>{t("why.p1")}</p>
                <p>{t.rich("why.p2", TAGS)}</p>
              </DocsSection>
            </article>

            <Pager
              prev={{
                href: "/tutorials/cockpit-layouts",
                label: t("pager.prev"),
              }}
              next={{
                href: "/tutorials/cockpit-telemetry",
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
