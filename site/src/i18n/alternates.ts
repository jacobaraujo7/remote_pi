import { routing } from "@/i18n/routing";

const BASE_URL = "https://remote-pi.jacobmoura.work";

/**
 * hreflang alternates for a Wave A pathname (e.g. "/download", "/" for the
 * landing page). `en` stays unprefixed to match localePrefix: "as-needed".
 */
export function localeAlternates(pathname: string): Record<string, string> {
  const path = pathname === "/" ? "" : pathname;
  const languages: Record<string, string> = {};
  for (const locale of routing.locales) {
    const prefix = locale === routing.defaultLocale ? "" : `/${locale}`;
    languages[locale] = `${BASE_URL}${prefix}${path}`;
  }
  languages["x-default"] = `${BASE_URL}${path}`;
  return languages;
}
