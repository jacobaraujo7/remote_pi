import { describe, expect, test, vi } from "vitest";
import { EventEmitter } from "node:events";
import { BrokerRemote, parseAddress } from "./broker_remote.js";
import type { Broker, RemoteInjectStatus } from "./broker.js";
import { envelope, type Envelope } from "./envelope.js";

// ── Test doubles ─────────────────────────────────────────────────────────────

/**
 * Minimal `PiForwardClient` stand-in. Records every outbound `sendEnvelopeToPi`
 * call so tests can assert on what was packed onto the relay, and exposes
 * `emit("envelope", env, fromPc)` so tests can simulate inbound delivery.
 */
class FakePi extends EventEmitter {
  readonly sent: { toPc: string; env: Envelope }[] = [];
  sendEnvelopeToPi(toPc: string, env: Envelope): void {
    this.sent.push({ toPc, env });
  }
  detach(): void { /* no-op */ }
}

interface FakeBrokerOptions {
  injectStatus?: RemoteInjectStatus;
  /** Local peer names the fake broker reports via `peerNames()`. Used by
   *  `BrokerRemote` to seed `lastLocalPeers` and to answer
   *  `peers_request` envelopes. Defaults to a single self peer. */
  localPeers?: string[];
}

function makeFakeBroker(opts: FakeBrokerOptions = {}): {
  broker: Broker;
  injectFromRemote: ReturnType<typeof vi.fn>;
  setRemoteRouter: ReturnType<typeof vi.fn>;
  peerNames: ReturnType<typeof vi.fn>;
  localPeerInfos: ReturnType<typeof vi.fn>;
  injected: Envelope[];
} {
  const injected: Envelope[] = [];
  const status = opts.injectStatus ?? "received";
  const injectFromRemote = vi.fn((env: Envelope) => {
    injected.push(env);
    return status;
  });
  const setRemoteRouter = vi.fn();
  let _localPeers = opts.localPeers ?? ["self"];
  const peerNames = vi.fn(() => [..._localPeers]);
  // plan/38 Fase 2: the cross-PC push reads the structured local inventory.
  // Synthesize `{cwd:"", name:addr, address:addr}` from the same address list.
  const localPeerInfos = vi.fn(() => _localPeers.map((address) => ({ cwd: "", name: address, address })));
  // Expose a setter for tests that mutate the local set mid-test.
  (peerNames as unknown as { set: (p: string[]) => void }).set = (p: string[]) => {
    _localPeers = p;
  };
  const broker = {
    injectFromRemote,
    setRemoteRouter,
    peerNames,
    localPeerInfos,
  } as unknown as Broker;
  return { broker, injectFromRemote, setRemoteRouter, peerNames, localPeerInfos, injected };
}

// ── parseAddress ─────────────────────────────────────────────────────────────

describe("parseAddress", () => {
  test("no prefix → null", () => {
    expect(parseAddress("backend")).toBeNull();
  });
  test("colon at end → null (empty peer name)", () => {
    expect(parseAddress("trab:")).toBeNull();
  });
  test("colon at start → null (empty pc label)", () => {
    expect(parseAddress(":agent")).toBeNull();
  });
  test("simple pc:peer → both parts", () => {
    expect(parseAddress("trab:agent-1")).toEqual({ pcLabel: "trab", peerName: "agent-1" });
  });
  test("multiple colons → split on first", () => {
    expect(parseAddress("trab:sub:agent")).toEqual({ pcLabel: "trab", peerName: "sub:agent" });
  });
});

// ── tryRouteOutbound ────────────────────────────────────────────────────────

