import type { Broker, RemoteInjectStatus, RemoteRouter } from "./broker.js";
import { safeLogString, shortId } from "../log_safety.js";
import { type Envelope, envelope, uuidv7 } from "./envelope.js";
import type { PiForwardClient } from "../transport/pi_forward_client.js";

/**
 * Plan/25 Wave B/C — cross-PC broker.
 *
 * Maintains a cache of `<pc_label> → { peers, pc_pubkey, ts }` populated
 * by `peers_update` envelopes pushed from sibling Pis and refreshed lazily
 * via `peers_request` on cache miss.
 *
 * Owns two halves of the protocol:
 *
 *  - **Outbound** (`tryRouteOutbound`): broker hands off envelopes with a
 *    known `<pc>:` prefix. We rewrite `env.from` with our own pc_label,
 *    pack onto the relay via `pi_forward_client.sendEnvelopeToPi`.
 *
 *  - **Inbound** (`handleIncoming`): `pi_forward_client` emits envelopes
 *    received from a verified `from_pc`. We:
 *      1. Anti-spoof the `envelope.from` prefix against the sibling cache
 *         keyed by `from_pc` (defends against a Pi lying about its own
 *         `pc_label`).
 *      2. Intercept control envelopes (`peers_update`, `peers_request`,
 *         `transport_error`) before any local UDS delivery.
 *      3. Strip the `<pc>:` prefix from `env.to` and call
 *         `broker.injectFromRemote`. Build a one-way ACK envelope back via
 *         the relay so the cross-PC sender's `sendWithAck` resolves.
 *
 * The replies-bypass-busy rule from Wave 0 is honoured at injection time
 * by the broker itself; `broker_remote` does not duplicate the check.
 *
 * Siblings (`Map<pc_label, pc_pubkey>`) are seeded externally by the
 * extension at bootstrap (typically from `mesh_versions` of every paired
 * Owner). Membership is the only thing we trust to ground anti-spoof —
 * the cache of peers is just for routing UX.
 */

const CACHE_TTL_MS = 5 * 60_000;
const PEERS_REQUEST_TIMEOUT_MS = 2_000;
const BROKER_NAME = "broker";

export interface RemotePeerEntry {
  peers: string[];
  pcPubkey: string;
  ts: number;
}

interface SiblingInfo {
  pcLabel: string;
  pcPubkey: string;
}

export interface BrokerRemoteOptions {
  broker: Broker;
  pi: PiForwardClient;
  selfPcLabel: string;
  selfPcPubkey: string;
  /** Initial siblings (Pis-irmãos of the same Owner). May be extended later. */
  siblings?: SiblingInfo[];
  /** TTL override (testing). */
  cacheTtlMs?: number;
  /** Logger (defaults to console.error). */
  log?: (msg: string) => void;
}

interface PeersUpdateBody {
  type: "peers_update";
  peers: string[];
}

interface PeersRequestBody {
  type: "peers_request";
}

interface AckBody {
  type: "ack";
  status: RemoteInjectStatus;
  target: string;
}

/** Promise + resolver for pending `peers_request` cache fills. */
interface PendingFill {
  resolve: () => void;
  timer: ReturnType<typeof setTimeout>;
}

export class BrokerRemote implements RemoteRouter {
  private readonly broker: Broker;
  private readonly pi: PiForwardClient;
  private readonly selfPcLabel: string;
  private readonly selfPcPubkey: string;
  private readonly cacheTtlMs: number;
  private readonly log: (msg: string) => void;

  /** Siblings: pc_label → pc_pubkey. Authoritative for anti-spoof. */
  private readonly siblingByLabel = new Map<string, string>();
  /** Reverse index built from siblings: pc_pubkey → pc_label. */
  private readonly siblingByPubkey = new Map<string, string>();

  /** Cache of peers per remote pc_label. */
  private readonly remotePeers = new Map<string, RemotePeerEntry>();
  /** In-flight `peers_request` calls, keyed by pc_label. */
  private readonly pendingFills = new Map<string, Set<PendingFill>>();

