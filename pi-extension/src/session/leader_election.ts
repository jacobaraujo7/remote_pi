import { Server, Socket, createConnection, createServer } from "node:net";
import { existsSync, lstatSync, unlinkSync } from "node:fs";
import { setTimeout as delay } from "node:timers/promises";

const MAX_ATTEMPTS = 20;
const BASE_BACKOFF_MS = 30;
const JITTER_MS = 70;
const PROBE_TIMEOUT_MS = 500;

export type ElectionResult =
  | { role: "leader"; server: Server }
  | { role: "follower"; socket: Socket };

/**
 * UDS-based leader election. Tries to connect to `sockPath`; on failure, tries
 * to bind. If both lose the race (EADDRINUSE on bind, ECONNREFUSED on connect),
 * cleans up stale sock file and retries with jittered backoff.
 *
 * Returns the role + the live handle (server for leader, socket for follower).
 */
export async function joinOrLead(sockPath: string): Promise<ElectionResult> {
  for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
    if (existsSync(sockPath)) {
      const sock = await _tryConnect(sockPath);
      if (sock) return { role: "follower", socket: sock };
      _removeStaleSock(sockPath);
    }

    const server = await _tryBind(sockPath);
    if (server) return { role: "leader", server };

    await delay(BASE_BACKOFF_MS + Math.random() * JITTER_MS);
  }
  throw new Error(`leader election failed after ${MAX_ATTEMPTS} attempts: ${sockPath}`);
}

function _tryConnect(sockPath: string): Promise<Socket | null> {
  return new Promise((resolve) => {
    const sock = createConnection({ path: sockPath });
    let settled = false;
    const settle = (val: Socket | null) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      if (!val) sock.destroy();
      resolve(val);
    };
    const timer = setTimeout(() => settle(null), PROBE_TIMEOUT_MS);
    sock.once("connect", () => settle(sock));
    sock.once("error", () => settle(null));
  });
}

function _tryBind(sockPath: string): Promise<Server | null> {
  return new Promise((resolve) => {
    const server = createServer();
    let settled = false;
    const settle = (val: Server | null) => {
      if (settled) return;
      settled = true;
      if (!val) {
        try { server.close(); } catch { /* ignored */ }
      }
      resolve(val);
    };
    server.once("error", () => settle(null));
    server.listen(sockPath, () => settle(server));
  });
}

function _removeStaleSock(sockPath: string): void {
  try {
    const stat = lstatSync(sockPath);
    if (stat.isSocket()) unlinkSync(sockPath);
  } catch {
    // ENOENT or not-a-socket — nothing to clean up.
  }
}
