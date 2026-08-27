import { Fragment } from "react";
import { useTranslations } from "next-intl";
import { Link } from "@/i18n/navigation";
import {
  IconGateway,
  IconAlwaysOn,
  IconMesh,
  IconArrow,
  IconAndroid,
  IconPlay,
  IconApple,
  IconDownload,
  IconMic,
  IconImage,
  IconOpenSource,
  IconSelfHost,
  IconGithub,
  IconStar,
} from "@/components/landing/icons";
import type { ReactNode } from "react";

const GITHUB_URL = "https://github.com/jacobaraujo7/remote_pi";
const PROTOCOL_URL = `${GITHUB_URL}/blob/main/PROTOCOL.md`;

/* ---------------- Pillars ---------------- */
type Pillar = {
  icon: ReactNode;
  tag: string;
  title: string;
  proof: string;
  link: string;
  href: string;
};

function PillarLink({ href, label }: { href: string; label: string }) {
  const inner = (
    <>
      {label} <IconArrow />
    </>
  );
  if (href.startsWith("http")) {
    return (
      <a className="plink" href={href} target="_blank" rel="noopener noreferrer">
        {inner}
      </a>
    );
  }
  if (href.startsWith("#")) {
    return (
      <a className="plink" href={href}>
        {inner}
      </a>
    );
  }
  return (
    <Link className="plink" href={href}>
      {inner}
    </Link>
  );
}

export function Pillars() {
  const t = useTranslations("Pillars");
  const pillars: Pillar[] = [
    {
      icon: <IconGateway />,
      tag: t("tag1"),
      title: t("title1"),
      proof: t("proof1"),
      link: t("link1"),
      href: "#install",
    },
    {
      icon: <IconAlwaysOn />,
      tag: t("tag2"),
      title: t("title2"),
      proof: t("proof2"),
      link: t("link2"),
      href: "/tutorials/daemon",
    },
    {
      icon: <IconMesh />,
      tag: t("tag3"),
      title: t("title3"),
      proof: t("proof3"),
      link: t("link3"),
      href: PROTOCOL_URL,
    },
  ];
  return (
    <section className="section pillars" id="pillars">
      <div className="wrap">
        <div className="pillar-grid">
          {pillars.map((p, i) => (
            <article
              className="pillar reveal"
              key={p.tag}
              style={{ transitionDelay: `${i * 0.08}s` }}
            >
              <span className="tag">{p.tag}</span>
              <span className="picon">{p.icon}</span>
              <h3>{p.title}</h3>
              <p className="proof">{p.proof}</p>
              <PillarLink href={p.href} label={p.link} />
            </article>
          ))}
        </div>
      </div>
    </section>
  );
}

/* ---------------- Get the app ---------------- */
type Store = {
  glyph: ReactNode;
  top: string;
  name: string;
  sub: string;
  href: string;
  /** External store link (new tab). Internal hrefs route through /download. */
  external?: boolean;
};

export function GetApp() {
  const t = useTranslations("GetApp");
  const stores: Store[] = [
    {
      glyph: <IconApple />,
      top: t("appStoreTop"),
      name: t("appStoreName"),
      sub: t("appStoreSub"),
      href: "https://apps.apple.com/app/remote-pi-coding-agent/id6773499691",
      external: true,
    },
    {
      glyph: <IconPlay />,
      top: t("playTop"),
      name: t("playName"),
      sub: t("playSub"),
      href: "https://play.google.com/store/apps/details?id=work.jacobmoura.remotepi",
      external: true,
    },
    {
      glyph: <IconAndroid />,
      top: t("apkTop"),
      name: t("apkName"),
      sub: t("apkSub"),
      href: "/download",
    },
    {
      glyph: <IconDownload />,
      top: t("cockpitTop"),
      name: t("cockpitName"),
      sub: t("cockpitSub"),
      href: "/cockpit",
    },
  ];
  return (
    <section className="section" id="get-the-app" style={{ paddingTop: 0 }}>
      <div className="wrap">
        <div className="section-head reveal">
          <span className="eyebrow">{t("eyebrow")}</span>
          <h2>{t("title")}</h2>
          <p>{t("sub")}</p>
        </div>
        <div className="app-grid">
          {stores.map((s, i) => {
            const inner = (
              <>
                <span className="glyph">{s.glyph}</span>
                <span>
                  <span className="s-top">{s.top}</span>
                  <div className="s-name">{s.name}</div>
                  <div className="s-sub">{s.sub}</div>
                </span>
              </>
            );
            const style = { transitionDelay: `${i * 0.06}s` };
            return s.external ? (
              <a
                className="store reveal"
                key={s.name}
                href={s.href}
                target="_blank"
                rel="noopener noreferrer"
                style={style}
              >
                {inner}
              </a>
            ) : (
              <Link
                className="store reveal"
                key={s.name}
                href={s.href}
                style={style}
              >
                {inner}
              </Link>
            );
          })}
        </div>
      </div>
    </section>
  );
}

/* ---------------- Secondary strip ---------------- */
export function Strip() {
  const t = useTranslations("Strip");
  const strip: { icon: ReactNode; label: string }[] = [
    { icon: <IconMic />, label: t("voice") },
    { icon: <IconImage />, label: t("image") },
    { icon: <IconOpenSource />, label: t("openSource") },
    { icon: <IconSelfHost />, label: t("selfHost") },
  ];
  return (
    <div className="strip">
      <div className="wrap">
        <div className="strip-inner">
          {strip.map((s, i) => (
            <Fragment key={s.label}>
              <span className="strip-item">
                {s.icon} {s.label}
              </span>
              {i < strip.length - 1 && <span className="strip-sep">·</span>}
            </Fragment>
          ))}
        </div>
      </div>
    </div>
  );
}

/* ---------------- GitHub CTA ---------------- */
export function GithubCTA() {
  const t = useTranslations("GithubCTA");
  return (
    <section className="cta">
      <div className="wrap cta-inner reveal">
        <span className="eyebrow">{t("eyebrow")}</span>
        <h2>{t("title")}</h2>
        <p>{t("sub")}</p>
        <div>
          <a
            className="btn btn-primary"
            href={GITHUB_URL}
            target="_blank"
            rel="noopener noreferrer"
          >
            <IconGithub /> {t("cta")}
          </a>
        </div>
        <div className="cta-stars">
          <span>
            <IconStar /> {t("star1")}
          </span>
          <span>
            <IconStar /> {t("star2")}
          </span>
          <span>
            <IconStar /> {t("star3")}
          </span>
        </div>
      </div>
    </section>
  );
}