  /** Local peers (UDS) at the moment of last `onLocalPeersChanged` call. */
  private lastLocalPeers: string[] = [];

  private readonly onIncoming: (env: Envelope, fromPc: string) => void;
  private detached = false;

  constructor(opts: BrokerRemoteOptions) {
    this.broker = opts.broker;
    this.pi = opts.pi;
    this.selfPcLabel = opts.selfPcLabel;
    this.selfPcPubkey = opts.selfPcPubkey;
    this.cacheTtlMs = opts.cacheTtlMs ?? CACHE_TTL_MS;
    this.log = opts.log ?? ((msg) => console.error(msg));

    for (const s of opts.siblings ?? []) this._addSibling(s);

    this.onIncoming = (env, fromPc) => this.handleIncoming(env, fromPc);
    this.pi.on("envelope", this.onIncoming);

    this.broker.setRemoteRouter(this);

    // Seed `lastLocalPeers` from the live broker so the first
    // `onLocalPeersChanged`-triggered push (or the bootstrap pushes below)
    // already carry real state. Without seeding, the same single-peer
    // mesh bug applies to OUTGOING `peers_update`s too: we'd announce
    // ourselves to siblings as having zero peers.
    this.lastLocalPeers = this.broker.peerNames();

    // Plan/25 Wave B bootstrap: kick a `peers_request` at every known
    // sibling so the cache is warm before anyone calls `list_peers` or
    // `agent_send` cross-PC. Also push our current peer list proactively
    // so siblings don't have to wait for their own request roundtrip.
    // Best-effort; siblings offline at boot will reply when they come
    // online and push their own `peers_update`.
    this._bootstrapWithSiblings();
  }

  /** Bootstrap: announce ourselves AND ask every sibling for their peers.
   *  Single helper so `_addSibling` can reuse half of it when a new
   *  sibling appears via `setSiblings`. */
  private _bootstrapWithSiblings(): void {
    for (const [, pcPubkey] of this.siblingByLabel) {
      this._sendControlEnvelope(pcPubkey, { type: "peers_request" });
      this._sendControlEnvelope(pcPubkey, {
        type: "peers_update",
        peers: this.lastLocalPeers,
      });
    }
  }

  detach(): void {
    if (this.detached) return;
    this.detached = true;
    this.pi.off("envelope", this.onIncoming);
    this.broker.setRemoteRouter(null);
  }

  // ── Sibling management ────────────────────────────────────────────────────

  /** Replace or extend the sibling set. Idempotent on identical input.
   *  Removes any sibling missing from `next`. Plan/25 Wave B bootstrap:
   *  fires `peers_request` at any sibling that wasn't in the previous
   *  set so the cache warms up without waiting for their next push. */
  setSiblings(next: SiblingInfo[]): void {
    const prevPubkeys = new Set(this.siblingByPubkey.keys());
    this.siblingByLabel.clear();
    this.siblingByPubkey.clear();
    for (const s of next) this._addSibling(s);
    // Drop cache entries for siblings that disappeared.
    for (const label of [...this.remotePeers.keys()]) {
      if (!this.siblingByLabel.has(label)) this.remotePeers.delete(label);
    }
    // For newly-added pubkeys: do the same announce+request pair the
    // constructor does. Re-pinging siblings we already knew about would
    // be wasteful (and triggers redundant audit lines on their side).
    for (const [, pcPubkey] of this.siblingByLabel) {
      if (prevPubkeys.has(pcPubkey)) continue;
      this._sendControlEnvelope(pcPubkey, { type: "peers_request" });
      this._sendControlEnvelope(pcPubkey, {
        type: "peers_update",
        peers: this.lastLocalPeers,
      });
    }
  }

