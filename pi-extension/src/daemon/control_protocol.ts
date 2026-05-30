/**
 * CLI ↔ supervisor IPC contract for `~/.pi/remote/supervisor.sock`.
 *
 * Framing: one JSON object per line, newline-terminated. The CLI sends a
 * single `ControlRequest`, the supervisor sends a single `ControlReply`,
 * both close the connection. No multiplexing, no streaming — each command
 * is a short round-trip.
 *
 * Plan/26 W2. The Pi RPC protocol (`pi --mode rpc`) used by the daemon
 * children themselves is a separate contract — see
 * `node_modules/@mariozechner/pi-coding-agent/dist/modes/rpc/rpc-types.d.ts`.
 * This file is strictly the supervisor's own control plane.
 */

/** Per-daemon runtime state observable through the supervisor. */
export type DaemonState = "running" | "stopped" | "starting" | "crashed";

export interface DaemonInfo {
  id: string;            // sha256(cwd)[0..8] — see daemon/id.ts
  cwd: string;           // absolute realpath
  name: string;          // from <cwd>/.pi/remote-pi/config.json agent_name
  state: DaemonState;
  pid?: number;          // current process pid, when running
  uptime_s?: number;     // since last successful spawn, when running
  restart_count?: number;
}

/** Requests sent CLI → supervisor. */
export type ControlRequest =
  | { op: "list" }
  | { op: "status" }
  | { op: "start_all" }
  | { op: "start"; id: string }
  | { op: "stop_all" }
  | { op: "restart_all" }
  | { op: "send"; id: string; text: string }
  | { op: "register"; cwd: string }
  | { op: "unregister"; id: string };

/** Replies sent supervisor → CLI. Tagged by `ok` boolean. */
export type ControlReply<T = unknown> =
  | { ok: true; data?: T }
  | { ok: false; error: string };

/**
 * Response shapes per op. Keep in sync with the supervisor handlers in
 * `daemon/supervisor.ts`. Used for typed client calls.
 */
export interface ControlReplyShapes {
  list: { daemons: DaemonInfo[] };
  status: { daemons: DaemonInfo[] };
  start_all: { started: string[]; already_running: string[] };
  start: { id: string; state: DaemonState; started: boolean };
  stop_all: { stopped: string[]; already_stopped: string[] };
  restart_all: { restarted: string[] };
  send: { id: string; delivered: boolean };
  register: { id: string; cwd: string };
  unregister: { removed: boolean; cwd?: string };
}

/** Convenience for typed `Client.request<...>("op")` calls. */
export type ControlReplyFor<Op extends ControlRequest["op"]> =
  Op extends keyof ControlReplyShapes ? ControlReplyShapes[Op] : never;

// ── Serialization helpers ────────────────────────────────────────────────────

const TRAILING_NEWLINE = "\n";

export function encodeRequest(req: ControlRequest): string {
  return JSON.stringify(req) + TRAILING_NEWLINE;
}

export function encodeReply<T>(reply: ControlReply<T>): string {
  return JSON.stringify(reply) + TRAILING_NEWLINE;
}

/**
 * Parses a single JSON line into a request. Throws on malformed input —
 * the supervisor catches and replies `{ok:false, error}` so the client
 * gets a clean error rather than an unframed disconnect.
 */
export function parseRequest(line: string): ControlRequest {
  let obj: unknown;
  try { obj = JSON.parse(line); }
  catch (e) { throw new Error(`malformed control request: ${(e as Error).message}`); }
  if (!obj || typeof obj !== "object") {
    throw new Error("control request must be a JSON object");
  }
  const op = (obj as { op?: unknown }).op;
  if (typeof op !== "string") {
    throw new Error("control request missing string `op` field");
  }
  // We don't validate every field shape here — supervisor handlers do it
  // per-op since the error messages are more specific that way.
  return obj as ControlRequest;
}

export function parseReply(line: string): ControlReply<unknown> {
  let obj: unknown;
  try { obj = JSON.parse(line); }
  catch (e) { throw new Error(`malformed control reply: ${(e as Error).message}`); }
  if (!obj || typeof obj !== "object") {
    throw new Error("control reply must be a JSON object");
  }
  const ok = (obj as { ok?: unknown }).ok;
  if (typeof ok !== "boolean") {
    throw new Error("control reply missing boolean `ok` field");
  }
  return obj as ControlReply<unknown>;
}
