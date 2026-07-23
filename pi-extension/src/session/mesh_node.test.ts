import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import type { Ed25519Keypair } from "../pairing/crypto.js";
import type { MeshTopologySnapshot } from "../mesh/siblings.js";

const SELF_SECRET = Buffer.from(
  "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60",
  "hex",
);
const SELF_PUBLIC = Buffer.from(
  "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a",
  "hex",
);
const SIBLING_PUBLIC = Buffer.from(
  "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c",
  "hex",
);
const OWNER_PUBLIC = Buffer.from(
  "fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025",
  "hex",
);
const KEYPAIR: Ed25519Keypair = {
  secretKey: SELF_SECRET,
  publicKey: SELF_PUBLIC,
};

function standardKey(bytes: Uint8Array): string {
  return Buffer.from(bytes).toString("base64");
}

function topology(
  selfAlias = "self",
  siblingAlias = "sibling",
  selfLegacyPcLabel = selfAlias,
  siblingLegacyPcLabel = siblingAlias,
): MeshTopologySnapshot {
  return {
    self: {
      pcLabel: selfAlias,
      pcPubkey: standardKey(SELF_PUBLIC),
      legacyPcLabel: selfLegacyPcLabel,
    },
    siblings: [
      {
        pcLabel: siblingAlias,
        pcPubkey: standardKey(SIBLING_PUBLIC),
        legacyPcLabel: siblingLegacyPcLabel,
      },
    ],
  };
}

const peerHarness = vi.hoisted(() => {
  const defaults: {
    role: "leader" | "follower";
    broker: object | null;
  } = { role: "leader", broker: { id: "broker-1" } };
  const instances: MockSessionPeer[] = [];

  class MockSessionPeer {
    role: "leader" | "follower";
    broker: object | null;
    readonly reconnectHandlers = new Set<() => void>();
    readonly start = vi.fn(async () => this.assignedName);
    readonly send = vi.fn(async () => undefined);
    readonly sendWithAck = vi.fn(async () => ({ status: "received", id: "ack" }));
    readonly request = vi.fn(async () => ({ body: { peers: [] } }));
    readonly onMessage = vi.fn(() => () => undefined);
    readonly leave = vi.fn(async () => undefined);
    readonly rename = vi.fn(async (name: string) => {
      this.assignedName = name;
      return name;
    });
    private assignedName: string;

    constructor(opts: { name: string }) {
      this.assignedName = opts.name;
      this.role = defaults.role;
      this.broker = defaults.broker;
      instances.push(this);
    }

    currentRole(): "leader" | "follower" { return this.role; }
    localBroker(): object | null { return this.broker; }
    name(): string { return this.assignedName; }
    address(): string { return this.assignedName; }
    onReconnect(handler: () => void): () => void {
      this.reconnectHandlers.add(handler);
      return () => this.reconnectHandlers.delete(handler);
    }
    triggerReconnect(): void {
      for (const handler of this.reconnectHandlers) handler();
    }
  }

  return { defaults, instances, MockSessionPeer };
});

vi.mock("./peer.js", () => ({ SessionPeer: peerHarness.MockSessionPeer }));

const relayHarness = vi.hoisted(() => {
  class MockRelayClient {
    static OPEN = 1;
    readyState = MockRelayClient.OPEN;
    readonly send = vi.fn();
    readonly sendControl = vi.fn();
    readonly connect = vi.fn(async () => undefined);
    readonly close = vi.fn(() => { this.readyState = 3; });
    private readonly listeners = new Map<string, Set<(...args: unknown[]) => void>>();

    constructor(
      readonly url = "wss://relay.test",
      readonly keypair?: Ed25519Keypair,
    ) {}

    on(event: string, handler: (...args: unknown[]) => void): this {
      const handlers = this.listeners.get(event) ?? new Set();
      handlers.add(handler);
      this.listeners.set(event, handlers);
      return this;
    }
    off(event: string, handler: (...args: unknown[]) => void): this {
      this.listeners.get(event)?.delete(handler);
      return this;
    }
    isOpen(): boolean {
      return this.readyState === MockRelayClient.OPEN;
    }
  }

  return { MockRelayClient };
});

vi.mock("../transport/relay_client.js", () => ({
  RelayClient: relayHarness.MockRelayClient,
}));

