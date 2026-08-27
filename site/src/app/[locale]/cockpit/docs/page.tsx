import type { Metadata } from "next";
import { getTranslations } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import {
  DocsSection,
  DocsSubsection,
  InlineCode,
  DocsTable,
} from "@/components/docs-shell";
import { CodeBlock } from "@/components/code-block";
import { Callout } from "@/components/callout";
import { DocsToc, type TocItem } from "@/components/docs-toc";
import { RevealController } from "@/components/landing/reveal-controller";
import { localeAlternates } from "@/i18n/alternates";

const GITHUB_URL = "https://github.com/jacobaraujo7/remote_pi";
const COCKPIT_DOCS =
  "https://github.com/jacobaraujo7/remote_pi/tree/main/cockpit/docs";
const THEME_SCHEMA =
  "https://raw.githubusercontent.com/jacobaraujo7/remote_pi/main/cockpit/docs/theme.schema.json";
const TASKS_SCHEMA =
  "https://github.com/jacobaraujo7/remote_pi/blob/main/cockpit/docs/tasks.schema.json";
const THEME_EXAMPLE =
  "https://github.com/jacobaraujo7/remote_pi/blob/main/cockpit/docs/theme.example.json";

const CKP_EXAMPLE = `# dev.ckp — anywhere in the project; cwd is relative to this file
autorun: worktree        # optional
panes:
  - name: Frontend       # required, unique — becomes the tab's stable label
    cwd: frontend        # relative to this file, always with "/"
    command: claude      # optional: typed into the shell after the tab opens
  - name: Backend
    cwd: backend
    split: right         # tab (default) | right (side by side) | down (stacked)
    command: npm run dev
  - name: Sign
    cwd: .
    command: ./sign.sh
    platforms: [macos]   # optional: macos | windows | linux (string or list)`;

const TASKS_EXAMPLE = `{
  "tasks": [
    {
      "label": "run",
      "cwd": "app",                 // relative to the tasks.json folder
      "command": "flutter",
      "args": ["run"],
      "kind": "watch",
      "interactiveKeys": [
        { "key": "r", "label": "Hot reload", "icon": "refresh", "primary": true },
        { "key": "R", "label": "Hot restart", "icon": "restart", "primary": true },
        { "key": "q", "label": "Quit", "icon": "stop" }
      ],
      "watch": {
        "paths": ["lib", "assets"],
        "ignore": ["build", ".dart_tool"],
        "onChange": "Hot reload",   // an interactiveKey label, or "__restart__"
        "debounceMs": 300
      },
      "progressPatterns": [
        { "begin": "Performing hot reload", "end": "Reloaded .* in .*ms" }
      ],
      "profiles": [
        { "name": "default" },
        { "name": "web", "args": ["-d", "chrome"] }
      ]
    },
    {
      "label": "api",
      "cwd": "backend",             // monorepo: another subfolder
      "command": "dart",
      "args": ["run", "bin/server.dart"],
      "kind": "watch"
    }
  ]
}`;

const THEME_SHAPE = `{
  "$schema": "${THEME_SCHEMA}",
  "id": "acme.aurora",
  "name": "Aurora",
  "author": "Acme",
  "version": "1.0.0",
  "extends": "cockpit",
  "variants": {
    "dark":  { "ui": {}, "syntax": {}, "terminal": {} },
    "light": { "ui": {}, "syntax": {}, "terminal": {} }
  }
}`;

const THEME_MINIMAL = `{
  "$schema": "${THEME_SCHEMA}",
  "id": "acme.violet",
  "name": "Violet",
  "variants": {
    "dark":  { "ui": { "accent": "#8B5CF6", "accentSoft": "#8B5CF633", "accentText": "#C4B5FD" } },
    "light": { "ui": { "accent": "#7C3AED", "accentSoft": "#7C3AED22", "accentText": "#5B21B6" } }
  }
}`;

type CockpitDocsT = Awaited<ReturnType<typeof getTranslations<"CockpitDocsPage">>>;

export async function generateMetadata({
  params,
}: {
  params: Promise<{ locale: string }>;
}): Promise<Metadata> {
  const { locale } = await params;
  const t = await getTranslations({ locale, namespace: "CockpitDocsPage" });
  return {
    title: t("title"),
    description: t("metaDescription"),
    alternates: { languages: localeAlternates("/cockpit/docs") },
  };
}

