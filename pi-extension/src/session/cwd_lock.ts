import { homedir } from "node:os";
import { dirname, join } from "node:path";
import type { Server } from "node:net";
import { roomIdForCwd } from "../rooms.js";
import { ensurePrivateDirSync } from "../secure_fs.js";
import { removeStaleSock, tryBind, tryConnect } from "./leader_election.js";

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
 * Lock files live in `~/.pi/remote/locks/<roomId>.sock` (where `roomId` is
 * `sha256(realpath(cwd))[:12]`), NOT inside the cwd itself, to dodge:
 *   - The 104/108-char path-length limit on UDS sockets on macOS/Linux.
 *   - Symlinked cwds (realpath canonicalization happens in `roomIdForCwd`).
 *   - Read-only cwds (the home directory is always writable).
 *
 * Caller workflow:
 *   const lock = await acquireCwdLock(cwd);
 *   if (!lock.ok) { ui.notify("Já tem um agente rodando nessa pasta."); return; }
 *   // …run /remote-pi normally; lock auto-releases on process exit
 */

const LOCKS_DIR = join(homedir(), ".pi", "remote", "locks");

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

/** Path of the lock socket for a given cwd. Pure helper (no IO). */
export function lockPathForCwd(cwd: string): string {
  return join(LOCKS_DIR, `${roomIdForCwd(cwd)}.sock`);
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
export async function acquireCwdLock(cwd: string): Promise<CwdLockResult> {
  const lockPath = lockPathForCwd(cwd);
  ensurePrivateDirSync(dirname(lockPath));

  // First attempt: bind directly.
  let server: Server | null = await tryBind(lockPath);
  if (server) return _acquired(server, lockPath);

  // Bind failed — check whether the existing socket has a live listener.
  const probe = await tryConnect(lockPath);
  if (probe) {
    probe.destroy();
    return { ok: false, lockPath };
  }

  // Socket is stale (no listener answered). Clean up + retry bind once.
  removeStaleSock(lockPath);
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
