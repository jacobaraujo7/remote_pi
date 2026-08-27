import type { Metadata } from "next";
import { getTranslations } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import { DocsSection, DocsSubsection, InlineCode } from "@/components/docs-shell";
import { CodeBlock } from "@/components/code-block";
import { InstallTabs } from "@/components/install-tabs";
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
  const t = await getTranslations({ locale, namespace: "TutorialGettingStarted" });
  return {
    title: t("title"),
    description: t("metaDescription"),
    alternates: { languages: localeAlternates("/tutorials/getting-started") },
  };
}

export default async function GettingStartedTutorial({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  const t = await getTranslations({ locale, namespace: "TutorialGettingStarted" });
  const shared = await getTranslations({ locale, namespace: "DocsShared" });
  const idx = await getTranslations({ locale, namespace: "TutorialsIndex" });
  const b = (chunks: React.ReactNode) => <strong className="text-fg">{chunks}</strong>;
  const code = (chunks: React.ReactNode) => <InlineCode>{chunks}</InlineCode>;
  const appStore = (chunks: React.ReactNode) => (
    <a
      className="text-accent underline"
      href="https://apps.apple.com/app/remote-pi-coding-agent/id6773499691"
      target="_blank"
      rel="noopener noreferrer"
    >
      {chunks}
    </a>
  );
  const googlePlay = (chunks: React.ReactNode) => (
    <a
      className="text-accent underline"
      href="https://play.google.com/store/apps/details?id=work.jacobmoura.remotepi"
      target="_blank"
      rel="noopener noreferrer"
    >
      {chunks}
    </a>
  );
  const apkLink = (chunks: React.ReactNode) => (
    <Link className="text-accent underline" href="/download">
      {chunks}
    </Link>
  );
  const meshLocalLink = (chunks: React.ReactNode) => (
    <Link href="/tutorials/mesh-local" className="text-accent underline">
      {chunks}
    </Link>
  );
  const daemonLink = (chunks: React.ReactNode) => (
    <Link href="/tutorials/daemon" className="text-accent underline">
      {chunks}
    </Link>
  );

  return (
    <div className="page">
      <div className="page-body">
        <div className="wrap">
          <div className="tut">
            <header className="page-head reveal" style={{ maxWidth: "none" }}>
              <span className="eyebrow">{shared("tutorialOf", { n: 1, total: 4 })}</span>
              <h1>{t("h1")}</h1>
              <p className="lede">{t("lede")}</p>
            </header>

            <article className="prose">
              <DocsSection id="prereqs" title={t("s1Title")}>
                <p>{t("s1P1")}</p>
                <ul className="ml-6 list-disc space-y-2">
                  <li>{t.rich("s1Li1", { b })}</li>
                  <li>
                    {t.rich("s1Li2", { b, appStore, googlePlay, apk: apkLink })}
                  </li>
                </ul>
                <p className="text-sm">{t.rich("s1P2", { b, code })}</p>
              </DocsSection>

              <DocsSection id="install" title={t("s2Title")}>
                <p>{t("s2P1")}</p>
                <InstallTabs />
                <p>{t("s2P2")}</p>
                <DocsSubsection title="pi install npm:remote-pi">
                  <p>{t.rich("s2Sub1P1", { code })}</p>
                </DocsSubsection>
                <DocsSubsection title="/remote-pi">
                  <p>{t.rich("s2Sub2P1", { b })}</p>
                  <ol className="ml-6 list-decimal space-y-2">
                    <li>{t.rich("s2Sub2Li1", { b })}</li>
                    <li>{t.rich("s2Sub2Li2", { b, code })}</li>
                  </ol>
                  <p>{t("s2Sub2P2")}</p>
                </DocsSubsection>
                <DocsSubsection title="/remote-pi pair">
                  <p>{t.rich("s2Sub3P1", { b })}</p>
                </DocsSubsection>
                <Callout variant="note" title={t("s2CalloutTitle")}>
                  {t.rich("s2CalloutBody", { code })}
                </Callout>
              </DocsSection>

              <DocsSection id="pair" title={t("s3Title")}>
                <p>{t("s3P1")}</p>
                <ol className="ml-6 list-decimal space-y-2">
                  <li>{t("s3Li1")}</li>
                  <li>{t.rich("s3Li2", { b })}</li>
                  <li>{t.rich("s3Li3", { code })}</li>
                </ol>
                <p className="text-sm">{t("s3P2")}</p>
              </DocsSection>

              <DocsSection id="first-command" title={t("s4Title")}>
                <p>{t("s4P1")}</p>
                <CodeBlock
                  code="List the files in this folder and tell me what this project is."
                  label={t("s4CodeLabel")}
                  language="text"
                />
                <p>{t("s4P2")}</p>
                <p>{t.rich("s4P3", { b })}</p>
              </DocsSection>

              <DocsSection id="next" title={t("s5Title")}>
                <p>{t("s5P1")}</p>
                <ul className="ml-6 list-disc space-y-2">
                  <li>{t.rich("s5Li1", { link: meshLocalLink })}</li>
                  <li>{t.rich("s5Li2", { link: daemonLink })}</li>
                </ul>
              </DocsSection>
            </article>

            <Pager next={{ href: "/tutorials/mesh-local", label: idx("meshLocalTitle") }} />
          </div>
        </div>
      </div>
      <RevealController />
    </div>
  );
}
