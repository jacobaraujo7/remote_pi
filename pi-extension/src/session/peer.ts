import type { Socket } from "node:net";
import { setTimeout as delay } from "node:timers/promises";
import {
  type Envelope,
  type TransportErrorReason,
  asTransportErrorBody,
  envelope,
  hasTransportErrorType,
  parse,
  serialize,
  EnvelopeError,
} from "./envelope.js";
import { joinOrLead, type ElectionResult } from "./leader_election.js";
import { Broker } from "./broker.js";

/**
 * Symmetric peer-in-session API. Hides whether you are leader or follower;
 * `send`, `request`, `onMessage`, `rename`, `leave` all work the same.
 *
 * Pending map demuxes parallel `request()` calls by message `id` → `re`.
 *
 * Failover: when the leader dies, follower socket emits `close`. Remaining
 * peers re-run `joinOrLead`. One becomes the new leader; others reconnect.
 */
export type MessageHandler = (env: Envelope) => void;
export type ReconnectHandler = () => void;

export interface SessionPeerOptions {
  sockPath: string;
  name: string;
  /**
   * Working directory of this agent. Sent in the `register` so the broker can
   * key peers by the (cwd, name) pair: two agents in the SAME folder with the
   * same name are the SAME logical agent reincarnating (switch_session /
   * restart), so the broker take-over the name instead of suffixing `#N`.
   * Optional for backward-compat with peers that predate this field.
   */
  cwd?: string;
  /** Replace an existing same-(cwd,name) registration instead of accepting a
   *  broker-assigned `#N`. Use only for stable logical identities; ordinary
   *  multi-agent sessions should leave this false. */
  takeoverExisting?: boolean;
  auditPath?: string;
  /** Per-request default timeout (ms). Override per call if needed. */
  defaultTimeoutMs?: number;
}

const DEFAULT_TIMEOUT_MS = 30_000;
const ACK_TIMEOUT_MS = 5_000;
const FAILOVER_RETRY_MS = 100;

export type AckStatus = "received" | "busy" | "denied" | "timeout";

export interface AckResult {
  status: AckStatus;
  /** The original envelope id that was awaiting ACK. */
  id: string;
  /** Target name reported by broker (when ACK arrived). Undefined on timeout. */
  target?: string;
  error?: `transport_error: ${TransportErrorReason}`;
  reason?: TransportErrorReason;
}

export class MeshTransportError extends Error {
  constructor(
    readonly reason: TransportErrorReason,
    readonly correlationId: string,
  ) {
    super(`transport_error: ${reason}`);
    this.name = "MeshTransportError";
  }
}

interface AckBody {
  type: "ack";
  status: "received" | "busy" | "denied";
  target: string;
}

function hasExactAckType(body: unknown): body is { type: "ack" } {
  return typeof body === "object"
    && body !== null
    && Object.prototype.hasOwnProperty.call(body, "type")
    && (body as { type: unknown }).type === "ack";
}

function expectedAckSender(destination: string): string {
  // Local absolute paths may contain colons; only non-path aliases are remote.
  if (
    destination === "" ||
    !destination.includes(":") ||
    destination.startsWith("/") ||
    /^[A-Za-z]:[\\/]/.test(destination) ||
    destination.startsWith("\\\\")
  ) {
    return "broker";
  }
  const remote = /^([^:]+):.+$/.exec(destination);
  return remote ? `${remote[1]}:broker` : "broker";
}

function asAckBody(body: unknown): AckBody | null {
  if (!hasExactAckType(body)
    || !Object.prototype.hasOwnProperty.call(body, "status")
    || !Object.prototype.hasOwnProperty.call(body, "target")) {
    return null;
  }

  const { status, target } = body as {
    type: "ack";
    status: unknown;
    target: unknown;
  };
  if ((status !== "received" && status !== "busy" && status !== "denied")
    || typeof target !== "string") {
    return null;
  }

  return { type: "ack", status, target };
}

export class SessionPeer {
  private readonly opts: SessionPeerOptions;
  /** Clean leaf name actually assigned by the broker (may carry a `#N`
   *  collision suffix). Used for display + self-filtering. */
  private assignedName: string;
  /** Canonical address assigned by the broker (`[<pc>:]<cwd>@<nome>`, or just
   *  the name for a legacy broker). This is the routing/identity key the mesh
   *  uses; callers ECHO it, never compose it. */
  private assignedAddress: string;
  private role: "leader" | "follower" = "follower";
  private broker: Broker | null = null;
  private socket: Socket | null = null;
  private buf = "";
  /** Map of in-flight request ids → resolver. Used by `request()`. */
  private readonly pending = new Map<string, {
    resolve: (env: Envelope) => void;
    reject: (err: Error) => void;
    timer: ReturnType<typeof setTimeout>;
  }>();
  /** Map of in-flight send ids → ACK resolver. Used by `sendWithAck()`. */
  private readonly ackPending = new Map<string, {
    expectedFrom: string;
    resolve: (result: AckResult) => void;
    timer: ReturnType<typeof setTimeout>;
  }>();
  private readonly handlers = new Set<MessageHandler>();
  private readonly reconnectHandlers = new Set<ReconnectHandler>();
  private leftFlag = false;

