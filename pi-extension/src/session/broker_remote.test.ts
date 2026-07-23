import { describe, expect, test, vi } from "vitest";
import { EventEmitter } from "node:events";
import { BrokerRemote, parseAddress } from "./broker_remote.js";
import type { Broker, RemoteInjectStatus } from "./broker.js";
import { envelope, type Envelope } from "./envelope.js";
import type { MeshTopologySnapshot, PiRoutingIdentity } from "../mesh/siblings.js";

function keyBytes(seed: number): Uint8Array {
  return Uint8Array.from(
    { length: 32 },
    (_, index) => (seed + index * 29) & 0xff,
  );
}

const KEY_A_BYTES = keyBytes(3);
const KEY_B_BYTES = keyBytes(71);
const KEY_C_BYTES = keyBytes(139);
const KEY_D_BYTES = keyBytes(207);
const KEY_A = Buffer.from(KEY_A_BYTES).toString("base64");
const KEY_B = Buffer.from(KEY_B_BYTES).toString("base64");
const KEY_C = Buffer.from(KEY_C_BYTES).toString("base64");
const KEY_D = Buffer.from(KEY_D_BYTES).toString("base64");
const KEY_A_URL = Buffer.from(KEY_A_BYTES).toString("base64url");
const KEY_B_URL = Buffer.from(KEY_B_BYTES).toString("base64url");
// Pinned 32-byte values whose legacy standard-Base64 prefixes differ from
// Base64url (`+///AAAA` / `////AAAA`).
const FALLBACK_KEY_A_BYTES = Uint8Array.from([
  0xfb, 0xff, 0xff, ...Array.from({ length: 29 }, (_, index) => index),
]);
const FALLBACK_KEY_B_BYTES = Uint8Array.from([
  0xff, 0xff, 0xff, ...Array.from({ length: 29 }, (_, index) => 255 - index),
]);
const FALLBACK_KEY_A = Buffer.from(FALLBACK_KEY_A_BYTES).toString("base64");
const FALLBACK_KEY_B = Buffer.from(FALLBACK_KEY_B_BYTES).toString("base64");
const FALLBACK_KEY_A_URL = Buffer.from(FALLBACK_KEY_A_BYTES).toString("base64url");
const FALLBACK_KEY_B_URL = Buffer.from(FALLBACK_KEY_B_BYTES).toString("base64url");

type TestRoutingIdentity = Omit<PiRoutingIdentity, "legacyPcLabel"> & {
  readonly legacyPcLabel?: string;
};

function topology(
  self: TestRoutingIdentity,
  siblings: readonly TestRoutingIdentity[] = [],
): MeshTopologySnapshot {
  const withLegacyLabel = (identity: TestRoutingIdentity): PiRoutingIdentity => ({
    ...identity,
    legacyPcLabel: identity.legacyPcLabel ?? identity.pcLabel,
  });
  return {
    self: withLegacyLabel(self),
    siblings: siblings.map(withLegacyLabel),
  };
}

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

interface LinkedDelivery {
  direction: "A→B" | "B→A";
  authenticatedFromPc: string;
  env: Envelope;
}

class BoundedInMemoryPiLink {
  constructor(
    private readonly piA: FakePi,
    private readonly piB: FakePi,
  ) {}

  pumpUntilQuiescent(): LinkedDelivery[] {
    const deliveries: LinkedDelivery[] = [];
    const maxRounds = 16;
    const maxFrames = 128;

    for (let round = 0; round < maxRounds; round += 1) {
      const fromA = this.piA.sent.splice(0);
      const fromB = this.piB.sent.splice(0);
      if (fromA.length === 0 && fromB.length === 0) return deliveries;
      if (deliveries.length + fromA.length + fromB.length > maxFrames) {
        throw new Error(`in-memory Pi link exceeded ${maxFrames} frames`);
      }

      for (const sent of fromA) {
        if (sent.toPc !== KEY_B) {
          throw new Error("in-memory Pi link received an unexpected A destination");
        }
        deliveries.push({
          direction: "A→B",
          authenticatedFromPc: KEY_A_URL,
          env: sent.env,
        });
        this.piB.emit("envelope", sent.env, KEY_A_URL);
      }
      for (const sent of fromB) {
        if (sent.toPc !== KEY_A) {
          throw new Error("in-memory Pi link received an unexpected B destination");
        }
        deliveries.push({
          direction: "B→A",
          authenticatedFromPc: KEY_B_URL,
          env: sent.env,
        });
        this.piA.emit("envelope", sent.env, KEY_B_URL);
      }
    }

    throw new Error(`in-memory Pi link did not quiesce after ${maxRounds} rounds`);
  }
}

/**
 * Frozen old-Extension oracle, derived directly from
 * `19c2997^:pi-extension/src/session/broker_remote.ts` and
 * `19c2997^:pi-extension/src/mesh/siblings.ts`.
 *
 * The old source selected `nickname ?? pcPubkey.slice(0, 8)`, required the
 * first `from` segment to equal the sibling label, handled controls before
 * target stripping, only stripped a matching first `to` segment, and echoed
 * the exact inbound `from` in ACK destinations. This deliberately small
 * harness preserves only those observable wire behaviors; it does not import
 * historical source or use a network.
 */
function frozenOldLegacyPcLabel(
  nickname: string | undefined,
  canonicalPcPubkey: string,
): string {
  return nickname || canonicalPcPubkey.slice(0, 8);
}

/** Pinned copy of `19c2997^`'s first-colon `<pc>:<peer>` parser. */
function frozenOldParseAddress(
  address: string,
): { pcLabel: string; peerName: string } | null {
  const index = address.indexOf(":");
  if (index <= 0 || index === address.length - 1) return null;
  return { pcLabel: address.slice(0, index), peerName: address.slice(index + 1) };
}

interface FrozenOldWirePeerInfo {
  cwd: string;
  name: string;
  address: string;
}

type FrozenOldControl =
  | { type: "peers_request" }
  | {
    type: "peers_update";
    peers: string[];
    peers_detailed: FrozenOldWirePeerInfo[];
  };

interface FrozenPendingAckSlot {
  expectedFrom: string;
  timer: ReturnType<typeof setTimeout>;
  resolve: (ack: Envelope) => void;
}

/** Test-local model of SessionPeer's ACK pending map and timer lifecycle. */
class FrozenPendingAckRegistry {
  private readonly pending = new Map<string, FrozenPendingAckSlot>();
  private readonly activeTimerIds = new Set<string>();
  private readonly resolutions = new Map<string, Envelope[]>();

  track(outbound: Envelope, expectedFrom: string): void {
    const resolved: Envelope[] = [];
    const timer = setTimeout(() => {
      this.pending.delete(outbound.id);
      this.activeTimerIds.delete(outbound.id);
    }, 60_000);
    timer.unref?.();
    this.resolutions.set(outbound.id, resolved);
    this.activeTimerIds.add(outbound.id);
    this.pending.set(outbound.id, {
      expectedFrom,
      timer,
      resolve: (ack) => resolved.push(ack),
    });
  }

  consume(ack: Envelope): boolean {
    const body = ack.body as { type?: unknown } | null;
    if (ack.re === null || body?.type !== "ack") return false;
    const slot = this.pending.get(ack.re);
    if (!slot || slot.expectedFrom !== ack.from) return false;
    clearTimeout(slot.timer);
    this.activeTimerIds.delete(ack.re);
    this.pending.delete(ack.re);
    slot.resolve(ack);
    return true;
  }

  hasPending(id: string): boolean {
    return this.pending.has(id);
  }

  hasActiveTimer(id: string): boolean {
    return this.activeTimerIds.has(id);
  }

  resolutionCount(id: string): number {
    return this.resolutions.get(id)?.length ?? 0;
  }
}

function expectExactlyOnceSettlement(
  pending: FrozenPendingAckRegistry,
  requestId: string,
  deliveredAck: Envelope,
): void {
  expect(pending.resolutionCount(requestId)).toBe(1);
  expect(pending.hasPending(requestId)).toBe(false);
  expect(pending.hasActiveTimer(requestId)).toBe(false);
  expect(pending.consume(deliveredAck)).toBe(false);
  expect(pending.resolutionCount(requestId)).toBe(1);
}

class FrozenOldBrokerRemoteOracle {
  readonly sent: { toPc: string; env: Envelope }[] = [];
  readonly injected: Envelope[] = [];
  private readonly remotePeers: FrozenOldWirePeerInfo[] = [];

  constructor(
    private readonly selfPcLabel: string,
    private readonly siblingPcLabel: string,
    private readonly siblingPcPubkey: string,
    private readonly localPeers: readonly string[],
    private readonly onInjected?: (env: Envelope) => void,
  ) {
    this.sendControl({ type: "peers_request" });
    this.sendControl(this.localPeersUpdate());
  }

  getRemotePeers(): readonly string[] {
    return this.remotePeers.map((peer) => peer.address);
  }

  tryRouteOutbound(env: Envelope): boolean {
    if (typeof env.to !== "string") return false;
    const target = frozenOldParseAddress(env.to);
    if (!target || target.pcLabel !== this.siblingPcLabel) return false;
    this.sent.push({
      toPc: this.siblingPcPubkey,
      env: { ...env, from: `${this.selfPcLabel}:${env.from}` },
    });
    return true;
  }