  private _addSibling(s: SiblingInfo): void {
    if (!s.pcLabel || !s.pcPubkey) return;
    if (s.pcLabel === this.selfPcLabel) return;  // never list self as sibling
    if (s.pcPubkey === this.selfPcPubkey) return;
    this.siblingByLabel.set(s.pcLabel, s.pcPubkey);
    this.siblingByPubkey.set(s.pcPubkey, s.pcLabel);
  }

  // ── Public cache API ──────────────────────────────────────────────────────

  /** Returns the cached peer list for a remote pc_label, or [] when
   *  unknown / expired. */
  getRemotePeers(pcLabel: string): string[] {
    const entry = this.remotePeers.get(pcLabel);
    if (!entry) return [];
    if (Date.now() - entry.ts > this.cacheTtlMs) return [];
    return [...entry.peers];
  }

  /** Returns the full cross-PC inventory: pc_label → peers (TTL-respected). */
  getAllRemote(): Record<string, string[]> {
    const out: Record<string, string[]> = {};
    for (const [label] of this.remotePeers) {
      const peers = this.getRemotePeers(label);
      if (peers.length > 0) out[label] = peers;
    }
    return out;
  }

  /** Returns aggregated remote peer names (`<pc>:<peer>`) for the broker's
   *  `list_peers` reply. Skips siblings with no cache entry. */
  listRemotePeers(): string[] {
    const out: string[] = [];
    for (const [label] of this.remotePeers) {
      for (const peer of this.getRemotePeers(label)) {
        out.push(`${label}:${peer}`);
      }
    }
    return out;
  }

  // ── Push proativo ─────────────────────────────────────────────────────────

  /**
   * Called whenever the local UDS broker's peer set changes
   * (peer_joined/peer_left). We push a `peers_update` envelope to every
   * sibling so their caches stay fresh without polling.
   */
  onLocalPeersChanged(peers: string[]): void {
    this.lastLocalPeers = [...peers];
    if (this.siblingByLabel.size === 0) return;
    const body: PeersUpdateBody = { type: "peers_update", peers: this.lastLocalPeers };
    for (const [, pcPubkey] of this.siblingByLabel) {
      this._sendControlEnvelope(pcPubkey, body);
    }
  }

  // ── RemoteRouter ──────────────────────────────────────────────────────────

  /**
   * Broker hook (plan/25 Wave C). Inspect `env.to` for a `<pc>:` prefix:
   *
   *   - no prefix or prefix == selfPcLabel → return false (broker delivers
   *     locally; if same-self prefix is present we DON'T strip it here —
   *     the local resolver will treat it as a literal name, which works
   *     because local names don't carry colons in practice)
   *   - prefix === known sibling label → rewrite `env.from`, pack onto the
   *     relay, return true. May trigger a lazy `peers_request` when the
   *     cache is empty (returns false on hard cache miss so the broker
   *     surfaces a transport_error path; we always optimistically send,
   *     and ACK timeout in the sender ends up reporting the failure).
   *   - prefix is not a known sibling label → return false (backward-compat
   *     for hypothetical local names containing `:`)
   */
  tryRouteOutbound(env: Envelope): boolean {
    if (this.detached) return false;
    if (typeof env.to !== "string") return false;
    const parsed = parseAddress(env.to);
    if (!parsed) return false;
    const { pcLabel } = parsed;
    if (pcLabel === this.selfPcLabel) return false;  // same-PC: local handles
    const siblingPk = this.siblingByLabel.get(pcLabel);
    if (!siblingPk) return false;  // unknown prefix → fall through

    // We have a destination PC. Rewrite `from` with our own pc_label.
    const rewritten: Envelope = {
      ...env,
      from: `${this.selfPcLabel}:${env.from}`,
    };

    // Optimistic send. If the recipient's cache doesn't list our target
    // yet, the recipient's wrapper still injects (the broker just decides
    // received/busy/denied on actual local UDS state). A simultaneous
    // `peers_request` warms the cache for next time.
    this.pi.sendEnvelopeToPi(siblingPk, rewritten);
    if (this.remotePeers.get(pcLabel) === undefined) {
      this._sendControlEnvelope(siblingPk, { type: "peers_request" } satisfies PeersRequestBody);
      void this._awaitPeersFill(pcLabel, PEERS_REQUEST_TIMEOUT_MS);
    }
    return true;
  }

