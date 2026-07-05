import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { basename, dirname, join } from "node:path";

const LOCAL_DIR = ".pi/remote-pi";
const LOCAL_FILE = "config.json";

/**
 * Escape hatch: when set, carries the WHOLE local config as inline JSON,
 * bypassing the on-disk `config.json`. For CI/ops/daemons that inject config
 * via env instead of writing a file — mirrors `REMOTE_PI_RELAY` for the relay
 * URL. Takes precedence over the file; an unset/empty/unparseable value falls
 * back to the file (never fatal).
 */
const DIRECT_CONFIG_ENV = "REMOTE_PI_DIRECT_CONFIG";

export interface LocalConfig {
  agent_name?: string;
  /**
   * If true (default), `/remote-pi` with no args auto-joins the local UDS
   * mesh and starts the relay on a fresh terminal. The field name is
   * historical (plano 21); the UX wording was reworked to "use the relay
   * on this terminal to connect to the remote mesh (mobile + PCs)". Legacy
   * configs without this field are treated as `true` for backward compat.
   */
  auto_start_relay?: boolean;
  // `workspace?`/`worktree?` were removed (plan/38, reescrito 2026-06-08): the
  // mesh identity is `(cwd, nome)`, with `cwd` subsuming folder + worktree
  // disambiguation. Neither axis is derived anymore, so the config fields are
  // gone. Any stale `workspace`/`worktree` key in an on-disk/inline config is
  // simply ignored on read (parseLocalConfig surfaces only known fields).
}

function pathFor(cwd: string): string {
  return join(cwd, LOCAL_DIR, LOCAL_FILE);
}

/**
 * Normalize a name segment to a mesh-safe token: trim, replace the addressing
 * separators (`/ : @ #`) and whitespace runs with `-`, collapse repeats, strip
 * edges. The `@` is included so a sanitized name can never contain the address
 * separator — `<cwd>@<name>` stays unambiguous on the wire. Returns undefined
 * when the input isn't a usable non-empty string, sanitizes to empty, or is a
 * reserved addressing keyword (`broadcast` / `broker`). Used by the broker's
 * `sanitizeMeshName` to keep the `<nome>` half of a peer address safe to
 * compose (plan/38).
 */