  receive(env: Envelope, fromPc: string): void {
    if (fromPc !== this.siblingPcPubkey) return;
    if (
      typeof env.from === "string" &&
      env.from.split(":", 1)[0] !== this.siblingPcLabel
    ) {
      return;
    }
    const body = env.body as {
      type?: unknown;
      peers?: unknown;
      peers_detailed?: unknown;
    } | null;
    const bodyType = body && typeof body === "object" ? body.type : undefined;
    if (bodyType === "peers_update") {
      this.remotePeers.splice(0, this.remotePeers.length, ...this.peersFromUpdate(body));
      return;
    }
    if (bodyType === "peers_request") {
      this.sendControl(this.localPeersUpdate());
      return;
    }
    if (typeof env.to !== "string") return;
    const target = frozenOldParseAddress(env.to);
    if (target && target.pcLabel !== this.selfPcLabel) return;
    const injected = target ? { ...env, to: target.peerName } : env;
    this.injected.push(injected);
    this.onInjected?.(injected);
    if (bodyType === "ack") return;
    this.sent.push({
      toPc: this.siblingPcPubkey,
      env: envelope(
        `${this.selfPcLabel}:broker`,
        env.from,
        { type: "ack", status: "received", target: injected.to },
        env.id,
      ),
    });
  }

  private localPeersUpdate(): FrozenOldControl {
    return {
      type: "peers_update",
      peers: [...this.localPeers],
      peers_detailed: this.localPeers.map((address) => ({
        cwd: "",
        name: address,
        address,
      })),
    };
  }

  private peersFromUpdate(body: {
    peers?: unknown;
    peers_detailed?: unknown;
  }): FrozenOldWirePeerInfo[] {
    if (Array.isArray(body.peers_detailed)) {
      return body.peers_detailed.filter((peer): peer is FrozenOldWirePeerInfo =>
        !!peer && typeof peer === "object" &&
        typeof (peer as FrozenOldWirePeerInfo).cwd === "string" &&
        typeof (peer as FrozenOldWirePeerInfo).name === "string" &&
        typeof (peer as FrozenOldWirePeerInfo).address === "string",
      );
    }
    return Array.isArray(body.peers)
      ? body.peers
        .filter((peer): peer is string => typeof peer === "string")
        .map((address) => ({ cwd: "", name: address, address }))
      : [];
  }

  private sendControl(body: FrozenOldControl): void {
    this.sent.push({
      toPc: this.siblingPcPubkey,
      env: envelope(
        `${this.selfPcLabel}:_broker_remote`,
        `${this.siblingPcLabel}:_broker_remote`,
        body,
        null,
      ),
    });
  }
}

interface CurrentOldDelivery {
  direction: "current→old" | "old→current";
  env: Envelope;
}

function pumpCurrentAndFrozenOld(
  currentPi: FakePi,
  old: FrozenOldBrokerRemoteOracle,
  currentPcPubkey: string,
  oldPcPubkey: string,
): CurrentOldDelivery[] {
  const deliveries: CurrentOldDelivery[] = [];
  for (let round = 0; round < 16; round += 1) {
    const fromCurrent = currentPi.sent.splice(0);
    const fromOld = old.sent.splice(0);
    if (fromCurrent.length === 0 && fromOld.length === 0) return deliveries;
    for (const sent of fromCurrent) {
      expect(sent.toPc).toBe(oldPcPubkey);
      deliveries.push({ direction: "current→old", env: sent.env });
      old.receive(sent.env, currentPcPubkey);
    }
    for (const sent of fromOld) {
      expect(sent.toPc).toBe(currentPcPubkey);
      deliveries.push({ direction: "old→current", env: sent.env });
      currentPi.emit("envelope", sent.env, oldPcPubkey);
    }
  }
  throw new Error("current/old compatibility link did not quiesce");
}

interface FakeBrokerOptions {
  injectStatus?: RemoteInjectStatus;
  onInject?: (env: Envelope) => void;
  /** Local peer names the fake broker reports via `peerNames()`. Used by
   *  `BrokerRemote` to seed `lastLocalPeers` and to answer
   *  `peers_request` envelopes. Defaults to a single self peer. */
  localPeers?: string[];
}

function makeFakeBroker(opts: FakeBrokerOptions = {}): {
  broker: Broker;
  injectFromRemote: ReturnType<typeof vi.fn>;
  setRemoteRouter: ReturnType<typeof vi.fn>;
  clearRemoteRouter: ReturnType<typeof vi.fn>;
  currentRemoteRouter: () => unknown;
  peerNames: ReturnType<typeof vi.fn>;
  localPeerInfos: ReturnType<typeof vi.fn>;
  injected: Envelope[];
} {
  const injected: Envelope[] = [];
  const status = opts.injectStatus ?? "received";
  const injectFromRemote = vi.fn((env: Envelope) => {
    injected.push(env);
    opts.onInject?.(env);
    return status;
  });
  let currentRemoteRouter: unknown = null;
  const setRemoteRouter = vi.fn((router: unknown) => {
    currentRemoteRouter = router;
  });
  const clearRemoteRouter = vi.fn((expected: unknown) => {
    if (currentRemoteRouter === expected) currentRemoteRouter = null;
  });
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
    clearRemoteRouter,
    peerNames,
    localPeerInfos,
  } as unknown as Broker;
  return {
    broker,
    injectFromRemote,
    setRemoteRouter,
    clearRemoteRouter,
    currentRemoteRouter: () => currentRemoteRouter,
    peerNames,
    localPeerInfos,
    injected,
  };
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
      topology: topology(
        { pcLabel: "self", pcPubkey: KEY_A },
        [{ pcLabel: "trab", pcPubkey: KEY_B }],
      ),
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
      topology: topology({ pcLabel: "self", pcPubkey: KEY_A }),
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
      topology: topology(
        { pcLabel: "self", pcPubkey: KEY_A },
        [{ pcLabel: "trab", pcPubkey: KEY_B }],
      ),
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
      topology: topology(
        { pcLabel: "casa", pcPubkey: KEY_A },
        [{ pcLabel: "trab", pcPubkey: KEY_B }],
      ),
    });

    const env = envelope("sess-3", "trab:agent-1", { x: 1 });
    expect(br.tryRouteOutbound(env)).toBe(true);
    expect(fakePi.sent.length).toBeGreaterThanOrEqual(1);
    const main = fakePi.sent.find((s) => s.env.id === env.id);
    expect(main).toBeDefined();
    expect(main!.toPc).toBe(KEY_B);
    expect(main!.env.from).toBe("casa:sess-3");
    expect(main!.env.to).toBe("trab:agent-1");
  });

  test("uses legacy labels only on normal and control wire prefixes", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    const br = new BrokerRemote({
      broker,
      pi: fakePi as never,
      topology: topology(
        { pcLabel: "Self%20Alias", pcPubkey: KEY_A, legacyPcLabel: "Self Alias" },
        [{ pcLabel: "Peer%20Alias", pcPubkey: KEY_B, legacyPcLabel: "Peer Alias" }],
      ),
    });
    fakePi.sent.length = 0;

    const outbound = envelope("local", "Peer%20Alias:agent", { hello: "world" });
    expect(br.tryRouteOutbound(outbound)).toBe(true);

    const normal = fakePi.sent.find((sent) => sent.env.id === outbound.id)!;
    const control = fakePi.sent.find((sent) =>
      (sent.env.body as { type?: string } | null)?.type === "peers_request",
    )!;
    expect(normal).toMatchObject({
      toPc: KEY_B,
      env: { from: "Self Alias:local", to: "Peer Alias:agent" },
    });
    expect(control.env).toMatchObject({
      from: "Self Alias:_broker_remote",
      to: "Peer Alias:_broker_remote",
    });
  });

  test("uses canonical standard-padded key prefixes when no nickname exists", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    const br = new BrokerRemote({
      broker,
      pi: fakePi as never,
      topology: topology(
        {
          pcLabel: "pc-self",
          pcPubkey: FALLBACK_KEY_A,
          legacyPcLabel: FALLBACK_KEY_A.slice(0, 8),
        },
        [{
          pcLabel: "pc-peer",
          pcPubkey: FALLBACK_KEY_B,
          legacyPcLabel: FALLBACK_KEY_B.slice(0, 8),
        }],
      ),
    });
    fakePi.sent.length = 0;

    expect(FALLBACK_KEY_A.slice(0, 8)).toMatch(/[+/]/);
    expect(FALLBACK_KEY_A.slice(0, 8)).not.toBe(FALLBACK_KEY_A_URL.slice(0, 8));
    expect(FALLBACK_KEY_B.slice(0, 8)).toMatch(/[+/]/);
    expect(FALLBACK_KEY_B.slice(0, 8)).not.toBe(FALLBACK_KEY_B_URL.slice(0, 8));
    const outbound = envelope("local", "pc-peer:agent", { hello: "world" });
    expect(br.tryRouteOutbound(outbound)).toBe(true);
    expect(fakePi.sent.find((sent) => sent.env.id === outbound.id)?.env).toMatchObject({
      from: `${FALLBACK_KEY_A.slice(0, 8)}:local`,
      to: `${FALLBACK_KEY_B.slice(0, 8)}:agent`,
    });
  });

  test("cache miss triggers a peers_request alongside the main send", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    const br = new BrokerRemote({
      broker, pi: fakePi as never,
      topology: topology(
        { pcLabel: "casa", pcPubkey: KEY_A },
        [{ pcLabel: "trab", pcPubkey: KEY_B }],
      ),
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
    expect(peersReq!.toPc).toBe(KEY_B);
  });

  test("does not trigger peers_request when cache is already populated", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    const br = new BrokerRemote({
      broker, pi: fakePi as never,
      topology: topology(
        { pcLabel: "casa", pcPubkey: KEY_A },
        [{ pcLabel: "trab", pcPubkey: KEY_B }],
      ),
    });

    // Prime the cache via peers_update
    fakePi.emit("envelope", envelope(
      "trab:_broker_remote", "casa:_broker_remote",
      { type: "peers_update", peers: ["agent-1"] },
    ), KEY_B);

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
      topology: topology(
        { pcLabel: "casa", pcPubkey: KEY_A },
        [{ pcLabel: "trab", pcPubkey: KEY_B }],
      ),
      log: (m) => logs.push(m),
    });

    fakePi.emit("envelope", envelope("evil:sess", "casa:agent-1", { x: 1 }), KEY_D);

    expect(injectFromRemote).not.toHaveBeenCalled();
    expect(logs.some((line) => /reason=unknown_from_pc/.test(line))).toBe(true);
    expect(logs.every((line) => !line.includes(KEY_D))).toBe(true);
  });

  test("sender prefix is display-only and rewrites to the receiver-local alias", () => {
    const fakePi = new FakePi();
    const { broker, injectFromRemote } = makeFakeBroker();
    const logs: string[] = [];
    new BrokerRemote({
      broker, pi: fakePi as never,
      topology: topology(
        { pcLabel: "casa", pcPubkey: KEY_A },
        [{ pcLabel: "trab", pcPubkey: KEY_B }],
      ),
      log: (m) => logs.push(m),
    });

    fakePi.emit("envelope", envelope("sender-old:sess", "receiver-old:agent-1", { x: 1 }), KEY_B_URL);

    expect(injectFromRemote).toHaveBeenCalledTimes(1);
    expect(injectFromRemote.mock.calls[0]![0]).toMatchObject({
      from: "trab:sess",
      to: "agent-1",
    });
    expect(logs).toEqual([]);
  });

  test("valid envelope → strip to-prefix, injectFromRemote, ACK back", () => {
    const fakePi = new FakePi();
    const { broker, injectFromRemote } = makeFakeBroker({ injectStatus: "received" });
    new BrokerRemote({
      broker, pi: fakePi as never,
      topology: topology(
        { pcLabel: "casa-local", pcPubkey: KEY_A, legacyPcLabel: "casa wire" },
        [{ pcLabel: "trab-local", pcPubkey: KEY_B, legacyPcLabel: "trab wire" }],
      ),
    });

    const inbound = envelope("trab wire:agent-1", "casa wire:sess-3", { hello: "world" });
    fakePi.emit("envelope", inbound, KEY_B);

    expect(injectFromRemote).toHaveBeenCalledTimes(1);
    const injected = injectFromRemote.mock.calls[0]![0] as Envelope;
    expect(injected.from).toBe("trab-local:agent-1");
    expect(injected.to).toBe("sess-3");  // prefix stripped

    // ACK packed back to K_B
    const acks = fakePi.sent.filter((s) =>
      (s.env.body as { type?: string } | null)?.type === "ack",
    );
    expect(acks).toHaveLength(1);
    expect(acks[0]!.toPc).toBe(KEY_B);
    expect(acks[0]!.env.re).toBe(inbound.id);
    expect(acks[0]!.env.from).toBe("casa wire:broker");
    expect(acks[0]!.env.to).toBe(inbound.from);
    expect((acks[0]!.env.body as { status: string }).status).toBe("received");
  });

  test("target prefix is display-only after Relay selected this Pi", () => {
    const fakePi = new FakePi();
    const { broker, injectFromRemote } = makeFakeBroker();
    const logs: string[] = [];
    new BrokerRemote({
      broker, pi: fakePi as never,
      topology: topology(
        { pcLabel: "casa", pcPubkey: KEY_A },
        [{ pcLabel: "trab", pcPubkey: KEY_B }],
      ),
      log: (m) => logs.push(m),
    });

    const inbound = envelope("trab:agent-1", "other:peer", { x: 1 });
    fakePi.emit("envelope", inbound, KEY_B);

    expect(injectFromRemote).toHaveBeenCalledTimes(1);
    expect(injectFromRemote.mock.calls[0]![0]).toMatchObject({
      from: "trab:agent-1",
      to: "peer",
    });
    expect(logs).toEqual([]);
  });

  test("incoming ACK does not generate a recursive ACK", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    new BrokerRemote({
      broker, pi: fakePi as never,
      topology: topology(
        { pcLabel: "casa", pcPubkey: KEY_A },
        [{ pcLabel: "trab", pcPubkey: KEY_B }],
      ),
    });

    const ackEnv: Envelope = envelope(
      "trab:broker", "casa:sess-3",
      { type: "ack", status: "received", target: "agent-1" },
      "01976000-0000-7000-8000-000000000000",
    );
    fakePi.emit("envelope", ackEnv, KEY_B);

    const generatedAck = fakePi.sent.find((s) =>
      (s.env.body as { type?: string } | null)?.type === "ack",
    );
    expect(generatedAck).toBeUndefined();
  });
});

