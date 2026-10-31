import { homedir } from "node:os";
import { basename, join } from "node:path";

/**
 * Backend-aware state paths (issue #170 — oh-my-pi support).
 *
 * Remote Pi reads and writes state under `~/.pi/…` (per-user) and
 * `<cwd>/.pi/…` (per-project). oh-my-pi is a hard fork of pi with an
 * identical extension surface but a separate state root (`~/.omp`), so a
 * daemon running under `omp` must keep its registry, cron, locks, identity
 * and local config under the omp namespace instead — otherwise an omp
 * install silently reads pi's state (or vice versa).
 *
 * Every module that resolves a `.pi` path goes through these helpers. The
 * namespace is selected per-process by `REMOTE_PI_STATE_PREFIX`
 * (`.omp` selects oh-my-pi; anything else keeps the default `.pi`). The
 * service templates render the variable into the supervisor's environment
 * (see `daemon/install.ts`), so a pinned install survives reboots without
 * the user exporting anything interactively.
 */

/** Env var that pins the state namespace. Set to `.omp` for oh-my-pi. */
export const REMOTE_PI_STATE_PREFIX_ENV = "REMOTE_PI_STATE_PREFIX";

/**
 * The state namespace for this process: `.omp` when
 * `REMOTE_PI_STATE_PREFIX=.omp` is set, `.pi` otherwise. Narrow literal
 * type — every caller composes paths from one of exactly these two roots.
 */
export function statePrefix(): ".pi" | ".omp" {
  return process.env[REMOTE_PI_STATE_PREFIX_ENV]?.trim() === ".omp" ? ".omp" : ".pi";
}

/**
 * Per-user state root: `~/<prefix>/remote` (honors `REMOTE_PI_HOME`, the
 * same test/ops override the daemon registry already uses). Holds the
 * registry, cron store, supervisor socket, identity/peers and config.
 */
export function userStateRoot(): string {
  return join(process.env["REMOTE_PI_HOME"] || homedir(), statePrefix(), "remote");
}

/**
 * Per-project state root: `<cwd>/<prefix>`. This is the directory the
 * agent itself reads project settings/extensions from, so the daemon's
 * child must agree with it for `-e`/settings to resolve under omp.
 */
export function projectStateRoot(cwd: string): string {
  return join(cwd, statePrefix());
}

/** Per-project remote-pi config dir: `<cwd>/<prefix>/remote-pi`. */
export function localConfigDir(cwd: string): string {
  return join(projectStateRoot(cwd), "remote-pi");
}

/** Per-project agent settings file: `<cwd>/<prefix>/settings.json`. */
export function projectSettingsPath(cwd: string): string {
  return join(projectStateRoot(cwd), "settings.json");
}

/**
 * The state namespace implied by an agent binary: an explicit
 * `REMOTE_PI_STATE_PREFIX` wins (the operator may pin namespaces
 * independently), otherwise a binary named `omp*` implies `.omp` and
 * anything else `.pi`. Used at install time to render the service
 * environment consistently with the detected agent.
 */
export function statePrefixForAgentBin(agentBin: string): ".pi" | ".omp" {
  const pinned = process.env[REMOTE_PI_STATE_PREFIX_ENV]?.trim();
  if (pinned === ".omp" || pinned === ".pi") return pinned;
  return basename(agentBin).toLowerCase().startsWith("omp") ? ".omp" : ".pi";
}
