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
    namespace: "RemoteTutorials.daemon",
  });
  return {
    title: t("meta.title"),
    description: t("meta.description"),
    alternates: pageAlternates(locale, "/remote-pi/tutorials/daemon"),
  };
}

/* Inline tags used by the messages: <code1>, <a2>... Handlers live here so
   each message just spreads TAGS. Contents of <code*> are never translated. */
const TAGS = {
  em1: (c: ReactNode) => <em>{c}</em>,
  link1: (c: ReactNode) => <Link href="/remote-pi/why">{c}</Link>,
  strong1: (c: ReactNode) => <strong className="text-fg">{c}</strong>,
  code1: (c: ReactNode) => <InlineCode>{c}</InlineCode>,
  em2: (c: ReactNode) => <em className="text-fg">{c}</em>,
  link2: (c: ReactNode) => (
    <Link
      href="/remote-pi/docs#commands-cron"
      className="text-accent underline"
    >
      {c}
    </Link>
  ),
  link3: (c: ReactNode) => (
    <Link href="/remote-pi/docs#daemon-mode" className="text-accent underline">
      {c}
    </Link>
  ),
};

export default async function DaemonTutorial({ params }: Props) {
  const { locale } = await params;
  setRequestLocale(locale);
  const t = await getTranslations({
    locale,
    namespace: "RemoteTutorials.daemon",
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
              <DocsSection id="model" title={t("model.title")}>
                <p>{t.rich("model.p1", TAGS)}</p>
                <Callout variant="warning" title={t("model.callout1")}>
                  {t.rich("model.callout2", TAGS)}
                </Callout>
              </DocsSection>

              <DocsSection id="install" title={t("install.title")}>
                <p>{t("install.p1")}</p>
                <CodeBlock
                  code="/remote-pi install"
                  label={t("install.label1")}
                  language="text"
                />
                <p>{t("install.p2")}</p>
                <ul className="ml-6 list-disc space-y-2">
                  <li>{t.rich("install.li1", TAGS)}</li>
                  <li>{t.rich("install.li2", TAGS)}</li>
                </ul>
                <p className="text-sm">{t.rich("install.p3", TAGS)}</p>
              </DocsSection>

              <DocsSection id="create" title={t("create.title")}>
                <p>{t.rich("create.p1", TAGS)}</p>
                <CodeBlock
                  code={`remote-pi create ~/Movies --name "Video Editor"
# → Daemon registered: id=4e39152d name="Video Editor" cwd=/Users/you/Movies · started`}
                  label="Shell"
                  language="bash"
                />
                <p>{t.rich("create.p2", TAGS)}</p>
                <Callout variant="note" title={t("create.callout1")}>
                  {t.rich("create.callout2", TAGS)}
                </Callout>
              </DocsSection>

              <DocsSection id="fleet" title={t("fleet.title")}>
                <p>{t.rich("fleet.p1", TAGS)}</p>
                <CodeBlock
                  code={`remote-pi daemons                  # list registered daemons + state
remote-pi daemon status            # pid, uptime, restart count
remote-pi daemon send 4e39152d "Cut the first 30s of the latest clip"
remote-pi daemon restart 4e39152d  # restart one daemon by id
remote-pi daemon restart           # ...or the whole fleet (no id)
remote-pi daemon stop 4e39152d     # stop one
remote-pi daemon stop              # stop all`}
                  label={t("fleet.label1")}
                  language="bash"
                />
                <p>{t("fleet.p2")}</p>
                <DocsSubsection title={t("fleet_WhereTheLogsAre.title")}>
                  <CodeBlock
                    code={`# Linux
journalctl --user -u remote-pi-supervisord -f

# macOS
tail -f ~/.pi/remote/supervisord.log`}
                    label="Logs"
                    language="bash"
                  />
                  <p>{t.rich("fleet_WhereTheLogsAre.p1", TAGS)}</p>
                </DocsSubsection>
              </DocsSection>

              <DocsSection id="cron" title={t("cron.title")}>
                <p>{t.rich("cron.p1", TAGS)}</p>
                <Callout variant="warning" title={t("cron.callout1")}>
                  {t.rich("cron.callout2", TAGS)}
                </Callout>
                <p>{t("cron.p2")}</p>
                <CodeBlock
                  code={`# every weekday at 9am, São Paulo time
remote-pi cron add 4e39152d "0 9 * * 1-5" "Summarize the new PRs" --tz America/Sao_Paulo
# → Cron j_ab12 added → daemon 4e39152d: "0 9 * * 1-5" (America/Sao_Paulo). Next run: …`}
                  label={t("cron.label1")}
                  language="bash"
                />
                <p>{t.rich("cron.p3", TAGS)}</p>
                <ul className="ml-6 list-disc space-y-2">
                  <li>{t.rich("cron.li1", TAGS)}</li>
                  <li>{t.rich("cron.li2", TAGS)}</li>
                  <li>{t.rich("cron.li3", TAGS)}</li>
                  <li>{t.rich("cron.li4", TAGS)}</li>
                </ul>
                <p>{t.rich("cron.p4", TAGS)}</p>
                <CodeBlock
                  code={`remote-pi cron list                # schedule, enabled, last run/status, next run
remote-pi cron run j_ab12          # fire one now, ignoring its schedule
remote-pi cron disable j_ab12      # pause without deleting (enable to resume)
remote-pi cron log --tail 20       # recent fires AND skips
remote-pi cron remove j_ab12       # delete the job`}
                  label="Inspect & audit"
                  language="bash"
                />
                <p>{t.rich("cron.p5", TAGS)}</p>
              </DocsSection>

              <DocsSection id="cleanup" title={t("cleanup.title")}>
                <CodeBlock
                  code={`remote-pi remove <id>              # unregister one daemon (folder config kept)
remote-pi uninstall                # remove the supervisor service (registry kept)`}
                  label="Cleanup"
                  language="bash"
                />
                <p>{t.rich("cleanup.p1", TAGS)}</p>
              </DocsSection>
            </article>

            <Pager
              prev={{
                href: "/remote-pi/tutorials/mesh-remote",
                label: t("pager.prev"),
              }}
            />
          </div>
        </div>
      </div>
      <RevealController />
    </div>
  );
}
