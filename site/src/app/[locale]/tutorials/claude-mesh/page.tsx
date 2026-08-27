import type { Metadata } from "next";
import { getTranslations } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import { DocsSection, DocsSubsection, InlineCode } from "@/components/docs-shell";
import { CodeBlock } from "@/components/code-block";
import { Callout } from "@/components/callout";
import { Pager } from "@/components/pager";
import { RevealController } from "@/components/landing/reveal-controller";
import { localeAlternates } from "@/i18n/alternates";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ locale: string }>;
}): Promise<Metadata> {
  const { locale } = await params;
  const t = await getTranslations({ locale, namespace: "TutorialClaudeMesh" });
  return {
    title: t("title"),
    description: t("metaDescription"),
    alternates: { languages: localeAlternates("/tutorials/claude-mesh") },
  };
}

export default async function ClaudeMeshTutorial({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  const t = await getTranslations({ locale, namespace: "TutorialClaudeMesh" });
  const idx = await getTranslations({ locale, namespace: "TutorialsIndex" });
  const b = (chunks: React.ReactNode) => <strong className="text-fg">{chunks}</strong>;
  const em = (chunks: React.ReactNode) => <em className="text-fg">{chunks}</em>;
  const code = (chunks: React.ReactNode) => <InlineCode>{chunks}</InlineCode>;
  const noAppAnchor = (chunks: React.ReactNode) => <a href="#no-app">{chunks}</a>;
  const cwdLockAnchor = (chunks: React.ReactNode) => (
    <a href="#cwd-lock" className="text-accent underline">
      {chunks}
    </a>
  );
  const daemonLink = (chunks: React.ReactNode) => (
    <Link href="/tutorials/daemon" className="text-accent underline">
      {chunks}
    </Link>
  );
  const meshLocalLink = (chunks: React.ReactNode) => (
    <Link href="/tutorials/mesh-local" className="text-accent underline">
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
              <p className="lede">{t.rich("lede", { code, b, why: noAppAnchor })}</p>
            </header>

            <article className="prose">
              <DocsSection id="prereqs" title={t("s1Title")}>
                <ul className="ml-6 list-disc space-y-2">
                  <li>{t.rich("s1Li1", { code, link: daemonLink })}</li>
                  <li>{t.rich("s1Li2", { b, code })}</li>
                  <li>{t.rich("s1Li3", { b, link: cwdLockAnchor })}</li>
                </ul>
              </DocsSection>

              <DocsSection id="run" title={t("s2Title")}>
                <CodeBlock
                  code={`remote-pi claude            # uses the current folder
remote-pi claude ~/code/api  # or target a specific folder`}
                  label={t("s2CodeLabel1")}
                  language="bash"
                />
                <p>{t("s2P1")}</p>
                <CodeBlock
                  code={`[remote-pi] No config found for /Users/you/code/api
Let's set up this agent.

Agent name [api]: reviewer`}
                  label={t("s2CodeLabel2")}
                  language="text"
                />
                <p>{t.rich("s2P2", { code })}</p>
              </DocsSection>

              <DocsSection id="injected" title={t("s3Title")}>
                <p>{t.rich("s3P1", { code })}</p>

                <DocsSubsection id="mcp" title={t("s3Sub1Title")}>
                  <p>{t.rich("s3Sub1P1", { code, b })}</p>
                  <CodeBlock
                    code="claude mcp add remote-pi-mesh -s local -- node …/mesh_server.js --cwd <folder>"
                    label={t("s3Sub1CodeLabel")}
                    language="bash"
                  />
                  <p>{t("s3Sub1P2")}</p>
                  <ul className="ml-6 list-disc space-y-2">
                    <li>{t.rich("s3Sub1Li1", { code })}</li>
                    <li>{t.rich("s3Sub1Li2", { code, b })}</li>
                    <li>{t.rich("s3Sub1Li3", { code })}</li>
                  </ul>
                </DocsSubsection>

                <DocsSubsection id="skill" title={t("s3Sub2Title")}>
                  <p>{t.rich("s3Sub2P1", { code, em })}</p>
                  <ul className="ml-6 list-disc space-y-2">
                    <li>{t.rich("s3Sub2Li1", { code })}</li>
                    <li>{t.rich("s3Sub2Li2", { code })}</li>
                    <li>{t.rich("s3Sub2Li3", { code })}</li>
                    <li>{t.rich("s3Sub2Li4", { code })}</li>
                  </ul>
                </DocsSubsection>

                <DocsSubsection id="channels" title={t("s3Sub3Title")}>
                  <p>{t.rich("s3Sub3P1", { code })}</p>
                  <ul className="ml-6 list-disc space-y-2">
                    <li>{t.rich("s3Sub3Li1", { b, code })}</li>
                    <li>{t.rich("s3Sub3Li2", { b, code })}</li>
                  </ul>
                </DocsSubsection>
              </DocsSection>

              <DocsSection id="flags" title={t("s4Title")}>
                <p>{t("s4P1")}</p>
                <CodeBlock
                  code="claude --dangerously-load-development-channels server:remote-pi-mesh --dangerously-skip-permissions"
                  label={t("s4CodeLabel")}
                  language="bash"
                />
                <Callout variant="warning" title={t("s4CalloutTitle")}>
                  {t.rich("s4CalloutBody", { code, b, link: daemonLink })}
                </Callout>
              </DocsSection>

              <DocsSection id="cwd-lock" title={t("s5Title")}>
                <p>{t.rich("s5P1", { code, b, em })}</p>
              </DocsSection>

              <DocsSection id="no-app" title={t("s6Title")}>
                <p>{t.rich("s6P1", { b, code })}</p>
                <p>{t.rich("s6P2", { link: meshLocalLink })}</p>
              </DocsSection>
            </article>

            <Pager
              prev={{ href: "/tutorials/daemon", label: idx("daemonTitle") }}
              next={{ href: "/tutorials", label: t("allTutorials") }}
            />
          </div>
        </div>
      </div>
      <RevealController />
    </div>
  );
}
