import type { Metadata } from "next";
import { getTranslations } from "next-intl/server";
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
import { localeAlternates } from "@/i18n/alternates";

const GITHUB_URL = "https://github.com/jacobaraujo7/remote_pi";
const PI_URL = "https://github.com/earendil-works/pi";
const RELAY_README_URL =
  "https://github.com/jacobaraujo7/remote_pi/blob/main/relay/README.md";
const ISSUES_URL = "https://github.com/jacobaraujo7/remote_pi/issues";
const PROTOCOL_URL = `${GITHUB_URL}/blob/main/PROTOCOL.md`;

type DocsT = Awaited<ReturnType<typeof getTranslations<"DocsPage">>>;

export async function generateMetadata({
  params,
}: {
  params: Promise<{ locale: string }>;
}): Promise<Metadata> {
  const { locale } = await params;
  const t = await getTranslations({ locale, namespace: "DocsPage" });
  return {
    title: t("title"),
    description: t("metaDescription"),
    alternates: { languages: localeAlternates("/docs") },
  };
}

function buildDocsToc(t: DocsT): TocItem[] {
  return [
    { id: "quick-start", label: t("tocQuickStart") },
    { id: "what-it-does", label: t("tocWhatItDoes") },
    { id: "install", label: t("tocInstall") },
    { id: "using-remote-pi", label: <>{t("tocUsingRemotePi")} <InlineCode>/remote-pi</InlineCode></> },
    { id: "pairing", label: t("tocPairing") },
    { id: "quick-actions", label: t("tocQuickActions") },
    { id: "agent-network", label: t("tocAgentNetwork") },
    { id: "daemon-mode", label: t("tocDaemonMode") },
    {
      id: "relay",
      label: t("tocRelay"),
      sub: [
        { id: "community-relay", label: t("tocCommunityRelay") },
        { id: "self-host", label: t("tocSelfHost") },
        { id: "point-pi", label: t("tocPointPi") },
      ],
    },
    { id: "protocol", label: t("tocProtocol") },
    {
      id: "commands",
      label: t("tocCommands"),
      sub: [
        { id: "commands-local", label: t("tocCommandsLocal") },
        { id: "commands-daemon", label: t("tocCommandsDaemon") },
        { id: "commands-cron", label: t("tocCommandsCron") },
      ],
    },
    { id: "config", label: t("tocConfig") },
    {
      id: "troubleshooting",
      label: t("tocTroubleshooting"),
      sub: [
        { id: "footer-stuck", label: t("tocFooterStuck") },
        { id: "timeout-mobile", label: t("tocTimeoutMobile") },
        { id: "timeout-request", label: t("tocTimeoutRequest") },
        { id: "one-pi-per-cwd", label: t("tocOnePiPerCwd") },
      ],
    },
    { id: "links", label: t("tocLinks") },
  ];
}