describe("BrokerRemote.tryRouteOutbound", () => {
  test("no prefix → false (broker delivers locally)", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    const br = new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "self", selfPcPubkey: "K_SELF",
      siblings: [{ pcLabel: "trab", pcPubkey: "K_B" }],
    });
    fakePi.sent.length = 0;  // drop bootstrap peers_request

    const env = envelope("sess-3", "agent-1", { x: 1 });
    expect(br.tryRouteOutbound(env)).toBe(false);
    expect(fakePi.sent.length).toBe(0);
  });

  test("self prefix → false (local handles)", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    const br = new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "self", selfPcPubkey: "K_SELF",
    });

    const env = envelope("sess-3", "self:agent-1", { x: 1 });
    expect(br.tryRouteOutbound(env)).toBe(false);
    expect(fakePi.sent.length).toBe(0);
  });

  test("unknown prefix → false (backward-compat for local names with ':')", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    const br = new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "self", selfPcPubkey: "K_SELF",
      siblings: [{ pcLabel: "trab", pcPubkey: "K_B" }],
    });
    fakePi.sent.length = 0;  // drop bootstrap peers_request

    const env = envelope("sess-3", "weird:peer", { x: 1 });
    expect(br.tryRouteOutbound(env)).toBe(false);
    expect(fakePi.sent.length).toBe(0);
  });

  test("known sibling prefix → packs frame to relay, rewrites from", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    const br = new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "casa", selfPcPubkey: "K_A",
      siblings: [{ pcLabel: "trab", pcPubkey: "K_B" }],
    });

    const env = envelope("sess-3", "trab:agent-1", { x: 1 });
    expect(br.tryRouteOutbound(env)).toBe(true);
    expect(fakePi.sent.length).toBeGreaterThanOrEqual(1);
    const main = fakePi.sent.find((s) => s.env.id === env.id);
    expect(main).toBeDefined();
    expect(main!.toPc).toBe("K_B");
    expect(main!.env.from).toBe("casa:sess-3");
    expect(main!.env.to).toBe("trab:agent-1");
  });

  test("cache miss triggers a peers_request alongside the main send", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    const br = new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "casa", selfPcPubkey: "K_A",
      siblings: [{ pcLabel: "trab", pcPubkey: "K_B" }],
    });
    // Bootstrap fires peers_request to every sibling on construction.
    // Clear that out so we can verify the cache-miss path also fires one.
    fakePi.sent.length = 0;

    const env = envelope("sess-3", "trab:agent-1", { x: 1 });
    br.tryRouteOutbound(env);

    const peersReq = fakePi.sent.find((s) =>
      (s.env.body as { type?: string } | null)?.type === "peers_request",
    );
    expect(peersReq).toBeDefined();
    expect(peersReq!.toPc).toBe("K_B");
  });

  test("does not trigger peers_request when cache is already populated", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    const br = new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "casa", selfPcPubkey: "K_A",
      siblings: [{ pcLabel: "trab", pcPubkey: "K_B" }],
    });

    // Prime the cache via peers_update
    fakePi.emit("envelope", envelope(
      "trab:_broker_remote", "casa:_broker_remote",
      { type: "peers_update", peers: ["agent-1"] },
    ), "K_B");

    fakePi.sent.length = 0;
    const env = envelope("sess-3", "trab:agent-1", { x: 1 });
    br.tryRouteOutbound(env);

    const peersReq = fakePi.sent.find((s) =>
      (s.env.body as { type?: string } | null)?.type === "peers_request",
    );
    expect(peersReq).toBeUndefined();
  });
});

// ── handleIncoming ──────────────────────────────────────────────────────────

