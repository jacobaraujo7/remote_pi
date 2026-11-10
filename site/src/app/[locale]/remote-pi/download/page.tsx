import type { Metadata } from "next";
import type { ReactNode } from "react";
import { getTranslations, setRequestLocale } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import { pageAlternates } from "@/i18n/alternates";
import { RevealController } from "@/components/landing/reveal-controller";
import { IconAndroid } from "@/components/landing/icons";
import {
  DownloadCard,
  ReleaseNotes,
} from "@/components/download/download-card";
import { loadAppManifest } from "@/lib/app-release";
import { rich } from "@/lib/rich";

type Props = { params: Promise<{ locale: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { locale } = await params;
  const t = await getTranslations({ locale, namespace: "RemotePiDownload" });
  return {
    title: t("metaTitle"),
    description: t("metaDescription"),
    alternates: pageAlternates(locale, "/remote-pi/download"),
  };
}

const PLAY_URL =
  "https://play.google.com/store/apps/details?id=work.jacobmoura.remotepi";
const APP_STORE_URL =
  "https://apps.apple.com/app/remote-pi-coding-agent/id6773499691";

export default async function RemotePiDownloadPage({ params }: Props) {
  const { locale } = await params;
  setRequestLocale(locale);
  const t = await getTranslations({ locale, namespace: "RemotePiDownload" });
  const app = await loadAppManifest();
  const apk = app.manifest.artifacts[0];

  const external = (href: string) =>
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

          <section className="dl-product reveal" id="android">
            <div className="section-head">
              <span className="eyebrow">{t("android.eyebrow")}</span>
              <h2>{t("android.title")}</h2>
              <p>{t("android.lede")}</p>
            </div>
            <div className="dl-meta">
              <span>{t("android.version", { version: app.manifest.version })}</span>
              <span>{t("android.released", { date: app.manifest.date })}</span>
              <span>{t("android.direct")}</span>
            </div>

            <ReleaseNotes
              version={app.manifest.version}
              notes={app.manifest.notes}
              live={app.live}
            />

            {apk ? (
              <div className="dl-os" id="android-build">
                <div className="dl-os-head">
                  <span className="dl-os-icon">
                    <IconAndroid />
                  </span>
                  <div className="dl-os-titles">
                    <h3>Android</h3>
                    <p>{t("android.tagline")}</p>
                  </div>
                </div>
                <div className="dl-cards dl-cards-solo">
                  <DownloadCard
                    artifact={apk}
                    live={app.live}
                    archLabel={t("android.archLabel")}
                    downloadLabel={t("android.downloadLabel")}
                  />
                </div>
                <div className="dl-os-help">
                  <div className="dl-note">
                    <ol>
                      <li>{t.rich("android.step1", rich)}</li>
                      <li>{t("android.step2")}</li>
                      <li>{t.rich("android.step3", rich)}</li>
                      <li>{t.rich("android.step4", rich)}</li>
                    </ol>
                    <p className="dl-note-foot">
                      {t.rich("android.foot", {
                        play: external(PLAY_URL),
                        appstore: external(APP_STORE_URL),
                      })}
                    </p>
                  </div>
                </div>
              </div>
            ) : null}

            <div className="dl-foot">
              <p>
                {t.rich("foot", {
                  ...rich,
                  guide: (chunks) => (
                    <Link href="/remote-pi/tutorials/getting-started">
                      {chunks}
                    </Link>
                  ),
                  cockpit: (chunks) => <Link href="/download">{chunks}</Link>,
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
