import type { Server, Socket } from "node:net";
import { appendPrivateFile } from "../secure_fs.js";
import { EnvelopeError, type Envelope, parse, serialize, uuidv7 } from "./envelope.js";

/**
 * Broker hosted by the session leader. Accepts UDS connections, maintains a
 * `name → connection` map, routes envelopes per the `to` field, and appends
 * each routed message to an `audit.jsonl` log.
 *
 * Auto-suffix on name collision: when a peer registers a name already taken,
 * the broker assigns `<name>#N` and returns it in the register ack.
 *
 * ## ACK protocol (plan/25 Wave 0)
 *
 * For **unicast non-broker** envelopes the broker synchronously emits an ACK
 * envelope back to the sender after deciding delivery:
 *
 *   - target idle  → mark target busy, deliver envelope, ACK `received`
 *   - target busy  → drop envelope, ACK `busy`
 *
 * "Busy" tracking is driven by control envelopes `{type:"turn_state", busy}`
 * the peer wrappers send on `turn_start`/`turn_end`. The broker also flips a
 * peer to busy at the moment it delivers an envelope to it — this is the
 * "received = commitment" rule: delivery itself is the promise the peer will
 * handle the message in its upcoming turn. The wrapper's own turn_end clears
 * it again. Atomicity between busy-check and busy-set is guaranteed by Node's
 * single-threaded event loop — the block in `_route` does no `await` between
 * the two.
 *
 * Broadcast/multicast/broker-addressed envelopes are not ACKed (no single
 * authoritative recipient or no semantic match). The audit log carries the
 * ACK status (`received | busy | dropped | none`) per envelope.
 */
export interface BrokerOptions {
  server: Server;
  auditPath?: string;
  /** Optional callback invoked after each successful route (testing/observability). */
  onRouted?: (env: Envelope, deliveredTo: string[]) => void;
}

/**
 * Hook the broker calls before doing local routing, so cross-PC prefixes
 * (`<pc_label>:<peer_name>`) can be handed off to a remote forwarder
 * without baking transport knowledge into the broker. Wave C (plan/25)
 * wires `broker_remote.ts` here.
 */
export interface RemoteRouter {
  /**
   * Try to claim responsibility for routing this envelope cross-PC.
   * Returns true if claimed (broker MUST NOT also deliver locally). Returns
   * false if the envelope should fall through to local routing — e.g., the
   * prefix matches the local `pc_label`, the prefix is not a known remote
   * label (backward-compat for local names containing `:`), or there's no
   * prefix at all.
   */
  tryRouteOutbound(env: Envelope): boolean;
  /** Aggregated remote peer names (`<pc_label>:<peer_name>`) for the
   *  `list_peers` reply. Returns empty when nothing is known yet. */
  listRemotePeers(): string[];
}

/** Local outcome of a cross-PC envelope injection. broker_remote uses this
 *  to construct the ACK envelope it sends back via the relay. */
export type RemoteInjectStatus = "received" | "busy" | "denied";

interface PeerConn {
  name: string;
  socket: Socket;
  buf: string;
}

const BROKER_NAME = "broker";

type AckStatus = "received" | "busy" | "denied";

interface AckBody {
  type: "ack";
  status: AckStatus;
  target: string;
}

interface RegisterMsg {
  type: "register";
  name: string;
}

interface RegisterAck {
  type: "register_ack";
  name_assigned: string;
}

interface SystemBody {
  type: "peer_joined" | "peer_left" | "list_peers_reply";
  name?: string;
  peers?: string[];
}

export class Broker {
  private readonly peers = new Map<string, PeerConn>();
  /** Peers whose wrapper has signaled they are mid-turn, or to whom the
   *  broker has just delivered an envelope (received = commitment). */
  private readonly busyPeers = new Set<string>();
  private readonly auditPath?: string;
  private readonly onRouted?: BrokerOptions["onRouted"];
  private readonly server: Server;
  /** Plan/25 Wave C: optional handoff for cross-PC routing. Null = local only. */
  private remoteRouter: RemoteRouter | null = null;

