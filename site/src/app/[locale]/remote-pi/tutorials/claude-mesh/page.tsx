import type { Metadata } from "next";
import type { ReactNode } from "react";
import { getTranslations, setRequestLocale } from "next-intl/server";
import { pageAlternates } from "@/i18n/alternates";
import { Link } from "@/i18n/navigation";
import {
  DocsSection,
  DocsSubsection,
  InlineCode,
} from "@/components/docs-shell";
import { CodeBlock } from "@/components/code-block";
import { Callout } from "@/components/callout";
import { Pager } from "@/components/pager";
import { RevealController } from "@/components/landing/reveal-controller";

type Props = { params: Promise<{ locale: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { locale } = await params;
  const t = await getTranslations({
    locale,
    namespace: "RemoteTutorials.claudeMesh",
  });
  return {
    title: t("meta.title"),
    description: t("meta.description"),
    alternates: pageAlternates(locale, "/remote-pi/tutorials/claude-mesh"),
  };
}

/* Inline tags used by the messages: <code1>, <a2>... Handlers live here so
   each message just spreads TAGS. Contents of <code*> are never translated. */
const TAGS = {
  code1: (c: ReactNode) => <InlineCode>{c}</InlineCode>,
  strong1: (c: ReactNode) => <strong className="text-fg">{c}</strong>,
  a1: (c: ReactNode) => <a href="#no-app">{c}</a>,
  link1: (c: ReactNode) => (
    <Link href="/remote-pi/tutorials/daemon" className="text-accent underline">
      {c}
    </Link>
  ),
  a2: (c: ReactNode) => (
    <a href="#cwd-lock" className="text-accent underline">
      {c}
    </a>
  ),
  em1: (c: ReactNode) => <em className="text-fg">{c}</em>,
  link2: (c: ReactNode) => (
    <Link
      href="/remote-pi/tutorials/mesh-local"
      className="text-accent underline"
    >
      {c}
    </Link>
  ),
};

export default async function ClaudeMeshTutorial({ params }: Props) {
  const { locale } = await params;
  setRequestLocale(locale);
  const t = await getTranslations({
    locale,
    namespace: "RemoteTutorials.claudeMesh",
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
              <DocsSection id="prereqs" title={t("prereqs.title")}>
                <ul className="ml-6 list-disc space-y-2">
                  <li>{t.rich("prereqs.li1", TAGS)}</li>
                  <li>{t.rich("prereqs.li2", TAGS)}</li>
                  <li>{t.rich("prereqs.li3", TAGS)}</li>
                </ul>
              </DocsSection>

              <DocsSection id="run" title={t("run.title")}>
                <CodeBlock
                  code={`remote-pi claude            # uses the current folder
remote-pi claude ~/code/api  # or target a specific folder`}
                  label="Shell"
                  language="bash"
                />
                <p>{t("run.p1")}</p>
                <CodeBlock
                  code={`[remote-pi] No config found for /Users/you/code/api
Let's set up this agent.

Agent name [api]: reviewer`}
                  label={t("run.label1")}
                  language="text"
                />
                <p>{t.rich("run.p2", TAGS)}</p>
              </DocsSection>

              <DocsSection id="injected" title={t("injected.title")}>
                <p>{t.rich("injected.p1", TAGS)}</p>

                <DocsSubsection id="mcp" title={t("injected_mcp.title")}>
                  <p>{t.rich("injected_mcp.p1", TAGS)}</p>
                  <CodeBlock
                    code="claude mcp add remote-pi-mesh -s local -- node …/mesh_server.js --cwd <folder>"
                    label={t("injected_mcp.label1")}
                    language="bash"
                  />
                  <p>{t("injected_mcp.p2")}</p>
                  <ul className="ml-6 list-disc space-y-2">
                    <li>{t.rich("injected_mcp.li1", TAGS)}</li>
                    <li>{t.rich("injected_mcp.li2", TAGS)}</li>
                    <li>{t.rich("injected_mcp.li3", TAGS)}</li>
                  </ul>
                </DocsSubsection>

                <DocsSubsection id="skill" title={t("injected_skill.title")}>
                  <p>{t.rich("injected_skill.p1", TAGS)}</p>
                  <ul className="ml-6 list-disc space-y-2">
                    <li>{t.rich("injected_skill.li1", TAGS)}</li>
                    <li>{t.rich("injected_skill.li2", TAGS)}</li>
                    <li>{t.rich("injected_skill.li3", TAGS)}</li>
                    <li>{t.rich("injected_skill.li4", TAGS)}</li>
                  </ul>
                </DocsSubsection>

                <DocsSubsection
                  id="channels"
                  title={t("injected_channels.title")}
                >
                  <p>{t.rich("injected_channels.p1", TAGS)}</p>
                  <ul className="ml-6 list-disc space-y-2">
                    <li>{t.rich("injected_channels.li1", TAGS)}</li>
                    <li>{t.rich("injected_channels.li2", TAGS)}</li>
                  </ul>
                </DocsSubsection>
              </DocsSection>

              <DocsSection id="flags" title={t("flags.title")}>
                <p>{t("flags.p1")}</p>
                <CodeBlock
                  code="claude --dangerously-load-development-channels server:remote-pi-mesh --dangerously-skip-permissions"
                  label={t("flags.label1")}
                  language="bash"
                />
                <Callout variant="warning" title={t("flags.callout1")}>
                  {t.rich("flags.callout2", TAGS)}
                </Callout>
              </DocsSection>

              <DocsSection id="cwd-lock" title={t("cwdLock.title")}>
                <p>{t.rich("cwdLock.p1", TAGS)}</p>
              </DocsSection>

              <DocsSection id="no-app" title={t("noApp.title")}>
                <p>{t.rich("noApp.p1", TAGS)}</p>
                <p>{t.rich("noApp.p2", TAGS)}</p>
              </DocsSection>
            </article>

            <Pager
              prev={{
                href: "/remote-pi/tutorials/daemon",
                label: t("pager.prev"),
              }}
              next={{ href: "/remote-pi/tutorials", label: t("pager.next") }}
            />
          </div>
        </div>
      </div>
      <RevealController />
    </div>
  );
}