  constructor(opts: SessionPeerOptions) {
    this.opts = opts;
    this.assignedName = opts.name;
    this.assignedAddress = opts.name;
  }

  // ── public API ────────────────────────────────────────────────────────────

  /** Joins or leads the session at `sockPath`. Resolves with the assigned name. */
  async start(): Promise<string> {
    return this._joinOrLead();
  }

  /** Returns the clean leaf name as assigned by the broker (after any `#N`). */
  name(): string {
    return this.assignedName;
  }

  /** Returns the canonical address (`[<pc>:]<cwd>@<nome>`) assigned by the
   *  broker — the key the mesh routes on. Equals `name()` against a legacy
   *  broker that returns no address. */
  address(): string {
    return this.assignedAddress;
  }

  /** Returns "leader" or "follower" — current role. */
  currentRole(): "leader" | "follower" {
    return this.role;
  }

  /** Returns the locally-hosted Broker when this peer is the leader, or
   *  null when it's a follower. Wave 25C uses this to attach the
   *  cross-PC router. */
  localBroker(): Broker | null {
    return this.broker;
  }

  /**
   * Fire-and-forget send. Doesn't await a reply.
   *
   * `re` (optional) lets the caller correlate this message as a reply to a
   * previous request — when an LLM peer is *answering* a question from
   * another agent, it must echo the original `id` here so the requester's
   * pending map can resolve. Without `re`, the requester treats this as a
   * new unsolicited message and its `request()` call times out.
   */
  async send(
    to: string | string[],
    body: unknown,
    re: string | null = null,
  ): Promise<void> {
    const env = envelope(this.assignedName, to, body, re);
    await this._writeEnvelope(env);
  }

  /**
   * Unicast send + await broker ACK. Returns the ACK status:
   *   - `received` — peer was idle, envelope delivered, will be processed soon
   *   - `busy`     — peer mid-turn, envelope dropped; sender is owner of retry
   *   - `denied`   — broker/Relay refused delivery (including authorization or envelope failure)
   *   - `timeout`  — no ACK within `timeoutMs`, or trusted Relay says offline
   *
   * Only meaningful for unicast non-broadcast addresses. The peer's body-level
   * reply (if any) is asynchronous and arrives as a normal inbound envelope
   * carrying `re=<this-send-id>` in a future turn — handled by `onMessage`.
   */
  async sendWithAck(
    to: string,
    body: unknown,
    re: string | null = null,
    timeoutMs: number = ACK_TIMEOUT_MS,
  ): Promise<AckResult> {
    const env = envelope(this.assignedName, to, body, re);
    return new Promise<AckResult>((resolve) => {
      const timer = setTimeout(() => {
        this.ackPending.delete(env.id);
        resolve({ status: "timeout", id: env.id });
      }, timeoutMs);
      this.ackPending.set(env.id, {
        expectedFrom: expectedAckSender(to),
        resolve,
        timer,
      });
      this._writeEnvelope(env).catch(() => {
        const slot = this.ackPending.get(env.id);
        if (!slot) return;
        clearTimeout(slot.timer);
        this.ackPending.delete(env.id);
        resolve({ status: "timeout", id: env.id });
      });
    });
  }

