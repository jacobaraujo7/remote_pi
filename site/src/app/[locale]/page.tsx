import type { Metadata } from "next";
import Image from "next/image";
import { getTranslations, setRequestLocale } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import { pageAlternates, localeUrl } from "@/i18n/alternates";
import { CodeBlock } from "@/components/code-block";
import { RevealController } from "@/components/landing/reveal-controller";
import { IconDownload, IconGithub, IconArrow } from "@/components/landing/icons";
import { rich } from "@/lib/rich";

type Props = { params: Promise<{ locale: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { locale } = await params;
  const t = await getTranslations({ locale, namespace: "Metadata" });
  const title = t("titleDefault");
  const description = t("description");

  return {
    title: { absolute: title },
    description,
    alternates: pageAlternates(locale, "/"),
    openGraph: {
      type: "website",
      url: localeUrl(locale, "/"),
      title,
      description,
      siteName: "Remote Pi Cockpit",
    },
    twitter: {
      card: "summary_large_image",
      title,
      description,
    },
  };
}

const GITHUB_URL = "https://github.com/jacobaraujo7/remote_pi";

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

export default async function CockpitPage({ params }: Props) {
  const { locale } = await params;
  setRequestLocale(locale);
  const t = await getTranslations({ locale, namespace: "Home" });

  const link = (href: string) =>
    function RichLink(chunks: React.ReactNode) {
      return (
        <Link href={href} className="text-accent underline">
          {chunks}
        </Link>
      );
    };

  return (
    <div className="page">
      <div className="page-body">
        <div className="wrap">
          {/* ---------------- HERO ---------------- */}
          <header className="page-head reveal" style={{ maxWidth: 860 }}>
            <span className="eyebrow">{t("hero.eyebrow")}</span>
            <h1>{t("hero.title")}</h1>
            <p className="lede">{t("hero.lede")}</p>
            <div
              style={{
                display: "flex",
                gap: 14,
                flexWrap: "wrap",
                marginTop: 32,
              }}
            >
              <Link className="btn btn-primary" href="/download">
                <IconDownload /> {t("hero.download")}
              </Link>
              <a className="btn btn-ghost" href="#remote">
                {t("hero.whatsNew")} <IconArrow />
              </a>
            </div>
          </header>

          <div className="ck-shot reveal">
            <Image
              src="/cockpit/hero-terminals.png"
              alt={t("hero.shotAlt")}
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
              <span className="eyebrow">{t("agents.eyebrow")}</span>
              <h2>{t("agents.title")}</h2>
              <p>{t("agents.body")}</p>
            </div>
            <Shot
              src="/cockpit/agent-diff-diagnostics.png"
              alt={t("agents.shotAlt")}
              width={3456}
              height={2182}
            />
          </section>

          {/* ---------------- 1. REMOTE OVER SSH ---------------- */}
          <section id="remote">
            <div className="section-head reveal" style={{ marginTop: 110 }}>
              <span className="eyebrow">{t("remote.eyebrow")}</span>
              <h2>{t("remote.title")}</h2>
              <p>{t("remote.p1")}</p>
              <p>{t.rich("remote.p2", rich)}</p>
            </div>
          </section>

          {/* ---------------- 2. SESSIONS OUTLIVE THE CLIENT ---------------- */}
          <section id="sessions">
            <div className="section-head reveal" style={{ marginTop: 110 }}>
              <span className="eyebrow">{t("sessions.eyebrow")}</span>
              <h2>{t("sessions.title")}</h2>
              <p>{t("sessions.body")}</p>
            </div>
          </section>

          {/* ---------------- 3. A VPS WITH ONE CURL ---------------- */}
          <section id="vps">
            <div className="section-head reveal" style={{ marginTop: 110 }}>
              <span className="eyebrow">{t("vps.eyebrow")}</span>
              <h2>{t("vps.title")}</h2>
              <p>{t.rich("vps.body", rich)}</p>
            </div>
            <div className="reveal" style={{ marginTop: 28, maxWidth: 760 }}>
              <CodeBlock
                label={t("vps.codeLabel")}
                prompt
                code={`curl -fsSL https://remote-pi.jacobmoura.work/cockpit-server.sh | bash`}
              />
              <p style={{ marginTop: 18, color: "var(--ink-soft)" }}>
                {t.rich("vps.recipe", {
                  download: link("/download#vps"),
                  ref: link("/docs#remote"),
                })}
              </p>
            </div>
          </section>

          {/* ---------------- 4. MOBILE CLIENT ---------------- */}
          <section id="mobile">
            <div className="section-head reveal" style={{ marginTop: 110 }}>
              <span className="eyebrow">{t("mobile.eyebrow")}</span>
              <h2>{t("mobile.title")}</h2>
              <p>{t("mobile.p1")}</p>
              <p>
                {t.rich("mobile.p2", { download: link("/download#android") })}
              </p>
            </div>
          </section>

          {/* ---------------- 5. DOCUMENTS AS TABS ---------------- */}
          <section id="documents">
            <div className="section-head reveal" style={{ marginTop: 110 }}>
              <span className="eyebrow">{t("documents.eyebrow")}</span>
              <h2>{t("documents.title")}</h2>
              <p>{t("documents.intro")}</p>
              <ul className="ck-list">
                <li>{t.rich("documents.notebook", rich)}</li>
                <li>{t.rich("documents.http", rich)}</li>
                <li>{t.rich("documents.kanban", rich)}</li>
                <li>{t.rich("documents.mermaid", rich)}</li>
                <li>{t.rich("documents.window", rich)}</li>
                <li>{t.rich("documents.gallery", rich)}</li>
              </ul>
            </div>
          </section>

          {/* ---------------- 6. SECRETS ---------------- */}
          <section id="secrets">
            <div className="section-head reveal" style={{ marginTop: 110 }}>
              <span className="eyebrow">{t("secrets.eyebrow")}</span>
              <h2>{t("secrets.title")}</h2>
              <p>{t.rich("secrets.body", rich)}</p>
            </div>
            <div className="reveal" style={{ marginTop: 28, maxWidth: 760 }}>
              <CodeBlock
                label=".env.cockpit"
                code={`OPENAI_API_KEY=sk-...
GITHUB_TOKEN=ghp_...`}
              />
              <p style={{ marginTop: 18, color: "var(--ink-soft)" }}>
                {t.rich("secrets.note", rich)}
              </p>
            </div>
          </section>

          {/* ---------------- 7. THE AGENT DRIVES THE COCKPIT ---------------- */}
          <section id="cli">
            <div className="section-head reveal" style={{ marginTop: 110 }}>
              <span className="eyebrow">{t("cli.eyebrow")}</span>
              <h2>{t("cli.title")}</h2>
              <p>{t.rich("cli.body", rich)}</p>
            </div>
            <div className="reveal" style={{ marginTop: 28, maxWidth: 760 }}>
              <CodeBlock
                label={t("cli.codeLabel")}
                prompt
                code={`# open a worker beside you and steer it
id=$(cockpit new-tab --cwd ~/proj --title Worker --split h)
cockpit send --tab-id "$id" --enter "pnpm test"

# read what it printed
cockpit read-tab Worker --lines 60

# run and follow the project's tasks
cockpit list-tasks
cockpit read-task npm:dev --lines 80

# open a file, query a database, fire a request, leave a note
cockpit open src/app.ts
cockpit db query --db dev-local --sql "SELECT * FROM orders" --limit 50
cockpit http run api/users.http
cockpit note add notes.notebook --title "What I changed" --body -`}
              />
              <p style={{ marginTop: 18, color: "var(--ink-soft)" }}>
                {t.rich("cli.ref", { ref: link("/docs#cli") })}
              </p>
            </div>
          </section>

          {/* ---------------- THE IDE EMERGES ---------------- */}
          <section id="ide">
            <div className="section-head reveal" style={{ marginTop: 110 }}>
              <span className="eyebrow">{t("ide.eyebrow")}</span>
              <h2>{t("ide.title")}</h2>
              <p>{t("ide.body")}</p>
            </div>
            <Shot
              src="/cockpit/code-viewer.png"
              alt={t("ide.shotAlt")}
              width={2270}
              height={2080}
            />
          </section>

          {/* ---------------- DATABASES AS TABS ---------------- */}
          <section id="database">
            <div className="section-head reveal" style={{ marginTop: 110 }}>
              <span className="eyebrow">{t("database.eyebrow")}</span>
              <h2>{t("database.title")}</h2>
              <p>{t.rich("database.body", rich)}</p>
            </div>
            <Shot
              src="/cockpit/database-panel.png"
              alt={t("database.shotAlt")}
              width={1116}
              height={1150}
              maxWidth={620}
            />
          </section>

          {/* ---------------- WORKSPACES & REALMS ---------------- */}
          <section id="workspaces">
            <div className="section-head reveal" style={{ marginTop: 110 }}>
              <span className="eyebrow">{t("workspaces.eyebrow")}</span>
              <h2>{t("workspaces.title")}</h2>
              <p>{t("workspaces.body")}</p>
            </div>
          </section>

          {/* ---------------- LAYOUTS & TASKS ---------------- */}
          <section id="layouts">
            <div className="section-head reveal" style={{ marginTop: 110 }}>
              <span className="eyebrow">{t("layouts.eyebrow")}</span>
              <h2>{t("layouts.title")}</h2>
              <p>{t.rich("layouts.body", rich)}</p>
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
                {t.rich("layouts.tutorial", {
                  tutorial: link("/tutorials/cockpit-layouts"),
                })}
              </p>
            </div>
          </section>

          {/* ---------------- MAKE IT YOURS ---------------- */}
          <section id="yours">
            <div className="section-head reveal" style={{ marginTop: 110 }}>
              <span className="eyebrow">{t("yours.eyebrow")}</span>
              <h2>{t("yours.title")}</h2>
              <p>{t("yours.body")}</p>
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
            <span className="eyebrow">{t("cta.eyebrow")}</span>
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
              {t("cta.title")}
            </h2>
            <p
              style={{
                color: "var(--ink-soft)",
                fontSize: 18,
                margin: "16px auto 0",
                maxWidth: 520,
              }}
            >
              {t("cta.body")}
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
                <IconDownload /> {t("cta.download")}
              </Link>
              <Link className="btn btn-ghost" href="/docs">
                {t("cta.reference")} <IconArrow />
              </Link>
              <a
                className="btn btn-ghost"
                href={GITHUB_URL}
                target="_blank"
                rel="noopener noreferrer"
              >
                <IconGithub /> {t("cta.github")}
              </a>
            </div>
            <p
              style={{
                color: "var(--muted)",
                fontSize: 14,
                marginTop: 40,
              }}
            >
              {t.rich("cta.remotePi", {
                remotepi: (chunks) => <Link href="/remote-pi">{chunks}</Link>,
              })}
            </p>
          </div>
        </div>
      </div>
      <RevealController />
    </div>
  );
}
