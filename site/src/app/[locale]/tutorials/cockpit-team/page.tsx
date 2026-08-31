import type { Metadata } from "next";
import { getTranslations } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import { DocsSection, InlineCode } from "@/components/docs-shell";
import { CodeBlock } from "@/components/code-block";
import { Callout } from "@/components/callout";
import { Pager } from "@/components/pager";
import { RevealController } from "@/components/landing/reveal-controller";
import { localeAlternates } from "@/i18n/alternates";

/* ---- example AGENTS.md files (one per folder) — left in English, decision G ---- */
const ORCHESTRATOR_MD = `# Orchestrator

You coordinate two teammates over the Remote Pi mesh: \`backend\` and
\`frontend\`. You don't write app code yourself — you split the work,
delegate it, and integrate the results.

## How you work
- At the start of every turn, drain your inbox and read any replies.
- Break a request into one backend task and one frontend task.
- Delegate with agent_send to "backend" and "frontend".
- Collect their replies, reconcile mismatches (e.g. the API shape vs.
  what the UI needs), and report back to the user.

Keep each message small and explicit: say what you want and what
"done" looks like.`;

const BACKEND_MD = `# Backend

You own the server and API in this folder. On the Remote Pi mesh you are
the peer named \`backend\`.

## How you work
- Check your inbox each turn — the \`orchestrator\` sends you tasks.
- Do the work here, in this folder, then reply to the sender (use the
  message id as \`re\`).
- If a task is ambiguous, reply asking for the missing detail instead of
  guessing.
- Keep the API contract (routes, payloads) explicit so \`frontend\` can
  build against it.`;

const FRONTEND_MD = `# Frontend

You own the UI in this folder. On the Remote Pi mesh you are the peer
named \`frontend\`.

## How you work
- Check your inbox each turn — the \`orchestrator\` sends you tasks.
- Build against the contract \`backend\` exposes. If you need a route or
  field that doesn't exist yet, ask the orchestrator to coordinate it.
- When done, reply to the sender with what changed (use the message id
  as \`re\`).`;

export async function generateMetadata({
  params,
}: {
  params: Promise<{ locale: string }>;
}): Promise<Metadata> {
  const { locale } = await params;
  const t = await getTranslations({ locale, namespace: "TutorialCockpitTeam" });
  return {
    title: t("title"),
    description: t("metaDescription"),
    alternates: { languages: localeAlternates("/tutorials/cockpit-team") },
  };
}

