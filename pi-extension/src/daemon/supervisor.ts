import { existsSync, mkdirSync, unlinkSync } from "node:fs";
import { createConnection, createServer, type Server, type Socket } from "node:net";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { addDaemon, listDaemons, migrateRegistryNames, removeDaemon } from "./registry.js";
import { daemonIdForCwd } from "./id.js";
import { defaultAgentName, type LocalConfig } from "../session/local_config.js";
import { ipcAddress, usesNamedPipe } from "../session/ipc.js";
import { EXIT_DAEMON_FRESH_SESSION, RpcChild, type RpcChildExitEvent, type RpcChildOptions } from "./rpc_child.js";
import {
  type ControlReply,
  type ControlRequest,
  type CronJobView,
  type DaemonInfo,
  encodeReply,
  parseRequest,
} from "./control_protocol.js";
import { Cron } from "croner";
import {
  addJob as addCronJob,
  getJob as getCronJob,
  listJobs as listCronJobs,
  nextRunFor,
  recordRun,
  removeJob as removeCronJob,
  setJobEnabled,
  validateSchedule,
  type CronJob,
  type NewJobInput,
} from "./cron_registry.js";
import { appendCronLog, readCronLog, type CronResult } from "./cron_log.js";

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

/** Fixed workspace for supervisor-launched daemons. Injected via
 *  REMOTE_PI_DIRECT_CONFIG so all daemons share one mesh scope. */
const DAEMON_WORKSPACE = "assistent";

/** Backoff schedule for auto-restart after a crash. After exhausting, the
 *  child stays in `crashed` state until manual `restart_all` or fresh
 *  registry add. Keeps logs sane when the agent dies on every boot. */
const RESTART_BACKOFFS_MS = [1_000, 5_000, 30_000, 5 * 60_000];

function supervisorSockPath(): string {
  const root = process.env["REMOTE_PI_HOME"] || homedir();
  // POSIX → ~/.pi/remote/supervisor.sock; Windows → per-user named pipe (plan/40).
  return ipcAddress("supervisor", join(root, ".pi", "remote", SUPERVISOR_SOCK_NAME));
}

/** Thrown by `start()` when another live supervisor already holds the UDS.
 *  Prevents a second supervisor from orphaning the first's children. */
export class SupervisorAlreadyRunningError extends Error {
  constructor(public readonly sockPath: string) {
    super(
      `Another pi-supervisord is already running (UDS held at ${sockPath}). ` +
      "Refusing to start a second instance. Use `remote-pi daemon …` to control it, " +
      "or stop the running one first.",
    );
    this.name = "SupervisorAlreadyRunningError";
  }
}

/** Probes whether a live supervisor is accepting connections on `path`.
 *  Resolves true if the connect succeeds (a listener is there), false on
 *  ECONNREFUSED / ENOENT (stale socket file from a crashed supervisor). */
function _probeSupervisor(path: string): Promise<boolean> {
  return new Promise<boolean>((resolve) => {
    const sock = createConnection({ path });
    const done = (alive: boolean) => {
      sock.removeAllListeners();
      sock.destroy();
      resolve(alive);
    };
    const timer = setTimeout(() => done(false), 1_000);
    sock.once("connect", () => { clearTimeout(timer); done(true); });
    sock.once("error", () => { clearTimeout(timer); done(false); });
  });
}

export interface SupervisorOptions {
  /** Absolute path to remote-pi's dist/index.js — passed as -e to each
   *  spawned `pi`. Defaults to the location relative to where this file
   *  is bundled (so the supervisor finds itself). */
  extensionPath: string;
  /** Override the `pi` binary path. Defaults to "pi" on PATH. */
  piBin?: string;
}

/** Pure decision for `fireJob` (plan/39) — picks the action from the daemon's
 *  liveness/busy state + the job's flags. Tested in isolation for all 4 ramos. */
