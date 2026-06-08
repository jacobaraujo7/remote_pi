import { existsSync } from "node:fs";
import { createConnection, type Socket } from "node:net";
import {
  type ControlReply,
  type ControlReplyFor,
  type ControlRequest,
  encodeRequest,
  parseReply,
} from "./control_protocol.js";
import { getSupervisorSockPath } from "./supervisor.js";
import { usesNamedPipe } from "../session/ipc.js";

/**
 * Tiny client for the `remote-pi` CLI to call the supervisor over the
 * `~/.pi/remote/supervisor.sock` UDS.
 *
 * Each call opens a fresh connection, sends one request line, reads one
 * reply line, closes. No connection pooling — the CLI is short-lived,
 * latency is dominated by the socket round-trip (<1ms).
 *
 * `SupervisorOfflineError` is the common error: thrown when the socket
 * file is missing OR the connect fails (no listener). The CLI handler
 * formats it as a friendly "Run `remote-pi install` first" message.
 */

const CONNECT_TIMEOUT_MS = 1000;
const REPLY_TIMEOUT_MS = 5000;

export class SupervisorOfflineError extends Error {
  constructor(public readonly sockPath: string) {
    super(
      `Supervisor is not running. UDS not responding at ${sockPath}.\n` +
      "Run `remote-pi install` to set it up, or start it manually with `pi-supervisord`.",
    );
    this.name = "SupervisorOfflineError";
  }
}

/**
 * Sends a single request and returns the typed reply data.
 *
 * Throws:
 *   - `SupervisorOfflineError` when the supervisor isn't reachable.
 *   - `Error` from `parseReply` when the reply line is malformed.
 *   - The supervisor's own error string when `ok: false`.
 */
export async function callSupervisor<Op extends ControlRequest["op"]>(
  req: Extract<ControlRequest, { op: Op }>,
): Promise<ControlReplyFor<Op>> {
  const sockPath = getSupervisorSockPath();
  // POSIX fast-fail on a missing socket file. Windows pipes have no file —
  // skip the check and let `_connect` fail fast if the pipe isn't there.
  if (!usesNamedPipe() && !existsSync(sockPath)) throw new SupervisorOfflineError(sockPath);

  const sock = await _connect(sockPath);
  try {
    sock.write(encodeRequest(req));
    const line = await _readLine(sock);
    const reply = parseReply(line) as ControlReply<ControlReplyFor<Op>>;
    if (!reply.ok) throw new Error(reply.error);
    return reply.data as ControlReplyFor<Op>;
  } finally {
    sock.destroy();
  }
}

/** Returns true when the supervisor is reachable. Used by `/remote-pi
 *  daemons` to decide whether to query runtime state or fall back to
 *  registry-only listing. */
export async function supervisorOnline(): Promise<boolean> {
  const sockPath = getSupervisorSockPath();
  if (!usesNamedPipe() && !existsSync(sockPath)) return false;
  try {
    const sock = await _connect(sockPath);
    sock.destroy();
    return true;
  } catch {
    return false;
  }
}

// ── internals ───────────────────────────────────────────────────────────────

function _connect(sockPath: string): Promise<Socket> {
  return new Promise((resolve, reject) => {
    const sock = createConnection({ path: sockPath });
    let settled = false;
    const timer = setTimeout(() => {
      if (settled) return;
      settled = true;
      sock.destroy();
      reject(new SupervisorOfflineError(sockPath));
    }, CONNECT_TIMEOUT_MS);
    sock.once("connect", () => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      sock.setEncoding("utf8");
      resolve(sock);
    });
    sock.once("error", () => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      reject(new SupervisorOfflineError(sockPath));
    });
  });
}

function _readLine(sock: Socket): Promise<string> {
  return new Promise((resolve, reject) => {
    let buf = "";
    const timer = setTimeout(() => {
      reject(new Error("supervisor reply timeout"));
      sock.destroy();
    }, REPLY_TIMEOUT_MS);
    sock.on("data", (chunk: string) => {
      buf += chunk;
      const nl = buf.indexOf("\n");
      if (nl >= 0) {
        clearTimeout(timer);
        resolve(buf.slice(0, nl));
      }
    });
    sock.on("end", () => {
      clearTimeout(timer);
      const nl = buf.indexOf("\n");
      if (nl >= 0) return resolve(buf.slice(0, nl));
      if (buf.length > 0) return resolve(buf);
      reject(new Error("supervisor closed connection without replying"));
    });
    sock.on("error", (err) => {
      clearTimeout(timer);
      reject(err);
    });
  });
}
