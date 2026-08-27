import type { Metadata } from "next";
import { getTranslations } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import { DocsSection, InlineCode } from "@/components/docs-shell";
import { CodeBlock } from "@/components/code-block";
import { Callout } from "@/components/callout";
import { Pager } from "@/components/pager";
import { RevealController } from "@/components/landing/reveal-controller";
import { localeAlternates } from "@/i18n/alternates";

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

export async function generateMetadata({
  params,
}: {
  params: Promise<{ locale: string }>;
}): Promise<Metadata> {
  const { locale } = await params;
  const t = await getTranslations({ locale, namespace: "TutorialCockpitLayouts" });
  return {
    title: t("title"),
    description: t("metaDescription"),
    alternates: { languages: localeAlternates("/tutorials/cockpit-layouts") },
  };
}

export default async function CockpitLayoutsTutorial({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  const t = await getTranslations({ locale, namespace: "TutorialCockpitLayouts" });
  const idx = await getTranslations({ locale, namespace: "TutorialsIndex" });
  const b = (chunks: React.ReactNode) => <strong>{chunks}</strong>;
  const code = (chunks: React.ReactNode) => <InlineCode>{chunks}</InlineCode>;
  const cockpitTeamLink = (chunks: React.ReactNode) => (
    <Link href="/tutorials/cockpit-team" className="text-accent underline">
      {chunks}
    </Link>
  );
  const downloadLink = (chunks: React.ReactNode) => (
    <Link href="/download" className="text-accent underline">
      {chunks}
    </Link>
  );
  const cockpitRefLink = (chunks: React.ReactNode) => (
    <Link href="/cockpit/docs#cli" className="text-accent underline">
      {chunks}
    </Link>
  );
  const cockpitDocsLink = (chunks: React.ReactNode) => (
    <Link href="/cockpit/docs" className="text-accent underline">
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
              <p className="lede">{t.rich("lede", { code })}</p>
            </header>

            <article className="prose">
              <DocsSection id="what" title={t("s1Title")}>
                <p>{t("s1P1")}</p>
                <CodeBlock code={TREE} label={t("s1CodeLabel")} language="text" />
                <p>{t.rich("s1P2", { link: cockpitTeamLink })}</p>
              </DocsSection>

              <DocsSection id="prereqs" title={t("s2Title")}>
                <ul className="ml-6 list-disc space-y-2">
                  <li>{t.rich("s2Li1", { b, link: downloadLink })}</li>
                  <li>{t.rich("s2Li2", { code })}</li>
                </ul>
              </DocsSection>

              <DocsSection id="first-layout" title={t("s3Title")}>
                <p>{t.rich("s3P1", { code })}</p>
                <CodeBlock code={CKP_FIRST} label="dev.ckp" language="yaml" />
                <p>{t.rich("s3P2", { b, code })}</p>
                <Callout variant="tip" title={t("s3CalloutTitle")}>
                  <p>{t.rich("s3CalloutBody", { b, code })}</p>
                </Callout>
              </DocsSection>

              <DocsSection id="splits" title={t("s4Title")}>
                <p>{t.rich("s4P1", { code })}</p>
                <CodeBlock code={CKP_FULL} label="dev.ckp" language="yaml" />
                <p>{t("s4P2")}</p>
                <CodeBlock code="cockpit orchestrate dev.ckp" label={t("s4CodeLabel")} prompt />
                <Callout variant="note" title="autorun: worktree">
                  <p>{t("s4CalloutBody")}</p>
                </Callout>
              </DocsSection>

              <DocsSection id="tasks" title={t("s5Title")}>
                <p>{t.rich("s5P1", { code })}</p>
                <CodeBlock code={TASKS} label=".cockpit/tasks.json" language="jsonc" />
                <p>{t.rich("s5P2", { code })}</p>
                <p>{t.rich("s5P3", { code })}</p>
                <Callout variant="tip" title={t("s5CalloutTitle")}>
                  <p>{t.rich("s5CalloutBody", { code })}</p>
                </Callout>
              </DocsSection>

              <DocsSection id="agents" title={t("s6Title")}>
                <p>{t.rich("s6P1", { code })}</p>
                <CodeBlock
                  label={t("s6CodeLabel")}
                  prompt
                  code={`# what can I run here?
cockpit list-tasks

# tail the dev server's output
cockpit read-task json:api --lines 80

# open a worker tab beside me and drive it
id=$(cockpit new-tab --cwd web --title Web --split h)
cockpit send --tab-id "$id" --enter "npm run build"`}
                />
                <p>{t.rich("s6P2", { code, link: cockpitRefLink })}</p>
              </DocsSection>

              <DocsSection id="commit" title={t("s7Title")}>
                <p>{t.rich("s7P1", { code })}</p>
                <p>{t.rich("s7P2", { link1: cockpitTeamLink, link2: cockpitDocsLink })}</p>
              </DocsSection>
            </article>

            <Pager
              prev={{ href: "/cockpit", label: t("pagerPrevLabel") }}
              next={{ href: "/tutorials/cockpit-team", label: idx("cockpitTeamTitle") }}
            />
          </div>
        </div>
      </div>
      <RevealController />
    </div>
  );
}