  constructor(opts: BrokerOptions) {
    this.server = opts.server;
    this.auditPath = opts.auditPath;
    this.onRouted = opts.onRouted;
    this.server.on("connection", (socket) => this._handleConnection(socket));
  }

  /** Attach (or detach with null) a cross-PC router. Idempotent. */
  setRemoteRouter(router: RemoteRouter | null): void {
    this.remoteRouter = router;
  }

  /**
   * Plan/25 Wave C entry point: deliver an envelope that arrived from a
   * remote PC (via relay forward) into the local UDS mesh. Skips the
   * `force from = conn.name` rule (that defense is anti-spoof for local
   * peers; cross-PC has its own defense via the relay's verified `from_pc`).
   *
   * Returns the ACK status so the caller (broker_remote) can pack and
   * forward an ACK envelope back across the relay:
   *   - `received` — target was idle (or `env.re != null`, see Wave 0
   *     bypass rule), envelope delivered, broker marked target busy if
   *     this is new work
   *   - `busy` — target mid-turn, envelope dropped
   *   - `denied` — no such local peer (or write failed) — caller maps to
   *     transport_error or denied ACK as it sees fit
   */
  injectFromRemote(env: Envelope): RemoteInjectStatus {
    if (typeof env.to !== "string" || env.to === "broadcast" || env.to === BROKER_NAME) {
      // Cross-PC is unicast-only at this protocol layer.
      return "denied";
    }
    const targetName = env.to;
    const peer = this.peers.get(targetName);
    if (!peer) return "denied";

    // Replies (re != null) bypass the busy gate (plan/25 Wave 0 rule —
    // replies resolve pending state, not new LLM turns).
    const isReply = env.re !== null;
    if (!isReply && this.busyPeers.has(targetName)) {
      void this._appendAudit(env, [], "busy", "relay");
      return "busy";
    }

    const line = serialize(env);
    try {
      peer.socket.write(line);
    } catch {
      return "denied";
    }
    if (!isReply) this.busyPeers.add(targetName);
    void this._appendAudit(env, [targetName], "received", "relay");
    this.onRouted?.(env, [targetName]);
    return "received";
  }

  /** Peers currently registered. Snapshot, safe to read. */
  peerNames(): string[] {
    return [...this.peers.keys()];
  }

  async close(): Promise<void> {
    for (const p of this.peers.values()) p.socket.destroy();
    this.peers.clear();
    this.busyPeers.clear();
    await new Promise<void>((resolve) => this.server.close(() => resolve()));
  }

  // ── connection lifecycle ──────────────────────────────────────────────────

  private _handleConnection(socket: Socket): void {
    const conn: PeerConn = { name: "", socket, buf: "" };
    socket.setEncoding("utf8");
    socket.on("data", (chunk: string) => this._onData(conn, chunk));
    socket.on("close", () => this._onClose(conn));
    socket.on("error", () => { /* ignored — close will follow */ });
  }

  private _onData(conn: PeerConn, chunk: string): void {
    conn.buf += chunk;
    let nl: number;
    while ((nl = conn.buf.indexOf("\n")) >= 0) {
      const line = conn.buf.slice(0, nl);
      conn.buf = conn.buf.slice(nl + 1);
      if (!line) continue;
      void this._handleLine(conn, line);
    }
  }

  private async _handleLine(conn: PeerConn, line: string): Promise<void> {
    // Unregistered conn must send a `register` control message first.
    if (!conn.name) {
      this._handleRegister(conn, line);
      return;
    }
    // Already registered — must be a regular envelope.
    let env: Envelope;
    try {
      env = parse(line);
    } catch (e) {
      if (e instanceof EnvelopeError) return;  // malformed; drop silently
      throw e;
    }
    // Force `from` to the registered name (security: peer can't spoof).
    env.from = conn.name;
    await this._route(env);
  }

