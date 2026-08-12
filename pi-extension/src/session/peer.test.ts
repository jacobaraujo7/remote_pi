import { once } from "node:events";
import { mkdtempSync, rmSync } from "node:fs";
import { createServer, type Socket } from "node:net";
import { tmpdir } from "node:os";
import { basename, join } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import { describe, expect, test } from "vitest";
import { ipcAddress } from "./ipc.js";
import { SessionPeer } from "./peer.js";

describe("SessionPeer registration", () => {
  test("destroys an unanswered registration socket after the timeout", async () => {
    const dir = mkdtempSync(join(tmpdir(), "pi-peer-"));
    const sockPath = ipcAddress(`peer-${basename(dir)}`, join(dir, "broker.sock"));
    const server = createServer();
    let acceptedSocket: Socket | null = null;
    const connection = once(server, "connection");
    const listening = once(server, "listening");
    server.listen(sockPath);
    await listening;

    try {
      const peer = new SessionPeer({ sockPath, name: "blocked-broker-client" });
      const start = peer.start();
      [acceptedSocket] = await connection as [Socket];
      acceptedSocket.resume();
      const socketClosed = once(acceptedSocket, "close");
      const error = await start.then(
        () => null,
        (reason: unknown) => reason,
      );
      const sawClose = await Promise.race([
        socketClosed.then(() => true),
        delay(500).then(() => false),
      ]);

      expect.soft(error).toBeInstanceOf(Error);
      const message = error instanceof Error ? error.message : String(error);
      expect.soft(message).toContain(sockPath);
      expect.soft(message).toContain("resume or terminate it, then rejoin");
      // This process owns the unanswered listener, so the diagnosis must name
      // it rather than leave the operator to search /proc for the blocker.
      if (process.platform === "linux") {
        expect.soft(message).toContain(`pid ${process.pid}`);
      }
      expect.soft(sawClose).toBe(true);
    } finally {
      acceptedSocket?.destroy();
      if (server.listening) {
        const closed = once(server, "close");
        server.close();
        await closed;
      }
      rmSync(dir, { recursive: true, force: true });
    }
  }, 10_000);
});