describe("BrokerRemote.handleIncoming (anti-spoof + injection)", () => {
  test("from_pc not in sibling cache → drop + log", () => {
    const fakePi = new FakePi();
    const { broker, injectFromRemote } = makeFakeBroker();
    const logs: string[] = [];
    new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "casa", selfPcPubkey: "K_A",
      siblings: [{ pcLabel: "trab", pcPubkey: "K_B" }],
      log: (m) => logs.push(m),
    });

    fakePi.emit("envelope", envelope("evil:sess", "casa:agent-1", { x: 1 }), "K_UNKNOWN");

    expect(injectFromRemote).not.toHaveBeenCalled();
    expect(logs.some((l) => /not in sibling cache/.test(l))).toBe(true);
  });

  test("envelope.from prefix mismatches sibling label → drop", () => {
    const fakePi = new FakePi();
    const { broker, injectFromRemote } = makeFakeBroker();
    const logs: string[] = [];
    new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "casa", selfPcPubkey: "K_A",
      siblings: [{ pcLabel: "trab", pcPubkey: "K_B" }],
      log: (m) => logs.push(m),
    });

    // K_B claims to be "evil" — spoof attempt
    fakePi.emit("envelope", envelope("evil:sess", "casa:agent-1", { x: 1 }), "K_B");

    expect(injectFromRemote).not.toHaveBeenCalled();
    expect(logs.some((l) => /prefix\s+mismatches/.test(l))).toBe(true);
  });

  test("valid envelope → strip to-prefix, injectFromRemote, ACK back", () => {
    const fakePi = new FakePi();
    const { broker, injectFromRemote } = makeFakeBroker({ injectStatus: "received" });
    new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "casa", selfPcPubkey: "K_A",
      siblings: [{ pcLabel: "trab", pcPubkey: "K_B" }],
    });

    const inbound = envelope("trab:agent-1", "casa:sess-3", { hello: "world" });
    fakePi.emit("envelope", inbound, "K_B");

    expect(injectFromRemote).toHaveBeenCalledTimes(1);
    const injected = injectFromRemote.mock.calls[0]![0] as Envelope;
    expect(injected.from).toBe("trab:agent-1");
    expect(injected.to).toBe("sess-3");  // prefix stripped

    // ACK packed back to K_B
    const ack = fakePi.sent.find((s) =>
      (s.env.body as { type?: string } | null)?.type === "ack",
    );
    expect(ack).toBeDefined();
    expect(ack!.toPc).toBe("K_B");
    expect(ack!.env.re).toBe(inbound.id);
    expect((ack!.env.body as { status: string }).status).toBe("received");
  });

  test("envelope addressed to third-party PC → drop", () => {
    const fakePi = new FakePi();
    const { broker, injectFromRemote } = makeFakeBroker();
    const logs: string[] = [];
    new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "casa", selfPcPubkey: "K_A",
      siblings: [{ pcLabel: "trab", pcPubkey: "K_B" }],
      log: (m) => logs.push(m),
    });

    const inbound = envelope("trab:agent-1", "other:peer", { x: 1 });
    fakePi.emit("envelope", inbound, "K_B");

    expect(injectFromRemote).not.toHaveBeenCalled();
    expect(logs.some((l) => /not addressed/.test(l))).toBe(true);
  });

  test("incoming ACK does not generate a recursive ACK", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "casa", selfPcPubkey: "K_A",
      siblings: [{ pcLabel: "trab", pcPubkey: "K_B" }],
    });

    const ackEnv: Envelope = envelope(
      "trab:broker", "casa:sess-3",
      { type: "ack", status: "received", target: "agent-1" },
      "01976000-0000-7000-8000-000000000000",
    );
    fakePi.emit("envelope", ackEnv, "K_B");

    const generatedAck = fakePi.sent.find((s) =>
      (s.env.body as { type?: string } | null)?.type === "ack",
    );
    expect(generatedAck).toBeUndefined();
  });
});

// ── peers_update / peers_request control ────────────────────────────────────