// ── peers_update / peers_request control ────────────────────────────────────

describe("BrokerRemote: control envelopes (peers_update / peers_request)", () => {
  test("malformed id or re cannot mutate the roster or produce ACK/control traffic", () => {
    const fakePi = new FakePi();
    const { broker, injectFromRemote } = makeFakeBroker();
    const br = new BrokerRemote({
      broker, pi: fakePi as never,
      topology: topology(
        { pcLabel: "casa", pcPubkey: KEY_A },
        [{ pcLabel: "trab", pcPubkey: KEY_B }],
      ),
    });
    fakePi.emit("envelope", envelope(
      "trab:_broker_remote", "casa:_broker_remote",
      { type: "peers_update", peers: ["known"] },
    ), KEY_B);
    fakePi.sent.length = 0;

    for (const invalid of [
      { ...envelope("trab:_broker_remote", "casa:_broker_remote", { type: "peers_update", peers: ["forged"] }), id: "not-a-uuid" },
      { ...envelope("trab:_broker_remote", "casa:_broker_remote", { type: "peers_request" }), re: "not-a-uuid" },
    ]) {
      fakePi.emit("envelope", invalid as Envelope, KEY_B);
    }

    expect(br.getRemotePeers("trab")).toEqual(["known"]);
    expect(injectFromRemote).not.toHaveBeenCalled();
    expect(fakePi.sent).toEqual([]);
  });

  test("ordinary peers controls are delivered as content and cannot mutate or reply", () => {
    const fakePi = new FakePi();
    const { broker, injectFromRemote } = makeFakeBroker();
    const br = new BrokerRemote({
      broker, pi: fakePi as never,
      topology: topology(
        { pcLabel: "casa", pcPubkey: KEY_A },
        [{ pcLabel: "trab", pcPubkey: KEY_B }],
      ),
    });
    fakePi.sent.length = 0;

    const incoming = envelope(
      "trab:ordinary-agent", "casa:local-agent",
      { type: "peers_update", peers: ["forged"] },
    );
    fakePi.emit("envelope", incoming, KEY_B);

    expect(br.getRemotePeers("trab")).toEqual([]);
    expect(injectFromRemote).toHaveBeenCalledWith(expect.objectContaining({
      from: "trab:ordinary-agent",
      to: "local-agent",
      body: { type: "peers_update", peers: ["forged"] },
    }));
    const acks = fakePi.sent.filter((sent) =>
      (sent.env.body as { type?: string } | null)?.type === "ack",
    );
    expect(acks).toHaveLength(1);
    expect(acks[0]!.env.re).toBe(incoming.id);
  });

  test("invalid normal envelope emits no ACK after cross-PC address checks", () => {
    const fakePi = new FakePi();
    const { broker, injectFromRemote } = makeFakeBroker();
    new BrokerRemote({
      broker, pi: fakePi as never,
      topology: topology(
        { pcLabel: "casa", pcPubkey: KEY_A },
        [{ pcLabel: "trab", pcPubkey: KEY_B }],
      ),
    });
    fakePi.sent.length = 0;

    fakePi.emit("envelope", {
      ...envelope("trab:agent", "casa:local-agent", { hello: "world" }),
      id: "not-a-uuid",
    } as Envelope, KEY_B);

    expect(injectFromRemote).not.toHaveBeenCalled();
    expect(fakePi.sent).toEqual([]);
  });

  test("peers_update populates cache (getRemotePeers returns)", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    const br = new BrokerRemote({
      broker, pi: fakePi as never,
      topology: topology(
        { pcLabel: "casa", pcPubkey: KEY_A },
        [{ pcLabel: "trab", pcPubkey: KEY_B }],
      ),
    });

    fakePi.emit("envelope", envelope(
      "trab:_broker_remote", "casa:_broker_remote",
      { type: "peers_update", peers: ["agent-1", "agent-2"] },
    ), KEY_B);

    expect(br.getRemotePeers("trab")).toEqual(["agent-1", "agent-2"]);
    expect(br.listRemotePeers()).toEqual(["trab:agent-1", "trab:agent-2"]);
  });

  test("invalid or oversized peers_update is rejected atomically with metadata-only reason", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    const logs: string[] = [];
    const br = new BrokerRemote({
      broker, pi: fakePi as never,
      topology: topology(
        { pcLabel: "casa", pcPubkey: KEY_A },
        [{ pcLabel: "trab", pcPubkey: KEY_B }],
      ),
      log: (message) => logs.push(message),
    });
    fakePi.emit("envelope", envelope(
      "trab:_broker_remote", "casa:_broker_remote",
      { type: "peers_update", peers: ["known"] },
    ), KEY_B);

    fakePi.emit("envelope", envelope(
      "trab:_broker_remote", "casa:_broker_remote",
      { type: "peers_update", peers: Array.from({ length: 1025 }, () => "oversized") },
    ), KEY_B);
    fakePi.emit("envelope", envelope(
      "trab:_broker_remote", "casa:_broker_remote",
      {
        type: "peers_update",
        peers: ["still-invalid"],
        peers_detailed: [{ cwd: "/" + "x".repeat(4096), name: "agent", address: "still-invalid" }],
      },
    ), KEY_B);

    expect(br.getRemotePeers("trab")).toEqual(["known"]);
    expect(logs).toEqual([
      expect.stringMatching(/event=drop reason=invalid_peers_update/),
      expect.stringMatching(/event=drop reason=invalid_peers_update/),
    ]);
  });

  test("roster limits accept exact code-unit maxima and reject limit-plus-one atomically", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    const br = new BrokerRemote({
      broker, pi: fakePi as never,
      topology: topology(
        { pcLabel: "casa", pcPubkey: KEY_A },
        [{ pcLabel: "trab", pcPubkey: KEY_B }],
      ),
    });
    const cwd = `/${"c".repeat(4095)}`;
    const name = "n".repeat(255);
    const address = `${cwd}@${name}`;
    expect(cwd).toHaveLength(4096);
    expect(name).toHaveLength(255);
    expect(address).toHaveLength(4352);

    fakePi.emit("envelope", envelope(
      "trab:_broker_remote", "casa:_broker_remote",
      { type: "peers_update", peers: [address], peers_detailed: [{ cwd, name, address }] },
    ), KEY_B);
    expect(br.getRemotePeers("trab")).toEqual([address]);

    const invalidUpdates = [
      { type: "peers_update", peers: [address], peers_detailed: [{ cwd: `${cwd}x`, name, address }] },
      { type: "peers_update", peers: [address], peers_detailed: [{ cwd: "", name: "n".repeat(257), address: "short" }] },
      { type: "peers_update", peers: ["a".repeat(4353)] },
      { type: "peers_update", peers: Array.from({ length: 1025 }, () => "peer") },
    ];
    for (const body of invalidUpdates) {
      fakePi.emit("envelope", envelope(
        "trab:_broker_remote", "casa:_broker_remote", body,
      ), KEY_B);
    }
    expect(br.getRemotePeers("trab")).toEqual([address]);

    const codeUnitName = "😀".repeat(128);
    fakePi.emit("envelope", envelope(
      "trab:_broker_remote", "casa:_broker_remote",
      {
        type: "peers_update",
        peers: [codeUnitName],
        peers_detailed: [{ cwd: "", name: codeUnitName, address: codeUnitName }],
      },
    ), KEY_B);
    expect(codeUnitName).toHaveLength(256);
    expect(br.getRemotePeers("trab")).toEqual([codeUnitName]);
    const tooLongCodeUnitName = "😀".repeat(129);
    fakePi.emit("envelope", envelope(
      "trab:_broker_remote", "casa:_broker_remote",
      {
        type: "peers_update",
        peers: [tooLongCodeUnitName],
        peers_detailed: [{
          cwd: "",
          name: tooLongCodeUnitName,
          address: tooLongCodeUnitName,
        }],
      },
    ), KEY_B);
    expect(br.getRemotePeers("trab")).toEqual([codeUnitName]);

    fakePi.emit("envelope", envelope(
      "trab:_broker_remote", "casa:_broker_remote",
      { type: "peers_update", peers: Array.from({ length: 1024 }, () => "peer") },
    ), KEY_B);
    expect(br.getRemotePeers("trab")).toHaveLength(1024);
  });

  test("peers_update with peers_detailed → listRemotePeerInfos fills pc + prefixes address (plan/38 Fase 2)", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    const br = new BrokerRemote({
      broker, pi: fakePi as never,
      topology: topology(
        { pcLabel: "casa", pcPubkey: KEY_A },
        [{ pcLabel: "trab", pcPubkey: KEY_B }],
      ),
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
    ), KEY_B);

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
      topology: topology(
        { pcLabel: "casa", pcPubkey: KEY_A },
        [{ pcLabel: "trab", pcPubkey: KEY_B }],
      ),
    });

    // An older sibling sends addresses only — no peers_detailed.
    fakePi.emit("envelope", envelope(
      "trab:_broker_remote", "casa:_broker_remote",
      { type: "peers_update", peers: ["/w/app@App"] },
    ), KEY_B);

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
      topology: topology(
        { pcLabel: "casa", pcPubkey: KEY_A },
        [{ pcLabel: "trab", pcPubkey: KEY_B }],
      ),
      cacheTtlMs: 10,  // tight TTL for tests
    });

    fakePi.emit("envelope", envelope(
      "trab:_broker_remote", "casa:_broker_remote",
      { type: "peers_update", peers: ["agent-1"] },
    ), KEY_B);
    expect(br.getRemotePeers("trab")).toEqual(["agent-1"]);

    return new Promise<void>((resolve) => {
      setTimeout(() => {
        expect(br.getRemotePeers("trab")).toEqual([]);
        fakePi.sent.length = 0;
        br.tryRouteOutbound(envelope("local", "trab:agent-1", { retry: true }));
        expect(fakePi.sent.some((sent) =>
          (sent.env.body as { type?: string } | null)?.type === "peers_request",
        )).toBe(true);
        resolve();
      }, 30);
    });
  });

  test("peers_request triggers peers_update reply with current local peers", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker({ localPeers: ["sess-3", "agent-1"] });
    new BrokerRemote({
      broker, pi: fakePi as never,
      topology: topology(
        { pcLabel: "casa", pcPubkey: KEY_A },
        [{ pcLabel: "trab", pcPubkey: KEY_B }],
      ),
    });
    fakePi.sent.length = 0;

    fakePi.emit("envelope", envelope(
      "trab:_broker_remote", "casa:_broker_remote",
      { type: "peers_request" },
    ), KEY_B);

    const reply = fakePi.sent.find((s) =>
      (s.env.body as { type?: string } | null)?.type === "peers_update",
    );
    expect(reply).toBeDefined();
    expect(reply!.toPc).toBe(KEY_B);
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
      topology: topology(
        { pcLabel: "MacMini", pcPubkey: KEY_B },
        [{ pcLabel: "MacBook", pcPubkey: KEY_A }],
      ),
    });
    // Note: no `onLocalPeersChanged` was ever called. Bootstrap traffic
    // was sent; clear it so we observe the reply path cleanly.
    fakePi.sent.length = 0;

    fakePi.emit("envelope", envelope(
      "MacBook:_broker_remote", "MacMini:_broker_remote",
      { type: "peers_request" },
    ), KEY_A);

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
      topology: topology(
        { pcLabel: "casa", pcPubkey: KEY_A },
        [
        { pcLabel: "trab", pcPubkey: KEY_B },
        { pcLabel: "movel", pcPubkey: KEY_C },
      ],
      ),
    });
    // Discard bootstrap announce/request traffic; we only care about the
    // peers_update emitted by `onLocalPeersChanged` below.
    fakePi.sent.length = 0;
    br.onLocalPeersChanged(["sess-3"]);

    const updates = fakePi.sent.filter((s) =>
      (s.env.body as { type?: string } | null)?.type === "peers_update",
    );
    expect(updates.map((u) => u.toPc).sort()).toEqual([KEY_B, KEY_C]);
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
        topology: topology(
          { pcLabel: "casa", pcPubkey: KEY_A },
          [{ pcLabel: "trab", pcPubkey: KEY_B }],
        ),
        reannounceIntervalMs: 1_000,
      });
      fakePi.sent.length = 0;  // drop bootstrap request+push

      vi.advanceTimersByTime(1_000);
      // One full re-announce cycle = the bootstrap pair (request + push).
      const byType = (t: string) => fakePi.sent.filter(
        (s) => (s.env.body as { type?: string } | null)?.type === t,
      );
      expect(byType("peers_request").map((s) => s.toPc)).toEqual([KEY_B]);
      expect(byType("peers_update").map((s) => s.toPc)).toEqual([KEY_B]);

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

