import { existsSync, mkdirSync, readdirSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const HOME_PI_REMOTE = join(homedir(), ".pi", "remote");
const SESSIONS_DIR = join(HOME_PI_REMOTE, "sessions");
const SKILLS_DIR = join(HOME_PI_REMOTE, "skills");

/** Ensures the new subdirs exist inside the existing ~/.pi/remote/. */
export function ensureGlobalDirs(): void {
  mkdirSync(SESSIONS_DIR, { recursive: true });
  mkdirSync(SKILLS_DIR, { recursive: true });
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
