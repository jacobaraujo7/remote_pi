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
  const t = await getTranslations({ locale, namespace: "TutorialDaemon" });
  return {
    title: t("title"),
    description: t("metaDescription"),
    alternates: { languages: localeAlternates("/tutorials/daemon") },
  };
}

export default async function DaemonTutorial({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  const t = await getTranslations({ locale, namespace: "TutorialDaemon" });
  const shared = await getTranslations({ locale, namespace: "DocsShared" });
  const idx = await getTranslations({ locale, namespace: "TutorialsIndex" });
  const b = (chunks: React.ReactNode) => <strong className="text-fg">{chunks}</strong>;
  const em = (chunks: React.ReactNode) => <em className="text-fg">{chunks}</em>;
  const i = (chunks: React.ReactNode) => <em>{chunks}</em>;
  const code = (chunks: React.ReactNode) => <InlineCode>{chunks}</InlineCode>;
  const why = (chunks: React.ReactNode) => <Link href="/why">{chunks}</Link>;
  const cronDocsLink = (chunks: React.ReactNode) => (
    <Link href="/docs#commands-cron" className="text-accent underline">
      {chunks}
    </Link>
  );
  const daemonDocsLink = (chunks: React.ReactNode) => (
    <Link href="/docs#daemon-mode" className="text-accent underline">
      {chunks}
    </Link>
  );

  return (
    <div className="page">
      <div className="page-body">
        <div className="wrap">
          <div className="tut">
            <header className="page-head reveal" style={{ maxWidth: "none" }}>
              <span className="eyebrow">{shared("tutorialOf", { n: 4, total: 4 })}</span>
              <h1>{t("h1")}</h1>
              <p className="lede">{t.rich("lede", { em, why })}</p>
            </header>

            <article className="prose">
              <DocsSection id="model" title={t("s1Title")}>
                <p>{t.rich("s1P1", { b, code })}</p>
                <Callout variant="warning" title={t("s1CalloutTitle")}>
                  {t.rich("s1CalloutBody", { code, b, em })}
                </Callout>
              </DocsSection>

              <DocsSection id="install" title={t("s2Title")}>
                <p>{t("s2P1")}</p>
                <CodeBlock code="/remote-pi install" label={t("s2CodeLabel1")} language="text" />
                <p>{t("s2P2")}</p>
                <ul className="ml-6 list-disc space-y-2">
                  <li>{t.rich("s2Li1", { code })}</li>
                  <li>{t.rich("s2Li2", { code })}</li>
                </ul>
                <p className="text-sm">{t.rich("s2P3", { b })}</p>
              </DocsSection>

              <DocsSection id="create" title={t("s3Title")}>
                <p>{t.rich("s3P1", { code })}</p>
                <CodeBlock
                  code={`remote-pi create ~/Movies --name "Video Editor"
# → Daemon registered: id=4e39152d name="Video Editor" cwd=/Users/you/Movies · started`}
                  label={t("s3CodeLabel")}
                  language="bash"
                />
                <p>{t.rich("s3P2", { code, b })}</p>
                <Callout variant="note" title={t("s3CalloutTitle")}>
                  {t.rich("s3CalloutBody", { code })}
                </Callout>
              </DocsSection>

              <DocsSection id="fleet" title={t("s4Title")}>
                <p>{t.rich("s4P1", { code })}</p>
                <CodeBlock
                  code={`remote-pi daemons                  # list registered daemons + state
remote-pi daemon status            # pid, uptime, restart count
remote-pi daemon send 4e39152d "Cut the first 30s of the latest clip"
remote-pi daemon restart 4e39152d  # restart one daemon by id
remote-pi daemon restart           # ...or the whole fleet (no id)
remote-pi daemon stop 4e39152d     # stop one
remote-pi daemon stop              # stop all`}
                  label={t("s4CodeLabel1")}
                  language="bash"
                />
                <p>{t("s4P2")}</p>
                <DocsSubsection title={t("s4SubTitle")}>
                  <CodeBlock
                    code={`# Linux
journalctl --user -u remote-pi-supervisord -f

# macOS
tail -f ~/.pi/remote/supervisord.log`}
                    label={t("s4CodeLabel2")}
                    language="bash"
                  />
                  <p>{t.rich("s4SubP1", { code })}</p>
                </DocsSubsection>
              </DocsSection>

              <DocsSection id="cron" title={t("s5Title")}>
                <p>{t.rich("s5P1", { code })}</p>
                <Callout variant="warning" title={t("s5CalloutTitle")}>
                  {t.rich("s5CalloutBody", { i, code })}
                </Callout>
                <p>{t("s5P2")}</p>
                <CodeBlock
                  code={`# every weekday at 9am, São Paulo time
remote-pi cron add 4e39152d "0 9 * * 1-5" "Summarize the new PRs" --tz America/Sao_Paulo
# → Cron j_ab12 added → daemon 4e39152d: "0 9 * * 1-5" (America/Sao_Paulo). Next run: …`}
                  label={t("s5CodeLabel1")}
                  language="bash"
                />
                <p>{t.rich("s5P3", { b, code })}</p>
                <ul className="ml-6 list-disc space-y-2">
                  <li>{t.rich("s5Li1", { code })}</li>
                  <li>{t.rich("s5Li2", { code })}</li>
                  <li>{t.rich("s5Li3", { code })}</li>
                  <li>{t.rich("s5Li4", { code, i })}</li>
                </ul>
                <p>{t.rich("s5P4", { code })}</p>
                <CodeBlock
                  code={`remote-pi cron list                # schedule, enabled, last run/status, next run
remote-pi cron run j_ab12          # fire one now, ignoring its schedule
remote-pi cron disable j_ab12      # pause without deleting (enable to resume)
remote-pi cron log --tail 20       # recent fires AND skips
remote-pi cron remove j_ab12       # delete the job`}
                  label={t("s5CodeLabel2")}
                  language="bash"
                />
                <p>{t.rich("s5P5", { code, i, link: cronDocsLink })}</p>
              </DocsSection>

              <DocsSection id="cleanup" title={t("s6Title")}>
                <CodeBlock
                  code={`remote-pi remove <id>              # unregister one daemon (folder config kept)
remote-pi uninstall                # remove the supervisor service (registry kept)`}
                  label={t("s6CodeLabel")}
                  language="bash"
                />
                <p>{t.rich("s6P1", { code, link: daemonDocsLink })}</p>
              </DocsSection>
            </article>

            <Pager prev={{ href: "/tutorials/mesh-remote", label: idx("meshRemoteTitle") }} />
          </div>
        </div>
      </div>
      <RevealController />
    </div>
  );
}
