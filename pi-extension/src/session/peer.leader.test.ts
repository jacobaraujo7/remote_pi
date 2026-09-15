import { once } from "node:events";
import { mkdtempSync, rmSync } from "node:fs";
import { createServer, type Server, type Socket } from "node:net";
import { tmpdir } from "node:os";
import { basename, join } from "node:path";
import { describe, expect, test, vi } from "vitest";
import { ipcAddress } from "./ipc.js";
// `vi.mock` is hoisted above these imports, so `peer.js` resolves the mocked
// broker even though this import is static.
import { SessionPeer } from "./peer.js";

// A broker that answers every registration with a well-formed line that is not
// a register_ack. The real Broker always acks correctly, so this is the only
// way to drive the leader's self-registration into its failure branch.
//
// `close` mirrors the real Broker.close contract: destroy accepted peer sockets
// first, then close the server. Without the destroy, the server stays open
// waiting on the live loopback connection and never releases the path.
vi.mock("./broker.js", () => ({
  Broker: class {
    private readonly server: Server;
    private readonly accepted = new Set<Socket>();

    constructor(opts: { server: Server }) {
      this.server = opts.server;
      this.server.on("connection", (sock: Socket) => {
        this.accepted.add(sock);
        sock.write(`${JSON.stringify({ type: "not_an_ack" })}\n`);
      });
    }

    async close(): Promise<void> {
      for (const sock of this.accepted) sock.destroy();
      this.accepted.clear();
      await new Promise<void>((resolve) => this.server.close(() => resolve()));
    }
  },
}));

describe("SessionPeer leader self-registration", () => {
  test("a malformed ack releases the broker path instead of stranding it", async () => {
    const dir = mkdtempSync(join(tmpdir(), "pi-peer-leader-"));
    const sockPath = ipcAddress(`peer-${basename(dir)}`, join(dir, "broker.sock"));

    try {
      // Nothing is listening, so election makes this peer the leader: it binds
      // the path, constructs the broker, then registers back over a loopback
      // connection. The mocked broker refuses that handshake.
      const peer = new SessionPeer({ sockPath, name: "leader-with-broken-broker" });
      const error = await peer.start().then(
        () => null,
        (reason: unknown) => reason,
      );

      expect.soft(error).toBeInstanceOf(Error);

      // The contract under test: a leader that cannot register itself must not
      // keep owning the path. If it does, every later session connects to a
      // broker whose owner reports "join failed" and the mesh is stranded.
      const replacement = createServer();
      const rebound = await new Promise<boolean>((resolve) => {
        replacement.once("error", () => resolve(false));
        replacement.listen(sockPath, () => resolve(true));
      });
      if (replacement.listening) {
        const closed = once(replacement, "close");
        replacement.close();
        await closed;
      }

      expect(rebound).toBe(true);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  }, 10_000);
});
