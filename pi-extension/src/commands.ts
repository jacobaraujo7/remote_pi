/**
 * Command handlers shared by the `/remote-pi` slash commands (extension.ts) and
 * the standalone `remote-pi` CLI (cli.ts).
 *
 * The CLI must start without the host packages (`@earendil-works/pi-*`,
 * `typebox`): they are peerDependencies, and Pi-managed installs omit peers.
 * So this module — and everything it imports — may reference host packages
 * with `import type` only. `cli_imports.test.ts` enforces that.
 */

import { createHash } from "node:crypto";
import { existsSync, unlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { createInterface } from "node:readline";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import type { ExtensionContext } from "@earendil-works/pi-coding-agent";
import type { PeerRecord } from "./pairing/storage.js";
import {
  canonicalizeEd25519PublicKey,
  decodeEd25519PublicKey,
  publicKeyFingerprint,
} from "./mesh/encoding.js";
import { addDaemon, listDaemons, removeDaemon } from "./daemon/registry.js";
import { callSupervisor, supervisorOnline, SupervisorOfflineError } from "./daemon/client.js";
import type { ControlRequest, DaemonInfo } from "./daemon/control_protocol.js";
import { installService, uninstallService, linkCliBinaries, unlinkCliBinaries, LAUNCHD_LABEL, SYSTEMD_UNIT, WINDOWS_TASK_NAME } from "./daemon/install.js";
import {
  defaultAgentName,
  loadLocalConfig,
  localConfigExists,
  saveLocalConfig,
} from "./session/local_config.js";

// ── Peer lookup helpers ───────────────────────────────────────────────────────

export interface InspectedPeerRecord {
  readonly record: PeerRecord;
  readonly rawHandle: string;
  readonly runtimeKey: string | null;
}

function _rawOwnerFingerprint(rawValue: unknown): string {
  let fingerprintInput: string;
  if (typeof rawValue === "string") {
    fingerprintInput = rawValue;
  } else {
    try {
      const serialized = JSON.stringify(rawValue);
      const type = rawValue === null ? "null" : typeof rawValue;
      fingerprintInput = `${type}:${serialized ?? ""}`;
    } catch {
      fingerprintInput = `${typeof rawValue}:unserializable`;
    }
  }
  return createHash("sha256")
    .update(fingerprintInput, "utf8")
    .digest("hex")
    .slice(0, 8);
}

export function _runtimeOwnerFingerprint(runtimeKey: string): string {
  try {
    return publicKeyFingerprint(
      decodeEd25519PublicKey(runtimeKey, "Owner runtime key"),
    );
  } catch {
    // Relay authentication guarantees canonical keys in production. This
    // fallback keeps diagnostics metadata-only at defensive/test boundaries.
    return _rawOwnerFingerprint(runtimeKey);
  }
}

export function _inspectPeerRecord(record: unknown): InspectedPeerRecord | null {
  if (!record || typeof record !== "object") {
    const fingerprint = _rawOwnerFingerprint(record);
    console.warn(`[remote-pi] event=invalid_owner_record owner_fp=${fingerprint}`);
    return null;
  }

  const candidate = record as Partial<Record<keyof PeerRecord, unknown>>;
  const rawHandle = candidate.remote_epk;
  if (typeof rawHandle !== "string") {
    const fingerprint = _rawOwnerFingerprint(rawHandle);
    console.warn(`[remote-pi] event=invalid_owner_record owner_fp=${fingerprint}`);
    return null;
  }

  const safeRecord: PeerRecord = {
    name: typeof candidate.name === "string" ? candidate.name : "Unknown Owner",
    remote_epk: rawHandle,
    paired_at: typeof candidate.paired_at === "string" ? candidate.paired_at : "",
  };
  try {
    const runtimeKey = canonicalizeEd25519PublicKey(
      rawHandle,
      "stored Owner public key",
    );
    return { record: safeRecord, rawHandle, runtimeKey };
  } catch {
    const fingerprint = _rawOwnerFingerprint(rawHandle);
    console.warn(`[remote-pi] event=invalid_owner_record owner_fp=${fingerprint}`);
    return { record: safeRecord, rawHandle, runtimeKey: null };
  }
}

// ── Daemon registry commands (plan/26 Wave 1) ─────────────────────────────────

/**
 * `/remote-pi create [<cwd>] [--name <name>]`
 *
 * Promotes a folder to a daemon entry in `~/.pi/remote/daemons.json`. The
 * cwd is **always normalized to an absolute realpath** before storage —
 * `~/Movies`, `./Movies`, `../foo/Movies` all collapse to a single
 * canonical entry. Relative paths resolve against the Pi process's
 * current working directory, not the slash-command's `ctx.cwd`.
 *
 * Side effects on the cwd's local config (`<cwd>/.pi/remote-pi/config.json`):
 *   - If the config doesn't exist: created with `auto_start_relay=true`
 *     (mandatory for daemons) and `agent_name` from `--name` if provided.
 *   - If the config already exists: left untouched. Re-running `create`
 *     on an existing daemon is idempotent at this layer; the registry
 *     itself rejects duplicate cwds.
 */
export async function _cmdCreate(arg: string, ctx: Pick<ExtensionContext, "ui">): Promise<void> {
  // Parse `[cwd] [--name "value with spaces" | --name word]` in any order.
  // The first non-flag token is the cwd; the rest of the line after
  // `--name` (quoted or unquoted) is the display name.
  const nameMatch = arg.match(/--name\s+"([^"]+)"|--name\s+(\S+)/);
  const name = nameMatch ? (nameMatch[1] ?? nameMatch[2]) : undefined;
  const cwdRaw = arg.replace(/--name\s+"[^"]+"|--name\s+\S+/, "").trim();
  if (!cwdRaw) {
    ctx.ui.notify(
      "[remote-pi] Usage: /remote-pi create <absolute-or-relative-cwd> [--name \"Display name\"]",
      "warning",
    );
    return;
  }

  let result: { id: string; cwd: string; name: string };
  try {
    result = addDaemon(cwdRaw, name);
  } catch (err) {
    ctx.ui.notify(`[remote-pi] create failed: ${String(err)}`, "error");
    return;
  }

  // No local `.pi/remote-pi/config.json` is written anymore — the name lives
  // in the registry and the supervisor injects the full config (agent_name,
  // auto_start_relay true) via REMOTE_PI_DIRECT_CONFIG when it spawns the
  // daemon. The cwd needs no init folder.

  ctx.ui.notify(
    `[remote-pi] Daemon registered: id=${result.id} name="${result.name}" cwd=${result.cwd}`,
    "info",
  );

  // Auto-start: register alone used to leave the daemon idle until the next
  // supervisor restart (the reported bug — `create` didn't run anything). Ask
  // the supervisor to spawn THIS daemon now; it reads the name from the
  // registry and injects the config via env. When the supervisor is offline we
  // keep the
  // registration and tell the user it'll boot on the next supervisor start.
  try {
    await callSupervisor({ op: "start", id: result.id });
    ctx.ui.notify(`[remote-pi] Daemon started: id=${result.id}`, "info");
  } catch (err) {
    if (err instanceof SupervisorOfflineError) {
      ctx.ui.notify(
        `[remote-pi] Registered, but the supervisor is offline — not running yet. ` +
        `Run \`remote-pi install\` (or start \`pi-supervisord\`); it auto-starts on the next supervisor boot.`,
        "warning",
      );
      return;
    }
    ctx.ui.notify(`[remote-pi] Registered, but auto-start failed: ${String(err)}`, "error");
  }
}

