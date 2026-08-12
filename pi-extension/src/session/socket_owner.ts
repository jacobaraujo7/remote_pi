// Identifies the process holding a listening AF_UNIX socket.
//
// A queued connection belongs to the listener, not to the client that made it,
// so a peer whose registration times out cannot release anything or repair the
// mesh on its own. Only the owning process can, by accepting, resuming, or
// exiting. The one useful thing the peer can do is say which process that is,
// which otherwise costs the operator a manual walk of /proc/net/unix and every
// /proc/<pid>/fd on the machine.
//
// Linux only: this reads /proc. Everywhere else the caller keeps its generic
// message rather than guessing.
import { readFile, readdir, readlink } from "node:fs/promises";
import { basename } from "node:path";
import { setTimeout as delay } from "node:timers/promises";

/**
 * Kernel process states in which a process cannot run its event loop, so no
 * amount of waiting produces a register_ack. Any other state is reported as
 * observed and nothing is inferred from it: a healthy broker under load can
 * miss a fixed deadline, and that is not evidence of a fault.
 */
const HALTED_STATES: Record<string, string> = {
  T: "suspended",
  t: "stopped by a debugger",
  Z: "a zombie",
  X: "dead",
};

export type SocketOwner = {
  pid: number;
  command: string;
  /** Kernel state as observed, e.g. "suspended" or "running". */
  state: string;
  /** True only when the state itself proves the process cannot answer. */
  halted: boolean;
};

/** Listening sockets report `01`; queued and connected ones do not. */
const ST_LISTENING = "01";

/**
 * Ceiling on how long a caller waits for this diagnosis. It runs on a path
 * where a descriptor has already been released and someone is waiting to
 * report an error, so the wait must be bounded by wall clock rather than by
 * how many processes and descriptors happen to exist.
 */
export const OWNER_LOOKUP_BUDGET_MS = 250;

async function listeningInode(sockPath: string): Promise<string | null> {
  const table = await readFile("/proc/net/unix", "utf8");
  for (const line of table.split("\n")) {
    // Num RefCount Protocol Flags Type St Inode Path
    const cols = line.trim().split(/\s+/);
    if (cols.length < 8) continue;
    if (cols[5] !== ST_LISTENING) continue;
    if (cols[cols.length - 1] !== sockPath) continue;
    return cols[6];
  }
  return null;
}

/**
 * Walks /proc until the descriptor turns up or `deadline` passes. Abandoning
 * the walk is a real stop, not a race against work that keeps running.
 */
async function pidHoldingInode(inode: string, deadline: number): Promise<number | null> {
  const target = `socket:[${inode}]`;
  for (const entry of await readdir("/proc")) {
    if (Date.now() >= deadline) return null;
    const pid = Number(entry);
    if (!Number.isInteger(pid) || pid <= 0) continue;
    let fds: string[];
    try {
      fds = await readdir(`/proc/${pid}/fd`);
    } catch {
      // Exited between listing and opening, or owned by another user.
      continue;
    }
    for (const fd of fds) {
      try {
        if ((await readlink(`/proc/${pid}/fd/${fd}`)) === target) return pid;
      } catch {
        // Descriptor closed mid-scan; keep looking.
      }
    }
  }
  return null;
}

async function readState(pid: number): Promise<{ state: string; halted: boolean }> {
  const stat = await readFile(`/proc/${pid}/stat`, "utf8");
  // The command field is parenthesized and may itself contain spaces or
  // parentheses, so the state character is read after the final ')'.
  const code = stat.slice(stat.lastIndexOf(")") + 2).trim().charAt(0);
  const halted = Object.prototype.hasOwnProperty.call(HALTED_STATES, code);
  return { state: halted ? HALTED_STATES[code] : "running", halted };
}

/**
 * A name the operator can match against `ps` output. `comm` is capped at 15
 * characters and runtimes overwrite it with a thread name, so Node processes
 * report "MainThread" there and identify nothing; the command line carries the
 * executable that was actually run.
 */
async function readCommand(pid: number): Promise<string> {
  try {
    const argv0 = (await readFile(`/proc/${pid}/cmdline`, "utf8")).split("\0")[0];
    if (argv0 !== "") return basename(argv0);
  } catch {
    // Kernel threads expose an empty cmdline; fall back to comm.
  }
  return (await readFile(`/proc/${pid}/comm`, "utf8")).trim();
}

async function lookup(sockPath: string, deadline: number): Promise<SocketOwner | null> {
  const inode = await listeningInode(sockPath);
  if (inode === null) return null;
  const pid = await pidHoldingInode(inode, deadline);
  if (pid === null) return null;
  const { state, halted } = await readState(pid);
  return { pid, command: await readCommand(pid), state, halted };
}

/**
 * Resolves the process listening on `sockPath`, or null when it cannot be
 * determined within `budgetMs`. Never throws.
 *
 * The budget is enforced twice, because one mechanism alone is not enough. The
 * race caps what the caller waits for even if a single /proc read stalls; the
 * deadline passed into the walk stops the abandoned scan shortly afterwards
 * instead of letting it run to completion unobserved.
 */
export async function describeSocketOwner(
  sockPath: string,
  budgetMs: number = OWNER_LOOKUP_BUDGET_MS,
): Promise<SocketOwner | null> {
  if (process.platform !== "linux") return null;
  const deadline = Date.now() + budgetMs;
  // `ref: false` so a pending diagnosis never holds the process open, and the
  // walk absorbs its own failure so losing the race cannot surface later as an
  // unhandled rejection.
  const expired = delay(budgetMs, null, { ref: false });
  const walk = lookup(sockPath, deadline).catch(() => null);
  return await Promise.race([walk, expired]);
}

/**
 * The operator-facing half of a registration timeout. Names the blocker when it
 * is known, and always ends with the same instruction so callers can rely on
 * one recovery contract regardless of what was discoverable.
 *
 * Only a halted owner earns a specific command. Missing a fixed deadline does
 * not prove a process is broken, and advising an operator to kill a busy broker
 * would turn a slow mesh into a destroyed one.
 */
export function describeRegistrationBlocker(sockPath: string, owner: SocketOwner | null): string {
  const preamble = `${sockPath} has a listener `;
  const tail = "resume or terminate it, then rejoin.";
  if (owner === null) {
    return preamble
      + "that never answered the register handshake. Its owning process is probably suspended "
      + `or blocked; ${tail}`;
  }
  const who = `owned by pid ${owner.pid} (${owner.command}), which is ${owner.state} `;
  if (owner.halted) {
    return preamble + who
      + `and cannot answer the register handshake. Resume it with \`kill -CONT ${owner.pid}\` `
      + `or terminate it, then rejoin.`;
  }
  return preamble + who
    + `and did not answer the register handshake in time. It may be busy rather than stuck, `
    + `so inspect pid ${owner.pid} before acting; ${tail}`;
}