describe("BrokerRemote: trusted transport_error provenance boundary", () => {
  const VALID_RE = "01976000-0000-7000-8000-000000000000";

  function relayError(overrides: Partial<Envelope> = {}): Envelope {
    return {
      ...envelope(
        "_relay",
        "casa:sess-3",
        { type: "transport_error", reason: "offline", ignored: "private-detail" },
        VALID_RE,
      ),
      ...overrides,
    };
  }

  function ackCount(fakePi: FakePi): number {
    return fakePi.sent.filter(
      (sent) => (sent.env.body as { type?: string } | null)?.type === "ack",
    ).length;
  }

  test.each(["offline", "not_authorized", "bad_envelope"] as const)(
    "converts trusted Relay reason %s to exact local broker provenance without ACK",
    (reason) => {
      const fakePi = new FakePi();
      const { broker, injectFromRemote } = makeFakeBroker();
      new BrokerRemote({
        broker, pi: fakePi as never,
        topology: topology(
          { pcLabel: "casa", pcPubkey: KEY_A },
          [{ pcLabel: "trab", pcPubkey: KEY_B }],
        ),
      });

      const incoming = relayError({
        body: { type: "transport_error", reason, ignored: "must-not-cross" },
      });
      fakePi.emit("envelope", incoming, "_relay");

      expect(injectFromRemote).toHaveBeenCalledTimes(1);
      expect(injectFromRemote).toHaveBeenCalledWith({
        ...incoming,
        from: "broker",
        to: "sess-3",
        body: { type: "transport_error", reason },
      });
      expect(ackCount(fakePi)).toBe(0);
    },
  );

  test("strips the exact colon-containing self legacy label from trusted Relay errors", () => {
    const fakePi = new FakePi();
    const { broker, injectFromRemote } = makeFakeBroker();
    new BrokerRemote({
      broker,
      pi: fakePi as never,
      topology: topology(
        { pcLabel: "casa-local", pcPubkey: KEY_A, legacyPcLabel: ":casa:wire" },
        [{ pcLabel: "trab-local", pcPubkey: KEY_B, legacyPcLabel: "trab:wire" }],
      ),
    });

    fakePi.emit("envelope", relayError({ to: ":casa:wire:sess-3" }), "_relay");

    expect(injectFromRemote).toHaveBeenCalledWith(expect.objectContaining({
      from: "broker",
      to: "sess-3",
    }));
  });

  test("normalizes only lowercase 32-hex Relay error ids before strict broker injection", () => {
    const fakePi = new FakePi();
    const { broker, injectFromRemote } = makeFakeBroker();
    new BrokerRemote({
      broker, pi: fakePi as never,
      topology: topology(
        { pcLabel: "casa", pcPubkey: KEY_A },
        [{ pcLabel: "trab", pcPubkey: KEY_B }],
      ),
    });
    const legacyId = "01976000000070008000000000000000";
    fakePi.emit("envelope", relayError({ id: legacyId }), "_relay");

    expect(injectFromRemote).toHaveBeenCalledWith(expect.objectContaining({
      id: "01976000-0000-7000-8000-000000000000",
      from: "broker",
      to: "sess-3",
    }));
  });

  test("drops malformed privileged frames before UDS injection or ACK", () => {
    const fakePi = new FakePi();
    const { broker, injectFromRemote } = makeFakeBroker();
    const logs: string[] = [];
    new BrokerRemote({
      broker, pi: fakePi as never,
      topology: topology(
        { pcLabel: "casa", pcPubkey: KEY_A },
        [{ pcLabel: "trab", pcPubkey: KEY_B }],
      ),
      log: (message) => logs.push(message),
    });

    const invalidFrames: Envelope[] = [
      relayError({ from: "private-origin:sender" }),
      relayError({ id: "0197600000007000800000000000000A" }),
      relayError({ id: "not-a-uuid" }),
      relayError({ re: null }),
      relayError({ re: "01976000000070008000000000000000" }),
      relayError({ re: "not-a-uuid" }),
      relayError({ to: ["casa:private-target"] }),
      relayError({ to: "broadcast" }),
      relayError({ to: "casa:broadcast" }),
      relayError({ to: "casa:" }),
      relayError({ body: { type: "ack", reason: "offline" } }),
      relayError({ body: { type: "transport_error" } }),
      relayError({
        to: "casa:private-target",
        body: { type: "transport_error", reason: "TOP_SECRET_BODY" },
      }),
    ];
    for (const frame of invalidFrames) fakePi.emit("envelope", frame, "_relay");

    expect(injectFromRemote).not.toHaveBeenCalled();
    expect(ackCount(fakePi)).toBe(0);
    expect(logs).toHaveLength(invalidFrames.length);
    expect(logs.every((line) => /event=drop reason=invalid_relay_error/.test(line))).toBe(true);
    for (const privateValue of [
      "private-origin",
      "private-target",
      "TOP_SECRET_BODY",
      KEY_B,
    ]) {
      expect(logs.every((line) => !line.includes(privateValue))).toBe(true);
    }
  });

  test.each([
    [KEY_B, "_relay"],
    ["_relay ", "_relay"],
    ["_RELAY", "_relay"],
  ])("requires the exact authenticated outer sentinel: %s", (fromPc, innerFrom) => {
    const fakePi = new FakePi();
    const { broker, injectFromRemote } = makeFakeBroker();
    new BrokerRemote({
      broker, pi: fakePi as never,
      topology: topology(
        { pcLabel: "casa", pcPubkey: KEY_A },
        [{ pcLabel: "trab", pcPubkey: KEY_B }],
      ),
      log: () => undefined,
    });

    fakePi.emit("envelope", relayError({ from: innerFrom }), fromPc);

    expect(injectFromRemote).not.toHaveBeenCalled();
    expect(ackCount(fakePi)).toBe(0);
  });

  test.each([
    {
      from: "sender-old:sender",
      body: { type: "transport_error", reason: "offline" },
      expectedFrom: "trab:sender",
    },
    {
      from: "sender-old:_relay",
      body: { text: "_relay" },
      expectedFrom: "trab:_relay",
    },
  ])("keeps authenticated sibling text ordinary for $expectedFrom", ({ from, body, expectedFrom }) => {
    const fakePi = new FakePi();
    const { broker, injectFromRemote } = makeFakeBroker({ injectStatus: "received" });
    new BrokerRemote({
      broker, pi: fakePi as never,
      topology: topology(
        { pcLabel: "casa", pcPubkey: KEY_A },
        [{ pcLabel: "trab", pcPubkey: KEY_B }],
      ),
    });

    const incoming = envelope(from, "casa:sess-3", body);
    fakePi.emit("envelope", incoming, KEY_B);

    expect(injectFromRemote).toHaveBeenCalledTimes(1);
    expect(injectFromRemote.mock.calls[0]![0]).toMatchObject({
      from: expectedFrom,
      to: "sess-3",
      body,
    });
    expect(injectFromRemote.mock.calls[0]![0].from).not.toBe("broker");
    expect(ackCount(fakePi)).toBe(1);
  });
});