export default async function DocsPage({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  const t = await getTranslations({ locale, namespace: "DocsPage" });
  const b = (chunks: React.ReactNode) => <strong className="text-fg">{chunks}</strong>;
  const em = (chunks: React.ReactNode) => <em className="text-fg">{chunks}</em>;
  const code = (chunks: React.ReactNode) => <InlineCode>{chunks}</InlineCode>;
  const tutorialsLink = (chunks: React.ReactNode) => (
    <Link href="/tutorials" className="text-accent underline">{chunks}</Link>
  );
  const whyLink = (chunks: React.ReactNode) => (
    <Link href="/why" className="text-accent underline">{chunks}</Link>
  );
  const gettingStartedLink = (chunks: React.ReactNode) => (
    <Link href="/tutorials/getting-started" className="text-accent underline">{chunks}</Link>
  );
  const meshLocalLink = (chunks: React.ReactNode) => (
    <Link href="/tutorials/mesh-local" className="text-accent underline">{chunks}</Link>
  );
  const meshRemoteLink = (chunks: React.ReactNode) => (
    <Link href="/tutorials/mesh-remote" className="text-accent underline">{chunks}</Link>
  );
  const daemonTutorialLink = (chunks: React.ReactNode) => (
    <Link href="/tutorials/daemon" className="text-accent underline">{chunks}</Link>
  );
  const daemonAnchor = (chunks: React.ReactNode) => (
    <a href="#daemon-mode" className="text-accent underline">{chunks}</a>
  );
  const commandsAnchor = (chunks: React.ReactNode) => (
    <a href="#commands" className="text-accent underline">{chunks}</a>
  );
  const selfHostAnchor = (chunks: React.ReactNode) => (
    <a href="#self-host" className="text-accent underline">{chunks}</a>
  );
  const protocolAnchor = (chunks: React.ReactNode) => (
    <a href="#protocol" className="text-accent underline">{chunks}</a>
  );
  const protocolLink = (chunks: React.ReactNode) => (
    <a className="text-accent underline" href={PROTOCOL_URL} target="_blank" rel="noopener noreferrer">{chunks}</a>
  );
  const piLink = (chunks: React.ReactNode) => (
    <a className="text-accent underline" href={PI_URL} target="_blank" rel="noopener noreferrer">{chunks}</a>
  );
  const relayReadmeLink = (chunks: React.ReactNode) => (
    <a className="text-accent underline" href={`${RELAY_README_URL}#self-hosted-relay-recommended-for-privacy`} target="_blank" rel="noopener noreferrer">{chunks}</a>
  );
  const tailscaleLink = (chunks: React.ReactNode) => (
    <a className="text-accent underline" href="https://tailscale.com" target="_blank" rel="noopener noreferrer">{chunks}</a>
  );
  const wireguardLink = (chunks: React.ReactNode) => (
    <a className="text-accent underline" href="https://www.wireguard.com" target="_blank" rel="noopener noreferrer">{chunks}</a>
  );
  const daemonCronLink = (chunks: React.ReactNode) => (
    <Link href="/tutorials/daemon#cron" className="text-accent underline">{chunks}</Link>
  );

  return (
    <div className="page">
      <div className="page-body">
        <div className="wrap">
          <header className="page-head reveal">
            <span className="eyebrow">{t("eyebrow")}</span>
            <h1>{t("h1")}</h1>
            <div className="meta-line">
              <span>{t("lastUpdated")}</span>
              <span>{t("license")}</span>
            </div>
            <p className="lede">
              {t.rich("intro", {
                b,
                piLink,
                code,
                tutorialsLink,
                whyLink,
              })}
            </p>
          </header>

          <div className="docs-layout">
            <DocsToc items={buildDocsToc(t)} />

            <article className="prose docs-article">
              <DocsSection id="quick-start" title={t("s1Title")}>
                <p>{t("s1P1")}</p>
                <p>{t.rich("s1P2", { link: gettingStartedLink })}</p>
              </DocsSection>

              <DocsSection id="what-it-does" title={t("s2Title")}>
                <p>{t.rich("s2P1", { b })}</p>
                <ul className="ml-6 list-disc space-y-2">
                  <li>{t.rich("s2Li1", { link: meshLocalLink })}</li>
                  <li>{t.rich("s2Li2", { link: meshRemoteLink })}</li>
                  <li>{t.rich("s2Li3", { link: gettingStartedLink })}</li>
                </ul>
              </DocsSection>

              <DocsSection id="install" title={t("s3Title")}>
                <p>{t.rich("s3P1", { code })}</p>
                <p>{t.rich("s3P2", { link1: gettingStartedLink, link2: daemonAnchor })}</p>
              </DocsSection>

              <DocsSection id="using-remote-pi" title={t("s4Title")}>
                <p>{t.rich("s4P1", { code, link: commandsAnchor })}</p>
                <p>{t.rich("s4P2", { link: gettingStartedLink })}</p>
              </DocsSection>

              <DocsSection id="pairing" title={t("s5Title")}>
                <p>{t.rich("s5P1", { b, code, link: commandsAnchor })}</p>
                <p>{t.rich("s5P2", { link: gettingStartedLink })}</p>
              </DocsSection>

              <DocsSection id="quick-actions" title={t("s6Title")}>
                <p>{t.rich("s6P1", { b, em, link: protocolLink })}</p>
                <p>{t.rich("s6P2", { link: gettingStartedLink })}</p>
              </DocsSection>

              <DocsSection id="agent-network" title={t("s7Title")}>
                <p>{t.rich("s7P1", { code })}</p>
                <ul className="ml-6 list-disc space-y-2">
                  <li>{t.rich("s7Li1", { link: meshLocalLink })}</li>
                  <li>{t.rich("s7Li2", { link: meshRemoteLink })}</li>
                </ul>
              </DocsSection>

              <DocsSection id="daemon-mode" title={t("s8Title")}>
                <p>{t.rich("s8P1", { code, link: commandsAnchor })}</p>
                <p>{t.rich("s8P2", { em, link1: daemonTutorialLink, link2: whyLink })}</p>
              </DocsSection>

              <DocsSection id="relay" title={t("s9Title")}>
                <p>{t.rich("s9P1", { link: protocolAnchor })}</p>
                <p>{t.rich("s9P2", { b, code, link: protocolLink })}</p>
                <p>{t("s9P3")}</p>

                <DocsSubsection id="community-relay" title={t("s9Sub1Title")}>
                  <p>{t.rich("s9Sub1P1", { code })}</p>
                  <p>{t("s9Sub1P2")}</p>
                  <ul className="ml-6 list-disc space-y-2">
                    <li>{t("s9Sub1Li1")}</li>
                    <li>{t.rich("s9Sub1Li2", { b })}</li>
                    <li>{t.rich("s9Sub1Li3", { b })}</li>
                  </ul>
                </DocsSubsection>

                <DocsSubsection id="self-host" title={t("s9Sub2Title")}>
                  <p>{t.rich("s9Sub2P1", { tailscaleLink, wireguardLink, b })}</p>
                  <p>{t.rich("s9Sub2P2", { link: relayReadmeLink })}</p>
                  <CodeBlock
                    code={`docker run -d \\
  --name remote-pi-relay \\
  -p 3000:3000 \\
  -v remote-pi-data:/data \\
  --restart unless-stopped \\
  jacobmoura7/remote-pi-relay`}
                    label={t("s9Sub2CodeLabel")}
                    language="bash"
                  />
                  <p>{t.rich("s9Sub2P3", { code })}</p>
                  <p>{t.rich("s9Sub2P4", { code })}</p>
                  <p>{t.rich("s9Sub2P5", { code })}</p>
                </DocsSubsection>

                <DocsSubsection id="point-pi" title={t("s9Sub3Title")}>
                  <p>{t("s9Sub3P1")}</p>
                  <CodeBlock code="/remote-pi set-relay https://relay.yourdomain.tld" label={t("s9Sub3CodeLabel1")} language="text" />
                  <p>{t.rich("s9Sub3P2", { code })}</p>
                  <p>{t.rich("s9Sub3P3", { code })}</p>
                  <ol className="ml-6 list-decimal space-y-2">
                    <li>{t.rich("s9Sub3Ol1", { code })}</li>
                    <li>{t.rich("s9Sub3Ol2", { code })}</li>
                    <li>{t.rich("s9Sub3Ol3", { code })}</li>
                  </ol>
                  <p>{t("s9Sub3P4")}</p>
                  <CodeBlock code="/remote-pi config" label={t("s9Sub3CodeLabel2")} language="text" />
                  <p>{t.rich("s9Sub3P5", { code })}</p>
                </DocsSubsection>
              </DocsSection>

              <DocsSection id="protocol" title={t("s10Title")}>
                <p>{t.rich("s10P1", { link: protocolLink })}</p>
                <p>{t.rich("s10P2", { b, link: selfHostAnchor })}</p>
              </DocsSection>

              <DocsSection id="commands" title={t("s11Title")}>
                <p>{t.rich("s11P1", { code })}</p>

                <DocsSubsection id="commands-local" title={t("s11Sub1Title")}>
                  <DocsTable
                    headers={[t("tableCommand"), t("tableDescription")]}
                    rows={[
                      [<InlineCode key="c">/remote-pi</InlineCode>, t("s11Sub1Row1")],
                      [<InlineCode key="c">/remote-pi setup</InlineCode>, t("s11Sub1Row2")],
                      [<InlineCode key="c">/remote-pi status</InlineCode>, t("s11Sub1Row3")],
                      [<InlineCode key="c">/remote-pi peers</InlineCode>, t("s11Sub1Row4")],
                      [<InlineCode key="c">/remote-pi stop</InlineCode>, t.rich("s11Sub1Row5", { em })],
                      [<InlineCode key="c">/remote-pi pair [--ttl &lt;seconds&gt;]</InlineCode>, t("s11Sub1Row6")],
                      [<InlineCode key="c">/remote-pi devices</InlineCode>, t("s11Sub1Row7")],
                      [<InlineCode key="c">/remote-pi revoke &lt;shortid&gt;</InlineCode>, t("s11Sub1Row8")],
                      [<InlineCode key="c">/remote-pi set-relay &lt;url&gt;</InlineCode>, t("s11Sub1Row9")],
                    ]}
                  />
                </DocsSubsection>

                <DocsSubsection id="commands-daemon" title={t("s11Sub2Title")}>
                  <p className="text-sm">{t.rich("s11Sub2P1", { link1: daemonAnchor, link2: daemonTutorialLink })}</p>
                  <DocsTable
                    headers={[t("tableCommand"), t("tableDescription")]}
                    rows={[
                      [<InlineCode key="c">/remote-pi create &lt;cwd&gt; [--name X]</InlineCode>, t("s11Sub2Row1")],
                      [<InlineCode key="c">/remote-pi remove &lt;id&gt;</InlineCode>, t("s11Sub2Row2")],
                      [<InlineCode key="c">/remote-pi daemons</InlineCode>, t("s11Sub2Row3")],
                      [<InlineCode key="c">/remote-pi daemon start [&lt;id&gt;]</InlineCode>, t("s11Sub2Row4")],
                      [<InlineCode key="c">/remote-pi daemon stop [&lt;id&gt;]</InlineCode>, t.rich("s11Sub2Row5", { code })],
                      [<InlineCode key="c">/remote-pi daemon restart [&lt;id&gt;]</InlineCode>, t("s11Sub2Row6")],
                      [<InlineCode key="c">/remote-pi daemon status</InlineCode>, t("s11Sub2Row7")],
                      [<InlineCode key="c">/remote-pi daemon send &lt;id&gt; &quot;&lt;text&gt;&quot;</InlineCode>, t("s11Sub2Row8")],
                      [<InlineCode key="c">/remote-pi install</InlineCode>, t.rich("s11Sub2Row9", { code, b })],
                      [<InlineCode key="c">/remote-pi uninstall</InlineCode>, t.rich("s11Sub2Row10", { code, b })],
                    ]}
                  />
                </DocsSubsection>

                <DocsSubsection id="commands-cron" title={t("s11Sub3Title")}>
                  <p className="text-sm">{t.rich("s11Sub3P1", { b, code, link1: daemonAnchor, link2: daemonCronLink })}</p>
                  <DocsTable
                    headers={[t("tableCommand"), t("tableDescription")]}
                    rows={[
                      [<InlineCode key="c">/remote-pi cron add &lt;id&gt; &quot;&lt;expr&gt;&quot; &quot;&lt;prompt&gt;&quot; [--tz Area/City] [--wake] [--no-skip-busy] [--catchup]</InlineCode>, t("s11Sub3Row1")],
                      [<InlineCode key="c">/remote-pi cron list</InlineCode>, t("s11Sub3Row2")],
                      [<InlineCode key="c">/remote-pi cron run &lt;jobId&gt;</InlineCode>, t("s11Sub3Row3")],
                      [<InlineCode key="c">/remote-pi cron enable &lt;jobId&gt;</InlineCode>, t("s11Sub3Row4")],
                      [<InlineCode key="c">/remote-pi cron disable &lt;jobId&gt;</InlineCode>, t("s11Sub3Row5")],
                      [<InlineCode key="c">/remote-pi cron remove &lt;jobId&gt;</InlineCode>, t("s11Sub3Row6")],
                      [<InlineCode key="c">/remote-pi cron log [&lt;jobId&gt;] [--tail N]</InlineCode>, t("s11Sub3Row7")],
                    ]}
                  />
                  <ul className="ml-6 list-disc space-y-2">
                    <li>{t.rich("s11Sub3Li1", { b, code })}</li>
                    <li>{t.rich("s11Sub3Li2", { b, code })}</li>
                    <li>{t.rich("s11Sub3Li3", { b, code })}</li>
                    <li>{t.rich("s11Sub3Li4", { b, em, code })}</li>
                  </ul>
                </DocsSubsection>
                <p>{t("s11FooterP1")}</p>
                <ul className="ml-6 list-disc space-y-2">
                  <li>{t.rich("s11FooterLi1", { code })}</li>
                  <li>{t.rich("s11FooterLi2", { code })}</li>
                  <li>{t.rich("s11FooterLi3", { code })}</li>
                  <li>{t.rich("s11FooterLi4", { code })}</li>
                </ul>
                <p>{t.rich("s11FooterP2", { code })}</p>
              </DocsSection>

              <DocsSection id="config" title={t("s12Title")}>
                <DocsTable
                  headers={[t("tablePath"), t("tableScope"), t("tableWhatsInIt")]}
                  rows={[
                    [<InlineCode key="p">&lt;cwd&gt;/.pi/remote-pi/config.json</InlineCode>, t("s12ScopePerDirectory"), <><InlineCode>agent_name</InlineCode>, <InlineCode>auto_start_relay</InlineCode></>],
                    [<InlineCode key="p">~/.pi/remote/config.json</InlineCode>, t("s12ScopePerUser"), <><InlineCode>relay</InlineCode> URL</>],
                    [<InlineCode key="p">~/.pi/remote/peers.json</InlineCode>, t("s12ScopePerMachine"), t("s12Row3Desc")],
                    [<InlineCode key="p">~/.pi/remote/daemons.json</InlineCode>, t("s12ScopePerMachine"), t.rich("s12Row4Desc", { code })],
                    [<InlineCode key="p">~/.pi/remote/identity.json</InlineCode>, t("s12ScopePerMachine"), t.rich("s12Row5Desc", { code, link: protocolLink })],
                    [<InlineCode key="p">~/.pi/remote/sessions/local/</InlineCode>, t("s12ScopePerMachine"), t.rich("s12Row6Desc", { code })],
                    [<InlineCode key="p">~/.pi/remote/skills/agent-network/SKILL.md</InlineCode>, t("s12ScopePerUser"), t("s12Row7Desc")],
                  ]}
                />
                <p>{t("s12P1")}</p>
                <CodeBlock code="REMOTE_PI_RELAY=https://staging.example.tld pi" label={t("s12CodeLabel1")} language="bash" />
                <p className="text-sm">{t.rich("s12P2", { code })}</p>
                <p className="text-sm">{t.rich("s12P3", { code })}</p>
                <CodeBlock
                  code={`REMOTE_PI_DIRECT_CONFIG='{"agent_name":"ci","auto_start_relay":true}' pi`}
                  label={t("s12CodeLabel2")}
                  language="bash"
                />
              </DocsSection>

              <DocsSection id="troubleshooting" title={t("s13Title")}>
                <DocsSubsection id="footer-stuck" title={t("s13Sub1Title")}>
                  <p>{t.rich("s13Sub1P1", { em, code })}</p>
                </DocsSubsection>
                <DocsSubsection id="timeout-mobile" title={t("s13Sub2Title")}>
                  <p>{t("s13Sub2P1")}</p>
                </DocsSubsection>
                <DocsSubsection id="timeout-request" title={t("s13Sub3Title")}>
                  <p>{t.rich("s13Sub3P1", { code })}</p>
                  <ul className="ml-6 list-disc space-y-2">
                    <li>{t.rich("s13Sub3Li1", { b, code })}</li>
                    <li>{t.rich("s13Sub3Li2", { b, code })}</li>
                    <li>{t.rich("s13Sub3Li3", { b, code })}</li>
                  </ul>
                  <p className="text-sm">{t.rich("s13Sub3P2", { b, code })}</p>
                </DocsSubsection>
                <DocsSubsection id="one-pi-per-cwd" title={t("s13Sub4Title")}>
                  <p>{t.rich("s13Sub4P1", { b, code })}</p>
                  <p>{t.rich("s13Sub4P2", { b, code, link: meshLocalLink })}</p>
                  <p>{t.rich("s13Sub4P3", { em })}</p>
                </DocsSubsection>
              </DocsSection>

              <DocsSection id="links" title={t("s14Title")}>
                <ul className="ml-6 list-disc space-y-2">
                  <li>{t("s14Li1Label")} <Link href="/" className="text-accent underline">remote-pi.jacobmoura.work</Link></li>
                  <li>{t("s14Li2Label")} <Link href="/tutorials" className="text-accent underline">{t("s14Li2Text")}</Link></li>
                  <li>{t("s14Li3Label")} <Link href="/cockpit/docs" className="text-accent underline">{t("s14Li3Text")}</Link></li>
                  <li>{t("s14Li4Label")} <a className="text-accent underline" href={GITHUB_URL} target="_blank" rel="noopener noreferrer">github.com/jacobaraujo7/remote_pi</a></li>
                  <li>{t("s14Li5Label")} <a className="text-accent underline" href={PROTOCOL_URL} target="_blank" rel="noopener noreferrer">PROTOCOL.md</a></li>
                  <li>{t("s14Li6Label")} <a className="text-accent underline" href={PI_URL} target="_blank" rel="noopener noreferrer">github.com/earendil-works/pi</a></li>
                  <li>{t("s14Li7Label")} <a className="text-accent underline" href={RELAY_README_URL} target="_blank" rel="noopener noreferrer">relay/README.md</a></li>
                  <li>{t("s14Li8Label")} <a className="text-accent underline" href={ISSUES_URL} target="_blank" rel="noopener noreferrer">github.com/jacobaraujo7/remote_pi/issues</a></li>
                </ul>
                <p className="text-sm">{t("s14License")}</p>
              </DocsSection>
            </article>
          </div>
        </div>
      </div>
      <RevealController />
    </div>
  );
}