describe("BrokerRemote: control envelopes (peers_update / peers_request)", () => {
  test("peers_update populates cache (getRemotePeers returns)", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    const br = new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "casa", selfPcPubkey: "K_A",
      siblings: [{ pcLabel: "trab", pcPubkey: "K_B" }],
    });

    fakePi.emit("envelope", envelope(
      "trab:_broker_remote", "casa:_broker_remote",
      { type: "peers_update", peers: ["agent-1", "agent-2"] },
    ), "K_B");

    expect(br.getRemotePeers("trab")).toEqual(["agent-1", "agent-2"]);
    expect(br.listRemotePeers()).toEqual(["trab:agent-1", "trab:agent-2"]);
  });

  test("peers_update with peers_detailed → listRemotePeerInfos fills pc + prefixes address (plan/38 Fase 2)", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    const br = new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "casa", selfPcPubkey: "K_A",
      siblings: [{ pcLabel: "trab", pcPubkey: "K_B" }],
    });

    fakePi.emit("envelope", envelope(
      "trab:_broker_remote", "casa:_broker_remote",
      {
        type: "peers_update",
        peers: ["/w/app@App", "/w/api@Api"],
        peers_detailed: [
          { cwd: "/w/app", name: "App", address: "/w/app@App" },
          { cwd: "/w/api", name: "Api", address: "/w/api@Api" },
        ],
      },
    ), "K_B");

    // Addresses (the `peers` half) get the sibling-label prefix.
    expect(br.listRemotePeers()).toEqual(["trab:/w/app@App", "trab:/w/api@Api"]);
    // Structured: `pc` filled from the verified sibling label, cwd/name preserved,
    // address prefixed `<pc>:<cwd>@<nome>` — this is what powers `peers_detailed`.
    expect(br.listRemotePeerInfos()).toEqual([
      { pc: "trab", cwd: "/w/app", name: "App", address: "trab:/w/app@App" },
      { pc: "trab", cwd: "/w/api", name: "Api", address: "trab:/w/api@Api" },
    ]);
  });

  test("back-compat: peers_update with ONLY peers[] (Fase-1 sibling) → synthesized infos, mesh not broken", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    const br = new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "casa", selfPcPubkey: "K_A",
      siblings: [{ pcLabel: "trab", pcPubkey: "K_B" }],
    });

    // An older sibling sends addresses only — no peers_detailed.
    fakePi.emit("envelope", envelope(
      "trab:_broker_remote", "casa:_broker_remote",
      { type: "peers_update", peers: ["/w/app@App"] },
    ), "K_B");

    expect(br.listRemotePeers()).toEqual(["trab:/w/app@App"]);
    // Synthesized: cwd "", name == address, pc filled, address prefixed. Routing
    // still works (address is intact); only cwd/name grouping is degraded.
    expect(br.listRemotePeerInfos()).toEqual([
      { pc: "trab", cwd: "", name: "/w/app@App", address: "trab:/w/app@App" },
    ]);
  });

  test("cache TTL expires entries", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    const br = new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "casa", selfPcPubkey: "K_A",
      siblings: [{ pcLabel: "trab", pcPubkey: "K_B" }],
      cacheTtlMs: 10,  // tight TTL for tests
    });

    fakePi.emit("envelope", envelope(
      "trab:_broker_remote", "casa:_broker_remote",
      { type: "peers_update", peers: ["agent-1"] },
    ), "K_B");
    expect(br.getRemotePeers("trab")).toEqual(["agent-1"]);

    return new Promise<void>((resolve) => {
      setTimeout(() => {
        expect(br.getRemotePeers("trab")).toEqual([]);
        resolve();
      }, 30);
    });
  });

  test("peers_request triggers peers_update reply with current local peers", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker({ localPeers: ["sess-3", "agent-1"] });
    new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "casa", selfPcPubkey: "K_A",
      siblings: [{ pcLabel: "trab", pcPubkey: "K_B" }],
    });
    fakePi.sent.length = 0;

    fakePi.emit("envelope", envelope(
      "trab:_broker_remote", "casa:_broker_remote",
      { type: "peers_request" },
    ), "K_B");

    const reply = fakePi.sent.find((s) =>
      (s.env.body as { type?: string } | null)?.type === "peers_update",
    );
    expect(reply).toBeDefined();
    expect(reply!.toPc).toBe("K_B");
    expect((reply!.env.body as { peers: string[] }).peers).toEqual(["sess-3", "agent-1"]);
  });

  test("peers_request reply pulls the LIVE local inventory (broker.localPeerInfos), not a stale cache", () => {
    // Regression: in a single-peer mesh (only the wrapper itself), no
    // peer_joined event ever fires for the joiner, so a cached local list
    // would stay []. Reading the broker's live inventory bypasses that.
    const fakePi = new FakePi();
    const { broker, localPeerInfos } = makeFakeBroker({ localPeers: ["MacMini"] });
    new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "MacMini", selfPcPubkey: "K_B",
      siblings: [{ pcLabel: "MacBook", pcPubkey: "K_A" }],
    });
    // Note: no `onLocalPeersChanged` was ever called. Bootstrap traffic
    // was sent; clear it so we observe the reply path cleanly.
    fakePi.sent.length = 0;

    fakePi.emit("envelope", envelope(
      "MacBook:_broker_remote", "MacMini:_broker_remote",
      { type: "peers_request" },
    ), "K_A");

    const reply = fakePi.sent.find((s) =>
      (s.env.body as { type?: string } | null)?.type === "peers_update",
    );
    expect(reply).toBeDefined();
    const body = reply!.env.body as { peers: string[]; peers_detailed: Array<{ cwd: string; name: string; address: string }> };
    expect(body.peers).toEqual(["MacMini"]);
    // plan/38 Fase 2: the reply also carries the structured roster.
    expect(body.peers_detailed).toEqual([{ cwd: "", name: "MacMini", address: "MacMini" }]);
    expect(localPeerInfos).toHaveBeenCalled();
  });

  test("onLocalPeersChanged pushes peers_update to every sibling", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    const br = new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "casa", selfPcPubkey: "K_A",
      siblings: [
        { pcLabel: "trab", pcPubkey: "K_B" },
        { pcLabel: "movel", pcPubkey: "K_C" },
      ],
    });
    // Discard bootstrap announce/request traffic; we only care about the
    // peers_update emitted by `onLocalPeersChanged` below.
    fakePi.sent.length = 0;
    br.onLocalPeersChanged(["sess-3"]);

    const updates = fakePi.sent.filter((s) =>
      (s.env.body as { type?: string } | null)?.type === "peers_update",
    );
    expect(updates.map((u) => u.toPc).sort()).toEqual(["K_B", "K_C"]);
  });

  test("periodic re-announce re-pushes to a STABLE sibling set (keeps roster warm vs TTL)", () => {
    // Regression: without a timer, a stable mesh never re-announces (only NEW
    // siblings get the bootstrap pair), so a single dropped push lets both
    // caches expire and the peer silently drops from list_peers overnight.
    vi.useFakeTimers();
    try {
      const fakePi = new FakePi();
      const { broker } = makeFakeBroker({ localPeers: ["sess-3"] });
      const br = new BrokerRemote({
        broker, pi: fakePi as never,
        selfPcLabel: "casa", selfPcPubkey: "K_A",
        siblings: [{ pcLabel: "trab", pcPubkey: "K_B" }],
        reannounceIntervalMs: 1_000,
      });
      fakePi.sent.length = 0;  // drop bootstrap request+push

      vi.advanceTimersByTime(1_000);
      // One full re-announce cycle = the bootstrap pair (request + push).
      const byType = (t: string) => fakePi.sent.filter(
        (s) => (s.env.body as { type?: string } | null)?.type === t,
      );
      expect(byType("peers_request").map((s) => s.toPc)).toEqual(["K_B"]);
      expect(byType("peers_update").map((s) => s.toPc)).toEqual(["K_B"]);

      // detach() stops the timer — no further traffic.
      br.detach();
      fakePi.sent.length = 0;
      vi.advanceTimersByTime(5_000);
      expect(fakePi.sent.length).toBe(0);
    } finally {
      vi.useRealTimers();
    }
  });
});