// ── setTopology ──────────────────────────────────────────────────────────────

describe("BrokerRemote.setTopology", () => {
  test("dropping a sibling clears its cache entry", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    const br = new BrokerRemote({
      broker, pi: fakePi as never,
      topology: topology(
        { pcLabel: "casa", pcPubkey: KEY_A },
        [
        { pcLabel: "trab", pcPubkey: KEY_B },
        { pcLabel: "movel", pcPubkey: KEY_C },
      ],
      ),
    });
    fakePi.emit("envelope", envelope(
      "trab:_broker_remote", "casa:_broker_remote",
      { type: "peers_update", peers: ["agent-1"] },
    ), KEY_B);
    expect(br.getRemotePeers("trab")).toEqual(["agent-1"]);

    br.setTopology(topology(
      { pcLabel: "casa", pcPubkey: KEY_A },
      [{ pcLabel: "movel", pcPubkey: KEY_C }],
    ));
    expect(br.getRemotePeers("trab")).toEqual([]);
  });

  test("self never appears in sibling set", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    const br = new BrokerRemote({
      broker, pi: fakePi as never,
      topology: topology(
        { pcLabel: "casa", pcPubkey: KEY_A },
        [
        { pcLabel: "casa", pcPubkey: KEY_A },     // self by both
        { pcLabel: "trab", pcPubkey: KEY_B },
      ],
      ),
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
      topology: topology(
        { pcLabel: "casa", pcPubkey: KEY_A },
        [
        { pcLabel: "trab", pcPubkey: KEY_B },
        { pcLabel: "movel", pcPubkey: KEY_C },
      ],
      ),
    });

    const requests = fakePi.sent.filter((s) =>
      (s.env.body as { type?: string } | null)?.type === "peers_request",
    );
    expect(requests.map((r) => r.toPc).sort()).toEqual([KEY_B, KEY_C]);
  });

  test("constructor also announces our own peers (peers_update) to every sibling", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker({ localPeers: ["MacMini"] });
    new BrokerRemote({
      broker, pi: fakePi as never,
      topology: topology(
        { pcLabel: "MacMini", pcPubkey: KEY_B },
        [{ pcLabel: "MacBook", pcPubkey: KEY_A }],
      ),
    });

    const announces = fakePi.sent.filter((s) =>
      (s.env.body as { type?: string } | null)?.type === "peers_update",
    );
    expect(announces.length).toBe(1);
    expect(announces[0]!.toPc).toBe(KEY_A);
    expect((announces[0]!.env.body as { peers: string[] }).peers).toEqual(["MacMini"]);
  });

  test("no peers_request emitted when there are zero siblings", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    new BrokerRemote({
      broker, pi: fakePi as never,
      topology: topology({ pcLabel: "casa", pcPubkey: KEY_A }),
    });

    expect(fakePi.sent.length).toBe(0);
  });

  test("setTopology sends peers_request only to newly-added siblings", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    const br = new BrokerRemote({
      broker, pi: fakePi as never,
      topology: topology(
        { pcLabel: "casa", pcPubkey: KEY_A },
        [{ pcLabel: "trab", pcPubkey: KEY_B }],
      ),
    });
    // Drop initial bootstrap traffic so the assertion is isolated.
    fakePi.sent.length = 0;

    // Replace with set that keeps K_B and adds K_C. We expect a single
    // peers_request to K_C; K_B should NOT be re-pinged.
    br.setTopology(topology(
      { pcLabel: "casa", pcPubkey: KEY_A },
      [
        { pcLabel: "trab", pcPubkey: KEY_B },
        { pcLabel: "movel", pcPubkey: KEY_C },
      ],
    ));

    const requests = fakePi.sent.filter((s) =>
      (s.env.body as { type?: string } | null)?.type === "peers_request",
    );
    expect(requests.map((r) => r.toPc)).toEqual([KEY_C]);
  });

  test("setTopology refreshes a retained sibling when only its wire label changes", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    const br = new BrokerRemote({
      broker,
      pi: fakePi as never,
      topology: topology(
        { pcLabel: "casa", pcPubkey: KEY_A, legacyPcLabel: "casa-old" },
        [{ pcLabel: "trab", pcPubkey: KEY_B, legacyPcLabel: "trab-old" }],
      ),
    });
    fakePi.sent.length = 0;

    br.setTopology(topology(
      { pcLabel: "casa", pcPubkey: KEY_A, legacyPcLabel: "casa-old" },
      [{ pcLabel: "trab", pcPubkey: KEY_B, legacyPcLabel: "trab-new" }],
    ));

    const controls = fakePi.sent.filter((sent) => sent.toPc === KEY_B);
    expect(controls).toHaveLength(2);
    expect(controls.every((sent) => sent.env.to === "trab-new:_broker_remote")).toBe(true);
  });

  test("setTopology removes a sibling without firing peers_request for the survivors", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    const br = new BrokerRemote({
      broker, pi: fakePi as never,
      topology: topology(
        { pcLabel: "casa", pcPubkey: KEY_A },
        [
        { pcLabel: "trab", pcPubkey: KEY_B },
        { pcLabel: "movel", pcPubkey: KEY_C },
      ],
      ),
    });
    fakePi.sent.length = 0;

    br.setTopology(topology(
      { pcLabel: "casa", pcPubkey: KEY_A },
      [{ pcLabel: "movel", pcPubkey: KEY_C }],
    ));

    const requests = fakePi.sent.filter((s) =>
      (s.env.body as { type?: string } | null)?.type === "peers_request",
    );
    expect(requests).toEqual([]);
  });
});

