"use client";

import { useEffect, useState, type ReactNode } from "react";
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

function buildOffer(
  detected: Detected,
  artifacts: CockpitArtifact[],
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
      title: "Download for your Mac",
      icon: <IconApple />,
      detail: `Universal build, Apple Silicon and Intel · ${formatBytes(dmg.size)} · macOS 12.0 or later`,
      primary: dmg,
      primaryLabel: "Download .dmg",
    };
  }

  if (detected.platform === "windows") {
    const exe = of("windows", "exe");
    if (!exe) return null;
    return {
      title: "Download for Windows",
      icon: <IconWindows />,
      detail: `64-bit installer · ${formatBytes(exe.size)} · Windows 10 or 11`,
      primary: exe,
      primaryLabel: "Download installer",
      note:
        detected.arch === "arm64"
          ? "Cockpit ships an x64 build only. It runs on Windows on ARM through emulation."
          : undefined,
    };
  }

  if (detected.platform === "android") {
    const apk = of("android", "apk", "arm64");
    if (!apk) return null;
    return {
      title: "Download for Android",
      icon: <IconAndroid />,
      detail: `arm64 phones and tablets · ${formatBytes(apk.size)}`,
      primary: apk,
      primaryLabel: "Download .apk",
      note: "The mobile app is a client: it connects over SSH to a host running cockpit-server.",
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
    title: "Download for Linux",
    icon: <IconLinux />,
    detail: `${arch === "arm64" ? "arm64 / aarch64" : "x86_64 / amd64"} · ${formatBytes(primary.size)} · GTK3, libmpv, libsecret and ALSA`,
    primary,
    primaryLabel: `Download .${primary.format}`,
    secondary,
    secondaryLabel: secondary ? `.${secondary.format} instead` : undefined,
  };
}

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
  const [offer, setOffer] = useState<Offer | null>(null);

  useEffect(() => {
    let cancelled = false;
    detectPlatform().then((detected) => {
      if (cancelled || !detected) return;
      setOffer(buildOffer(detected, artifacts));
    });
    return () => {
      cancelled = true;
    };
  }, [artifacts]);

  /* First paint (and every JS-less visit) lands here. */
  if (!offer) {
    return (
      <div className="dl-hero dl-hero-plain">
        <div className="dl-hero-copy">
          <span className="dl-hero-eyebrow">Version {version}</span>
          <h2>Choose your platform</h2>
          <p>Every build below comes with its size and its SHA-256.</p>
        </div>
        <nav className="dl-hero-links" aria-label="Jump to a platform">
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
            Linux host
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
          <span className="dl-hero-eyebrow">Version {version}</span>
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
            <IconDownload /> Not published yet
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
        Not your system? <a href="#platforms">See every build</a>, or put Cockpit
        on a <a href="#vps">Linux host</a>.
      </p>
    </div>
  );
}
