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
  const t = await getTranslations({ locale, namespace: "TermsPage" });
  return {
    title: t("title"),
    description: t("metaDescription"),
    alternates: {
      languages: localeAlternates("/terms"),
    },
  };
}

export default async function TermsPage({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  const t = await getTranslations({ locale, namespace: "TermsPage" });
  const legal = await getTranslations({ locale, namespace: "LegalCommon" });
  const b = (chunks: React.ReactNode) => <strong className="text-fg">{chunks}</strong>;
  const link = (chunks: React.ReactNode) => (
    <a className="text-accent underline" href={`mailto:${CONTACT_EMAIL}`}>
      {chunks}
    </a>
  );
  const code = (chunks: React.ReactNode) => (
    <code className="rounded bg-surface px-1.5 py-0.5 font-mono text-xs text-fg">{chunks}</code>
  );

  return (
    <LegalShell
      title={t("title")}
      lastUpdated={legal("lastUpdated", { date: "2026-05-22" })}
      subtitle={<p>{t.rich("subtitle", { b })}</p>}
    >
      <LegalSection id="acceptance" number={1} title={t("s1Title")}>
        <p>{t("s1P1")}</p>
        <p>{t("s1P2")}</p>
      </LegalSection>

      <LegalSection id="account-pairing" number={2} title={t("s2Title")}>
        <p>{t("s2P1")}</p>
        <p>{t("s2P2")}</p>
        <p>{t("s2P3")}</p>
      </LegalSection>

      <LegalSection id="features" number={3} title={t("s3Title")}>
        <p>{t("s3P1")}</p>
        <ul className="ml-6 list-disc space-y-2">
          <li>{t("s3Li1")}</li>
          <li>{t("s3Li2")}</li>
          <li>{t("s3Li3")}</li>
        </ul>
        <p>{t("s3P2")}</p>
      </LegalSection>

      <LegalSection id="user-content" number={4} title={t("s4Title")}>
        <p>{t("s4P1")}</p>
        <p>{t.rich("s4P2", { b })}</p>
        <p>{t("s4P3")}</p>
      </LegalSection>

      <LegalSection id="prohibited" number={5} title={t("s5Title")}>
        <p>{t("s5P1")}</p>
        <ul className="ml-6 list-disc space-y-2">
          <li>{t("s5Li1")}</li>
          <li>{t("s5Li2")}</li>
          <li>{t("s5Li3")}</li>
          <li>{t("s5Li4")}</li>
        </ul>
      </LegalSection>

      <LegalSection id="reporting" number={6} title={t("s6Title")}>
        <p>{t.rich("s6P1", { link, email: CONTACT_EMAIL })}</p>
      </LegalSection>

      <LegalSection id="ip" number={7} title={t("s7Title")}>
        <p>{t("s7P1")}</p>
        <p>{t("s7P2")}</p>
      </LegalSection>

      <LegalSection id="availability" number={8} title={t("s8Title")}>
        <p>{t("s8P1")}</p>
        <p>{t("s8P2")}</p>
      </LegalSection>

      <LegalSection id="liability" number={9} title={t("s9Title")}>
        <p>{t("s9P1")}</p>
        <p>{t("s9P2")}</p>
      </LegalSection>

      <LegalSection id="modifications" number={10} title={t("s10Title")}>
        <p>{t("s10P1")}</p>
      </LegalSection>

      <LegalSection id="termination" number={11} title={t("s11Title")}>
        <p>{t.rich("s11P1", { code })}</p>
        <p>{t("s11P2")}</p>
      </LegalSection>

      <LegalSection id="law" number={12} title={t("s12Title")}>
        <p>{t("s12P1")}</p>
      </LegalSection>

      <LegalSection id="contact" number={13} title={t("s13Title")}>
        <p>{t.rich("s13P1", { link, email: CONTACT_EMAIL })}</p>
      </LegalSection>
    </LegalShell>
  );
}
