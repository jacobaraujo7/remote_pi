import type { Metadata } from "next";
import { getTranslations } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import { DocsSection, InlineCode } from "@/components/docs-shell";
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
  const t = await getTranslations({ locale, namespace: "TutorialMeshLocal" });
  return {
    title: t("title"),
    description: t("metaDescription"),
    alternates: { languages: localeAlternates("/tutorials/mesh-local") },
  };
}

export default async function MeshLocalTutorial({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  const t = await getTranslations({ locale, namespace: "TutorialMeshLocal" });
  const shared = await getTranslations({ locale, namespace: "DocsShared" });
  const idx = await getTranslations({ locale, namespace: "TutorialsIndex" });
  const b = (chunks: React.ReactNode) => <strong className="text-fg">{chunks}</strong>;
  const code = (chunks: React.ReactNode) => <InlineCode>{chunks}</InlineCode>;
  const gettingStarted = (chunks: React.ReactNode) => (
    <Link href="/tutorials/getting-started" className="text-accent underline">
      {chunks}
    </Link>
  );

  return (
    <div className="page">
      <div className="page-body">
        <div className="wrap">
          <div className="tut">
            <header className="page-head reveal" style={{ maxWidth: "none" }}>
              <span className="eyebrow">{shared("tutorialOf", { n: 2, total: 4 })}</span>
              <h1>{t("h1")}</h1>
              <p className="lede">{t("lede")}</p>
            </header>

            <article className="prose">
              <DocsSection id="how" title={t("s1Title")}>
                <p>{t.rich("s1P1", { code })}</p>
                <Callout variant="note" title={t("s1CalloutTitle")}>
                  {t.rich("s1CalloutBody", { b, code })}
                </Callout>
              </DocsSection>

              <DocsSection id="start" title={t("s2Title")}>
                <p>{t.rich("s2P1", { b, link: gettingStarted })}</p>
                <CodeBlock
                  code={`cd ~/code/service-b
pi            # then run /remote-pi and answer the wizard`}
                  label={t("s2CodeLabel")}
                  language="bash"
                />
                <p>{t.rich("s2P2", { code })}</p>
              </DocsSection>

              <DocsSection id="tools" title={t("s3Title")}>
                <p>{t("s3P1")}</p>
                <ul className="ml-6 list-disc space-y-2">
                  <li>{t.rich("s3Li1", { code })}</li>
                  <li>{t.rich("s3Li2", { code })}</li>
                  <li>{t.rich("s3Li3", { code })}</li>
                </ul>
              </DocsSection>

              <DocsSection id="exchange" title={t("s4Title")}>
                <p>{t.rich("s4P1", { code })}</p>
                <CodeBlock
                  code="List the other agents available."
                  label={t("s4PromptLabel1")}
                  language="text"
                />
                <p>{t("s4P2")}</p>
                <CodeBlock
                  code={`list_peers()
→ agent-b`}
                  label={t("s4ToolLabel1")}
                  language="text"
                />
                <p>{t("s4P3")}</p>
                <CodeBlock
                  code="Send agent-b a ping with the current time."
                  label={t("s4PromptLabel1")}
                  language="text"
                />
                <CodeBlock
                  code={`agent_send({
  to: "agent-b",
  body: { type: "ping", at: "2026-05-31T14:02:00Z" }
})
→ Delivered to agent-b`}
                  label={t("s4ToolLabel1")}
                  language="text"
                />
                <p>{t.rich("s4P4", { code })}</p>
                <CodeBlock
                  code="Any new messages? If so, reply to the sender."
                  label={t("s4PromptLabel2")}
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
                  label={t("s4ToolLabel2")}
                  language="text"
                />
                <p>{t.rich("s4P5", { code })}</p>
              </DocsSection>

              <DocsSection id="acks" title={t("s5Title")}>
                <p>{t.rich("s5P1", { code })}</p>
                <ul className="ml-6 list-disc space-y-2">
                  <li>{t.rich("s5Li1", { code })}</li>
                  <li>{t.rich("s5Li2", { code })}</li>
                  <li>{t.rich("s5Li3", { code })}</li>
                  <li>{t.rich("s5Li4", { b })}</li>
                </ul>
                <Callout variant="note" title={t("s5CalloutTitle")}>
                  {t.rich("s5CalloutBody", { code })}
                </Callout>
              </DocsSection>
            </article>

            <Pager
              prev={{ href: "/tutorials/getting-started", label: idx("gettingStartedTitle") }}
              next={{ href: "/tutorials/mesh-remote", label: idx("meshRemoteTitle") }}
            />
          </div>
        </div>
      </div>
      <RevealController />
    </div>
  );
}
