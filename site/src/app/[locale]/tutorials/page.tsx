import type { Metadata } from "next";
import { getTranslations } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import { localeAlternates } from "@/i18n/alternates";
import { IconArrow, IconStar } from "@/components/landing/icons";
import { RevealController } from "@/components/landing/reveal-controller";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ locale: string }>;
}): Promise<Metadata> {
  const { locale } = await params;
  const t = await getTranslations({ locale, namespace: "TutorialsIndex" });
  return {
    title: t("title"),
    description: t("metaDescription"),
    alternates: { languages: localeAlternates("/tutorials") },
  };
}

type StepKey =
  | "gettingStarted"
  | "meshLocal"
  | "meshRemote"
  | "daemon"
  | "cockpitLayouts"
  | "cockpitTeam"
  | "claudeMesh";

type Step = {
  key: StepKey;
  n?: string;
  star?: boolean;
  tag: string;
  href: string;
};

const STEPS: Step[] = [
  { key: "gettingStarted", n: "1", tag: "01 / 04", href: "/tutorials/getting-started" },
  { key: "meshLocal", n: "2", tag: "02 / 04", href: "/tutorials/mesh-local" },
  { key: "meshRemote", n: "3", tag: "03 / 04", href: "/tutorials/mesh-remote" },
  { key: "daemon", n: "4", tag: "04 / 04", href: "/tutorials/daemon" },
];

const EXTRAS: Step[] = [
  { key: "cockpitLayouts", star: true, tag: "extra", href: "/tutorials/cockpit-layouts" },
  { key: "cockpitTeam", star: true, tag: "extra", href: "/tutorials/cockpit-team" },
  { key: "claudeMesh", star: true, tag: "extra", href: "/tutorials/claude-mesh" },
];

type TutorialsIndexT = Awaited<ReturnType<typeof getTranslations<"TutorialsIndex">>>;

function StepCard({ s, t }: { s: Step; t: TutorialsIndexT }) {
  return (
    <Link className="step-card reveal" href={s.href}>
      <div className="sc-top">
        <span className="sc-num">{s.star ? <IconStar /> : s.n}</span>
        <span className="sc-tag">{s.tag}</span>
      </div>
      <h3>{t(`${s.key}Title`)}</h3>
      <p>{t(`${s.key}Desc`)}</p>
      <span className="sc-link">
        {t("openTutorial")} <IconArrow />
      </span>
    </Link>
  );
}

export default async function TutorialsIndexPage({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  const t = await getTranslations({ locale, namespace: "TutorialsIndex" });

  return (
    <div className="page">
      <div className="page-body">
        <div className="wrap">
          <header className="page-head reveal">
            <span className="eyebrow">{t("eyebrow")}</span>
            <h1>{t("h1")}</h1>
            <p className="lede">
              {t.rich("lede", {
                em: (chunks) => <em>{chunks}</em>,
                why: (chunks) => <Link href="/why">{chunks}</Link>,
                docs: (chunks) => <Link href="/docs">{chunks}</Link>,
              })}
            </p>
          </header>

          <div className="card-list">
            {STEPS.map((s) => (
              <StepCard key={s.href} s={s} t={t} />
            ))}
          </div>

          <div className="group-label reveal">{t("extras")}</div>
          <div className="card-list">
            {EXTRAS.map((s) => (
              <StepCard key={s.href} s={s} t={t} />
            ))}
          </div>
        </div>
      </div>
      <RevealController />
    </div>
  );
}