/**
 * `/remote-pi remove <id>`
 *
 * Unregisters a daemon by its 8-hex-char id (the same id printed by
 * `/remote-pi create` and `/remote-pi daemons`). The cwd's local config
 * stays on disk — re-creating later with the same cwd is a no-op
 * because the existing config wins.
 */
export async function _cmdRemove(arg: string, ctx: Pick<ExtensionContext, "ui">): Promise<void> {
  const id = arg.trim();
  if (!id) {
    ctx.ui.notify(
      "[remote-pi] Usage: /remote-pi remove <id>. Run /remote-pi daemons to see ids.",
      "warning",
    );
    return;
  }

  // Prefer the supervisor's `unregister`: it STOPS the running child (SIGTERM →
  // SIGKILL) BEFORE deleting the registry entry. Removing only the registry
  // (the old behaviour) left an orphaned `pi --mode rpc` process running with
  // nothing left to manage it — the reported bug. Fall back to a registry-only
  // removal when the supervisor is offline (no managed process to stop anyway).
  try {
    const data = await callSupervisor({ op: "unregister", id });
    if (!data.removed) {
      const known = listDaemons().map((d) => d.id).join(", ") || "(none)";
      ctx.ui.notify(`[remote-pi] No daemon with id "${id}". Known ids: ${known}`, "warning");
      return;
    }
    ctx.ui.notify(
      `[remote-pi] Daemon removed + process stopped: id=${id} cwd=${data.cwd}. ` +
      `Local config at ${data.cwd}/.pi/remote-pi/config.json was kept.`,
      "info",
    );
    return;
  } catch (err) {
    if (!(err instanceof SupervisorOfflineError)) {
      ctx.ui.notify(`[remote-pi] remove failed: ${String(err)}`, "error");
      return;
    }
    // Supervisor offline — fall through to registry-only removal below.
  }

  let result: { removed: boolean; cwd?: string };
  try {
    result = removeDaemon(id);
  } catch (err) {
    ctx.ui.notify(`[remote-pi] remove failed: ${String(err)}`, "error");
    return;
  }

  if (!result.removed) {
    const known = listDaemons().map((d) => d.id).join(", ") || "(none)";
    ctx.ui.notify(`[remote-pi] No daemon with id "${id}". Known ids: ${known}`, "warning");
    return;
  }

  ctx.ui.notify(
    `[remote-pi] Daemon removed from registry: id=${id} cwd=${result.cwd}. ` +
    `Supervisor was offline, so any running process was NOT stopped. Local config kept.`,
    "warning",
  );
}

// ── Fleet-ops commands (plan/26 W2) — talk to the supervisor over UDS ─────────
//
// Every command here is a thin wrapper around `callSupervisor(...)`. When
// the supervisor isn't running we fall back to a friendly hint instead of
// the raw error, so the user can't get stuck on "what's wrong?".

