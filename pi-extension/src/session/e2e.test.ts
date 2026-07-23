import { describe, expect, test, vi } from "vitest";
import { EventEmitter } from "node:events";
import { mkdtempSync, readFileSync } from "node:fs";
import { setTimeout as wait } from "node:timers/promises";
import { tmpdir } from "node:os";
import { basename, join } from "node:path";
import { createConnection } from "node:net";
import { ipcAddress } from "./ipc.js";
import { SessionPeer } from "./peer.js";
import { envelope, type Envelope } from "./envelope.js";
import { BrokerRemote } from "./broker_remote.js";
import { probeListPeers } from "../index.js";
import { composeAddress, sanitizeMeshName, type PeerInfo, type RemoteRouter } from "./broker.js";
import { migrateAgentName } from "./local_config.js";

function uniqueSock(): string {
  // Per-test unique IPC address. POSIX → a `.sock` file in a fresh tmpdir;
  // Windows → a named pipe whose name embeds the unique tmpdir basename
  // (pipes are machine-global, so the suffix must be unique — plan/40).
  const dir = mkdtempSync(join(tmpdir(), "pi-e2e-"));
  return ipcAddress(`e2e-${basename(dir)}`, join(dir, "broker.sock"));
}

const tmpSock = uniqueSock;

async function makePeer(sockPath: string, name: string, auditPath?: string): Promise<SessionPeer> {
  const peer = new SessionPeer({ sockPath, name, auditPath, defaultTimeoutMs: 3000 });
  await peer.start();
  return peer;
}

class FakePiForward extends EventEmitter {
  readonly sent: { toPc: string; env: Envelope }[] = [];
  private readonly queued: { toPc: string; env: Envelope }[] = [];
  private readonly waiters: Array<(
    sent: { toPc: string; env: Envelope },
  ) => void> = [];

  sendEnvelopeToPi(toPc: string, env: Envelope): void {
    const sent = { toPc, env };
    this.sent.push(sent);
    const waiter = this.waiters.shift();
    if (waiter) waiter(sent);
    else this.queued.push(sent);
  }

  nextOutbound(): Promise<{ toPc: string; env: Envelope }> {
    const sent = this.queued.shift();
    return sent
      ? Promise.resolve(sent)
      : new Promise((resolve) => this.waiters.push(resolve));
  }

  clearOutbound(): void {
    if (this.waiters.length > 0) {
      throw new Error("cannot clear FakePiForward with pending waiters");
    }
    this.sent.length = 0;
    this.queued.length = 0;
  }
}

function capturingRemoteRouter(): {
  router: RemoteRouter;
  nextOutbound: () => Promise<Envelope>;
} {
  const queued: Envelope[] = [];
  const waiters: Array<(env: Envelope) => void> = [];
  return {
    router: {
      tryRouteOutbound: (env) => {
        const waiter = waiters.shift();
        if (waiter) waiter(env);
        else queued.push(env);
        return true;
      },
      listRemotePeers: () => [],
      listRemotePeerInfos: () => [],
    },
    nextOutbound: () => {
      const env = queued.shift();
      return env ? Promise.resolve(env) : new Promise((resolve) => waiters.push(resolve));
    },
  };
}

async function flushUds(): Promise<void> {
  await new Promise<void>((resolve) => setImmediate(resolve));
  await new Promise<void>((resolve) => setImmediate(resolve));
}

function observe<T>(promise: Promise<T>): Promise<
  { status: "resolved"; value: T } | { status: "rejected"; reason: unknown }