export type FireAction = "send" | "wake_and_send" | "skip_down" | "skip_busy";
export function decideFireAction(o: {
  running: boolean;
  busy: boolean;
  wake: boolean;
  skipIfBusy: boolean;
}): FireAction {
  if (!o.running) return o.wake ? "wake_and_send" : "skip_down";
  if (o.skipIfBusy && o.busy) return "skip_busy";
  return "send";
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
  /** Live croner schedules, keyed by cron job id (plan/39). */
  private readonly cronJobs = new Map<string, Cron>();
  private shuttingDown = false;

  constructor(private readonly opts: SupervisorOptions) {}

  /** Bind the control UDS + spawn all registered daemons. */
  async start(): Promise<void> {
    this._mkdirParent();
    // Backfill folder-derived names into legacy registry entries (pre-name
    // field) so every daemon has a stable name to inject via env.
    migrateRegistryNames();
    await this._bindUds();
    this._spawnAllFromRegistry();
    // Cron (plan/39): schedule all enabled jobs, then run any missed catchup.
    this._reconcileCron();
    this._runCatchup();
  }

  /** Graceful shutdown: stop all children, close UDS. */
  async stop(): Promise<void> {
    this.shuttingDown = true;
    // Stop all cron schedules (plan/39) so no fire races with teardown.
    for (const c of this.cronJobs.values()) c.stop();
    this.cronJobs.clear();
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
    // Windows named pipes have no file (auto-removed on exit) → nothing to do.
    if (!usesNamedPipe()) {
      try { unlinkSync(supervisorSockPath()); } catch { /* ignored */ }
    }
  }

  // ── UDS binding ──────────────────────────────────────────────────────────

  private _mkdirParent(): void {
    // A named pipe has no parent directory to create (the addr is `\\.\pipe\…`).
    if (usesNamedPipe()) return;
    mkdirSync(dirname(supervisorSockPath()), { recursive: true });
  }

  private async _bindUds(): Promise<void> {
    const path = supervisorSockPath();
    const pipe = usesNamedPipe();
    // Single-instance guard. PROBE first: a live supervisor answering the
    // connect means we must NOT start a second one. Stealing the socket
    // (unlink + bind) would orphan the running supervisor's children — they'd
    // keep running, unreachable by the CLI. Only on POSIX, when the probe
    // fails (stale socket from a crash), do we unlink + bind. On Windows there
    // is no file: always probe, never unlink (the pipe self-cleans on exit).
    if (pipe || existsSync(path)) {
      const alive = await _probeSupervisor(path);
      if (alive) {
        throw new SupervisorAlreadyRunningError(path);
      }
      if (!pipe) {
        try { unlinkSync(path); } catch { /* will throw on bind if still held */ }
      }
    }
    const server = createServer((socket) => this._onConnection(socket));
    await new Promise<void>((resolve, reject) => {
      server.once("error", reject);
      server.listen(path, () => resolve());
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
      case "start":        return this._opStart(req.id);
      case "stop_all":     return this._opStopAll();
      case "stop":         return this._opStop(req.id);
      case "restart_all":  return this._opRestartAll();
      case "restart":      return this._opRestart(req.id);
      case "send":         return this._opSend(req.id, req.text);
      case "register":     return this._opRegister(req.cwd);
      case "unregister":   return this._opUnregister(req.id);
      case "cron_add":     return this._opCronAdd(req);
      case "cron_list":    return this._opCronList();
      case "cron_remove":  return this._opCronRemove(req.job_id);
      case "cron_enable":  return this._opCronEnable(req.job_id, req.enabled);
      case "cron_run":     return this._opCronRun(req.job_id);
      case "cron_log":     return this._opCronLog(req.job_id, req.tail);
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
      const name = entry.name ?? defaultAgentName(entry.cwd);
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

  /** Spawn a single registered daemon by id. Idempotent: a daemon already
   *  running returns `started: false`. Unknown id → ok:false. This is what
   *  `/remote-pi create` calls so a freshly-registered folder boots its Pi
   *  immediately instead of waiting for the next supervisor restart. */
  private _opStart(id: string): ControlReply<unknown> {
    const entry = listDaemons().find((d) => d.id === id);
    if (!entry) return { ok: false, error: `no daemon with id ${id}` };
    const slot = this.children.get(id);
    if (slot && slot.child.state === "running") {
      return { ok: true, data: { id, state: slot.child.state, started: false } };
    }
    this._spawnEntry(entry.id, entry.cwd, entry.name);
    const state = this.children.get(id)?.child.state ?? "starting";
    return { ok: true, data: { id, state, started: true } };
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

  /** Stop a single registered daemon by id. Idempotent: a daemon that isn't
   *  running returns `stopped: false`. Unknown id → ok:false. Mirrors the
   *  per-id semantics of `_opStart`. Cancels any pending restart backoff so a
   *  deliberate stop stays stopped. */
  private async _opStop(id: string): Promise<ControlReply<unknown>> {
    const entry = listDaemons().find((d) => d.id === id);
    if (!entry) return { ok: false, error: `no daemon with id ${id}` };
    const slot = this.children.get(id);
    if (!slot || slot.child.state !== "running") {
      return { ok: true, data: { id, state: slot?.child.state ?? "stopped", stopped: false } };
    }
    if (slot.restartTimer !== null) {
      clearTimeout(slot.restartTimer);
      slot.restartTimer = null;
    }
    await slot.child.stop();
    return { ok: true, data: { id, state: slot.child.state, stopped: true } };
  }

  /** Restart a single registered daemon by id (stop-if-running, then spawn).
   *  Unknown id → ok:false. Resets the crash backoff. */
  private async _opRestart(id: string): Promise<ControlReply<unknown>> {
    const entry = listDaemons().find((d) => d.id === id);
    if (!entry) return { ok: false, error: `no daemon with id ${id}` };
    const slot = this.children.get(id);
    if (slot && slot.child.state === "running") {
      if (slot.restartTimer !== null) {
        clearTimeout(slot.restartTimer);
        slot.restartTimer = null;
      }
      await slot.child.stop();
    }
    this._spawnEntry(entry.id, entry.cwd, entry.name);
    const state = this.children.get(id)?.child.state ?? "starting";
    return { ok: true, data: { id, state, restarted: true } };
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

  // ── Cron ops + engine (plan/39) ────────────────────────────────────────────

  private _opCronAdd(req: Extract<ControlRequest, { op: "cron_add" }>): ControlReply<unknown> {
    const v = validateSchedule(req.schedule, req.tz);
    if (!v.ok) return { ok: false, error: v.error ?? "invalid schedule" };
    const input: NewJobInput = { daemon_id: req.daemon_id, schedule: req.schedule, prompt: req.prompt };
    if (req.tz !== undefined) input.tz = req.tz;
    if (req.skip_if_busy !== undefined) input.skip_if_busy = req.skip_if_busy;
    if (req.wake !== undefined) input.wake = req.wake;
    if (req.catchup !== undefined) input.catchup = req.catchup;
    const job = addCronJob(input);
    this._scheduleCron(job);
    return { ok: true, data: { job: this._jobView(job) } };
  }

  private _opCronList(): ControlReply<unknown> {
    const jobs = listCronJobs().map((j) => this._jobView(j));
    return { ok: true, data: { jobs } };
  }

  private _opCronRemove(jobId: string): ControlReply<unknown> {
    const removed = removeCronJob(jobId);
    this._stopCron(jobId);
    return { ok: true, data: { removed } };
  }

  private _opCronEnable(jobId: string, enabled: boolean): ControlReply<unknown> {
    const updated = setJobEnabled(jobId, enabled);
    if (updated) {
      this._stopCron(jobId);
      const job = getCronJob(jobId);
      if (enabled && job) this._scheduleCron(job);
    }
    return { ok: true, data: { job_id: jobId, enabled, updated } };
  }

  private async _opCronRun(jobId: string): Promise<ControlReply<unknown>> {
    if (!getCronJob(jobId)) return { ok: false, error: `no cron job with id ${jobId}` };
    const result = await this.fireJob(jobId, { manual: true });
    return { ok: true, data: { job_id: jobId, result } };
  }

  private _opCronLog(jobId: string | undefined, tail: number | undefined): ControlReply<unknown> {
    const opts: { jobId?: string; tail?: number } = {};
    if (jobId !== undefined) opts.jobId = jobId;
    if (tail !== undefined) opts.tail = tail;
    return { ok: true, data: { entries: readCronLog(opts) } };
  }

  private _jobView(job: CronJob): CronJobView {
    const next = nextRunFor(job);
    return { ...job, next_run: next ? next.toISOString() : null };
  }

  /** Rebuild all live `Cron` schedules from the registry (enabled jobs only).
   *  Called on start; mutations reconcile incrementally via _scheduleCron/_stopCron. */
  private _reconcileCron(): void {
    for (const c of this.cronJobs.values()) c.stop();
    this.cronJobs.clear();
    for (const job of listCronJobs()) {
      if (job.enabled) this._scheduleCron(job);
    }
  }

  private _scheduleCron(job: CronJob): void {
    this._stopCron(job.id);
    try {
      const opts = job.tz ? { timezone: job.tz, name: job.id } : { name: job.id };
      const cron = new Cron(job.schedule, opts, () => { void this.fireJob(job.id); });
      this.cronJobs.set(job.id, cron);
    } catch (e) {
      process.stderr.write(`[remote-pi-supervisord] cron schedule failed for ${job.id}: ${String(e)}\n`);
    }
  }

  private _stopCron(jobId: string): void {
    const c = this.cronJobs.get(jobId);
    if (c) { c.stop(); this.cronJobs.delete(jobId); }
  }

  /** Detail 2: on start, run a catchup job once if its previous scheduled run
   *  was missed while the supervisor was down. Opt-in (`catchup`), at most 1×. */
  private _runCatchup(): void {
    for (const job of listCronJobs()) {
      if (!job.enabled || !job.catchup) continue;
      try {
        const cron = new Cron(job.schedule, job.tz ? { timezone: job.tz } : {});
        const prev = cron.previousRun();
        cron.stop();
        if (!prev) continue;
        const lastRunMs = job.last_run ? Date.parse(job.last_run) : 0;
        if (prev.getTime() > lastRunMs) void this.fireJob(job.id, { manual: true });
      } catch { /* skip a malformed schedule */ }
    }
  }

  /**
   * Fires a cron job: resolves the daemon, decides the action (decideFireAction),
   * acts, and records the outcome — ALWAYS one `last_status` update + one JSONL
   * line, for both fires and skips. Returns the result. `manual` bypasses the
   * disabled-skip (used by `cron run` + catchup).
   */
  async fireJob(jobId: string, opts: { manual?: boolean } = {}): Promise<CronResult | "missing"> {
    const job = getCronJob(jobId);
    if (!job) return "missing";

    let result: CronResult;
    if (!job.enabled && !opts.manual) {
      result = "skipped_disabled";
    } else {
      const slot = this.children.get(job.daemon_id);
      const running = !!slot && slot.child.state === "running";
      let busy = false;
      if (running && job.skip_if_busy) busy = await slot!.child.refreshBusy();
      const action = decideFireAction({ running, busy, wake: job.wake, skipIfBusy: job.skip_if_busy });
      if (action === "skip_down") {
        result = "skipped_down";
      } else if (action === "skip_busy") {
        result = "skipped_busy";
      } else if (action === "wake_and_send") {
        const entry = listDaemons().find((d) => d.id === job.daemon_id);
        if (!entry) {
          result = "skipped_down";
        } else {
          this._spawnEntry(entry.id, entry.cwd, entry.name);
          const woke = this.children.get(job.daemon_id);
          result = woke && woke.child.sendPrompt(job.prompt) ? "woke_and_delivered" : "deliver_failed";
        }
      } else {
        result = slot!.child.sendPrompt(job.prompt) ? "delivered" : "deliver_failed";
      }
    }

    const at = new Date().toISOString();
    recordRun(job.id, at, result);
    appendCronLog({ job_id: job.id, daemon_id: job.daemon_id, schedule: job.schedule, result, prompt: job.prompt });
    return result;
  }

  // ── Child lifecycle ──────────────────────────────────────────────────────

  private _spawnAllFromRegistry(): void {
    for (const entry of listDaemons()) {
      this._spawnEntry(entry.id, entry.cwd, entry.name);
    }
  }

  private _spawnEntry(id: string, cwd: string, name?: string): void {
    // Clean up any prior slot (e.g. crashed + waiting for backoff).
    const existing = this.children.get(id);
    if (existing) {
      if (existing.restartTimer !== null) clearTimeout(existing.restartTimer);
      // If somehow the child is still alive, stop it first so we don't
      // leak. Fire-and-forget — caller doesn't await.
      if (existing.child.state === "running") void existing.child.stop();
    }

    // Build the daemon's config and inject it via REMOTE_PI_DIRECT_CONFIG —
    // no per-cwd config file needed. workspace is fixed; no worktree; relay on.
    const config: LocalConfig = {
      agent_name: name ?? defaultAgentName(cwd),
      auto_start_relay: true,
      workspace: DAEMON_WORKSPACE,
    };
    const childOpts: RpcChildOptions = {
      extensionPath: this.opts.extensionPath,
      cwd,
      config,
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

    if (evt.code === EXIT_DAEMON_FRESH_SESSION) {
      // App-triggered daemon `/new`: this is an intentional recycle, not a
      // crash. Restart immediately and don't burn the crash backoff budget.
      slot.restartAttempt = 0;
      slot.child.noteRestart();
      slot.child.spawn();
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