function _notifyOffline(ctx: Pick<ExtensionContext, "ui">, err: SupervisorOfflineError): void {
  ctx.ui.notify(`[remote-pi] ${err.message}`, "warning");
}

function _formatDaemonTable(daemons: DaemonInfo[]): string {
  if (daemons.length === 0) return "(no daemons registered)";
  const rows = daemons.map((d) => {
    const uptime = d.uptime_s !== undefined ? `${d.uptime_s}s` : "—";
    const pid = d.pid !== undefined ? String(d.pid) : "—";
    const restarts = d.restart_count ?? 0;
    return `  ${d.id}  ${d.state.padEnd(8)}  pid=${pid}  up=${uptime}  restarts=${restarts}  ${d.name}  ${d.cwd}`;
  });
  return rows.join("\n");
}

/**
 * `/remote-pi daemons` — registry + runtime state in one view. When the
 * supervisor is offline we still show registry-only output (state =
 * "stopped" everywhere), so the user can see what's configured even
 * before `install`.
 */
export async function _cmdDaemonsList(ctx: Pick<ExtensionContext, "ui">): Promise<void> {
  if (!(await supervisorOnline())) {
    const registry = listDaemons();
    if (registry.length === 0) {
      ctx.ui.notify("[remote-pi] No daemons registered. Run /remote-pi create <cwd>.", "info");
      return;
    }
    const rows = registry.map((d) => {
      const cfg = loadLocalConfig(d.cwd);
      const name = cfg.agent_name ?? defaultAgentName(d.cwd);
      return `  ${d.id}  ${name}  ${d.cwd}  (supervisor offline)`;
    }).join("\n");
    ctx.ui.notify(`[remote-pi] Daemons (registry only — run install to bring supervisor up):\n${rows}`, "info");
    return;
  }
  try {
    const data = await callSupervisor({ op: "list" });
    ctx.ui.notify(`[remote-pi] Daemons:\n${_formatDaemonTable(data.daemons)}`, "info");
  } catch (err) {
    if (err instanceof SupervisorOfflineError) { _notifyOffline(ctx, err); return; }
    ctx.ui.notify(`[remote-pi] daemons failed: ${String(err)}`, "error");
  }
}

export async function _cmdDaemonStatus(ctx: Pick<ExtensionContext, "ui">): Promise<void> {
  try {
    const data = await callSupervisor({ op: "status" });
    ctx.ui.notify(`[remote-pi] Fleet status:\n${_formatDaemonTable(data.daemons)}`, "info");
  } catch (err) {
    if (err instanceof SupervisorOfflineError) { _notifyOffline(ctx, err); return; }
    ctx.ui.notify(`[remote-pi] status failed: ${String(err)}`, "error");
  }
}

export async function _cmdDaemonStart(ctx: Pick<ExtensionContext, "ui">, id?: string): Promise<void> {
  try {
    if (id) {
      const data = await callSupervisor({ op: "start", id });
      ctx.ui.notify(
        data.started
          ? `[remote-pi] Started daemon ${id} (${data.state}).`
          : `[remote-pi] Daemon ${id} already ${data.state}.`,
        "info",
      );
      return;
    }
    const data = await callSupervisor({ op: "start_all" });
    ctx.ui.notify(
      `[remote-pi] Started ${data.started.length} daemon(s), ` +
      `${data.already_running.length} already running.`,
      "info",
    );
  } catch (err) {
    if (err instanceof SupervisorOfflineError) { _notifyOffline(ctx, err); return; }
    ctx.ui.notify(`[remote-pi] start failed: ${String(err)}`, "error");
  }
}

export async function _cmdDaemonStop(ctx: Pick<ExtensionContext, "ui">, id?: string): Promise<void> {
  try {
    if (id) {
      const data = await callSupervisor({ op: "stop", id });
      ctx.ui.notify(
        data.stopped
          ? `[remote-pi] Stopped daemon ${id}.`
          : `[remote-pi] Daemon ${id} already ${data.state}.`,
        "info",
      );
      return;
    }
    const data = await callSupervisor({ op: "stop_all" });
    ctx.ui.notify(
      `[remote-pi] Stopped ${data.stopped.length} daemon(s), ` +
      `${data.already_stopped.length} already stopped.`,
      "info",
    );
  } catch (err) {
    if (err instanceof SupervisorOfflineError) { _notifyOffline(ctx, err); return; }
    ctx.ui.notify(`[remote-pi] stop failed: ${String(err)}`, "error");
  }
}

export async function _cmdDaemonRestart(ctx: Pick<ExtensionContext, "ui">, id?: string): Promise<void> {
  try {
    if (id) {
      const data = await callSupervisor({ op: "restart", id });
      ctx.ui.notify(`[remote-pi] Restarted daemon ${id} (${data.state}).`, "info");
      return;
    }
    const data = await callSupervisor({ op: "restart_all" });
    ctx.ui.notify(`[remote-pi] Restarted ${data.restarted.length} daemon(s).`, "info");
  } catch (err) {
    if (err instanceof SupervisorOfflineError) { _notifyOffline(ctx, err); return; }
    ctx.ui.notify(`[remote-pi] restart failed: ${String(err)}`, "error");
  }
}