  private _handleRegister(conn: PeerConn, line: string): void {
    let req: RegisterMsg;
    try {
      const parsed = JSON.parse(line) as unknown;
      if (
        !parsed ||
        typeof parsed !== "object" ||
        (parsed as { type?: unknown }).type !== "register" ||
        typeof (parsed as { name?: unknown }).name !== "string"
      ) {
        conn.socket.destroy();
        return;
      }
      req = parsed as RegisterMsg;
    } catch {
      conn.socket.destroy();
      return;
    }

    const assigned = this._uniqueName(req.name);
    conn.name = assigned;
    this.peers.set(assigned, conn);

    const ack: RegisterAck = { type: "register_ack", name_assigned: assigned };
    try {
      conn.socket.write(JSON.stringify(ack) + "\n");
    } catch { /* peer hung up */ }

    // Notify others (peer_joined broadcast).
    this._broadcastSystem({ type: "peer_joined", name: assigned }, assigned);
  }

  private _uniqueName(requested: string): string {
    if (!this.peers.has(requested)) return requested;
    for (let n = 2; n < 1000; n++) {
      const candidate = `${requested}#${n}`;
      if (!this.peers.has(candidate)) return candidate;
    }
    throw new Error(`name space exhausted for ${requested}`);
  }

  private _onClose(conn: PeerConn): void {
    if (!conn.name) return;
    this.peers.delete(conn.name);
    this.busyPeers.delete(conn.name);
    this._broadcastSystem({ type: "peer_left", name: conn.name }, conn.name);
  }

  // ── routing ───────────────────────────────────────────────────────────────

  private async _route(env: Envelope): Promise<void> {
    // Special handling for messages addressed to the broker itself.
    if (env.to === BROKER_NAME) {
      this._handleBrokerMessage(env);
      return;
    }

    // Plan/25 Wave C: give the cross-PC router a chance to claim this
    // envelope. It returns true when the `to` field carries a known remote
    // prefix and the envelope was packed onto the relay; on miss it falls
    // through so locally-named peers (including ones with literal `:` in
    // their names) still work.
    if (this.remoteRouter && typeof env.to === "string") {
      if (this.remoteRouter.tryRouteOutbound(env)) return;
    }

    const targets = this._resolveTargets(env);
    const delivered: string[] = [];
    const line = serialize(env);
    const isUnicast = typeof env.to === "string" && env.to !== "broadcast";
    // Replies (envelope.re != null) are answers the recipient was already
    // expecting — they resolve pending state at the application layer rather
    // than starting a new LLM turn. Always deliverable; never trigger the
    // busy-on-delivery flip. New work (re == null) keeps the original
    // "received = commitment" semantics.
    const isReply = env.re !== null;

    // Synchronous block — Node's single-threaded loop gives atomicity between
    // busy-check and busy-mark (no await between them). Multiple deliveries in
    // the same `for` iteration may interleave with another peer's writes only
    // at await points; the busy-set transition itself is atomic.
    let ackStatus: AckStatus | "none" = "none";
    for (const targetName of targets) {
      const peer = this.peers.get(targetName);
      if (!peer) continue;  // unknown peer: silent drop (sender times out)

      if (isUnicast && !isReply && this.busyPeers.has(targetName)) {
        // New work for a busy peer → drop + ACK busy. Audit logged below
        // captures the rejection via `ackStatus = "busy"` + delivered=[].
        ackStatus = "busy";
        this._sendAckToSender(env, "busy", targetName);
        continue;
      }

      try {
        peer.socket.write(line);
        delivered.push(targetName);
        if (isUnicast) {
          if (!isReply) {
            // "received = commitment" for new work: peer now owns this
            // envelope and will process it in its upcoming turn. Wrapper's
            // turn_end clears the busy flag.
            this.busyPeers.add(targetName);
          }
          ackStatus = "received";
          this._sendAckToSender(env, "received", targetName);
        }
      } catch {
        // peer dropped mid-write — close handler will fire; treat as silent
      }
    }

    if (this.auditPath) await this._appendAudit(env, delivered, ackStatus);
    this.onRouted?.(env, delivered);
  }

