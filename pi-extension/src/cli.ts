/**
 * Standalone `remote-pi` CLI, run by index.ts when `dist/index.js` (the
 * package `bin`, and the `~/.local/bin/remote-pi` link target) is executed.
 *
 * Kept separate from the extension (extension.ts) so it starts without the
 * host packages: Pi installs extensions with peer dependencies omitted, and
 * extension.ts imports `@earendil-works/pi-*` / `typebox` at runtime. Only
 * import host-independent modules here (enforced by `cli_imports.test.ts`).
 */

import { realpathSync } from "node:fs";
import { fileURLToPath } from "node:url";
import type { ExtensionContext } from "@earendil-works/pi-coding-agent";
import {
  kDefaultRelayUrl,
  saveConfig,
  isValidRelayUrl,
  isWebSocketScheme,
} from "./config.js";
import { listPeers } from "./pairing/storage.js";
import { formatPeerInventory } from "./session/peer_inventory.js";
import { LOCAL_SESSION_NAME, sessionSockPath } from "./session/global_config.js";
import {
  _cmdClaudeCli,
  _cmdCreate,
  _cmdCron,
  _cmdDaemonRestart,
  _cmdDaemonSend,
  _cmdDaemonStart,
  _cmdDaemonStatus,
  _cmdDaemonStop,
  _cmdDaemonsList,
  _cmdInstall,
  _cmdRemove,
  _cmdUninstall,
  _inspectPeerRecord,
  _restartSupervisor,
  probeListPeers,
  type InspectedPeerRecord,
} from "./commands.js";

/** True when `moduleUrl` is the script Node was launched with. */
export function isDirectRun(moduleUrl: string): boolean {
  try {
    return fileURLToPath(moduleUrl) === realpathSync(process.argv[1] ?? "");
  } catch {
    return false;
  }
}

