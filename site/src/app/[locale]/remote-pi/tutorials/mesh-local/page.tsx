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
    namespace: "RemoteTutorials.meshLocal",
  });
  return {
    title: t("meta.title"),
    description: t("meta.description"),
    alternates: pageAlternates(locale, "/remote-pi/tutorials/mesh-local"),
  };
}

/* Inline tags used by the messages: <code1>, <a2>... Handlers live here so
   each message just spreads TAGS. Contents of <code*> are never translated. */
const TAGS = {
  code1: (c: ReactNode) => <InlineCode>{c}</InlineCode>,
  strong1: (c: ReactNode) => <strong className="text-fg">{c}</strong>,
  link1: (c: ReactNode) => (
    <Link
      href="/remote-pi/tutorials/getting-started"
      className="text-accent underline"
    >
      {c}
    </Link>
  ),
};

export default async function MeshLocalTutorial({ params }: Props) {
  const { locale } = await params;
  setRequestLocale(locale);
  const t = await getTranslations({
    locale,
    namespace: "RemoteTutorials.meshLocal",
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
              <DocsSection id="how" title={t("how.title")}>
                <p>{t.rich("how.p1", TAGS)}</p>
                <Callout variant="note" title={t("how.callout1")}>
                  {t.rich("how.callout2", TAGS)}
                </Callout>
              </DocsSection>

              <DocsSection id="start" title={t("start.title")}>
                <p>{t.rich("start.p1", TAGS)}</p>
                <CodeBlock
                  code={`cd ~/code/service-b
pi            # then run /remote-pi and answer the wizard`}
                  label={t("start.label1")}
                  language="bash"
                />
                <p>{t.rich("start.p2", TAGS)}</p>
              </DocsSection>

              <DocsSection id="tools" title={t("tools.title")}>
                <p>{t("tools.p1")}</p>
                <ul className="ml-6 list-disc space-y-2">
                  <li>{t.rich("tools.li1", TAGS)}</li>
                  <li>{t.rich("tools.li2", TAGS)}</li>
                  <li>{t.rich("tools.li3", TAGS)}</li>
                </ul>
              </DocsSection>

              <DocsSection id="exchange" title={t("exchange.title")}>
                <p>{t.rich("exchange.p1", TAGS)}</p>
                <CodeBlock
                  code="List the other agents available."
                  label={t("exchange.label1")}
                  language="text"
                />
                <p>{t("exchange.p2")}</p>
                <CodeBlock
                  code={`list_peers()
→ agent-b`}
                  label={t("exchange.label2")}
                  language="text"
                />
                <p>{t("exchange.p3")}</p>
                <CodeBlock
                  code="Send agent-b a ping with the current time."
                  label={t("exchange.label3")}
                  language="text"
                />
                <CodeBlock
                  code={`agent_send({
  to: "agent-b",
  body: { type: "ping", at: "2026-05-31T14:02:00Z" }
})
→ Delivered to agent-b`}
                  label={t("exchange.label4")}
                  language="text"
                />
                <p>{t.rich("exchange.p4", TAGS)}</p>
                <CodeBlock
                  code="Any new messages? If so, reply to the sender."
                  label={t("exchange.label5")}
                  language="text"
                />
                <CodeBlock
                  code={`get_messages()
→ [2026-05-31T14:02:00Z] from=agent-a
  id=ab12cd34
  { "type": "ping", "at": "2026-05-31T14:02:00Z" }

agent_send({
  to: "agent-a",
  body: { type: "pong" },
  re: "ab12cd34"        // reply to the ping's id
})
→ Delivered to agent-a`}
                  label={t("exchange.label6")}
                  language="text"
                />
                <p>{t.rich("exchange.p5", TAGS)}</p>
              </DocsSection>

              <DocsSection id="acks" title={t("acks.title")}>
                <p>{t.rich("acks.p1", TAGS)}</p>
                <ul className="ml-6 list-disc space-y-2">
                  <li>{t.rich("acks.li1", TAGS)}</li>
                  <li>{t.rich("acks.li2", TAGS)}</li>
                  <li>{t.rich("acks.li3", TAGS)}</li>
                  <li>{t.rich("acks.li4", TAGS)}</li>
                </ul>
                <Callout variant="note" title={t("acks.callout1")}>
                  {t.rich("acks.callout2", TAGS)}
                </Callout>
              </DocsSection>
            </article>

            <Pager
              prev={{
                href: "/remote-pi/tutorials/getting-started",
                label: t("pager.prev"),
              }}
              next={{
                href: "/remote-pi/tutorials/mesh-remote",
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
