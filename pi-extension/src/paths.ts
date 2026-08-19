import { homedir } from "node:os";
import { join } from "node:path";

/**
 * Absolute root for ALL remote-pi on-disk state: `config.json`, `sessions/`,
 * `skills/`, the paired-identity/`peers.json` store, the daemon registries
 * (`daemons.json`, `cron.json`), the cron/audit logs, the supervisor socket,
 * and the cwd lock dir. Every path in the codebase derives from this one
 * resolver so a relocated install can never split its state across two roots.
 *
 * Precedence (resolved at CALL time so tests — and a relocated deployment —
 * can override via env without re-importing):
 *
 *   1. `REMOTE_PI_DIR`  — an ABSOLUTE override of the state dir itself. Lets the
 *      state live at an arbitrary path (e.g. an XDG-style
 *      `~/.config/pi/remote-pi`) with no forced `.pi/remote` suffix. This is the
 *      knob to reach for when relocating; `REMOTE_PI_HOME` cannot express it.
 *   2. `REMOTE_PI_HOME` — a stand-in `$HOME`; state lives at
 *      `<REMOTE_PI_HOME>/.pi/remote`. Long-standing test/override knob, kept for
 *      backward compatibility.
 *   3. `os.homedir()`   — the default, `~/.pi/remote`.
 *
 * Historically `config.ts` and `pairing/storage.ts` resolved this from
 * `os.homedir()` directly while seven other sites honoured `REMOTE_PI_HOME`, so
 * setting the override silently split `config.json`/`identity.json` away from
 * `sessions/` and the daemon state. Centralising here closes that hole.
 */
export function remotePiHome(): string {
  const dir = process.env["REMOTE_PI_DIR"];
  if (dir && dir.length > 0) return dir;
  return join(process.env["REMOTE_PI_HOME"] || homedir(), ".pi", "remote");
}