  private _resolveTargets(env: Envelope): string[] {
    if (env.to === "broadcast") {
      return this.peerNames().filter((n) => n !== env.from);
    }
    if (Array.isArray(env.to)) {
      return env.to.filter((n) => n !== env.from);
    }
    // Unicast: drop self-loops too. The skill warns "useless" but the LLM
    // might still try (especially with deceiving `re` reply chains). A
    // self-loop has no upside and risks unbounded message ↔ inject ↔ message
    // cycles when the inbound injector tells the LLM "reply with re=…".
    if (env.to === env.from) return [];
    return [env.to];
  }

  /**
   * Writes an ACK envelope to the original sender's socket. Synchronous —
   * the caller is inside `_route` and must keep busy-check/busy-set atomic.
   * Broker → sender: `from="broker"`, `to=env.from`, `re=env.id`,
   * `body={type:"ack", status, target}`.
   */
  private _sendAckToSender(env: Envelope, status: AckStatus, target: string): void {
    const sender = this.peers.get(env.from);
    if (!sender) return;  // sender vanished mid-write
    const body: AckBody = { type: "ack", status, target };
    const ackEnv: Envelope = {
      from: BROKER_NAME,
      to: env.from,
      id: uuidv7(),
      re: env.id,
      body,
    };
    try {
      sender.socket.write(serialize(ackEnv));
    } catch { /* sender dropped; close handler will fire */ }
  }

  private _handleBrokerMessage(env: Envelope): void {
    const body = env.body as { type?: string; busy?: unknown; peers?: unknown } | null;
    if (!body || typeof body !== "object") return;
    if (body.type === "list_peers") {
      const remote = this.remoteRouter ? this.remoteRouter.listRemotePeers() : [];
      const peers = [...this.peerNames(), ...remote];
      const reply: Envelope = {
        from: BROKER_NAME,
        to: env.from,
        id: uuidv7(),
        re: env.id,
        body: { type: "list_peers_reply", peers } as SystemBody,
      };
      const peer = this.peers.get(env.from);
      if (peer) {
        try { peer.socket.write(serialize(reply)); } catch { /* ignored */ }
      }
      return;
    }
    if (body.type === "turn_state" && typeof body.busy === "boolean") {
      // Peer wrapper notifies its own turn lifecycle. We use `env.from`
      // (forced to conn.name by `_handleLine`) so a peer can never set
      // someone else's busy state.
      if (body.busy) this.busyPeers.add(env.from);
      else this.busyPeers.delete(env.from);
      return;
    }
  }

  private _broadcastSystem(body: SystemBody, excludeName: string): void {
    for (const [name, peer] of this.peers) {
      if (name === excludeName) continue;
      const env: Envelope = {
        from: BROKER_NAME,
        to: name,
        id: uuidv7(),
        re: null,
        body,
      };
      try {
        peer.socket.write(serialize(env));
      } catch { /* ignored */ }
    }
  }

  private async _appendAudit(
    env: Envelope,
    delivered: string[],
    ackStatus: AckStatus | "none",
    /**
     * Plan/25 Wave D: provenance hint for the audit reader. `"relay"` marks
     * envelopes injected via `injectFromRemote` (cross-PC). Local UDS
     * delivery keeps the default `"uds"` so existing audit consumers see
     * a uniform field rather than an undefined hole.
     */
    via: "uds" | "relay" = "uds",
  ): Promise<void> {
    if (!this.auditPath) return;
    const line = JSON.stringify({
      ts: Date.now(),
      from: env.from,
      to: env.to,
      id: env.id,
      re: env.re,
      delivered,
      ack_status: ackStatus,
      via,
    }) + "\n";
    try {
      await appendPrivateFile(this.auditPath, line);
    } catch { /* audit best-effort */ }
  }
}