  // ── Inbound ───────────────────────────────────────────────────────────────

  /**
   * Entry point for envelopes the relay forwards to us. Receives the
   * envelope verbatim plus the verified `from_pc` (Pi-pubkey of the
   * sender, authoritative — relay-checked).
   */
  handleIncoming(env: Envelope, fromPc: string): void {
    // ── transport_error from relay ─────────────────────────────────────────
    // The relay synthesises these with `from_pc = "_relay"` and
    // `envelope.from = "_relay"`. Inject locally as a system envelope
    // addressed to the original sender (env.to is the original sender's
    // prefixed address; strip the prefix and deliver via UDS).
    if (fromPc === "_relay") {
      this._propagateTransportError(env);
      return;
    }

    // ── anti-spoof ─────────────────────────────────────────────────────────
    const claimedLabel = this.siblingByPubkey.get(fromPc);
    if (!claimedLabel) {
      this.log(
        `[broker_remote] drop: from_pc ${shortId(fromPc, 12)} not in sibling cache`,
      );
      return;
    }
    if (typeof env.from === "string") {
      const fromPrefix = env.from.split(":", 1)[0];
      if (fromPrefix !== claimedLabel) {
        this.log(
          `[broker_remote] drop: envelope.from "${safeLogString(env.from)}" prefix ` +
          `mismatches sibling label "${safeLogString(claimedLabel)}"`,
        );
        return;
      }
    }

    const body = env.body as { type?: unknown } | null;
    const bodyType = body && typeof body === "object" ? body.type : undefined;

    // ── control: peers_update ──────────────────────────────────────────────
    if (bodyType === "peers_update") {
      const peers = Array.isArray((body as PeersUpdateBody).peers)
        ? (body as PeersUpdateBody).peers.filter((p) => typeof p === "string")
        : [];
      this._setRemoteCache(claimedLabel, fromPc, peers);
      return;
    }

    // ── control: peers_request ─────────────────────────────────────────────
    if (bodyType === "peers_request") {
      // Always query the broker directly for the current peer list. We
      // can't rely on `lastLocalPeers` because that cache is fed by the
      // `peer_joined`/`peer_left` broadcast in index.ts — and the broker
      // never delivers a `peer_joined` to the peer that just joined (see
      // `_broadcastSystem(..., excludeName=assigned)`). In a single-peer
      // mesh, no event ever fires → `lastLocalPeers` stays `[]` →
      // siblings see us as "no peers" → cache populates empty → cross-PC
      // `list_peers` misses us. Querying broker.peerNames() resolves
      // sync (Map keys), so this is essentially free.
      const currentLocal = this.broker.peerNames();
      this._sendControlEnvelope(fromPc, {
        type: "peers_update",
        peers: currentLocal,
      });
      return;
    }

    // ── control: ack ───────────────────────────────────────────────────────
    // ACK envelopes from a remote wrapper are addressed to our local
    // sender. Strip prefix from `to` and inject so the sender's
    // `sendWithAck` pending resolves. ACK envelopes carry `re` (always)
    // and bypass busy via the `isReply` rule in `injectFromRemote`.
    // (No special-casing needed — generic injection below covers them.)

    // ── regular envelope: strip `to` prefix and inject ─────────────────────
    if (typeof env.to !== "string") {
      this.log("[broker_remote] drop: cross-PC envelope must be unicast string");
      return;
    }
    const toParsed = parseAddress(env.to);
    let injectedEnv = env;
    if (toParsed && toParsed.pcLabel === this.selfPcLabel) {
      injectedEnv = { ...env, to: toParsed.peerName };
    } else if (toParsed) {
      // `to` carries a third-party prefix — not for us. Drop.
      this.log(
        `[broker_remote] drop: envelope.to "${safeLogString(env.to)}" not addressed to ` +
        `selfPcLabel "${safeLogString(this.selfPcLabel)}"`,
      );
      return;
    }

    const status = this.broker.injectFromRemote(injectedEnv);
    // Only generate an ACK for non-ACK envelopes — otherwise we'd loop
    // ACKing the ACK. Detect by body shape.
    if (bodyType === "ack") return;

    // Forward an ACK envelope back to fromPc. The cross-PC sender's
    // `sendWithAck` correlates by `re = env.id`.
    const ackBody: AckBody = { type: "ack", status, target: injectedEnv.to as string };
    const ackEnv: Envelope = {
      from: `${this.selfPcLabel}:${BROKER_NAME}`,
      to: env.from,
      id: uuidv7(),
      re: env.id,
      body: ackBody,
    };
    this.pi.sendEnvelopeToPi(fromPc, ackEnv);
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  private _setRemoteCache(
    pcLabel: string,
    pcPubkey: string,
    peers: string[],
  ): void {
    this.remotePeers.set(pcLabel, { peers, pcPubkey, ts: Date.now() });
    // Resolve any pending `peers_request` waiters for this label.
    const pending = this.pendingFills.get(pcLabel);
    if (pending) {
      for (const slot of pending) {
        clearTimeout(slot.timer);
        slot.resolve();
      }
      this.pendingFills.delete(pcLabel);
    }
  }

  private _awaitPeersFill(pcLabel: string, timeoutMs: number): Promise<void> {
    return new Promise<void>((resolve) => {
      const slot: PendingFill = {
        resolve,
        timer: setTimeout(() => {
          const set = this.pendingFills.get(pcLabel);
          set?.delete(slot);
          resolve();
        }, timeoutMs),
      };
      const set = this.pendingFills.get(pcLabel) ?? new Set<PendingFill>();
      set.add(slot);
      this.pendingFills.set(pcLabel, set);
    });
  }

  private _propagateTransportError(env: Envelope): void {
    // Strip prefix from to (if any) and deliver to the local sender by
    // injecting the envelope into the broker. Per plan/25 spec the
    // wrapper's `sendWithAck` will see this as a body with
    // `type:"transport_error"` correlated by `re`. The ackPending matcher
    // only resolves for body.type === "ack", so transport_error envelopes
    // fall through to handlers — which is what we want (sender's pending
    // map times out, then handler dispatches inbox notification).
    if (typeof env.to !== "string") return;
    const parsed = parseAddress(env.to);
    const injected: Envelope = parsed && parsed.pcLabel === this.selfPcLabel
      ? { ...env, to: parsed.peerName }
      : env;
    this.broker.injectFromRemote(injected);
  }

  private _sendControlEnvelope(
    toPc: string,
    body: PeersUpdateBody | PeersRequestBody,
  ): void {
    const env: Envelope = envelope(
      `${this.selfPcLabel}:_broker_remote`,
      `${this._labelForPubkey(toPc) ?? "?"}:_broker_remote`,
      body,
      null,
    );
    this.pi.sendEnvelopeToPi(toPc, env);
  }

  private _labelForPubkey(pcPubkey: string): string | undefined {
    return this.siblingByPubkey.get(pcPubkey);
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

/**
 * Parse a `<pc>:<peer>` address. Returns null when the input doesn't
 * carry a `:`. Note: callers are responsible for deciding whether the
 * parsed `pcLabel` is meaningful (i.e., matches selfPcLabel or a known
 * sibling); a non-null return here does NOT imply the address is remote.
 * The broker's prefix routing uses this — local names containing literal
 * `:` continue working as long as no sibling carries the same prefix.
 */
export function parseAddress(
  to: string,
): { pcLabel: string; peerName: string } | null {
  const idx = to.indexOf(":");
  if (idx <= 0 || idx === to.length - 1) return null;
  return { pcLabel: to.slice(0, idx), peerName: to.slice(idx + 1) };
}
