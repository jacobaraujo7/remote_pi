import type { Metadata } from "next";
import { getTranslations, setRequestLocale } from "next-intl/server";
import { pageAlternates, localeUrl } from "@/i18n/alternates";
import { Hero } from "@/components/landing/hero";
import { Install } from "@/components/landing/install";
import { Pillars, GetApp, Strip, GithubCTA } from "@/components/landing/sections";
import { RevealController } from "@/components/landing/reveal-controller";

type Props = { params: Promise<{ locale: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { locale } = await params;
  const t = await getTranslations({ locale, namespace: "RemotePiMeta" });
  const title = t("pageTitle");
  const description = t("pageDescription");

  return {
    title: { absolute: title },
    description,
    alternates: pageAlternates(locale, "/remote-pi"),
    openGraph: {
      type: "website",
      url: localeUrl(locale, "/remote-pi"),
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

export default async function Home({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  setRequestLocale(locale);
  return (
    <>
      <Hero />
      <Pillars />
      <Install />
      <GetApp />
      <Strip />
      <GithubCTA />
      <RevealController />
    </>
  );
}