function buildDocsToc(t: CockpitDocsT): TocItem[] {
  return [
    { id: "install", label: t("tocInstall") },
    {
      id: "cli",
      label: <>{t("tocCli")} <InlineCode>cockpit</InlineCode></>,
      sub: [
        { id: "cli-targets", label: t("tocCliTargets") },
        { id: "cli-commands", label: t("tocCliCommands") },
        { id: "cli-read", label: t("tocCliRead") },
      ],
    },
    {
      id: "layouts",
      label: <><InlineCode>.ckp</InlineCode> {t("tocLayouts")}</>,
      sub: [
        { id: "layouts-fields", label: t("tocLayoutsFields") },
        { id: "layouts-merge", label: t("tocLayoutsMerge") },
      ],
    },
    {
      id: "tasks",
      label: t("tocTasks"),
      sub: [
        { id: "tasks-file", label: "tasks.json" },
        { id: "tasks-fields", label: t("tocTasksFields") },
      ],
    },
    { id: "databases", label: t("tocDatabases") },
    {
      id: "themes",
      label: t("tocThemes"),
      sub: [
        { id: "themes-file", label: t("tocThemesFile") },
        { id: "themes-tokens", label: t("tocThemesTokens") },
      ],
    },
    {
      id: "turn-status",
      label: t("tocTurnStatus"),
      sub: [
        { id: "turn-status-events", label: t("tocTurnStatusEvents") },
        { id: "turn-status-resume", label: t("tocTurnStatusResume") },
      ],
    },
    { id: "sounds", label: t("tocSounds") },
    { id: "language", label: t("tocLanguage") },
    { id: "links", label: t("tocLinks") },
  ];
}

