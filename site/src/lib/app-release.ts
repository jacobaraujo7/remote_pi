/* ===========================================================
   Remote Pi App (Android) — release manifest
   Mirror of src/lib/cockpit-release.ts for the mobile app (plan/44).
   Same `latest.json` schema as the cockpit (plan/43, step 4), but the
   app ships a single artifact: an Android APK (platform "android",
   arch "universal", format "apk"). Distribution is direct APK — no
   Play Store — so the URL points at the GitHub Release asset.

   The host (rp-s3) may not have the manifest yet, so the URL is
   configurable (NEXT_PUBLIC_APP_MANIFEST_URL) and the loader falls back
   to APP_MOCK_MANIFEST — same shape — whenever the fetch fails.
   =========================================================== */

export type AppPlatform = "android";
export type AppArch = "universal";
export type AppFormat = "apk";

/** One downloadable app build. Produced by app-release.yml (plan/44). */
export type AppArtifact = {
  platform: AppPlatform;
  arch: AppArch;
  format: AppFormat;
  url: string;
  sha256: string;
  size: number;
};

export type AppManifest = {
  version: string;
  date: string;
  notes: string;
  artifacts: AppArtifact[];
};

/**
 * Where the live app manifest lives. Set NEXT_PUBLIC_APP_MANIFEST_URL once
 * the host serves it; until then this default 404s and the page falls back
 * to APP_MOCK_MANIFEST.
 */
export const APP_MANIFEST_URL =
  process.env.NEXT_PUBLIC_APP_MANIFEST_URL ??
  "https://rp-s3.jacobmoura.work/downloads/app/latest.json";

/**
 * Stand-in manifest for development and whenever the live fetch fails. Same
 * structure and the single APK artifact the CI emits, with the GitHub Release
 * asset URL from the plan. Checksum/size are placeholders — shown as a preview,
 * not a live download.
 */
export const APP_MOCK_MANIFEST: AppManifest = {
  version: "1.1.0",
  date: "2026-06-12",
  notes:
    "First direct-download Android build. Pair your phone with a QR, drive your agents from anywhere, and follow live sessions on the go.",
  artifacts: [
    {
      platform: "android",
      arch: "universal",
      format: "apk",
      url: "https://github.com/jacobaraujo7/remote_pi/releases/download/app-v1.1.0/RemotePi.apk",
      sha256: "7a1b2c3d4e5f60718293a4b5c6d7e8f900112233445566778899aabbccddeeff",
      size: 53477376,
    },
  ],
};

export type AppManifestLoad = {
  manifest: AppManifest;
  /**
   * True when the data came from the live host manifest; false when we fell
   * back to the bundled mock (URL unset, fetch failed, or bad shape).
   */
  live: boolean;
};

/** Narrow an untrusted JSON payload to the contract before trusting it. */
function isAppManifest(d: unknown): d is AppManifest {
  if (!d || typeof d !== "object") return false;
  const m = d as Record<string, unknown>;
  if (
    typeof m.version !== "string" ||
    typeof m.date !== "string" ||
    typeof m.notes !== "string" ||
    !Array.isArray(m.artifacts)
  ) {
    return false;
  }
  return m.artifacts.every((raw) => {
    if (!raw || typeof raw !== "object") return false;
    const a = raw as Record<string, unknown>;
    return (
      typeof a.platform === "string" &&
      typeof a.arch === "string" &&
      typeof a.format === "string" &&
      typeof a.url === "string" &&
      typeof a.sha256 === "string" &&
      typeof a.size === "number"
    );
  });
}

/**
 * Load the app release manifest. Fetches the live host endpoint at request
 * time (no build-time caching — the manifest is published independently of
 * the site deploy, so a static snapshot would go stale or freeze the page in
 * "not published" state). On any failure (network, non-200, malformed)
 * returns the mock so the page degrades gracefully instead of crashing.
 */
export async function loadAppManifest(): Promise<AppManifestLoad> {
  try {
    const res = await fetch(APP_MANIFEST_URL, { cache: "no-store" });
    if (!res.ok) throw new Error(`manifest responded ${res.status}`);
    const data: unknown = await res.json();
    if (!isAppManifest(data)) throw new Error("manifest shape invalid");
    return { manifest: data, live: true };
  } catch {
    return { manifest: APP_MOCK_MANIFEST, live: false };
  }
}
