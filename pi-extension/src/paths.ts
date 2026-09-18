import { homedir } from "node:os";
import { join } from "node:path";

/**
 * Absolute root for remote-pi on-disk STATE: `sessions/`, `skills/`, the
 * paired-identity/`peers.json` store, the daemon registries (`daemons.json`,
 * `cron.json`), the cron/audit logs, the supervisor socket, and the cwd lock
 * dir. Every state path in the codebase derives from this one resolver so a
 * relocated install can never split its state across two roots.
 *
 * The GLOBAL `config.json` is the one exception — it follows the coding-agent
 * dir via `remotePiConfigHome()` (below), not this resolver — though by default
 * both land in the same place.
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
 * setting the override silently split `identity.json` away from `sessions/` and
 * the daemon state. Centralising here closes that hole.
 */
export function remotePiHome(): string {
  const dir = process.env["REMOTE_PI_DIR"];
  if (dir && dir.length > 0) return dir;
  return join(process.env["REMOTE_PI_HOME"] || homedir(), ".pi", "remote");
}

/**
 * Root for remote-pi's global `config.json` specifically (the machine-wide
 * relay URL + `defaults` block). Distinct from `remotePiHome()`: the Pi host
 * keeps its own global settings under `PI_CODING_AGENT_DIR`, and remote-pi's
 * config is a sibling of those, so it follows the agent dir when relocated
 * rather than the state dir.
 *
 * Precedence (resolved at CALL time):
 *
 *   1. `PI_CODING_AGENT_DIR` — the Pi host's settings root (default `~/.pi`).
 *      Config lives at `<PI_CODING_AGENT_DIR>/remote/config.json`, so with the
 *      default agent dir the path stays exactly `~/.pi/remote/config.json`.
 *   2. otherwise `remotePiHome()` — which itself stays settable via
 *      `REMOTE_PI_DIR` / `REMOTE_PI_HOME`. So a pure state relocation (no agent
 *      dir set) keeps config beside the rest of the state, as before.
 *
 * State (sessions, daemon registries, cwd locks, identity) is unaffected — only
 * `config.json` honours `PI_CODING_AGENT_DIR`.
 */
export function remotePiConfigHome(): string {
  const agentDir = process.env["PI_CODING_AGENT_DIR"];
  if (agentDir && agentDir.length > 0) return join(agentDir, "remote");
  return remotePiHome();
}
