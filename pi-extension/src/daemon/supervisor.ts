import { existsSync, unlinkSync } from "node:fs";
import { createServer, type Server, type Socket } from "node:net";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { PRIVATE_FILE_MODE, chmodPrivatePathSync, ensurePrivateDirSync } from "../secure_fs.js";
import { addDaemon, listDaemons, removeDaemon } from "./registry.js";
import { daemonIdForCwd } from "./id.js";
import { loadLocalConfig, defaultAgentName } from "../session/local_config.js";
import { RpcChild, type RpcChildExitEvent, type RpcChildOptions } from "./rpc_child.js";
import {
  type ControlReply,
  type ControlRequest,
  type DaemonInfo,
  encodeReply,
  parseRequest,
} from "./control_protocol.js";

/**
 * Central process that owns the daemon fleet (plan/26).
 *
 * Responsibilities:
 *   - Spawn one `pi --mode rpc` child per registry entry. Track them in
 *     `_children: Map<id, RpcChild>`.
 *   - Auto-restart crashed children with exponential backoff
 *     (1s, 5s, 30s, 5min). Give up after 4 attempts to avoid log spam
 *     when the agent is misconfigured.
 *   - Listen on `~/.pi/remote/supervisor.sock` for `ControlRequest`s from
 *     the `remote-pi` CLI. Each connection: 1 request → 1 reply → close.
 *   - Graceful shutdown on SIGTERM/SIGINT: stop all children + unlink
 *     the UDS file so a next supervisor can bind cleanly.
 *
 * The supervisor itself is the only long-running process the user
 * installs as a system service (plan/26 W3 will generate the unit/plist).
 * If it crashes, systemd/launchd restarts it; on restart it re-reads
 * the registry and re-spawns everything.
 */

const SUPERVISOR_SOCK_NAME = "supervisor.sock";

/** Backoff schedule for auto-restart after a crash. After exhausting, the
 *  child stays in `crashed` state until manual `restart_all` or fresh
 *  registry add. Keeps logs sane when the agent dies on every boot. */
const RESTART_BACKOFFS_MS = [1_000, 5_000, 30_000, 5 * 60_000];

function supervisorSockPath(): string {
  const root = process.env["REMOTE_PI_HOME"] || homedir();
  return join(root, ".pi", "remote", SUPERVISOR_SOCK_NAME);
}

export interface SupervisorOptions {
  /** Absolute path to remote-pi's dist/index.js — passed as -e to each
   *  spawned `pi`. Defaults to the location relative to where this file
   *  is bundled (so the supervisor finds itself). */
  extensionPath: string;
  /** Override the `pi` binary path. Defaults to "pi" on PATH. */
  piBin?: string;
}

interface ChildSlot {
  id: string;
  cwd: string;
  child: RpcChild;
  restartTimer: ReturnType<typeof setTimeout> | null;
  restartAttempt: number;
}

export class Supervisor {
  private server: Server | null = null;
  private readonly children = new Map<string, ChildSlot>();
  private shuttingDown = false;

  constructor(private readonly opts: SupervisorOptions) {}

  /** Bind the control UDS + spawn all registered daemons. */
  async start(): Promise<void> {
    this._mkdirParent();
    await this._bindUds();
    this._spawnAllFromRegistry();
  }

  /** Graceful shutdown: stop all children, close UDS. */
  async stop(): Promise<void> {
    this.shuttingDown = true;
    // Cancel pending restart timers first so they don't race with stop().
    for (const slot of this.children.values()) {
      if (slot.restartTimer !== null) {
        clearTimeout(slot.restartTimer);
        slot.restartTimer = null;
      }
    }
    await Promise.all([...this.children.values()].map((s) => s.child.stop()));
    this.children.clear();
    await new Promise<void>((resolve) => {
      if (!this.server) return resolve();
      this.server.close(() => resolve());
    });
    this.server = null;
    // Best-effort: clear the socket file so a next supervisor bind succeeds.
    try { unlinkSync(supervisorSockPath()); } catch { /* ignored */ }
  }

  // ── UDS binding ──────────────────────────────────────────────────────────