/**
 * `/remote-pi daemon send <id> "<text>"` — injects a prompt into a
 * running daemon via its RPC stdin. The agent processes the prompt as
 * if a user typed it; output flows back via the relay/mesh, not here.
 *
 * Fire-and-forget at this layer — the CLI just confirms delivery.
 */
export async function _cmdDaemonSend(arg: string, ctx: Pick<ExtensionContext, "ui">): Promise<void> {
  // Parse `<id> <text...>` — id is the first token, rest is the prompt.
  // The text may be quoted; if so, strip the outer quotes. Otherwise
  // take the entire remainder verbatim.
  const m = arg.match(/^(\S+)\s+(?:"([^"]*)"|(.*))$/);
  if (!m) {
    ctx.ui.notify(
      "[remote-pi] Usage: /remote-pi daemon send <id> \"<prompt text>\"",
      "warning",
    );
    return;
  }
  const id = m[1]!;
  const text = (m[2] ?? m[3] ?? "").trim();
  if (!text) {
    ctx.ui.notify("[remote-pi] daemon send: prompt text is empty.", "warning");
    return;
  }
  try {
    const data = await callSupervisor({ op: "send", id, text });
    if (data.delivered) {
      ctx.ui.notify(`[remote-pi] Sent to ${id}: ${text.slice(0, 60)}${text.length > 60 ? "…" : ""}`, "info");
    } else {
      ctx.ui.notify(`[remote-pi] daemon ${id} did not accept the prompt (not running?)`, "warning");
    }
  } catch (err) {
    if (err instanceof SupervisorOfflineError) { _notifyOffline(ctx, err); return; }
    ctx.ui.notify(`[remote-pi] daemon send failed: ${String(err)}`, "error");
  }
}

// ── Cron — scheduled prompts for daemons (plan/39) ──────────────────────────

/** Splits an arg string into tokens, honoring double-quoted groups. */
function _tokenizeArgs(s: string): string[] {
  const out: string[] = [];
  const re = /"([^"]*)"|(\S+)/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(s)) !== null) out.push(m[1] !== undefined ? m[1] : m[2]!);
  return out;
}

/**
 * `/remote-pi cron <add|list|remove|enable|disable|run|log>` — schedules
 * recurring prompts to daemons via the supervisor. All subcommands require the
 * supervisor running (offline → friendly notice, not a crash).
 */
export async function _cmdCron(arg: string, ctx: Pick<ExtensionContext, "ui">): Promise<void> {
  const trimmed = arg.trim();
  const sp = trimmed.indexOf(" ");
  const sub = (sp === -1 ? trimmed : trimmed.slice(0, sp)).toLowerCase();
  const rest = sp === -1 ? "" : trimmed.slice(sp + 1).trim();
  try {
    switch (sub) {
      case "":
      case "list":    return await _cronList(ctx);
      case "add":     return await _cronAdd(rest, ctx);
      case "remove":
      case "rm":      return await _cronMutate({ op: "cron_remove", job_id: rest.trim() }, rest.trim(), ctx);
      case "enable":  return await _cronMutate({ op: "cron_enable", job_id: rest.trim(), enabled: true }, rest.trim(), ctx);
      case "disable": return await _cronMutate({ op: "cron_enable", job_id: rest.trim(), enabled: false }, rest.trim(), ctx);
      case "run":     return await _cronRun(rest.trim(), ctx);
      case "log":     return await _cronLog(rest, ctx);
      default:
        ctx.ui.notify("[remote-pi] Usage: /remote-pi cron <add|list|remove|enable|disable|run|log>", "warning");
    }
  } catch (err) {
    if (err instanceof SupervisorOfflineError) {
      ctx.ui.notify(
        "[remote-pi] Cron needs the supervisor running. Run `remote-pi install` " +
        "(or start `pi-supervisord`).",
        "warning",
      );
      return;
    }
    ctx.ui.notify(`[remote-pi] cron ${sub || "list"} failed: ${String(err)}`, "error");
  }
}

async function _cronAdd(rest: string, ctx: Pick<ExtensionContext, "ui">): Promise<void> {
  const toks = _tokenizeArgs(rest);
  let tz: string | undefined;
  let wake = false;
  let skipBusy = true;
  let catchup = false;
  const pos: string[] = [];
  for (let i = 0; i < toks.length; i++) {
    const t = toks[i]!;
    if (t === "--wake") wake = true;
    else if (t === "--no-skip-busy") skipBusy = false;
    else if (t === "--catchup") catchup = true;
    else if (t === "--tz") tz = toks[++i];
    else pos.push(t);
  }
  const [daemonId, schedule, prompt] = pos;
  if (!daemonId || !schedule || !prompt) {
    ctx.ui.notify(
      '[remote-pi] Usage: /remote-pi cron add <daemonId> "<cron-expr>" "<prompt>" ' +
      "[--tz Area/City] [--wake] [--no-skip-busy] [--catchup]",
      "warning",
    );
    return;
  }
  const req: Extract<ControlRequest, { op: "cron_add" }> = {
    op: "cron_add", daemon_id: daemonId, schedule, prompt,
  };
  if (tz) req.tz = tz;
  if (wake) req.wake = true;
  if (!skipBusy) req.skip_if_busy = false;
  if (catchup) req.catchup = true;
  const data = await callSupervisor(req);
  ctx.ui.notify(
    `[remote-pi] Cron ${data.job.id} added → daemon ${daemonId}: "${schedule}"` +
    `${tz ? ` (${tz})` : ""}. Next run: ${data.job.next_run ?? "?"}`,
    "info",
  );
}