const storageHarness = vi.hoisted(() => ({
  listOwnerPubkeys: vi.fn<() => Promise<unknown[]>>().mockResolvedValue([]),
  getOrCreateEd25519Keypair: vi.fn(async () => KEYPAIR),
}));

vi.mock("../pairing/storage.js", () => ({
  listOwnerPubkeys: storageHarness.listOwnerPubkeys,
  getOrCreateEd25519Keypair: storageHarness.getOrCreateEd25519Keypair,
}));

const brokerRemoteHarness = vi.hoisted(() => {
  const instances: MockBrokerRemote[] = [];
  class MockBrokerRemote {
    readonly setTopology = vi.fn();
    readonly activate = vi.fn();
    readonly detach = vi.fn();
    constructor(readonly options: Record<string, unknown>) {
      instances.push(this);
    }
  }
  return { instances, MockBrokerRemote };
});

vi.mock("./broker_remote.js", () => ({
  BrokerRemote: brokerRemoteHarness.MockBrokerRemote,
}));

const piForwardHarness = vi.hoisted(() => {
  class MockPiForwardClient {
    readonly detach = vi.fn();
    readonly on = vi.fn();
    readonly off = vi.fn();
    constructor(readonly relay: unknown) {}
  }
  return { MockPiForwardClient };
});

vi.mock("../transport/pi_forward_client.js", () => ({
  PiForwardClient: piForwardHarness.MockPiForwardClient,
}));

const bridgeModule = await import("./bridge.js");
const { MeshNode } = await import("./mesh_node.js");

type TestMeshNode = InstanceType<typeof MeshNode> & {
  setTopology(snapshot: MeshTopologySnapshot): void;
  hasTopology(): boolean;
};

type TestBridge = {
  brokerRemote: { setTopology: ReturnType<typeof vi.fn> };
  piForward: object;
  topology: MeshTopologySnapshot;
  activate: ReturnType<typeof vi.fn>;
  detach: ReturnType<typeof vi.fn>;
};

function testNode(role: "leader" | "follower" = "leader"): {
  node: TestMeshNode;
  peer: InstanceType<typeof peerHarness.MockSessionPeer>;
} {
  peerHarness.defaults.role = role;
  peerHarness.defaults.broker = { id: "broker" };
  const node = new MeshNode({
    sockPath: "/tmp/mesh-node-test.sock",
    name: "agent",
  }) as TestMeshNode;
  return { node, peer: peerHarness.instances.at(-1)! };
}

function injectedRelay(): InstanceType<typeof relayHarness.MockRelayClient> {
  return new relayHarness.MockRelayClient("wss://relay.test", KEYPAIR);
}

function bridge(snapshot = topology()): TestBridge {
  return {
    brokerRemote: { setTopology: vi.fn() },
    piForward: {},
    topology: snapshot,
    activate: vi.fn(),
    detach: vi.fn(),
  };
}

