import { ChildProcess, execFileSync, spawn } from "node:child_process";
import { EventEmitter } from "node:events";
import type { DaemonState } from "./control_protocol.js";
import { defaultAgentName, loadLocalConfig, type LocalConfig } from "../session/local_config.js";

/**
 * Wrapper around a `pi --mode rpc -e <extension>` child process for the
 * supervisor.
 *
 * Lifecycle:
 *   - `spawn()` boots the child with the daemon's cwd + `REMOTE_PI_DAEMON=1`
 *     env so the extension knows to skip the interactive wizard.
 *   - `sendPrompt(text)` writes a Pi RPC `prompt` command to stdin.
 *   - The child's stdout (Pi RPC events) is currently consumed line-by-line
 *     and ignored — wave 2 only needs fire-and-forget. Later waves can
 *     surface the events back through the supervisor's status op.
 *   - Exit/crash fires `exit` event with `{code, signal, isCrash}` so the
 *     supervisor can decide whether to auto-restart.
 *
 * Each `RpcChild` instance maps 1:1 to a registry entry (single cwd).
 * The supervisor owns the map of these and addresses them by `id`.
 */

export interface RpcChildOptions {
  /** Path to the `pi` binary. Defaults to "pi" (must be on PATH). */
  piBin?: string;
  /** Absolute path to the remote-pi `dist/index.js` to load as -e. */
  extensionPath: string;
  /** Working directory for the spawned process. Determines which local
   *  config the extension reads. */
  cwd: string;
  /** Additional env vars merged on top of `process.env` + the mandatory
   *  `REMOTE_PI_DAEMON=1`. */
  env?: NodeJS.ProcessEnv;
  /**
   * Daemon config injected into the child via `REMOTE_PI_DIRECT_CONFIG`
   * (JSON inline) instead of a per-cwd `.pi/remote-pi/config.json` file. The
   * supervisor builds this from the registry. When set, the child reads it
   * env-first (see `loadLocalConfig`) and no config file is needed. Also the
   * source of the `--name` for the session. Falls back to the on-disk config
   * when omitted.
   */
  config?: LocalConfig;
}

export interface RpcChildExitEvent {
  code: number | null;
  signal: NodeJS.Signals | null;
  /** True when exit was not clean (non-zero or signal). */
  isCrash: boolean;
}

export const EXIT_DAEMON_FRESH_SESSION = 42;

/**
 * Resolve the `pi` executable for `spawn` (plan/40, decision C). On Windows a
 * bare `pi` is actually `pi.cmd`/`pi.ps1`, and `spawn` won't find it without an
 * extension → resolve the real path via `where` (rather than `shell:true`,
 * which risks shell injection). An explicit path or an already-suffixed name is
 * used as-is. POSIX returns the name unchanged. Best-effort: if `where` fails,
 * fall back to the bare name (spawn will surface ENOENT honestly).
 */
export function resolvePiBin(piBin: string, plat: NodeJS.Platform = process.platform): string {
  if (plat !== "win32") return piBin;
  if (piBin.includes("\\") || piBin.includes("/") || /\.[a-z0-9]+$/i.test(piBin)) return piBin;
  try {
    const out = execFileSync("where", [piBin], { encoding: "utf8" });
    const first = out.split(/\r?\n/).map((l) => l.trim()).filter(Boolean)[0];
    if (first) return first;
  } catch {
    /* `where` unavailable or `pi` not found — fall back to the bare name */
  }
  return piBin;
}

/**
 * Maps an RPC stdout line to a busy-state transition: `message_start` → true
 * (a message is streaming), `message_end` → false. Other lines → null (no
 * change). Pure + exported for tests.
 *
 * NOTE (plan/39 detail 1): the Pi RPC stream has NO turn-level event — only
 * per-message start/end (and `response{command:"prompt"}` is emitted at
 * PREFLIGHT, i.e. turn START, not end). So this passive flag reflects
 * "a message is being produced right now"; the authoritative turn-busy signal
 * is `get_state.isStreaming` (see `RpcChild.refreshBusy`).
 */
export function busyTransition(line: string): boolean | null {
  let obj: unknown;
  try { obj = JSON.parse(line); } catch { return null; }
  const t = (obj as { type?: unknown } | null)?.type;
  if (t === "message_start") return true;
  if (t === "message_end") return false;
  return null;
}

/** Parses a `get_state` RPC response line, returning its id + isStreaming. */
function parseGetStateResponse(line: string): { id?: string; isStreaming?: boolean } | null {
  let obj: unknown;
  try { obj = JSON.parse(line); } catch { return null; }
  const o = obj as { type?: unknown; command?: unknown; id?: unknown; data?: unknown };
  if (o.type !== "response" || o.command !== "get_state") return null;
  const data = o.data as { isStreaming?: unknown } | undefined;
  return {
    id: typeof o.id === "string" ? o.id : undefined,
    isStreaming: typeof data?.isStreaming === "boolean" ? data.isStreaming : undefined,
  };
}

