import type { Metadata } from "next";
import { getTranslations } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import { DocsSection, DocsSubsection, InlineCode } from "@/components/docs-shell";
import { CodeBlock } from "@/components/code-block";
import { Callout } from "@/components/callout";
import { Pager } from "@/components/pager";
import { RevealController } from "@/components/landing/reveal-controller";
import { localeAlternates } from "@/i18n/alternates";

const GITHUB_URL = "https://github.com/jacobaraujo7/remote_pi";
const PROTOCOL_URL = `${GITHUB_URL}/blob/main/PROTOCOL.md`;

export async function generateMetadata({
  params,
}: {
  params: Promise<{ locale: string }>;
}): Promise<Metadata> {
  const { locale } = await params;
  const t = await getTranslations({ locale, namespace: "TutorialMeshRemote" });
  return {
    title: t("title"),
    description: t("metaDescription"),
    alternates: { languages: localeAlternates("/tutorials/mesh-remote") },
  };
}

export default async function MeshRemoteTutorial({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  const t = await getTranslations({ locale, namespace: "TutorialMeshRemote" });
  const shared = await getTranslations({ locale, namespace: "DocsShared" });
  const idx = await getTranslations({ locale, namespace: "TutorialsIndex" });
  const b = (chunks: React.ReactNode) => <strong className="text-fg">{chunks}</strong>;
  const em = (chunks: React.ReactNode) => <em className="text-fg">{chunks}</em>;
  const code = (chunks: React.ReactNode) => <InlineCode>{chunks}</InlineCode>;
  const meshLocal = (chunks: React.ReactNode) => (
    <Link href="/tutorials/mesh-local">{chunks}</Link>
  );
  const protocolLink = (chunks: React.ReactNode) => (
    <a className="text-accent underline" href={PROTOCOL_URL} target="_blank" rel="noopener noreferrer">
      {chunks}
    </a>
  );
  const relayLink = (chunks: React.ReactNode) => (
    <Link href="/docs#relay" className="text-accent underline">
      {chunks}
    </Link>
  );
  const selfHostLink = (chunks: React.ReactNode) => (
    <Link href="/docs#self-host" className="text-accent underline">
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
              <span className="eyebrow">{shared("tutorialOf", { n: 3, total: 4 })}</span>
              <h1>{t("h1")}</h1>
              <p className="lede">{t.rich("lede", { meshLocal, code })}</p>
            </header>

            <article className="prose">
              <DocsSection id="setup" title={t("s1Title")}>
                <p>{t.rich("s1P1", { b })}</p>
                <ul className="ml-6 list-disc space-y-2">
                  <li>{t.rich("s1Li1", { code, b })}</li>
                  <li>{t.rich("s1Li2", { b, link: protocolLink })}</li>
                </ul>
                <p>{t.rich("s1P2", { link: relayLink })}</p>
              </DocsSection>

              <DocsSection id="addressing" title={t("s2Title")}>
                <p>{t.rich("s2P1", { code })}</p>
                <CodeBlock
                  code={`list_peers()
→ frontend                 # local — same machine
  MacMini:backend          # remote — agent "backend" on PC "MacMini"
  build-box:tests          # remote — agent "tests" on PC "build-box"`}
                  label={t("s2CodeLabel1")}
                  language="text"
                />
                <p>{t.rich("s2P2", { code })}</p>
                <CodeBlock
                  code={`agent_send({
  to: "MacMini:backend",
  body: { task: "run the integration suite and report failures" }
})
→ Delivered to MacMini:backend`}
                  label={t("s2CodeLabel2")}
                  language="text"
                />
                <p>{t.rich("s2P3", { code })}</p>
              </DocsSection>

              <DocsSection id="delivered" title={t("s3Title")}>
                <p>{t.rich("s3P1", { code, b, em })}</p>
                <Callout variant="warning" title={t("s3CalloutTitle")}>
                  {t.rich("s3CalloutBody", { code, b })}
                </Callout>
                <p>{t.rich("s3P2", { code })}</p>
              </DocsSection>

              <DocsSection id="trust" title={t("s4Title")}>
                <p>{t("s4P1")}</p>
                <Callout variant="warning" title={t("s4CalloutTitle")}>
                  {t.rich("s4CalloutBody", { b, link: selfHostLink })}
                </Callout>
                <p className="text-sm">{t.rich("s4P2", { link: protocolLink })}</p>
              </DocsSection>

              <DocsSection id="uses" title={t("s5Title")}>
                <p>{t.rich("s5P1", { code })}</p>
                <DocsSubsection title={t("s5SubTitle")}>
                  <p>{t.rich("s5SubP1", { link: daemonLink })}</p>
                </DocsSubsection>
              </DocsSection>
            </article>

            <Pager
              prev={{ href: "/tutorials/mesh-local", label: idx("meshLocalTitle") }}
              next={{ href: "/tutorials/daemon", label: idx("daemonTitle") }}
            />
          </div>
        </div>
      </div>
      <RevealController />
    </div>
  );
}