describe("MeshNode retained topology", () => {
  let attachSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    peerHarness.instances.length = 0;
    peerHarness.defaults.role = "leader";
    peerHarness.defaults.broker = { id: "broker" };
    storageHarness.listOwnerPubkeys.mockReset().mockResolvedValue([]);
    brokerRemoteHarness.instances.length = 0;
    attachSpy = vi.spyOn(bridgeModule, "attachCrossPcBridge");
  });

  afterEach(() => {
    attachSpy.mockRestore();
    vi.useRealTimers();
    vi.unstubAllGlobals();
  });

  test("follower retains topology until it can lead", async () => {
    const retained = topology();
    const attached = bridge(retained);
    attachSpy.mockResolvedValue(attached as never);
    const { node, peer } = testNode("follower");

    node.setTopology(retained);
    await node.attachBridge({
      relay: injectedRelay() as never,
      relayUrl: "https://relay.test",
      keypair: KEYPAIR,
    });
    expect(attachSpy).not.toHaveBeenCalled();

    peer.role = "leader";
    peer.broker = { id: "promoted-broker" };
    peer.triggerReconnect();
    await vi.waitFor(() => expect(attachSpy).toHaveBeenCalledTimes(1));

    expect(attachSpy).toHaveBeenCalledWith(expect.objectContaining({
      broker: peer.broker,
      topology: retained,
    }));
    expect(attached.activate).toHaveBeenCalledTimes(1);
  });

  test("attaching a bridge later applies retained topology", async () => {
    const retained = topology("retained-self", "retained-sibling");
    attachSpy.mockResolvedValue(bridge(retained) as never);
    const { node } = testNode();

    node.setTopology(retained);
    expect(node.hasTopology()).toBe(true);
    await node.attachBridge({
      relay: injectedRelay() as never,
      relayUrl: "https://relay.test",
      keypair: KEYPAIR,
    });

    expect(attachSpy).toHaveBeenCalledWith(expect.objectContaining({
      topology: retained,
    }));
  });

  test("retains and forwards a wire-label-only topology change", async () => {
    const first = topology("self", "sibling", "self-wire", "sibling-wire");
    const updated = topology("self", "sibling", "self-wire-next", "sibling-wire");
    const attached = bridge(first);
    attachSpy.mockResolvedValue(attached as never);
    const { node } = testNode();

    node.setTopology(first);
    await node.attachBridge({
      relay: injectedRelay() as never,
      relayUrl: "https://relay.test",
      keypair: KEYPAIR,
    });
    node.setTopology(updated);

    expect(attached.brokerRemote.setTopology).toHaveBeenCalledWith(updated);
  });

  test("failover uses the latest retained topology", async () => {
    const first = bridge(topology("first-self", "first-sibling"));
    const second = bridge(topology("latest-self", "latest-sibling"));
    attachSpy.mockResolvedValueOnce(first as never).mockResolvedValueOnce(second as never);
    const { node, peer } = testNode();

    node.setTopology(first.topology);
    await node.attachBridge({
      relay: injectedRelay() as never,
      relayUrl: "https://relay.test",
      keypair: KEYPAIR,
    });
    node.setTopology(second.topology);
    peer.broker = { id: "failover-broker" };
    peer.triggerReconnect();
    await vi.waitFor(() => expect(attachSpy).toHaveBeenCalledTimes(2));

    expect(first.detach).toHaveBeenCalledTimes(1);
    expect(attachSpy.mock.calls[1]![0]).toMatchObject({
      broker: peer.broker,
      topology: second.topology,
    });
  });
});

describe("cross-PC bridge discovery boundary", () => {
  beforeEach(() => {
    storageHarness.listOwnerPubkeys.mockReset().mockResolvedValue([]);
    brokerRemoteHarness.instances.length = 0;
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.unstubAllGlobals();
  });

  test("supplied topology bypasses discovery", async () => {
    const supplied = topology();
    storageHarness.listOwnerPubkeys.mockResolvedValue([standardKey(OWNER_PUBLIC)]);
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);
    const broker = { setRemoteRouter: vi.fn(), clearRemoteRouter: vi.fn() };

    const result = await bridgeModule.attachCrossPcBridge({
      broker: broker as never,
      relay: injectedRelay() as never,
      relayUrl: "https://relay.test",
      keypair: KEYPAIR,
      topology: supplied,
    });

    expect(storageHarness.listOwnerPubkeys).not.toHaveBeenCalled();
    expect(fetchMock).not.toHaveBeenCalled();
    expect(result.topology).toEqual(supplied);
    expect(brokerRemoteHarness.instances[0]!.options).toMatchObject({
      topology: supplied,
      activateOnConstruct: false,
    });
    result.detach();
  });

  test("discovery falls back after finite header and body deadlines", async () => {
    vi.useFakeTimers();
    storageHarness.listOwnerPubkeys.mockResolvedValue([standardKey(OWNER_PUBLIC)]);
    const broker = { setRemoteRouter: vi.fn(), clearRemoteRouter: vi.fn() };

    for (const phase of ["headers", "body"] as const) {
      const fetchMock = vi.fn(async () => {
        if (phase === "headers") return await new Promise<Response>(() => undefined);
        return {
          status: 200,
          json: () => new Promise<unknown>(() => undefined),
        } as Response;
      });
      vi.stubGlobal("fetch", fetchMock);

      const attaching = bridgeModule.attachCrossPcBridge({
        broker: broker as never,
        relay: injectedRelay() as never,
        relayUrl: "https://relay.test",
        keypair: KEYPAIR,
        meshRequestTimeoutMs: 25,
      });
      await vi.advanceTimersByTimeAsync(25);
      const result = await attaching;

      expect(fetchMock).toHaveBeenCalledTimes(1);
      expect(result.topology).toMatchObject({
        self: { pcPubkey: standardKey(SELF_PUBLIC) },
        siblings: [],
      });
      result.detach();
    }
  });
});
