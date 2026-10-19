import type { Metadata } from "next";
import { getTranslations, setRequestLocale } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import { pageAlternates } from "@/i18n/alternates";
import { IconArrow, IconStar } from "@/components/landing/icons";
import { RevealController } from "@/components/landing/reveal-controller";

type Props = { params: Promise<{ locale: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { locale } = await params;
  const t = await getTranslations({
    locale,
    namespace: "CockpitTutorials.index",
  });
  return {
    title: t("meta.title"),
    description: t("meta.description"),
    alternates: pageAlternates(locale, "/tutorials"),
  };
}

type Step = {
  n?: string;
  star?: boolean;
  tag: string;
  title: string;
  href: string;
  desc: string;
};

function StepCard({ s, openLabel }: { s: Step; openLabel: string }) {
  return (
    <Link className="step-card reveal" href={s.href}>
      <div className="sc-top">
        <span className="sc-num">{s.star ? <IconStar /> : s.n}</span>
        <span className="sc-tag">{s.tag}</span>
      </div>
      <h3>{s.title}</h3>
      <p>{s.desc}</p>
      <span className="sc-link">
        {openLabel} <IconArrow />
      </span>
    </Link>
  );
}

export default async function TutorialsIndexPage({ params }: Props) {
  const { locale } = await params;
  setRequestLocale(locale);
  const t = await getTranslations({
    locale,
    namespace: "CockpitTutorials.index",
  });

  const steps: Step[] = [
    {
      n: "1",
      tag: "01 / 03",
      title: t("step1.title"),
      href: "/tutorials/cockpit-layouts",
      desc: t("step1.desc"),
    },
    {
      n: "2",
      tag: "02 / 03",
      title: t("step2.title"),
      href: "/tutorials/cockpit-team",
      desc: t("step2.desc"),
    },
    {
      n: "3",
      tag: "03 / 03",
      title: t("step3.title"),
      href: "/tutorials/cockpit-telemetry",
      desc: t("step3.desc"),
    },
  ];

  return (
    <div className="page">
      <div className="page-body">
        <div className="wrap">
          <header className="page-head reveal">
            <span className="eyebrow">{t("eyebrow")}</span>
            <h1>{t("h1")}</h1>
            <p className="lede">
              {t.rich("lede", {
                ref: (c) => <Link href="/docs">{c}</Link>,
                remote: (c) => <Link href="/remote-pi/tutorials">{c}</Link>,
              })}
            </p>
          </header>

          <div className="card-list">
            {steps.map((s) => (
              <StepCard key={s.href} s={s} openLabel={t("open")} />
            ))}
          </div>
        </div>
      </div>
      <RevealController />
    </div>
  );
}
