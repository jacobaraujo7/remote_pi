import type { Socket } from "node:net";
import { setTimeout as delay } from "node:timers/promises";
import { type Envelope, envelope, parse, serialize, EnvelopeError } from "./envelope.js";
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
  auditPath?: string;
  /** Per-request default timeout (ms). Override per call if needed. */
  defaultTimeoutMs?: number;
}

const DEFAULT_TIMEOUT_MS = 30_000;
const FAILOVER_RETRY_MS = 100;

export class SessionPeer {
  private readonly opts: SessionPeerOptions;
  /** Name actually assigned by the broker (may differ via #N collision suffix). */
  private assignedName: string;
  private role: "leader" | "follower" = "follower";
  private broker: Broker | null = null;
  private socket: Socket | null = null;
  private buf = "";
  /** Map of in-flight request ids → resolver. */
  private readonly pending = new Map<string, {
    resolve: (env: Envelope) => void;
    reject: (err: Error) => void;
    timer: ReturnType<typeof setTimeout>;
  }>();
  private readonly handlers = new Set<MessageHandler>();
  private readonly reconnectHandlers = new Set<ReconnectHandler>();
  private leftFlag = false;

  constructor(opts: SessionPeerOptions) {
    this.opts = opts;
    this.assignedName = opts.name;
  }

  // ── public API ────────────────────────────────────────────────────────────

  /** Joins or leads the session at `sockPath`. Resolves with the assigned name. */
  async start(): Promise<string> {
    return this._joinOrLead();
  }

  /** Returns the name as assigned by the broker (after collision suffix). */
  name(): string {
    return this.assignedName;
  }

  /** Returns "leader" or "follower" — current role. */
  currentRole(): "leader" | "follower" {
    return this.role;
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
   * Send + await reply. Resolves with the first inbound envelope whose `re`
   * matches the outbound `id`. Rejects on timeout.
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
    sock.on("close", () => this._onSocketClose());
    sock.on("error", () => { /* close will follow */ });
  }

  private _registerOver(sock: Socket): Promise<string> {
    return new Promise<string>((resolve, reject) => {
      // The first inbound line MUST be the register_ack. Buffer-aware.
      const wait = setTimeout(() => reject(new Error("register_ack timeout")), 5_000);
      const onceListener = (raw: unknown) => {
        clearTimeout(wait);
        const ack = raw as { type?: string; name_assigned?: string };
        if (ack && ack.type === "register_ack" && typeof ack.name_assigned === "string") {
          this.assignedName = ack.name_assigned;
          this._preAckListener = null;
          resolve(ack.name_assigned);
        } else {
          reject(new Error(`expected register_ack, got: ${JSON.stringify(raw)}`));
        }
      };
      this._preAckListener = onceListener;
      const req = JSON.stringify({ type: "register", name: this.opts.name }) + "\n";
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

    // Correlate replies first.
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

  private async _onSocketClose(): Promise<void> {
    if (this.leftFlag) return;  // intentional leave
    // Attempt to re-elect once. New leader will bind sockPath; we either
    // become leader ourselves or rejoin as follower.
    await delay(FAILOVER_RETRY_MS);
    if (this.leftFlag) return;
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
    if (this.socket) {
      try { this.socket.destroy(); } catch { /* ignored */ }
      this.socket = null;
    }
    if (this.broker) {
      try { await this.broker.close(); } catch { /* ignored */ }
      this.broker = null;
    }
    for (const slot of this.pending.values()) {
      clearTimeout(slot.timer);
      slot.reject(new Error("peer leaving"));
    }
    this.pending.clear();
  }
}
