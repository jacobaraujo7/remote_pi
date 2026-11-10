import type { Metadata } from "next";
import { hasLocale, NextIntlClientProvider } from "next-intl";
import { getMessages, getTranslations, setRequestLocale } from "next-intl/server";
import { notFound } from "next/navigation";
import "../globals.css";
import { fontVariables } from "@/lib/fonts";
import { SiteHeader } from "@/components/header";
import { SiteFooter } from "@/components/footer";
import { routing } from "@/i18n/routing";

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
    applicationName: "Remote Pi Cockpit",
    authors: [{ name: "Flutterando", url: "https://flutterando.com.br" }],
    keywords: [
      "Cockpit",
      "Remote Pi Cockpit",
      "coding agents",
      "multiplexed terminal",
      "Claude Code",
      "Codex CLI",
      "remote development over SSH",
      "agent IDE",
    ],
    openGraph: {
      type: "website",
      url: "https://remote-pi.jacobmoura.work",
      title,
      description,
      siteName: "Remote Pi Cockpit",
      locale: locale.replace("-", "_"),
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
  const messages = await getMessages();

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
