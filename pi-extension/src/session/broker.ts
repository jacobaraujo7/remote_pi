import type { Server, Socket } from "node:net";
import { appendFile, mkdir } from "node:fs/promises";
import { dirname, posix, win32 } from "node:path";
import { type Envelope, parse, serialize, uuidv7, EnvelopeError } from "./envelope.js";
import { sanitizeSegment } from "./local_config.js";
import {
  isBoundedPeerInfo,
  MAX_CWD_LENGTH,
  MAX_PEERS_UPDATE_ENTRIES,
} from "./peer_limits.js";

/**
 * Structured view of one mesh peer (plan/38). The `address` is the canonical
 * routing key; the other fields let a client group/label peers WITHOUT parsing
 * the address string. `pc` is undefined for local peers (filled cross-PC in
 * Fase 2). Returned by `list_peers` as `peers_detailed`.
 */
export interface PeerInfo {
  /** Cross-PC label; undefined for a local peer. */
  pc?: string;
  /** Working directory (realpath). Empty string for a legacy peer (no cwd). */
  cwd: string;
  /** Clean leaf name (carries a `#N` only on a same-(cwd,name) collision). */
  name: string;
  /** Canonical address — the broker's Map key and the `to`/`from` on the wire. */
  address: string;
}

/**
 * THE sole encoder of a peer address (plan/38): `[<pc>:]<cwd>@<nome>`.
 *
 * - `cwd` present → `<cwd>@<nome>` (the `@` separates name from path so a `/`
 *   in the path never confuses lookup, which is exact-match anyway).
 * - `cwd` empty (legacy peer that sent no cwd) → `address == name`, preserving
 *   pre-plan/38 behavior so a mixed mesh keeps routing.
 * - `pc` present (cross-PC, Fase 2) → prefixed `<pc>:`.
 *
 * Does NOT sanitize — callers sanitize the `name` once (see `sanitizeMeshName`)
 * before composing, so an already-appended `#N` collision suffix survives.
 * Everyone else ECHOES `peer.address` verbatim; only the broker composes.
 */
export function composeAddress(parts: { pc?: string; cwd: string; name: string }): string {
  const base = parts.cwd ? `${parts.cwd}@${parts.name}` : parts.name;
  return parts.pc ? `${parts.pc}:${base}` : base;
}

/**
 * Sanitize a requested mesh name to a safe leaf while PRESERVING a trailing
 * `#N` collision suffix (which the cwd-lock or a prior assignment may have
 * added — `sanitizeSegment` alone would mangle `#`→`-`). The base is run through
 * `sanitizeSegment` (af66d04); an unusable base (empty / reserved keyword) falls
 * back to `"agent"`.
 */
export function sanitizeMeshName(raw: string): string {
  const m = /^(.*?)(#\d+)?$/.exec(raw);
  const base = sanitizeSegment(m?.[1] ?? raw) ?? "agent";
  return m?.[2] ? base + m[2] : base;
}

/**
 * Broker hosted by the session leader. Accepts UDS connections, maintains a
 * `name → connection` map, routes envelopes per the `to` field, and appends
 * each routed message to an `audit.jsonl` log.
 *
 * Auto-suffix on name collision: when a peer registers a name already taken,
 * the broker assigns `<name>#N` and returns it in the register ack.
 *
 * ## ACK protocol (plan/25 Wave 0; reliable delivery per plan/34)
 *
 * For **unicast non-broker** envelopes the broker synchronously emits an ACK
 * envelope back to the sender once it has delivered:
 *
 *   - target online → deliver envelope, ACK `received`
 *   - no such peer  → silent drop (sender times out)
 *
 * plan/34 removed the busy-drop: a message that arrives while the target is
 * mid-turn is **always delivered**, never dropped. The Pi harness
 * (`sendMessage(triggerTurn:true)`) enqueues mid-turn messages and processes
 * them in the upcoming turn, so the broker needs no busy gate or mailbox.
 * Consequently `busy` is no longer a possible ACK status for unicast new
 * work — the sender always gets `received`. (Turn-lifecycle / working
 * indicators live in `index.ts` via room_meta over the relay, not here.)
 *
 * Broadcast/multicast/broker-addressed envelopes are not ACKed (no single
 * authoritative recipient or no semantic match). The audit log carries the
 * ACK status (`received | denied | none`) per envelope.
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
  /** Aggregated remote peer addresses (`<pc_label>:<cwd>@<nome>`) for the
   *  `list_peers` reply's `peers` (string) field. Empty when nothing known. */
  listRemotePeers(): string[];
  /** Structured remote roster (plan/38 Fase 2): one `PeerInfo` per cross-PC
   *  peer with `pc` filled (the sibling label), `cwd`/`name` from the sibling's
   *  inventory, and `address` prefixed `<pc>:<cwd>@<nome>`. Powers the
   *  `peers_detailed` half of `list_peers` so clients group by `pc`/`cwd`
   *  without parsing. Empty when nothing known. */
  listRemotePeerInfos(): PeerInfo[];
}