describe("BrokerRemote canonical topology and receiver-local routing", () => {
  test.each([KEY_B, KEY_B_URL])(
    "canonicalizes authenticated from_pc variant %s and ignores divergent text aliases",
    (fromPc) => {
      const fakePi = new FakePi();
      const { broker, injectFromRemote } = makeFakeBroker();
      new BrokerRemote({
        broker,
        pi: fakePi as never,
        topology: topology(
          { pcLabel: "Captiva-RTX-4090", pcPubkey: KEY_A },
          [{ pcLabel: "mac", pcPubkey: KEY_B }],
        ),
        reannounceIntervalMs: 0,
      });
      fakePi.sent.length = 0;

      fakePi.emit(
        "envelope",
        envelope(
          "Mac:C:\\work\\sender@agent",
          "RTX4090:/local@target",
          { hello: "world" },
        ),
        fromPc,
      );

      expect(injectFromRemote).toHaveBeenCalledTimes(1);
      expect(injectFromRemote.mock.calls[0]![0]).toMatchObject({
        from: "mac:C:\\work\\sender@agent",
        to: "/local@target",
      });
    },
  );

  test("invalid and unknown authenticated keys drop with metadata-only diagnostics", () => {
    const fakePi = new FakePi();
    const { broker, injectFromRemote } = makeFakeBroker();
    const logs: string[] = [];
    new BrokerRemote({
      broker,
      pi: fakePi as never,
      topology: topology(
        { pcLabel: "self", pcPubkey: KEY_A },
        [{ pcLabel: "remote", pcPubkey: KEY_B }],
      ),
      reannounceIntervalMs: 0,
      log: (message) => logs.push(message),
    });

    fakePi.emit(
      "envelope",
      envelope("raw-secret:sender", "raw-target:local", { secret: true }),
      "bad key",
    );
    fakePi.emit(
      "envelope",
      envelope("raw-secret:sender", "raw-target:local", { secret: true }),
      KEY_D,
    );

    expect(injectFromRemote).not.toHaveBeenCalled();
    expect(logs).toHaveLength(2);
    expect(logs[0]).toMatch(/reason=invalid_from_pc/);
    expect(logs[1]).toMatch(/reason=unknown_from_pc fingerprint=[0-9a-f]{8}/);
    expect(logs.every((line) => !/raw-secret|raw-target|bad key|secret/.test(line))).toBe(true);
  });

  test("rejects a sibling alias that conflicts with the self alias", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();

    expect(() => new BrokerRemote({
      broker,
      pi: fakePi as never,
      topology: topology(
        { pcLabel: "same", pcPubkey: KEY_A },
        [{ pcLabel: "same", pcPubkey: KEY_B }],
      ),
      reannounceIntervalMs: 0,
    })).toThrow(/alias conflicts with self/);
  });

  test("alias-only topology refresh preserves cache, rekeys roster, and reboots controls", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    const br = new BrokerRemote({
      broker,
      pi: fakePi as never,
      topology: topology(
        { pcLabel: "self-old", pcPubkey: KEY_A },
        [{ pcLabel: "remote-old", pcPubkey: KEY_B }],
      ),
      reannounceIntervalMs: 0,
    });
    fakePi.sent.length = 0;
    fakePi.emit(
      "envelope",
      envelope(
        "sender-old:_broker_remote",
        "receiver-old:_broker_remote",
        { type: "peers_update", peers: ["/remote@app"] },
      ),
      KEY_B_URL,
    );
    expect(br.listRemotePeers()).toEqual(["remote-old:/remote@app"]);
    fakePi.sent.length = 0;

    br.setTopology(
      topology(
        { pcLabel: "self-new", pcPubkey: KEY_A },
        [{ pcLabel: "remote-new", pcPubkey: KEY_B_URL }],
      ),
    );

    expect(br.listRemotePeers()).toEqual(["remote-new:/remote@app"]);
    expect(fakePi.sent.filter((sent) =>
      (sent.env.body as { type?: string } | null)?.type === "peers_request"
    ).map((sent) => sent.toPc)).toEqual([KEY_B]);
    expect(fakePi.sent.filter((sent) =>
      (sent.env.body as { type?: string } | null)?.type === "peers_update"
    ).map((sent) => sent.toPc)).toEqual([KEY_B]);
    const outbound = envelope("local", "remote-new:agent", { task: true });
    br.tryRouteOutbound(outbound);
    expect(fakePi.sent.find((sent) => sent.env.id === outbound.id)?.env.from)
      .toBe("self-new:local");

    expect(() => br.setTopology(topology(
      { pcLabel: "self-new", pcPubkey: KEY_C },
      [{ pcLabel: "remote-new", pcPubkey: KEY_B }],
    ))).toThrow(/self public key/);
    expect(br.listRemotePeers()).toEqual(["remote-new:/remote@app"]);
  });

  test("prototype-like aliases remain own data keys in grouped listings", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    const br = new BrokerRemote({
      broker,
      pi: fakePi as never,
      topology: topology(
        { pcLabel: "self", pcPubkey: KEY_A },
        [{ pcLabel: "__proto__", pcPubkey: KEY_B }],
      ),
      reannounceIntervalMs: 0,
    });
    fakePi.emit("envelope", envelope(
      "ignored:_broker_remote",
      "self:_broker_remote",
      { type: "peers_update", peers: ["remote"] },
    ), KEY_B);

    const grouped = br.getAllRemote();
    expect(Object.prototype.hasOwnProperty.call(grouped, "__proto__")).toBe(true);
    expect(grouped["__proto__"]).toEqual(["remote"]);
    expect(Object.getPrototypeOf(grouped)).toBe(Object.prototype);
  });

  test("invalid alias/key topology is rejected atomically", () => {
    const fakePi = new FakePi();
    const { broker } = makeFakeBroker();
    const br = new BrokerRemote({
      broker,
      pi: fakePi as never,
      topology: topology(
        { pcLabel: "self", pcPubkey: KEY_A },
        [{ pcLabel: "remote", pcPubkey: KEY_B }],
      ),
      reannounceIntervalMs: 0,
    });
    fakePi.sent.length = 0;

    expect(() => br.setTopology(topology(
      { pcLabel: "self", pcPubkey: KEY_A },
      [
        { pcLabel: "duplicate", pcPubkey: KEY_C },
        { pcLabel: "duplicate", pcPubkey: KEY_D },
      ],
    ))).toThrow(/duplicate sibling routing alias/);
    expect(() => br.setTopology(topology(
      { pcLabel: "self", pcPubkey: KEY_A },
      [
        { pcLabel: "one", pcPubkey: KEY_B },
        { pcLabel: "two", pcPubkey: KEY_B_URL },
      ],
    ))).toThrow(/duplicate sibling public key/);

    const outbound = envelope("local", "remote:agent", { task: true });
    expect(br.tryRouteOutbound(outbound)).toBe(true);
    expect(fakePi.sent.find((sent) => sent.env.id === outbound.id)?.toPc).toBe(KEY_B);
  });

  test("missing technical prefixes fail closed without logging addresses", () => {
    const fakePi = new FakePi();
    const { broker, injectFromRemote } = makeFakeBroker();
    const logs: string[] = [];
    new BrokerRemote({
      broker,
      pi: fakePi as never,
      topology: topology(
        { pcLabel: "self", pcPubkey: KEY_A },
        [{ pcLabel: "remote", pcPubkey: KEY_B }],
      ),
      reannounceIntervalMs: 0,
      log: (message) => logs.push(message),
    });

    fakePi.emit("envelope", envelope("no-prefix", "self:target", { x: 1 }), KEY_B);
    fakePi.emit("envelope", envelope("old:sender", "no-prefix", { x: 2 }), KEY_B);
    fakePi.emit("envelope", envelope("old:", "self:target", { x: 3 }), KEY_B);
    fakePi.emit("envelope", {
      ...envelope("old:sender", "self:target", { x: 4 }),
      to: ["self:target"],
    }, KEY_B);

    expect(injectFromRemote).not.toHaveBeenCalled();
    expect(logs).toEqual([
      expect.stringMatching(/reason=invalid_cross_pc_address/),
      expect.stringMatching(/reason=invalid_cross_pc_address/),
      expect.stringMatching(/reason=invalid_cross_pc_address/),
      expect.stringMatching(/reason=invalid_to/),
    ]);
    expect(logs.every((line) => !/no-prefix|target|sender/.test(line))).toBe(true);
  });
});