// ── transport_error propagation ──────────────────────────────────────────────

describe("BrokerRemote: transport_error from relay", () => {
  test("from_pc='_relay' → inject locally (no anti-spoof, no ACK back)", () => {
    const fakePi = new FakePi();
    const { broker, injectFromRemote } = makeFakeBroker();
    new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "casa", selfPcPubkey: "K_A",
      siblings: [{ pcLabel: "trab", pcPubkey: "K_B" }],
    });

    const err: Envelope = envelope(
      "_relay", "casa:sess-3",
      { type: "transport_error", reason: "offline" },
      "01976000-0000-7000-8000-000000000000",
    );
    fakePi.emit("envelope", err, "_relay");

    expect(injectFromRemote).toHaveBeenCalledTimes(1);
    const injected = injectFromRemote.mock.calls[0]![0] as Envelope;
    expect(injected.to).toBe("sess-3");  // prefix stripped
    expect((injected.body as { type: string }).type).toBe("transport_error");

    const ackBack = fakePi.sent.find((s) =>
      (s.env.body as { type?: string } | null)?.type === "ack",
    );
    expect(ackBack).toBeUndefined();
  });
});

// ── setSiblings ──────────────────────────────────────────────────────────────

describe("BrokerRemote.setSiblings", () => {
  test("dropping a sibling clears its cache entry", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    const br = new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "casa", selfPcPubkey: "K_A",
      siblings: [
        { pcLabel: "trab", pcPubkey: "K_B" },
        { pcLabel: "movel", pcPubkey: "K_C" },
      ],
    });
    fakePi.emit("envelope", envelope(
      "trab:_broker_remote", "casa:_broker_remote",
      { type: "peers_update", peers: ["agent-1"] },
    ), "K_B");
    expect(br.getRemotePeers("trab")).toEqual(["agent-1"]);

    br.setSiblings([{ pcLabel: "movel", pcPubkey: "K_C" }]);
    expect(br.getRemotePeers("trab")).toEqual([]);
  });

  test("self never appears in sibling set", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    const br = new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "casa", selfPcPubkey: "K_A",
      siblings: [
        { pcLabel: "casa", pcPubkey: "K_A" },     // self by both
        { pcLabel: "trab", pcPubkey: "K_B" },
      ],
    });

    const env = envelope("sess-3", "casa:agent-1", { x: 1 });
    expect(br.tryRouteOutbound(env)).toBe(false);  // self → local
  });
});

