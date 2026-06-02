import { describe, expect, test } from "vitest";
import { mkdtempSync, readFileSync } from "node:fs";
import { setTimeout as wait } from "node:timers/promises";
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

describe("ACK protocol (plan/25 Wave 0)", () => {
  test("sendWithAck to idle peer → status=received in <200ms", async () => {
    const sock = tmpSock();
    const orq = await makePeer(sock, "orq");
    const backend = await makePeer(sock, "backend");

    const t0 = Date.now();
    const ack = await orq.sendWithAck("backend", { task: "ping" });
    const dt = Date.now() - t0;

    expect(ack.status).toBe("received");
    expect(ack.target).toBe("backend");
    expect(dt).toBeLessThan(200);

    await orq.leave(); await backend.leave();
  });

  test("plan/34: send to mid-turn peer is delivered, not dropped → status=received", async () => {
    const sock = tmpSock();
    const orq = await makePeer(sock, "orq");
    const backend = await makePeer(sock, "backend");

    // Even if backend announces it is mid-turn (legacy turn_state — now a
    // no-op at the broker), the message must still be delivered.
    await backend.send("broker", { type: "turn_state", busy: true });
    await new Promise((r) => setTimeout(r, 50));

    const backendInbox: Envelope[] = [];
    backend.onMessage((env) => {
      const body = env.body as { type?: string } | null;
      if (env.from === "broker") return;
      if (body && (body.type === "peer_joined" || body.type === "peer_left")) return;
      backendInbox.push(env);
    });

    const ack = await orq.sendWithAck("backend", { task: "ping-while-busy" });

    expect(ack.status).toBe("received");
    expect(ack.target).toBe("backend");

    // The envelope reached the peer — reliable delivery, no drop.
    await new Promise((r) => setTimeout(r, 50));
    expect(backendInbox.length).toBe(1);

    await orq.leave(); await backend.leave();
  });

  test("plan/34: back-to-back new-work sends both deliver (no busy-on-delivery)", async () => {
    const sock = tmpSock();
    const orq = await makePeer(sock, "orq");
    const backend = await makePeer(sock, "backend");

    const backendInbox: Envelope[] = [];
    backend.onMessage((env) => {
      const body = env.body as { type?: string } | null;
      if (env.from === "broker") return;
      if (body && (body.type === "peer_joined" || body.type === "peer_left")) return;
      backendInbox.push(env);
    });

    // First send → received.
    const ack1 = await orq.sendWithAck("backend", { task: "t1" });
    expect(ack1.status).toBe("received");

    // Second send, before any turn_end: previously this returned `busy`
    // (received = commitment). plan/34 removed that — it must also deliver.
    const ack2 = await orq.sendWithAck("backend", { task: "t2" });
    expect(ack2.status).toBe("received");

    await new Promise((r) => setTimeout(r, 50));
    expect(backendInbox.length).toBe(2);

    await orq.leave(); await backend.leave();
  });

  test("reply via send with re=<original> arrives in sender inbox (async pattern)", async () => {
    const sock = tmpSock();
    const orq = await makePeer(sock, "orq");
    const backend = await makePeer(sock, "backend");

    // Orq's inbox collects replies (skip broker control / peer events).
    const orqInbox: Envelope[] = [];
    orq.onMessage((env) => {
      if (env.from === "broker") return;
      orqInbox.push(env);
    });

    // Backend auto-replies once it sees a task, marking itself busy/idle
    // around its "turn".
    backend.onMessage(async (env) => {
      if (env.from === "broker") return;
      // simulate turn lifecycle
      await backend.send("broker", { type: "turn_state", busy: true });
      // do "work" then reply via send (not sendWithAck — broadcast-style reply)
      await backend.sendWithAck(env.from, { answer: 42 }, env.id);
      await backend.send("broker", { type: "turn_state", busy: false });
    });

    const ack = await orq.sendWithAck("backend", { question: "meaning?" });
    expect(ack.status).toBe("received");

    // wait for the async reply to round-trip
    await new Promise((r) => setTimeout(r, 200));

    expect(orqInbox.length).toBeGreaterThan(0);
    const reply = orqInbox.find((e) => e.from === "backend");
    expect(reply).toBeDefined();
    expect(reply!.re).toBe(ack.id);
    expect((reply!.body as { answer: number }).answer).toBe(42);

    await orq.leave(); await backend.leave();
  });

  test("sendWithAck resolves on cross-PC ACK (from=<pc>:broker)", async () => {
    const sock = tmpSock();
    const orq = await makePeer(sock, "orq");
    const broker = orq.localBroker()!;

    // Kick off a sendWithAck that points to an unknown local target — without
    // a sibling router the broker would silently drop. We want the ACK to
    // come from a fake cross-PC broker, simulating broker_remote on Pi-B
    // sending an ACK back via the relay → broker_remote on Pi-A → the local
    // UDS broker (injectFromRemote injects the ACK envelope into the sender's
    // socket).
    const pendingAck = orq.sendWithAck("trab:agent-1", { task: "ping" }, null, 1500);
    // Give the outbound write time to register in ackPending before injecting.
    await new Promise((r) => setTimeout(r, 30));

    // Locate the original send's id by inspecting ackPending — but it's
    // private. Instead, capture the outbound envelope id by sniffing the
    // last write on orq's socket. Simpler approach: peek via a wrapper.
    // We just attach a no-op onMessage to ensure the envelope is delivered
    // and assume the most recent uuid in ackPending is ours. Cleaner: use
    // sendWithAck's return type's `id` after resolution. Since we need
    // the id BEFORE resolution, take the path of injecting via broker:
    const ackPendingMap = (orq as unknown as { ackPending: Map<string, unknown> }).ackPending;
    const outboundId = [...ackPendingMap.keys()][0]!;

    const crossPcAck: Envelope = {
      from: "casa:broker",
      to: "orq",
      id: "01976000-0000-7000-8000-aaaaaaaaaaab",
      re: outboundId,
      body: { type: "ack", status: "received", target: "agent-1" },
    };
    expect(broker.injectFromRemote(crossPcAck)).toBe("received");

    const result = await pendingAck;
    expect(result.status).toBe("received");
    expect(result.target).toBe("agent-1");

    await orq.leave();
  });

  test("plan/34: injectFromRemote delivers new work and replies alike (no busy)", async () => {
    const sock = tmpSock();
    const orq = await makePeer(sock, "orq");
    const backend = await makePeer(sock, "backend");

    // Even if backend announced mid-turn (now a no-op at the broker), cross-PC
    // injection must deliver.
    await backend.send("broker", { type: "turn_state", busy: true });
    await new Promise((r) => setTimeout(r, 50));

    const leader = orq.currentRole() === "leader" ? orq : backend;
    const broker = leader.localBroker()!;
    expect(broker).toBeTruthy();

    const backendInbox: Envelope[] = [];
    backend.onMessage((env) => {
      if (env.from === "broker") return;
      backendInbox.push(env);
    });

    // New work (re=null) — delivered, not dropped.
    const newWork = {
      from: "casa:sess-3", to: "backend", id: "01976000-0000-7000-8000-000000000001",
      re: null, body: { task: "do thing" },
    };
    expect(broker.injectFromRemote(newWork)).toBe("received");

    // A reply (re set) — same outcome.
    const reply = {
      from: "casa:sess-3", to: "backend", id: "01976000-0000-7000-8000-000000000002",
      re: "01976000-0000-7000-8000-000000000003", body: { answer: 42 },
    };
    expect(broker.injectFromRemote(reply)).toBe("received");

    await new Promise((r) => setTimeout(r, 50));
    expect(backendInbox.length).toBe(2);

    await orq.leave(); await backend.leave();
  });

  test("injectFromRemote: unknown local peer → denied", async () => {
    const sock = tmpSock();
    const orq = await makePeer(sock, "orq");
    const broker = orq.localBroker()!;

    const env = {
      from: "casa:sess-3", to: "no-such-peer", id: "01976000-0000-7000-8000-000000000004",
      re: null, body: { x: 1 },
    };
    expect(broker.injectFromRemote(env)).toBe("denied");

    await orq.leave();
  });

  test("Broker.list_peers includes RemoteRouter.listRemotePeers", async () => {
    const sock = tmpSock();
    const orq = await makePeer(sock, "orq");
    const broker = orq.localBroker()!;

    broker.setRemoteRouter({
      tryRouteOutbound: () => false,
      listRemotePeers: () => ["trab:agent-1", "movel:agent-2"],
    });

    const reply = await orq.request("broker", { type: "list_peers" }, 1000);
    const peers = (reply.body as { peers: string[] }).peers;
    expect(peers).toContain("orq");
    expect(peers).toContain("trab:agent-1");
    expect(peers).toContain("movel:agent-2");

    broker.setRemoteRouter(null);
    await orq.leave();
  });

  test("Broker._route delegates to RemoteRouter for prefix-addressed envelopes", async () => {
    const sock = tmpSock();
    const orq = await makePeer(sock, "orq");
    const broker = orq.localBroker()!;

    const claimed: Envelope[] = [];
    broker.setRemoteRouter({
      tryRouteOutbound: (env) => { claimed.push(env); return true; },
      listRemotePeers: () => [],
    });

    await orq.send("trab:agent-1", { hello: 1 });
    await new Promise((r) => setTimeout(r, 50));
    expect(claimed.length).toBe(1);
    expect(claimed[0]!.to).toBe("trab:agent-1");

    broker.setRemoteRouter(null);
    await orq.leave();
  });

  test("audit.jsonl tags envelopes with via=uds for local routing", async () => {
    const sock = tmpSock();
    const auditDir = mkdtempSync(join(tmpdir(), "pi-audit-"));
    const audit = join(auditDir, "audit.jsonl");
    const orq = await makePeer(sock, "orq", audit);
    const backend = await makePeer(sock, "backend", audit);

    await orq.sendWithAck("backend", { task: "ping" });
    // Audit writes are async + best-effort; give them a tick.
    await wait(40);

    const lines = readFileSync(audit, "utf8").trim().split("\n").filter(Boolean).map((l) => JSON.parse(l));
    // Skip any peer-discovery / broker-control lines; find the unicast.
    const uds = lines.find((r) => r.from === "orq" && r.to === "backend");
    expect(uds).toBeDefined();
    expect(uds.via).toBe("uds");
    expect(uds.ack_status).toBe("received");

    await orq.leave(); await backend.leave();
  });

  test("audit.jsonl tags injectFromRemote envelopes with via=relay", async () => {
    const sock = tmpSock();
    const auditDir = mkdtempSync(join(tmpdir(), "pi-audit-"));
    const audit = join(auditDir, "audit.jsonl");
    const orq = await makePeer(sock, "orq", audit);
    const broker = orq.localBroker()!;

    const env = {
      from: "casa:sess-3", to: "orq", id: "01976000-0000-7000-8000-aaaaaaaaaaac",
      re: null, body: { task: "remote ping" },
    };
    expect(broker.injectFromRemote(env)).toBe("received");
    await wait(40);

    const lines = readFileSync(audit, "utf8").trim().split("\n").filter(Boolean).map((l) => JSON.parse(l));
    const relayLine = lines.find((r) => r.id === env.id);
    expect(relayLine).toBeDefined();
    expect(relayLine.via).toBe("relay");
    expect(relayLine.ack_status).toBe("received");

    await orq.leave();
  });

  test("no ACK for broadcast (multi-target, no authoritative recipient)", async () => {
    const sock = tmpSock();
    const orq = await makePeer(sock, "orq");
    const a = await makePeer(sock, "a");
    const b = await makePeer(sock, "b");

    // We expose ackPending behavior indirectly: if broker ACKed broadcasts,
    // we'd see the ack envelope in handlers. Sniff for it.
    const orqInbox: Envelope[] = [];
    orq.onMessage((env) => {
      if (env.from === "broker") orqInbox.push(env);
    });

    await orq.send("broadcast", { hello: "hi" });
    await new Promise((r) => setTimeout(r, 100));

    // No ack envelopes (only peer_joined/peer_left, which we filter below)
    const ackMessages = orqInbox.filter((e) => {
      const b = e.body as { type?: string } | null;
      return !!b && b.type === "ack";
    });
    expect(ackMessages.length).toBe(0);

    await orq.leave(); await a.leave(); await b.leave();
  });
});
