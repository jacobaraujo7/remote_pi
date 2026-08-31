import type { Metadata } from "next";
import { hasLocale, NextIntlClientProvider } from "next-intl";
import { getTranslations, setRequestLocale } from "next-intl/server";
import { notFound } from "next/navigation";
import "../globals.css";
import { fontVariables } from "@/lib/fonts";
import { SiteHeader } from "@/components/header";
import { SiteFooter } from "@/components/footer";
import { routing } from "@/i18n/routing";
import { localeAlternates } from "@/i18n/alternates";

export function generateStaticParams() {
  return routing.locales.map((locale) => ({ locale }));
}

export async function generateMetadata({
  params,
}: {
  params: Promise<{ locale: string }>;
}): Promise<Metadata> {
  const { locale } = await params;
  const t = await getTranslations({ locale, namespace: "Metadata" });
  const title = t("titleDefault");
  const description = t("description");

  return {
    metadataBase: new URL("https://remote-pi.jacobmoura.work"),
    title: {
      default: title,
      template: t("titleTemplate"),
    },
    description,
    alternates: {
      languages: localeAlternates("/"),
    },
    applicationName: "Remote Pi",
    authors: [{ name: "Flutterando", url: "https://flutterando.com.br" }],
    keywords: [
      "Remote Pi",
      "coding agents",
      "Pi coding agent",
      "mobile agent control",
      "24/7 agent daemon",
      "agent mesh",
      "self-hostable relay",
    ],
    openGraph: {
      type: "website",
      url: "https://remote-pi.jacobmoura.work",
      title,
      description,
      siteName: "Remote Pi",
    },
    twitter: {
      card: "summary_large_image",
      title,
      description,
    },
  };
}

export default async function LocaleLayout({
  children,
  params,
}: {
  children: React.ReactNode;
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  if (!hasLocale(routing.locales, locale)) {
    notFound();
  }
  setRequestLocale(locale);
  const messages = (await import(`../../messages/${locale}.json`)).default;

  return (
    <html lang={locale} className={`${fontVariables} h-full antialiased`}>
      <body className="min-h-full flex flex-col bg-bg text-fg">
        <NextIntlClientProvider locale={locale} messages={messages}>
          <div className="app flex min-h-full flex-1 flex-col" id="top">
            <SiteHeader />
            <main className="flex-1">{children}</main>
            <SiteFooter />
          </div>
        </NextIntlClientProvider>
      </body>
    </html>
  );
}
