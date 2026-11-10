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
    namespace: "RemoteTutorials.index",
  });
  return {
    title: t("meta.title"),
    description: t("meta.description"),
    alternates: pageAlternates(locale, "/remote-pi/tutorials"),
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
    namespace: "RemoteTutorials.index",
  });

  const steps: Step[] = [
    {
      n: "1",
      tag: "01 / 04",
      title: t("step1.title"),
      href: "/remote-pi/tutorials/getting-started",
      desc: t("step1.desc"),
    },
    {
      n: "2",
      tag: "02 / 04",
      title: t("step2.title"),
      href: "/remote-pi/tutorials/mesh-local",
      desc: t("step2.desc"),
    },
    {
      n: "3",
      tag: "03 / 04",
      title: t("step3.title"),
      href: "/remote-pi/tutorials/mesh-remote",
      desc: t("step3.desc"),
    },
    {
      n: "4",
      tag: "04 / 04",
      title: t("step4.title"),
      href: "/remote-pi/tutorials/daemon",
      desc: t("step4.desc"),
    },
  ];
  const extras: Step[] = [
    {
      star: true,
      tag: t("extraTag"),
      title: t("extra1.title"),
      href: "/remote-pi/tutorials/claude-mesh",
      desc: t("extra1.desc"),
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
                em: (c) => <em>{c}</em>,
                why: (c) => <Link href="/remote-pi/why">{c}</Link>,
                docs: (c) => <Link href="/remote-pi/docs">{c}</Link>,
                cockpit: (c) => <Link href="/tutorials">{c}</Link>,
              })}
            </p>
          </header>

          <div className="card-list">
            {steps.map((s) => (
              <StepCard key={s.href} s={s} openLabel={t("open")} />
            ))}
          </div>

          <div className="group-label reveal">{t("extras")}</div>
          <div className="card-list">
            {extras.map((s) => (
              <StepCard key={s.href} s={s} openLabel={t("open")} />
            ))}
          </div>
        </div>
      </div>
      <RevealController />
    </div>
  );
}