export interface ConditionalRemoteRouterHost {
  clearRemoteRouter(expected: RemoteRouter): void;
}

/** Local outcome of a cross-PC envelope injection. broker_remote uses this
 *  to construct the ACK envelope it sends back via the relay. plan/34: `busy`
 *  is gone — injection always delivers when the peer exists. */
export type RemoteInjectStatus = "received" | "denied";

interface PeerConn {
  /** Clean leaf name (may carry a `#N` on a same-(cwd,name) collision). */
  name: string;
  /** Working directory the peer registered with — the second half of the
   *  (cwd, name) identity. Empty string for legacy peers that sent no cwd. */
  cwd: string;
  /** Canonical address `composeAddress({cwd, name})` — this conn's Map key and
   *  the value forced onto `env.from`. Empty until registered. */
  address: string;
  socket: Socket;
  buf: string;
}

const BROKER_NAME = "broker";

/** Host-independent Windows drive absolute-path check. */
function isWindowsDriveAbsolutePath(value: string): boolean {
  return /^[A-Za-z]:[\\/]/.test(value);
}

/** Accept legacy empty cwd plus bounded syntactically absolute paths only. */
function isValidRegisteredCwd(value: string): boolean {
  if (value === "") return true;
  if (
    value.length > MAX_CWD_LENGTH ||
    /[\0\r\n]/.test(value)
  ) {
    return false;
  }
  return posix.isAbsolute(value) ||
    isWindowsDriveAbsolutePath(value) ||
    (win32.isAbsolute(value) && /^[/\\]{2}/.test(value));
}

type AckStatus = "received" | "denied";

interface AckBody {
  type: "ack";
  status: "received" | "denied";
  target: string;
}

interface RegisterMsg {
  type: "register";
  name: string;
  /** Optional working directory — enables (cwd,name) take-over (see
   *  `_handleRegister`). Absent → legacy `#N`-on-collision behavior. */
  cwd?: string;
  /** Replace an existing same-(cwd,name) peer instead of suffixing `#N`.
   *  Used by stable identities such as supervised daemons and session
   *  replacement, where a second registration is the same logical agent. */
  takeover?: boolean;
}

interface RegisterAck {
  type: "register_ack";
  /** Canonical address (plan/38). New clients route by this. */
  address_assigned: string;
  /** Clean leaf name actually assigned (carries `#N` on a same-(cwd,name)
   *  collision). New clients use it for display; for a legacy peer (no cwd)
   *  it equals `address_assigned`. */
  name_assigned: string;
}

interface SystemBody {
  type: "peer_joined" | "peer_left" | "list_peers_reply";
  /** Compat: carries the peer's ADDRESS (the Map key), not the bare name. */
  name?: string;
  /** Explicit address (plan/38) for clients that prefer the typed field. */
  address?: string;
  /** Addresses (legacy clients route by these). */
  peers?: string[];
  /** Structured roster (plan/38) — clients group by `cwd`/`pc` without parsing. */
  peers_detailed?: PeerInfo[];
}

export class Broker {
  private readonly peers = new Map<string, PeerConn>();
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