describe("BrokerRemote current ↔ frozen old-Extension compatibility oracle", () => {
  test.each([
    {
      name: "shared unique colon-free raw signed nickname labels",
      newNickname: "New-Office",
      oldNickname: "Old-Studio",
      newPcPubkey: KEY_A,
      oldPcPubkey: KEY_B,
    },
    {
      name: "no-nickname canonical standard-padded key.slice(0, 8) fallback",
      newNickname: undefined,
      oldNickname: undefined,
      newPcPubkey: FALLBACK_KEY_A,
      oldPcPubkey: FALLBACK_KEY_B,
    },
  ])("preserves bootstrap, delivery, ACKs, replies, and receiver-local aliases for $name", ({
    newNickname,
    oldNickname,
    newPcPubkey,
    oldPcPubkey,
  }) => {
    const newLegacyLabel = frozenOldLegacyPcLabel(newNickname, newPcPubkey);
    const oldLegacyLabel = frozenOldLegacyPcLabel(oldNickname, oldPcPubkey);
    if (newNickname === undefined && oldNickname === undefined) {
      expect(newLegacyLabel).toBe(newPcPubkey.slice(0, 8));
      expect(oldLegacyLabel).toBe(oldPcPubkey.slice(0, 8));
      for (const [standard, urlSafe] of [
        [newPcPubkey, FALLBACK_KEY_A_URL],
        [oldPcPubkey, FALLBACK_KEY_B_URL],
      ]) {
        expect(standard.slice(0, 8)).toMatch(/[+/]/);
        expect(standard.slice(0, 8)).not.toBe(urlSafe.slice(0, 8));
      }
    }

    const currentPi = new FakePi();
    const currentPending = new FrozenPendingAckRegistry();
    const oldPending = new FrozenPendingAckRegistry();
    const currentBroker = makeFakeBroker({
      localPeers: ["new-sender"],
      onInject: (env) => currentPending.consume(env),
    });
    const current = new BrokerRemote({
      broker: currentBroker.broker,
      pi: currentPi as never,
      topology: topology(
        {
          pcLabel: "new-self-local",
          pcPubkey: newPcPubkey,
          legacyPcLabel: newLegacyLabel,
        },
        [{
          pcLabel: "old-at-new",
          pcPubkey: oldPcPubkey,
          legacyPcLabel: oldLegacyLabel,
        }],
      ),
      reannounceIntervalMs: 0,
    });
    const old = new FrozenOldBrokerRemoteOracle(
      oldLegacyLabel,
      newLegacyLabel,
      newPcPubkey,
      ["old-worker"],
      (env) => oldPending.consume(env),
    );

    try {
      // Both implementations bootstrap with peers_request + peers_update in
      // both directions, using the exact historical legacy prefixes.
      const bootstrap = pumpCurrentAndFrozenOld(
        currentPi,
        old,
        newPcPubkey,
        oldPcPubkey,
      );
      expect(bootstrap).toEqual(expect.arrayContaining([
        expect.objectContaining({
          direction: "current→old",
          env: expect.objectContaining({
            from: `${newLegacyLabel}:_broker_remote`,
            to: `${oldLegacyLabel}:_broker_remote`,
            body: expect.objectContaining({ type: "peers_request" }),
          }),
        }),
        expect.objectContaining({
          direction: "current→old",
          env: expect.objectContaining({
            from: `${newLegacyLabel}:_broker_remote`,
            to: `${oldLegacyLabel}:_broker_remote`,
            body: expect.objectContaining({ type: "peers_update" }),
          }),
        }),
        expect.objectContaining({
          direction: "old→current",
          env: expect.objectContaining({
            from: `${oldLegacyLabel}:_broker_remote`,
            to: `${newLegacyLabel}:_broker_remote`,
            body: expect.objectContaining({ type: "peers_request" }),
          }),
        }),
        expect.objectContaining({
          direction: "old→current",
          env: expect.objectContaining({
            from: `${oldLegacyLabel}:_broker_remote`,
            to: `${newLegacyLabel}:_broker_remote`,
            body: expect.objectContaining({ type: "peers_update" }),
          }),
        }),
      ]));
      const oldUpdate = bootstrap.find((delivery) =>
        delivery.direction === "old→current" &&
        (delivery.env.body as { type?: string } | null)?.type === "peers_update",
      );
      expect(oldUpdate?.env.body).toEqual({
        type: "peers_update",
        peers: ["old-worker"],
        peers_detailed: [{ cwd: "", name: "old-worker", address: "old-worker" }],
      });
      expect(current.getRemotePeers("old-at-new")).toEqual(["old-worker"]);
      expect(old.getRemotePeers()).toEqual(["new-sender"]);

      // New → old: current emits old labels, old settles the one wire ACK.
      const newToOld = envelope(
        "new-sender",
        "old-at-new:old-worker",
        { type: "work", direction: "new-to-old" },
      );
      currentPending.track(newToOld, "old-at-new:broker");
      expect(current.tryRouteOutbound(newToOld)).toBe(true);
      const newToOldDeliveries = pumpCurrentAndFrozenOld(
        currentPi,
        old,
        newPcPubkey,
        oldPcPubkey,
      );
      const newToOldRequest = newToOldDeliveries.filter((delivery) =>
        delivery.direction === "current→old" && delivery.env.id === newToOld.id,
      );
      const newToOldAck = newToOldDeliveries.filter((delivery) =>
        delivery.direction === "old→current" &&
        delivery.env.re === newToOld.id &&
        (delivery.env.body as { type?: string } | null)?.type === "ack",
      );
      expect(newToOldRequest).toHaveLength(1);
      expect(newToOldAck).toHaveLength(1);
      expect(newToOldAck[0]!.env.to).toBe(newToOldRequest[0]!.env.from);
      expect(newToOldAck[0]!.env.re).toBe(newToOld.id);
      expect(old.injected).toContainEqual(expect.objectContaining({
        id: newToOld.id,
        from: `${newLegacyLabel}:new-sender`,
        to: "old-worker",
      }));
      const newToOldSettled = currentBroker.injected.filter(
        (candidate) => candidate.re === newToOld.id,
      );
      expect(newToOldSettled).toHaveLength(1);
      expect(newToOldSettled[0]).toMatchObject({
        from: "old-at-new:broker",
        to: "new-sender",
        body: expect.objectContaining({ type: "ack", target: "old-worker" }),
      });
      expectExactlyOnceSettlement(
        currentPending,
        newToOld.id,
        newToOldSettled[0]!,
      );

      // Old → new: current strips the wire labels and old gets one ACK back.
      const oldToNew = envelope(
        "old-worker",
        `${newLegacyLabel}:new-sender`,
        { type: "work", direction: "old-to-new" },
      );
      oldPending.track(oldToNew, `${newLegacyLabel}:broker`);
      expect(old.tryRouteOutbound(oldToNew)).toBe(true);
      const oldToNewDeliveries = pumpCurrentAndFrozenOld(
        currentPi,
        old,
        newPcPubkey,
        oldPcPubkey,
      );
      const oldToNewRequest = oldToNewDeliveries.filter((delivery) =>
        delivery.direction === "old→current" && delivery.env.id === oldToNew.id,
      );
      const oldToNewAck = oldToNewDeliveries.filter((delivery) =>
        delivery.direction === "current→old" &&
        delivery.env.re === oldToNew.id &&
        (delivery.env.body as { type?: string } | null)?.type === "ack",
      );
      expect(oldToNewRequest).toHaveLength(1);
      expect(oldToNewAck).toHaveLength(1);
      expect(oldToNewAck[0]!.env.to).toBe(oldToNewRequest[0]!.env.from);
      expect(oldToNewAck[0]!.env.re).toBe(oldToNew.id);
      expect(currentBroker.injected).toContainEqual(expect.objectContaining({
        id: oldToNew.id,
        from: "old-at-new:old-worker",
        to: "new-sender",
      }));
      const oldToNewSettled = old.injected.filter(
        (candidate) => candidate.re === oldToNew.id,
      );
      expect(oldToNewSettled).toHaveLength(1);
      expect(oldToNewSettled[0]).toMatchObject({
        from: `${newLegacyLabel}:broker`,
        to: "old-worker",
        body: expect.objectContaining({ type: "ack", target: "new-sender" }),
      });
      expectExactlyOnceSettlement(
        oldPending,
        oldToNew.id,
        oldToNewSettled[0]!,
      );

      // Replies retain correlation and each produces one reverse wire ACK.
      const oldReply = envelope(
        "old-worker",
        `${newLegacyLabel}:new-sender`,
        { type: "reply", direction: "old-to-new" },
        newToOld.id,
      );
      oldPending.track(oldReply, `${newLegacyLabel}:broker`);
      expect(old.tryRouteOutbound(oldReply)).toBe(true);
      const oldReplyDeliveries = pumpCurrentAndFrozenOld(
        currentPi,
        old,
        newPcPubkey,
        oldPcPubkey,
      );
      const oldReplyRequest = oldReplyDeliveries.filter((delivery) =>
        delivery.direction === "old→current" && delivery.env.id === oldReply.id,
      );
      const oldReplyAck = oldReplyDeliveries.filter((delivery) =>
        delivery.direction === "current→old" &&
        delivery.env.re === oldReply.id &&
        (delivery.env.body as { type?: string } | null)?.type === "ack",
      );
      expect(oldReplyRequest).toHaveLength(1);
      expect(oldReplyAck).toHaveLength(1);
      expect(oldReplyAck[0]!.env.to).toBe(oldReplyRequest[0]!.env.from);
      expect(oldReplyAck[0]!.env.re).toBe(oldReply.id);
      const oldReplySettled = old.injected.filter(
        (candidate) => candidate.re === oldReply.id,
      );
      expect(oldReplySettled).toHaveLength(1);
      expectExactlyOnceSettlement(
        oldPending,
        oldReply.id,
        oldReplySettled[0]!,
      );
      expect(currentBroker.injected).toContainEqual(expect.objectContaining({
        id: oldReply.id,
        re: newToOld.id,
        from: "old-at-new:old-worker",
        to: "new-sender",
      }));

      const newReply = envelope(
        "new-sender",
        "old-at-new:old-worker",
        { type: "reply", direction: "new-to-old" },
        oldToNew.id,
      );
      currentPending.track(newReply, "old-at-new:broker");
      expect(current.tryRouteOutbound(newReply)).toBe(true);
      const newReplyDeliveries = pumpCurrentAndFrozenOld(
        currentPi,
        old,
        newPcPubkey,
        oldPcPubkey,
      );
      const newReplyRequest = newReplyDeliveries.filter((delivery) =>
        delivery.direction === "current→old" && delivery.env.id === newReply.id,
      );
      const newReplyAck = newReplyDeliveries.filter((delivery) =>
        delivery.direction === "old→current" &&
        delivery.env.re === newReply.id &&
        (delivery.env.body as { type?: string } | null)?.type === "ack",
      );
      expect(newReplyRequest).toHaveLength(1);
      expect(newReplyAck).toHaveLength(1);
      expect(newReplyAck[0]!.env.to).toBe(newReplyRequest[0]!.env.from);
      expect(newReplyAck[0]!.env.re).toBe(newReply.id);
      const newReplySettled = currentBroker.injected.filter(
        (candidate) => candidate.re === newReply.id,
      );
      expect(newReplySettled).toHaveLength(1);
      expectExactlyOnceSettlement(
        currentPending,
        newReply.id,
        newReplySettled[0]!,
      );
      expect(old.injected).toContainEqual(expect.objectContaining({
        id: newReply.id,
        re: oldToNew.id,
        from: `${newLegacyLabel}:new-sender`,
        to: "old-worker",
      }));
    } finally {
      current.detach();
    }
  });
});