/**
 * CLI args for the daemon's `pi --mode rpc` child.
 *
 * `--continue` is the key bit: it resumes the **most recent** session for the
 * cwd (`SessionManager.continueRecent`, non-interactive — unlike `--resume`
 * which opens a picker). Without it every supervisor restart spun up a brand
 * new session file, piling up thousands of JSONLs per folder. With it, a
 * restart REUSES the one session; the app's `/new` (session_new) still rolls
 * it over to a fresh one, which the next restart then continues. First boot
 * (no prior session) just creates the first one.
 *
 * `--name <sessionName>`, when given, pins the session's display name to the
 * daemon's identity (its `agent_name`) so every restart shows up under the
 * same stable name in the picker/app instead of an auto-generated one. The
 * daemon's name is set at registration (`remote-pi create <cwd> --name "…"`).
 * Omitted when no name resolves, so the arg list stays minimal.
 */
export function rpcSpawnArgs(
  extensionPath: string,
  sessionName?: string,
  useContinue = true,
): string[] {
  return [
    "--mode", "rpc",
    ...(useContinue ? ["--continue"] : []),
    ...(sessionName ? ["--name", sessionName] : []),
    "-e", extensionPath,
  ];
}

export class RpcChild extends EventEmitter {
  private child: ChildProcess | null = null;
  private _state: DaemonState = "stopped";
  private _startedAt: number | null = null;
  private _restartCount = 0;
  /** True while a deliberate `stop()` is in flight. The process dies by
   *  signal (SIGTERM/SIGKILL), which would otherwise look like a crash and
   *  trip the supervisor's auto-restart — re-spawning a daemon the operator
   *  just stopped/removed. Gating `isCrash` on this makes a deliberate stop a
   *  clean exit (no restart). Reset on every `spawn()`. */
  private _stopping = false;
  /** Next spawn should create a fresh session instead of --continue. */
  private forceFreshSessionOnNextSpawn = false;
  /** Accumulates partial stdout lines while waiting for `\n`. */
  private stdoutBuf = "";
  /** Passive busy flag derived from the RPC stream (message_start/end). Hint
   *  only; `refreshBusy` syncs it authoritatively via get_state.isStreaming. */
  private _busy = false;
  /** In-flight `get_state` requests, keyed by request id. */
  private readonly _statePending = new Map<string, { resolve: (b: boolean) => void; timer: ReturnType<typeof setTimeout> }>();

  constructor(private readonly opts: RpcChildOptions) {
    super();
  }

  get state(): DaemonState { return this._state; }
  /** Passive busy hint from the stream. Prefer `refreshBusy()` for an
   *  authoritative check before acting on it (cron skip_if_busy). */
  get isBusy(): boolean { return this._busy; }
  get pid(): number | undefined { return this.child?.pid; }
  get restartCount(): number { return this._restartCount; }
  get uptimeMs(): number | undefined {
    return this._startedAt !== null ? Date.now() - this._startedAt : undefined;
  }

  /**
   * Spawn the child process. Idempotent for the same instance: a second
   * call while already running is a no-op.
   */
  spawn(): void {
    if (this.child) return;
    this._stopping = false;  // fresh start — a later signal IS a real crash
    this._busy = false;
    this._state = "starting";

    const piBin = resolvePiBin(this.opts.piBin ?? "pi");
    // Name the (single) daemon session after the daemon's configured identity,
    // so it shows up stably instead of an auto-generated name on each restart.
    // Prefer the supervisor-injected config; fall back to the on-disk file.
    const cfg = this.opts.config ?? loadLocalConfig(this.opts.cwd);
    const sessionName = cfg.agent_name ?? defaultAgentName(this.opts.cwd);
    const useContinue = !this.forceFreshSessionOnNextSpawn;
    this.forceFreshSessionOnNextSpawn = false;
    const args = rpcSpawnArgs(this.opts.extensionPath, sessionName, useContinue);
    const env: NodeJS.ProcessEnv = {
      ...process.env,
      ...this.opts.env,
      // Mandatory daemon marker — `_cmdRoot` in index.ts can use this to
      // bail early if local config is missing (no wizard in RPC mode).
      REMOTE_PI_DAEMON: "1",
      // Inject the daemon config inline so the child needs no config file.
      ...(this.opts.config ? { REMOTE_PI_DIRECT_CONFIG: JSON.stringify(this.opts.config) } : {}),
    };

    const child = spawn(piBin, args, {
      cwd: this.opts.cwd,
      env,
      stdio: ["pipe", "pipe", "pipe"],
    });
    this.child = child;
    this._startedAt = Date.now();
    this._state = "running";

    child.stdout?.on("data", (chunk: Buffer) => this._onStdout(chunk));
    child.stderr?.on("data", (chunk: Buffer) => {
      // Forward stderr to our own stderr so `journalctl --user -u remote-pi-supervisord`
      // sees daemon logs (with cwd prefix for disambiguation).
      process.stderr.write(`[${this.opts.cwd}] ${chunk.toString()}`);
    });
    child.on("exit", (code, signal) => this._onExit(code, signal));
    child.on("error", (err) => {
      // spawn() itself failed (e.g. `pi` binary not found).
      this._state = "crashed";
      process.stderr.write(
        `[remote-pi-supervisord] spawn failed for ${this.opts.cwd}: ${String(err)}\n`,
      );
      this.emit("exit", { code: null, signal: null, isCrash: true });
    });

    this.emit("spawn", { pid: child.pid });
  }