export default async function CockpitDocsPage({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  const t = await getTranslations({ locale, namespace: "CockpitDocsPage" });
  const b = (chunks: React.ReactNode) => <strong>{chunks}</strong>;
  const em = (chunks: React.ReactNode) => <em>{chunks}</em>;
  const code = (chunks: React.ReactNode) => <InlineCode>{chunks}</InlineCode>;
  const downloadLink = (chunks: React.ReactNode) => (
    <Link href="/download" className="text-accent underline">{chunks}</Link>
  );
  const mainDocsInstallLink = (chunks: React.ReactNode) => (
    <Link href="/docs#install" className="text-accent underline">{chunks}</Link>
  );
  const databasesAnchor = (chunks: React.ReactNode) => (
    <a href="#databases" className="text-accent underline">{chunks}</a>
  );
  const layoutsAnchor = (chunks: React.ReactNode) => (
    <a href="#layouts" className="text-accent underline">{chunks}</a>
  );
  const tasksSchemaLink = (chunks: React.ReactNode) => (
    <a className="text-accent underline" href={TASKS_SCHEMA} target="_blank" rel="noopener noreferrer">{chunks}</a>
  );
  const themeExampleLink = (chunks: React.ReactNode) => (
    <a className="text-accent underline" href={THEME_EXAMPLE} target="_blank" rel="noopener noreferrer">{chunks}</a>
  );
  const cockpitLink = (chunks: React.ReactNode) => (
    <Link href="/cockpit" className="text-accent underline">{chunks}</Link>
  );
  const remotePiDocsLink = (chunks: React.ReactNode) => (
    <Link href="/docs" className="text-accent underline">{chunks}</Link>
  );

  return (
    <div className="page">
      <div className="page-body">
        <div className="wrap">
          <header className="page-head reveal">
            <span className="eyebrow">{t("eyebrow")}</span>
            <h1>{t("h1")}</h1>
            <div className="meta-line">
              <span>{t("lastUpdated")}</span>
              <span>{t("license")}</span>
            </div>
            <p className="lede">
              {t.rich("lede", { code, cockpitLink, remotePiDocsLink })}
            </p>
          </header>

          <div className="docs-layout">
            <DocsToc items={buildDocsToc(t)} />

            <article className="prose docs-article">
              {/* ── INSTALL ─────────────────────────────────────────────── */}

              <DocsSection id="install" title={t("s1Title")}>
                <p>{t.rich("s1P1", { code, link: downloadLink })}</p>
                <p>{t.rich("s1P2", { code, link: mainDocsInstallLink })}</p>
              </DocsSection>

              {/* ── CLI ─────────────────────────────────────────────────── */}

              <DocsSection id="cli" title={t("s2Title")}>
                <p>{t.rich("s2P1", { code })}</p>
                <p>{t.rich("s2P2", { em })}</p>

                <DocsSubsection id="cli-targets" title={t("s2Sub1Title")}>
                  <p>{t.rich("s2Sub1P1", { b, code })}</p>
                  <DocsTable
                    headers={[t("tableFlag"), t("tableWhatItDoes")]}
                    rows={[
                      [<InlineCode key="t">--tab-id &lt;id&gt;</InlineCode>, t.rich("s2Sub1Row1", { code })],
                      [<InlineCode key="f">--focused</InlineCode>, t.rich("s2Sub1Row2", { code })],
                      [<InlineCode key="e">--enter</InlineCode>, t.rich("s2Sub1Row3", { code })],
                    ]}
                  />
                  <Callout variant="warning" title={t("s2Sub1CalloutTitle")}>
                    <p>{t.rich("s2Sub1CalloutBody", { code, b })}</p>
                  </Callout>
                </DocsSubsection>

                <DocsSubsection id="cli-commands" title={t("s2Sub2Title")}>
                  <DocsTable
                    headers={[t("tableCommand"), t("tableWhatItDoes")]}
                    rows={[
                      [<InlineCode key="c">send [--tab-id id] [--enter] &lt;text&gt;</InlineCode>, t("s2Sub2Row1")],
                      [<InlineCode key="c">send-key [--tab-id id] &lt;Key&gt;…</InlineCode>, t.rich("s2Sub2Row2", { code })],
                      [<InlineCode key="c">open &lt;file&gt;</InlineCode>, t.rich("s2Sub2Row3", { code })],
                      [<InlineCode key="c">new-tab [--cwd dir] [--title name] [--split h|v]</InlineCode>, t.rich("s2Sub2Row4", { code })],
                      [<InlineCode key="c">read-tab [label|tab-id]</InlineCode>, t.rich("s2Sub2Row5", { code })],
                      [<InlineCode key="c">read-task &lt;task-id&gt;</InlineCode>, t("s2Sub2Row6")],
                      [<InlineCode key="c">list-tabs [--json]</InlineCode>, t.rich("s2Sub2Row7", { code })],
                      [<InlineCode key="c">list-workspaces [--json]</InlineCode>, t("s2Sub2Row8")],
                      [<InlineCode key="c">list-tasks [--json]</InlineCode>, t.rich("s2Sub2Row9", { code })],
                      [<InlineCode key="c">db &lt;list|schema|query|run|execute&gt;</InlineCode>, t.rich("s2Sub2Row10", { link: databasesAnchor })],
                      [<InlineCode key="c">redis [browse] --db conn</InlineCode>, t("s2Sub2Row11")],
                      [<InlineCode key="c">mongo [browse] --db conn [--database name]</InlineCode>, t("s2Sub2Row12")],
                      [<InlineCode key="c">orchestrate &lt;file.ckp&gt; [--json]</InlineCode>, t.rich("s2Sub2Row13", { link: layoutsAnchor, code })],
                      [<InlineCode key="c">install-skill [--force]</InlineCode>, t("s2Sub2Row14")],
                    ]}
                  />
                  <CodeBlock
                    label={t("s2Sub2CodeLabel")}
                    prompt
                    code={`# open a worker tab beside you, then drive it
id=$(cockpit new-tab --cwd ~/proj --title Worker --split h)
cockpit send --tab-id "$id" --enter "npm test"

# read what it printed
cockpit read-tab Worker --lines 50

# run and follow a project task
cockpit list-tasks
cockpit read-task npm:dev --lines 80

# open a file in the viewer, query a database
cockpit open ~/.gitconfig
cockpit db query --db dev-local --sql "SELECT * FROM orders LIMIT 5"`}
                  />
                </DocsSubsection>

                <DocsSubsection id="cli-read" title={t("s2Sub3Title")}>
                  <p>{t.rich("s2Sub3P1", { code })}</p>
                  <DocsTable
                    headers={[t("tableFlag"), t("tableDefault"), t("tableWhatItDoes")]}
                    rows={[
                      [<InlineCode key="l">--lines N</InlineCode>, "100", t("s2Sub3Row1")],
                      [<InlineCode key="o">--offset N</InlineCode>, "0", t("s2Sub3Row2")],
                      [<InlineCode key="s">--from-start</InlineCode>, t("off"), t("s2Sub3Row3")],
                    ]}
                  />
                  <p>{t.rich("s2Sub3P2", { code })}</p>
                </DocsSubsection>
              </DocsSection>

              {/* ── .ckp LAYOUTS ────────────────────────────────────────── */}

              <DocsSection id="layouts" title=".ckp pane layouts">
                <p>{t.rich("s3P1", { code })}</p>
                <p>{t("s3P2")}</p>
                <ul>
                  <li>{t.rich("s3Li1", { b, code })}</li>
                  <li>{t.rich("s3Li2", { b, code })}</li>
                  <li>{t.rich("s3Li3", { b, code })}</li>
                </ul>
                <CodeBlock label="dev.ckp" language="yaml" code={CKP_EXAMPLE} />

                <DocsSubsection id="layouts-fields" title={t("s3Sub1Title")}>
                  <p>{t.rich("s3Sub1P1", { b, code })}</p>
                  <DocsTable
                    headers={[t("tableField"), t("tableRequired"), t("tableDefault"), t("tableDescription")]}
                    rows={[
                      [<InlineCode key="n">name</InlineCode>, t("yes"), "—", t("s3Sub1Row1")],
                      [<InlineCode key="c">cwd</InlineCode>, t("no"), <InlineCode key="d">.</InlineCode>, t.rich("s3Sub1Row2", { code })],
                      [<InlineCode key="s">split</InlineCode>, t("no"), <InlineCode key="d">tab</InlineCode>, t.rich("s3Sub1Row3", { em, code })],
                      [<InlineCode key="cm">command</InlineCode>, t("no"), "—", t("s3Sub1Row4")],
                      [<InlineCode key="p">platforms</InlineCode>, t("no"), t("all"), t.rich("s3Sub1Row5", { code })],
                    ]}
                  />
                </DocsSubsection>

                <DocsSubsection id="layouts-merge" title={t("s3Sub2Title")}>
                  <ul>
                    <li>{t.rich("s3Sub2Li1", { code, b })}</li>
                    <li>{t.rich("s3Sub2Li2", { code, em })}</li>
                    <li>{t.rich("s3Sub2Li3", { code })}</li>
                    <li>{t.rich("s3Sub2Li4", { code })}</li>
                  </ul>
                  <p>{t.rich("s3Sub2P1", { code })}</p>
                </DocsSubsection>
              </DocsSection>

              {/* ── TASK RUN ────────────────────────────────────────────── */}

              <DocsSection id="tasks" title={t("s4Title")}>
                <p>{t.rich("s4P1", { code })}</p>
                <ul>
                  <li>{t.rich("s4Li1", { b, code })}</li>
                  <li>{t.rich("s4Li2", { b, code })}</li>
                </ul>
                <Callout variant="note" title={t("s4CalloutTitle")}>
                  <p>{t.rich("s4CalloutBody", { code })}</p>
                </Callout>

                <DocsSubsection id="tasks-file" title={t("s4Sub1Title")}>
                  <p>{t.rich("s4Sub1P1", { b, code })}</p>
                  <p>{t.rich("s4Sub1P2", { b, code, link: tasksSchemaLink })}</p>
                  <CodeBlock label=".cockpit/tasks.json" language="jsonc" code={TASKS_EXAMPLE} />
                </DocsSubsection>

                <DocsSubsection id="tasks-fields" title={t("s4Sub2Title")}>
                  <p>{t.rich("s4Sub2P1", { code })}</p>
                  <DocsTable
                    headers={[t("tableField"), t("tableRequired"), t("tableDefault"), t("tableDescription")]}
                    rows={[
                      [<InlineCode key="l">label</InlineCode>, t("yes"), "—", t.rich("s4Sub2Row1", { code })],
                      [<InlineCode key="c">command</InlineCode>, t("yes"), "—", t("s4Sub2Row2")],
                      [<InlineCode key="a">args</InlineCode>, t("no"), <InlineCode key="d">[]</InlineCode>, t("s4Sub2Row3")],
                      [<InlineCode key="w">cwd</InlineCode>, t("no"), t("root"), t.rich("s4Sub2Row4", { code })],
                      [<InlineCode key="p">platforms</InlineCode>, t("no"), t("all"), t.rich("s4Sub2Row5", { code })],
                      [<InlineCode key="k">kind</InlineCode>, t("no"), <InlineCode key="d">oneShot</InlineCode>, t.rich("s4Sub2Row6", { code })],
                      [<InlineCode key="i">interactiveKeys</InlineCode>, t("no"), <InlineCode key="d">[]</InlineCode>, t.rich("s4Sub2Row7", { code })],
                      [<InlineCode key="wa">watch</InlineCode>, t("no"), <InlineCode key="d">null</InlineCode>, t.rich("s4Sub2Row8", { code })],
                      [<InlineCode key="pp">progressPatterns</InlineCode>, t("no"), <InlineCode key="d">[]</InlineCode>, t.rich("s4Sub2Row9", { code, em })],
                      [<InlineCode key="pr">profiles</InlineCode>, t("no"), <InlineCode key="d">[]</InlineCode>, t.rich("s4Sub2Row10", { code })],
                    ]}
                  />
                  <Callout variant="warning" title={t("s4Sub2CalloutTitle")}>
                    <p>{t.rich("s4Sub2CalloutBody", { b, code })}</p>
                  </Callout>
                </DocsSubsection>
              </DocsSection>

              {/* ── DATABASES ───────────────────────────────────────────── */}

              <DocsSection id="databases" title={t("s5Title")}>
                <p>{t.rich("s5P1", { code })}</p>
                <p>{t.rich("s5P2", { b })}</p>
                <CodeBlock
                  label={t("s2Sub2CodeLabel")}
                  prompt
                  code={`cockpit db list
cockpit db schema --db dev-local orders
cockpit db query --db dev-local --sql "SELECT * FROM orders LIMIT 5"
cockpit db run reports/daily.dbq

# non-SQL engines have their own verbs
cockpit redis --db cache --command "SCAN 0 COUNT 20"
cockpit mongo --db atlas --database shop --command '{"find":"orders","limit":5}'

# open the same thing visually for a human
cockpit redis browse --db cache
cockpit mongo browse --db atlas --database shop`}
                />
                <Callout variant="note" title={t("s5CalloutTitle")}>
                  <p>{t.rich("s5CalloutBody", { code })}</p>
                </Callout>
              </DocsSection>

              {/* ── THEMES ──────────────────────────────────────────────── */}

              <DocsSection id="themes" title={t("s6Title")}>
                <p>{t.rich("s6P1", { code, b })}</p>

                <DocsSubsection id="themes-file" title={t("s6Sub1Title")}>
                  <ul>
                    <li>{t.rich("s6Sub1Li1", { b })}</li>
                    <li>{t.rich("s6Sub1Li2", { code })}</li>
                    <li>{t.rich("s6Sub1Li3", { b, code })}</li>
                  </ul>
                  <CodeBlock label="theme.json — shape" language="json" code={THEME_SHAPE} />
                  <DocsTable
                    headers={[t("tableField"), t("tableRequired"), t("tableWhatItIs")]}
                    rows={[
                      [<InlineCode key="i">id</InlineCode>, t("yes"), t.rich("s6Sub1Row1", { code })],
                      [<InlineCode key="n">name</InlineCode>, t("yes"), t("s6Sub1Row2")],
                      [<InlineCode key="a">author</InlineCode>, t("no"), t("metadata")],
                      [<InlineCode key="v">version</InlineCode>, t("no"), t("metadata")],
                      [<InlineCode key="e">extends</InlineCode>, t("no"), t.rich("s6Sub1Row3", { code })],
                      [<InlineCode key="va">variants</InlineCode>, t("yes"), t.rich("s6Sub1Row4", { code })],
                    ]}
                  />
                  <p>{t.rich("s6Sub1P1", { b })}</p>
                  <CodeBlock label="acme.violet.json" language="json" code={THEME_MINIMAL} />
                  <p>{t.rich("s6Sub1P2", { code, b })}</p>
                </DocsSubsection>

                <DocsSubsection id="themes-tokens" title={t("s6Sub2Title")}>
                  <DocsTable
                    headers={[t("tableGroup"), t("tableTokens")]}
                    rows={[
                      [<><InlineCode>ui</InlineCode> (25)</>, t.rich("s6Sub2Row1", { code })],
                      [<><InlineCode>syntax</InlineCode> (12)</>, t.rich("s6Sub2Row2", { code })],
                      [<><InlineCode>terminal</InlineCode> (23)</>, t.rich("s6Sub2Row3", { code })],
                    ]}
                  />
                  <p>{t.rich("s6Sub2P1", { code, em })}</p>
                  <p>{t.rich("s6Sub2P2", { code, em })}</p>
                  <p>{t.rich("s6Sub2P3", { code, link: themeExampleLink })}</p>
                </DocsSubsection>
              </DocsSection>

              {/* ── TURN STATUS ─────────────────────────────────────────── */}

              <DocsSection id="turn-status" title={t("s7Title")}>
                <p>{t.rich("s7P1", { b })}</p>
                <p>{t("s7P2")}</p>
                <ol>
                  <li>{t.rich("s7Ol1", { code })}</li>
                  <li>{t("s7Ol2")}</li>
                  <li>{t.rich("s7Ol3", { code })}</li>
                  <li>{t.rich("s7Ol4", { code, em })}</li>
                </ol>
                <DocsTable
                  headers={[t("tableHarness"), t("tableFile"), t("tableFormat")]}
                  rows={[
                    ["Claude Code", <InlineCode key="c">~/.claude/settings.json</InlineCode>, t.rich("s7Row1", { code })],
                    ["Codex CLI", <InlineCode key="x">~/.codex/hooks.json</InlineCode>, t.rich("s7Row2", { b, code })],
                  ]}
                />
                <p>{t.rich("s7P3", { code })}</p>

                <DocsSubsection id="turn-status-events" title={t("s7Sub1Title")}>
                  <DocsTable
                    headers={[t("tableEvent"), "Claude", "Codex", t("tableStatus")]}
                    rows={[
                      [<InlineCode key="e">UserPromptSubmit</InlineCode>, "✓", "✓", t.rich("s7Sub1Row1", { code })],
                      [<InlineCode key="e">PreToolUse</InlineCode>, "✓", "✓", t.rich("s7Sub1Row2", { code })],
                      [<InlineCode key="e">PostToolUse</InlineCode>, "✓", "✓", <InlineCode key="s">working</InlineCode>],
                      [<InlineCode key="e">Notification</InlineCode>, "✓", "—", t.rich("s7Sub1Row4", { code })],
                      [<InlineCode key="e">PermissionRequest</InlineCode>, "—", "✓", <InlineCode key="s">waiting</InlineCode>],
                      [<InlineCode key="e">Stop</InlineCode>, "✓", "✓", <InlineCode key="s">idle</InlineCode>],
                      [<><InlineCode>SessionStart</InlineCode> / <InlineCode>SessionEnd</InlineCode></>, "✓", "✓", <InlineCode key="s">idle</InlineCode>],
                      [<><InlineCode>SubagentStart/Stop</InlineCode>, <InlineCode>PreCompact/PostCompact</InlineCode></>, "—", "✓", <strong key="s">{t("ignored")}</strong>],
                    ]}
                  />
                  <p>{t.rich("s7Sub1P1", { b, code })}</p>
                </DocsSubsection>

                <DocsSubsection id="turn-status-resume" title={t("s7Sub2Title")}>
                  <p>{t.rich("s7Sub2P1", { code })}</p>
                  <Callout variant="warning" title={t("s7Sub2CalloutTitle")}>
                    <p>{t.rich("s7Sub2CalloutBody", { em, code })}</p>
                  </Callout>
                </DocsSubsection>
              </DocsSection>

              {/* ── SOUNDS ──────────────────────────────────────────────── */}

              <DocsSection id="sounds" title={t("s8Title")}>
                <p>{t.rich("s8P1", { b })}</p>
              </DocsSection>

              {/* ── LANGUAGE ────────────────────────────────────────────── */}

              <DocsSection id="language" title={t("s9Title")}>
                <p>{t.rich("s9P1", { b })}</p>
              </DocsSection>

              {/* ── LINKS ───────────────────────────────────────────────── */}

              <DocsSection id="links" title={t("s10Title")}>
                <ul>
                  <li><Link href="/cockpit" className="text-accent underline">{t("s10Li1Text")}</Link> — {t("s10Li1Suffix")}</li>
                  <li><Link href="/tutorials/cockpit-layouts" className="text-accent underline">{t("s10Li2Text")}</Link> — {t.rich("s10Li2Suffix", { code })}</li>
                  <li><Link href="/tutorials/cockpit-team" className="text-accent underline">{t("s10Li3Text")}</Link>.</li>
                  <li><Link href="/docs" className="text-accent underline">{t("s10Li4Text")}</Link> — {t("s10Li4Suffix")}</li>
                  <li><a className="text-accent underline" href={COCKPIT_DOCS} target="_blank" rel="noopener noreferrer">{t("s10Li5Text")}</a> {t("s10Li5Suffix")}</li>
                  <li><a className="text-accent underline" href={GITHUB_URL} target="_blank" rel="noopener noreferrer">GitHub</a> — {t("s10Li6Suffix")}</li>
                </ul>
              </DocsSection>
            </article>
          </div>
        </div>
      </div>
      <RevealController />
    </div>
  );
}
