import { routing } from "@/i18n/routing";

const BASE_URL = "https://remote-pi.jacobmoura.work";

/** Absolute URL of `pathname` in `locale`. `en` stays unprefixed (as-needed). */
export function localeUrl(locale: string, pathname: string): string {
  const path = pathname === "/" ? "" : pathname;
  const prefix = locale === routing.defaultLocale ? "" : `/${locale}`;
  return `${BASE_URL}${prefix}${path}`;
}

/** hreflang map for a pathname without locale prefix ("/" for the home). */
export function localeAlternates(pathname: string): Record<string, string> {
  const languages: Record<string, string> = {};
  for (const locale of routing.locales) {
    languages[locale] = localeUrl(locale, pathname);
  }
  languages["x-default"] = localeUrl(routing.defaultLocale, pathname);
  return languages;
}

/** `alternates` metadata block: canonical for the current locale + hreflang. */
export function pageAlternates(locale: string, pathname: string) {
  return {
    canonical: localeUrl(locale, pathname),
    languages: localeAlternates(pathname),
  };
}