export async function runCli(argv: string[]): Promise<void> {
  const [subcmd, ...cliArgs] = argv;
  if (subcmd === "devices" || subcmd === "list") {
    const peers = (await listPeers())
      .map(_inspectPeerRecord)
      .filter((peer): peer is InspectedPeerRecord => peer !== null);
    if (peers.length === 0) { console.log("[remote-pi] No peers"); }
    else {
      for (const peer of peers) {
        console.log(`• ${peer.rawHandle.slice(0, 8)} — ${peer.record.name}`);
      }
    }
  } else if (subcmd === "revoke") {
    const shortid = (cliArgs[0] ?? "").trim();
    if (!shortid) {
      console.log("Usage: revoke <shortid>");
    } else {
      const matches = (await listPeers())
        .map(_inspectPeerRecord)
        .filter((peer): peer is InspectedPeerRecord => peer !== null)
        .filter((peer) => peer.rawHandle.startsWith(shortid));
      if (matches.length === 0) console.log("No peer matching that shortid");
      else if (matches.length > 1) console.log(`Ambiguous: ${matches.map((peer) => peer.rawHandle.slice(0, 8)).join(", ")}`);
      else {
        const peer = matches[0]!;
        const { removePeer } = await import("./pairing/storage.js");
        await removePeer(peer.rawHandle);
        console.log(`Revoked: ${peer.record.name} (${peer.rawHandle.slice(0, 8)}…)`);
      }
    }
  } else if (subcmd === "set-relay") {
    const raw = (cliArgs[0] ?? "").trim();
    if (!raw) {
      console.log(`Usage: set-relay <url> (default: ${kDefaultRelayUrl})`);
    } else if (isWebSocketScheme(raw)) {
      console.log(`Use http:// or https://. The extension converts to WebSocket automatically.`);
    } else if (!isValidRelayUrl(raw)) {
      console.log(`Invalid URL: ${raw}. Must start with http:// or https://`);
    } else {
      saveConfig({ relay: raw });
      console.log(`Relay set to ${raw}`);
    }
  } else if (subcmd === "create") {
    // Standalone: `remote-pi create <cwd> [--name "X"]`. The shell already
    // split the args and stripped the outer quotes, so an arg like
    // `Tmp Agent` arrives as a single element with embedded space. Re-add
    // quotes around any arg containing whitespace so the regex-based
    // parser (shared with the slash-command path) sees the same shape
    // as it would from a Pi interactive prompt.
    const joined = cliArgs.map((a) => (/\s/.test(a) ? `"${a}"` : a)).join(" ");
    await _cmdCreate(joined, {
      ui: { notify: (msg: string) => console.log(msg) } as unknown as ExtensionContext["ui"],
    });
  } else if (subcmd === "remove") {
    const id = (cliArgs[0] ?? "").trim();
    await _cmdRemove(id, {
      ui: { notify: (msg: string) => console.log(msg) } as unknown as ExtensionContext["ui"],
    });
  } else if (subcmd === "daemons") {
    // Mirror the slash handler: ask the supervisor when reachable,
    // fall back to registry-only when not.
    const stubCtx = { ui: { notify: (msg: string) => console.log(msg) } as unknown as ExtensionContext["ui"] };
    await _cmdDaemonsList(stubCtx);
  } else if (subcmd === "daemon") {
    // `remote-pi daemon <op> [args]`. Reuse the fleet-ops handlers — they
    // already accept a minimal ctx with `notify`.
    const op = cliArgs[0] ?? "";
    const rest = cliArgs.slice(1).map((a) => (/\s/.test(a) ? `"${a}"` : a)).join(" ");
    const stubCtx = { ui: { notify: (msg: string) => console.log(msg) } as unknown as ExtensionContext["ui"] };
    if      (op === "start")   { await _cmdDaemonStart(stubCtx, cliArgs[1]); }
    else if (op === "stop")    { await _cmdDaemonStop(stubCtx, cliArgs[1]); }
    else if (op === "restart") { await _cmdDaemonRestart(stubCtx, cliArgs[1]); }
    else if (op === "status")  { await _cmdDaemonStatus(stubCtx); }
    else if (op === "send")    { await _cmdDaemonSend(rest, stubCtx); }
    else {
      console.log("Usage: remote-pi daemon <start|stop|restart [<id>]|status|send <id> \"<text>\">");
    }
  } else if (subcmd === "cron") {
    // `remote-pi cron <op> [args]`. Re-quote args with spaces so the shared
    // parser sees the same shape as a Pi slash prompt.
    const joined = cliArgs.map((a) => (/\s/.test(a) ? `"${a}"` : a)).join(" ");
    const stubCtx = { ui: { notify: (msg: string) => console.log(msg) } as unknown as ExtensionContext["ui"] };
    await _cmdCron(joined, stubCtx);
  } else if (subcmd === "peers") {
    // Read-only roster of the local + cross-PC mesh. Unlike `devices` (which
    // reads paired phones from peers.json), the mesh roster lives only in the
    // running broker's memory, so we probe the UDS broker. The probe never
    // registers as a peer — it leaves no trace on the mesh (see
    // Broker._tryObserverProbe). Null = no broker reachable on this machine.
    const peers = await probeListPeers(sessionSockPath(LOCAL_SESSION_NAME));
    if (peers === null) {
      console.log("[remote-pi] Mesh offline — no agent is running on this machine.");
    } else {
      console.log(`[remote-pi] peers:\n${formatPeerInventory(peers)}`);
    }
  } else if (subcmd === "claude") {
    await _cmdClaudeCli(cliArgs);
  } else if (subcmd === "install") {
    // CLI mode = user installed via `npm install -g remote-pi`, so the
    // `remote-pi` / `pi-supervisord` bins are already on $PATH via npm's
    // global prefix. Explicit `linkCli: false` so we never stomp those
    // with symlinks pointing at a parallel Pi-extension install.
    const stubCtx = { ui: { notify: (msg: string) => console.log(msg) } as unknown as ExtensionContext["ui"] };
    // Propagate failure as a non-zero exit so callers (Cockpit / CI) detect it
    // — installService throws on a failed schtasks/launchctl/systemctl step.
    if (!_cmdInstall(stubCtx, { linkCli: false })) process.exit(1);
  } else if (subcmd === "uninstall") {
    const stubCtx = { ui: { notify: (msg: string) => console.log(msg) } as unknown as ExtensionContext["ui"] };
    // `linkCli: true` even from the CLI: unlinking is ALWAYS safe and must run
    // regardless of how install ran. `unlinkCliBinaries` only removes OUR
    // reserved symlinks (`remote-pi` / `pi-supervisord`) under `~/.local/bin`;
    // npm-global bins live in a different prefix and are never touched. So a
    // user who installed via the TUI (`/remote-pi install`, which links) and
    // uninstalls from a shell still gets the links cleaned up — the asymmetry
    // that left an orphaned `~/.local/bin/remote-pi` behind.
    _cmdUninstall(stubCtx, { linkCli: true });
  } else if (subcmd === "restart-supervisor") {
    _restartSupervisor();
  } else {
    console.log([
      "Usage: remote-pi <command>",
      "",
      "Daemon registry:",
      "  create <cwd> [--name \"Name\"]   Register a folder as a daemon",
      "  remove <id>                     Unregister a daemon",
      "  daemons                         List registered daemons",
      "",
      "Fleet control:",
      "  daemon start [<id>]             Start all daemons, or one by id",
      "  daemon stop [<id>]              Stop all daemons, or one by id",
      "  daemon restart [<id>]           Restart all daemons, or one by id",
      "  daemon status                   Show pid / uptime / restarts",
      "  daemon send <id> \"<text>\"       Send a prompt to a daemon",
      "  cron add <id> \"<expr>\" \"<txt>\"  Schedule a recurring prompt (≥60s; --tz, --wake)",
      "  cron list|run|remove|log        Manage scheduled prompts (needs the supervisor)",
      "",
      "Service:",
      "  install                         Install pi-supervisord as a system service",
      "  uninstall                       Remove the system service",
      "  restart-supervisor              Restart the pi-supervisord process",
      "",
      "Devices:",
      "  devices                         List paired phones (peers.json)",
      "  revoke <shortid>                Revoke a paired device",
      "",
      "Config:",
      "  set-relay <url>                 Set the relay URL (http:// or https://)",
      "",
      "Agent mesh:",
      "  peers                           List agents on the local + cross-PC mesh",
      "  claude [cwd]                    Start Claude Code connected to the agent mesh",
    ].join("\n"));
  }
}
