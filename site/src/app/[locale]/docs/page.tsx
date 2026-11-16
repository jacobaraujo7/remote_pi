import type { Metadata } from "next";
import type { ReactNode } from "react";
import { getTranslations, setRequestLocale } from "next-intl/server";
import { pageAlternates } from "@/i18n/alternates";
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

type Props = { params: Promise<{ locale: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { locale } = await params;
  const t = await getTranslations({ locale, namespace: "CockpitDocs" });
  return {
    title: t("meta.title"),
    description: t("meta.description"),
    alternates: pageAlternates(locale, "/docs"),
  };
}

const GITHUB_URL = "https://github.com/jacobaraujo7/remote_pi";
const COCKPIT_DOCS =
  "https://github.com/jacobaraujo7/remote_pi/tree/main/cockpit/docs";
const THEME_SCHEMA =
  "https://raw.githubusercontent.com/jacobaraujo7/remote_pi/main/cockpit/docs/theme.schema.json";
const TASKS_SCHEMA =
  "https://github.com/jacobaraujo7/remote_pi/blob/main/cockpit/docs/tasks.schema.json";
const THEME_EXAMPLE =
  "https://github.com/jacobaraujo7/remote_pi/blob/main/cockpit/docs/theme.example.json";

/* Inline tags used by the messages: <code1>, <a2>... Handlers live here so
   each message just spreads TAGS. Contents of <code*> are never translated. */
const TAGS = {
  code1: (c: ReactNode) => <InlineCode>{c}</InlineCode>,
  link1: (c: ReactNode) => (
    <Link href="/" className="text-accent underline">
      {c}
    </Link>
  ),
  link2: (c: ReactNode) => (
    <Link href="/remote-pi/docs" className="text-accent underline">
      {c}
    </Link>
  ),
  link3: (c: ReactNode) => (
    <Link href="/download" className="text-accent underline">
      {c}
    </Link>
  ),
  a1: (c: ReactNode) => (
    <a href="#remote" className="text-accent underline">
      {c}
    </a>
  ),
  link4: (c: ReactNode) => (
    <Link href="/remote-pi" className="text-accent underline">
      {c}
    </Link>
  ),
  em1: (c: ReactNode) => <em>{c}</em>,
  strong1: (c: ReactNode) => <strong>{c}</strong>,
  a2: (c: ReactNode) => (
    <a href="#databases" className="text-accent underline">
      {c}
    </a>
  ),
  a3: (c: ReactNode) => (
    <a href="#layouts" className="text-accent underline">
      {c}
    </a>
  ),
  a4: (c: ReactNode) => (
    <a
      className="text-accent underline"
      href={TASKS_SCHEMA}
      target="_blank"
      rel="noopener noreferrer"
    >
      {c}
    </a>
  ),
  a5: (c: ReactNode) => (
    <a
      className="text-accent underline"
      href={THEME_EXAMPLE}
      target="_blank"
      rel="noopener noreferrer"
    >
      {c}
    </a>
  ),
  link5: (c: ReactNode) => (
    <Link href="/tutorials/cockpit-layouts" className="text-accent underline">
      {c}
    </Link>
  ),
  link6: (c: ReactNode) => (
    <Link href="/tutorials/cockpit-telemetry" className="text-accent underline">
      {c}
    </Link>
  ),
  a6: (c: ReactNode) => (
    <a
      className="text-accent underline"
      href={COCKPIT_DOCS}
      target="_blank"
      rel="noopener noreferrer"
    >
      {c}
    </a>
  ),
  a7: (c: ReactNode) => (
    <a
      className="text-accent underline"
      href={GITHUB_URL}
      target="_blank"
      rel="noopener noreferrer"
    >
      {c}
    </a>
  ),
};

type Translate = Awaited<ReturnType<typeof getTranslations<"CockpitDocs">>>;

function buildToc(t: Translate): TocItem[] {
  return [
    { id: "install", label: t("toc.install") },
    {
      id: "cli",
      label: t.rich("toc.cli", TAGS),
      sub: [
        { id: "cli-targets", label: t("toc.cliTargets") },
        { id: "cli-commands", label: t("toc.cliCommands") },
        { id: "cli-read", label: t("toc.cliRead") },
      ],
    },
    {
      id: "layouts",
      label: t.rich("toc.layouts", TAGS),
      sub: [
        { id: "layouts-fields", label: t("toc.layoutsFields") },
        { id: "layouts-merge", label: t("toc.layoutsMerge") },
      ],
    },
    {
      id: "tasks",
      label: t("toc.tasks"),
      sub: [
        { id: "tasks-file", label: t("toc.tasksFile") },
        { id: "tasks-fields", label: t("toc.tasksFields") },
      ],
    },
    {
      id: "databases",
      label: t("toc.databases"),
    },
    {
      id: "documents",
      label: t("toc.documents"),
      sub: [
        { id: "documents-notebook", label: t("toc.documentsNotebook") },
        { id: "documents-http", label: t.rich("toc.documentsHttp", TAGS) },
        { id: "documents-more", label: t("toc.documentsMore") },
      ],
    },
    {
      id: "env",
      label: (
        <>
          <InlineCode>.env.cockpit</InlineCode>
        </>
      ),
      sub: [
        { id: "env-redaction", label: t("toc.envRedaction") },
        { id: "env-blocked", label: t("toc.envBlocked") },
        { id: "env-accounts", label: t("toc.envAccounts") },
      ],
    },
    {
      id: "themes",
      label: t("toc.themes"),
      sub: [
        { id: "themes-file", label: t("toc.themesFile") },
        { id: "themes-tokens", label: t("toc.themesTokens") },
      ],
    },
    {
      id: "turn-status",
      label: t("toc.turnStatus"),
      sub: [
        { id: "turn-status-events", label: t("toc.turnStatusEvents") },
        { id: "turn-status-resume", label: t("toc.turnStatusResume") },
      ],
    },
    {
      id: "remote",
      label: t("toc.remote"),
      sub: [
        { id: "remote-install", label: t("toc.remoteInstall") },
        { id: "remote-service", label: t("toc.remoteService") },
        { id: "remote-troubleshooting", label: t("toc.remoteTroubleshooting") },
      ],
    },
    { id: "sounds", label: t("toc.sounds") },
    { id: "language", label: t("toc.language") },
    { id: "links", label: t("toc.links") },
  ];
}

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

export default async function CockpitDocsPage({ params }: Props) {
  const { locale } = await params;
  setRequestLocale(locale);
  const t = await getTranslations({ locale, namespace: "CockpitDocs" });
  return (
    <div className="page">
      <div className="page-body">
        <div className="wrap">
          <header className="page-head reveal">
            <span className="eyebrow">{t("intro.span1")}</span>
            <h1>{t("intro.h11")}</h1>
            <div className="meta-line">
              <span>{t("intro.span2")}</span>
              <span>{t("intro.span3")}</span>
            </div>
            <p className="lede">{t.rich("intro.p1", TAGS)}</p>
          </header>

          <div className="docs-layout">
            <DocsToc items={buildToc(t)} />

            <article className="prose docs-article">
              {/* ── INSTALL ─────────────────────────────────────────────── */}

              <DocsSection id="install" title={t("install.title")}>
                <p>{t.rich("install.p1", TAGS)}</p>
                <p>{t("install.p2")}</p>
                <p>{t.rich("install.p3", TAGS)}</p>
              </DocsSection>

              {/* ── CLI ─────────────────────────────────────────────────── */}

              <DocsSection id="cli" title={t("cli.title")}>
                <p>{t.rich("cli.p1", TAGS)}</p>
                <p>{t.rich("cli.p2", TAGS)}</p>

                <DocsSubsection
                  id="cli-targets"
                  title={t("cli_cliTargets.title")}
                >
                  <p>{t.rich("cli_cliTargets.p1", TAGS)}</p>
                  <DocsTable
                    headers={[t("cli_cliTargets.th1"), t("cli_cliTargets.th2")]}
                    rows={[
                      [
                        <InlineCode key="t">--tab-id &lt;id&gt;</InlineCode>,
                        <>{t.rich("cli_cliTargets.cell1", TAGS)}</>,
                      ],
                      [
                        <InlineCode key="f">--focused</InlineCode>,
                        <>{t.rich("cli_cliTargets.cell2", TAGS)}</>,
                      ],
                      [
                        <InlineCode key="e">--enter</InlineCode>,
                        <>{t.rich("cli_cliTargets.cell3", TAGS)}</>,
                      ],
                    ]}
                  />
                  <Callout
                    variant="warning"
                    title={t("cli_cliTargets.callout1")}
                  >
                    <p>{t.rich("cli_cliTargets.p2", TAGS)}</p>
                  </Callout>
                </DocsSubsection>

                <DocsSubsection
                  id="cli-commands"
                  title={t("cli_cliCommands.title")}
                >
                  <DocsTable
                    headers={[
                      t("cli_cliCommands.th1"),
                      t("cli_cliCommands.th2"),
                    ]}
                    rows={[
                      [
                        <InlineCode key="c">
                          send [--tab-id id] [--enter] &lt;text&gt;
                        </InlineCode>,
                        t("cli_cliCommands.td1"),
                      ],
                      [
                        <InlineCode key="c">
                          send-key [--tab-id id] &lt;Key&gt;…
                        </InlineCode>,
                        <>{t.rich("cli_cliCommands.cell1", TAGS)}</>,
                      ],
                      [
                        <InlineCode key="c">open &lt;file&gt;</InlineCode>,
                        <>{t.rich("cli_cliCommands.cell2", TAGS)}</>,
                      ],
                      [
                        <InlineCode key="c">
                          new-tab [--cwd dir] [--title name] [--split h|v]
                        </InlineCode>,
                        <>{t.rich("cli_cliCommands.cell3", TAGS)}</>,
                      ],
                      [
                        <InlineCode key="c">
                          read-tab [label|tab-id]
                        </InlineCode>,
                        <>{t.rich("cli_cliCommands.cell4", TAGS)}</>,
                      ],
                      [
                        <InlineCode key="c">
                          read-task &lt;task-id&gt;
                        </InlineCode>,
                        t("cli_cliCommands.td2"),
                      ],
                      [
                        <InlineCode key="c">list-tabs [--json]</InlineCode>,
                        <>{t.rich("cli_cliCommands.cell5", TAGS)}</>,
                      ],
                      [
                        <InlineCode key="c">
                          list-workspaces [--json]
                        </InlineCode>,
                        t("cli_cliCommands.td3"),
                      ],
                      [
                        <InlineCode key="c">list-tasks [--json]</InlineCode>,
                        <>{t.rich("cli_cliCommands.cell6", TAGS)}</>,
                      ],
                      [
                        <InlineCode key="c">
                          db &lt;list|schema|query|run|execute&gt;
                        </InlineCode>,
                        <>{t.rich("cli_cliCommands.cell7", TAGS)}</>,
                      ],
                      [
                        <InlineCode key="c">
                          redis [browse] --db conn
                        </InlineCode>,
                        t("cli_cliCommands.td4"),
                      ],
                      [
                        <InlineCode key="c">
                          mongo [browse] --db conn [--database name]
                        </InlineCode>,
                        t("cli_cliCommands.td5"),
                      ],
                      [
                        <InlineCode key="c">
                          orchestrate &lt;file.ckp&gt; [--json]
                        </InlineCode>,
                        <>{t.rich("cli_cliCommands.cell8", TAGS)}</>,
                      ],
                      [
                        <InlineCode key="c">
                          install-skill [--force]
                        </InlineCode>,
                        t("cli_cliCommands.td6"),
                      ],
                    ]}
                  />
                  <CodeBlock
                    label={t("cli_cliCommands.label1")}
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

                <DocsSubsection id="cli-read" title={t("cli_cliRead.title")}>
                  <p>{t.rich("cli_cliRead.p1", TAGS)}</p>
                  <DocsTable
                    headers={[
                      t("cli_cliRead.th1"),
                      t("cli_cliRead.th2"),
                      t("cli_cliRead.th3"),
                    ]}
                    rows={[
                      [
                        <InlineCode key="l">--lines N</InlineCode>,
                        "100",
                        t("cli_cliRead.td1"),
                      ],
                      [
                        <InlineCode key="o">--offset N</InlineCode>,
                        "0",
                        t("cli_cliRead.td2"),
                      ],
                      [
                        <InlineCode key="s">--from-start</InlineCode>,
                        t("cli_cliRead.td3"),
                        t("cli_cliRead.td4"),
                      ],
                    ]}
                  />
                  <p>{t.rich("cli_cliRead.p2", TAGS)}</p>
                </DocsSubsection>
              </DocsSection>

              {/* ── .ckp LAYOUTS ────────────────────────────────────────── */}

              <DocsSection id="layouts" title={t("layouts.title")}>
                <p>{t.rich("layouts.p1", TAGS)}</p>
                <p>{t("layouts.p2")}</p>
                <ul>
                  <li>{t.rich("layouts.li1", TAGS)}</li>
                  <li>{t.rich("layouts.li2", TAGS)}</li>
                  <li>{t.rich("layouts.li3", TAGS)}</li>
                </ul>
                <CodeBlock label="dev.ckp" language="yaml" code={CKP_EXAMPLE} />

                <DocsSubsection
                  id="layouts-fields"
                  title={t("layouts_layoutsFields.title")}
                >
                  <p>{t.rich("layouts_layoutsFields.p1", TAGS)}</p>
                  <DocsTable
                    headers={[
                      t("layouts_layoutsFields.th1"),
                      t("layouts_layoutsFields.th2"),
                      t("layouts_layoutsFields.th3"),
                      t("layouts_layoutsFields.th4"),
                    ]}
                    rows={[
                      [
                        <InlineCode key="n">name</InlineCode>,
                        t("layouts_layoutsFields.td1"),
                        "—",
                        t("layouts_layoutsFields.td2"),
                      ],
                      [
                        <InlineCode key="c">cwd</InlineCode>,
                        t("layouts_layoutsFields.td3"),
                        <InlineCode key="d">.</InlineCode>,
                        <>{t.rich("layouts_layoutsFields.cell1", TAGS)}</>,
                      ],
                      [
                        <InlineCode key="s">split</InlineCode>,
                        t("layouts_layoutsFields.td4"),
                        <InlineCode key="d">tab</InlineCode>,
                        <>{t.rich("layouts_layoutsFields.cell2", TAGS)}</>,
                      ],
                      [
                        <InlineCode key="cm">command</InlineCode>,
                        t("layouts_layoutsFields.td5"),
                        "—",
                        t("layouts_layoutsFields.td6"),
                      ],
                      [
                        <InlineCode key="p">platforms</InlineCode>,
                        t("layouts_layoutsFields.td7"),
                        t("layouts_layoutsFields.td8"),
                        <>{t.rich("layouts_layoutsFields.cell3", TAGS)}</>,
                      ],
                    ]}
                  />
                </DocsSubsection>

                <DocsSubsection
                  id="layouts-merge"
                  title={t("layouts_layoutsMerge.title")}
                >
                  <ul>
                    <li>{t.rich("layouts_layoutsMerge.li1", TAGS)}</li>
                    <li>{t.rich("layouts_layoutsMerge.li2", TAGS)}</li>
                    <li>{t.rich("layouts_layoutsMerge.li3", TAGS)}</li>
                    <li>{t.rich("layouts_layoutsMerge.li4", TAGS)}</li>
                  </ul>
                  <p>{t.rich("layouts_layoutsMerge.p1", TAGS)}</p>
                </DocsSubsection>
              </DocsSection>

              {/* ── TASK RUN ────────────────────────────────────────────── */}

              <DocsSection id="tasks" title={t("tasks.title")}>
                <p>{t.rich("tasks.p1", TAGS)}</p>
                <ul>
                  <li>{t.rich("tasks.li1", TAGS)}</li>
                  <li>{t.rich("tasks.li2", TAGS)}</li>
                </ul>
                <Callout variant="note" title={t("tasks.callout1")}>
                  <p>{t.rich("tasks.p2", TAGS)}</p>
                </Callout>

                <DocsSubsection
                  id="tasks-file"
                  title={t("tasks_tasksFile.title")}
                >
                  <p>{t.rich("tasks_tasksFile.p1", TAGS)}</p>
                  <p>{t.rich("tasks_tasksFile.p2", TAGS)}</p>
                  <CodeBlock
                    label=".cockpit/tasks.json"
                    language="jsonc"
                    code={TASKS_EXAMPLE}
                  />
                </DocsSubsection>

                <DocsSubsection
                  id="tasks-fields"
                  title={t("tasks_tasksFields.title")}
                >
                  <p>{t.rich("tasks_tasksFields.p1", TAGS)}</p>
                  <DocsTable
                    headers={[
                      t("tasks_tasksFields.th1"),
                      t("tasks_tasksFields.th2"),
                      t("tasks_tasksFields.th3"),
                      t("tasks_tasksFields.th4"),
                    ]}
                    rows={[
                      [
                        <InlineCode key="l">label</InlineCode>,
                        t("tasks_tasksFields.td1"),
                        "—",
                        <>{t.rich("tasks_tasksFields.cell1", TAGS)}</>,
                      ],
                      [
                        <InlineCode key="c">command</InlineCode>,
                        t("tasks_tasksFields.td2"),
                        "—",
                        t("tasks_tasksFields.td3"),
                      ],
                      [
                        <InlineCode key="a">args</InlineCode>,
                        t("tasks_tasksFields.td4"),
                        <InlineCode key="d">[]</InlineCode>,
                        t("tasks_tasksFields.td5"),
                      ],
                      [
                        <InlineCode key="w">cwd</InlineCode>,
                        t("tasks_tasksFields.td6"),
                        t("tasks_tasksFields.td7"),
                        <>{t.rich("tasks_tasksFields.cell2", TAGS)}</>,
                      ],
                      [
                        <InlineCode key="p">platforms</InlineCode>,
                        t("tasks_tasksFields.td8"),
                        t("tasks_tasksFields.td9"),
                        <>{t.rich("tasks_tasksFields.cell3", TAGS)}</>,
                      ],
                      [
                        <InlineCode key="k">kind</InlineCode>,
                        t("tasks_tasksFields.td10"),
                        <InlineCode key="d">oneShot</InlineCode>,
                        <>{t.rich("tasks_tasksFields.cell4", TAGS)}</>,
                      ],
                      [
                        <InlineCode key="i">interactiveKeys</InlineCode>,
                        t("tasks_tasksFields.td11"),
                        <InlineCode key="d">[]</InlineCode>,
                        <>{t.rich("tasks_tasksFields.cell5", TAGS)}</>,
                      ],
                      [
                        <InlineCode key="wa">watch</InlineCode>,
                        t("tasks_tasksFields.td12"),
                        <InlineCode key="d">null</InlineCode>,
                        <>{t.rich("tasks_tasksFields.cell6", TAGS)}</>,
                      ],
                      [
                        <InlineCode key="pp">progressPatterns</InlineCode>,
                        t("tasks_tasksFields.td13"),
                        <InlineCode key="d">[]</InlineCode>,
                        <>{t.rich("tasks_tasksFields.cell7", TAGS)}</>,
                      ],
                      [
                        <InlineCode key="pr">profiles</InlineCode>,
                        t("tasks_tasksFields.td14"),
                        <InlineCode key="d">[]</InlineCode>,
                        <>{t.rich("tasks_tasksFields.cell8", TAGS)}</>,
                      ],
                    ]}
                  />
                  <Callout
                    variant="warning"
                    title={t("tasks_tasksFields.callout1")}
                  >
                    <p>{t.rich("tasks_tasksFields.p2", TAGS)}</p>
                  </Callout>
                </DocsSubsection>
              </DocsSection>

              {/* ── DATABASES ───────────────────────────────────────────── */}

              <DocsSection id="databases" title={t("databases.title")}>
                <p>{t.rich("databases.p1", TAGS)}</p>
                <p>{t.rich("databases.p2", TAGS)}</p>
                <CodeBlock
                  label={t("databases.label1")}
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
                <Callout variant="note" title={t("databases.callout1")}>
                  <p>{t.rich("databases.p3", TAGS)}</p>
                </Callout>
              </DocsSection>

              {/* ── DOCUMENTS ───────────────────────────────────────────── */}

              <DocsSection id="documents" title={t("documents.title")}>
                <p>{t.rich("documents.p1", TAGS)}</p>

                <DocsSubsection
                  id="documents-notebook"
                  title={t("documents_documentsNotebook.title")}
                >
                  <p>{t.rich("documents_documentsNotebook.p1", TAGS)}</p>
                  <CodeBlock
                    label="notes.notebook/2026-09-07-ssh-tunnel.md"
                    language="markdown"
                    code={`---
title: SSH tunnel on the host
tags: [relay, agent]
created: 2026-09-07T10:12
updated: 2026-09-07T11:40
---

Free markdown body.`}
                  />
                  <DocsTable
                    headers={[
                      t("documents_documentsNotebook.th1"),
                      t("documents_documentsNotebook.th2"),
                      t("documents_documentsNotebook.th3"),
                    ]}
                    rows={[
                      [
                        <InlineCode key="t">title</InlineCode>,
                        t("documents_documentsNotebook.td1"),
                        t("documents_documentsNotebook.td2"),
                      ],
                      [
                        <InlineCode key="g">tags</InlineCode>,
                        t("documents_documentsNotebook.td3"),
                        <>
                          {t.rich("documents_documentsNotebook.cell1", TAGS)}
                        </>,
                      ],
                      [
                        <InlineCode key="c">created</InlineCode>,
                        t("documents_documentsNotebook.td4"),
                        <InlineCode key="f">YYYY-MM-DDTHH:MM</InlineCode>,
                      ],
                      [
                        <InlineCode key="u">updated</InlineCode>,
                        t("documents_documentsNotebook.td5"),
                        t("documents_documentsNotebook.td6"),
                      ],
                    ]}
                  />
                  <p>{t.rich("documents_documentsNotebook.p2", TAGS)}</p>
                  <p>{t.rich("documents_documentsNotebook.p3", TAGS)}</p>
                  <CodeBlock
                    label={t("documents_documentsNotebook.label1")}
                    prompt
                    code={`cockpit note add notes.notebook --title "SSH tunnel on the host" --tag relay \
  --body "The host opens the tunnel, not the client."

# read the body from stdin, and list what is there
cockpit note add notes.notebook --title "Session summary" --body - <<'NOTE'
Everything that changed today.
NOTE
cockpit note list notes.notebook`}
                  />
                  <Callout
                    variant="note"
                    title={t("documents_documentsNotebook.callout1")}
                  >
                    <p>{t.rich("documents_documentsNotebook.p4", TAGS)}</p>
                  </Callout>
                </DocsSubsection>

                <DocsSubsection
                  id="documents-http"
                  title={t("documents_documentsHttp.title")}
                >
                  <p>{t.rich("documents_documentsHttp.p1", TAGS)}</p>
                  <CodeBlock
                    label="api/users.http"
                    code={`@base = https://api.example.com
@token = a-token-for-this-file

### list users
GET {{base}}/users
Authorization: Bearer {{token}}

### create one
POST {{base}}/users
Content-Type: application/json

{ "name": "Ada" }`}
                  />
                  <p>{t.rich("documents_documentsHttp.p2", TAGS)}</p>
                  <CodeBlock
                    label={t("documents_documentsHttp.label1")}
                    prompt
                    code={`cockpit http list api/users.http
cockpit http run api/users.http --request "list users"`}
                  />
                </DocsSubsection>

                <DocsSubsection
                  id="documents-more"
                  title={t("documents_documentsMore.title")}
                >
                  <ul>
                    <li>{t.rich("documents_documentsMore.li1", TAGS)}</li>
                    <li>{t.rich("documents_documentsMore.li2", TAGS)}</li>
                    <li>{t.rich("documents_documentsMore.li3", TAGS)}</li>
                  </ul>
                </DocsSubsection>
              </DocsSection>

              {/* ── .env.cockpit ────────────────────────────────────────── */}

              <DocsSection id="env" title={t("env.title")}>
                <p>{t.rich("env.p1", TAGS)}</p>
                <CodeBlock
                  label=".env.cockpit"
                  code={`OPENAI_API_KEY=sk-...
GITHUB_TOKEN=ghp_...
DATABASE_URL=postgres://user:pass@localhost/app`}
                />

                <DocsSubsection
                  id="env-redaction"
                  title={t("env_envRedaction.title")}
                >
                  <p>{t.rich("env_envRedaction.p1", TAGS)}</p>
                  <p>{t("env_envRedaction.p2")}</p>
                </DocsSubsection>

                <DocsSubsection
                  id="env-blocked"
                  title={t("env_envBlocked.title")}
                >
                  <p>{t.rich("env_envBlocked.p1", TAGS)}</p>
                  <CodeBlock
                    label={t("env_envBlocked.label1")}
                    code={`PATH  SHELL  HOME  ZDOTDIR  BASH_ENV  ENV  PROMPT_COMMAND  IFS  LD_*  DYLD_*`}
                  />
                  <p>{t.rich("env_envBlocked.p2", TAGS)}</p>
                </DocsSubsection>

                <DocsSubsection
                  id="env-accounts"
                  title={t("env_envAccounts.title")}
                >
                  <p>{t("env_envAccounts.p1")}</p>
                  <CodeBlock
                    label="work-project/.env.cockpit"
                    code={`CLAUDE_CONFIG_DIR=/Users/me/.claude-work
# Codex uses its own variable
CODEX_HOME=/Users/me/.codex-work`}
                  />
                  <p>{t.rich("env_envAccounts.p2", TAGS)}</p>
                </DocsSubsection>
              </DocsSection>

              {/* ── THEMES ──────────────────────────────────────────────── */}

              <DocsSection id="themes" title={t("themes.title")}>
                <p>{t.rich("themes.p1", TAGS)}</p>

                <DocsSubsection
                  id="themes-file"
                  title={t("themes_themesFile.title")}
                >
                  <ul>
                    <li>{t.rich("themes_themesFile.li1", TAGS)}</li>
                    <li>{t.rich("themes_themesFile.li2", TAGS)}</li>
                    <li>{t.rich("themes_themesFile.li3", TAGS)}</li>
                  </ul>
                  <CodeBlock
                    label={t("themes_themesFile.label1")}
                    language="json"
                    code={THEME_SHAPE}
                  />
                  <DocsTable
                    headers={[
                      t("themes_themesFile.th1"),
                      t("themes_themesFile.th2"),
                      t("themes_themesFile.th3"),
                    ]}
                    rows={[
                      [
                        <InlineCode key="i">id</InlineCode>,
                        t("themes_themesFile.td1"),
                        <>{t.rich("themes_themesFile.cell1", TAGS)}</>,
                      ],
                      [
                        <InlineCode key="n">name</InlineCode>,
                        t("themes_themesFile.td2"),
                        t("themes_themesFile.td3"),
                      ],
                      [
                        <InlineCode key="a">author</InlineCode>,
                        t("themes_themesFile.td4"),
                        t("themes_themesFile.td5"),
                      ],
                      [
                        <InlineCode key="v">version</InlineCode>,
                        t("themes_themesFile.td6"),
                        t("themes_themesFile.td7"),
                      ],
                      [
                        <InlineCode key="e">extends</InlineCode>,
                        t("themes_themesFile.td8"),
                        <>{t.rich("themes_themesFile.cell2", TAGS)}</>,
                      ],
                      [
                        <InlineCode key="va">variants</InlineCode>,
                        t("themes_themesFile.td9"),
                        <>{t.rich("themes_themesFile.cell3", TAGS)}</>,
                      ],
                    ]}
                  />
                  <p>{t.rich("themes_themesFile.p1", TAGS)}</p>
                  <CodeBlock
                    label="acme.violet.json"
                    language="json"
                    code={THEME_MINIMAL}
                  />
                  <p>{t.rich("themes_themesFile.p2", TAGS)}</p>
                </DocsSubsection>

                <DocsSubsection
                  id="themes-tokens"
                  title={t("themes_themesTokens.title")}
                >
                  <DocsTable
                    headers={[
                      t("themes_themesTokens.th1"),
                      t("themes_themesTokens.th2"),
                    ]}
                    rows={[
                      [
                        <>
                          <InlineCode>ui</InlineCode> (25)
                        </>,
                        <>{t.rich("themes_themesTokens.cell1", TAGS)}</>,
                      ],
                      [
                        <>
                          <InlineCode>syntax</InlineCode> (12)
                        </>,
                        <>
                          <InlineCode>background</InlineCode>{" "}
                          <InlineCode>base</InlineCode>{" "}
                          <InlineCode>comment</InlineCode>{" "}
                          <InlineCode>keyword</InlineCode>{" "}
                          <InlineCode>string</InlineCode>{" "}
                          <InlineCode>number</InlineCode>{" "}
                          <InlineCode>class</InlineCode>{" "}
                          <InlineCode>builtin</InlineCode>{" "}
                          <InlineCode>function</InlineCode>{" "}
                          <InlineCode>variable</InlineCode>{" "}
                          <InlineCode>meta</InlineCode>{" "}
                          <InlineCode>deletion</InlineCode>
                        </>,
                      ],
                      [
                        <>
                          <InlineCode>terminal</InlineCode> (23)
                        </>,
                        <>{t.rich("themes_themesTokens.cell2", TAGS)}</>,
                      ],
                    ]}
                  />
                  <p>{t.rich("themes_themesTokens.p1", TAGS)}</p>
                  <p>{t.rich("themes_themesTokens.p2", TAGS)}</p>
                  <p>{t.rich("themes_themesTokens.p3", TAGS)}</p>
                </DocsSubsection>
              </DocsSection>

              {/* ── TURN STATUS ─────────────────────────────────────────── */}

              <DocsSection id="turn-status" title={t("turnStatus.title")}>
                <p>{t.rich("turnStatus.p1", TAGS)}</p>
                <p>{t("turnStatus.p2")}</p>
                <ol>
                  <li>{t.rich("turnStatus.li1", TAGS)}</li>
                  <li>{t("turnStatus.li2")}</li>
                  <li>{t.rich("turnStatus.li3", TAGS)}</li>
                  <li>{t.rich("turnStatus.li4", TAGS)}</li>
                </ol>
                <DocsTable
                  headers={[
                    t("turnStatus.th1"),
                    t("turnStatus.th2"),
                    t("turnStatus.th3"),
                  ]}
                  rows={[
                    [
                      t("turnStatus.td1"),
                      <InlineCode key="c">~/.claude/settings.json</InlineCode>,
                      <>{t.rich("turnStatus.cell1", TAGS)}</>,
                    ],
                    [
                      t("turnStatus.td2"),
                      <InlineCode key="x">~/.codex/hooks.json</InlineCode>,
                      <>{t.rich("turnStatus.cell2", TAGS)}</>,
                    ],
                  ]}
                />
                <p>{t.rich("turnStatus.p3", TAGS)}</p>

                <DocsSubsection
                  id="turn-status-events"
                  title={t("turnStatus_turnStatusEvents.title")}
                >
                  <DocsTable
                    headers={[
                      t("turnStatus_turnStatusEvents.th1"),
                      t("turnStatus_turnStatusEvents.th2"),
                      t("turnStatus_turnStatusEvents.th3"),
                      t("turnStatus_turnStatusEvents.th4"),
                    ]}
                    rows={[
                      [
                        <InlineCode key="e">UserPromptSubmit</InlineCode>,
                        "✓",
                        "✓",
                        <>
                          {t.rich("turnStatus_turnStatusEvents.cell1", TAGS)}
                        </>,
                      ],
                      [
                        <InlineCode key="e">PreToolUse</InlineCode>,
                        "✓",
                        "✓",
                        <>
                          {t.rich("turnStatus_turnStatusEvents.cell2", TAGS)}
                        </>,
                      ],
                      [
                        <InlineCode key="e">PostToolUse</InlineCode>,
                        "✓",
                        "✓",
                        <InlineCode key="s">working</InlineCode>,
                      ],
                      [
                        <InlineCode key="e">Notification</InlineCode>,
                        "✓",
                        "—",
                        <>
                          {t.rich("turnStatus_turnStatusEvents.cell3", TAGS)}
                        </>,
                      ],
                      [
                        <InlineCode key="e">PermissionRequest</InlineCode>,
                        "—",
                        "✓",
                        <InlineCode key="s">waiting</InlineCode>,
                      ],
                      [
                        <InlineCode key="e">Stop</InlineCode>,
                        "✓",
                        "✓",
                        <InlineCode key="s">idle</InlineCode>,
                      ],
                      [
                        <>
                          <InlineCode>SessionStart</InlineCode> /{" "}
                          <InlineCode>SessionEnd</InlineCode>
                        </>,
                        "✓",
                        "✓",
                        <InlineCode key="s">idle</InlineCode>,
                      ],
                      [
                        <>
                          <InlineCode>SubagentStart/Stop</InlineCode>,{" "}
                          <InlineCode>PreCompact/PostCompact</InlineCode>
                        </>,
                        "—",
                        "✓",
                        <strong key="s">
                          {t("turnStatus_turnStatusEvents.strong1")}
                        </strong>,
                      ],
                    ]}
                  />
                  <p>{t.rich("turnStatus_turnStatusEvents.p1", TAGS)}</p>
                </DocsSubsection>

                <DocsSubsection
                  id="turn-status-resume"
                  title={t("turnStatus_turnStatusResume.title")}
                >
                  <p>{t.rich("turnStatus_turnStatusResume.p1", TAGS)}</p>
                  <Callout
                    variant="warning"
                    title={t("turnStatus_turnStatusResume.callout1")}
                  >
                    <p>{t.rich("turnStatus_turnStatusResume.p2", TAGS)}</p>
                  </Callout>
                </DocsSubsection>
              </DocsSection>

              {/* ── REMOTE HOSTS ────────────────────────────────────────── */}

              <DocsSection id="remote" title={t("remote.title")}>
                <p>{t.rich("remote.p1", TAGS)}</p>
                <p>{t.rich("remote.p2", TAGS)}</p>
                <p>{t("remote.p3")}</p>
                <div className="overflow-x-auto">
                  <table>
                    <thead>
                      <tr>
                        <th>{t("remote.th1")}</th>
                        <th>{t("remote.th2")}</th>
                        <th>{t("remote.th3")}</th>
                      </tr>
                    </thead>
                    <tbody>
                      <tr>
                        <td>{t("remote.td1")}</td>
                        <td>{t("remote.td2")}</td>
                        <td>{t("remote.td3")}</td>
                      </tr>
                      <tr>
                        <td>{t("remote.td4")}</td>
                        <td>{t("remote.td5")}</td>
                        <td>{t("remote.td6")}</td>
                      </tr>
                      <tr>
                        <td>{t("remote.td7")}</td>
                        <td>{t("remote.td8")}</td>
                        <td>{t("remote.td9")}</td>
                      </tr>
                      <tr>
                        <td>{t("remote.td10")}</td>
                        <td>{t("remote.td11")}</td>
                        <td>{t("remote.td12")}</td>
                      </tr>
                      <tr>
                        <td>{t("remote.td13")}</td>
                        <td>{t("remote.td14")}</td>
                        <td>{t("remote.td15")}</td>
                      </tr>
                    </tbody>
                  </table>
                </div>
                <p>{t("remote.p4")}</p>

                <DocsSubsection
                  id="remote-install"
                  title={t("remote_remoteInstall.title")}
                >
                  <p>{t("remote_remoteInstall.p1")}</p>
                  <CodeBlock
                    label={t("remote_remoteInstall.label1")}
                    language="bash"
                    code={`curl -fsSL https://remote-pi.jacobmoura.work/cockpit-server.sh | bash
# or straight from GitHub (the URL above redirects here):
curl -fsSL https://raw.githubusercontent.com/jacobaraujo7/remote_pi/main/cockpit/install-server.sh | bash`}
                  />
                  <p>{t.rich("remote_remoteInstall.p2", TAGS)}</p>
                  <Callout>
                    <p>{t.rich("remote_remoteInstall.p3", TAGS)}</p>
                  </Callout>
                </DocsSubsection>

                <DocsSubsection
                  id="remote-service"
                  title={t("remote_remoteService.title")}
                >
                  <p>{t.rich("remote_remoteService.p1", TAGS)}</p>
                  <CodeBlock
                    label={t("remote_remoteService.label1")}
                    language="bash"
                    code={`# at install time
curl -fsSL https://remote-pi.jacobmoura.work/cockpit-server.sh | bash -s -- --service

# or later (the installer links cockpit-server into ~/.local/bin)
cockpit-server service install
cockpit-server service status
cockpit-server service uninstall`}
                  />
                  <p>{t.rich("remote_remoteService.p2", TAGS)}</p>
                </DocsSubsection>

                <DocsSubsection
                  id="remote-troubleshooting"
                  title={t("remote_remoteTroubleshooting.title")}
                >
                  <ul>
                    <li>{t.rich("remote_remoteTroubleshooting.li1", TAGS)}</li>
                    <li>{t.rich("remote_remoteTroubleshooting.li2", TAGS)}</li>
                    <li>{t.rich("remote_remoteTroubleshooting.li3", TAGS)}</li>
                    <li>{t.rich("remote_remoteTroubleshooting.li4", TAGS)}</li>
                    <li>{t.rich("remote_remoteTroubleshooting.li5", TAGS)}</li>
                  </ul>
                </DocsSubsection>
              </DocsSection>

              {/* ── SOUNDS ──────────────────────────────────────────────── */}

              <DocsSection id="sounds" title={t("sounds.title")}>
                <p>{t.rich("sounds.p1", TAGS)}</p>
              </DocsSection>

              {/* ── LANGUAGE ────────────────────────────────────────────── */}

              <DocsSection id="language" title={t("language.title")}>
                <p>{t.rich("language.p1", TAGS)}</p>
              </DocsSection>

              {/* ── LINKS ───────────────────────────────────────────────── */}

              <DocsSection id="links" title={t("links.title")}>
                <ul>
                  <li>{t.rich("links.li1", TAGS)}</li>
                  <li>{t.rich("links.li2", TAGS)}</li>
                  <li>{t.rich("links.li3", TAGS)}</li>
                  <li>
                    <Link
                      href="/tutorials/cockpit-team"
                      className="text-accent underline"
                    >
                      {t("links.link1")}
                    </Link>
                    .
                  </li>
                  <li>{t.rich("links.li4", TAGS)}</li>
                  <li>{t.rich("links.li5", TAGS)}</li>
                  <li>{t.rich("links.li6", TAGS)}</li>
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
