import type { Metadata } from "next";
import type { ReactNode } from "react";
import { getTranslations } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import { localeAlternates } from "@/i18n/alternates";
import { Callout } from "@/components/callout";
import { CodeBlock } from "@/components/code-block";
import { RevealController } from "@/components/landing/reveal-controller";
import {
  IconApple,
  IconWindows,
  IconLinux,
  IconAndroid,
  IconDownload,
} from "@/components/landing/icons";
import { ShaCopy } from "@/components/download/sha-copy";
import {
  loadCockpitManifest,
  artifactFileName,
  formatBytes,
  ARCH_LABEL,
  type CockpitArtifact,
  type CockpitManifest,
} from "@/lib/cockpit-release";
import { loadAppManifest } from "@/lib/app-release";

type DownloadT = Awaited<ReturnType<typeof getTranslations<"DownloadPage">>>;

export async function generateMetadata({
  params,
}: {
  params: Promise<{ locale: string }>;
}): Promise<Metadata> {
  const { locale } = await params;
  const t = await getTranslations({ locale, namespace: "DownloadPage" });
  return {
    title: t("title"),
    description: t("lede"),
    alternates: {
      languages: localeAlternates("/download"),
    },
  };
}

const GETTING_STARTED = "/tutorials/getting-started";

/* A download card reads only these fields, so both manifests feed it. */
type CardArtifact = {
  format: string;
  arch: string;
  url: string;
  sha256: string;
  size: number;
};

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

function DownloadCard({
  artifact,
  live,
  archLabel,
  downloadLabel,
  t,
}: {
  artifact: CardArtifact;
  live: boolean;
  archLabel: string;
  downloadLabel?: string;
  t: DownloadT;
}) {
  return (
    <div className="dl-card">
      <div className="dl-card-top">
        <span className="dl-fmt">.{artifact.format}</span>
        <span className="dl-size">{formatBytes(artifact.size)}</span>
      </div>
      <div className="dl-arch">{archLabel}</div>
      <div className="dl-file">{artifactFileName(artifact)}</div>
      {live ? (
        <a className="btn btn-primary dl-btn" href={artifact.url} download>
          <IconDownload /> {downloadLabel ?? t("download")}
        </a>
      ) : (
        <span
          className="btn dl-btn dl-btn-off"
          aria-disabled="true"
          title="Not published yet"
        >
          <IconDownload /> {t("unavailable")}
        </span>
      )}
      <ShaCopy sha256={artifact.sha256} />
    </div>
  );
}

/** Shared "not published" banner + release notes for a product band. */
function ReleaseNotes({
  version,
  notes,
  live,
  t,
}: {
  version: string;
  notes: string;
  live: boolean;
  t: DownloadT;
}) {
  return (
    <>
      {!live ? (
        <div className="reveal" style={{ marginTop: 24, maxWidth: 760 }}>
          <Callout variant="warning" title={t("notPublishedTitle")}>
            <p>{t("notPublishedBody")}</p>
          </Callout>
        </div>
      ) : null}
      {notes ? (
        <div className="reveal" style={{ marginTop: 20, maxWidth: 760 }}>
          <Callout title={t("whatsNew", { version })}>
            <p>{notes}</p>
          </Callout>
        </div>
      ) : null}
    </>
  );
}

type OsGroup = {
  id: string;
  name: string;
  icon: ReactNode;
  tagline: string;
  select: (m: CockpitManifest) => CockpitArtifact[];
  instructions: (m: CockpitManifest) => ReactNode;
};

function buildOsGroups(t: DownloadT): OsGroup[] {
  return [
    {
      id: "macos",
      name: t("macosName"),
      icon: <IconApple />,
      tagline: t("macosTagline"),
      select: (m) => m.artifacts.filter((a) => a.platform === "macos"),
      instructions: () => (
        <div className="dl-note">
          <ol>
            <li>{t.rich("macosStep1", { code: (chunks) => <code>{chunks}</code> })}</li>
            <li>{t.rich("macosStep2", { b: (chunks) => <strong>{chunks}</strong> })}</li>
            <li>{t("macosStep3")}</li>
          </ol>
          <p className="dl-note-foot">{t("macosFoot")}</p>
        </div>
      ),
    },
    {
      id: "windows",
      name: t("windowsName"),
      icon: <IconWindows />,
      tagline: t("windowsTagline"),
      select: (m) => m.artifacts.filter((a) => a.platform === "windows"),
      instructions: () => (
        <Callout variant="warning" title={t("windowsWarningTitle")}>
          <p>{t("windowsWarningBody1")}</p>
          <p>{t.rich("windowsWarningBody2", { b: (chunks) => <strong>{chunks}</strong> })}</p>
        </Callout>
      ),
    },
    {
      id: "linux",
      name: t("linuxName"),
      icon: <IconLinux />,
      tagline: t("linuxTagline"),
      select: (m) =>
        m.artifacts.filter((a) => a.platform === "linux").sort(linuxSort),
      instructions: (m) => (
        <div className="dl-note">
          <p>{t("linuxIntro")}</p>
          <CodeBlock
            label={t("linuxDebLabel")}
            code={`sudo dpkg -i remote-pi-cockpit_${m.version}_amd64.deb\nsudo apt-get install -f   # pull in any missing dependencies`}
          />
          <CodeBlock
            label={t("linuxRpmLabel")}
            code={`sudo dnf install ./remote-pi-cockpit-${m.version}.x86_64.rpm`}
          />
          <p className="dl-note-foot">
            {t.rich("linuxFoot", { code: (chunks) => <code>{chunks}</code> })}
          </p>
        </div>
      ),
    },
  ];
}

