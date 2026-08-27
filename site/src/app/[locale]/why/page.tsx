import type { Metadata } from "next";
import { getTranslations } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import { localeAlternates } from "@/i18n/alternates";
import { Callout } from "@/components/callout";
import { IconDownload, IconGithub } from "@/components/landing/icons";
import { RevealController } from "@/components/landing/reveal-controller";

const GITHUB_URL = "https://github.com/jacobaraujo7/remote_pi";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ locale: string }>;
}): Promise<Metadata> {
  const { locale } = await params;
  const t = await getTranslations({ locale, namespace: "WhyPage" });
  return {
    title: t("title"),
    description: t("metaDescription"),
    alternates: {
      languages: localeAlternates("/why"),
    },
  };
}

export default async function WhyPage({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  const t = await getTranslations({ locale, namespace: "WhyPage" });
  const b = (chunks: React.ReactNode) => <strong>{chunks}</strong>;
  const i = (chunks: React.ReactNode) => <em>{chunks}</em>;

  const highlights = [
    { titleKey: "h1Title", descKey: "h1Desc" },
    { titleKey: "h2Title", descKey: "h2Desc" },
    { titleKey: "h3Title", descKey: "h3Desc" },
    { titleKey: "h4Title", descKey: "h4Desc" },
    { titleKey: "h5Title", descKey: "h5Desc" },
    { titleKey: "h6Title", descKey: "h6Desc" },
  ] as const;

  return (
    <div className="page">
      <div className="page-body">
        <div className="wrap">
          <header className="page-head reveal" style={{ maxWidth: 760 }}>
            <span className="eyebrow">{t("eyebrow")}</span>
            <h1>{t("h1")}</h1>
            <p className="lede">{t("lede")}</p>
          </header>

          <div className="section-head reveal" style={{ marginTop: 64 }}>
            <span className="eyebrow">{t("gotEyebrow")}</span>
            <h2>{t("gotTitle")}</h2>
          </div>
          <div
            className="reveal"
            style={{
              display: "grid",
              gridTemplateColumns: "repeat(auto-fit, minmax(248px, 1fr))",
              gap: 18,
              marginTop: 28,
            }}
          >
            {highlights.map((h) => (
              <div className="feat-card" key={h.titleKey}>
                <h3>{t(h.titleKey)}</h3>
                <p>{t(h.descKey)}</p>
              </div>
            ))}
          </div>

          <div className="section-head reveal" style={{ marginTop: 80 }}>
            <span className="eyebrow">{t("honestEyebrow")}</span>
            <h2>{t("honestTitle")}</h2>
          </div>
          <div
            className="compare reveal"
            style={{ maxWidth: 760, marginTop: 28 }}
          >
            <p className="sub">{t.rich("honestP1", { b })}</p>
            <p>{t("honestP2")}</p>
            <Callout title={t("choiceTitle")}>{t("choiceBody")}</Callout>
            <p style={{ fontSize: 14 }}>{t.rich("scopeNote", { i })}</p>
          </div>

          <div
            className="reveal"
            style={{
              textAlign: "center",
              maxWidth: 680,
              margin: "96px auto 0",
              paddingBottom: 24,
            }}
          >
            <span className="eyebrow">{t("getStartedEyebrow")}</span>
            <h2
              style={{
                fontFamily: "var(--ff-display)",
                fontWeight: 600,
                color: "var(--ink)",
                fontSize: "clamp(28px, 4vw, 44px)",
                letterSpacing: "-0.02em",
                lineHeight: 1.05,
                margin: "14px 0 0",
              }}
            >
              {t("getStartedTitle")}
            </h2>
            <p
              style={{
                color: "var(--ink-soft)",
                fontSize: 17,
                margin: "16px auto 0",
                maxWidth: 520,
              }}
            >
              {t("getStartedSub")}
            </p>
            <div
              style={{
                display: "flex",
                gap: 14,
                justifyContent: "center",
                flexWrap: "wrap",
                marginTop: 28,
              }}
            >
              <Link className="btn btn-primary" href="/#install">
                <IconDownload /> {t("install")}
              </Link>
              <Link className="btn btn-ghost" href="/tutorials/daemon">
                {t("daemonHowTo")}
              </Link>
              <a
                className="btn btn-ghost"
                href={GITHUB_URL}
                target="_blank"
                rel="noopener noreferrer"
              >
                <IconGithub /> {t("github")}
              </a>
            </div>
          </div>
        </div>
      </div>
      <RevealController />
    </div>
  );
}