> {
  return promise.then(
    (value) => ({ status: "resolved" as const, value }),
    (reason: unknown) => ({ status: "rejected" as const, reason }),
  );
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
  test("sendWithAck to idle peer → status=received, synchronously (not an LLM turn)", async () => {
    const sock = tmpSock();
    const orq = await makePeer(sock, "orq");
    const backend = await makePeer(sock, "backend");

    const t0 = Date.now();
    const ack = await orq.sendWithAck("backend", { task: "ping" });
    const dt = Date.now() - t0;

    expect(ack.status).toBe("received");
    expect(ack.target).toBe("backend");
    // The broker ACK is synchronous — it must NOT block on the peer taking a
    // turn. A generous ceiling proves "immediate, not a turn" without flaking
    // under CI/load (this used to be 200ms and broke `prepublishOnly`).
    expect(dt).toBeLessThan(2_000);

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

  test("sendWithAck to a local POSIX cwd containing a colon accepts the local broker ACK", async () => {
    const sock = tmpSock();
    const orq = await makePeer(sock, "orq");
    const local = new SessionPeer({
      sockPath: sock,
      name: "agent",
      cwd: "/tmp/a:b",
      defaultTimeoutMs: 3000,
    });
    await local.start();

    const ack = await orq.sendWithAck(local.address(), { task: "ping" });

    expect(local.address()).toBe("/tmp/a:b@agent");
    expect(ack).toMatchObject({ status: "received", target: local.address() });

    await orq.leave();
    await local.leave();
  });

  test("sendWithAck resolves on cross-PC ACK (from=<pc>:broker)", async () => {
    const sock = tmpSock();
    const orq = await makePeer(sock, "orq");
    const broker = orq.localBroker()!;
    const capture = capturingRemoteRouter();
    broker.setRemoteRouter(capture.router);

    try {
      const pendingAck = orq.sendWithAck("trab:agent-1", { task: "ping" }, null, 1500);
      const outbound = await capture.nextOutbound();
      const crossPcAck: Envelope = {
        from: "trab:broker",
        to: orq.address(),
        id: "01976000-0000-7000-8000-aaaaaaaaaaab",
        re: outbound.id,
        body: { type: "ack", status: "received", target: "agent-1" },
      };
      expect(broker.injectFromRemote(crossPcAck)).toBe("received");

      await expect(pendingAck).resolves.toMatchObject({
        status: "received",
        id: outbound.id,
        target: "agent-1",
      });
    } finally {
      broker.setRemoteRouter(null);
      await orq.leave();
    }
  });

  test("wrong remote ACK alias with the correct correlation id times out", async () => {
    const sock = tmpSock();
    const peer = await makePeer(sock, "orq");
    const broker = peer.localBroker()!;
    const capture = capturingRemoteRouter();
    broker.setRemoteRouter(capture.router);

    try {
      vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout"] });
      const pending = peer.sendWithAck("trab:agent-1", { task: "ping" }, null, 1_000);
      const outbound = await capture.nextOutbound();
      expect(broker.injectFromRemote(envelope(
        "casa:broker",
        peer.address(),
        { type: "ack", status: "received", target: "agent-1" },
        outbound.id,
      ))).toBe("received");
      await flushUds();
      await vi.advanceTimersByTimeAsync(1_000);
      await expect(pending).resolves.toEqual({ status: "timeout", id: outbound.id });
    } finally {
      broker.setRemoteRouter(null);
      await peer.leave();
      vi.useRealTimers();
    }
  });

  describe("ACK wire guard", () => {
    const invalidExactAckBodies: ReadonlyArray<{
      caseName: string;
      body: Record<string, unknown>;
    }> = [
      {
        caseName: "unsupported string status",
        body: { type: "ack", status: "future_status", target: "agent-1" },
      },
      {
        caseName: "non-string status",
        body: { type: "ack", status: 42, target: "agent-1" },
      },
      {
        caseName: "missing status",
        body: { type: "ack", target: "agent-1" },
      },
      {
        caseName: "missing target",
        body: { type: "ack", status: "received" },
      },
      {
        caseName: "non-string target",
        body: { type: "ack", status: "received", target: 42 },
      },
    ];

    test.each(invalidExactAckBodies)(
      "sendWithAck ignores invalid exact prefixed-broker ACK: $caseName",
      async ({ body }) => {
        const sock = tmpSock();
        const peer = await makePeer(sock, "orq");
        const broker = peer.localBroker()!;
        const capture = capturingRemoteRouter();
        const handler = vi.fn();
        peer.onMessage(handler);
        broker.setRemoteRouter(capture.router);

        try {
          vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout"] });
          let settled = false;
          const outcome = observe(
            peer.sendWithAck("trab:agent-1", { task: "ack-guard" }, null, 1_000),
          ).then((result) => {
            settled = true;
            return result;
          });
          const outbound = await capture.nextOutbound();

          expect(broker.injectFromRemote(envelope(
            "casa:broker",
            peer.address(),
            body,
            outbound.id,
          ))).toBe("received");
          await flushUds();

          expect(settled).toBe(false);
          expect(handler).not.toHaveBeenCalled();
          expect(vi.getTimerCount()).toBe(1);

          await vi.advanceTimersByTimeAsync(1_000);
          await expect(outcome).resolves.toEqual({
            status: "resolved",
            value: { status: "timeout", id: outbound.id },
          });
          expect(vi.getTimerCount()).toBe(0);
        } finally {
          broker.setRemoteRouter(null);
          await peer.leave();
          vi.useRealTimers();
        }
      },
    );

    test.each(invalidExactAckBodies)(
      "request ignores invalid exact prefixed-broker ACK: $caseName",
      async ({ body }) => {
        const sock = tmpSock();
        const peer = await makePeer(sock, "orq");
        const broker = peer.localBroker()!;
        const capture = capturingRemoteRouter();
        const handler = vi.fn();
        peer.onMessage(handler);
        broker.setRemoteRouter(capture.router);

        try {
          vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout"] });
          let settled = false;
          const outcome = observe(
            peer.request("trab:agent-1", { task: "ack-guard" }, 1_000),
          ).then((result) => {
            settled = true;
            return result;
          });
          const outbound = await capture.nextOutbound();

          expect(broker.injectFromRemote(envelope(
            "casa:broker",
            peer.address(),
            body,
            outbound.id,
          ))).toBe("received");
          await flushUds();

          expect(settled).toBe(false);
          expect(handler).not.toHaveBeenCalled();
          expect(vi.getTimerCount()).toBe(1);

          await vi.advanceTimersByTimeAsync(1_000);
          const result = await outcome;
          expect(result.status).toBe("rejected");
          if (result.status === "rejected") {
            expect(result.reason).toMatchObject({
              name: "Error",
              message: "request to trab:agent-1 timed out after 1000ms",
            });
          }
          expect(vi.getTimerCount()).toBe(0);
        } finally {
          broker.setRemoteRouter(null);
          await peer.leave();
          vi.useRealTimers();
        }
      },
    );

    test.each(["busy", "denied"] as const)(
      "valid exact prefixed-broker ACK preserves %s status and target",
      async (status) => {
        const sock = tmpSock();
        const peer = await makePeer(sock, "orq");
        const broker = peer.localBroker()!;
        const capture = capturingRemoteRouter();
        broker.setRemoteRouter(capture.router);

        try {
          vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout"] });
          let result: Awaited<ReturnType<SessionPeer["sendWithAck"]>> | undefined;
          const pending = peer.sendWithAck(
            "trab:agent-1",
            { task: "ack-compatibility" },
            null,
            1_000,
          ).then((value) => {
            result = value;
            return value;
          });
          const outbound = await capture.nextOutbound();
          const target = "agent-1";

          expect(broker.injectFromRemote(envelope(
            "trab:broker",
            peer.address(),
            { type: "ack", status, target },
            outbound.id,
          ))).toBe("received");
          await flushUds();

          const expected = { status, id: outbound.id, target };
          expect(result).toEqual(expected);
          await expect(pending).resolves.toEqual(expected);
          expect(vi.getTimerCount()).toBe(0);
        } finally {
          broker.setRemoteRouter(null);
          await peer.leave();
          vi.useRealTimers();
        }
      },
    );
  });

  test("trusted offline transport error immediately resolves sendWithAck with reason", async () => {
    const sock = tmpSock();
    const orq = await makePeer(sock, "orq");
    const broker = orq.localBroker()!;
    const capture = capturingRemoteRouter();
    broker.setRemoteRouter(capture.router);

    try {
      vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout"] });
      let result: Awaited<ReturnType<SessionPeer["sendWithAck"]>> | undefined;
      const pending = orq.sendWithAck("trab:agent-1", { task: "ping" }, null, 1000)
        .then((value) => { result = value; return value; });
      const outbound = await capture.nextOutbound();

      expect(broker.injectFromRemote({
        from: "broker",
        to: orq.address(),
        id: "01976000-0000-7000-8000-000000000101",
        re: outbound.id,
        body: { type: "transport_error", reason: "offline" },
      })).toBe("received");
      await flushUds();

      const expected = {
        status: "timeout",
        id: outbound.id,
        error: "transport_error: offline",
        reason: "offline",
      };
      expect(result).toEqual(expected);
      await expect(pending).resolves.toEqual(expected);
      expect(vi.getTimerCount()).toBe(0);
    } finally {
      broker.setRemoteRouter(null);
      await orq.leave();
      vi.useRealTimers();
    }
  });



  test.each(["not_authorized", "bad_envelope"] as const)(
    "trusted %s transport error immediately resolves sendWithAck as denied",
    async (reason) => {
      const sock = tmpSock();
      const orq = await makePeer(sock, "orq");
      const broker = orq.localBroker()!;
      const capture = capturingRemoteRouter();
      broker.setRemoteRouter(capture.router);

      try {
        vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout"] });
        let result: Awaited<ReturnType<SessionPeer["sendWithAck"]>> | undefined;
        const pending = orq.sendWithAck("trab:agent-1", { task: "ping" }, null, 1000)
          .then((value) => { result = value; return value; });
        const outbound = await capture.nextOutbound();

        expect(broker.injectFromRemote({
          from: "broker",
          to: orq.address(),
          id: reason === "not_authorized"
            ? "01976000-0000-7000-8000-000000000102"
            : "01976000-0000-7000-8000-000000000103",
          re: outbound.id,
          body: { type: "transport_error", reason },
        })).toBe("received");
        await flushUds();

        const expected = {
          status: "denied",
          id: outbound.id,
          error: `transport_error: ${reason}`,
          reason,
        };
        expect(result).toEqual(expected);
        await expect(pending).resolves.toEqual(expected);
        expect(vi.getTimerCount()).toBe(0);
      } finally {
        broker.setRemoteRouter(null);
        await orq.leave();
        vi.useRealTimers();
      }
    },
  );


  test("trusted broker transport error immediately rejects request once with MeshTransportError", async () => {
    const sock = tmpSock();
    const orq = await makePeer(sock, "orq");
    const broker = orq.localBroker()!;
    const capture = capturingRemoteRouter();
    broker.setRemoteRouter(capture.router);

    try {
      vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout"] });
      let settlements = 0;
      const pending = observe(orq.request("trab:agent-1", { task: "ping" }, 1000))
        .then((outcome) => { settlements += 1; return outcome; });
      const outbound = await capture.nextOutbound();
      const transportError: Envelope = {
        from: "broker",
        to: orq.address(),
        id: "01976000-0000-7000-8000-000000000104",
        re: outbound.id,
        body: { type: "transport_error", reason: "offline" },
      };

      expect(broker.injectFromRemote(transportError)).toBe("received");
      expect(broker.injectFromRemote(transportError)).toBe("received");
      await flushUds();

      const outcome = await pending;
      expect(outcome).toMatchObject({
        status: "rejected",
        reason: {
          name: "MeshTransportError",
          reason: "offline",
          correlationId: outbound.id,
          message: "transport_error: offline",
        },
      });
      expect(settlements).toBe(1);
      expect(vi.getTimerCount()).toBe(0);
    } finally {
      broker.setRemoteRouter(null);
      await orq.leave();
      vi.useRealTimers();
    }
  });

  test("duplicate trusted transport error settles once, clears timer, and is swallowed", async () => {
    const sock = tmpSock();
    const orq = await makePeer(sock, "orq");
    const broker = orq.localBroker()!;
    const capture = capturingRemoteRouter();
    const handler = vi.fn();
    orq.onMessage(handler);
    broker.setRemoteRouter(capture.router);

    try {
      vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout"] });
      let settlements = 0;
      const pending = orq.sendWithAck("trab:agent-1", { task: "ping" }, null, 1000)
        .then((value) => { settlements += 1; return value; });
      const outbound = await capture.nextOutbound();
      const errorEnvelope: Envelope = {
        from: "broker",
        to: orq.address(),
        id: "01976000-0000-7000-8000-000000000105",
        re: outbound.id,
        body: { type: "transport_error", reason: "offline" },
      };

      expect(broker.injectFromRemote(errorEnvelope)).toBe("received");
      expect(broker.injectFromRemote(errorEnvelope)).toBe("received");
      await flushUds();

      expect(settlements).toBe(1);
      await expect(pending).resolves.toEqual({
        status: "timeout",
        id: outbound.id,
        error: "transport_error: offline",
        reason: "offline",
      });
      expect(handler).not.toHaveBeenCalled();
      expect(vi.getTimerCount()).toBe(0);
    } finally {
      broker.setRemoteRouter(null);
      await orq.leave();
      vi.useRealTimers();
    }
  });

  test("local and remote forged transport error messages settle neither pending operation", async () => {
    const sock = tmpSock();
    const orq = await makePeer(sock, "orq");
    const sibling = await makePeer(sock, "sibling");
    const broker = orq.localBroker()!;
    const capture = capturingRemoteRouter();
    const handlerMessages: Envelope[] = [];
    orq.onMessage((env) => {
      if ((env.body as { type?: string } | null)?.type === "transport_error") {
        handlerMessages.push(env);
      }
    });
    broker.setRemoteRouter(capture.router);

    try {
      vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout"] });
      let ackSettled = false;
      let requestSettled = false;
      const ackOutcome = observe(orq.sendWithAck("trab:agent-1", { task: "ack" }, null, 1000))
        .then((outcome) => { ackSettled = true; return outcome; });
      const ackOutbound = await capture.nextOutbound();
      const requestOutcome = observe(orq.request("trab:agent-2", { task: "request" }, 1000))
        .then((outcome) => { requestSettled = true; return outcome; });
      const requestOutbound = await capture.nextOutbound();

      expect(broker.injectFromRemote(envelope(
        sibling.address(),
        orq.address(),
        { type: "transport_error", reason: "offline" },
        ackOutbound.id,
      ))).toBe("received");
      expect(broker.injectFromRemote({
        from: "casa:broker",
        to: orq.address(),
        id: "01976000-0000-7000-8000-000000000106",
        re: requestOutbound.id,
        body: { type: "transport_error", reason: "offline" },
      })).toBe("received");
      await flushUds();

      expect(handlerMessages).toEqual(expect.arrayContaining([
        expect.objectContaining({ from: sibling.address(), re: ackOutbound.id }),
        expect.objectContaining({ from: "casa:broker", re: requestOutbound.id }),
      ]));
      expect(ackSettled).toBe(false);
      expect(requestSettled).toBe(false);
      expect(vi.getTimerCount()).toBe(2);

      await vi.advanceTimersByTimeAsync(1000);
      await expect(ackOutcome).resolves.toEqual({
        status: "resolved",
        value: { status: "timeout", id: ackOutbound.id },
      });
      const requestResult = await requestOutcome;
      expect(requestResult.status).toBe("rejected");
      if (requestResult.status === "rejected") {
        expect(requestResult.reason).toMatchObject({
          message: "request to trab:agent-2 timed out after 1000ms",
        });
      }
      expect(vi.getTimerCount()).toBe(0);
    } finally {
      broker.setRemoteRouter(null);
      await sibling.leave();
      await orq.leave();
      vi.useRealTimers();
    }
  });


  test.each([
    { compatibility: "malformed 32-hex envelope id", malformed: "id" as const },
    { compatibility: "malformed 32-hex correlation id", malformed: "re" as const },
    { compatibility: "genuine silence", malformed: null },
  ])("$compatibility transport error cannot bypass the strict Broker boundary", async ({ malformed }) => {
    const sock = tmpSock();
    const orq = await makePeer(sock, "orq");
    const broker = orq.localBroker()!;
    const capture = capturingRemoteRouter();
    broker.setRemoteRouter(capture.router);

    try {
      vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout"] });
      const pending = orq.sendWithAck("trab:agent-1", { task: "ping" }, null, 1000);
      const outbound = await capture.nextOutbound();

      if (malformed) {
        expect(broker.injectFromRemote({
          from: "_relay",
          to: orq.address(),
          id: malformed === "id"
            ? "01976000000070008000000000000108"
            : "01976000-0000-7000-8000-000000000108",
          re: malformed === "re"
            ? "01976000000070008000000000000109"
            : outbound.id,
          body: { type: "transport_error", reason: "offline" },
        })).toBe("denied");
        await flushUds();
      }

      await vi.advanceTimersByTimeAsync(1000);
      await expect(pending).resolves.toEqual({ status: "timeout", id: outbound.id });
      expect(vi.getTimerCount()).toBe(0);
    } finally {
      broker.setRemoteRouter(null);
      await orq.leave();
      vi.useRealTimers();
    }
  });

  test("Relay offline errors cross BrokerRemote and real UDS with trusted legacy id normalization", async () => {
    const sock = uniqueSock();
    const peer = await makePeer(sock, "orq");
    const broker = peer.localBroker()!;
    const fakePi = new FakePiForward();
    const selfKey = Buffer.alloc(32, 17).toString("base64");
    const siblingKey = Buffer.alloc(32, 93).toString("base64");
    let bridge: BrokerRemote | undefined;

    try {
      bridge = new BrokerRemote({
        broker,
        pi: fakePi as never,
        topology: {
          self: { pcLabel: "Mac", pcPubkey: selfKey, legacyPcLabel: "Mac" },
          siblings: [{ pcLabel: "RTX4090", pcPubkey: siblingKey, legacyPcLabel: "RTX4090" }],
        },
        reannounceIntervalMs: 0,
        log: () => undefined,
      });
      fakePi.emit(
        "envelope",
        envelope(
          "old-rtx:_broker_remote",
          "old-mac:_broker_remote",
          {
            type: "peers_update",
            peers: ["remote-agent"],
            peers_detailed: [
              { cwd: "", name: "remote-agent", address: "remote-agent" },
            ],
          },
        ),
        siblingKey,
      );
      expect(bridge.getRemotePeers("RTX4090")).toEqual(["remote-agent"]);
      fakePi.clearOutbound();

      vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout"] });

      type Ack = Awaited<ReturnType<SessionPeer["sendWithAck"]>>;
      async function startSend(caseName: string): Promise<{
        outbound: { toPc: string; env: Envelope };
        pending: Promise<Ack>;
        result: () => Ack | undefined;
      }> {
        let result: Ack | undefined;
        const pending = peer.sendWithAck(
          "RTX4090:remote-agent",
          { case: caseName },
          null,
          1_000,
        ).then((value) => {
          result = value;
          return value;
        });
        const outbound = await fakePi.nextOutbound();
        expect(outbound.toPc).toBe(siblingKey);
        expect(outbound.env.to).toBe("RTX4090:remote-agent");
        return { outbound, pending, result: () => result };
      }

      const valid = await startSend("valid offline");
      // Relay-first rollout: the Extension accepts the established Relay UUID
      // form and injects it through the normal strict broker boundary.
      fakePi.emit("envelope", {
        from: "_relay",
        to: `old-mac:${peer.address()}`,
        id: "01976000-0000-7000-8000-000000000201",
        re: valid.outbound.env.id,
        body: { type: "transport_error", reason: "offline" },
      } satisfies Envelope, "_relay");
      await flushUds();
      const expectedOffline = {
        status: "timeout" as const,
        id: valid.outbound.env.id,
        error: "transport_error: offline" as const,
        reason: "offline" as const,
      };
      expect(valid.result()).toEqual(expectedOffline);
      await expect(valid.pending).resolves.toEqual(expectedOffline);

      const malformed = await startSend("old malformed frame");
      fakePi.emit("envelope", {
        from: "_relay",
        to: `Mac:${peer.address()}`,
        id: "01976000000070008000000000000202",
        re: malformed.outbound.env.id,
        body: { type: "transport_error", reason: "offline" },
      } satisfies Envelope, "_relay");
      await flushUds();
      expect(malformed.result()).toEqual({
        status: "timeout",
        id: malformed.outbound.env.id,
        error: "transport_error: offline",
        reason: "offline",
      });
      await expect(malformed.pending).resolves.toEqual({
        status: "timeout",
        id: malformed.outbound.env.id,
        error: "transport_error: offline",
        reason: "offline",
      });

      const silent = await startSend("genuine silence");
      await flushUds();
      expect(silent.result()).toBeUndefined();
      await vi.advanceTimersByTimeAsync(1_000);
      await expect(silent.pending).resolves.toEqual({
        status: "timeout",
        id: silent.outbound.env.id,
      });

      expect(fakePi.sent).toHaveLength(3);
      expect(vi.getTimerCount()).toBe(0);
    } finally {
      bridge?.detach();
      try {
        await peer.leave();
      } finally {
        vi.useRealTimers();
      }
    }
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

  test("injectFromRemote rejects malformed envelopes before claiming received", async () => {
    const sock = tmpSock();
    const peer = await makePeer(sock, "orq");
    const broker = peer.localBroker()!;
    const malformed = {
      from: "casa:sender",
      to: peer.address(),
      id: "not-a-uuid",
      re: null,
      body: { task: "must not arrive" },
    } as unknown as Envelope;
    expect(broker.injectFromRemote(malformed)).toBe("denied");
    await peer.leave();
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
      listRemotePeerInfos: () => [],
    });

    const reply = await orq.request("broker", { type: "list_peers" }, 1000);
    const peers = (reply.body as { peers: string[] }).peers;
    expect(peers).toContain("orq");
    expect(peers).toContain("trab:agent-1");
    expect(peers).toContain("movel:agent-2");

    broker.setRemoteRouter(null);
    await orq.leave();
  });

  test("Broker.list_peers surfaces remote peers_detailed with pc (plan/38 Fase 2)", async () => {
    const sock = tmpSock();
    const orq = new SessionPeer({ sockPath: sock, name: "orq", cwd: "/w/orq", defaultTimeoutMs: 3000 });
    await orq.start();
    const broker = orq.localBroker()!;

    broker.setRemoteRouter({
      tryRouteOutbound: () => false,
      listRemotePeers: () => ["casa:/w/api@api"],
      listRemotePeerInfos: () => [
        { pc: "casa", cwd: "/w/api", name: "api", address: "casa:/w/api@api" },
      ],
    });

    const reply = await orq.request("broker", { type: "list_peers" }, 1000);
    const body = reply.body as { peers: string[]; peers_detailed: Array<{ pc?: string; cwd: string; name: string; address: string }> };

    // Legacy `peers` field still carries the prefixed address.
    expect(body.peers).toContain("casa:/w/api@api");
    // Local self has no pc; the remote entry carries pc="casa", real cwd/name.
    expect(body.peers_detailed).toEqual(expect.arrayContaining([
      expect.objectContaining({ cwd: "/w/orq", name: "orq", address: "/w/orq@orq" }),  // local, no pc
      { pc: "casa", cwd: "/w/api", name: "api", address: "casa:/w/api@api" },           // remote, pc filled
    ]));
    const localEntry = body.peers_detailed.find((p) => p.address === "/w/orq@orq");
    expect(localEntry!.pc).toBeUndefined();

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
      listRemotePeerInfos: () => [],
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

  // ── `remote-pi peers` observer probe (read-only roster) ─────────────────────

  test("unregistered list_peers probe returns the roster without joining", async () => {
    const sock = tmpSock();
    const orq = await makePeer(sock, "orq");
    const backend = await makePeer(sock, "backend");
    const broker = orq.localBroker()!;
    broker.setRemoteRouter({
      tryRouteOutbound: () => false,
      listRemotePeers: () => ["casa:sess-9"],
      listRemotePeerInfos: () => [],
    });

    // Sniff anything the registered peers receive, so we can prove the probe
    // produced no peer_joined / peer_left noise on the mesh. Flush the genuine
    // backend-join broadcast first so only probe-induced traffic remains.
    const orqSystem: Envelope[] = [];
    orq.onMessage((env) => { if (env.from === "broker") orqSystem.push(env); });
    await wait(50);
    orqSystem.length = 0;

    const reply = await new Promise<Envelope>((resolve, reject) => {
      const probe = createConnection({ path: sock });
      let buf = "";
      const timer = setTimeout(() => { probe.destroy(); reject(new Error("probe timeout")); }, 2000);
      probe.setEncoding("utf8");
      probe.on("connect", () => probe.write(JSON.stringify({ type: "list_peers" }) + "\n"));
      probe.on("data", (chunk: string) => {
        buf += chunk;
        const nl = buf.indexOf("\n");
        if (nl < 0) return;
        clearTimeout(timer);
        probe.destroy();
        resolve(JSON.parse(buf.slice(0, nl)) as Envelope);
      });
      probe.on("error", reject);
    });

    const peers = (reply.body as { type: string; peers: string[] });
    expect(peers.type).toBe("list_peers_reply");
    expect(peers.peers).toEqual(expect.arrayContaining(["orq", "backend", "casa:sess-9"]));

    // The probe must NOT have registered: roster unchanged, no observer leaked.
    expect(broker.peerNames().sort()).toEqual(["backend", "orq"]);

    // And no peer_joined/peer_left reached the real peers because of the probe.
    await wait(50);
    const joins = orqSystem.filter((e) => {
      const b = e.body as { type?: string } | null;
      return !!b && (b.type === "peer_joined" || b.type === "peer_left");
    });
    expect(joins.length).toBe(0);

    broker.setRemoteRouter(null);
    await orq.leave(); await backend.leave();
  });

  test("probeListPeers returns the roster against a live broker", async () => {
    const sock = tmpSock();
    const orq = await makePeer(sock, "orq");
    const backend = await makePeer(sock, "backend");

    const peers = await probeListPeers(sock);
    expect(peers).not.toBeNull();
    expect(peers!.sort()).toEqual(["backend", "orq"]);

    await orq.leave(); await backend.leave();
  });

  test("probeListPeers resolves null when no broker is listening", async () => {
    const sock = tmpSock();  // fresh path, nothing bound to it
    const peers = await probeListPeers(sock, 500);
    expect(peers).toBeNull();
  });
});

// ── plan/38: address encoder + name migration (pure) ─────────────────────────

describe("plan/38 — address encoder + name migration (pure)", () => {
  test("composeAddress renders [<pc>:]<cwd>@<nome>; cwd-less → name", () => {
    // The render matrix from the plan.
    expect(composeAddress({ cwd: "/Users/jacob/acme/backend", name: "backend" }))
      .toBe("/Users/jacob/acme/backend@backend");
    expect(composeAddress({ cwd: "/Users/jacob/acme/backend", name: "reviewer" }))
      .toBe("/Users/jacob/acme/backend@reviewer");
    expect(composeAddress({ cwd: "/Users/jacob/.wt/feat-login", name: "backend" }))
      .toBe("/Users/jacob/.wt/feat-login@backend");
    expect(composeAddress({ cwd: "/x/backend", name: "backend#2" }))
      .toBe("/x/backend@backend#2");               // collision suffix is part of the name
    expect(composeAddress({ pc: "MacMini", cwd: "/Users/jose/work/acme", name: "app" }))
      .toBe("MacMini:/Users/jose/work/acme@app");   // cross-PC prefix
    expect(composeAddress({ cwd: "", name: "legacy" })).toBe("legacy");  // no cwd → name only
  });

  test("sanitizeMeshName cleans the name but preserves a trailing #N", () => {
    expect(sanitizeMeshName("a/b")).toBe("a-b");          // `/` sanitized
    expect(sanitizeMeshName("two words")).toBe("two-words");  // space sanitized
    expect(sanitizeMeshName("a@b")).toBe("a-b");          // `@` sanitized → address stays unambiguous
    expect(sanitizeMeshName("name#2")).toBe("name#2");    // collision suffix kept
    expect(sanitizeMeshName("a/b#3")).toBe("a-b#3");      // base cleaned, suffix kept
    expect(sanitizeMeshName("broker")).toBe("agent");     // reserved keyword → fallback
  });

  test("migrateAgentName strips a frozen #N and the legacy parent/folder shape", () => {
    expect(migrateAgentName("backend")).toBe("backend");
    expect(migrateAgentName("backend#2")).toBe("backend");       // frozen runtime suffix
    expect(migrateAgentName("Projects/remote_pi")).toBe("remote_pi");  // legacy parent/folder
    expect(migrateAgentName("myapp/backend#3")).toBe("backend");  // both at once
    expect(migrateAgentName("")).toBeUndefined();
    expect(migrateAgentName("#2")).toBeUndefined();
  });
});

// ── plan/38: (cwd, name) mesh addressing (e2e over real UDS) ──────────────────

describe("plan/38 — (cwd, name) mesh addressing (e2e)", () => {
  async function makePeerCwd(sockPath: string, name: string, cwd: string): Promise<SessionPeer> {
    const peer = new SessionPeer({ sockPath, name, cwd, defaultTimeoutMs: 3000 });
    await peer.start();
    return peer;
  }

  test("register accepts absolute POSIX, Windows drive, and UNC cwd values", async () => {
    const sock = tmpSock();
    const posixPeer = await makePeerCwd(sock, "posix", "/a/backend");
    const windowsPeer = await makePeerCwd(sock, "windows", "C:\\work\\backend");
    const uncPeer = await makePeerCwd(sock, "unc", "\\\\server\\share\\backend");
    expect(posixPeer.address()).toBe("/a/backend@posix");
    expect(windowsPeer.address()).toBe("C:\\work\\backend@windows");
    expect(uncPeer.address()).toBe("\\\\server\\share\\backend@unc");
    await posixPeer.leave();
    await windowsPeer.leave();
    await uncPeer.leave();
  });

  test("registration rejects relative, control-character, and oversized cwd atomically", async () => {
    const sock = tmpSock();
    const leader = await makePeer(sock, "leader");
    const rejected = async (cwd: unknown): Promise<void> => {
      await new Promise<void>((resolve, reject) => {
        const client = createConnection({ path: sock });
        const timer = setTimeout(() => {
          client.destroy();
          reject(new Error("invalid cwd registration was not rejected"));
        }, 1_000);
        client.on("error", () => undefined);
        client.on("connect", () => client.write(JSON.stringify({ type: "register", name: "bad", cwd }) + "\n"));
        client.on("close", () => {
          clearTimeout(timer);
          resolve();
        });
      });
    };
    await rejected("relative/path");
    await rejected("casa:/shadow");
    await rejected("/bad\npath");
    await rejected("/bad\0path");
    await rejected(`/${"x".repeat(4096)}`);
    expect(leader.localBroker()!.peerNames()).toEqual(["leader"]);
    await leader.leave();
  });

  test("registration enforces shared code-unit roster limits before mutating peers", async () => {
    const sock = tmpSock();
    const cwd = `/${"c".repeat(4095)}`;
    const name = "n".repeat(255);
    const exact = await makePeerCwd(sock, name, cwd);
    expect(exact.address()).toHaveLength(4352);
    await exact.leave();

    const leader = await makePeerCwd(sock, "leader", "/workspace");
    const rejected = async (name: string, rejectedCwd: string, takeover = false): Promise<void> => {
      await new Promise<void>((resolve, reject) => {
        const client = createConnection({ path: sock });
        const timer = setTimeout(() => {
          client.destroy();
          reject(new Error("out-of-bounds registration was not rejected"));
        }, 1_000);
        client.on("error", () => undefined);
        client.on("connect", () => client.write(JSON.stringify({
          type: "register", name, cwd: rejectedCwd, takeover,
        }) + "\n"));
        client.on("close", () => { clearTimeout(timer); resolve(); });
      });
    };
    await rejected("x", `/${"c".repeat(4096)}`); // cwd 4097
    await rejected("n".repeat(257), "/workspace"); // name 257
    await rejected("n".repeat(256), cwd); // composed address 4353

    const multibyte = await makePeerCwd(sock, "😀".repeat(128), "/emoji");
    expect(multibyte.name()).toHaveLength(256);
    await multibyte.leave();

    const original = await makePeerCwd(sock, "stable", "/takeover");
    await rejected("x".repeat(257), "/takeover", true);
    const roster = await leader.request("broker", { type: "list_peers" });
    expect((roster.body as { peers?: string[] }).peers).toContain(original.address());
    await original.leave();
    await leader.leave();
  });

  test("legacy peer (no cwd) → address() == name() (mixed-mesh compat)", async () => {
    const sock = tmpSock();
    const p = await makePeer(sock, "backend");  // no cwd in register
    expect(p.name()).toBe("backend");
    expect(p.address()).toBe("backend");
    await p.leave();
  });

  test("same name in DIFFERENT folders coexist — no #N, distinct addresses", async () => {
    const sock = tmpSock();
    const a = await makePeerCwd(sock, "backend", "/a/backend");
    const b = await makePeerCwd(sock, "backend", "/b/backend");
    expect(a.name()).toBe("backend");
    expect(b.name()).toBe("backend");                 // NOT backend#2 — different cwd
    expect(a.address()).toBe("/a/backend@backend");
    expect(b.address()).toBe("/b/backend@backend");

    const reply = await a.request("broker", { type: "list_peers" });
    const peers = (reply.body as { peers?: string[] }).peers ?? [];
    expect(peers).toContain("/a/backend@backend");
    expect(peers).toContain("/b/backend@backend");
    await a.leave(); await b.leave();
  });

  test("same name SAME folder → second gets a runtime #2", async () => {
    const sock = tmpSock();
    const a = await makePeerCwd(sock, "backend", "/a/backend");
    const b = await makePeerCwd(sock, "backend", "/a/backend");
    expect(a.name()).toBe("backend");
    expect(b.name()).toBe("backend#2");
    expect(b.address()).toBe("/a/backend@backend#2");
    await a.leave(); await b.leave();
  });

  test("takeoverExisting replaces the same cwd/name instead of creating #2", async () => {
    const sock = tmpSock();
    const first = await makePeerCwd(sock, "backend", "/a/backend");
    const replacement = new SessionPeer({
      sockPath: sock,
      name: "backend",
      cwd: "/a/backend",
      takeoverExisting: true,
      defaultTimeoutMs: 3000,
    });
    await replacement.start();

    expect(replacement.name()).toBe("backend");
    expect(replacement.address()).toBe("/a/backend@backend");

    const reply = await replacement.request("broker", { type: "list_peers" });
    const peers = (reply.body as { peers?: string[] }).peers ?? [];
    expect(peers.filter((p) => p.startsWith("/a/backend@backend"))).toEqual([
      "/a/backend@backend",
    ]);

    await expect(first.send("broadcast", { stale: true })).rejects.toThrow("session peer not connected");
    await first.leave();
    await replacement.leave();
  });

  test("list_peers_reply carries peers_detailed ({cwd,name,address})", async () => {
    const sock = tmpSock();
    const a = await makePeerCwd(sock, "backend", "/a/backend");
    const b = await makePeerCwd(sock, "web", "/a/web");
    const reply = await a.request("broker", { type: "list_peers" });
    const body = reply.body as { peers?: string[]; peers_detailed?: PeerInfo[] };
    expect(body.peers).toEqual(expect.arrayContaining(["/a/backend@backend", "/a/web@web"]));
    expect(body.peers_detailed).toEqual(expect.arrayContaining([
      expect.objectContaining({ cwd: "/a/backend", name: "backend", address: "/a/backend@backend" }),
      expect.objectContaining({ cwd: "/a/web", name: "web", address: "/a/web@web" }),
    ]));
    await a.leave(); await b.leave();
  });

  test("Windows-style local cwd (drive-letter ':') is classified LOCAL, not remote", async () => {
    // plan/38 Fase 2 gap 3: a local address like `C:\proj\app@app` contains a
    // ':' but is NOT cross-PC. The broker tags it with no `pc` in
    // peers_detailed, so the consumer (index.ts) keys on `!pc` instead of a
    // naive `:`-split and counts/pushes it as local.
    const sock = tmpSock();
    const p = await makePeerCwd(sock, "app", "C:\\proj\\app");
    expect(p.address()).toBe("C:\\proj\\app@app");  // contains ':' yet local

    const reply = await p.request("broker", { type: "list_peers" });
    const detailed = (reply.body as { peers_detailed?: Array<{ pc?: string; address: string }> })
      .peers_detailed ?? [];
    const self = detailed.find((e) => e.address === "C:\\proj\\app@app");
    expect(self).toBeDefined();
    expect(self!.pc).toBeUndefined();  // no pc → LOCAL despite the ':'
    await p.leave();
  });

  test("Windows drive local address beats RemoteRouter alias handling", async () => {
    const sock = tmpSock();
    const sender = await makePeerCwd(sock, "sender", "/proj/sender");
    const localTarget = await makePeerCwd(sock, "agent", "C:\\proj\\app");
    const broker = sender.localBroker()!;
    const tryRouteOutbound = vi.fn((env: Envelope) =>
      typeof env.to === "string" && env.to.startsWith("C:"),
    );
    broker.setRemoteRouter({
      tryRouteOutbound,
      listRemotePeers: () => [],
      listRemotePeerInfos: () => [],
    });
    const inbox: Envelope[] = [];
    localTarget.onMessage((env) => {
      if (env.from !== "broker") inbox.push(env);
    });

    const ack = await sender.sendWithAck(localTarget.address(), { local: true });
    await wait(50);

    expect(localTarget.address()).toBe("C:\\proj\\app@agent");
    expect(tryRouteOutbound).not.toHaveBeenCalled();
    expect(ack.status).toBe("received");
    expect(inbox).toHaveLength(1);
    expect(inbox[0]?.to).toBe(localTarget.address());

    broker.setRemoteRouter(null);
    await sender.leave();
    await localTarget.leave();
  });

  test("broadcast is scoped to the sender's cwd (folder colleagues only)", async () => {
    const sock = tmpSock();
    const a = await makePeerCwd(sock, "a", "/proj/x");          // sender
    const sameFolder = await makePeerCwd(sock, "b", "/proj/x");
    const otherFolder = await makePeerCwd(sock, "c", "/proj/y");
    const gotSame: Envelope[] = [];
    const gotOther: Envelope[] = [];
    sameFolder.onMessage((e) => { if (e.from !== "broker") gotSame.push(e); });
    otherFolder.onMessage((e) => { if (e.from !== "broker") gotOther.push(e); });

    await a.send("broadcast", { hello: 1 });
    await wait(150);

    expect(gotSame.length).toBe(1);     // same folder hears it
    expect(gotOther.length).toBe(0);    // different folder does NOT
    expect(gotSame[0]!.from).toBe("/proj/x@a");  // from is the sender's address
    await a.leave(); await sameFolder.leave(); await otherFolder.leave();
  });
});

// ── SessionPeer.rename: no duplicate / no ghost ───────────────────────────────

describe("SessionPeer.rename (live rename)", () => {
  test("renames in place — no `#N` duplicate, no stale old name (single rejoin)", async () => {
    const sock = tmpSock();
    const observer = await makePeer(sock, "observer");  // leader; used to query the roster
    const p = await makePeer(sock, "alice");            // follower we rename
    expect(p.name()).toBe("alice");

    const assigned = await p.rename("bob");
    expect(assigned).toBe("bob");
    // Wait past FAILOVER_RETRY_MS (100ms): the old bug fired a spurious
    // `_onSocketClose` → second `_joinOrLead` → "bob#2" + an orphaned "alice".
    await wait(300);

    const reply = await observer.request("broker", { type: "list_peers" });
    const names = ((reply.body as { peers?: string[] }).peers ?? [])
      .filter((x) => x === "alice" || x.startsWith("bob"));
    expect(names).toEqual(["bob"]);  // exactly one, no ghost "alice", no "bob#2"

    expect(p.name()).toBe("bob");
    await p.leave();
    await observer.leave();
  });
});