export default async function DownloadPage({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  const t = await getTranslations({ locale, namespace: "DownloadPage" });
  const [cockpit, app] = await Promise.all([
    loadCockpitManifest(),
    loadAppManifest(),
  ]);
  const apk = app.manifest.artifacts[0];
  const osGroups = buildOsGroups(t);

  return (
    <div className="page">
      <div className="page-body">
        <div className="wrap">
          <header className="page-head reveal" style={{ maxWidth: 760 }}>
            <span className="eyebrow">{t("eyebrow")}</span>
            <h1>{t("title")}</h1>
            <p className="lede">{t("lede")}</p>
          </header>

          {/* ---------- Cockpit (desktop) ---------- */}
          <section className="dl-product reveal" id="cockpit">
            <div className="section-head">
              <span className="eyebrow">{t("cockpitEyebrow")}</span>
              <h2>{t("cockpitTitle")}</h2>
              <p>{t("cockpitDesc")}</p>
            </div>
            <div className="dl-meta">
              <span>{t("version", { version: cockpit.manifest.version })}</span>
              <span>{t("released", { date: cockpit.manifest.date })}</span>
              <span>{t("signedNotarized")}</span>
            </div>

            <ReleaseNotes
              version={cockpit.manifest.version}
              notes={cockpit.manifest.notes}
              live={cockpit.live}
              t={t}
            />

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
                    </div>
                  </div>
                  <div className="dl-cards">
                    {artifacts.map((a) => (
                      <DownloadCard
                        key={`${a.format}-${a.arch}`}
                        artifact={a}
                        live={cockpit.live}
                        archLabel={ARCH_LABEL[a.arch]}
                        t={t}
                      />
                    ))}
                  </div>
                  <div className="dl-os-help">
                    {group.instructions(cockpit.manifest)}
                  </div>
                </section>
              );
            })}

            <div className="dl-foot">
              <p>
                {t.rich("cockpitFoot", {
                  code: (chunks) => <code>{chunks}</code>,
                  link: (chunks) => <Link href={GETTING_STARTED}>{chunks}</Link>,
                })}
              </p>
            </div>
          </section>

          {/* ---------- App (Android) ---------- */}
          <section className="dl-product reveal" id="android">
            <div className="section-head">
              <span className="eyebrow">{t("androidEyebrow")}</span>
              <h2>{t("androidTitle")}</h2>
              <p>{t("androidDesc")}</p>
            </div>
            <div className="dl-meta">
              <span>{t("version", { version: app.manifest.version })}</span>
              <span>{t("released", { date: app.manifest.date })}</span>
              <span>{t("androidDirect")}</span>
            </div>

            <ReleaseNotes
              version={app.manifest.version}
              notes={app.manifest.notes}
              live={app.live}
              t={t}
            />

            {apk ? (
              <div className="dl-os" id="android-build">
                <div className="dl-os-head">
                  <span className="dl-os-icon">
                    <IconAndroid />
                  </span>
                  <div className="dl-os-titles">
                    <h3>{t("androidName")}</h3>
                    <p>{t("androidTagline")}</p>
                  </div>
                </div>
                <div className="dl-cards dl-cards-solo">
                  <DownloadCard
                    artifact={apk}
                    live={app.live}
                    archLabel="Universal APK"
                    downloadLabel={t("androidDownloadLabel")}
                    t={t}
                  />
                </div>
                <div className="dl-os-help">
                  <div className="dl-note">
                    <ol>
                      <li>{t.rich("androidStep1", { code: (chunks) => <code>{chunks}</code> })}</li>
                      <li>{t("androidStep2")}</li>
                      <li>{t.rich("androidStep3", { b: (chunks) => <strong>{chunks}</strong> })}</li>
                      <li>{t.rich("androidStep4", { b: (chunks) => <strong>{chunks}</strong> })}</li>
                    </ol>
                    <p className="dl-note-foot">
                      {t.rich("androidFoot", {
                        link: (chunks) => (
                          <a
                            href="https://play.google.com/store/apps/details?id=work.jacobmoura.remotepi"
                            target="_blank"
                            rel="noopener noreferrer"
                          >
                            {chunks}
                          </a>
                        ),
                      })}
                    </p>
                  </div>
                </div>
              </div>
            ) : null}
          </section>
        </div>
      </div>
      <RevealController />
    </div>
  );
}
