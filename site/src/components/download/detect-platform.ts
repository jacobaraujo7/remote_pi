/* ===========================================================
   Platform detection for the download hero.

   Pure and browser-only: it reads `navigator` and never touches React, so it
   can be exercised on its own. Returning null is a first-class answer and
   means "show the full list", which is what the page renders anyway.
   =========================================================== */

export type Detected = {
  /** Matches CockpitArtifact["platform"]. */
  platform: "macos" | "windows" | "linux" | "android";
  /** Undefined while the browser has not told us, or when it does not matter. */
  arch?: "x64" | "arm64";
};

/**
 * Read the platform from the browser. `userAgentData` is the reliable path
 * (Chromium); everything else falls back to sniffing the UA string, which is
 * good enough to pick a download and harmless when it fails, because failing
 * just means showing the full list.
 */
export async function detectPlatform(): Promise<Detected | null> {
  if (typeof navigator === "undefined") return null;

  type UADataValues = { architecture?: string; bitness?: string };
  type UAData = {
    platform?: string;
    mobile?: boolean;
    getHighEntropyValues?: (hints: string[]) => Promise<UADataValues>;
  };
  const uaData = (navigator as Navigator & { userAgentData?: UAData })
    .userAgentData;
  const ua = navigator.userAgent ?? "";
  const legacyPlatform =
    (navigator as Navigator & { platform?: string }).platform ?? "";

  /* iPadOS reports itself as a Mac with a touch screen. We ship no iOS build,
     so this must not resolve to the macOS .dmg. */
  const isIpad =
    /iPad|iPhone|iPod/.test(ua) ||
    (/Mac/.test(legacyPlatform) && (navigator.maxTouchPoints ?? 0) > 1);
  if (isIpad) return null;

  let platform: Detected["platform"] | null = null;
  const uaPlatform = (uaData?.platform ?? "").toLowerCase();

  if (uaPlatform) {
    if (uaPlatform.includes("mac")) platform = "macos";
    else if (uaPlatform.includes("windows")) platform = "windows";
    else if (uaPlatform.includes("android")) platform = "android";
    else if (uaPlatform.includes("linux") || uaPlatform.includes("chrome os"))
      platform = "linux";
  }
  if (!platform) {
    if (/Android/i.test(ua)) platform = "android";
    else if (/Win/i.test(ua) || /Win/i.test(legacyPlatform)) platform = "windows";
    else if (/Mac/i.test(ua) || /Mac/i.test(legacyPlatform)) platform = "macos";
    else if (/Linux|X11|CrOS/i.test(ua)) platform = "linux";
  }
  if (!platform) return null;

  /* Architecture only changes which file we offer on Linux and Android, and
     Android ships arm64 only, so a miss there costs nothing. */
  let arch: Detected["arch"];
  if (uaData?.getHighEntropyValues) {
    try {
      const high = await uaData.getHighEntropyValues(["architecture", "bitness"]);
      if (high.architecture === "arm") arch = "arm64";
      else if (high.architecture === "x86") arch = "x64";
    } catch {
      /* The browser refused the hint: fall through to the UA string. */
    }
  }
  if (!arch) {
    if (/aarch64|arm64/i.test(ua)) arch = "arm64";
    else if (/x86_64|x64|Win64|amd64/i.test(ua)) arch = "x64";
  }

  return { platform, arch };
}