  /**
   * Send + await reply. Resolves with the first inbound envelope whose `re`
   * matches the outbound `id`. Rejects on timeout, teardown/write failure, or
   * a trusted Relay transport error.
   */
  async request(
    to: string,
    body: unknown,
    timeoutMs: number = this.opts.defaultTimeoutMs ?? DEFAULT_TIMEOUT_MS,
  ): Promise<Envelope> {
    const env = envelope(this.assignedName, to, body, null);
    return new Promise<Envelope>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(env.id);
        reject(new Error(`request to ${to} timed out after ${timeoutMs}ms`));
      }, timeoutMs);
      this.pending.set(env.id, { resolve, reject, timer });
      this._writeEnvelope(env).catch((err) => {
        const slot = this.pending.get(env.id);
        if (!slot) return;
        clearTimeout(slot.timer);
        this.pending.delete(env.id);
        reject(err);
      });
    });
  }

  onMessage(handler: MessageHandler): () => void {
    this.handlers.add(handler);
    return () => this.handlers.delete(handler);
  }

  /**
   * Fires after the peer successfully (re)joins following a failover —
   * leader died and we re-elected. NOT called for the initial `start()`,
   * only for post-drop reconnects. Consumers use this to re-query state
   * the broker may have lost in the transition (e.g., peer list).
   */
  onReconnect(handler: ReconnectHandler): () => void {
    this.reconnectHandlers.add(handler);
    return () => this.reconnectHandlers.delete(handler);
  }

  /**
   * Requests a different display name from the broker. Returns the name
   * actually assigned (may carry a #N suffix on collision). Implemented as
   * a soft rejoin: leaves & rejoins with the new name.
   */
  async rename(newName: string): Promise<string> {
    await this._teardownConn();
    this.opts.name = newName;
    this.assignedName = newName;
    return this._joinOrLead();
  }

  async leave(): Promise<void> {
    this.leftFlag = true;
    await this._teardownConn();
  }

  // ── join / failover loop ──────────────────────────────────────────────────

  private async _joinOrLead(): Promise<string> {
    const result: ElectionResult = await joinOrLead(this.opts.sockPath);
    if (result.role === "leader") {
      this.role = "leader";
      this.broker = new Broker({
        server: result.server,
        auditPath: this.opts.auditPath,
      });
      // Leader also registers itself as a peer so other followers see it +
      // can address it. We create a self-loopback socket via the broker's
      // internal API: easiest is to open a real client connection back to
      // our own server.
      return this._registerAsClient();
    } else {
      this.role = "follower";
      this._wireSocket(result.socket);
      return this._registerOver(result.socket);
    }
  }

  private async _registerAsClient(): Promise<string> {
    const { createConnection } = await import("node:net");
    const sock = createConnection(this.opts.sockPath);
    await new Promise<void>((resolve, reject) => {
      sock.once("connect", () => resolve());
      sock.once("error", reject);
    });
    this._wireSocket(sock);
    return this._registerOver(sock);
  }

  private _wireSocket(sock: Socket): void {
    this.socket = sock;
    this.buf = "";
    sock.setEncoding("utf8");
    sock.on("data", (chunk: string) => this._onData(chunk));
    sock.on("close", () => this._onSocketClose(sock));
    sock.on("error", () => { /* close will follow */ });
  }

  private _registerOver(sock: Socket): Promise<string> {
    return new Promise<string>((resolve, reject) => {
      // The first inbound line MUST be the register_ack. Buffer-aware.
      const wait = setTimeout(() => reject(new Error("register_ack timeout")), 5_000);
      const onceListener = (raw: unknown) => {
        clearTimeout(wait);
        // plan/38: a new broker returns `address_assigned` (canonical key) +
        // `name_assigned` (clean leaf). Read both with cross-fallback so we work
        // against either a new broker OR a legacy one (only `name_assigned`,
        // where address == name).
        const ack = raw as { type?: string; name_assigned?: string; address_assigned?: string };
        const name = typeof ack?.name_assigned === "string" ? ack.name_assigned : ack?.address_assigned;
        const address = typeof ack?.address_assigned === "string" ? ack.address_assigned : ack?.name_assigned;
        if (ack && ack.type === "register_ack" && typeof name === "string" && typeof address === "string") {
          this.assignedName = name;
          this.assignedAddress = address;
          this._preAckListener = null;
          resolve(name);
        } else {
          reject(new Error(`expected register_ack, got: ${JSON.stringify(raw)}`));
        }
      };
      this._preAckListener = onceListener;
      const req = JSON.stringify({
        type: "register",
        name: this.opts.name,
        // Only include cwd when set — keeps the wire identical to the legacy
        // payload for callers that don't supply it (broker treats absent cwd
        // as "no take-over", i.e. the old #N behavior).
        ...(this.opts.cwd !== undefined ? { cwd: this.opts.cwd } : {}),
        ...(this.opts.takeoverExisting === true ? { takeover: true } : {}),
      }) + "\n";
      try {
        sock.write(req);
      } catch (e) {
        clearTimeout(wait);
        reject(e as Error);
      }
    });
  }

  private _preAckListener: ((raw: unknown) => void) | null = null;

  private _onData(chunk: string): void {
    this.buf += chunk;
    let nl: number;
    while ((nl = this.buf.indexOf("\n")) >= 0) {
      const line = this.buf.slice(0, nl);
      this.buf = this.buf.slice(nl + 1);
      if (!line) continue;
      this._handleLine(line);
    }
  }

  private _handleLine(line: string): void {
    // Before register_ack: parse loosely as an ack control message.
    if (this._preAckListener) {
      try {
        const parsed = JSON.parse(line) as unknown;
        this._preAckListener(parsed);
      } catch {
        // Garbage during register window — ignore.
      }
      return;
    }

    // Regular envelope.
    let env: Envelope;
    try {
      env = parse(line);
    } catch (e) {
      if (e instanceof EnvelopeError) return;
      throw e;
    }

    // Reserve every raw transport_error body before either pending map can
    // correlate it. Only exact broker provenance plus a valid body may settle;
    // forged or invalid reserved frames remain ordinary handler messages.
    if (hasTransportErrorType(env.body)) {
      const trusted = env.from === "broker" && env.re !== null
        ? asTransportErrorBody(env.body)
        : null;
      if (trusted && env.re !== null) {
        this._consumeAckTransportError(env.re, trusted.reason);
        this._rejectRequestTransportError(env.re, trusted.reason);
        return;
      }
      this._dispatchToHandlers(env);
      return;
    }

    // Reserve exact broker ACKs before generic correlation or handler dispatch.
    // The sender is bound when the send begins: local sends accept only
    // `broker`, while remote alias sends accept only `<alias>:broker`.
    const fromBroker = env.from === "broker" || env.from.endsWith(":broker");
    if (fromBroker && hasExactAckType(env.body)) {
      const ackBody = asAckBody(env.body);
      if (env.re !== null && ackBody) {
        const slot = this.ackPending.get(env.re);
        if (slot && slot.expectedFrom === env.from) {
          clearTimeout(slot.timer);
          this.ackPending.delete(env.re);
          slot.resolve({ status: ackBody.status, id: env.re, target: ackBody.target });
        }
      }
      return;
    }

    // Correlate replies for `request()`.
    if (env.re) {
      const slot = this.pending.get(env.re);
      if (slot) {
        clearTimeout(slot.timer);
        this.pending.delete(env.re);
        slot.resolve(env);
        return;
      }
    }

    // Otherwise dispatch to subscribers.
    this._dispatchToHandlers(env);
  }

  private _consumeAckTransportError(
    correlationId: string,
    reason: TransportErrorReason,
  ): void {
    const pendingId = correlationId.toLowerCase();
    const slot = this.ackPending.get(pendingId);
    if (!slot) return;
    clearTimeout(slot.timer);
    this.ackPending.delete(pendingId);
    slot.resolve({
      status: reason === "offline" ? "timeout" : "denied",
      id: pendingId,
      error: `transport_error: ${reason}`,
      reason,
    });
  }

  private _rejectRequestTransportError(
    correlationId: string,
    reason: TransportErrorReason,
  ): void {
    const pendingId = correlationId.toLowerCase();
    const slot = this.pending.get(pendingId);
    if (!slot) return;
    clearTimeout(slot.timer);
    this.pending.delete(pendingId);
    slot.reject(new MeshTransportError(reason, pendingId));
  }

  private _dispatchToHandlers(env: Envelope): void {
    for (const h of this.handlers) {
      try { h(env); } catch { /* handler errors don't break peer */ }
    }
  }

  private async _writeEnvelope(env: Envelope): Promise<void> {
    if (!this.socket || this.socket.destroyed) {
      throw new Error("session peer not connected");
    }
    this.socket.write(serialize(env));
  }

  private async _onSocketClose(closedSock: Socket): Promise<void> {
    if (this.leftFlag) return;  // intentional leave
    // Only the CURRENT socket dying is a real failover. A close from a socket
    // we've already replaced — `rename()` (teardown + rejoin) or a prior
    // reconnect — must NOT trigger another `_joinOrLead`, or we'd double-
    // register (the broker suffixes the second as `#N`) and leave an orphaned
    // still-open socket as a ghost peer. `this.socket` is null mid-rename
    // (teardown done, rejoin in flight) or already the new socket — either way
    // `!== closedSock`, so we skip. Genuine leader death: `this.socket` is still
    // the (now-closed) follower socket → identity matches → we re-elect.
    if (this.socket !== closedSock) return;
    // Attempt to re-elect once. New leader will bind sockPath; we either
    // become leader ourselves or rejoin as follower.
    await delay(FAILOVER_RETRY_MS);
    if (this.leftFlag || this.socket !== closedSock) return;
    try {
      await this._joinOrLead();
      // The new broker's peers map starts fresh — consumers must re-query
      // any cached state (peer count, etc.) that depended on the old broker.
      for (const h of this.reconnectHandlers) {
        try { h(); } catch { /* handler errors don't break peer */ }
      }
    } catch { /* election failed; peer stuck in disconnected state */ }
  }

  private async _teardownConn(): Promise<void> {
    for (const [id, slot] of this.pending) {
      clearTimeout(slot.timer);
      this.pending.delete(id);
      slot.reject(new Error("peer leaving"));
    }
    for (const [id, slot] of this.ackPending) {
      clearTimeout(slot.timer);
      this.ackPending.delete(id);
      slot.resolve({ status: "timeout", id });
    }

    if (this.socket) {
      try { this.socket.destroy(); } catch { /* ignored */ }
      this.socket = null;
    }
    if (this.broker) {
      try { await this.broker.close(); } catch { /* ignored */ }
      this.broker = null;
    }
  }
}