  /**
   * Sends a Pi RPC `prompt` command to the child's stdin. Fire-and-forget
   * — we don't wait for the response (response would be the success ack;
   * the actual agent output streams via the relay/UDS, not back through
   * stdout).
   *
   * Returns false if the child isn't running (caller decides how to report).
   */
  sendPrompt(text: string, requestId?: string): boolean {
    if (!this.child || !this.child.stdin || this._state !== "running") return false;
    const cmd = { id: requestId ?? `sv-${Date.now()}`, type: "prompt", message: text };
    try {
      this.child.stdin.write(JSON.stringify(cmd) + "\n");
      return true;
    } catch {
      return false;
    }
  }

  /**
   * Asks the child to exit gracefully. Sends SIGTERM; if the child doesn't
   * exit within `timeoutMs`, escalates to SIGKILL. Resolves when the
   * `exit` event fires.
   */
  async stop(timeoutMs = 5000): Promise<void> {
    if (!this.child) return;
    this._stopping = true;  // deliberate — the upcoming signal-exit is NOT a crash
    const child = this.child;
    return new Promise<void>((resolve) => {
      const onExit = () => { resolve(); };
      this.once("exit", onExit);
      try { child.kill("SIGTERM"); } catch { /* already dead */ }
      const t = setTimeout(() => {
        try { child.kill("SIGKILL"); } catch { /* race — already dead */ }
      }, timeoutMs);
      this.once("exit", () => clearTimeout(t));
    });
  }

  private _onStdout(chunk: Buffer): void {
    this.stdoutBuf += chunk.toString();
    let nl: number;
    while ((nl = this.stdoutBuf.indexOf("\n")) >= 0) {
      const line = this.stdoutBuf.slice(0, nl);
      this.stdoutBuf = this.stdoutBuf.slice(nl + 1);
      if (!line.trim()) continue;
      this._handleStdoutLine(line);
    }
  }

  private _handleStdoutLine(line: string): void {
    const t = busyTransition(line);
    if (t !== null) this._busy = t;
    const gs = parseGetStateResponse(line);
    if (gs && gs.id) {
      const pending = this._statePending.get(gs.id);
      if (pending) {
        clearTimeout(pending.timer);
        this._statePending.delete(gs.id);
        if (typeof gs.isStreaming === "boolean") this._busy = gs.isStreaming;
        pending.resolve(this._busy);
      }
    }
    this.emit("stdout", line);
  }

  /**
   * Authoritative busy check: queries the child's `get_state` and syncs
   * `_busy` to `isStreaming`. Resolves the passive flag on timeout (no
   * response) or when the child isn't running. Used by the cron `skip_if_busy`
   * gate, where a false "not busy" would pile a prompt onto a live turn.
   */
  async refreshBusy(timeoutMs = 1500): Promise<boolean> {
    if (this._state !== "running" || !this.child?.stdin) return this._busy;
    const id = `gs-${Date.now()}-${Math.round(Math.random() * 1e6)}`;
    return new Promise<boolean>((resolve) => {
      const timer = setTimeout(() => {
        this._statePending.delete(id);
        resolve(this._busy);
      }, timeoutMs);
      this._statePending.set(id, { resolve, timer });
      try {
        this.child!.stdin!.write(JSON.stringify({ id, type: "get_state" }) + "\n");
      } catch {
        clearTimeout(timer);
        this._statePending.delete(id);
        resolve(this._busy);
      }
    });
  }

  /** Test-only: feed a raw stdout line through the same handler. */
  _ingestStdoutForTest(line: string): void {
    this._handleStdoutLine(line);
  }

  private _onExit(code: number | null, signal: NodeJS.Signals | null): void {
    // Daemon app-action `/new`: child exits with a private code, supervisor
    // restarts it, and the next spawn omits --continue once to create a fresh
    // session. Later restarts go back to --continue.
    if (code === EXIT_DAEMON_FRESH_SESSION) this.forceFreshSessionOnNextSpawn = true;
    // A deliberate stop() kills by signal — not a crash, so the supervisor
    // must NOT auto-restart it. Only an UNexpected exit counts as a crash.
    const isCrash = !this._stopping && (code !== 0 || signal !== null);
    this._state = isCrash ? "crashed" : "stopped";
    this.child = null;
    this._startedAt = null;
    this._busy = false;
    for (const p of this._statePending.values()) {
      clearTimeout(p.timer);
      p.resolve(false);
    }
    this._statePending.clear();
    this.emit("exit", { code, signal, isCrash } satisfies RpcChildExitEvent);
  }

  /** Bumps the restart counter — called by the supervisor when it
   *  decides to re-spawn after a crash. Exposed so tests can drive it. */
  noteRestart(): void {
    this._restartCount += 1;
  }
}
