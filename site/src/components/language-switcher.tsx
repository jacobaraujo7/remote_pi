"use client";

import { useLocale } from "next-intl";
import { useRouter, usePathname } from "@/i18n/navigation";
import { routing, type Locale } from "@/i18n/routing";

const LOCALE_META: Record<Locale, { label: string; flag: string }> = {
  en: { label: "EN", flag: "🇺🇸" },
  "pt-BR": { label: "PT-BR", flag: "🇧🇷" },
  es: { label: "ES", flag: "🇪🇸" },
};

export function LanguageSwitcher({ mobile = false }: { mobile?: boolean }) {
  const pathname = usePathname();
  const router = useRouter();
  const activeLocale = useLocale() as Locale;

  return (
    <span className={mobile ? "lang-select-wrap lang-select-wrap-mobile" : "lang-select-wrap"}>
      <span className="lang-select-flag" aria-hidden="true">
        {LOCALE_META[activeLocale].flag}
      </span>
      <select
        className="lang-select"
        aria-label="Language"
        value={activeLocale}
        onChange={(e) => {
          router.replace(pathname, { locale: e.target.value as Locale });
        }}
      >
        {routing.locales.map((loc) => (
          <option key={loc} value={loc}>
            {LOCALE_META[loc].label}
          </option>
        ))}
      </select>
    </span>
  );
}
