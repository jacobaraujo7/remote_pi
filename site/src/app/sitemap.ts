import type { MetadataRoute } from "next";
import { routing } from "@/i18n/routing";
import { localeAlternates } from "@/i18n/alternates";

const LOCALIZED_PATHS = [
  "/",
  "/download",
  "/privacy",
  "/terms",
  "/cockpit",
  "/why",
  "/docs",
  "/cockpit/docs",
  "/tutorials",
  "/tutorials/claude-mesh",
  "/tutorials/cockpit-layouts",
  "/tutorials/cockpit-team",
  "/tutorials/daemon",
  "/tutorials/getting-started",
  "/tutorials/mesh-local",
  "/tutorials/mesh-remote",
];

export default function sitemap(): MetadataRoute.Sitemap {
  return LOCALIZED_PATHS.flatMap((path) => {
    const languages = localeAlternates(path);
    return routing.locales.map((locale) => ({
      url: languages[locale],
      alternates: { languages },
    }));
  });
}
