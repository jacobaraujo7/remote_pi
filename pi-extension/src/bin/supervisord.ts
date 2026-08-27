#!/usr/bin/env node
/**
 * `pi-supervisord` — long-running daemon supervisor.
 *
 * Entry point of the `pi-supervisord` binary (plan/26 W2). Run by
 * systemd/launchd in production, or directly during dev:
 *
 *   pnpm build
 *   node dist/bin/supervisord.js
 *
 * Once running, it:
 *   - Reads `~/.pi/remote/daemons.json`
 *   - Spawns `pi --mode rpc -e <remote-pi/dist/extension.js>` per entry
 *   - Listens on `~/.pi/remote/supervisor.sock` for CLI control requests
 *   - Restarts crashed children with exponential backoff
 *
 * Exits cleanly on SIGTERM/SIGINT (used by `remote-pi uninstall`).
 */
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { Supervisor, SupervisorAlreadyRunningError } from "../daemon/supervisor.js";

const HELP_TEXT = `pi-supervisord — Remote Pi daemon supervisor

Usage: pi-supervisord

Runs the long-lived supervisor: reads ~/.pi/remote/daemons.json, spawns one
\`pi --mode rpc\` child per entry, and listens on ~/.pi/remote/supervisor.sock
for control requests from the \`remote-pi\` CLI.

This binary takes NO arguments — it is normally launched by systemd/launchd
(via \`remote-pi install\`), not by hand. Manage the fleet with:
  remote-pi daemon start | stop | restart | status
  remote-pi daemons

Options:
  -h, --help      Show this help and exit
  -v, --version   Print version and exit
`;

async function main(): Promise<void> {
  // Guard: any stray argument used to fall through and start a FULL
  // supervisor (a `pi-supervisord --help` once ran for days). Handle the
  // conventional flags explicitly and reject unknown args instead of
  // silently spawning the daemon fleet.
  const args = process.argv.slice(2);
  if (args.includes("-h") || args.includes("--help")) {
    process.stdout.write(HELP_TEXT);
    return;
  }
  if (args.includes("-v") || args.includes("--version")) {
    process.stdout.write("pi-supervisord (remote-pi)\n");
    return;
  }
  if (args.length > 0) {
    process.stderr.write(
      `pi-supervisord: unexpected argument(s): ${args.join(" ")}\n` +
      "This binary takes no arguments. Run `pi-supervisord --help`.\n",
    );
    process.exit(2);
  }

  // The supervisor needs to point each spawned Pi at the extension
  // entry it's bundled with. We're at `dist/bin/supervisord.js` after
  // build; the Pi-only extension entry is the sibling `dist/extension.js`.
  const here = fileURLToPath(import.meta.url);
  const distRoot = dirname(dirname(here));  // dist/bin → dist
  const extensionPath = join(distRoot, "extension.js");

  const supervisor = new Supervisor({ extensionPath });
  await supervisor.start();
  process.stderr.write(
    `[pi-supervisord] up — UDS: ~/.pi/remote/supervisor.sock, extension: ${extensionPath}\n`,
  );

  const shutdown = async (signal: string) => {
    process.stderr.write(`[pi-supervisord] received ${signal}, shutting down\n`);
    await supervisor.stop();
    process.exit(0);
  };
  process.on("SIGTERM", () => void shutdown("SIGTERM"));
  process.on("SIGINT", () => void shutdown("SIGINT"));
}

main().catch((err) => {
  // "Already running" is a normal, expected condition (systemd/launchd may
  // race a manual start, or the user double-launches) — not a crash. Report
  // it calmly and exit 0 so service managers don't flag a failure loop.
  if (err instanceof SupervisorAlreadyRunningError) {
    process.stderr.write(`[pi-supervisord] ${err.message}\n`);
    process.exit(0);
  }
  process.stderr.write(`[pi-supervisord] fatal: ${String(err)}\n`);
  process.exit(1);
});