  private _mkdirParent(): void {
    ensurePrivateDirSync(dirname(supervisorSockPath()));
  }

  private async _bindUds(): Promise<void> {
    const path = supervisorSockPath();
    // If a stale socket file exists from a previous crashed supervisor,
    // try to connect first — if that fails, unlink and bind. Same self-
    // healing pattern as cwd_lock / leader_election.
    if (existsSync(path)) {
      try { unlinkSync(path); } catch { /* will throw on bind if still held */ }
    }
    const server = createServer((socket) => this._onConnection(socket));
    await new Promise<void>((resolve, reject) => {
      server.once("error", reject);
      server.listen(path, () => {
        chmodPrivatePathSync(path, PRIVATE_FILE_MODE);
        resolve();
      });
    });
    this.server = server;
  }

  private _onConnection(socket: Socket): void {
    let buf = "";
    socket.setEncoding("utf8");
    socket.on("data", (chunk: string) => {
      buf += chunk;
      const nl = buf.indexOf("\n");
      if (nl < 0) return;
      const line = buf.slice(0, nl);
      // Single request per connection; ignore anything past the newline.
      void this._handleRequest(line)
        .then((reply) => socket.end(encodeReply(reply)))
        .catch((err) => socket.end(encodeReply<unknown>({ ok: false, error: String(err) })));
    });
    socket.on("error", () => { /* client hung up; nothing to do */ });
  }

  // ── Request dispatch ─────────────────────────────────────────────────────

  private async _handleRequest(line: string): Promise<ControlReply<unknown>> {
    let req: ControlRequest;
    try { req = parseRequest(line); }
    catch (e) { return { ok: false, error: (e as Error).message }; }

    switch (req.op) {
      case "list":         return { ok: true, data: { daemons: this._listInfo() } };
      case "status":       return { ok: true, data: { daemons: this._listInfo() } };
      case "start_all":    return this._opStartAll();
      case "stop_all":     return this._opStopAll();
      case "restart_all":  return this._opRestartAll();
      case "send":         return this._opSend(req.id, req.text);
      case "register":     return this._opRegister(req.cwd);
      case "unregister":   return this._opUnregister(req.id);
      default: {
        const unknown = (req as { op: string }).op;
        return { ok: false, error: `unknown op: ${unknown}` };
      }
    }
  }

  // ── Op handlers ──────────────────────────────────────────────────────────

  private _listInfo(): DaemonInfo[] {
    const registry = listDaemons();
    return registry.map((entry) => {
      const slot = this.children.get(entry.id);
      const cfg = loadLocalConfig(entry.cwd);
      const name = cfg.agent_name ?? defaultAgentName(entry.cwd);
      const info: DaemonInfo = {
        id: entry.id,
        cwd: entry.cwd,
        name,
        state: slot?.child.state ?? "stopped",
      };
      if (slot) {
        if (slot.child.pid !== undefined) info.pid = slot.child.pid;
        if (slot.child.uptimeMs !== undefined) info.uptime_s = Math.floor(slot.child.uptimeMs / 1000);
        info.restart_count = slot.child.restartCount;
      }
      return info;
    });
  }

  private _opStartAll(): ControlReply<unknown> {
    const started: string[] = [];
    const already: string[] = [];
    for (const entry of listDaemons()) {
      const slot = this.children.get(entry.id);
      if (slot && slot.child.state === "running") {
        already.push(entry.id);
        continue;
      }
      this._spawnEntry(entry.id, entry.cwd);
      started.push(entry.id);
    }
    return { ok: true, data: { started, already_running: already } };
  }

  private async _opStopAll(): Promise<ControlReply<unknown>> {
    const stopped: string[] = [];
    const already: string[] = [];
    for (const [id, slot] of this.children) {
      if (slot.child.state !== "running") {
        already.push(id);
        continue;
      }
      if (slot.restartTimer !== null) {
        clearTimeout(slot.restartTimer);
        slot.restartTimer = null;
      }
      await slot.child.stop();
      stopped.push(id);
    }
    return { ok: true, data: { stopped, already_stopped: already } };
  }

