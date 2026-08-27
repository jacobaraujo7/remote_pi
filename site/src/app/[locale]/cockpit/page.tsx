import type { Metadata } from "next";
import Image from "next/image";
import { getTranslations } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import { localeAlternates } from "@/i18n/alternates";
import { CodeBlock } from "@/components/code-block";
import { RevealController } from "@/components/landing/reveal-controller";
import { IconDownload, IconGithub, IconArrow } from "@/components/landing/icons";

const GITHUB_URL = "https://github.com/jacobaraujo7/remote_pi";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ locale: string }>;
}): Promise<Metadata> {
  const { locale } = await params;
  const t = await getTranslations({ locale, namespace: "CockpitPage" });
  const title = t("title");
  const description = t("metaDescription");

  return {
    title: { absolute: title },
    description,
    alternates: {
      languages: localeAlternates("/cockpit"),
    },
    openGraph: {
      type: "website",
      url: "https://remote-pi.jacobmoura.work/cockpit",
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

/* visual-first section: eyebrow + short headline + max one sentence + big shot */
function Shot({
  src,
  alt,
  width,
  height,
  maxWidth,
}: {
  src: string;
  alt: string;
  width: number;
  height: number;
  maxWidth?: number;
}) {
  return (
    <div
      className="ck-shot reveal"
      style={maxWidth ? { maxWidth, marginLeft: "auto", marginRight: "auto" } : undefined}
    >
      <Image
        src={src}
        alt={alt}
        width={width}
        height={height}
        sizes="(max-width: 1180px) 100vw, 1180px"
        style={{ width: "100%", height: "auto" }}
      />
    </div>
  );
}

export default async function CockpitPage({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  const t = await getTranslations({ locale, namespace: "CockpitPage" });
  const code = (chunks: React.ReactNode) => <code>{chunks}</code>;

  return (
    <div className="page">
      <div className="page-body">
        <div className="wrap">
          {/* ---------------- HERO / JUST A TERMINAL ---------------- */}
          <header className="page-head reveal" style={{ maxWidth: 820 }}>
            <span className="eyebrow">{t("eyebrow")}</span>
            <h1>{t("h1")}</h1>
            <p className="lede">{t("lede")}</p>
            <div
              style={{
                display: "flex",
                gap: 14,
                flexWrap: "wrap",
                marginTop: 32,
              }}
            >
              <Link className="btn btn-primary" href="/download">
                <IconDownload /> {t("download")}
              </Link>
              <a className="btn btn-ghost" href="#agents">
                {t("seeItGrow")} <IconArrow />
              </a>
            </div>
          </header>

          <div className="ck-shot reveal">
            <Image
              src="/cockpit/hero-terminals.png"
              alt={t("heroShotAlt")}
              width={3456}
              height={2168}
              priority
              sizes="(max-width: 1180px) 100vw, 1180px"
              style={{ width: "100%", height: "auto" }}
            />
          </div>

          {/* ---------------- AGENTS LIVE IN TABS ---------------- */}
          <section id="agents">
            <div className="section-head reveal" style={{ marginTop: 110 }}>
              <span className="eyebrow">{t("agentsEyebrow")}</span>
              <h2>{t("agentsTitle")}</h2>
              <p>{t("agentsDesc")}</p>
            </div>
            <Shot
              src="/cockpit/agent-diff-diagnostics.png"
              alt={t("agentsShotAlt")}
              width={3456}
              height={2182}
            />
          </section>

          {/* ---------------- THE IDE EMERGES ---------------- */}
          <section id="ide">
            <div className="section-head reveal" style={{ marginTop: 110 }}>
              <span className="eyebrow">{t("ideEyebrow")}</span>
              <h2>{t("ideTitle")}</h2>
              <p>{t("ideDesc")}</p>
            </div>
            <Shot
              src="/cockpit/code-viewer.png"
              alt={t("ideShotAlt")}
              width={2270}
              height={2080}
            />
          </section>

          {/* ---------------- DATABASES AS TABS ---------------- */}
          <section id="database">
            <div className="section-head reveal" style={{ marginTop: 110 }}>
              <span className="eyebrow">{t("dbEyebrow")}</span>
              <h2>{t("dbTitle")}</h2>
              <p>{t.rich("dbDesc", { code })}</p>
            </div>
            <Shot
              src="/cockpit/database-panel.png"
              alt={t("dbShotAlt")}
              width={1116}
              height={1150}
              maxWidth={620}
            />
          </section>

          {/* ---------------- AGENTS DRIVE THE COCKPIT ---------------- */}
          <section id="cli">
            <div className="section-head reveal" style={{ marginTop: 110 }}>
              <span className="eyebrow">{t("cliEyebrow")}</span>
              <h2>{t("cliTitle")}</h2>
              <p>{t.rich("cliDesc", { code })}</p>
            </div>
            <div className="reveal" style={{ marginTop: 28, maxWidth: 760 }}>
              <CodeBlock
                label={t("cliTerminalLabel")}
                prompt
                code={`# open a worker beside you and steer it
id=$(cockpit new-tab --cwd ~/proj --title Worker --split h)
cockpit send --tab-id "$id" --enter "pnpm test"

# read what it printed
cockpit read-tab Worker --lines 60

# run and follow the project's tasks
cockpit list-tasks
cockpit read-task npm:dev --lines 80

# open a file in the viewer, query a database
cockpit open src/app.ts
cockpit db query --db dev-local --sql "SELECT * FROM orders" --limit 50`}
              />
              <p style={{ marginTop: 18, color: "var(--ink-soft)" }}>
                {t.rich("cliReferenceNote", {
                  link: (chunks) => (
                    <Link href="/cockpit/docs#cli" className="text-accent underline">
                      {chunks}
                    </Link>
                  ),
                })}
              </p>
            </div>
          </section>

          {/* ---------------- WORKSPACES & REALMS ---------------- */}
          <section id="workspaces">
            <div className="section-head reveal" style={{ marginTop: 110 }}>
              <span className="eyebrow">{t("workspacesEyebrow")}</span>
              <h2>{t("workspacesTitle")}</h2>
              <p>{t("workspacesDesc")}</p>
            </div>
          </section>

          {/* ---------------- LAYOUTS & TASKS ---------------- */}
          <section id="layouts">
            <div className="section-head reveal" style={{ marginTop: 110 }}>
              <span className="eyebrow">{t("layoutsEyebrow")}</span>
              <h2>{t("layoutsTitle")}</h2>
              <p>{t.rich("layoutsDesc", { code })}</p>
            </div>
            <div className="reveal" style={{ marginTop: 28, maxWidth: 760 }}>
              <CodeBlock
                label="dev.ckp"
                code={`autorun: worktree
panes:
  - name: Agent
    cwd: .
    command: claude
  - name: API
    cwd: api
    split: right
    command: npm run dev`}
              />
              <p style={{ marginTop: 18, color: "var(--ink-soft)" }}>
                {t.rich("layoutsTutorialNote", {
                  link: (chunks) => (
                    <Link href="/tutorials/cockpit-layouts" className="text-accent underline">
                      {chunks}
                    </Link>
                  ),
                })}
              </p>
            </div>
          </section>

          {/* ---------------- MAKE IT YOURS ---------------- */}
          <section id="yours">
            <div className="section-head reveal" style={{ marginTop: 110 }}>
              <span className="eyebrow">{t("yoursEyebrow")}</span>
              <h2>{t("yoursTitle")}</h2>
              <p>{t("yoursDesc")}</p>
            </div>
          </section>

          {/* ---------------- TURN STATUS ---------------- */}
          <section id="status">
            <div className="section-head reveal" style={{ marginTop: 110 }}>
              <span className="eyebrow">{t("statusEyebrow")}</span>
              <h2>{t("statusTitle")}</h2>
              <p>{t("statusDesc")}</p>
            </div>
          </section>

          {/* ---------------- PLATFORMS + FINAL CTA ---------------- */}
          <div
            className="reveal"
            style={{
              textAlign: "center",
              maxWidth: 680,
              margin: "120px auto 0",
              paddingBottom: 8,
            }}
          >
            <span className="eyebrow">{t("getEyebrow")}</span>
            <h2
              style={{
                fontFamily: "var(--ff-display)",
                fontWeight: 600,
                color: "var(--ink)",
                fontSize: "clamp(30px, 4.4vw, 48px)",
                letterSpacing: "-0.02em",
                lineHeight: 1.04,
                margin: "14px 0 0",
              }}
            >
              {t("getTitle")}
            </h2>
            <p
              style={{
                color: "var(--ink-soft)",
                fontSize: 18,
                margin: "16px auto 0",
                maxWidth: 520,
              }}
            >
              {t("getSub")}
            </p>
            <div
              style={{
                display: "flex",
                gap: 14,
                justifyContent: "center",
                flexWrap: "wrap",
                marginTop: 30,
              }}
            >
              <Link className="btn btn-primary" href="/download">
                <IconDownload /> {t("download")}
              </Link>
              <Link className="btn btn-ghost" href="/cockpit/docs">
                {t("reference")} <IconArrow />
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
            <p
              style={{
                color: "var(--muted)",
                fontSize: 14,
                marginTop: 40,
              }}
            >
              {t.rich("footerNote", {
                link: (chunks) => <Link href="/">{chunks}</Link>,
              })}
            </p>
          </div>
        </div>
      </div>
      <RevealController />
    </div>
  );
}
