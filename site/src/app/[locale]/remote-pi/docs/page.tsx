import type { Metadata } from "next";
import type { ReactNode } from "react";
import { getTranslations, setRequestLocale } from "next-intl/server";
import { pageAlternates } from "@/i18n/alternates";
import { Link } from "@/i18n/navigation";
import {
  DocsSection,
  DocsSubsection,
  InlineCode,
  DocsTable,
} from "@/components/docs-shell";
import { CodeBlock } from "@/components/code-block";
import { DocsToc, type TocItem } from "@/components/docs-toc";
import { RevealController } from "@/components/landing/reveal-controller";

type Props = { params: Promise<{ locale: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { locale } = await params;
  const t = await getTranslations({ locale, namespace: "RemoteDocs" });
  return {
    title: t("meta.title"),
    description: t("meta.description"),
    alternates: pageAlternates(locale, "/remote-pi/docs"),
  };
}

const GITHUB_URL = "https://github.com/jacobaraujo7/remote_pi";
const PI_URL = "https://github.com/earendil-works/pi";
const RELAY_README_URL =
  "https://github.com/jacobaraujo7/remote_pi/blob/main/relay/README.md";
const ISSUES_URL = "https://github.com/jacobaraujo7/remote_pi/issues";

/* Inline tags used by the messages: <code1>, <a2>... Handlers live here so
   each message just spreads TAGS. Contents of <code*> are never translated. */
const TAGS = {
  code1: (c: ReactNode) => <InlineCode>{c}</InlineCode>,
  strong1: (c: ReactNode) => <strong className="text-fg">{c}</strong>,
  a1: (c: ReactNode) => (
    <a
      className="text-accent underline"
      href={PI_URL}
      target="_blank"
      rel="noopener noreferrer"
    >
      {c}
    </a>
  ),
  link1: (c: ReactNode) => (
    <Link href="/remote-pi/tutorials" className="text-accent underline">
      {c}
    </Link>
  ),
  link2: (c: ReactNode) => (
    <Link href="/remote-pi/why" className="text-accent underline">
      {c}
    </Link>
  ),
  link3: (c: ReactNode) => (
    <Link
      href="/remote-pi/tutorials/mesh-local"
      className="text-accent underline"
    >
      {c}
    </Link>
  ),
  link4: (c: ReactNode) => (
    <Link
      href="/remote-pi/tutorials/mesh-remote"
      className="text-accent underline"
    >
      {c}
    </Link>
  ),
  link5: (c: ReactNode) => (
    <Link
      href="/remote-pi/tutorials/getting-started"
      className="text-accent underline"
    >
      {c}
    </Link>
  ),
  a2: (c: ReactNode) => (
    <a href="#daemon-mode" className="text-accent underline">
      {c}
    </a>
  ),
  a3: (c: ReactNode) => (
    <a href="#commands" className="text-accent underline">
      {c}
    </a>
  ),
  a4: (c: ReactNode) => (
    <a
      className="text-accent underline"
      href={`${GITHUB_URL}/blob/main/PROTOCOL.md`}
      target="_blank"
      rel="noopener noreferrer"
    >
      {c}
    </a>
  ),
  em1: (c: ReactNode) => <em>{c}</em>,
  link6: (c: ReactNode) => (
    <Link href="/remote-pi/tutorials/daemon" className="text-accent underline">
      {c}
    </Link>
  ),
  a5: (c: ReactNode) => (
    <a href="#protocol" className="text-accent underline">
      {c}
    </a>
  ),
  a6: (c: ReactNode) => (
    <a
      className="text-accent underline"
      href="https://tailscale.com"
      target="_blank"
      rel="noopener noreferrer"
    >
      {c}
    </a>
  ),
  a7: (c: ReactNode) => (
    <a
      className="text-accent underline"
      href="https://www.wireguard.com"
      target="_blank"
      rel="noopener noreferrer"
    >
      {c}
    </a>
  ),
  a8: (c: ReactNode) => (
    <a
      className="text-accent underline"
      href={`${RELAY_README_URL}#self-hosted-relay-recommended-for-privacy`}
      target="_blank"
      rel="noopener noreferrer"
    >
      {c}
    </a>
  ),
  a9: (c: ReactNode) => (
    <a href="#self-host" className="text-accent underline">
      {c}
    </a>
  ),
  link7: (c: ReactNode) => (
    <Link
      href="/remote-pi/tutorials/daemon#cron"
      className="text-accent underline"
    >
      {c}
    </Link>
  ),
  link8: (c: ReactNode) => (
    <Link href="/remote-pi" className="text-accent underline">
      {c}
    </Link>
  ),
  link9: (c: ReactNode) => (
    <Link href="/docs" className="text-accent underline">
      {c}
    </Link>
  ),
  a10: (c: ReactNode) => (
    <a
      className="text-accent underline"
      href={GITHUB_URL}
      target="_blank"
      rel="noopener noreferrer"
    >
      {c}
    </a>
  ),
  a11: (c: ReactNode) => (
    <a
      className="text-accent underline"
      href={RELAY_README_URL}
      target="_blank"
      rel="noopener noreferrer"
    >
      {c}
    </a>
  ),
  a12: (c: ReactNode) => (
    <a
      className="text-accent underline"
      href={ISSUES_URL}
      target="_blank"
      rel="noopener noreferrer"
    >
      {c}
    </a>
  ),
};

type Translate = Awaited<ReturnType<typeof getTranslations<"RemoteDocs">>>;

function buildToc(t: Translate): TocItem[] {
  return [
    { id: "quick-start", label: t("toc.quickStart") },
    { id: "what-it-does", label: t("toc.whatItDoes") },
    { id: "install", label: t("toc.install") },
    { id: "using-remote-pi", label: t.rich("toc.usingRemotePi", TAGS) },
    { id: "pairing", label: t("toc.pairing") },
    { id: "quick-actions", label: t("toc.quickActions") },
    { id: "agent-network", label: t("toc.agentNetwork") },
    { id: "daemon-mode", label: t("toc.daemonMode") },
    {
      id: "relay",
      label: t("toc.relay"),
      sub: [
        { id: "community-relay", label: t("toc.communityRelay") },
        { id: "self-host", label: t("toc.selfHost") },
        { id: "point-pi", label: t("toc.pointPi") },
      ],
    },
    { id: "protocol", label: t("toc.protocol") },
    {
      id: "commands",
      label: t("toc.commands"),
      sub: [
        { id: "commands-local", label: t("toc.commandsLocal") },
        { id: "commands-daemon", label: t("toc.commandsDaemon") },
        { id: "commands-cron", label: t("toc.commandsCron") },
      ],
    },
    { id: "config", label: t("toc.config") },
    {
      id: "troubleshooting",
      label: t("toc.troubleshooting"),
      sub: [
        { id: "footer-stuck", label: t("toc.footerStuck") },
        { id: "timeout-mobile", label: t("toc.timeoutMobile") },
        { id: "timeout-request", label: t("toc.timeoutRequest") },
        { id: "one-pi-per-cwd", label: t("toc.onePiPerCwd") },
      ],
    },
    { id: "links", label: t("toc.links") },
  ];
}

export default async function DocsPage({ params }: Props) {
  const { locale } = await params;
  setRequestLocale(locale);
  const t = await getTranslations({ locale, namespace: "RemoteDocs" });
  return (
    <div className="page">
      <div className="page-body">
        <div className="wrap">
          <header className="page-head reveal">
            <span className="eyebrow">{t("intro.span1")}</span>
            <h1>{t("intro.h11")}</h1>
            <div className="meta-line">
              <span>{t("intro.span2")}</span>
              <span>{t("intro.span3")}</span>
            </div>
            <p className="lede">{t.rich("intro.p1", TAGS)}</p>
          </header>

          <div className="docs-layout">
            <DocsToc items={buildToc(t)} />

            <article className="prose docs-article">
              {/* ── Pointers into the tutorials ─────────────────────────── */}

              <DocsSection id="quick-start" title={t("quickStart.title")}>
                <p>{t("quickStart.p1")}</p>
                <p>
                  →{" "}
                  <Link
                    href="/remote-pi/tutorials/getting-started"
                    className="text-accent underline"
                  >
                    {t("quickStart.link1")}
                  </Link>
                  .
                </p>
              </DocsSection>

              <DocsSection id="what-it-does" title={t("whatItDoes.title")}>
                <p>{t.rich("whatItDoes.p1", TAGS)}</p>
                <ul className="ml-6 list-disc space-y-2">
                  <li>{t.rich("whatItDoes.li1", TAGS)}</li>
                  <li>{t.rich("whatItDoes.li2", TAGS)}</li>
                  <li>{t.rich("whatItDoes.li3", TAGS)}</li>
                </ul>
              </DocsSection>

              <DocsSection id="install" title={t("install.title")}>
                <p>{t.rich("install.p1", TAGS)}</p>
                <p>{t.rich("install.p2", TAGS)}</p>
              </DocsSection>

              <DocsSection
                id="using-remote-pi"
                title={t("usingRemotePi.title")}
              >
                <p>{t.rich("usingRemotePi.p1", TAGS)}</p>
                <p>{t.rich("usingRemotePi.p2", TAGS)}</p>
              </DocsSection>

              <DocsSection id="pairing" title={t("pairing.title")}>
                <p>{t.rich("pairing.p1", TAGS)}</p>
                <p>
                  →{" "}
                  <Link
                    href="/remote-pi/tutorials/getting-started"
                    className="text-accent underline"
                  >
                    {t("pairing.link1")}
                  </Link>
                  .
                </p>
              </DocsSection>

              <DocsSection id="quick-actions" title={t("quickActions.title")}>
                <p>{t.rich("quickActions.p1", TAGS)}</p>
                <p>
                  →{" "}
                  <Link
                    href="/remote-pi/tutorials/getting-started"
                    className="text-accent underline"
                  >
                    {t("quickActions.link1")}
                  </Link>
                  .
                </p>
              </DocsSection>

              <DocsSection id="agent-network" title={t("agentNetwork.title")}>
                <p>{t.rich("agentNetwork.p1", TAGS)}</p>
                <ul className="ml-6 list-disc space-y-2">
                  <li>{t.rich("agentNetwork.li1", TAGS)}</li>
                  <li>{t.rich("agentNetwork.li2", TAGS)}</li>
                </ul>
              </DocsSection>

              <DocsSection id="daemon-mode" title={t("daemonMode.title")}>
                <p>{t.rich("daemonMode.p1", TAGS)}</p>
                <p>{t.rich("daemonMode.p2", TAGS)}</p>
              </DocsSection>

              {/* ── Reference ───────────────────────────────────────────────────── */}

              <DocsSection id="relay" title={t("relay.title")}>
                <p>{t.rich("relay.p1", TAGS)}</p>
                <p>{t.rich("relay.p2", TAGS)}</p>
                <p>{t("relay.p3")}</p>

                <DocsSubsection
                  id="community-relay"
                  title={t("relay_communityRelay.title")}
                >
                  <p>{t.rich("relay_communityRelay.p1", TAGS)}</p>
                  <p>{t("relay_communityRelay.p2")}</p>
                  <ul className="ml-6 list-disc space-y-2">
                    <li>{t("relay_communityRelay.li1")}</li>
                    <li>{t.rich("relay_communityRelay.li2", TAGS)}</li>
                    <li>{t.rich("relay_communityRelay.li3", TAGS)}</li>
                  </ul>
                </DocsSubsection>

                <DocsSubsection
                  id="self-host"
                  title={t("relay_selfHost.title")}
                >
                  <p>{t.rich("relay_selfHost.p1", TAGS)}</p>
                  <p>{t.rich("relay_selfHost.p2", TAGS)}</p>
                  <CodeBlock
                    code={`docker run -d \\
  --name remote-pi-relay \\
  -p 3000:3000 \\
  -v remote-pi-data:/data \\
  --restart unless-stopped \\
  jacobmoura7/remote-pi-relay`}
                    label={t("relay_selfHost.label1")}
                    language="bash"
                  />
                  <p>{t.rich("relay_selfHost.p3", TAGS)}</p>
                  <p>{t.rich("relay_selfHost.p4", TAGS)}</p>
                  <p>{t.rich("relay_selfHost.p5", TAGS)}</p>
                </DocsSubsection>

                <DocsSubsection id="point-pi" title={t("relay_pointPi.title")}>
                  <p>{t("relay_pointPi.p1")}</p>
                  <CodeBlock
                    code="/remote-pi set-relay https://relay.yourdomain.tld"
                    label={t("relay_pointPi.label1")}
                    language="text"
                  />
                  <p>{t.rich("relay_pointPi.p2", TAGS)}</p>
                  <p>{t.rich("relay_pointPi.p3", TAGS)}</p>
                  <ol className="ml-6 list-decimal space-y-2">
                    <li>{t.rich("relay_pointPi.li1", TAGS)}</li>
                    <li>
                      <InlineCode>~/.pi/remote/config.json</InlineCode>
                    </li>
                    <li>{t.rich("relay_pointPi.li2", TAGS)}</li>
                  </ol>
                  <p>{t("relay_pointPi.p4")}</p>
                  <CodeBlock
                    code="/remote-pi config"
                    label={t("relay_pointPi.label2")}
                    language="text"
                  />
                  <p>{t.rich("relay_pointPi.p5", TAGS)}</p>
                </DocsSubsection>
              </DocsSection>

              <DocsSection id="protocol" title={t("protocol.title")}>
                <p>{t.rich("protocol.p1", TAGS)}</p>
                <p>{t.rich("protocol.p2", TAGS)}</p>
              </DocsSection>

              <DocsSection id="commands" title={t("commands.title")}>
                <p>{t.rich("commands.p1", TAGS)}</p>

                <DocsSubsection
                  id="commands-local"
                  title={t("commands_commandsLocal.title")}
                >
                  <DocsTable
                    headers={[
                      t("commands_commandsLocal.th1"),
                      t("commands_commandsLocal.th2"),
                    ]}
                    rows={[
                      [
                        <InlineCode key="c">/remote-pi</InlineCode>,
                        t("commands_commandsLocal.td1"),
                      ],
                      [
                        <InlineCode key="c">/remote-pi setup</InlineCode>,
                        t("commands_commandsLocal.td2"),
                      ],
                      [
                        <InlineCode key="c">/remote-pi status</InlineCode>,
                        t("commands_commandsLocal.td3"),
                      ],
                      [
                        <InlineCode key="c">/remote-pi peers</InlineCode>,
                        t("commands_commandsLocal.td4"),
                      ],
                      [
                        <InlineCode key="c">/remote-pi stop</InlineCode>,
                        <>{t.rich("commands_commandsLocal.cell1", TAGS)}</>,
                      ],
                      [
                        <InlineCode key="c">
                          /remote-pi pair [--ttl &lt;seconds&gt;]
                        </InlineCode>,
                        t("commands_commandsLocal.td5"),
                      ],
                      [
                        <InlineCode key="c">/remote-pi devices</InlineCode>,
                        t("commands_commandsLocal.td6"),
                      ],
                      [
                        <InlineCode key="c">
                          /remote-pi revoke &lt;shortid&gt;
                        </InlineCode>,
                        t("commands_commandsLocal.td7"),
                      ],
                      [
                        <InlineCode key="c">
                          /remote-pi set-relay &lt;url&gt;
                        </InlineCode>,
                        t("commands_commandsLocal.td8"),
                      ],
                    ]}
                  />
                </DocsSubsection>

                <DocsSubsection
                  id="commands-daemon"
                  title={t("commands_commandsDaemon.title")}
                >
                  <p className="text-sm">
                    {t.rich("commands_commandsDaemon.p1", TAGS)}
                  </p>
                  <DocsTable
                    headers={[
                      t("commands_commandsDaemon.th1"),
                      t("commands_commandsDaemon.th2"),
                    ]}
                    rows={[
                      [
                        <InlineCode key="c">
                          /remote-pi create &lt;cwd&gt; [--name X]
                        </InlineCode>,
                        t("commands_commandsDaemon.td1"),
                      ],
                      [
                        <InlineCode key="c">
                          /remote-pi remove &lt;id&gt;
                        </InlineCode>,
                        t("commands_commandsDaemon.td2"),
                      ],
                      [
                        <InlineCode key="c">/remote-pi daemons</InlineCode>,
                        t("commands_commandsDaemon.td3"),
                      ],
                      [
                        <InlineCode key="c">
                          /remote-pi daemon start [&lt;id&gt;]
                        </InlineCode>,
                        t("commands_commandsDaemon.td4"),
                      ],
                      [
                        <InlineCode key="c">
                          /remote-pi daemon stop [&lt;id&gt;]
                        </InlineCode>,
                        <>{t.rich("commands_commandsDaemon.cell1", TAGS)}</>,
                      ],
                      [
                        <InlineCode key="c">
                          /remote-pi daemon restart [&lt;id&gt;]
                        </InlineCode>,
                        t("commands_commandsDaemon.td5"),
                      ],
                      [
                        <InlineCode key="c">
                          /remote-pi daemon status
                        </InlineCode>,
                        t("commands_commandsDaemon.td6"),
                      ],
                      [
                        <InlineCode key="c">
                          /remote-pi daemon send &lt;id&gt;
                          &quot;&lt;text&gt;&quot;
                        </InlineCode>,
                        t("commands_commandsDaemon.td7"),
                      ],
                      [
                        <InlineCode key="c">/remote-pi install</InlineCode>,
                        <>{t.rich("commands_commandsDaemon.cell2", TAGS)}</>,
                      ],
                      [
                        <InlineCode key="c">/remote-pi uninstall</InlineCode>,
                        <>{t.rich("commands_commandsDaemon.cell3", TAGS)}</>,
                      ],
                    ]}
                  />
                </DocsSubsection>

                <DocsSubsection
                  id="commands-cron"
                  title={t("commands_commandsCron.title")}
                >
                  <p className="text-sm">
                    {t.rich("commands_commandsCron.p1", TAGS)}
                  </p>
                  <DocsTable
                    headers={[
                      t("commands_commandsCron.th1"),
                      t("commands_commandsCron.th2"),
                    ]}
                    rows={[
                      [
                        <InlineCode key="c">
                          /remote-pi cron add &lt;id&gt;
                          &quot;&lt;expr&gt;&quot; &quot;&lt;prompt&gt;&quot;
                          [--tz Area/City] [--wake] [--no-skip-busy] [--catchup]
                        </InlineCode>,
                        t("commands_commandsCron.td1"),
                      ],
                      [
                        <InlineCode key="c">/remote-pi cron list</InlineCode>,
                        t("commands_commandsCron.td2"),
                      ],
                      [
                        <InlineCode key="c">
                          /remote-pi cron run &lt;jobId&gt;
                        </InlineCode>,
                        t("commands_commandsCron.td3"),
                      ],
                      [
                        <InlineCode key="c">
                          /remote-pi cron enable &lt;jobId&gt;
                        </InlineCode>,
                        t("commands_commandsCron.td4"),
                      ],
                      [
                        <InlineCode key="c">
                          /remote-pi cron disable &lt;jobId&gt;
                        </InlineCode>,
                        t("commands_commandsCron.td5"),
                      ],
                      [
                        <InlineCode key="c">
                          /remote-pi cron remove &lt;jobId&gt;
                        </InlineCode>,
                        t("commands_commandsCron.td6"),
                      ],
                      [
                        <InlineCode key="c">
                          /remote-pi cron log [&lt;jobId&gt;] [--tail N]
                        </InlineCode>,
                        <>{t("commands_commandsCron.cell1")}</>,
                      ],
                    ]}
                  />
                  <ul className="ml-6 list-disc space-y-2">
                    <li>{t.rich("commands_commandsCron.li1", TAGS)}</li>
                    <li>{t.rich("commands_commandsCron.li2", TAGS)}</li>
                    <li>{t.rich("commands_commandsCron.li3", TAGS)}</li>
                    <li>{t.rich("commands_commandsCron.li4", TAGS)}</li>
                  </ul>
                </DocsSubsection>
                <p>{t("commands.p2")}</p>
                <ul className="ml-6 list-disc space-y-2">
                  <li>{t.rich("commands.li1", TAGS)}</li>
                  <li>{t.rich("commands.li2", TAGS)}</li>
                  <li>{t.rich("commands.li3", TAGS)}</li>
                  <li>{t.rich("commands.li4", TAGS)}</li>
                </ul>
                <p>{t.rich("commands.p3", TAGS)}</p>
              </DocsSection>

              <DocsSection id="config" title={t("config.title")}>
                <DocsTable
                  headers={[t("config.th1"), t("config.th2"), t("config.th3")]}
                  rows={[
                    [
                      <InlineCode key="p">
                        &lt;cwd&gt;/.pi/remote-pi/config.json
                      </InlineCode>,
                      t("config.td1"),
                      <>
                        <InlineCode>agent_name</InlineCode>,{" "}
                        <InlineCode>auto_start_relay</InlineCode>
                      </>,
                    ],
                    [
                      <InlineCode key="p">~/.pi/remote/config.json</InlineCode>,
                      t("config.td2"),
                      <>{t.rich("config.cell1", TAGS)}</>,
                    ],
                    [
                      <InlineCode key="p">~/.pi/remote/peers.json</InlineCode>,
                      t("config.td3"),
                      t("config.td4"),
                    ],
                    [
                      <InlineCode key="p">
                        ~/.pi/remote/daemons.json
                      </InlineCode>,
                      t("config.td5"),
                      <>{t.rich("config.cell2", TAGS)}</>,
                    ],
                    [
                      <InlineCode key="p">
                        ~/.pi/remote/identity.json
                      </InlineCode>,
                      t("config.td6"),
                      <>{t.rich("config.cell3", TAGS)}</>,
                    ],
                    [
                      <InlineCode key="p">
                        ~/.pi/remote/sessions/local/
                      </InlineCode>,
                      t("config.td7"),
                      <>{t.rich("config.cell4", TAGS)}</>,
                    ],
                    [
                      <InlineCode key="p">
                        ~/.pi/remote/skills/agent-network/SKILL.md
                      </InlineCode>,
                      t("config.td8"),
                      t("config.td9"),
                    ],
                  ]}
                />
                <p>{t("config.p1")}</p>
                <CodeBlock
                  code="REMOTE_PI_RELAY=https://staging.example.tld pi"
                  label={t("config.label1")}
                  language="bash"
                />
                <p className="text-sm">{t.rich("config.p2", TAGS)}</p>
                <p className="text-sm">{t.rich("config.p3", TAGS)}</p>
                <CodeBlock
                  code={`REMOTE_PI_DIRECT_CONFIG='{"agent_name":"ci","auto_start_relay":true}' pi`}
                  label={t("config.label2")}
                  language="bash"
                />
              </DocsSection>

              <DocsSection
                id="troubleshooting"
                title={t("troubleshooting.title")}
              >
                <DocsSubsection
                  id="footer-stuck"
                  title={t("troubleshooting_footerStuck.title")}
                >
                  <p>{t.rich("troubleshooting_footerStuck.p1", TAGS)}</p>
                </DocsSubsection>
                <DocsSubsection
                  id="timeout-mobile"
                  title={t("troubleshooting_timeoutMobile.title")}
                >
                  <p>{t("troubleshooting_timeoutMobile.p1")}</p>
                </DocsSubsection>
                <DocsSubsection
                  id="timeout-request"
                  title={t("troubleshooting_timeoutRequest.title")}
                >
                  <p>{t.rich("troubleshooting_timeoutRequest.p1", TAGS)}</p>
                  <ul className="ml-6 list-disc space-y-2">
                    <li>
                      {t.rich("troubleshooting_timeoutRequest.li1", TAGS)}
                    </li>
                    <li>
                      {t.rich("troubleshooting_timeoutRequest.li2", TAGS)}
                    </li>
                    <li>
                      {t.rich("troubleshooting_timeoutRequest.li3", TAGS)}
                    </li>
                  </ul>
                  <p className="text-sm">
                    {t.rich("troubleshooting_timeoutRequest.p2", TAGS)}
                  </p>
                </DocsSubsection>
                <DocsSubsection
                  id="one-pi-per-cwd"
                  title={t("troubleshooting_onePiPerCwd.title")}
                >
                  <p>{t.rich("troubleshooting_onePiPerCwd.p1", TAGS)}</p>
                  <p>{t.rich("troubleshooting_onePiPerCwd.p2", TAGS)}</p>
                  <p>{t.rich("troubleshooting_onePiPerCwd.p3", TAGS)}</p>
                </DocsSubsection>
              </DocsSection>

              <DocsSection id="links" title={t("links.title")}>
                <ul className="ml-6 list-disc space-y-2">
                  <li>{t.rich("links.li1", TAGS)}</li>
                  <li>{t.rich("links.li2", TAGS)}</li>
                  <li>{t.rich("links.li3", TAGS)}</li>
                  <li>{t.rich("links.li4", TAGS)}</li>
                  <li>{t.rich("links.li5", TAGS)}</li>
                  <li>{t.rich("links.li6", TAGS)}</li>
                  <li>{t.rich("links.li7", TAGS)}</li>
                  <li>{t.rich("links.li8", TAGS)}</li>
                </ul>
                <p className="text-sm">{t("links.p1")}</p>
              </DocsSection>
            </article>
          </div>
        </div>
      </div>
      <RevealController />
    </div>
  );
}
