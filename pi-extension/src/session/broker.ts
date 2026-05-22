import type { Server, Socket } from "node:net";
import { appendFile, mkdir } from "node:fs/promises";
import { dirname } from "node:path";
import { type Envelope, parse, serialize, uuidv7, EnvelopeError } from "./envelope.js";

/**
 * Broker hosted by the session leader. Accepts UDS connections, maintains a
 * `name → connection` map, routes envelopes per the `to` field, and appends
 * each routed message to an `audit.jsonl` log.
 *
 * Auto-suffix on name collision: when a peer registers a name already taken,
 * the broker assigns `<name>#N` and returns it in the register ack.
 */
export interface BrokerOptions {
  server: Server;
  auditPath?: string;
  /** Optional callback invoked after each successful route (testing/observability). */
  onRouted?: (env: Envelope, deliveredTo: string[]) => void;
}

interface PeerConn {
  name: string;
  socket: Socket;
  buf: string;
}

const BROKER_NAME = "broker";

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
  private readonly auditPath?: string;
  private readonly onRouted?: BrokerOptions["onRouted"];
  private readonly server: Server;

  constructor(opts: BrokerOptions) {
    this.server = opts.server;
    this.auditPath = opts.auditPath;
    this.onRouted = opts.onRouted;
    this.server.on("connection", (socket) => this._handleConnection(socket));
  }

  /** Peers currently registered. Snapshot, safe to read. */
  peerNames(): string[] {
    return [...this.peers.keys()];
  }

  async close(): Promise<void> {
    for (const p of this.peers.values()) p.socket.destroy();
    this.peers.clear();
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
    this._broadcastSystem({ type: "peer_left", name: conn.name }, conn.name);
  }

  // ── routing ───────────────────────────────────────────────────────────────

  private async _route(env: Envelope): Promise<void> {
    // Special handling for messages addressed to the broker itself.
    if (env.to === BROKER_NAME) {
      this._handleBrokerMessage(env);
      return;
    }

    const targets = this._resolveTargets(env);
    const delivered: string[] = [];
    const line = serialize(env);

    for (const targetName of targets) {
      const peer = this.peers.get(targetName);
      if (!peer) continue;
      try {
        peer.socket.write(line);
        delivered.push(targetName);
      } catch {
        // peer dropped mid-write — close handler will fire
      }
    }

    if (this.auditPath) await this._appendAudit(env, delivered);
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

  private _handleBrokerMessage(env: Envelope): void {
    const body = env.body as { type?: string } | null;
    if (!body || typeof body !== "object") return;
    if (body.type === "list_peers") {
      const reply: Envelope = {
        from: BROKER_NAME,
        to: env.from,
        id: uuidv7(),
        re: env.id,
        body: { type: "list_peers_reply", peers: this.peerNames() } as SystemBody,
      };
      const peer = this.peers.get(env.from);
      if (peer) {
        try { peer.socket.write(serialize(reply)); } catch { /* ignored */ }
      }
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

  private async _appendAudit(env: Envelope, delivered: string[]): Promise<void> {
    if (!this.auditPath) return;
    const line = JSON.stringify({
      ts: Date.now(),
      from: env.from,
      to: env.to,
      id: env.id,
      re: env.re,
      delivered,
    }) + "\n";
    try {
      await mkdir(dirname(this.auditPath), { recursive: true });
      await appendFile(this.auditPath, line, "utf8");
    } catch { /* audit best-effort */ }
  }
}
