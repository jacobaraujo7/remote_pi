import { existsSync, readdirSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { ensurePrivateDirSync } from "../secure_fs.js";

const HOME_PI_REMOTE = join(homedir(), ".pi", "remote");
const SESSIONS_DIR = join(HOME_PI_REMOTE, "sessions");
const SKILLS_DIR = join(HOME_PI_REMOTE, "skills");

/**
 * Fixed UDS session name. The local mesh is single per machine — every Pi
 * process on the host shares this broker. Previous versions exposed
 * multi-session support (named sessions, leave/rename/sessions commands);
 * those were removed in the 2026-05-23 simplification because in practice
 * every install converged on one session anyway and multi-session UX added
 * friction without value.
 */
export const LOCAL_SESSION_NAME = "local";

/** Ensures the new subdirs exist inside the existing ~/.pi/remote/. */
export function ensureGlobalDirs(): void {
  ensurePrivateDirSync(HOME_PI_REMOTE);
  ensurePrivateDirSync(SESSIONS_DIR);
  ensurePrivateDirSync(SKILLS_DIR);
}

export function ensureSessionDir(name: string): void {
  ensurePrivateDirSync(dirname(sessionSockPath(name)));
}

/** Path to the UDS socket for a named session. */
export function sessionSockPath(name: string): string {
  return join(SESSIONS_DIR, name, "broker.sock");
}

/** Path to the audit log for a named session. */
export function sessionAuditPath(name: string): string {
  return join(SESSIONS_DIR, name, "audit.jsonl");
}

/** Path to the session metadata JSON. */
export function sessionMetaPath(name: string): string {
  return join(SESSIONS_DIR, name, "session.json");
}

export function sessionsDir(): string {
  return SESSIONS_DIR;
}

export function skillsDir(): string {
  return SKILLS_DIR;
}

/** Lists discovered session names from disk. */
export function listSessions(): string[] {
  ensureGlobalDirs();
  try {
    return readdirSync(SESSIONS_DIR).filter((entry) => {
      try {
        return statSync(join(SESSIONS_DIR, entry)).isDirectory();
      } catch { return false; }
    });
  } catch {
    return [];
  }
}

/** Heuristic: a session has an existing broker.sock file. */
export function sessionHasSock(name: string): boolean {
  return existsSync(sessionSockPath(name));
}