async function _cronList(ctx: Pick<ExtensionContext, "ui">): Promise<void> {
  const data = await callSupervisor({ op: "cron_list" });
  if (data.jobs.length === 0) {
    ctx.ui.notify("[remote-pi] No cron jobs.", "info");
    return;
  }
  const lines = data.jobs.map((j) =>
    `${j.enabled ? "✓" : "✗"} ${j.id}  "${j.schedule}"${j.tz ? ` (${j.tz})` : ""}  → ${j.daemon_id}  ` +
    `next:${j.next_run ?? "?"}  last:${j.last_status ?? "—"}${j.last_run ? `@${j.last_run}` : ""}`,
  );
  ctx.ui.notify(`[remote-pi] Cron jobs (${data.jobs.length}):\n${lines.join("\n")}`, "info");
}

async function _cronMutate(
  req: Extract<ControlRequest, { op: "cron_remove" | "cron_enable" }>,
  jobId: string,
  ctx: Pick<ExtensionContext, "ui">,
): Promise<void> {
  if (!jobId) {
    ctx.ui.notify(`[remote-pi] Usage: /remote-pi cron ${req.op === "cron_remove" ? "remove" : "enable|disable"} <jobId>`, "warning");
    return;
  }
  if (req.op === "cron_remove") {
    const data = await callSupervisor(req);
    ctx.ui.notify(data.removed ? `[remote-pi] Cron ${jobId} removed.` : `[remote-pi] No cron job ${jobId}.`, data.removed ? "info" : "warning");
  } else {
    const data = await callSupervisor(req);
    ctx.ui.notify(
      data.updated ? `[remote-pi] Cron ${jobId} ${data.enabled ? "enabled" : "disabled"}.` : `[remote-pi] No cron job ${jobId}.`,
      data.updated ? "info" : "warning",
    );
  }
}

async function _cronRun(jobId: string, ctx: Pick<ExtensionContext, "ui">): Promise<void> {
  if (!jobId) {
    ctx.ui.notify("[remote-pi] Usage: /remote-pi cron run <jobId>", "warning");
    return;
  }
  const data = await callSupervisor({ op: "cron_run", job_id: jobId });
  ctx.ui.notify(`[remote-pi] Cron ${jobId} fired now → ${data.result}`, "info");
}

async function _cronLog(rest: string, ctx: Pick<ExtensionContext, "ui">): Promise<void> {
  const toks = _tokenizeArgs(rest);
  let jobId: string | undefined;
  let tail = 20;
  for (let i = 0; i < toks.length; i++) {
    const t = toks[i]!;
    if (t === "--tail") { const n = Number(toks[++i]); if (Number.isFinite(n)) tail = n; }
    else if (!t.startsWith("--")) jobId = t;
  }
  const req: Extract<ControlRequest, { op: "cron_log" }> = { op: "cron_log", tail };
  if (jobId) req.job_id = jobId;
  const data = await callSupervisor(req);
  if (data.entries.length === 0) {
    ctx.ui.notify("[remote-pi] No cron log entries.", "info");
    return;
  }
  const lines = data.entries.map((e) =>
    `${new Date(e.ts).toISOString()}  ${e.fired ? "▶" : "∅"} ${e.result}  ${e.job_id} → ${e.daemon_id}  ${e.prompt_preview}`,
  );
  ctx.ui.notify(`[remote-pi] Cron log (last ${data.entries.length}):\n${lines.join("\n")}`, "info");
}

// ── Install/uninstall the supervisor service (plan/26 W3) ────────────────────
//
// Installs `pi-supervisord` as a user-level system service (systemd
// `--user` unit on Linux, launchd LaunchAgent on macOS). Once installed:
//   - Supervisor starts at login + survives reboots.
//   - `remote-pi daemon start/stop/send/...` work without manually
//     spawning the supervisor.
// Uninstall is the inverse — leaves the registry (`daemons.json`) intact,
// so re-installing later picks up where you left off.

/**
 * `linkCli` controls whether we symlink `remote-pi` + `pi-supervisord`
 * into `~/.local/bin/`. The slash-command path passes `true` (user is
 * inside Pi's TUI — they installed via `pi install npm:remote-pi` and
 * need us to expose the CLI for them). The standalone-CLI path passes
 * `false` because the user is already running our binary from PATH (they
 * did `npm install -g remote-pi`), so re-linking would point their
 * `remote-pi` at the Pi-extension copy and diverge on upgrades.
 */
/** Returns true on success, false when install failed (so the standalone CLI
 *  can exit non-zero — e.g. the Cockpit / CI detect failure by exit code).
 *  We do NOT process.exit here: this also runs inside the Pi TUI, where exiting
 *  would kill the session. */
