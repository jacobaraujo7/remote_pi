import { ChildProcess, spawn } from "node:child_process";
import { EventEmitter } from "node:events";
import type { DaemonState } from "./control_protocol.js";

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
}

export interface RpcChildExitEvent {
  code: number | null;
  signal: NodeJS.Signals | null;
  /** True when exit was not clean (non-zero or signal). */
  isCrash: boolean;
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
  /** Accumulates partial stdout lines while waiting for `\n`. */
  private stdoutBuf = "";

  constructor(private readonly opts: RpcChildOptions) {
    super();
  }

  get state(): DaemonState { return this._state; }
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
    this._state = "starting";

    const piBin = this.opts.piBin ?? "pi";
    const args = ["--mode", "rpc", "-e", this.opts.extensionPath];
    const env: NodeJS.ProcessEnv = {
      ...process.env,
      ...this.opts.env,
      // Mandatory daemon marker — `_cmdRoot` in index.ts can use this to
      // bail early if local config is missing (no wizard in RPC mode).
      REMOTE_PI_DAEMON: "1",
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
      this.emit("stdout", line);
    }
  }

  private _onExit(code: number | null, signal: NodeJS.Signals | null): void {
    // A deliberate stop() kills by signal — not a crash, so the supervisor
    // must NOT auto-restart it. Only an UNexpected exit counts as a crash.
    const isCrash = !this._stopping && (code !== 0 || signal !== null);
    this._state = isCrash ? "crashed" : "stopped";
    this.child = null;
    this._startedAt = null;
    this.emit("exit", { code, signal, isCrash } satisfies RpcChildExitEvent);
  }

  /** Bumps the restart counter — called by the supervisor when it
   *  decides to re-spawn after a crash. Exposed so tests can drive it. */
  noteRestart(): void {
    this._restartCount += 1;
  }
}
