/* ===========================================================
   Remote Pi Cockpit — release manifest
   The download page reads a `latest.json` published by the release CI
   (plan/43, step 3) to the VPS. The shape below is the CLOSED CONTRACT
   between that CI and this site (plan/43, step 4) — do not drift it on
   one side without the other.

   The VPS endpoint does not exist yet, so the manifest URL is
   configurable (NEXT_PUBLIC_COCKPIT_MANIFEST_URL) and the loader falls
   back to MOCK_MANIFEST — same shape — whenever the fetch fails. The page
   still renders, just flagged "not yet published".
   =========================================================== */

export type CockpitPlatform = "macos" | "windows" | "linux";
export type CockpitArch = "universal" | "x64" | "arm64";
export type CockpitFormat = "dmg" | "exe" | "deb" | "rpm";

/** One downloadable build. Every field is produced by cockpit-release.yml. */
export type CockpitArtifact = {
  platform: CockpitPlatform;
  arch: CockpitArch;
  format: CockpitFormat;
  url: string;
  sha256: string;
  size: number;
};

export type CockpitManifest = {
  version: string;
  date: string;
  notes: string;
  artifacts: CockpitArtifact[];
};

/**
 * Where the live manifest lives. Set NEXT_PUBLIC_COCKPIT_MANIFEST_URL once
 * the release pipeline publishes to the VPS; until then this default 404s
 * and the page falls back to MOCK_MANIFEST.
 */
export const MANIFEST_URL =
  process.env.NEXT_PUBLIC_COCKPIT_MANIFEST_URL ??
  "https://rp-s3.jacobmoura.work/downloads/cockpit/latest.json";

/**
 * Stand-in manifest used during development and whenever the live fetch
 * fails. Same structure and the same six artifacts the CI emits, with the
 * exact filenames from the plan's artifact matrix. Checksums/sizes are
 * placeholders — the page shows these as a preview, not a live download.
 */
export const MOCK_MANIFEST: CockpitManifest = {
  version: "1.0.0",
  date: "2026-06-12",
  notes:
    "First public Cockpit build. Pair from the desktop, watch live agent sessions, and manage 24/7 daemons and schedules.",
  artifacts: [
    {
      platform: "macos",
      arch: "universal",
      format: "dmg",
      url: "https://remote-pi.jacobmoura.work/downloads/cockpit/1.0.0/RemotePiCockpit-1.0.0-macos-universal.dmg",
      sha256: "9f1c2a7d4e6b8035c1d2e3f405162738a9bbccddeeff00112233445566778899",
      size: 89128960,
    },
    {
      platform: "windows",
      arch: "x64",
      format: "exe",
      url: "https://remote-pi.jacobmoura.work/downloads/cockpit/1.0.0/RemotePiCockpit-Setup-1.0.0-windows-x64.exe",
      sha256: "1a2b3c4d5e6f70819203a4b5c6d7e8f9001122334455667788990aabbccddeef",
      size: 44040192,
    },
    {
      platform: "linux",
      arch: "x64",
      format: "deb",
      url: "https://remote-pi.jacobmoura.work/downloads/cockpit/1.0.0/remote-pi-cockpit_1.0.0_amd64.deb",
      sha256: "c0ffee11223344556677889900aabbccddeeff00112233445566778899aabbcc",
      size: 39845888,
    },
    {
      platform: "linux",
      arch: "arm64",
      format: "deb",
      url: "https://remote-pi.jacobmoura.work/downloads/cockpit/1.0.0/remote-pi-cockpit_1.0.0_arm64.deb",
      sha256: "ba5eba11feedface0011223344556677889900aabbccddeeff0011223344aa55",
      size: 38797312,
    },
    {
      platform: "linux",
      arch: "x64",
      format: "rpm",
      url: "https://remote-pi.jacobmoura.work/downloads/cockpit/1.0.0/remote-pi-cockpit-1.0.0.x86_64.rpm",
      sha256: "d15ea5e0112233445566778899aabbccddeeff00998877665544332211000fff",
      size: 39845888,
    },
    {
      platform: "linux",
      arch: "arm64",
      format: "rpm",
      url: "https://remote-pi.jacobmoura.work/downloads/cockpit/1.0.0/remote-pi-cockpit-1.0.0.aarch64.rpm",
      sha256: "f00dcafe9988776655443322110000ffeeddccbbaa00112233445566778899ab",
      size: 38797312,
    },
  ],
};

export type ManifestLoad = {
  manifest: CockpitManifest;
  /**
   * True when the data came from the live VPS manifest; false when we fell
   * back to the bundled mock (URL unset, fetch failed, or bad shape).
   */
  live: boolean;
};

/** Narrow an untrusted JSON payload to the contract before trusting it. */
function isManifest(d: unknown): d is CockpitManifest {
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
 * Load the release manifest. Fetches the live VPS endpoint at request time
 * (no build-time caching — the manifest is published independently of the
 * site deploy, so a static snapshot would go stale or freeze the page in
 * "not published" state). On any failure (network, non-200, malformed)
 * returns the mock so the page degrades gracefully instead of crashing.
 */
export async function loadCockpitManifest(): Promise<ManifestLoad> {
  try {
    const res = await fetch(MANIFEST_URL, { cache: "no-store" });
    if (!res.ok) throw new Error(`manifest responded ${res.status}`);
    const data: unknown = await res.json();
    if (!isManifest(data)) throw new Error("manifest shape invalid");
    return { manifest: data, live: true };
  } catch {
    return { manifest: MOCK_MANIFEST, live: false };
  }
}

/**
 * Last path segment of an artifact URL, e.g. `remote-pi-cockpit_1.0.0_amd64.deb`.
 * Structurally typed so the app manifest (plan/44) reuses it without importing
 * cockpit's format/platform unions.
 */
export function artifactFileName(a: { url: string; format: string }): string {
  const seg = a.url.split("/").pop();
  return seg && seg.length > 0 ? seg : `cockpit.${a.format}`;
}

/** Human-readable file size from a byte count. */
export function formatBytes(bytes: number): string {
  if (!bytes || bytes <= 0) return "—";
  const mb = bytes / (1024 * 1024);
  if (mb >= 1024) return `${(mb / 1024).toFixed(1)} GB`;
  return `${mb.toFixed(1)} MB`;
}

/** Display label for an architecture, in the download card. */
export const ARCH_LABEL: Record<CockpitArch, string> = {
  universal: "Universal · Apple Silicon + Intel",
  x64: "x86_64 / amd64",
  arm64: "arm64 / aarch64",
};
