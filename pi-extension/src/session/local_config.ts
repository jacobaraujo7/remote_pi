import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { basename, dirname, join } from "node:path";

const LOCAL_DIR = ".pi/remote-pi";
const LOCAL_FILE = "config.json";

export interface LocalConfig {
  agent_name?: string;
  session_name?: string;
  /**
   * If true (default), `/remote-pi` with no args auto-joins the session and
   * starts the relay on a fresh terminal. Added in plano 21. Legacy configs
   * without this field are treated as `true` for backward compatibility.
   */
  auto_start_relay?: boolean;
}

function pathFor(cwd: string): string {
  return join(cwd, LOCAL_DIR, LOCAL_FILE);
}

/** Returns true when `<cwd>/.pi/remote-pi/config.json` exists on disk. */
export function localConfigExists(cwd: string): boolean {
  return existsSync(pathFor(cwd));
}

export function loadLocalConfig(cwd: string): LocalConfig {
  const p = pathFor(cwd);
  if (!existsSync(p)) return {};
  try {
    const raw = readFileSync(p, "utf8");
    const parsed = JSON.parse(raw) as unknown;
    if (!parsed || typeof parsed !== "object") return {};
    return parsed as LocalConfig;
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

/** Default agent name when none is configured: basename of cwd. */
export function defaultAgentName(cwd: string): string {
  return basename(cwd) || "agent";
}

/** Resolves auto_start_relay with backward-compat (undefined → true). */
export function effectiveAutoStartRelay(cfg: LocalConfig): boolean {
  return cfg.auto_start_relay !== false;
}