export default async function CockpitTeamTutorial({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  const t = await getTranslations({ locale, namespace: "TutorialCockpitTeam" });
  const b = (chunks: React.ReactNode) => <strong className="text-fg">{chunks}</strong>;
  const em = (chunks: React.ReactNode) => <em>{chunks}</em>;
  const code = (chunks: React.ReactNode) => <InlineCode>{chunks}</InlineCode>;
  const gettingStartedLink = (chunks: React.ReactNode) => (
    <Link href="/tutorials/getting-started" className="text-accent underline">
      {chunks}
    </Link>
  );
  const meshLocalLink = (chunks: React.ReactNode) => (
    <Link href="/tutorials/mesh-local" className="text-accent underline">
      {chunks}
    </Link>
  );
  const cockpitLink = (chunks: React.ReactNode) => (
    <Link href="/cockpit" className="text-accent underline">
      {chunks}
    </Link>
  );
  const daemonLink = (chunks: React.ReactNode) => (
    <Link href="/tutorials/daemon" className="text-accent underline">
      {chunks}
    </Link>
  );
  const meshRemoteLink = (chunks: React.ReactNode) => (
    <Link href="/tutorials/mesh-remote" className="text-accent underline">
      {chunks}
    </Link>
  );

  return (
    <div className="page">
      <div className="page-body">
        <div className="wrap">
          <div className="tut">
            <header className="page-head reveal" style={{ maxWidth: "none" }}>
              <div className="flex flex-wrap items-center gap-3">
                <span className="inline-flex items-center rounded-full border border-accent/40 bg-accent/15 px-3 py-1 text-xs font-semibold uppercase tracking-[0.15em] text-accent">
                  {t("badge")}
                </span>
              </div>
              <span className="eyebrow" style={{ marginTop: 14 }}>
                {t("eyebrow")}
              </span>
              <h1>{t("h1")}</h1>
              <p className="lede">{t.rich("lede", { b, code })}</p>
            </header>

            <article className="prose">
              <DocsSection id="what" title={t("s1Title")}>
                <p>{t.rich("s1P1", { code })}</p>
                <p>{t("s1P2")}</p>
                <Callout variant="note" title={t("s1CalloutTitle")}>
                  {t.rich("s1CalloutBody", { code, link1: gettingStartedLink, link2: meshLocalLink })}
                </Callout>
              </DocsSection>

              <DocsSection id="prereqs" title={t("s2Title")}>
                <ul className="ml-6 list-disc space-y-2">
                  <li>{t.rich("s2Li1", { b, code, link: cockpitLink })}</li>
                  <li>{t.rich("s2Li2", { code })}</li>
                </ul>
              </DocsSection>

              <DocsSection id="folders" title={t("s3Title")}>
                <p>{t.rich("s3P1", { code })}</p>
                <CodeBlock
                  code={`my-app/
├── orchestrator/
│   └── AGENTS.md
├── backend/
│   └── AGENTS.md
└── frontend/
    └── AGENTS.md`}
                  label={t("s3CodeLabel1")}
                  language="text"
                />
                <p>{t.rich("s3P2", { code })}</p>
                <CodeBlock code={ORCHESTRATOR_MD} label="orchestrator/AGENTS.md" language="markdown" />
                <CodeBlock code={BACKEND_MD} label="backend/AGENTS.md" language="markdown" />
                <CodeBlock code={FRONTEND_MD} label="frontend/AGENTS.md" language="markdown" />
                <Callout variant="note" title={t("s3CalloutTitle")}>
                  {t("s3CalloutBody")}
                </Callout>
              </DocsSection>

              <DocsSection id="panes" title={t("s4Title")}>
                <p>{t.rich("s4P1", { code, b })}</p>
                <p>{t("s4P2")}</p>
                <Callout variant="tip" title={t("s4CalloutTitle")}>
                  {t.rich("s4CalloutBody", { code })}
                </Callout>
              </DocsSection>

              <DocsSection id="mesh" title={t("s5Title")}>
                <p>{t.rich("s5P1", { code })}</p>
                <CodeBlock code="/remote-pi" label={t("s5CodeLabel1")} language="text" />
                <p>{t.rich("s5P2", { code })}</p>
                <CodeBlock code="List the other agents on the mesh." label={t("s5CodeLabel2")} language="text" />
                <CodeBlock
                  code={`list_peers()
→ backend
  frontend`}
                  label={t("s5CodeLabel3")}
                  language="text"
                />
                <p>{t.rich("s5P3", { code })}</p>
              </DocsSection>

              <DocsSection id="run" title={t("s6Title")}>
                <p>{t("s6P1")}</p>
                <CodeBlock
                  code={`Add a "todos" feature: an API to list and create todos, and a page
that shows them with a form to add one. Coordinate backend and frontend.`}
                  label={t("s6CodeLabel1")}
                  language="text"
                />
                <p>{t("s6P2")}</p>
                <CodeBlock
                  code={`agent_send({
  to: "backend",
  body: { task: "Expose GET /todos and POST /todos (title:string). Return the JSON shape." }
})
→ Delivered to backend

agent_send({
  to: "frontend",
  body: { task: "Build a Todos page: list todos and a form to add one, against backend's API." }
})
→ Delivered to frontend`}
                  label={t("s6CodeLabel2")}
                  language="text"
                />
                <p>{t.rich("s6P3", { code, em })}</p>
                <CodeBlock
                  code={`get_messages()
→ [..] from=orchestrator id=7f3a91 { "task": "Expose GET /todos and POST /todos ..." }

# ...writes the routes here, in backend/ ...

agent_send({
  to: "orchestrator",
  body: { done: "Added GET/POST /todos", api: { todo: { id: "string", title: "string", done: "bool" } } },
  re: "7f3a91"
})
→ Delivered to orchestrator`}
                  label={t("s6CodeLabel3")}
                  language="text"
                />
                <p>{t.rich("s6P4", { code })}</p>
                <Callout variant="note" title={t("s6CalloutTitle")}>
                  {t.rich("s6CalloutBody", { code, link: meshLocalLink })}
                </Callout>
              </DocsSection>

              <DocsSection id="why" title={t("s7Title")}>
                <p>{t("s7P1")}</p>
                <p>{t.rich("s7P2", { link1: daemonLink, link2: meshRemoteLink })}</p>
              </DocsSection>
            </article>

            <Pager
              prev={{ href: "/tutorials/mesh-local", label: t("pagerPrevLabel") }}
              next={{ href: "/cockpit", label: t("pagerNextLabel") }}
            />
          </div>
        </div>
      </div>
      <RevealController />
    </div>
  );
}