describe("BrokerRemote linked two-PC matrix", () => {
  test("exchanges control, messages, ACKs, and replies with leading and embedded-colon legacy labels", () => {
    const localPeersA = ["/mac/orchestrator@Orch", "/mac/api@Api"];
    const localPeersB = ["/rtx/worker@Worker", "/rtx/tests@Test"];
    const piA = new FakePi();
    const piB = new FakePi();
    const brokerA = makeFakeBroker({ localPeers: localPeersA });
    const brokerB = makeFakeBroker({ localPeers: localPeersB });
    const remoteA = new BrokerRemote({
      broker: brokerA.broker,
      pi: piA as never,
      topology: topology(
        { pcLabel: "Mac", pcPubkey: KEY_A, legacyPcLabel: "Mac:Wire" },
        [{ pcLabel: "RTX4090", pcPubkey: KEY_B, legacyPcLabel: ":Captiva Wire" }],
      ),
      reannounceIntervalMs: 0,
    });
    const remoteB = new BrokerRemote({
      broker: brokerB.broker,
      pi: piB as never,
      topology: topology(
        { pcLabel: "Captiva-RTX-4090", pcPubkey: KEY_B, legacyPcLabel: ":Captiva Wire" },
        [{ pcLabel: "mac", pcPubkey: KEY_A, legacyPcLabel: "Mac:Wire" }],
      ),
      reannounceIntervalMs: 0,
    });
    const link = new BoundedInMemoryPiLink(piA, piB);

    try {
      const bootstrap = link.pumpUntilQuiescent();
      expect(bootstrap.some((delivery) =>
        (delivery.env.body as { type?: string } | null)?.type === "peers_request"
      )).toBe(true);
      expect(bootstrap.some((delivery) =>
        (delivery.env.body as { type?: string } | null)?.type === "peers_update"
      )).toBe(true);
      expect(piA.sent).toEqual([]);
      expect(piB.sent).toEqual([]);

      expect(remoteA.getAllRemote()).toEqual({ RTX4090: localPeersB });
      expect(remoteA.getRemotePeers("RTX4090")).toEqual(localPeersB);
      expect(remoteA.listRemotePeers()).toEqual(
        localPeersB.map((address) => `RTX4090:${address}`),
      );
      expect(remoteA.listRemotePeerInfos()).toEqual(
        localPeersB.map((address) => ({
          pc: "RTX4090",
          cwd: "",
          name: address,
          address: `RTX4090:${address}`,
        })),
      );

      expect(remoteB.getAllRemote()).toEqual({ mac: localPeersA });
      expect(remoteB.getRemotePeers("mac")).toEqual(localPeersA);
      expect(remoteB.listRemotePeers()).toEqual(
        localPeersA.map((address) => `mac:${address}`),
      );
      expect(remoteB.listRemotePeerInfos()).toEqual(
        localPeersA.map((address) => ({
          pc: "mac",
          cwd: "",
          name: address,
          address: `mac:${address}`,
        })),
      );

      const modes = [
        {
          direction: "A→B" as const,
          senderRemote: remoteA,
          receiverRemote: remoteB,
          senderBroker: brokerA,
          receiverBroker: brokerB,
          senderLocal: localPeersA[0]!,
          receiverLocal: localPeersB[0]!,
          senderWireAlias: "Mac:Wire",
          receiverWireAlias: ":Captiva Wire",
          receiverAliasAtSender: "RTX4090",
          senderAliasAtReceiver: "mac",
          authenticatedSender: KEY_A_URL,
          authenticatedReceiver: KEY_B_URL,
        },
        {
          direction: "B→A" as const,
          senderRemote: remoteB,
          receiverRemote: remoteA,
          senderBroker: brokerB,
          receiverBroker: brokerA,
          senderLocal: localPeersB[1]!,
          receiverLocal: localPeersA[1]!,
          senderWireAlias: ":Captiva Wire",
          receiverWireAlias: "Mac:Wire",
          receiverAliasAtSender: "mac",
          senderAliasAtReceiver: "RTX4090",
          authenticatedSender: KEY_B_URL,
          authenticatedReceiver: KEY_A_URL,
        },
      ];

      for (const mode of modes) {
        const messageBody = { type: "work", direction: mode.direction };
        const message = envelope(
          mode.senderLocal,
          `${mode.receiverAliasAtSender}:${mode.receiverLocal}`,
          messageBody,
        );
        expect(mode.senderRemote.tryRouteOutbound(message)).toBe(true);
        const messageDeliveries = link.pumpUntilQuiescent();
        const messageOnWire = messageDeliveries.find(
          (delivery) => delivery.env.id === message.id,
        );
        expect(messageOnWire).toMatchObject({
          direction: mode.direction,
          authenticatedFromPc: mode.authenticatedSender,
          env: {
            from: `${mode.senderWireAlias}:${mode.senderLocal}`,
            to: `${mode.receiverWireAlias}:${mode.receiverLocal}`,
            id: message.id,
            re: null,
            body: messageBody,
          },
        });
        expect(mode.senderWireAlias).not.toBe(mode.senderAliasAtReceiver);
        expect(mode.receiverAliasAtSender).not.toBe(mode.receiverWireAlias);
        const ackOnWire = messageDeliveries.find((delivery) =>
          delivery.env.re === message.id &&
          (delivery.env.body as { type?: string } | null)?.type === "ack",
        );
        expect(ackOnWire?.env).toMatchObject({
          from: `${mode.receiverWireAlias}:broker`,
          to: messageOnWire?.env.from,
          re: message.id,
        });

        const receivedMessage = mode.receiverBroker.injected.find(
          (candidate) => candidate.id === message.id,
        );
        expect(receivedMessage).toEqual({
          ...message,
          from: `${mode.senderAliasAtReceiver}:${mode.senderLocal}`,
          to: mode.receiverLocal,
        });
        const messageAck = mode.senderBroker.injected.find(
          (candidate) =>
            candidate.re === message.id &&
            (candidate.body as { type?: string } | null)?.type === "ack",
        );
        expect(messageAck).toMatchObject({
          from: `${mode.receiverAliasAtSender}:broker`,
          to: mode.senderLocal,
          re: message.id,
          body: {
            type: "ack",
            status: "received",
            target: mode.receiverLocal,
          },
        });

        const replyBody = { type: "reply", direction: mode.direction };
        const reply = envelope(
          mode.receiverLocal,
          `${mode.senderAliasAtReceiver}:${mode.senderLocal}`,
          replyBody,
          message.id,
        );
        expect(mode.receiverRemote.tryRouteOutbound(reply)).toBe(true);
        const replyDeliveries = link.pumpUntilQuiescent();
        const reverseDirection = mode.direction === "A→B" ? "B→A" : "A→B";
        const replyOnWire = replyDeliveries.find(
          (delivery) => delivery.env.id === reply.id,
        );
        expect(replyOnWire).toMatchObject({
          direction: reverseDirection,
          authenticatedFromPc: mode.authenticatedReceiver,
          env: {
            from: `${mode.receiverWireAlias}:${mode.receiverLocal}`,
            to: `${mode.senderWireAlias}:${mode.senderLocal}`,
            id: reply.id,
            re: message.id,
            body: replyBody,
          },
        });
        const replyAckOnWire = replyDeliveries.find((delivery) =>
          delivery.env.re === reply.id &&
          (delivery.env.body as { type?: string } | null)?.type === "ack",
        );
        expect(replyAckOnWire?.env).toMatchObject({
          from: `${mode.senderWireAlias}:broker`,
          to: replyOnWire?.env.from,
          re: reply.id,
        });

        const receivedReply = mode.senderBroker.injected.find(
          (candidate) => candidate.id === reply.id,
        );
        expect(receivedReply).toEqual({
          ...reply,
          from: `${mode.receiverAliasAtSender}:${mode.receiverLocal}`,
          to: mode.senderLocal,
        });
        const replyAck = mode.receiverBroker.injected.find(
          (candidate) =>
            candidate.re === reply.id &&
            (candidate.body as { type?: string } | null)?.type === "ack",
        );
        expect(replyAck).toMatchObject({
          from: `${mode.senderAliasAtReceiver}:broker`,
          to: mode.receiverLocal,
          re: reply.id,
          body: {
            type: "ack",
            status: "received",
            target: mode.senderLocal,
          },
        });
      }

      expect(KEY_A_URL).not.toBe(KEY_A);
      expect(KEY_B_URL).not.toBe(KEY_B);
      expect(piA.sent).toEqual([]);
      expect(piB.sent).toEqual([]);
    } finally {
      remoteA.detach();
      remoteB.detach();
    }
  });
});