export function _cmdInstall(ctx: Pick<ExtensionContext, "ui">, opts: { linkCli?: boolean } = {}): boolean {
  const linkCli = opts.linkCli ?? false;
  try {
    const result = installService();
    const sections = [
      `[remote-pi] Supervisor service installed (${result.platform}).`,
      `  Unit: ${result.unitPath}`,
      `  Steps:\n${result.log.map((l) => "    " + l).join("\n")}`,
    ];
    if (linkCli) {
      const link = linkCliBinaries();
      sections.push(
        `  CLI bins linked into ${link.binDir}:`,
        link.links.map((l) => `    ${l.name} → ${l.target}`).join("\n"),
        `  Steps:\n${link.log.map((l) => "    " + l).join("\n")}`,
      );
      if (!link.onPath) {
        if (process.platform === "win32") {
          sections.push(
            `  ⚠ ${link.binDir} was just added to your user PATH (it wasn't there yet).`,
            `    Open a NEW terminal and run \`remote-pi daemons\` to verify.`,
          );
        } else {
          sections.push(
            `  ⚠ ${link.binDir} is not on $PATH yet. Add this line to ~/.zshrc / ~/.bashrc:`,
            `      export PATH="$HOME/.local/bin:$PATH"`,
            `    Then open a new terminal and run \`remote-pi daemons\` to verify.`,
          );
        }
      }
    }
    ctx.ui.notify(sections.join("\n"), "info");
    return true;
  } catch (err) {
    ctx.ui.notify(`[remote-pi] install failed: ${String(err)}`, "error");
    return false;
  }
}

export function _cmdUninstall(ctx: Pick<ExtensionContext, "ui">, opts: { linkCli?: boolean } = {}): void {
  const linkCli = opts.linkCli ?? false;
  try {
    const result = uninstallService();
    const sections = [
      `[remote-pi] Supervisor service uninstalled (${result.platform}).`,
      `  Unit: ${result.unitPath} (${result.removed ? "removed" : "not present"})`,
      `  Steps:\n${result.log.map((l) => "    " + l).join("\n")}`,
      `  Note: daemons registry (~/.pi/remote/daemons.json) kept — re-install restores everything.`,
    ];
    if (linkCli) {
      const unlink = unlinkCliBinaries();
      sections.push(
        `  CLI bins cleanup (${unlink.binDir}):`,
        unlink.removed
          .map((r) => `    ${r.name} (${r.existed ? "removed" : "not present"})`)
          .join("\n"),
      );
    }
    ctx.ui.notify(sections.join("\n"), "info");
  } catch (err) {
    ctx.ui.notify(`[remote-pi] uninstall failed: ${String(err)}`, "error");
  }
}

// ── CLI-only commands (restart-supervisor, peers) ─────────────────────────────

/**
 * `remote-pi restart-supervisor` — restarts the `pi-supervisord` PROCESS
 * (not the daemons). The supervisor is a long-running Node process with no
 * hot-reload, so after a `dist` rebuild the old code keeps running until the
 * process is restarted. The Cockpit "Restart supervisor" button shells out to
 * this; the OS-specific restart lives here so the app stays cross-platform.
 *
 * Restarting the supervisor re-spawns every daemon as a side effect. Exits 0
 * on success, non-zero on failure (the Cockpit detects failure by exit code).
 */
/** One step of a restart sequence. `ignoreFailure` steps (e.g. `schtasks /End`
 *  when the task isn't running) don't abort the sequence. */
export interface RestartStep { cmd: string; args: string[]; ignoreFailure?: boolean }

/** Pure: the OS command sequence that restarts the supervisor service, or null
 *  when the platform isn't supported. Most platforms are 1 step; Windows is 2
 *  (`schtasks /End` then `/Run`). Exported for tests. */
export function _restartSupervisorCommand(
  platform: NodeJS.Platform,
  uid: number,
): RestartStep[] | null {
  if (platform === "darwin") return [{ cmd: "launchctl", args: ["kickstart", "-k", `gui/${uid}/${LAUNCHD_LABEL}`] }];
  if (platform === "linux") return [{ cmd: "systemctl", args: ["--user", "restart", SYSTEMD_UNIT] }];
  if (platform === "win32") return [
    { cmd: "schtasks", args: ["/End", "/TN", WINDOWS_TASK_NAME], ignoreFailure: true },
    { cmd: "schtasks", args: ["/Run", "/TN", WINDOWS_TASK_NAME] },
  ];
  return null;
}

export function _restartSupervisor(): void {
  const uid = process.getuid?.() ?? 0;
  const steps = _restartSupervisorCommand(process.platform, uid);
  if (!steps) {
    console.error(
      `[remote-pi] restart-supervisor is not supported on '${process.platform}' yet. ` +
      "Restart pi-supervisord manually.",
    );
    process.exit(1);
  }
  for (const step of steps) {
    const r = spawnSync(step.cmd, step.args, { stdio: ["ignore", "pipe", "pipe"], encoding: "utf8" });
    if (r.error) {
      if (step.ignoreFailure) continue;
      console.error(`[remote-pi] restart-supervisor failed: ${step.cmd} not runnable (${r.error.message}). Is the service installed? Run \`remote-pi install\`.`);
      process.exit(1);
    }
    if (r.status !== 0 && !step.ignoreFailure) {
      const detail = (r.stderr || r.stdout || "").trim();
      console.error(`[remote-pi] restart-supervisor failed (${step.cmd} exited ${r.status})${detail ? `: ${detail}` : ""}.`);
      process.exit(r.status === null ? 1 : r.status);
    }
  }
  console.log("[remote-pi] Supervisor restarted.");
}


