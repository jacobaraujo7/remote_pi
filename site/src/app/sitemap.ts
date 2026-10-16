import type { MetadataRoute } from "next";
import { routing } from "@/i18n/routing";
import { localeAlternates } from "@/i18n/alternates";

/* Only pages that are translated into every locale are listed with alternates.
   Later waves of plan/70 append their routes here as they are localized. */
const LOCALIZED_PATHS = [
  "/",
  "/download",
  "/remote-pi",
  "/remote-pi/download",
  "/remote-pi/why",
  "/privacy",
  "/terms",
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
