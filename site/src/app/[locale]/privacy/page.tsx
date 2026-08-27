import type { Metadata } from "next";
import { getTranslations } from "next-intl/server";
import { LegalShell, LegalSection } from "@/components/legal-shell";
import { localeAlternates } from "@/i18n/alternates";

const CONTACT_EMAIL = "jacob@flutterando.com.br";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ locale: string }>;
}): Promise<Metadata> {
  const { locale } = await params;
  const t = await getTranslations({ locale, namespace: "PrivacyPage" });
  return {
    title: t("title"),
    description: t("metaDescription"),
    alternates: {
      languages: localeAlternates("/privacy"),
    },
  };
}

export default async function PrivacyPage({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  const t = await getTranslations({ locale, namespace: "PrivacyPage" });
  const legal = await getTranslations({ locale, namespace: "LegalCommon" });
  const b = (chunks: React.ReactNode) => <strong className="text-fg">{chunks}</strong>;
  const link = (chunks: React.ReactNode) => (
    <a className="text-accent underline" href={`mailto:${CONTACT_EMAIL}`}>
      {chunks}
    </a>
  );
  const code = (chunks: React.ReactNode) => (
    <code className="rounded bg-surface px-1 py-0.5 font-mono text-xs text-fg">{chunks}</code>
  );

  return (
    <LegalShell
      title={t("title")}
      lastUpdated={legal("lastUpdated", { date: "2026-05-22" })}
      subtitle={<p>{t.rich("subtitle", { b, link, email: CONTACT_EMAIL })}</p>}
    >
      <LegalSection id="who" number={1} title={t("s1Title")}>
        <p>{t("s1P1")}</p>
        <p>{t.rich("s1P2", { link, email: CONTACT_EMAIL })}</p>
      </LegalSection>

      <LegalSection id="collect" number={2} title={t("s2Title")}>
        <h3 className="text-base font-semibold text-fg">{t("s2h1")}</h3>
        <p>{t("s2P1")}</p>
        <p>{t("s2P2")}</p>
        <h3 className="text-base font-semibold text-fg">{t("s2h2")}</h3>
        <p>{t("s2P3")}</p>
        <ul className="ml-6 list-disc space-y-2">
          <li>{t.rich("s2Li1", { b })}</li>
          <li>{t.rich("s2Li2", { b })}</li>
          <li>{t.rich("s2Li3", { b, code })}</li>
        </ul>
        <p>{t("s2P4")}</p>
        <h3 className="text-base font-semibold text-fg">{t("s2h3")}</h3>
        <ul className="ml-6 list-disc space-y-2">
          <li>{t("s2Li4")}</li>
          <li>{t("s2Li5")}</li>
          <li>{t("s2Li6")}</li>
          <li>{t("s2Li7")}</li>
          <li>{t("s2Li8")}</li>
        </ul>
      </LegalSection>

      <LegalSection id="use" number={3} title={t("s3Title")}>
        <p>{t("s3P1")}</p>
        <ul className="ml-6 list-disc space-y-2">
          <li>{t("s3Li1")}</li>
          <li>{t("s3Li2")}</li>
          <li>{t("s3Li3")}</li>
        </ul>
        <p>{t("s3P2")}</p>
      </LegalSection>

      <LegalSection id="legal-bases" number={4} title={t("s4Title")}>
        <p>{t("s4P1")}</p>
        <ul className="ml-6 list-disc space-y-2">
          <li>{t.rich("s4Li1", { b })}</li>
          <li>{t.rich("s4Li2", { b })}</li>
        </ul>
      </LegalSection>

      <LegalSection id="sharing" number={5} title={t("s5Title")}>
        <p>{t("s5P1")}</p>
        <p>{t("s5P2")}</p>
      </LegalSection>

      <LegalSection id="international" number={6} title={t("s6Title")}>
        <p>{t("s6P1")}</p>
      </LegalSection>

      <LegalSection id="retention" number={7} title={t("s7Title")}>
        <p>{t.rich("s7P1", { b })}</p>
        <p>{t("s7P2")}</p>
      </LegalSection>

      <LegalSection id="rights" number={8} title={t("s8Title")}>
        <p>{t("s8P1")}</p>
        <ul className="ml-6 list-disc space-y-2">
          <li>{t("s8Li1")}</li>
          <li>{t("s8Li2")}</li>
          <li>{t("s8Li3")}</li>
          <li>{t("s8Li4")}</li>
          <li>{t("s8Li5")}</li>
          <li>{t("s8Li6")}</li>
          <li>{t("s8Li7")}</li>
        </ul>
        <p>{t.rich("s8P2", { link, email: CONTACT_EMAIL })}</p>
      </LegalSection>

      <LegalSection id="security" number={9} title={t("s9Title")}>
        <p>{t("s9P1")}</p>
        <ul className="ml-6 list-disc space-y-2">
          <li>{t.rich("s9Li1", { b })}</li>
          <li>{t.rich("s9Li2", { b })}</li>
          <li>{t("s9Li3")}</li>
          <li>{t("s9Li4")}</li>
        </ul>
        <p>{t.rich("s9P2", { b })}</p>
        <p>{t.rich("s9P3", { b })}</p>
        <p>{t.rich("s9P4", { link, email: CONTACT_EMAIL })}</p>
      </LegalSection>

      <LegalSection id="minors" number={10} title={t("s10Title")}>
        <p>{t("s10P1")}</p>
      </LegalSection>

      <LegalSection id="cookies" number={11} title={t("s11Title")}>
        <p>{t("s11P1")}</p>
      </LegalSection>

      <LegalSection id="updates" number={12} title={t("s12Title")}>
        <p>{t("s12P1")}</p>
      </LegalSection>

      <LegalSection id="contact" number={13} title={t("s13Title")}>
        <p>{t.rich("s13P1", { link, email: CONTACT_EMAIL })}</p>
        <p>{t("s13P2")}</p>
      </LegalSection>
    </LegalShell>
  );
}