/**
 * Read-only probe of the local UDS broker for the mesh roster, backing
 * `remote-pi peers`. Opens a raw connection to `sockPath`, sends a single
 * unregistered `list_peers` request, and resolves with the peer names from the
 * broker's reply (local UDS peers + cross-PC `<pc>:<peer>` entries).
 *
 * The probe deliberately does NOT register as a peer: the broker answers
 * observer probes without assigning a name or broadcasting peer_joined/left
 * (see Broker._tryObserverProbe), so a shell query never perturbs the mesh —
 * no phantom peer flashes in anyone's roster, local or cross-PC.
 *
 * Resolves null when no broker is reachable (connection refused / no socket
 * file — i.e. no Pi or daemon is leading the mesh on this machine), or on
 * timeout, so the caller can print an "offline" message instead of an empty
 * roster.
 */
export async function probeListPeers(
  sockPath: string,
  timeoutMs = 2000,
): Promise<string[] | null> {
  const { createConnection } = await import("node:net");
  return new Promise<string[] | null>((resolve) => {
    const sock = createConnection({ path: sockPath });
    let buf = "";
    let settled = false;
    const done = (result: string[] | null): void => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      try { sock.destroy(); } catch { /* already gone */ }
      resolve(result);
    };
    const timer = setTimeout(() => done(null), timeoutMs);
    sock.setEncoding("utf8");
    sock.on("connect", () => {
      try { sock.write(JSON.stringify({ type: "list_peers" }) + "\n"); }
      catch { done(null); }
    });
    sock.on("data", (chunk: string) => {
      buf += chunk;
      const nl = buf.indexOf("\n");
      if (nl < 0) return;  // wait for a full line
      const line = buf.slice(0, nl);
      try {
        const env = JSON.parse(line) as { body?: { type?: string; peers?: unknown } };
        const body = env.body;
        if (body && body.type === "list_peers_reply" && Array.isArray(body.peers)) {
          done(body.peers.filter((p): p is string => typeof p === "string"));
          return;
        }
      } catch { /* fall through */ }
      done(null);  // a line arrived but it wasn't the reply we expected
    });
    sock.on("error", () => done(null));  // ECONNREFUSED / ENOENT → mesh offline
    sock.on("close", () => done(null));
  });
}

// ── `remote-pi claude` — launch Claude Code connected to the mesh ─────────────

/**
 * Resolve the packaged agent-network skill path
 * (`<pkgRoot>/skills/agent-network/SKILL.md`). Single source of truth shared
 * by both runtimes: Pi discovers it via `resources_discover`, and the Claude
 * launcher injects it as a system prompt (see `_cmdClaudeCli`). Returns null
 * if the file is missing (e.g. running before `pnpm build`).
 */
function _agentNetworkSkillPath(): string | null {
  const here = fileURLToPath(import.meta.url);            // dist/commands.js (or src/commands.ts via tsx)
  const pkgRoot = dirname(dirname(here));                 // package root (dist → ..; src → ..)
  const skill = join(pkgRoot, "skills", "agent-network", "SKILL.md");
  return existsSync(skill) ? skill : null;
}