// ── Bootstrap: warm cache via peers_request ──────────────────────────────────

describe("BrokerRemote: bootstrap peers_request (plan/25 Wave B)", () => {
  test("constructor pings every initial sibling with peers_request", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "casa", selfPcPubkey: "K_A",
      siblings: [
        { pcLabel: "trab", pcPubkey: "K_B" },
        { pcLabel: "movel", pcPubkey: "K_C" },
      ],
    });

    const requests = fakePi.sent.filter((s) =>
      (s.env.body as { type?: string } | null)?.type === "peers_request",
    );
    expect(requests.map((r) => r.toPc).sort()).toEqual(["K_B", "K_C"]);
  });

  test("constructor also announces our own peers (peers_update) to every sibling", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker({ localPeers: ["MacMini"] });
    new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "MacMini", selfPcPubkey: "K_B",
      siblings: [{ pcLabel: "MacBook", pcPubkey: "K_A" }],
    });

    const announces = fakePi.sent.filter((s) =>
      (s.env.body as { type?: string } | null)?.type === "peers_update",
    );
    expect(announces.length).toBe(1);
    expect(announces[0]!.toPc).toBe("K_A");
    expect((announces[0]!.env.body as { peers: string[] }).peers).toEqual(["MacMini"]);
  });

  test("no peers_request emitted when there are zero siblings", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "casa", selfPcPubkey: "K_A",
    });

    expect(fakePi.sent.length).toBe(0);
  });

  test("setSiblings sends peers_request only to newly-added siblings", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    const br = new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "casa", selfPcPubkey: "K_A",
      siblings: [{ pcLabel: "trab", pcPubkey: "K_B" }],
    });
    // Drop initial bootstrap traffic so the assertion is isolated.
    fakePi.sent.length = 0;

    // Replace with set that keeps K_B and adds K_C. We expect a single
    // peers_request to K_C; K_B should NOT be re-pinged.
    br.setSiblings([
      { pcLabel: "trab", pcPubkey: "K_B" },
      { pcLabel: "movel", pcPubkey: "K_C" },
    ]);

    const requests = fakePi.sent.filter((s) =>
      (s.env.body as { type?: string } | null)?.type === "peers_request",
    );
    expect(requests.map((r) => r.toPc)).toEqual(["K_C"]);
  });

  test("setSiblings removes a sibling without firing peers_request for the survivors", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    const br = new BrokerRemote({
      broker, pi: fakePi as never,
      selfPcLabel: "casa", selfPcPubkey: "K_A",
      siblings: [
        { pcLabel: "trab", pcPubkey: "K_B" },
        { pcLabel: "movel", pcPubkey: "K_C" },
      ],
    });
    fakePi.sent.length = 0;

    br.setSiblings([{ pcLabel: "movel", pcPubkey: "K_C" }]);

    const requests = fakePi.sent.filter((s) =>
      (s.env.body as { type?: string } | null)?.type === "peers_request",
    );
    expect(requests).toEqual([]);
  });
});