  private async _opRestartAll(): Promise<ControlReply<unknown>> {
    const stopReply = await this._opStopAll();
    if (!stopReply.ok) return stopReply;
    const startReply = this._opStartAll();
    if (!startReply.ok) return startReply;
    const restarted = (startReply.data as { started: string[] }).started;
    return { ok: true, data: { restarted } };
  }

  private _opSend(id: string, text: string): ControlReply<unknown> {
    const slot = this.children.get(id);
    if (!slot) return { ok: false, error: `daemon ${id} not running` };
    if (slot.child.state !== "running") {
      return { ok: false, error: `daemon ${id} state is ${slot.child.state}` };
    }
    const ok = slot.child.sendPrompt(text);
    return { ok: true, data: { id, delivered: ok } };
  }

  private _opRegister(rawCwd: string): ControlReply<unknown> {
    try {
      const { id, cwd } = addDaemon(rawCwd);
      return { ok: true, data: { id, cwd } };
    } catch (e) {
      return { ok: false, error: (e as Error).message };
    }
  }

  private async _opUnregister(id: string): Promise<ControlReply<unknown>> {
    // Stop the child first so we don't leave an orphan when the registry
    // entry is gone.
    const slot = this.children.get(id);
    if (slot) {
      if (slot.restartTimer !== null) {
        clearTimeout(slot.restartTimer);
        slot.restartTimer = null;
      }
      await slot.child.stop();
      this.children.delete(id);
    }
    try {
      const result = removeDaemon(id);
      return { ok: true, data: result };
    } catch (e) {
      return { ok: false, error: (e as Error).message };
    }
  }

  // ── Child lifecycle ──────────────────────────────────────────────────────

  private _spawnAllFromRegistry(): void {
    for (const entry of listDaemons()) {
      this._spawnEntry(entry.id, entry.cwd);
    }
  }

  private _spawnEntry(id: string, cwd: string): void {
    // Clean up any prior slot (e.g. crashed + waiting for backoff).
    const existing = this.children.get(id);
    if (existing) {
      if (existing.restartTimer !== null) clearTimeout(existing.restartTimer);
      // If somehow the child is still alive, stop it first so we don't
      // leak. Fire-and-forget — caller doesn't await.
      if (existing.child.state === "running") void existing.child.stop();
    }

    const childOpts: RpcChildOptions = {
      extensionPath: this.opts.extensionPath,
      cwd,
    };
    if (this.opts.piBin !== undefined) childOpts.piBin = this.opts.piBin;
    const child = new RpcChild(childOpts);
    const slot: ChildSlot = { id, cwd, child, restartTimer: null, restartAttempt: 0 };
    this.children.set(id, slot);

    child.on("exit", (evt: RpcChildExitEvent) => this._onChildExit(id, evt));
    child.spawn();
  }

  private _onChildExit(id: string, evt: RpcChildExitEvent): void {
    if (this.shuttingDown) return;
    const slot = this.children.get(id);
    if (!slot) return;

    if (!evt.isCrash) {
      // Clean shutdown (e.g. via `stop_all`). Don't auto-restart.
      return;
    }

    // Crash: schedule restart with backoff. After exhausting the schedule
    // we give up and stay in `crashed`.
    if (slot.restartAttempt >= RESTART_BACKOFFS_MS.length) {
      process.stderr.write(
        `[remote-pi-supervisord] giving up restart for ${id} after ${slot.restartAttempt} attempts\n`,
      );
      return;
    }
    const delay = RESTART_BACKOFFS_MS[slot.restartAttempt]!;
    process.stderr.write(
      `[remote-pi-supervisord] scheduling restart of ${id} in ${delay}ms (attempt ${slot.restartAttempt + 1})\n`,
    );
    slot.restartTimer = setTimeout(() => {
      slot.restartTimer = null;
      slot.restartAttempt += 1;
      slot.child.noteRestart();
      slot.child.spawn();
    }, delay);
  }
}

/** Test helper: derive id from cwd without going through the registry. */
export function _idForCwdForTest(cwd: string): string { return daemonIdForCwd(cwd); }

/** Exported for the bin/supervisord entry + tests to know where the
 *  supervisor will bind. */
export function getSupervisorSockPath(): string { return supervisorSockPath(); }
