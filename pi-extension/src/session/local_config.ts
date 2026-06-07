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
  /**
   * Logical project namespace (plan/38). When set, it's prefixed onto this
   * agent's mesh identity so agents of different projects — or different git
   * worktrees of the same repo — don't collide on the local broker and stay
   * scoped to their own group. Sanitized to a mesh-safe token on read.
   */
  workspace?: string;
  /**
   * OPTIONAL override of the worktree label (plan/38). Normally LEFT UNSET —
   * the effective worktree is derived from git at runtime (branch / dir) and
   * is NOT a persisted preference. Set this only to pin a custom label.
   * Sanitized to a mesh-safe token on read.
   */
  worktree?: string;
}

function pathFor(cwd: string): string {
  return join(cwd, LOCAL_DIR, LOCAL_FILE);
}

/**
 * Normalize a workspace/worktree segment to a mesh-safe token: trim, replace
 * the addressing separators (`/ : #`) and whitespace runs with `-`, collapse
 * repeats, strip edges. Returns undefined when the input isn't a usable
 * non-empty string, sanitizes to empty, or is a reserved addressing keyword
 * (`broadcast` / `broker`). Keeps these dimensions safe to compose into a
 * peer address (plan/38) regardless of source (file or inline env).
 */
function sanitizeSegment(v: unknown): string | undefined {
  if (typeof v !== "string") return undefined;
  const token = v.trim().replace(/[/:#\s]+/g, "-").replace(/-{2,}/g, "-").replace(/^-+|-+$/g, "");
  if (!token) return undefined;
  if (token.toLowerCase() === "broadcast" || token.toLowerCase() === "broker") return undefined;
  return token;
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
  if (typeof src["agent_name"] === "string") cfg.agent_name = src["agent_name"];
  if (typeof src["auto_start_relay"] === "boolean") cfg.auto_start_relay = src["auto_start_relay"];
  const workspace = sanitizeSegment(src["workspace"]);
  if (workspace) cfg.workspace = workspace;
  const worktree = sanitizeSegment(src["worktree"]);
  if (worktree) cfg.worktree = worktree;
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
  mkdirSync(dirname(p), { recursive: true });
  const current = loadLocalConfig(cwd);
  const next: LocalConfig = { ...current, ...patch };
  // Always persist auto_start_relay explicitly (default true) so future reads
  // never need to guess. Backward-compat: legacy files without the field
  // are treated as true on read; we lock that intent in on first save.
  if (typeof next.auto_start_relay !== "boolean") next.auto_start_relay = true;
  writeFileSync(p, JSON.stringify(next, null, 2));
}

/**
 * Default agent name when none is configured: `<parent>/<folder>` of the
 * given cwd. Falls back gracefully when the parent isn't meaningful
 * (root, current dir, single-segment paths) — in those cases just the
 * folder name. Purpose: surface a non-empty string the user can accept
 * by pressing enter in the wizard.
 */
export function defaultAgentName(cwd: string): string {
  const folder = basename(cwd);
  const parent = basename(dirname(cwd));
  if (!folder) return "agent";
  if (!parent || parent === "/" || parent === folder || parent === ".") return folder;
  return `${parent}/${folder}`;
}

/** Resolves auto_start_relay with backward-compat (undefined → true). */
export function effectiveAutoStartRelay(cfg: LocalConfig): boolean {
  return cfg.auto_start_relay !== false;
}