export function sanitizeSegment(v: unknown): string | undefined {
  if (typeof v !== "string") return undefined;
  const token = v.trim().replace(/[/:@#\s]+/g, "-").replace(/-{2,}/g, "-").replace(/^-+|-+$/g, "");
  if (!token) return undefined;
  if (token.toLowerCase() === "broadcast" || token.toLowerCase() === "broker") return undefined;
  return token;
}

/**
 * Migrate a persisted `agent_name` to the plan/38 leaf-name model (decision E).
 * Two legacy shapes get rewritten on read so a pre-fix config never fossilizes a
 * runtime accident as if it were an explicit choice:
 *
 *   - **`#N` collision suffix** — could only have come from a broker/lock
 *     assignment (the user can't type `#`: `sanitizeSegment` maps it to `-`), so
 *     a trailing `#<digits>` is stripped and the clean base re-derived.
 *   - **legacy `parent/folder`** — the old `defaultAgentName` shape; the `/`
 *     means it predates the leaf-only model, so we keep only the leaf segment.
 *
 * Returns the cleaned name, or undefined when nothing usable remains (so the
 * caller falls back to `defaultAgentName(cwd)`).
 */
export function migrateAgentName(raw: string): string | undefined {
  // Legacy `parent/folder` (or any path-ish value) → keep the trailing segment.
  const leaf = raw.includes("/") ? raw.slice(raw.lastIndexOf("/") + 1) : raw;
  // Drop a runtime collision suffix a pre-fix build may have frozen into config.
  const clean = leaf.replace(/#\d+$/, "").trim();
  return clean.length > 0 ? clean : undefined;
}

/**
 * Parse a raw JSON string into a LocalConfig, surfacing only known fields.
 * Returns null when the input isn't a usable JSON object. Legacy `session_name`
 * from pre-refactor configs is silently dropped — the local UDS mesh is now
 * always a single fixed session, so the field has no meaning.
 */
function parseLocalConfig(raw: string): LocalConfig | null {
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw) as unknown;
  } catch {
    return null;
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return null;
  const src = parsed as Record<string, unknown>;
  const cfg: LocalConfig = {};
  if (typeof src["agent_name"] === "string") {
    // Migrate on read (plan/38 decision E): strip a frozen `#N` and the legacy
    // `parent/folder` shape so neither fossilizes as an explicit name.
    const migrated = migrateAgentName(src["agent_name"]);
    if (migrated) cfg.agent_name = migrated;
  }
  if (typeof src["auto_start_relay"] === "boolean") cfg.auto_start_relay = src["auto_start_relay"];
  return cfg;
}

/** Inline config from `REMOTE_PI_DIRECT_CONFIG`, when set + parseable; else null. */
function directConfig(): LocalConfig | null {
  const raw = process.env[DIRECT_CONFIG_ENV];
  if (!raw || raw.trim().length === 0) return null;
  return parseLocalConfig(raw);
}

/**
 * True when a local config is available for this cwd — either inline via
 * `REMOTE_PI_DIRECT_CONFIG` or as `<cwd>/.pi/remote-pi/config.json` on disk.
 */
export function localConfigExists(cwd: string): boolean {
  return directConfig() !== null || existsSync(pathFor(cwd));
}

export function loadLocalConfig(cwd: string): LocalConfig {
  // Precedence: inline `REMOTE_PI_DIRECT_CONFIG` env wins over the file. An
  // unset/empty/malformed env falls through to the on-disk config.json.
  const direct = directConfig();
  if (direct) return direct;

  const p = pathFor(cwd);
  if (!existsSync(p)) return {};
  try {
    return parseLocalConfig(readFileSync(p, "utf8")) ?? {};
  } catch {
    return {};
  }
}

export function saveLocalConfig(cwd: string, patch: Partial<LocalConfig>): void {
  const p = pathFor(cwd);
  const current = loadLocalConfig(cwd);
  const next: LocalConfig = { ...current, ...patch };
  // Always persist auto_start_relay explicitly (default true) so future reads
  // never need to guess. Backward-compat: legacy files without the field
  // are treated as true on read; we lock that intent in on first save.
  if (typeof next.auto_start_relay !== "boolean") next.auto_start_relay = true;
  // Best-effort persistence: a read-only config.json is a legitimate deployment
  // (NixOS/Home Manager symlink into the immutable Nix store, read-only root,
  // EPERM). The name/config sync is cosmetic — it must NEVER crash the pi
  // process with an uncaughtException. `saveLocalConfig` is reached via
  // fire-and-forget async paths (`void _syncNameFromPi()` from `turn_start` /
  // `session_start`), so a sync throw from `mkdirSync`/`writeFileSync` sails
  // past the runner's per-handler try/catch and takes down pi. Guard both fs
  // calls together so a partial attempt can't throw past the caller.
  try {
    mkdirSync(dirname(p), { recursive: true });
    writeFileSync(p, JSON.stringify(next, null, 2));
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.warn(`[remote-pi] could not persist local config ${p}: ${message}`);
  }
}

/**
 * Default agent name when none is configured (plan/38 decision D): the **leaf**
 * of the cwd, `basename(cwd)`. The cwd now travels as its own address axis
 * (`<cwd>@<nome>`), so the name no longer needs the `parent/folder` prefix that
 * used to disambiguate folders — the broker keys peers by `(cwd, nome)`, and a
 * clean leaf means `#N` almost never fires. Falls back to `"agent"` for a
 * path with no usable basename (root / empty).
 */
export function defaultAgentName(cwd: string): string {
  return basename(cwd) || "agent";
}

/** Resolves auto_start_relay with backward-compat (undefined → true). */
export function effectiveAutoStartRelay(cfg: LocalConfig): boolean {
  return cfg.auto_start_relay !== false;
}
