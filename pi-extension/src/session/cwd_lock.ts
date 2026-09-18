import { mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import type { Server } from "node:net";
import { roomIdFor } from "../rooms.js";
import { removeStaleSock, tryBind, tryConnect } from "./leader_election.js";
import { ipcAddress, usesNamedPipe } from "./ipc.js";
import { remotePiHome } from "../paths.js";

/**
 * Per-cwd singleton lock for `/remote-pi`. At most one Pi process per
 * working directory may hold the lock; the second attempt is refused.
 *
 * Why a UDS bind instead of a PID lock file:
 *   - The OS releases the socket handle the instant the process dies, even
 *     on `kill -9` or hard crash. No stale-lock cleanup needed.
 *   - The next Pi to try in the same cwd detects the dead socket via
 *     `ECONNREFUSED` on `tryConnect`, unlinks the leftover file, and
 *     binds successfully. Fully self-healing.
 *   - Kernel-enforced — there is no race window between "check if held"
 *     and "claim", which an explicit PID file would have.
 *
 * Lock files live in `<root>/.pi/remote/locks/<roomId>.sock` (where `roomId`
 * is `sha256(realpath(cwd))[:12]` and `<root>` is `$REMOTE_PI_HOME` or the
 * home dir), NOT inside the cwd itself, to dodge:
 *   - The 104/108-char path-length limit on UDS sockets on macOS/Linux.
 *   - Symlinked cwds (realpath canonicalization happens in `roomIdFor`).
 *   - Read-only cwds (the home directory is always writable).
 *
 * Caller workflow:
 *   const lock = await acquireCwdLock(cwd);
 *   if (!lock.ok) { ui.notify("Já tem um agente rodando nessa pasta."); return; }
 *   // …run /remote-pi normally; lock auto-releases on process exit
 */

/** Resolved at call time (not module load) so tests can redirect the lock
 *  dir away from the developer's real `~/.pi/remote/locks` via
 *  `REMOTE_PI_DIR` / `REMOTE_PI_HOME` — the shared override every site honors. */
function locksDir(): string {
  return join(remotePiHome(), "locks");
}

export interface AcquiredLock {
  ok: true;
  /** Manual release. Optional — process exit cleans up too. */
  release(): void;
}

export interface RefusedLock {
  ok: false;
  /** Where the live lock socket lives, in case the caller wants to log it. */
  lockPath: string;
}

export type CwdLockResult = AcquiredLock | RefusedLock;

/**
 * Lock id for an agent. Keyed by **(cwd, name)** so several agents can run in
 * the SAME folder as long as their names differ — the per-folder singleton is
 * now a per-(folder,name) singleton.
 *
 * plan/41: this is the SAME derivation as the App↔Pi `room_id` — `lockIdFor`
 * delegates to the shared `roomIdFor(cwd, name)`. So the per-(folder,name) lock
 * and the announced room stay in lockstep: a default/unnamed agent locks the
 * legacy cwd id (and owns the legacy room); a custom or `#N`-suffixed name gets
 * a name-scoped id for both. Symlinks canonicalize via `realpath` inside
 * `roomIdFor`.
 */
function lockIdFor(cwd: string, name?: string): string {
  return roomIdFor(cwd, name);
}

/**
 * Local-IPC address of the lock for a given (cwd, name). Pure helper (no IO).
 * POSIX → a `.sock` file under `locksDir()`; Windows → a per-user named pipe.
 */
export function lockPathFor(cwd: string, name?: string): string {
  const id = lockIdFor(cwd, name);
  return ipcAddress(`lock-${id}`, join(locksDir(), `${id}.sock`));
}

/** Back-compat alias: the cwd-only lock path (no name component). */
export function lockPathForCwd(cwd: string): string {
  return lockPathFor(cwd);
}

/**
 * Attempts to acquire the cwd lock. Resolves with either:
 *   - `{ ok: true, release }` when we own it (server bound + retained).
 *   - `{ ok: false, lockPath }` when a live Pi already holds the lock.
 *
 * Self-healing path: if the prior holder crashed, the leftover socket file
 * fails `tryConnect` (ECONNREFUSED). We unlink it and retry the bind — the
 * second attempt then succeeds.
 *
 * The server holds no actual listener logic; its only job is to keep the
 * UDS endpoint pinned by the OS. No incoming connection ever does anything
 * useful — the next-Pi-attempt's `tryConnect` succeeding is the entire
 * signal we care about.
 */
export async function acquireCwdLock(cwd: string, name?: string): Promise<CwdLockResult> {
  const lockPath = lockPathFor(cwd, name);
  // POSIX: the lock socket is a file under locksDir → ensure the dir exists.
  // Windows: lockPath is a named pipe (`\\.\pipe\…`) — no parent dir to create.
  if (!usesNamedPipe()) mkdirSync(dirname(lockPath), { recursive: true });

  // First attempt: bind directly.
  let server: Server | null = await tryBind(lockPath);
  if (server) return _acquired(server, lockPath);

  // Bind failed — check whether the existing socket has a live listener.
  const probe = await tryConnect(lockPath);
  if (probe) {
    probe.destroy();
    return { ok: false, lockPath };
  }

  // POSIX: a leftover stale `.sock` file blocks the bind → clean it + retry.
  // Windows: a named pipe auto-disappears when its owner exits, so there is
  // never a stale pipe to remove.
  if (!usesNamedPipe()) removeStaleSock(lockPath);
  server = await tryBind(lockPath);
  if (server) return _acquired(server, lockPath);

  // Race: someone else bound between our unlink and retry. Treat as held.
  return { ok: false, lockPath };
}

function _acquired(server: Server, _lockPath: string): AcquiredLock {
  let released = false;
  // Don't keep the event loop alive just to hold the socket — the Pi
  // process has its own reasons to stay up (relay WS, broker, etc.).
  // When those are gone, the OS will tear the socket down with us.
  server.unref();
  return {
    ok: true,
    release: () => {
      if (released) return;
      released = true;
      try { server.close(); } catch { /* ignored */ }
    },
  };
}