export async function _cmdClaudeCli(args: string[]): Promise<void> {
  // Contract: `remote-pi claude [cwd] [claude-flags...]`. The optional cwd is
  // ONLY the leading positional (first token, not a flag); everything after it
  // is forwarded verbatim to the `claude` binary (e.g. `--resume`, `-c`,
  // `-p "prompt"`). Restricting cwd to the leading token avoids mistaking a
  // flag's value (e.g. the id in `--resume <id>`) for the cwd.
  const hasCwdArg = args.length > 0 && !args[0]!.startsWith("-");
  const targetCwd = hasCwdArg ? args[0]! : process.cwd();
  const passthroughArgs = hasCwdArg ? args.slice(1) : args;

  // Wizard when no local config exists
  if (!localConfigExists(targetCwd)) {
    const suggested = defaultAgentName(targetCwd);
    process.stdout.write(`\n[remote-pi] No config found for ${targetCwd}\n`);
    process.stdout.write("Let's set up this agent.\n\n");

    const rl = createInterface({ input: process.stdin, output: process.stdout });
    const agentName: string = await new Promise((res) =>
      rl.question(`Agent name [${suggested}]: `, (ans) => { rl.close(); res(ans.trim() || suggested); }),
    );

    saveLocalConfig(targetCwd, { agent_name: agentName, auto_start_relay: true });
    process.stdout.write(`[remote-pi] Config saved: agent="${agentName}"\n\n`);
  }

  // Resolve mesh server script path (dist/mcp/mesh_server.js)
  const here = fileURLToPath(import.meta.url);
  const distRoot = dirname(here);
  const meshServerPath = resolve(distRoot, "mcp/mesh_server.js");

  if (!existsSync(meshServerPath)) {
    console.log(`[remote-pi] mesh server not found at ${meshServerPath}. Run pnpm build first.`);
    process.exit(1);
  }

  const absCwd = resolve(targetCwd);
  const SERVER_NAME = "remote-pi-mesh";

  // The mesh MCP must be visible ONLY inside a `remote-pi claude` session — a
  // plain `claude` in the same repo must NOT inherit it (otherwise every
  // ordinary session silently joins the mesh as a stray agent).
  //
  // Older builds registered the server with `claude mcp add -s local`. That
  // scope lives in `~/.claude.json` keyed by the **git repo root** and is
  // inherited by EVERY claude session under that root — which is exactly the
  // leak we're closing. So we no longer write any persistent scope; we load
  // the server through an ephemeral `--mcp-config <tmpfile>` passed on the
  // launch command line (see below). That config is session-only: it is never
  // recorded in any scope `claude mcp list` enumerates, so a normal `claude`
  // sees nothing.
  //
  // Migration: best-effort scrub of the stale `-s local` entry that prior
  // versions left behind (and that is the source of the inherited-mesh bug).
  // Idempotent — a no-op (non-zero, ignored) when the entry is already gone.
  spawnSync("claude", ["mcp", "remove", SERVER_NAME, "-s", "local"], {
    cwd: absCwd, stdio: "ignore", shell: false,
  });

  // Ephemeral MCP config consumed by `--mcp-config` below. We do NOT bake a
  // `cwd` into it: the server resolves its folder from its own `process.cwd()`,
  // which Claude sets to the directory the session was launched in (verified
  // empirically — NOT the git root, NOT CLAUDE_PROJECT_DIR). We spawn claude
  // with `cwd: absCwd`, the MCP child inherits it, so the server self-identifies
  // as the right agent without leaking that path to any other session.
  // Unique per pid so concurrent `remote-pi claude` launches don't collide.
  const mcpConfigPath = join(tmpdir(), `remote-pi-mesh-mcp-${process.pid}.json`);
  writeFileSync(mcpConfigPath, JSON.stringify({
    mcpServers: {
      [SERVER_NAME]: { command: process.execPath, args: [meshServerPath] },
    },
  }));

  // Inject the agent-network protocol as a system prompt instead of deploying a
  // skill file into ~/.claude. Anyone running `remote-pi claude` is here to use
  // the mesh, so load the protocol unconditionally — no lazy skill gating, no
  // global skills-dir pollution, and the packaged file is the single source of
  // truth shared with the Pi runtime. Skipped only if the file is missing.
  const skillPath = _agentNetworkSkillPath();

  // Launch flags:
  //   --mcp-config <tmpfile>                       — load the mesh server for
  //       THIS session only (never a persistent scope). We intentionally omit
  //       `--strict-mcp-config` so the user's own persistent MCP servers stay
  //       available alongside the mesh.
  //   --dangerously-load-development-channels TAG  — enable claude/channel push
  //       for our local (non-allowlisted) server, so incoming mesh messages
  //       wake Claude instead of waiting for a get_messages poll. Entries must
  //       be tagged: `server:<name>` for a manually configured MCP server
  //       (`plugin:<name>@<marketplace>` is the plugin form). Shows a one-time
  //       confirmation dialog at startup. Works against the `--mcp-config`
  //       server in current Claude Code; if a build ever fails to match it, the
  //       per-turn `get_messages` poll (mandated by the mesh protocol) still
  //       delivers — we lose the wake, not the messages.
  //   --dangerously-skip-permissions               — auto-approve tool calls
  //   --append-system-prompt-file=<skill>           — load the mesh protocol
  // `--append-system-prompt-file` uses the glued `--flag=value` form (a SINGLE
  // argv token) on purpose: tools that restore a session by capturing and
  // replaying the live process's argv (e.g. cmux) drop the TRAILING token,
  // which here was the skill path — leaving a dangling `--append-system-prompt-file`
  // → `claude` aborts with "argument missing" and the session never comes back.
  // As one token, the worst case is the whole flag being dropped: claude still
  // starts (just without the injected protocol), which is recoverable instead
  // of fatal. (The other flags stay separate pairs — never last, so unaffected,
  // and we don't risk a parser that may not accept `=`.)
  // Any extra args the user passed (e.g. `--resume`, `-c`) are appended last so
  // they reach the claude binary; ours come first as sensible defaults.
  try {
    spawnSync("claude", [
      "--mcp-config", mcpConfigPath,
      "--dangerously-load-development-channels", `server:${SERVER_NAME}`,
      "--dangerously-skip-permissions",
      ...(skillPath ? [`--append-system-prompt-file=${skillPath}`] : []),
      ...passthroughArgs,
    ], {
      cwd: absCwd,
      stdio: "inherit",
      shell: false,
    });
  } finally {
    // Session over — drop the ephemeral config so it never lingers as a stray
    // file. spawnSync blocks until claude exits, so claude has long since read
    // it. Best-effort: ignore if already gone.
    try { unlinkSync(mcpConfigPath); } catch { /* already removed */ }
  }
}