  /** Clear only when the caller still owns the active router slot. */
  clearRemoteRouter(expected: RemoteRouter): void {
    if (this.remoteRouter === expected) this.remoteRouter = null;
  }

  /**
   * Plan/25 Wave C entry point: deliver an envelope that arrived from a
   * remote PC (via relay forward) into the local UDS mesh. Skips the
   * `force from = conn.name` rule (that defense is anti-spoof for local
   * peers; cross-PC has its own defense via the relay's verified `from_pc`).
   *
   * Returns the ACK status so the caller (broker_remote) can pack and
   * forward an ACK envelope back across the relay:
   *   - `received` — target exists, envelope delivered (plan/34: always
   *     delivered when the peer is online — the Pi harness enqueues mid-turn
   *     messages, so there is no busy-drop)
   *   - `denied` — no such local peer (or write failed) — caller maps to
   *     transport_error or denied ACK as it sees fit
   */
  injectFromRemote(env: Envelope): RemoteInjectStatus {
    // Remote callers do not cross the normal UDS parser, so validate the exact
    // serialized payload before claiming receipt or writing it to a peer.
    let validated: Envelope;
    try {
      validated = parse(serialize(env));
    } catch {
      return "denied";
    }
    if (
      typeof validated.to !== "string" ||
      validated.to === "broadcast" ||
      validated.to === BROKER_NAME
    ) {
      // Cross-PC is unicast-only at this protocol layer.
      return "denied";
    }
    const targetName = validated.to;
    const peer = this.peers.get(targetName);
    if (!peer) return "denied";

    const line = serialize(validated);
    try {
      peer.socket.write(line);
    } catch {
      return "denied";
    }
    void this._appendAudit(validated, [targetName], "received", "relay");
    this.onRouted?.(validated, [targetName]);
    return "received";
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
    const conn: PeerConn = { name: "", cwd: "", address: "", socket, buf: "" };
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
    // Unregistered conn: a read-only `list_peers` probe (the `remote-pi peers`
    // CLI — answered without registering, so it leaves no trace on the mesh) or
    // the mandatory `register` handshake. Anything else `_handleRegister` drops.
    if (!conn.name) {
      if (this._tryObserverProbe(conn, line)) return;
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
    // Force `from` to the registered ADDRESS (security: peer can't spoof; and
    // replies/ACKs address back by the same canonical key the Map is keyed on).
    env.from = conn.address;
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

    // (cwd, name) identity (plan/38). The cwd is the first-class axis: the
    // address embeds it, so two same-named agents in DIFFERENT folders get
    // distinct addresses and never collide. Legacy peers (no cwd) keep the old
    // global-name behavior. New peers can opt into exact-address takeover for
    // same-folder reincarnations such as daemon restarts.
    const requestedCwd = req.cwd === undefined ? "" : req.cwd;
    if (typeof requestedCwd !== "string" || !isValidRegisteredCwd(requestedCwd)) {
      conn.socket.destroy();
      return;
    }
    const identity = this._identityForRegister(
      requestedCwd,
      req.name,
      req.takeover === true,
    );
    if (!identity) {
      conn.socket.destroy();
      return;
    }

    conn.cwd = requestedCwd;
    conn.name = identity.name;
    conn.address = identity.address;
    // Candidate validity is established before a takeover evicts its prior
    // connection, so a rejected replacement cannot drop a healthy peer.
    if (identity.replaceAddress) this._dropPeerAt(identity.replaceAddress);
    this.peers.set(identity.address, conn);

    // `name_assigned` doubles as the compat alias: for a legacy peer it equals
    // `address_assigned` (cwd empty → address == name), so old clients that read
    // `name_assigned` still get a routable identity.
    const ack: RegisterAck = {
      type: "register_ack",
      address_assigned: conn.address,
      name_assigned: conn.name,
    };
    try {
      conn.socket.write(JSON.stringify(ack) + "\n");
    } catch { /* peer hung up */ }

    // Notify others (peer_joined broadcast). The field carries the ADDRESS.
    this._broadcastSystem(
      { type: "peer_joined", name: conn.address, address: conn.address },
      conn.address,
    );
  }

  /**
   * Answer a read-only `list_peers` request from an UNREGISTERED connection
   * (the `remote-pi peers` CLI probe). Returns true when the line was such a
   * probe — the reply is written and the connection stays unregistered: no
   * name assigned, no `peer_joined`/`peer_left` broadcast, no sibling push, so
   * querying the roster from the shell never perturbs the mesh. Returns false
   * (not a probe) so the caller falls through to the register handshake.
   */
  private _tryObserverProbe(conn: PeerConn, line: string): boolean {
    let parsed: { type?: unknown };
    try {
      parsed = JSON.parse(line) as { type?: unknown };
    } catch {
      return false;  // not JSON → let _handleRegister destroy it
    }
    if (!parsed || typeof parsed !== "object" || parsed.type !== "list_peers") {
      return false;
    }
    const reply: Envelope = {
      from: BROKER_NAME,
      to: "observer",  // synthetic: the conn has no registered name
      id: uuidv7(),
      re: null,
      body: {
        type: "list_peers_reply",
        peers: this._allPeerNames(),
        peers_detailed: this._allPeerInfos(),
      } as SystemBody,
    };
    try { conn.socket.write(serialize(reply)); } catch { /* probe hung up */ }
    return true;
  }

  /** Local UDS peer names plus cross-PC `<pc>:<peer>` entries from the remote
   *  router (empty when no bridge). Shared by the registered `list_peers`
   *  handler and the unregistered observer probe. */
  private _allPeerNames(): string[] {
    const remote = this.remoteRouter ? this.remoteRouter.listRemotePeers() : [];
    return [...this.peerNames(), ...remote];
  }

  /** Structured roster of LOCAL UDS peers (plan/38): one `PeerInfo` each, no
   *  `pc` (they're on this machine). Public so the cross-PC router
   *  (`broker_remote`) can read the authoritative local inventory directly to
   *  push to siblings — no `list_peers` round-trip, no stale cache. */
  localPeerInfos(): PeerInfo[] {
    return [...this.peers.values()].map((p) => ({
      cwd: p.cwd,
      name: p.name,
      address: p.address,
    }));
  }

  /** Structured roster (plan/38): local peers (no `pc`) + cross-PC peers with
   *  `pc`/`cwd`/`name` filled by the remote router (Fase 2). */
  private _allPeerInfos(): PeerInfo[] {
    const remote = this.remoteRouter?.listRemotePeerInfos() ?? [];
    return [...this.localPeerInfos(), ...remote];
  }

  /**
   * Resolve a free `(name, address)` for a register, keyed by **(cwd, name)**
   * (plan/38): the collision check is on the composed ADDRESS, so a name only
   * collides with another peer in the SAME cwd. `#N` is appended to the name
   * (matching the cwd-lock's suffix scheme) until the address is free; for a
   * legacy peer (cwd "") the address is the name, preserving global-name `#N`.
   */
  private _identityForRegister(
    cwd: string,
    requested: string,
    takeover: boolean,
  ): { name: string; address: string; replaceAddress?: string } | null {
    const sanitized = sanitizeMeshName(requested);
    const candidateFor = (name: string): { name: string; address: string } | null => {
      const address = composeAddress({ cwd, name });
      return isBoundedPeerInfo({ cwd, name, address }) ? { name, address } : null;
    };
    const direct = candidateFor(sanitized);
    if (!direct) return null;
    if (takeover && cwd && this.peers.has(direct.address)) {
      return { ...direct, replaceAddress: direct.address };
    }
    if (this.peers.size >= MAX_PEERS_UPDATE_ENTRIES) return null;
    if (!this.peers.has(direct.address)) return direct;

    // Collision: strip any client-provided `#N`, then re-suffix from #2.
    const base = sanitized.replace(/#\d+$/, "");
    for (let n = 2; n < 1000; n++) {
      const candidate = candidateFor(`${base}#${n}`);
      if (!candidate) return null;
      if (!this.peers.has(candidate.address)) return candidate;
    }
    return null;
  }

  private _dropPeerAt(address: string): void {
    const existing = this.peers.get(address);
    if (!existing) return;
    this.peers.delete(address);
    // The old socket's close event may arrive after the replacement has been
    // inserted. Clear its address so it cannot delete the replacement.
    existing.address = "";
    try { existing.socket.destroy(); } catch { /* ignored */ }
  }

  private _onClose(conn: PeerConn): void {
    if (!conn.address) return;
    if (this.peers.get(conn.address) !== conn) return;
    this.peers.delete(conn.address);
    this._broadcastSystem({ type: "peer_left", name: conn.address, address: conn.address }, conn.address);
  }

  // ── routing ───────────────────────────────────────────────────────────────

  private async _route(env: Envelope): Promise<void> {
    // Special handling for messages addressed to the broker itself.
    if (env.to === BROKER_NAME) {
      this._handleBrokerMessage(env);
      return;
    }

    // Give known cross-PC aliases first chance to route. A syntactically
    // absolute Windows drive address contains a colon but is always exact
    // local; all other local registrations may not shadow a known alias.
    const exactLocal = typeof env.to === "string" ? this.peers.get(env.to) : undefined;
    const exactWindowsDriveLocal = !!exactLocal && isWindowsDriveAbsolutePath(exactLocal.cwd);
    if (!exactWindowsDriveLocal && this.remoteRouter && typeof env.to === "string") {
      if (this.remoteRouter.tryRouteOutbound(env)) return;
    }

    const targets = this._resolveTargets(env);
    const delivered: string[] = [];
    const line = serialize(env);
    const isUnicast = typeof env.to === "string" && env.to !== "broadcast";

    // plan/34: reliable delivery — always write to the target's socket. The
    // Pi harness enqueues messages that arrive mid-turn, so there is no
    // busy-drop and `busy` is no longer a possible ACK status. Unicast sends
    // to an online peer always ACK `received`.
    let ackStatus: AckStatus | "none" = "none";
    for (const targetName of targets) {
      const peer = this.peers.get(targetName);
      if (!peer) continue;  // unknown peer: silent drop (sender times out)

      try {
        peer.socket.write(line);
        delivered.push(targetName);
        if (isUnicast) {
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
      // plan/38 decision C: broadcast is scoped to the sender's cwd (folder
      // colleagues), local-only. A peer in /a/b never hears /a/c. The sender is
      // keyed by its address (= env.from); legacy peers (cwd "") broadcast among
      // other cwd-less peers, matching pre-plan/38 behavior.
      const sender = this.peers.get(env.from);
      const scope = sender?.cwd ?? "";
      return [...this.peers.values()]
        .filter((p) => p.address !== env.from && p.cwd === scope)
        .map((p) => p.address);
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
    const body = env.body as { type?: string; peers?: unknown } | null;
    if (!body || typeof body !== "object") return;
    if (body.type === "list_peers") {
      const reply: Envelope = {
        from: BROKER_NAME,
        to: env.from,
        id: uuidv7(),
        re: env.id,
        body: {
          type: "list_peers_reply",
          peers: this._allPeerNames(),       // addresses — legacy clients route by these
          peers_detailed: this._allPeerInfos(),  // plan/38 — clients group without parsing
        } as SystemBody,
      };
      const peer = this.peers.get(env.from);
      if (peer) {
        try { peer.socket.write(serialize(reply)); } catch { /* ignored */ }
      }
      return;
    }
    // plan/34: `turn_state` is no longer consumed — the broker doesn't gate
    // delivery on busy state. The Pi extension still publishes working state
    // as room_meta over the relay (index.ts), independent of the broker.
  }

  private _broadcastSystem(body: SystemBody, excludeAddress: string): void {
    for (const [address, peer] of this.peers) {
      if (address === excludeAddress) continue;
      const env: Envelope = {
        from: BROKER_NAME,
        to: address,
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
      await mkdir(dirname(this.auditPath), { recursive: true });
      await appendFile(this.auditPath, line, "utf8");
    } catch { /* audit best-effort */ }
  }
}
