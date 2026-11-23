"use client";

import { useEffect, useMemo, useState, type ReactNode } from "react";
import { useTranslations } from "next-intl";
import {
  IconApple,
  IconWindows,
  IconLinux,
  IconAndroid,
  IconDownload,
} from "@/components/landing/icons";
import {
  artifactFileName,
  formatBytes,
  type CockpitArtifact,
} from "@/lib/cockpit-release";
import {
  detectPlatform,
  type Detected,
} from "@/components/download/detect-platform";

/* ===========================================================
   "Download for your Mac" hero.

   Progressive enhancement, on purpose: the server already renders every
   artifact further down the page, so this component starts in a neutral
   state (a list of anchors) and only promotes one build after the browser
   tells us what it is. No JavaScript, a locked-down browser or an
   unrecognized platform all end at that same neutral state, never at an
   empty or wrong CTA.
   =========================================================== */

/** What the hero offers once a platform is known. */
type Offer = {
  title: string;
  icon: ReactNode;
  detail: string;
  primary: CockpitArtifact;
  primaryLabel: string;
  /** Second format for the same machine (Linux ships both .deb and .rpm). */
  secondary?: CockpitArtifact;
  secondaryLabel?: string;
  /** Shown under the buttons when the machine needs a caveat. */
  note?: string;
};

type Translate = ReturnType<typeof useTranslations<"DownloadWidgets.picker">>;

function buildOffer(
  detected: Detected,
  artifacts: CockpitArtifact[],
  t: Translate,
): Offer | null {
  const of = (
    platform: string,
    format: string,
    arch?: string,
  ): CockpitArtifact | undefined =>
    artifacts.find(
      (a) =>
        a.platform === platform &&
        a.format === format &&
        (arch ? a.arch === arch : true),
    );

  if (detected.platform === "macos") {
    const dmg = of("macos", "dmg");
    if (!dmg) return null;
    return {
      title: t("macTitle"),
      icon: <IconApple />,
      detail: t("macDetail", { size: formatBytes(dmg.size) }),
      primary: dmg,
      primaryLabel: t("macPrimary"),
    };
  }

  if (detected.platform === "windows") {
    const exe = of("windows", "exe");
    if (!exe) return null;
    return {
      title: t("winTitle"),
      icon: <IconWindows />,
      detail: t("winDetail", { size: formatBytes(exe.size) }),
      primary: exe,
      primaryLabel: t("winPrimary"),
      note: detected.arch === "arm64" ? t("winArmNote") : undefined,
    };
  }

  if (detected.platform === "android") {
    const apk = of("android", "apk", "arm64");
    if (!apk) return null;
    return {
      title: t("androidTitle"),
      icon: <IconAndroid />,
      detail: t("androidDetail", { size: formatBytes(apk.size) }),
      primary: apk,
      primaryLabel: t("androidPrimary"),
      note: t("androidNote"),
    };
  }

  /* Linux: the architecture is worth detecting, the packaging format is not
     (nothing in the browser knows whether this machine wants deb or rpm), so
     both are offered for the detected arch. */
  const arch = detected.arch ?? "x64";
  const deb = of("linux", "deb", arch);
  const rpm = of("linux", "rpm", arch);
  if (!deb && !rpm) return null;
  const primary = deb ?? rpm!;
  const secondary = deb && rpm ? rpm : undefined;
  return {
    title: t("linuxTitle"),
    icon: <IconLinux />,
    detail: t("linuxDetail", {
      arch: arch === "arm64" ? "arm64 / aarch64" : "x86_64 / amd64",
      size: formatBytes(primary.size),
    }),
    primary,
    primaryLabel: t("linuxPrimary", { format: primary.format }),
    secondary,
    secondaryLabel: secondary
      ? t("linuxSecondary", { format: secondary.format })
      : undefined,
  };
}

/* Platform names are proper nouns: not translated. */
const FALLBACK_LINKS = [
  { href: "#macos", label: "macOS", icon: <IconApple /> },
  { href: "#windows", label: "Windows", icon: <IconWindows /> },
  { href: "#linux", label: "Linux", icon: <IconLinux /> },
  { href: "#android", label: "Android", icon: <IconAndroid /> },
];

export function PlatformPicker({
  artifacts,
  live,
  version,
}: {
  artifacts: CockpitArtifact[];
  live: boolean;
  version: string;
}) {
  const t = useTranslations("DownloadWidgets.picker");
  const [detected, setDetected] = useState<Detected | null>(null);

  useEffect(() => {
    let cancelled = false;
    detectPlatform().then((result) => {
      if (cancelled || !result) return;
      setDetected(result);
    });
    return () => {
      cancelled = true;
    };
  }, []);

  const offer = useMemo(
    () => (detected ? buildOffer(detected, artifacts, t) : null),
    [detected, artifacts, t],
  );

  /* First paint (and every JS-less visit) lands here. */
  if (!offer) {
    return (
      <div className="dl-hero dl-hero-plain">
        <div className="dl-hero-copy">
          <span className="dl-hero-eyebrow">{t("version", { version })}</span>
          <h2>{t("choose")}</h2>
          <p>{t("chooseLede")}</p>
        </div>
        <nav className="dl-hero-links" aria-label={t("jumpAria")}>
          {FALLBACK_LINKS.map((l) => (
            <a className="dl-hero-link" href={l.href} key={l.href}>
              <span className="dl-hero-link-icon">{l.icon}</span>
              {l.label}
            </a>
          ))}
          <a className="dl-hero-link" href="#vps">
            <span className="dl-hero-link-icon">
              <IconLinux />
            </span>
            {t("linuxHost")}
          </a>
        </nav>
      </div>
    );
  }

  return (
    <div className="dl-hero">
      <div className="dl-hero-main">
        <span className="dl-hero-icon">{offer.icon}</span>
        <div className="dl-hero-copy">
          <span className="dl-hero-eyebrow">{t("version", { version })}</span>
          <h2>{offer.title}</h2>
          <p>{offer.detail}</p>
        </div>
      </div>
      <div className="dl-hero-actions">
        {live ? (
          <a className="btn btn-primary" href={offer.primary.url} download>
            <IconDownload /> {offer.primaryLabel}
          </a>
        ) : (
          <span className="btn dl-btn-off" aria-disabled="true">
            <IconDownload /> {t("notPublished")}
          </span>
        )}
        {offer.secondary && live ? (
          <a className="btn btn-ghost" href={offer.secondary.url} download>
            {offer.secondaryLabel}
          </a>
        ) : null}
      </div>
      <p className="dl-hero-file">{artifactFileName(offer.primary)}</p>
      {offer.note ? <p className="dl-hero-note">{offer.note}</p> : null}
      <p className="dl-hero-alt">
        {t.rich("notYours", {
          all: (c) => <a href="#platforms">{c}</a>,
          host: (c) => <a href="#vps">{c}</a>,
        })}
      </p>
    </div>
  );
}
