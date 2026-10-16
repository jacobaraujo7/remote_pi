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

const GITHUB_URL = "https://github.com/jacobaraujo7/remote_pi";

type Props = { params: Promise<{ locale: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { locale } = await params;
  const t = await getTranslations({
    locale,
    namespace: "RemoteTutorials.meshRemote",
  });
  return {
    title: t("meta.title"),
    description: t("meta.description"),
    alternates: pageAlternates(locale, "/remote-pi/tutorials/mesh-remote"),
  };
}

/* Inline tags used by the messages: <code1>, <a2>... Handlers live here so
   each message just spreads TAGS. Contents of <code*> are never translated. */
const TAGS = {
  link1: (c: ReactNode) => (
    <Link href="/remote-pi/tutorials/mesh-local">{c}</Link>
  ),
  code1: (c: ReactNode) => <InlineCode>{c}</InlineCode>,
  strong1: (c: ReactNode) => <strong className="text-fg">{c}</strong>,
  a1: (c: ReactNode) => (
    <a
      className="text-accent underline"
      href={`${GITHUB_URL}/blob/main/PROTOCOL.md`}
      target="_blank"
      rel="noopener noreferrer"
    >
      {c}
    </a>
  ),
  link2: (c: ReactNode) => (
    <Link href="/remote-pi/docs#relay" className="text-accent underline">
      {c}
    </Link>
  ),
  em1: (c: ReactNode) => <em className="text-fg">{c}</em>,
  link3: (c: ReactNode) => (
    <Link href="/remote-pi/docs#self-host" className="text-accent underline">
      {c}
    </Link>
  ),
  link4: (c: ReactNode) => (
    <Link href="/remote-pi/tutorials/daemon" className="text-accent underline">
      {c}
    </Link>
  ),
};

export default async function MeshRemoteTutorial({ params }: Props) {
  const { locale } = await params;
  setRequestLocale(locale);
  const t = await getTranslations({
    locale,
    namespace: "RemoteTutorials.meshRemote",
  });
  return (
    <div className="page">
      <div className="page-body">
        <div className="wrap">
          <div className="tut">
            <header className="page-head reveal" style={{ maxWidth: "none" }}>
              <span className="eyebrow">{t("intro.span1")}</span>
              <h1>{t("intro.h11")}</h1>
              <p className="lede">{t.rich("intro.p1", TAGS)}</p>
            </header>

            <article className="prose">
              <DocsSection id="setup" title={t("setup.title")}>
                <p>{t.rich("setup.p1", TAGS)}</p>
                <ul className="ml-6 list-disc space-y-2">
                  <li>{t.rich("setup.li1", TAGS)}</li>
                  <li>{t.rich("setup.li2", TAGS)}</li>
                </ul>
                <p>{t.rich("setup.p2", TAGS)}</p>
              </DocsSection>

              <DocsSection id="addressing" title={t("addressing.title")}>
                <p>{t.rich("addressing.p1", TAGS)}</p>
                <CodeBlock
                  code={`list_peers()
→ frontend                 # local — same machine
  MacMini:backend          # remote — agent "backend" on PC "MacMini"
  build-box:tests          # remote — agent "tests" on PC "build-box"`}
                  label={t("addressing.label1")}
                  language="text"
                />
                <p>{t.rich("addressing.p2", TAGS)}</p>
                <CodeBlock
                  code={`agent_send({
  to: "MacMini:backend",
  body: { task: "run the integration suite and report failures" }
})
→ Delivered to MacMini:backend`}
                  label={t("addressing.label2")}
                  language="text"
                />
                <p>{t.rich("addressing.p3", TAGS)}</p>
              </DocsSection>

              <DocsSection id="delivered" title={t("delivered.title")}>
                <p>{t.rich("delivered.p1", TAGS)}</p>
                <Callout variant="warning" title={t("delivered.callout1")}>
                  {t.rich("delivered.callout2", TAGS)}
                </Callout>
                <p>{t.rich("delivered.p2", TAGS)}</p>
              </DocsSection>

              <DocsSection id="trust" title={t("trust.title")}>
                <p>{t("trust.p1")}</p>
                <Callout variant="warning" title={t("trust.callout1")}>
                  {t.rich("trust.callout2", TAGS)}
                </Callout>
                <p className="text-sm">{t.rich("trust.p2", TAGS)}</p>
              </DocsSection>

              <DocsSection id="uses" title={t("uses.title")}>
                <p>{t.rich("uses.p1", TAGS)}</p>
                <DocsSubsection title={t("uses_KeepThemReachable.title")}>
                  <p>{t.rich("uses_KeepThemReachable.p1", TAGS)}</p>
                </DocsSubsection>
              </DocsSection>
            </article>

            <Pager
              prev={{
                href: "/remote-pi/tutorials/mesh-local",
                label: t("pager.prev"),
              }}
              next={{
                href: "/remote-pi/tutorials/daemon",
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
