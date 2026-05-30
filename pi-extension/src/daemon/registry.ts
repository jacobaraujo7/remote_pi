import { existsSync, readFileSync, realpathSync } from "node:fs";
import { homedir } from "node:os";
import { isAbsolute, join, resolve as resolvePath } from "node:path";
import { writePrivateFileAtomicSync } from "../secure_fs.js";
import { daemonIdForCwd } from "./id.js";

/**
 * The global daemon registry: which working directories are promoted to
 * always-on daemons under the supervisor.
 *
 * Schema rationale (decision Q in plan/26): the registry stores **only**
 * `cwd` per entry. Everything else (agent_name, auto_start_relay, etc.)
 * is the cwd's local config at `<cwd>/.pi/remote-pi/config.json` — single
 * source of truth, no duplication. The daemon `id` is *derived* from cwd
 * via `daemonIdForCwd`, never persisted.
 *
 * Cwds are always normalized to an **absolute realpath** before storage.
 * A user typing `/remote-pi create ~/Movies` or `/remote-pi create .`
 * results in the same entry as `/remote-pi create /Users/x/Movies` — no
 * surprise duplicates, symlinks collapse correctly.
 */

/** Resolved at call time so tests can override via `REMOTE_PI_HOME`. The
 *  prod path is always `~/.pi/remote/daemons.json`. */
function registryPathInternal(): string {
  const root = process.env["REMOTE_PI_HOME"] || homedir();
  return join(root, ".pi", "remote", "daemons.json");
}

export interface DaemonEntry {
  /** Absolute realpath of the cwd this daemon manages. */
  cwd: string;
}

export interface DaemonRegistry {
  daemons: DaemonEntry[];
}

/**
 * Normalizes a user-provided path: expands `~`/`~/...`, resolves relative
 * components against `process.cwd()`, and runs `realpath` to canonicalize
 * symlinks. Throws if the resulting path doesn't exist on disk.
 *
 * `/remote-pi create` always stores normalized paths so two registrations
 * of the same logical folder via different aliases produce a single entry.
 */
export function normalizeCwd(input: string): string {
  if (!input || !input.trim()) {
    throw new Error("cwd is required");
  }
  let p = input.trim();
  // Expand `~` / `~/relative`. Shell wouldn't expand inside slash command args.
  if (p === "~") p = homedir();
  else if (p.startsWith("~/")) p = join(homedir(), p.slice(2));
  if (!isAbsolute(p)) p = resolvePath(process.cwd(), p);
  // realpath canonicalizes symlinks + throws if path doesn't exist.
  return realpathSync(p);
}

/** Reads the registry, returning an empty one when the file is absent. */
export function loadRegistry(): DaemonRegistry {
  if (!existsSync(registryPathInternal())) return { daemons: [] };
  try {
    const raw = readFileSync(registryPathInternal(), "utf8");
    const parsed = JSON.parse(raw) as unknown;
    if (!parsed || typeof parsed !== "object") return { daemons: [] };
    const arr = (parsed as { daemons?: unknown }).daemons;
    if (!Array.isArray(arr)) return { daemons: [] };
    const daemons: DaemonEntry[] = [];
    for (const item of arr) {
      if (!item || typeof item !== "object") continue;
      const cwd = (item as { cwd?: unknown }).cwd;
      if (typeof cwd === "string" && cwd.length > 0) {
        daemons.push({ cwd });
      }
    }
    return { daemons };
  } catch {
    return { daemons: [] };
  }
}

export function saveRegistry(reg: DaemonRegistry): void {
  writePrivateFileAtomicSync(registryPathInternal(), JSON.stringify(reg, null, 2) + "\n");
}

/**
 * Adds a daemon entry. Refuses duplicates (same normalized cwd already
 * present). Returns the derived id + normalized cwd so the caller can
 * report it back to the user.
 */
export function addDaemon(rawCwd: string): { id: string; cwd: string } {
  const cwd = normalizeCwd(rawCwd);
  const reg = loadRegistry();
  if (reg.daemons.some((d) => d.cwd === cwd)) {
    throw new Error(`Daemon already registered for cwd: ${cwd}`);
  }
  reg.daemons.push({ cwd });
  saveRegistry(reg);
  return { id: daemonIdForCwd(cwd), cwd };
}

/**
 * Removes the daemon entry whose derived id matches `id`. Returns the
 * removed cwd (if any). Does NOT touch the cwd's local config — `create`
 * the same cwd later restores the registration idempotently.
 */
export function removeDaemon(id: string): { removed: boolean; cwd?: string } {
  const reg = loadRegistry();
  const idx = reg.daemons.findIndex((d) => daemonIdForCwd(d.cwd) === id);
  if (idx === -1) return { removed: false };
  const [removed] = reg.daemons.splice(idx, 1);
  saveRegistry(reg);
  return { removed: true, cwd: removed!.cwd };
}

/** Snapshot of all registered daemons with derived ids. Order matches the
 *  file's insertion order — first-registered first. */
export function listDaemons(): Array<{ id: string; cwd: string }> {
  return loadRegistry().daemons.map((d) => ({
    id: daemonIdForCwd(d.cwd),
    cwd: d.cwd,
  }));
}

/** Test/diag-only: returns the on-disk path. Exported so tests can poke
 *  at it (e.g. tmpdir override is done via env, but for now the path is
 *  hardcoded to ~/.pi/remote/daemons.json). */
export function registryPath(): string {
  return registryPathInternal();
}
