import type { Metadata } from "next";
import type { ReactNode } from "react";
import { getTranslations, setRequestLocale } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import { pageAlternates } from "@/i18n/alternates";
import { Callout } from "@/components/callout";
import { CodeBlock } from "@/components/code-block";
import { RevealController } from "@/components/landing/reveal-controller";
import {
  IconApple,
  IconWindows,
  IconLinux,
  IconAndroid,
} from "@/components/landing/icons";
import {
  DownloadCard,
  ReleaseNotes,
} from "@/components/download/download-card";
import { PlatformPicker } from "@/components/download/platform-picker";
import {
  loadCockpitManifest,
  ARCH_LABEL,
  type CockpitArtifact,
  type CockpitManifest,
} from "@/lib/cockpit-release";
import { rich } from "@/lib/rich";

type Props = { params: Promise<{ locale: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { locale } = await params;
  const t = await getTranslations({ locale, namespace: "DownloadPage" });
  return {
    title: t("metaTitle"),
    description: t("metaDescription"),
    alternates: pageAlternates(locale, "/download"),
  };
}

const GITHUB_RELEASES =
  "https://github.com/jacobaraujo7/remote_pi/releases/tag/cockpit-v";
const INSTALL_SCRIPT_RAW =
  "https://raw.githubusercontent.com/jacobaraujo7/remote_pi/main/cockpit/install-server.sh";
const SHA256SUMS_URL =
  "https://rp-s3.jacobmoura.work/downloads/cockpit/SHA256SUMS";

/* Order Linux packages deb-then-rpm, x64-then-arm64 for a stable card grid. */
const LINUX_ORDER: Record<string, number> = {
  "deb:x64": 0,
  "deb:arm64": 1,
  "rpm:x64": 2,
  "rpm:arm64": 3,
};

function linuxSort(a: CockpitArtifact, b: CockpitArtifact): number {
  const ka = LINUX_ORDER[`${a.format}:${a.arch}`] ?? 99;
  const kb = LINUX_ORDER[`${b.format}:${b.arch}`] ?? 99;
  return ka - kb;
}

type OsGroup = {
  id: string;
  name: string;
  icon: ReactNode;
  tagline: string;
  select: (m: CockpitManifest) => CockpitArtifact[];
  instructions: (m: CockpitManifest) => ReactNode;
  /** Card label for an artifact, when the plain architecture name is not enough. */
  archLabel?: (a: CockpitArtifact) => string;
  /** Minimum system this build runs on, shown next to the cards. */
  requirements: string;
};

type Translate = Awaited<ReturnType<typeof getTranslations<"DownloadPage">>>;

function buildOsGroups(t: Translate): OsGroup[] {
  return [
    {
      id: "macos",
      name: "macOS",
      icon: <IconApple />,
      tagline: t("macos.tagline"),
      /* 12.0 is the deployment target in the Xcode project. The macOS appcast
         still advertises minimumSystemVersion 10.15.0, which is wrong and has a
         card of its own (k34), so this page does not read that value. */
      requirements: t("macos.requirements"),
      select: (m) => m.artifacts.filter((a) => a.platform === "macos"),
      archLabel: (a) =>
        a.arch === "universal" ? t("archUniversal") : ARCH_LABEL[a.arch],
      instructions: () => (
        <div className="dl-note">
          <ol>
            <li>{t.rich("macos.step1", rich)}</li>
            <li>{t.rich("macos.step2", rich)}</li>
            <li>{t("macos.step3")}</li>
          </ol>
          <p className="dl-note-foot">{t("macos.foot")}</p>
        </div>
      ),
    },
    {
      id: "windows",
      name: "Windows",
      icon: <IconWindows />,
      tagline: t("windows.tagline"),
      requirements: t("windows.requirements"),
      select: (m) => m.artifacts.filter((a) => a.platform === "windows"),
      instructions: () => (
        <Callout variant="warning" title={t("windows.calloutTitle")}>
          <p>{t("windows.p1")}</p>
          <p>{t.rich("windows.p2", rich)}</p>
        </Callout>
      ),
    },
    {
      id: "linux",
      name: "Linux",
      icon: <IconLinux />,
      tagline: t("linux.tagline"),
      requirements: t("linux.requirements"),
      select: (m) =>
        m.artifacts.filter((a) => a.platform === "linux").sort(linuxSort),
      instructions: (m) => (
        <div className="dl-note">
          <p>{t("linux.intro")}</p>
          <CodeBlock
            label={t("linux.debLabel")}
            code={`sudo dpkg -i remote-pi-cockpit_${m.version}_amd64.deb\nsudo apt-get install -f   # pull in any missing dependencies`}
          />
          <CodeBlock
            label={t("linux.rpmLabel")}
            code={`sudo dnf install ./remote-pi-cockpit-${m.version}.x86_64.rpm`}
          />
          <p className="dl-note-foot">{t.rich("linux.foot", rich)}</p>
          <Callout variant="warning" title={t("linux.calloutTitle")}>
            <p>{t("linux.calloutBody")}</p>
          </Callout>
        </div>
      ),
    },
    {
      id: "android",
      name: "Android",
      icon: <IconAndroid />,
      tagline: t("android.tagline"),
      requirements: t("android.requirements"),
      /* The release also ships a universal .aab: that is a Play Store upload, not
         something a person installs, so it stays out of the UI. */
      select: (m) =>
        m.artifacts.filter((a) => a.platform === "android" && a.format === "apk"),
      archLabel: () => t("android.archLabel"),
      instructions: () => (
        <div className="dl-note">
          <ol>
            <li>{t.rich("android.step1", rich)}</li>
            <li>{t("android.step2")}</li>
            <li>{t.rich("android.step3", rich)}</li>
            <li>{t.rich("android.step4", rich)}</li>
          </ol>
          <Callout title={t("android.calloutTitle")}>
            <p>
              {t.rich("android.calloutBody", {
                ...rich,
                vps: (chunks) => <a href="#vps">{chunks}</a>,
              })}
            </p>
          </Callout>
        </div>
      ),
    },
  ];
}

export default async function DownloadPage({ params }: Props) {
  const { locale } = await params;
  setRequestLocale(locale);
  const t = await getTranslations({ locale, namespace: "DownloadPage" });
  const cockpit = await loadCockpitManifest();
  const osGroups = buildOsGroups(t);
  const vpsLink = (chunks: ReactNode) => <a href="#vps">{chunks}</a>;
  const externalLink = (href: string) =>
    function ExternalLink(chunks: ReactNode) {
      return (
        <a href={href} target="_blank" rel="noopener noreferrer">
          {chunks}
        </a>
      );
    };

  return (
    <div className="page">
      <div className="page-body">
        <div className="wrap">
          <header className="page-head reveal" style={{ maxWidth: 760 }}>
            <span className="eyebrow">{t("head.eyebrow")}</span>
            <h1>{t("head.title")}</h1>
            <p className="lede">{t("head.lede")}</p>
          </header>

          <div className="reveal">
            <PlatformPicker
              artifacts={cockpit.manifest.artifacts}
              live={cockpit.live}
              version={cockpit.manifest.version}
            />
          </div>

          {/* ---------- Cockpit (desktop) ---------- */}
          <section className="dl-product reveal" id="cockpit">
            <div className="section-head">
              <span className="eyebrow">{t("product.eyebrow")}</span>
              <h2>{t("product.title")}</h2>
              <p>{t("product.lede")}</p>
            </div>
            <div className="dl-meta">
              <span>{t("product.version", { version: cockpit.manifest.version })}</span>
              <span>{t("product.released", { date: cockpit.manifest.date })}</span>
              <span>{t("product.signed")}</span>
            </div>

            <ReleaseNotes
              version={cockpit.manifest.version}
              notes={cockpit.manifest.notes}
              live={cockpit.live}
              releaseUrl={`${GITHUB_RELEASES}${cockpit.manifest.version}`}
            />

            <div id="platforms">
              {osGroups.map((group) => {
                const artifacts = group.select(cockpit.manifest);
                if (artifacts.length === 0) return null;
                return (
                  <section className="dl-os" key={group.id} id={group.id}>
                    <div className="dl-os-head">
                      <span className="dl-os-icon">{group.icon}</span>
                      <div className="dl-os-titles">
                        <h3>{group.name}</h3>
                        <p>{group.tagline}</p>
                        <p className="dl-req">
                          <span>{t("requires")}</span> {group.requirements}
                        </p>
                      </div>
                    </div>
                    <div className="dl-cards">
                      {artifacts.map((a) => (
                        <DownloadCard
                          key={`${a.format}-${a.arch}`}
                          artifact={a}
                          live={cockpit.live}
                          archLabel={
                            group.archLabel
                              ? group.archLabel(a)
                              : ARCH_LABEL[a.arch]
                          }
                        />
                      ))}
                    </div>
                    <div className="dl-os-help">
                      {group.instructions(cockpit.manifest)}
                    </div>
                  </section>
                );
              })}
            </div>

            {/* ---------- updates + checksums ---------- */}
            <section className="dl-os dl-os-bare" id="updates">
              <div className="dl-os-head">
                <div className="dl-os-titles">
                  <h3>{t("updates.title")}</h3>
                  <p>{t("updates.lede")}</p>
                </div>
              </div>
              <div className="dl-os-help">
                <div className="dl-note">
                  <p>{t.rich("updates.p1", rich)}</p>
                  <p>{t.rich("updates.p2", rich)}</p>
                  <p className="dl-note-foot">
                    {t.rich("updates.foot", { ...rich, vps: vpsLink })}
                  </p>
                </div>
              </div>
            </section>

            <section className="dl-os dl-os-bare" id="verify">
              <div className="dl-os-head">
                <div className="dl-os-titles">
                  <h3>{t("verify.title")}</h3>
                  <p>{t("verify.lede")}</p>
                </div>
              </div>
              <div className="dl-os-help">
                <div className="dl-note">
                  <CodeBlock
                    label="macOS"
                    prompt
                    code={`shasum -a 256 ~/Downloads/RemotePiCockpit-${cockpit.manifest.version}-macos-universal.dmg`}
                  />
                  <CodeBlock
                    label="Windows · PowerShell"
                    code={`Get-FileHash .\\RemotePiCockpit-Setup-${cockpit.manifest.version}-windows-x64.exe -Algorithm SHA256`}
                  />
                  <CodeBlock
                    label="Linux"
                    prompt
                    code={`sha256sum remote-pi-cockpit_${cockpit.manifest.version}_amd64.deb`}
                  />
                  <p className="dl-note-foot">
                    {t.rich("verify.foot", { sums: externalLink(SHA256SUMS_URL) })}
                  </p>
                </div>
              </div>
            </section>

            <div className="dl-foot">
              <p>
                {t.rich("foot", {
                  docs: (chunks) => <Link href="/docs">{chunks}</Link>,
                })}
              </p>
            </div>
          </section>

          {/* ---------- cockpit-server (Linux host / VPS) ---------- */}
          <section className="dl-product reveal" id="vps">
            <div className="section-head">
              <span className="eyebrow">{t("vps.eyebrow")}</span>
              <h2>{t("vps.title")}</h2>
              <p>{t("vps.lede")}</p>
            </div>
            <div className="dl-meta">
              <span>{t("vps.meta1")}</span>
              <span>{t("vps.meta2")}</span>
              <span>{t("vps.meta3")}</span>
            </div>

            <div className="dl-os" id="vps-install">
              <div className="dl-os-head">
                <span className="dl-os-icon">
                  <IconLinux />
                </span>
                <div className="dl-os-titles">
                  <h3>{t("vps.installTitle")}</h3>
                  <p>{t("vps.installLede")}</p>
                </div>
              </div>
              <div className="dl-os-help">
                <div className="dl-note">
                  <CodeBlock
                    label={t("vps.codeLabel")}
                    code={`curl -fsSL https://remote-pi.jacobmoura.work/cockpit-server.sh | bash`}
                  />
                  <p>{t.rich("vps.installBody", rich)}</p>
                  <CodeBlock
                    label={t("vps.variantsLabel")}
                    code={`# register a systemd --user unit so the server is up after a reboot
curl -fsSL https://remote-pi.jacobmoura.work/cockpit-server.sh | bash -s -- --service

# pin a version instead of taking the latest release
COCKPIT_VERSION=${cockpit.manifest.version} curl -fsSL https://remote-pi.jacobmoura.work/cockpit-server.sh | bash`}
                  />
                  <p className="dl-note-foot">
                    {t.rich("vps.installFoot", {
                      ...rich,
                      src: externalLink(INSTALL_SCRIPT_RAW),
                    })}
                  </p>
                </div>
              </div>
              <div className="dl-os-help">
                <Callout variant="warning" title={t("vps.versionsTitle")}>
                  <p>
                    {t.rich("vps.versionsBody", {
                      ...rich,
                      version: cockpit.manifest.version,
                    })}
                  </p>
                </Callout>
              </div>
            </div>

            <div className="dl-foot">
              <p>
                {t.rich("vps.foot", {
                  ...rich,
                  remote: (chunks) => <Link href="/docs#remote">{chunks}</Link>,
                })}
              </p>
            </div>
          </section>
        </div>
      </div>
      <RevealController />
    </div>
  );
}
