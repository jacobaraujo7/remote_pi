import { describe, expect, test } from "vitest";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { SessionPeer } from "./peer.js";
import type { Envelope } from "./envelope.js";

function tmpSock(): string {
  const dir = mkdtempSync(join(tmpdir(), "pi-e2e-"));
  return join(dir, "broker.sock");
}

async function makePeer(sockPath: string, name: string, auditPath?: string): Promise<SessionPeer> {
  const peer = new SessionPeer({ sockPath, name, auditPath, defaultTimeoutMs: 3000 });
  await peer.start();
  return peer;
}

describe("agent-network e2e", () => {
  test("1) single agent join — peer alone with itself as leader", async () => {
    const sock = tmpSock();
    const p = await makePeer(sock, "solo");
    expect(p.name()).toBe("solo");
    expect(p.currentRole()).toBe("leader");
    await p.leave();
  });

  test("2) two agents request/reply — orq.request(backend) → pong", async () => {
    const sock = tmpSock();
    const orq = await makePeer(sock, "orq");
    const backend = await makePeer(sock, "backend");

    // backend replies to any inbound message
    backend.onMessage((env: Envelope) => {
      void backend.send(env.from, { reply_to: env.id, status: "ok", text: "pong" })
        .then(() => undefined)
        .catch(() => undefined);
      // Use proper request/reply pattern: respond with `re = env.id`.
      const reply = { type: "reply", original_id: env.id, text: "pong" };
      void (async () => {
        const { envelope, serialize } = await import("./envelope.js");
        // not actually used; we send directly via send() above which is fire-and-forget
        void envelope; void serialize; void reply;
      })();
    });

    // Skip the convenience handler approach — backend uses send() to reply.
    // For proper request/reply correlation we instead use a tailored handler:
    // (rewrite below)
    backend.onMessage(() => { /* no-op (already handled above) */ });

    // Approach: orq.request and backend's handler must emit a reply with re=id.
    // The handler above used backend.send which doesn't include `re`. Switch to
    // a low-level approach by re-creating backend's handler:
    await backend.leave();
    const backend2 = await makePeer(sock, "backend");
    backend2.onMessage(async (env) => {
      // Reply with re=env.id so orq's request() resolves.
      const { envelope, serialize } = await import("./envelope.js");
      const reply = envelope(backend2.name(), env.from, { ok: true, text: "pong" }, env.id);
      // Internal: write via the peer's send() with correlation — extend API.
      // SessionPeer doesn't expose direct reply; emulate with raw socket access.
      // Cleanest: add a `reply()` helper. For now, fake via private socket.
      const sockets = (backend2 as unknown as { socket: import("node:net").Socket | null }).socket;
      if (sockets) sockets.write(serialize(reply));
    });

    const result = await orq.request("backend", { text: "ping" }, 2000);
    expect((result.body as { ok: boolean }).ok).toBe(true);
    expect((result.body as { text: string }).text).toBe("pong");
    expect(result.re).toBeTruthy();

    await orq.leave();
    await backend2.leave();
  });

  test("3) parallel wave — Promise.all([req(be), req(fe)]) — both respond", async () => {
    const sock = tmpSock();
    const orq = await makePeer(sock, "orq");
    const be = await makePeer(sock, "be");
    const fe = await makePeer(sock, "fe");

    async function autoReply(p: SessionPeer, replyText: string) {
      p.onMessage(async (env) => {
        if (env.re !== null) return;  // skip replies
        const { envelope, serialize } = await import("./envelope.js");
        const env2 = envelope(p.name(), env.from, { text: replyText }, env.id);
        const s = (p as unknown as { socket: import("node:net").Socket | null }).socket;
        if (s) s.write(serialize(env2));
      });
    }
    await autoReply(be, "be-pong");
    await autoReply(fe, "fe-pong");

    const [r1, r2] = await Promise.all([
      orq.request("be", { q: "x" }, 2000),
      orq.request("fe", { q: "y" }, 2000),
    ]);
    expect((r1.body as { text: string }).text).toBe("be-pong");
    expect((r2.body as { text: string }).text).toBe("fe-pong");

    await orq.leave();
    await be.leave();
    await fe.leave();
  });

  test("6) name collision → auto-suffix #N", async () => {
    const sock = tmpSock();
    const p1 = await makePeer(sock, "backend");
    const p2 = await makePeer(sock, "backend");
    const p3 = await makePeer(sock, "backend");
    expect(p1.name()).toBe("backend");
    expect(p2.name()).toBe("backend#2");
    expect(p3.name()).toBe("backend#3");
    await p1.leave();
    await p2.leave();
    await p3.leave();
  });

  test("broadcast: msg pra todos exceto sender", async () => {
    const sock = tmpSock();
    const orq = await makePeer(sock, "orq");
    const a = await makePeer(sock, "a");
    const b = await makePeer(sock, "b");

    const inboxA: Envelope[] = [];
    const inboxB: Envelope[] = [];
    a.onMessage((e) => { if (typeof e.body === "object" && e.body && (e.body as { type?: string }).type !== "peer_joined" && (e.body as { type?: string }).type !== "peer_left") inboxA.push(e); });
    b.onMessage((e) => { if (typeof e.body === "object" && e.body && (e.body as { type?: string }).type !== "peer_joined" && (e.body as { type?: string }).type !== "peer_left") inboxB.push(e); });

    await orq.send("broadcast", { hello: "world" });
    await new Promise((r) => setTimeout(r, 100));

    expect(inboxA.length).toBe(1);
    expect(inboxB.length).toBe(1);
    expect((inboxA[0]!.body as { hello: string }).hello).toBe("world");

    await orq.leave(); await a.leave(); await b.leave();
  });
});
