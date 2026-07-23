import type { Broker } from "./broker.js";
import { BrokerRemote } from "./broker_remote.js";
import { PiForwardClient } from "../transport/pi_forward_client.js";
import type { RelayClient } from "../transport/relay_client.js";
import { MeshClient } from "../mesh/client.js";
import {
  buildTopologySnapshot,
  discoverTopology,
  type MeshTopologySnapshot,
} from "../mesh/siblings.js";
import {
  canonicalizeEd25519PublicKey,
  encodeEd25519PublicKey,
} from "../mesh/encoding.js";
import { listOwnerPubkeys } from "../pairing/storage.js";
import type { Ed25519Keypair } from "../pairing/crypto.js";

/**
 * Cross-PC mesh bridge composition. Discovery finishes before either transport
 * half is constructed, and the returned bridge stays dormant until its caller
 * has re-checked lifecycle ownership and calls `activate()`.
 */

export interface AttachBridgeOptions {
  /** The leader's local Broker (from SessionPeer.localBroker()). */
  broker: Broker;
  /** Live relay connection. Caller owns its lifecycle. */
  relay: RelayClient;
  /** Relay URL in http(s):// form — for standalone topology discovery. */
  relayUrl: string;
  /** This host's Ed25519 identity (machine Pi-key). */
  keypair: Ed25519Keypair;
  /** Retained Pi-produced topology. Supplying it bypasses discovery. */
  topology?: MeshTopologySnapshot;
  /** Standalone discovery deadline per mesh request. Defaults to 5 seconds. */
  meshRequestTimeoutMs?: number;
  /** Diagnostic logger. Defaults to a no-op (avoids TUI leaks). */
  log?: (msg: string) => void;
}

export interface CrossPcBridge {
  brokerRemote: BrokerRemote;
  piForward: PiForwardClient;
  topology: MeshTopologySnapshot;
  /** Publish the already-built router exactly once. */
  activate(): void;
  /** Safe before or after activation; tears down both halves exactly once. */
  detach(): void;
}

function compareAscii(left: string, right: string): number {
  return left < right ? -1 : left > right ? 1 : 0;
}

function validateAlias(alias: unknown, field: string): string {
  if (typeof alias !== "string" || alias.length === 0 || alias.includes(":")) {
    throw new Error(`mesh: ${field} is not a valid routing alias`);
  }
  return alias;
}

function validateLegacyPcLabel(label: unknown, field: string): string {
  if (typeof label !== "string" || label.length === 0) {
    throw new Error(`mesh: ${field} is not a valid legacy PC label`);
  }
  return label;
}

function ownTopology(
  snapshot: MeshTopologySnapshot,
  expectedSelfPubkey: string,
): MeshTopologySnapshot {
  const selfPubkey = canonicalizeEd25519PublicKey(
    snapshot.self?.pcPubkey,
    "self public key",
  );
  if (selfPubkey !== expectedSelfPubkey) {
    throw new Error("mesh: topology self public key does not match relay identity");
  }
  const selfLabel = validateAlias(snapshot.self.pcLabel, "self.pcLabel");
  const selfLegacyPcLabel = validateLegacyPcLabel(
    snapshot.self.legacyPcLabel,
    "self.legacyPcLabel",
  );
  const self = Object.freeze({
    pcLabel: selfLabel,
    pcPubkey: selfPubkey,
    legacyPcLabel: selfLegacyPcLabel,
  });
  const siblingKeys = new Set<string>();
  const siblingAliases = new Set<string>();
  const normalizedSiblings: Array<Readonly<{
    pcLabel: string;
    pcPubkey: string;
    legacyPcLabel: string;
  }>> = [];
  for (const [index, sibling] of snapshot.siblings.entries()) {
    const pcPubkey = canonicalizeEd25519PublicKey(
      sibling.pcPubkey,
      `siblings[${index}].pcPubkey`,
    );
    if (pcPubkey === selfPubkey) continue;
    const pcLabel = validateAlias(sibling.pcLabel, `siblings[${index}].pcLabel`);
    const legacyPcLabel = validateLegacyPcLabel(
      sibling.legacyPcLabel,
      `siblings[${index}].legacyPcLabel`,
    );
    if (pcLabel === selfLabel || siblingAliases.has(pcLabel)) {
      throw new Error("mesh: duplicate sibling routing alias");
    }
    if (siblingKeys.has(pcPubkey)) {
      throw new Error("mesh: duplicate sibling public key");
    }
    siblingAliases.add(pcLabel);
    siblingKeys.add(pcPubkey);
    normalizedSiblings.push(Object.freeze({ pcLabel, pcPubkey, legacyPcLabel }));
  }
  normalizedSiblings.sort((left, right) => compareAscii(left.pcPubkey, right.pcPubkey));
  return Object.freeze({ self, siblings: Object.freeze(normalizedSiblings) });
}

async function discoverStandaloneTopology(
  opts: AttachBridgeOptions,
): Promise<MeshTopologySnapshot> {
  const silent = { warn: (_message: string): void => { /* metadata stays silent in TUI */ } };
  try {
    const owners = await listOwnerPubkeys();
    return await discoverTopology({
      client: new MeshClient(opts.relayUrl, {
        ...(opts.meshRequestTimeoutMs !== undefined
          ? { requestTimeoutMs: opts.meshRequestTimeoutMs }
          : {}),
      }),
      ownerEpks: owners,
      myPubkey: opts.keypair.publicKey,
      log: silent,
    });
  } catch {
    return buildTopologySnapshot(opts.keypair.publicKey, []);
  }
}

export async function attachCrossPcBridge(
  opts: AttachBridgeOptions,
): Promise<CrossPcBridge> {
  const expectedSelfPubkey = encodeEd25519PublicKey(
    opts.keypair.publicKey,
    "relay public key",
  );
  const topology = ownTopology(
    opts.topology ?? await discoverStandaloneTopology(opts),
    expectedSelfPubkey,
  );

  // No Relay listeners exist until all standalone discovery has completed.
  const piForward = new PiForwardClient(opts.relay);
  let brokerRemote: BrokerRemote;
  try {
    brokerRemote = new BrokerRemote({
      broker: opts.broker,
      pi: piForward,
      topology,
      activateOnConstruct: false,
      log: opts.log ?? ((): void => {}),
    });
  } catch (error) {
    piForward.detach();
    throw error;
  }

  let state: "dormant" | "active" | "detached" = "dormant";
  return {
    brokerRemote,
    piForward,
    topology,
    activate(): void {
      if (state !== "dormant") return;
      try {
        brokerRemote.activate();
        state = "active";
      } catch (error) {
        state = "detached";
        try {
          brokerRemote.detach();
        } finally {
          piForward.detach();
        }
        throw error;
      }
    },
    detach(): void {
      if (state === "detached") return;
      state = "detached";
      try {
        brokerRemote.detach();
      } finally {
        piForward.detach();
      }
    },
  };
}
