import type { Metadata } from "next";
import Link from "next/link";
import { DocsSection, InlineCode } from "@/components/docs-shell";
import { CodeBlock } from "@/components/code-block";
import { Callout } from "@/components/callout";
import { Pager } from "@/components/pager";
import { RevealController } from "@/components/landing/reveal-controller";

export const metadata: Metadata = {
  title: "Telemetry: let agents query errors, not terminals",
  description:
    "Cockpit keeps a per-workspace store of what your processes print: errors grouped by fingerprint, JSON logs with their fields, and the lines around them. Agents query it with one CLI instead of reading thousands of terminal lines.",
};

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

export default function CockpitTelemetryTutorial() {
  return (
    <div className="page">
      <div className="page-body">
        <div className="wrap">
          <div className="tut">
            <header className="page-head reveal" style={{ maxWidth: "none" }}>
              <div className="flex flex-wrap items-center gap-3">
                <span className="inline-flex items-center rounded-full border border-accent/40 bg-accent/15 px-3 py-1 text-xs font-semibold uppercase tracking-[0.15em] text-accent">
                  Cockpit · debugging
                </span>
              </div>
              <span className="eyebrow" style={{ marginTop: 14 }}>
                Tutorial · Cockpit
              </span>
              <h1>Telemetry: let agents query errors, not terminals</h1>
              <p className="lede">
                A dev server prints thousands of lines. Somewhere in there is
                the one error that matters, and the agent debugging your app
                has to read all of it to find it. Cockpit keeps a structured,
                per-workspace store of what your processes print, groups errors
                by fingerprint, and gives agents one CLI to ask{" "}
                <em>what broke, where, and is it new</em>. No SDK, no account,
                nothing leaves your machine.
              </p>
            </header>

            <article className="prose">
              <DocsSection id="what" title="What you get">
                <ul className="ml-6 list-disc space-y-2">
                  <li>
                    <strong className="text-fg">A Telemetry tab</strong> in the
                    right panel (next to Files, Search, Database, Tasks): cases
                    grouped by project and run, with counts, file:line, and
                    tags for <em>new</em> and <em>regression</em>. Clicking a
                    case opens it in the center pane with the stack, the JSON
                    log printed right before it, occurrences per run, and the
                    raw context lines.
                  </li>
                  <li>
                    <strong className="text-fg">Triage that agents respect.</strong>{" "}
                    Mark a case resolved and it disappears; if it comes back in
                    a later run it returns flagged as a regression. Ignore a
                    case and agents stop seeing it too.
                  </li>
                  <li>
                    <strong className="text-fg">
                      <InlineCode>cockpit telemetry</InlineCode>
                    </strong>
                    , a CLI that answers in compact JSON: errors, logs, one
                    case in detail, wait-until-it-stops-happening.
                  </li>
                </ul>
              </DocsSection>

              <DocsSection id="how" title="1. Where the data comes from">
                <p>
                  Every task you run from{" "}
                  <InlineCode>.cockpit/tasks.json</InlineCode> feeds the store
                  by default. Anything else enters when you prefix the command
                  with <InlineCode>cockpit telemetry</InlineCode>. That works in
                  a terminal tab (colors and keys preserved) and from an
                  agent&rsquo;s own shell, which is the case that matters most:
                  an agent running <InlineCode>flutter test</InlineCode> gets
                  the three failing tests with file:line instead of the whole
                  output.
                </p>
                <CodeBlock code={WRAPPER} label="terminal" language="bash" />
                <Callout title="Nothing is captured behind your back">
                  Cockpit never taps a terminal you did not ask it to observe.
                  Tasks are observed because Cockpit is the parent process; the
                  wrapper is the explicit opt-in for everything else.
                </Callout>
              </DocsSection>

              <DocsSection id="loop" title="2. The agent loop">
                <p>
                  The wrapper prints a summary line at exit. From there the
                  agent narrows down instead of reading up:
                </p>
                <CodeBlock code={LOOP} label="terminal" language="bash" />
                <p>
                  Useful filters: <InlineCode>--new</InlineCode> (never seen in
                  earlier runs of the same command),{" "}
                  <InlineCode>--since-edit</InlineCode> (since your last save in
                  the editor), <InlineCode>--before ev_xxxx --window 5s</InlineCode>{" "}
                  (what happened right before an event),{" "}
                  <InlineCode>--project</InlineCode> in a monorepo. Replies are
                  capped and tell the agent how to narrow further. The skill
                  installed by <InlineCode>cockpit install-skill</InlineCode>{" "}
                  teaches all of this to Claude Code and friends.
                </p>
              </DocsSection>

              <DocsSection id="speak" title="3. Make your project speak telemetry">
                <p>
                  Stack traces and error blocks are recognized as they are
                  (Dart, Flutter, Node, Python, Rust, Go, test runners). For
                  everything else there is one rule: make the project&rsquo;s
                  logger emit <strong className="text-fg">JSON Lines</strong> to
                  stdout. Every ecosystem already does this (pino, structlog,
                  slog, tracing). Cockpit only knows the field aliases:
                </p>
                <CodeBlock code={JSONL} label="one log line" language="json" />
                <CodeBlock code={DART} label="Flutter example" language="dart" />
                <p>
                  Keep <InlineCode>msg</InlineCode> fixed and put variable data
                  in fields: <InlineCode>&quot;msg&quot;:&quot;order failed&quot;,&quot;orderId&quot;:&quot;91c&quot;</InlineCode>{" "}
                  groups into one case; <InlineCode>&quot;order 91c failed&quot;</InlineCode>{" "}
                  becomes one case per order.
                </p>
                <Callout title="Do not gate logs on Cockpit">
                  The app should behave the same inside and outside Cockpit.
                  Control verbosity with your own knob (
                  <InlineCode>LOG_LEVEL</InlineCode>, <InlineCode>kReleaseMode</InlineCode>
                  ), set per task through <InlineCode>env</InlineCode>.
                  A <InlineCode>COCKPIT=1</InlineCode> check would not even
                  reach a phone or a container.
                </Callout>
                <CodeBlock code={TASKS} label=".cockpit/tasks.json" language="json" />
              </DocsSection>

              <DocsSection id="extras" title="4. Flutter, OpenTelemetry, HTTP proxy">
                <ul className="ml-6 list-disc space-y-2">
                  <li>
                    <strong className="text-fg">Flutter, zero code.</strong> When
                    a run prints the Dart VM Service URI, Cockpit attaches as a
                    second client and reads <InlineCode>dart:developer log()</InlineCode>{" "}
                    records and the framework&rsquo;s structured errors. An
                    error that also reached the console counts once.
                  </li>
                  <li>
                    <strong className="text-fg">OpenTelemetry.</strong> Observed
                    processes get <InlineCode>OTEL_EXPORTER_OTLP_ENDPOINT</InlineCode>{" "}
                    and <InlineCode>OTEL_SERVICE_NAME</InlineCode> in their
                    environment. An app with the OTel SDK (or Node&rsquo;s
                    auto-instrumentation) sends logs and spans to a local,
                    loopback-only receiver; failed spans become cases too.
                  </li>
                  <li>
                    <strong className="text-fg">HTTP proxy.</strong> Point the
                    frontend at the proxy port and every request/response is
                    recorded with status, duration, redacted bodies and an
                    injected <InlineCode>x-request-id</InlineCode>. Mark a
                    reproduction window and replay it after the fix.
                  </li>
                </ul>
                <CodeBlock code={CONFIG} label=".cockpit/telemetry.json" language="json" />
              </DocsSection>

              <DocsSection id="privacy" title="Privacy and retention">
                <p>
                  The store is a SQLite file per workspace in Cockpit&rsquo;s
                  local cache, never inside your repository and never
                  synchronized. Secrets are redacted on the way in
                  (authorization headers, cookies, tokens, JWTs, passwords).
                  Old runs are dropped after 7 days or 256 MB, oldest first.
                  Delete anything from the Telemetry tab at any time.
                </p>
                <p>
                  From here: put{" "}
                  <Link
                    href="/tutorials/cockpit-team"
                    className="text-accent underline"
                  >
                    a team of agents
                  </Link>{" "}
                  on top of it, or read the{" "}
                  <Link href="/docs" className="text-accent underline">
                    Cockpit reference
                  </Link>
                  .
                </p>
              </DocsSection>
            </article>

            <Pager
              prev={{
                href: "/tutorials/cockpit-team",
                label: "An agent team in Cockpit",
              }}
              next={{ href: "/docs", label: "Cockpit reference" }}
            />
          </div>
        </div>
      </div>
      <RevealController />
    </div>
  );
}
