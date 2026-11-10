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
import { InstallTabs } from "@/components/install-tabs";
import { Callout } from "@/components/callout";
import { Pager } from "@/components/pager";
import { RevealController } from "@/components/landing/reveal-controller";

type Props = { params: Promise<{ locale: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { locale } = await params;
  const t = await getTranslations({
    locale,
    namespace: "RemoteTutorials.gettingStarted",
  });
  return {
    title: t("meta.title"),
    description: t("meta.description"),
    alternates: pageAlternates(locale, "/remote-pi/tutorials/getting-started"),
  };
}

/* Inline tags used by the messages: <code1>, <a2>... Handlers live here so
   each message just spreads TAGS. Contents of <code*> are never translated. */
const TAGS = {
  strong1: (c: ReactNode) => <strong className="text-fg">{c}</strong>,
  a1: (c: ReactNode) => (
    <a
      className="text-accent underline"
      href="https://apps.apple.com/app/remote-pi-coding-agent/id6773499691"
      target="_blank"
      rel="noopener noreferrer"
    >
      {c}
    </a>
  ),
  a2: (c: ReactNode) => (
    <a
      className="text-accent underline"
      href="https://play.google.com/store/apps/details?id=work.jacobmoura.remotepi"
      target="_blank"
      rel="noopener noreferrer"
    >
      {c}
    </a>
  ),
  link1: (c: ReactNode) => (
    <Link className="text-accent underline" href="/remote-pi/download">
      {c}
    </Link>
  ),
  code1: (c: ReactNode) => <InlineCode>{c}</InlineCode>,
  link2: (c: ReactNode) => (
    <Link
      href="/remote-pi/tutorials/mesh-local"
      className="text-accent underline"
    >
      {c}
    </Link>
  ),
  link3: (c: ReactNode) => (
    <Link href="/remote-pi/tutorials/daemon" className="text-accent underline">
      {c}
    </Link>
  ),
};

export default async function GettingStartedTutorial({ params }: Props) {
  const { locale } = await params;
  setRequestLocale(locale);
  const t = await getTranslations({
    locale,
    namespace: "RemoteTutorials.gettingStarted",
  });
  return (
    <div className="page">
      <div className="page-body">
        <div className="wrap">
          <div className="tut">
            <header className="page-head reveal" style={{ maxWidth: "none" }}>
              <span className="eyebrow">{t("intro.span1")}</span>
              <h1>{t("intro.h11")}</h1>
              <p className="lede">{t("intro.p1")}</p>
            </header>

            <article className="prose">
              <DocsSection id="prereqs" title={t("prereqs.title")}>
                <p>{t("prereqs.p1")}</p>
                <ul className="ml-6 list-disc space-y-2">
                  <li>{t.rich("prereqs.li1", TAGS)}</li>
                  <li>{t.rich("prereqs.li2", TAGS)}</li>
                </ul>
                <p className="text-sm">{t.rich("prereqs.p2", TAGS)}</p>
              </DocsSection>

              <DocsSection id="install" title={t("install.title")}>
                <p>{t("install.p1")}</p>
                <InstallTabs />
                <p>{t("install.p2")}</p>
                <DocsSubsection title={t("install_piInstallNpmremotePi.title")}>
                  <p>{t.rich("install_piInstallNpmremotePi.p1", TAGS)}</p>
                </DocsSubsection>
                <DocsSubsection title={t("install_remotePi.title")}>
                  <p>{t.rich("install_remotePi.p1", TAGS)}</p>
                  <ol className="ml-6 list-decimal space-y-2">
                    <li>{t.rich("install_remotePi.li1", TAGS)}</li>
                    <li>{t.rich("install_remotePi.li2", TAGS)}</li>
                  </ol>
                  <p>{t("install_remotePi.p2")}</p>
                </DocsSubsection>
                <DocsSubsection title={t("install_remotePiPair.title")}>
                  <p>{t.rich("install_remotePiPair.p1", TAGS)}</p>
                </DocsSubsection>
                <Callout variant="note" title={t("install.callout1")}>
                  {t.rich("install.callout2", TAGS)}
                </Callout>
              </DocsSection>

              <DocsSection id="pair" title={t("pair.title")}>
                <p>{t("pair.p1")}</p>
                <ol className="ml-6 list-decimal space-y-2">
                  <li>{t("pair.li1")}</li>
                  <li>{t.rich("pair.li2", TAGS)}</li>
                  <li>{t.rich("pair.li3", TAGS)}</li>
                </ol>
                <p className="text-sm">{t("pair.p2")}</p>
              </DocsSection>

              <DocsSection id="first-command" title={t("firstCommand.title")}>
                <p>{t("firstCommand.p1")}</p>
                <CodeBlock
                  code="List the files in this folder and tell me what this project is."
                  label={t("firstCommand.label1")}
                  language="text"
                />
                <p>{t("firstCommand.p2")}</p>
                <p>{t.rich("firstCommand.p3", TAGS)}</p>
              </DocsSection>

              <DocsSection id="next" title={t("next.title")}>
                <p>{t("next.p1")}</p>
                <ul className="ml-6 list-disc space-y-2">
                  <li>{t.rich("next.li1", TAGS)}</li>
                  <li>{t.rich("next.li2", TAGS)}</li>
                </ul>
              </DocsSection>
            </article>

            <Pager
              next={{
                href: "/remote-pi/tutorials/mesh-local",
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
