import type { Metadata } from "next";
import type { ReactNode } from "react";
import { getTranslations, setRequestLocale } from "next-intl/server";
import { pageAlternates } from "@/i18n/alternates";
import { Link } from "@/i18n/navigation";
import { DocsSection, InlineCode } from "@/components/docs-shell";
import { CodeBlock } from "@/components/code-block";
import { Callout } from "@/components/callout";
import { Pager } from "@/components/pager";
import { RevealController } from "@/components/landing/reveal-controller";

type Props = { params: Promise<{ locale: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { locale } = await params;
  const t = await getTranslations({
    locale,
    namespace: "CockpitTutorials.telemetry",
  });
  return {
    title: t("meta.title"),
    description: t("meta.description"),
    alternates: pageAlternates(locale, "/tutorials/cockpit-telemetry"),
  };
}

const WRAPPER = `# anything you run yourself (a terminal tab, or an agent's shell)
cockpit telemetry flutter run
cockpit telemetry --name api npm run dev

# at exit, one summary line:
telemetry: run r_42 · 3 errors · 12 warnings · cockpit telemetry errors --run r_42`;

const LOOP = `cockpit telemetry errors --run r_42        # grouped cases, ids like e_3f2a
cockpit telemetry show e_3f2a               # stack (project frames flagged),
                                            # the JSON log right before it, context
# fix the code, then run again, or on a dev server with hot reload:
cockpit telemetry wait --fingerprint e_3f2a --absent 30s   # ok | hit | inconclusive
cockpit telemetry resolve e_3f2a --reason "off-by-one in CartService.add"`;

const JSONL = `{"level":"error","msg":"cart add failed","err":{"type":"RangeError","message":"index 3 of 2","stack":"#0 ..."},"itemId":"abc","total":42}`;

const DART = `// lib/main.dart — the project's own logger, JSON to stdout
import 'dart:convert';
import 'dart:developer' as dev;
import 'package:logging/logging.dart';

void setupLogging() {
  Logger.root.level = kReleaseMode ? Level.WARNING : Level.ALL;
  Logger.root.onRecord.listen((r) {
    print(jsonEncode({
      'level': r.level.name.toLowerCase(),
      'msg': r.message,
      'logger': r.loggerName,
      if (r.error != null) 'err': {'type': r.error.runtimeType.toString(),
        'message': r.error.toString(), 'stack': r.stackTrace?.toString()},
    }));
  });
  FlutterError.onError = (d) => Logger.root.severe(d.exceptionAsString(), d.exception, d.stack);
}`;

const TASKS = `{
  "tasks": [
    { "label": "api", "cwd": "backend", "command": "npm", "args": ["run", "dev"],
      "kind": "watch", "env": { "LOG_LEVEL": "debug" } },
    { "label": "noisy-worker", "cwd": "worker", "command": "npm", "args": ["start"],
      "telemetry": false }
  ]
}`;

const CONFIG = `// .cockpit/telemetry.json (optional, versioned)
{
  "unwrap": ["^api-1\\\\s*\\\\| "],                 // odd log prefixes to strip
  "ignore": ["DeprecationWarning: The \`punycode\`"],  // known noise, dropped on entry
  "proxy": { "listen": 3100, "upstream": "http://127.0.0.1:3000" }
}`;

/* Inline tags used by the messages: <code1>, <a2>... Handlers live here so
   each message just spreads TAGS. Contents of <code*> are never translated. */
const TAGS = {
  em1: (c: ReactNode) => <em>{c}</em>,
  strong1: (c: ReactNode) => <strong className="text-fg">{c}</strong>,
  code1: (c: ReactNode) => <InlineCode>{c}</InlineCode>,
  link1: (c: ReactNode) => (
    <Link href="/tutorials/cockpit-team" className="text-accent underline">
      {c}
    </Link>
  ),
  link2: (c: ReactNode) => (
    <Link href="/docs" className="text-accent underline">
      {c}
    </Link>
  ),
};

export default async function CockpitTelemetryTutorial({ params }: Props) {
  const { locale } = await params;
  setRequestLocale(locale);
  const t = await getTranslations({
    locale,
    namespace: "CockpitTutorials.telemetry",
  });
  return (
    <div className="page">
      <div className="page-body">
        <div className="wrap">
          <div className="tut">
            <header className="page-head reveal" style={{ maxWidth: "none" }}>
              <div className="flex flex-wrap items-center gap-3">
                <span className="inline-flex items-center rounded-full border border-accent/40 bg-accent/15 px-3 py-1 text-xs font-semibold uppercase tracking-[0.15em] text-accent">
                  {t("intro.span1")}
                </span>
              </div>
              <span className="eyebrow" style={{ marginTop: 14 }}>
                {t("intro.span2")}
              </span>
              <h1>{t("intro.h11")}</h1>
              <p className="lede">{t.rich("intro.p1", TAGS)}</p>
            </header>

            <article className="prose">
              <DocsSection id="what" title={t("what.title")}>
                <ul className="ml-6 list-disc space-y-2">
                  <li>{t.rich("what.li1", TAGS)}</li>
                  <li>{t.rich("what.li2", TAGS)}</li>
                  <li>{t.rich("what.li3", TAGS)}</li>
                </ul>
              </DocsSection>

              <DocsSection id="how" title={t("how.title")}>
                <p>{t.rich("how.p1", TAGS)}</p>
                <CodeBlock code={WRAPPER} label="terminal" language="bash" />
                <Callout title={t("how.callout1")}>{t("how.callout2")}</Callout>
              </DocsSection>

              <DocsSection id="loop" title={t("loop.title")}>
                <p>{t("loop.p1")}</p>
                <CodeBlock code={LOOP} label="terminal" language="bash" />
                <p>{t.rich("loop.p2", TAGS)}</p>
              </DocsSection>

              <DocsSection id="speak" title={t("speak.title")}>
                <p>{t.rich("speak.p1", TAGS)}</p>
                <CodeBlock
                  code={JSONL}
                  label={t("speak.label1")}
                  language="json"
                />
                <CodeBlock
                  code={DART}
                  label={t("speak.label2")}
                  language="dart"
                />
                <p>{t.rich("speak.p2", TAGS)}</p>
                <Callout title={t("speak.callout1")}>
                  {t.rich("speak.callout2", TAGS)}
                </Callout>
                <CodeBlock
                  code={TASKS}
                  label=".cockpit/tasks.json"
                  language="json"
                />
              </DocsSection>

              <DocsSection id="extras" title={t("extras.title")}>
                <ul className="ml-6 list-disc space-y-2">
                  <li>{t.rich("extras.li1", TAGS)}</li>
                  <li>{t.rich("extras.li2", TAGS)}</li>
                  <li>{t.rich("extras.li3", TAGS)}</li>
                </ul>
                <CodeBlock
                  code={CONFIG}
                  label=".cockpit/telemetry.json"
                  language="json"
                />
              </DocsSection>

              <DocsSection id="privacy" title={t("privacy.title")}>
                <p>{t("privacy.p1")}</p>
                <p>{t.rich("privacy.p2", TAGS)}</p>
              </DocsSection>
            </article>

            <Pager
              prev={{
                href: "/tutorials/cockpit-team",
                label: t("pager.prev"),
              }}
              next={{ href: "/docs", label: t("pager.next") }}
            />
          </div>
        </div>
      </div>
      <RevealController />
    </div>
  );
}
