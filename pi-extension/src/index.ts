/**
 * pi-extension — remote-pi slash commands + AgentBridge wiring
 *
 * Exported as ExtensionFactory (default export) to be loaded by Pi SDK:
 *   pi -e $(pwd)/dist/index.js
 *
 * State machine:  idle → started → paired
 *   /remote-pi start   connects to relay (idle → started)
 *   /remote-pi pair    shows QR for new peers (started, async → paired via auto-listener)
 *   /remote-pi stop    closes everything (any → idle)
 *
 * Pairing (post plano 06 — sem Noise XX):
 *   App envia inner `pair_request` (id, token, device_name) sobre canal opaco.
 *   Pi valida o token via qrSession.consumeToken, salva peer em peers.json
 *   {name, remote_epk, paired_at} e responde com `pair_ok` (ou `pair_error`).
 *   `ct` é base64(JSON.stringify(inner)) — sem cifra, sem MAC.
 *
 * Reconexão de peer conhecido:
 *   Se uma mensagem chega em estado `started` vinda de um epk presente em
 *   peers.json, o auto-listener promove direto pra `paired` sem novo
 *   pair_request, criando o PlainPeerChannel e roteando a mensagem.
 *
 * Architecture note — why we don't use AgentBridge directly here:
 *   AgentBridge.beforeToolCallHook is designed to be passed to createAgentSession().
 *   Inside an extension Pi already owns the AgentSession, so we can't re-bind
 *   beforeToolCall after the fact. The equivalent is pi.on("tool_call", …) which
 *   fires BEFORE execution and supports { block: true }.
 *   AgentBridge (src/session/agent_bridge.ts) remains the tested, mockable unit
 *   for integration tests.
 */

import { randomUUID } from "node:crypto";
import type {
  ExtensionAPI,
  ExtensionCommandContext,
  ExtensionContext,
  ExtensionFactory,
} from "@mariozechner/pi-coding-agent";
import { type Ed25519Keypair } from "./pairing/crypto.js";
import { buildQRUri, displayQR, qrSession, startQRRotation } from "./pairing/qr.js";
import {
  addPeer,
  getOrCreateEd25519Keypair,
  listPeers,
  removePeer,
  type PeerRecord,
} from "./pairing/storage.js";
import type {
  ClientMessage,
  PairErrorCode,
  ServerMessage,
  SessionHistoryEvent,
} from "./protocol/types.js";
import { RelayClient, RoomAlreadyOpenError } from "./transport/relay_client.js";
import { PlainPeerChannel } from "./transport/peer_channel.js";
import { roomIdForCwd } from "./rooms.js";
import { SessionPeer } from "./session/peer.js";
import { registerAgentTools } from "./session/tools.js";
import {
  ensureGlobalDirs,
  listSessions,
  sessionAuditPath,
  sessionHasSock,
  sessionSockPath,
  skillsDir,
} from "./session/global_config.js";
import {
  defaultAgentName,
  effectiveAutoStartRelay,
  loadLocalConfig,
  localConfigExists,
  saveLocalConfig,
} from "./session/local_config.js";
import { runSetupWizard, type WizardUI } from "./session/setup_wizard.js";
import { updateFooter, type FooterState } from "./ui/footer.js";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { mkdirSync, copyFileSync, existsSync, unlinkSync } from "node:fs";
import {
  kDefaultRelayUrl,
  resolveRelayUrl,
  saveConfig,
  isValidRelayUrl,
} from "./config.js";

// ── State machine ─────────────────────────────────────────────────────────────

export type RemoteState = "idle" | "started" | "paired";

let _state: RemoteState = "idle";
let _relay: RelayClient | null = null;
let _relayUrl: string | null = null;  // URL used by current _relay connection
let _peerChannel: PlainPeerChannel | null = null;
let _appPeerId: string | null = null;  // active app peer ID (Ed25519 pk base64 std)
let _peerShort = "";

let _myRoomId: string | null = null;   // this Pi's room id (derived from cwd)
let _myRoomMeta: { name: string; cwd: string; model?: string } | null = null;
let _currentModel: string | undefined = undefined;  // last-known model name

// ── Agent-network session (plano 19) ──────────────────────────────────────────
let _sessionPeer: SessionPeer | null = null;
let _sessionName: string | null = null;
let _sessionPeerCount = 0;

// Cached state of global pairings (`peers.json`). Pairing is per-machine, so a
// device paired in any Pi process is paired everywhere. Refreshed on boot,
// after addPeer (handle_pair_request), and after removePeer (revoke).
let _hasGlobalPairings = false;

/** Reads peers.json and updates the global-pairings cache + footer. Fire and
 *  forget; failures keep the previous cached value. */
function _refreshPairingsCache(): void {
  void listPeers()
    .then((peers) => {
      _hasGlobalPairings = peers.length > 0;
      _refreshFooter();
    })
    .catch(() => { /* keep prior cached value */ });
}

/** Re-queries the broker for the authoritative peer list. The broker's map is
 *  the source of truth — incremental +1/-1 counters drift after failover, lost
 *  `peer_left` broadcasts (e.g., leader leaves), or any dropped event. Called
 *  on every `peer_joined`/`peer_left` and once on join. Fire-and-forget. */
function _refreshSessionPeerCount(
  peer: SessionPeer,
  ctx?: Pick<ExtensionContext, "ui"> | null,
): void {
  void peer.request("broker", { type: "list_peers" }, 2000)
    .then((reply) => {
      const peers = (reply.body as { peers?: string[] } | null)?.peers;
      if (Array.isArray(peers)) {
        _sessionPeerCount = peers.length;
        _refreshFooter(ctx);
      }
    })
    .catch(() => { /* older broker without list_peers — keep prior count */ });
}

/** Friendly model name for room_meta (plano 18). undefined when SDK has none yet. */
function _currentModelName(): string | undefined {
  return _currentModel;
}

/** Refreshes the Pi TUI footer slots from current module state. Safe no-op when ctx lacks ui. */
function _refreshFooter(ctx?: { ui?: { setStatus?: unknown; setTitle?: unknown } } | null): void {
  const target = ctx ?? _lastCtx;
  const ui = target?.ui as (
    { setStatus?: (k: string, v: string | undefined) => void; setTitle?: (t: string) => void } | undefined
  );
  if (!ui || typeof ui.setStatus !== "function" || typeof ui.setTitle !== "function") return;
  const state: FooterState = {
    session: _sessionName ?? undefined,
    peerCount: _sessionPeerCount,
    relayOn: _state !== "idle",
    devicePaired: _state === "paired" ? _peerShort : undefined,
    hasPairings: _hasGlobalPairings,
    agentName: _sessionPeer?.name(),
  };
  updateFooter(
    { ui: { setStatus: ui.setStatus.bind(ui), setTitle: ui.setTitle.bind(ui) } },
    state,
  );
}

// Epoch ms when the state machine entered 'started' (last /remote-pi start).
// Used by session_sync to let the app detect Pi restarts (and force a full
// replay). Cleared on _goIdle.
let _sessionStartedAt: number | null = null;

// Snapshot of agent messages, captured on every agent_end event. Used to
// answer session_sync. Cleared on _goIdle.
type BufferMsg = {
  role: "user" | "assistant" | "toolResult" | string;
  content?: unknown;
  timestamp?: number;
  toolCallId?: string;
  toolName?: string;
  isError?: boolean;
  usage?: { input?: number; output?: number };
};
let _messageBuffer: BufferMsg[] = [];

/** Test-only override of the message buffer. */
export function _setMessageBufferForTest(msgs: unknown[]): void {
  _messageBuffer = msgs as BufferMsg[];
}

/** Test-only accessor: returns a defensive copy of the buffer. */
export function _getMessageBufferForTest(): unknown[] {
  return [..._messageBuffer];
}

/** Test-only override of session started timestamp. */
export function _setSessionStartedAtForTest(ts: number | null): void {
  _sessionStartedAt = ts;
}

/** Test-only: reset the cached model name (between tests). */
export function _setCurrentModelForTest(name: string | undefined): void {
  _currentModel = name;
}

// Per-turn messaging state
let _currentTurnId: string | null = null;

// Module-level pi reference
let _pi: ExtensionAPI | null = null;

let _stopAutoListener: (() => void) | null = null;

// Cached keypair (loaded once, reused across start/pair cycles)
let _cachedEd25519: Ed25519Keypair | null = null;

// ── Session sync limit (mirror cache cap) ─────────────────────────────────────
//
// Configurable via REMOTE_PI_SYNC_LIMIT env var (positive int, default 30).
// Read on every session_sync so QA can `export REMOTE_PI_SYNC_LIMIT=N` between
// runs without restarting the extension. The value is also clamped against
// the client-provided `limit` (server is authoritative).
const SYNC_LIMIT_DEFAULT = 30;
function _getSyncLimit(): number {
  const raw = process.env["REMOTE_PI_SYNC_LIMIT"];
  const parsed = raw ? parseInt(raw, 10) : NaN;
  return Number.isFinite(parsed) && parsed > 0 ? parsed : SYNC_LIMIT_DEFAULT;
}

// ── Relay reconnect state ─────────────────────────────────────────────────────
// Backoffs in ms: 1s, 2s, 5s, 10s, 30s, then stays at 30s.
const RECONNECT_BACKOFFS_MS = [1_000, 2_000, 5_000, 10_000, 30_000];
let _reconnectTimer: ReturnType<typeof setTimeout> | null = null;
let _reconnectAttempt = 0;

/** Test-only: exposes pending reconnect timer state. */
export function _hasPendingReconnect(): boolean {
  return _reconnectTimer !== null;
}

/** Exported for tests. */
export function _getState(): RemoteState { return _state; }


// ── Peer lookup helpers ───────────────────────────────────────────────────────

async function _findKnownPeer(appPeerIdStd: string): Promise<PeerRecord | null> {
  const peers = await listPeers();
  return peers.find((p) => p.remote_epk === appPeerIdStd) ?? null;
}

// ── Transition helpers ────────────────────────────────────────────────────────

/**
 * Full teardown: stop listener, detach channel, close relay → idle.
 *
 * `byeReason` (optional): when present and the channel is up, sends a
 * `{type:"bye", reason}` to the app before detaching so it sees offline
 * immediately instead of waiting ~50s for a ping miss. Fire-and-forget —
 * if the WS already failed (e.g., `relay.on("close")` callback) skip it
 * by omitting the reason; app falls back to ping miss naturally.
 */
function _goIdle(byeReason?: import("./protocol/types.js").ByeReason): void {
  if (_peerChannel && byeReason && _state !== "idle") {
    try {
      _peerChannel.send({ type: "bye", reason: byeReason });
    } catch {
      // peer already offline — fine
    }
  }

  // Cancel any pending reconnect attempt. Critical: /remote-pi stop must
  // win the race against a scheduled reconnect.
  if (_reconnectTimer !== null) {
    clearTimeout(_reconnectTimer);
    _reconnectTimer = null;
  }
  _reconnectAttempt = 0;

  _stopAutoListener?.();
  _stopAutoListener = null;

  _peerChannel?.detach();
  _peerChannel = null;
  _appPeerId = null;
  _peerShort = "";
  _currentTurnId = null;

  _relay?.close();
  _relay = null;
  _relayUrl = null;
  // Preserve _sessionStartedAt + _messageBuffer across stop/start cycles.
  // The Pi agent session outlives the relay connection — `message_end` keeps
  // firing for terminal turns even while idle, and the buffer must survive
  // so those turns appear in the next session_sync. Only a Pi process
  // restart resets these (init-time values).

  _state = "idle";
  _refreshFooter();
}

/**
 * Called when the relay WS closes unexpectedly (network drop, relay restart,
 * etc.). Does a **partial** teardown — keeps `_sessionStartedAt`, `_messageBuffer`,
 * `_relayUrl`, `_cachedEd25519`, `_peerShort` so the session can resume on
 * reconnect — and schedules an `_attemptReconnect`.
 *
 * Peer (app) reconnect after a successful relay reconnect is handled by the
 * existing auto-listener via `peers.json` lookup, so we don't need to track
 * the prior peer here; we just go back to `started` and wait.
 */
function _onRelayClose(): void {
  if (_state === "idle") return;  // already torn down (e.g. /remote-pi stop)

  _stopAutoListener?.();
  _stopAutoListener = null;

  _peerChannel?.detach();
  _peerChannel = null;
  _appPeerId = null;
  _currentTurnId = null;

  _relay = null;  // _relayUrl preserved for retry
  _state = "started";
  _refreshFooter();

  _scheduleReconnect();
}

function _scheduleReconnect(): void {
  if (_reconnectTimer !== null) return;  // already scheduled
  if (!_cachedEd25519 || !_relayUrl) return;  // can't reconnect without these
  if (_getState() === "idle") return;  // stopped while we were here

  const idx = Math.min(_reconnectAttempt, RECONNECT_BACKOFFS_MS.length - 1);
  const delay = RECONNECT_BACKOFFS_MS[idx]!;
  _reconnectAttempt += 1;

  _reconnectTimer = setTimeout(() => {
    _reconnectTimer = null;
    void _attemptReconnect();
  }, delay);
}

async function _attemptReconnect(): Promise<void> {
  // `_state` may transition to "idle" between awaits via _goIdle; read via
  // _getState() to defeat TS narrowing on the module-level let.
  if (_getState() === "idle") return;
  if (!_cachedEd25519 || !_relayUrl) return;

  const edKp = _cachedEd25519;
  const url = _relayUrl;
  const relay = new RelayClient(url, edKp);

  try {
    // Replay the same room identity from _cmdStart. Without this the relay
    // would log this WS as a default-room peer and the app would see a
    // phantom "legacy session" appear (regression of plano 17 + 18).
    await relay.connect({
      ...(_myRoomId ? { roomId: _myRoomId } : {}),
      ...(_myRoomMeta ? { roomMeta: _myRoomMeta } : {}),
    });
  } catch {
    if (_getState() === "idle") return;
    _scheduleReconnect();
    return;
  }

  if (_getState() === "idle") {
    // Stop fired while connect was succeeding — drop the new relay.
    relay.close();
    return;
  }

  _relay = relay;
  _reconnectAttempt = 0;

  relay.on("close", _onRelayClose);
  _stopAutoListener = _installAutoListener(relay);

  // _state stays "started"; peer reconnect (if previously paired) flows
  // through _installAutoListener → _findKnownPeer → _promoteToPaired
  // automatically when the app sends any inner.
}

/**
 * App-level peer disconnect (relay still up).
 * Transitions paired → started and re-installs the auto-listener.
 * Exported so tests can trigger it directly; in production it will be
 * called when the relay sends a peer-disconnect notification (future).
 */
export function _onPeerDisconnect(): void {
  if (_state !== "paired") return;

  _peerChannel?.detach();
  _peerChannel = null;
  _appPeerId = null;
  _peerShort = "";
  _currentTurnId = null;

  _state = "started";
  _refreshFooter();
  _lastCtx?.ui.notify("[remote-pi] App disconnected, listening for reconnect", "info");

  // Re-install auto-listener so reconnect works
  if (_relay) {
    _stopAutoListener?.();
    _stopAutoListener = _installAutoListener(_relay);
  }
}

/**
 * Promotes started → paired by installing a PlainPeerChannel for `appPeerId`.
 * Routes `firstInner` immediately so the message that triggered reconnection
 * isn't dropped.
 */
function _promoteToPaired(
  relay: RelayClient,
  appPeerId: string,
  peerName: string,
  firstInner?: ClientMessage,
): void {
  const peerShort = appPeerId.slice(0, 8);

  const channel = new PlainPeerChannel(
    relay,
    appPeerId,
    _myRoomId ?? undefined,
    (msg) => routeClientMessage(msg, _lastCtx ?? _noopCtx),
    () => _onPeerDisconnect(),
  );

  _peerChannel = channel;
  _appPeerId = appPeerId;
  _peerShort = peerShort;
  _state = "paired";
  _refreshFooter();

  _lastCtx?.ui.notify(
    `[remote-pi] state: paired (peer=${peerShort}, name=${peerName})`,
    "info",
  );

  if (firstInner) {
    // Route the inner that triggered the reconnect — the channel listener
    // also saw it, but we route through routeClientMessage to be explicit.
    void firstInner;
  }
}

// ── Auto-reconnect listener ───────────────────────────────────────────────────
//
// Installed while in 'started' state. Decodes the outer envelope as
// base64(JSON) and dispatches based on inner type:
//   • pair_request from any peer → validate token, persist peer, send pair_ok/pair_error
//   • any inner from a known peer (peers.json) → promote to paired and route
//   • anything else → ignored

function _installAutoListener(relay: RelayClient): () => void {
  const onMsg = async (line: string) => {
    let outer: { peer?: string; ct?: string };
    try { outer = JSON.parse(line) as { peer?: string; ct?: string }; }
    catch { return; }

    if (!outer.peer || !outer.ct) return;

    // Once paired, the PlainPeerChannel handles application messages.
    if (_state === "paired") return;
    if (_state !== "started") return;

    // Decode inner envelope (base64 JSON)
    let inner: ClientMessage;
    try {
      const plaintext = Buffer.from(outer.ct, "base64").toString("utf8");
      const parsed = JSON.parse(plaintext) as unknown;
      if (
        !parsed ||
        typeof parsed !== "object" ||
        typeof (parsed as Record<string, unknown>).type !== "string"
      ) return;
      inner = parsed as ClientMessage;
    } catch { return; }

    const appPeerId = outer.peer;

    if (inner.type === "pair_request") {
      await _handlePairRequest(relay, appPeerId, inner);
      return;
    }

    // Reconnect path: known peer sends a non-pair message → promote to paired
    // and route through the new PlainPeerChannel. See pairing.md §Reconexão.
    const known = await _findKnownPeer(appPeerId);
    if (known) {
      _promoteToPaired(relay, appPeerId, known.name);
      // The PlainPeerChannel that was just installed will not have observed
      // the line we already consumed; route the inner directly.
      routeClientMessage(inner, _lastCtx ?? _noopCtx);
      return;
    }

    // Unknown peer with non-pair_request inner — signal so the app can react
    // (peer was revoked / never paired). pair_request from unknown peer was
    // already handled above as a legitimate path. We never log inner contents,
    // only inner.type.
    const errReply: ServerMessage = {
      type: "error",
      code: "unknown_peer",
      message: "Peer not paired — re-scan QR",
    };
    const errCt = Buffer.from(JSON.stringify(errReply)).toString("base64");
    relay.send(JSON.stringify({ peer: appPeerId, ct: errCt }));
  };

  relay.on("message", onMsg);
  return () => relay.off("message", onMsg);
}

async function _handlePairRequest(
  relay: RelayClient,
  appPeerId: string,
  inner: Extract<ClientMessage, { type: "pair_request" }>,
): Promise<void> {
  const sendInner = (msg: ServerMessage) => {
    const ct = Buffer.from(JSON.stringify(msg)).toString("base64");
    relay.send(JSON.stringify({ peer: appPeerId, ct }));
  };

  const sendError = (code: PairErrorCode, message: string) => {
    sendInner({ type: "pair_error", in_reply_to: inner.id, code, message });
  };

  const status = qrSession.consumeToken(inner.token);
  if (status !== "ok") {
    const code: PairErrorCode =
      status === "expired"  ? "token_expired"
      : status === "consumed" ? "token_consumed"
      : "token_unknown";
    const msg =
      code === "token_expired"  ? "Token efêmero expirou. Gere um novo QR com /remote-pi pair."
      : code === "token_consumed" ? "Token já consumido por outro pair_request."
      : "Token não foi emitido por este Pi.";
    sendError(code, msg);
    return;
  }

  try {
    await addPeer({
      name: inner.device_name,
      remote_epk: appPeerId,
      paired_at: new Date().toISOString(),
    });
    _refreshPairingsCache();
  } catch (err) {
    sendError("internal_error", `Failed to persist peer: ${String(err)}`);
    return;
  }

  const cwd = _lastCtx && "cwd" in _lastCtx
    ? (_lastCtx as ExtensionCommandContext).cwd
    : process.cwd();
  const sessionName = cwd.split("/").slice(-2).join("/") || "remote";

  _promoteToPaired(relay, appPeerId, inner.device_name);

  sendInner({
    type: "pair_ok",
    in_reply_to: inner.id,
    session_name: sessionName,
    session_started_at: _sessionStartedAt ?? Date.now(),
    // App uses this to address subsequent inner messages to the right room
    // when this Pi runs alongside others with the same epk. Defensive fallback
    // to roomIdForCwd(cwd) covers the edge case where pair_request lands
    // before _cmdStart could set _myRoomId (shouldn't happen in practice).
    room_id: _myRoomId ?? roomIdForCwd(cwd),
  });
}

// ── Extension factory (default export) ───────────────────────────────────────

// Stores most recent command context so the auto-listener can use ui.notify
let _lastCtx: Pick<ExtensionContext, "ui" | "abort" | "cwd"> | null = null;
const _noopCtx = { ui: { notify: () => undefined }, abort: () => undefined };

const extension: ExtensionFactory = (pi: ExtensionAPI): void => {
  _pi = pi;
  console.error(`[remote-pi] session sync limit: ${_getSyncLimit()}`);

  // Plano 19: ensure ~/.pi/remote/{sessions,skills}/ exist and deploy the
  // agent-network skill on first load. resources_discover lets Pi find it.
  try {
    ensureGlobalDirs();
    _deployAgentNetworkSkill();
  } catch { /* best-effort init */ }

  // Seed the global-pairings cache from peers.json so the footer can show
  // 🟢/🟡 correctly the moment the relay is up (no race with first refresh).
  _refreshPairingsCache();

  pi.on("resources_discover", () => ({ skillPaths: [skillsDir()] }));

  // Plano 20: agent_send + agent_request tools so the LLM can drive the
  // session network natively. Getter captures `_sessionPeer` live so the
  // tool always sees the current state.
  registerAgentTools(pi, () => _sessionPeer);

  // Tool calls execute without prompting the remote user. The Pi SDK has no
  // native `requiresApproval` per tool, and a hardcoded gate (Bash/Edit/Write)
  // misfired on every custom tool from third-party packages. Approval will
  // come back when the Pi ecosystem ships a permissions convention. tool_result
  // is still forwarded so the app shows tool activity transparently.

  // Mirror input typed in the Pi terminal (or sent via RPC) to the remote app.
  // 'extension' source is our own sendUserMessage call from routeClientMessage,
  // which already set _currentTurnId — skip to avoid double turnId.
  pi.on("input", (event) => {
    if (!_peerChannel) return;
    if (event.source === "extension") return;
    const turnId = `local_${randomUUID()}`;
    _currentTurnId = turnId;
    _peerChannel.send({ type: "user_input", id: turnId, text: event.text });
  });

  // Track active model so the app can show it in the SessionTile (plano 18).
  // SDK fires model_select on settings load + every user switch. We cache the
  // friendly name and broadcast a room_meta_update so the relay can fan it
  // out to subscribed apps without needing a new pair.
  pi.on("model_select", (event) => {
    const m = event?.model as { name?: string; id?: string } | undefined;
    const modelName = m?.name ?? m?.id;
    if (!modelName) return;
    _currentModel = modelName;
    // Keep the cached room_meta fresh so a future reconnect carries the
    // current model in its hello (otherwise the post-reconnect hello would
    // ship the stale model that was active at _cmdStart time).
    if (_myRoomMeta) _myRoomMeta = { ..._myRoomMeta, model: modelName };
    if (!_relay || !_myRoomId) return;
    console.error(`[remote-pi] model_select → ${modelName}`);
    _relay.sendControl({
      type: "room_meta_update",
      room_id: _myRoomId,
      meta: { model: modelName },
    });
  });

  pi.on("message_update", (event) => {
    if (!_peerChannel || !_currentTurnId) return;
    const ae = event.assistantMessageEvent;
    if (ae.type === "text_delta") {
      _peerChannel.send({ type: "agent_chunk", in_reply_to: _currentTurnId, delta: ae.delta });
    }
  });

  // Notify the app a tool is about to run (visibility only, NOT approval).
  // tool_execution_start fires before the tool executes; tool_execution_end
  // closes the loop with the result (success or error). Together they let
  // the app render a "Tool running… done" timeline without any gating.
  pi.on("tool_execution_start", (event) => {
    if (!_peerChannel) return;
    _peerChannel.send({
      type: "tool_request",
      tool_call_id: event.toolCallId,
      tool: event.toolName,
      args: event.args as Record<string, unknown>,
    });
  });

  pi.on("tool_execution_end", (event) => {
    if (!_peerChannel) return;
    const msg: ServerMessage = event.isError
      ? { type: "tool_result", tool_call_id: event.toolCallId, error: String(event.result) }
      : { type: "tool_result", tool_call_id: event.toolCallId, result: event.result as unknown };
    _peerChannel.send(msg);
  });

  // Cumulative session buffer fed via `message_end`, which fires once per
  // persisted message (user, assistant, toolResult) — same hook the SDK uses
  // to persist to sessionManager (see agent-session.js:298-309). Pushing here
  // accumulates the whole session over time, so session_sync can replay every
  // turn — including turns initiated from the Pi terminal (source:"interactive")
  // or RPC. Previous impl overwrote on `agent_end` and lost everything but the
  // last turn (see diagnostics 14, 15).
  pi.on("message_end", (event) => {
    const m = event?.message as { role?: string } | undefined;
    if (!m) return;
    if (m.role === "user" || m.role === "assistant" || m.role === "toolResult") {
      _messageBuffer.push(m as unknown as BufferMsg);
    }
  });

  pi.on("agent_end", () => {
    // Buffer is fed by `message_end`; here we only finalize the outbound
    // turn signal to the app. No buffer mutation.
    if (!_peerChannel || !_currentTurnId) return;
    _peerChannel.send({ type: "agent_done", in_reply_to: _currentTurnId });
    _currentTurnId = null;
  });

  // ── Commands (plano 19 taxonomy) ──────────────────────────────────────────
  pi.registerCommand("remote-pi", {
    description: "Connect (join session + start relay), or run setup on first use",
    getArgumentCompletions: async (prefix) => {
      if (prefix.startsWith("revoke ") || prefix === "revoke") {
        const shortPrefix = prefix === "revoke" ? "" : prefix.slice("revoke ".length);
        return _shortidCompletions(shortPrefix, "revoke ");
      }
      return [
        "join", "leave", "rename", "sessions", "setup",
        "relay", "pair", "devices", "revoke",
        "set-relay", "config",
        // legacy aliases (still autocomplete-visible during the deprecation window)
        "start", "stop", "list", "add-relay",
      ]
        .filter((o) => o.startsWith(prefix))
        .map((o) => ({ value: o, label: o }));
    },
    handler: async (args, ctx) => {
      _lastCtx = ctx;
      const sub = args.trim();
      if      (sub === "")                  { await _cmdStatus(ctx); }
      else if (sub === "setup")             { await _cmdSetup(ctx); }
      else if (sub === "join" || sub.startsWith("join ")) { await _cmdJoin(sub.slice("join".length).trim(), ctx); }
      else if (sub === "leave")             { await _cmdLeave(ctx); }
      else if (sub.startsWith("rename"))    { await _cmdRename(sub.slice("rename".length).trim(), ctx); }
      else if (sub === "sessions")          { _cmdSessions(ctx); }
      else if (sub === "relay")             { await _cmdRelayToggle(ctx); }
      else if (sub === "relay start")       { await _cmdStart(ctx); }
      else if (sub === "relay stop")        { await _cmdStop(ctx); }
      else if (sub === "relay status")      { _cmdRelayStatus(ctx); }
      else if (sub.startsWith("relay url")) { _cmdSetRelay(sub.slice("relay url".length).trim(), ctx); }
      else if (sub === "pair")              { await _cmdPair(ctx); }
      else if (sub === "devices")           { await _cmdList(ctx); }
      else if (sub.startsWith("revoke"))    { await _cmdRevoke(sub.slice("revoke".length).trim(), ctx); }
      else if (sub.startsWith("set-relay")) { _cmdSetRelay(sub.slice("set-relay".length).trim(), ctx); }
      else if (sub === "config")            { _cmdConfig(ctx); }
      // ── Legacy aliases (deprecated, 1-release window) ─────────────────────
      else if (sub === "start") {
        ctx.ui.notify("[remote-pi] '/remote-pi start' deprecated — use '/remote-pi relay start' (auto-joining default session)", "warning");
        await _cmdJoin("", ctx);
        await _cmdStart(ctx);
      }
      else if (sub === "stop") {
        ctx.ui.notify("[remote-pi] '/remote-pi stop' deprecated — use '/remote-pi leave' + '/remote-pi relay stop'", "warning");
        await _cmdLeave(ctx);
        await _cmdStop(ctx);
      }
      else if (sub === "list") {
        ctx.ui.notify("[remote-pi] '/remote-pi list' deprecated — use '/remote-pi devices'", "warning");
        await _cmdList(ctx);
      }
      else if (sub.startsWith("add-relay")) {
        ctx.ui.notify("[remote-pi] '/remote-pi add-relay' deprecated — use '/remote-pi relay url <...>'", "warning");
        _cmdSetRelay(sub.slice("add-relay".length).trim(), ctx);
      }
      else { await _cmdStatus(ctx); }
    },
  });

  // Nested registrations (full taxonomy)
  pi.registerCommand("remote-pi setup",    { description: "Run the setup wizard and update local config", handler: async (_, ctx) => { _lastCtx = ctx; await _cmdSetup(ctx); } });
  pi.registerCommand("remote-pi join",     { description: "Join (or create) a local agent session", handler: async (args, ctx) => { _lastCtx = ctx; await _cmdJoin(args.trim(), ctx); } });
  pi.registerCommand("remote-pi leave",    { description: "Leave the current agent session", handler: async (_, ctx) => { _lastCtx = ctx; await _cmdLeave(ctx); } });
  pi.registerCommand("remote-pi rename",   { description: "Rename this agent in the current session", handler: async (args, ctx) => { _lastCtx = ctx; await _cmdRename(args.trim(), ctx); } });
  pi.registerCommand("remote-pi sessions", { description: "List local agent sessions", handler: async (_, ctx) => { _lastCtx = ctx; _cmdSessions(ctx); } });
  pi.registerCommand("remote-pi relay",    { description: "Toggle the relay connection on/off", handler: async (_, ctx) => { _lastCtx = ctx; await _cmdRelayToggle(ctx); } });
  pi.registerCommand("remote-pi relay start",  { description: "Connect to the relay", handler: async (_, ctx) => { _lastCtx = ctx; await _cmdStart(ctx); } });
  pi.registerCommand("remote-pi relay stop",   { description: "Disconnect from the relay", handler: async (_, ctx) => { _lastCtx = ctx; await _cmdStop(ctx); } });
  pi.registerCommand("remote-pi relay status", { description: "Show current relay status", handler: async (_, ctx) => { _lastCtx = ctx; _cmdRelayStatus(ctx); } });
  pi.registerCommand("remote-pi relay url",    { description: "Set relay URL (alias of /remote-pi set-relay)", handler: async (args, ctx) => { _lastCtx = ctx; _cmdSetRelay(args.trim(), ctx); } });
  pi.registerCommand("remote-pi pair",     { description: "Show a QR code to pair a new mobile device", handler: async (_, ctx) => { _lastCtx = ctx; await _cmdPair(ctx); } });
  pi.registerCommand("remote-pi devices",  { description: "List paired mobile devices", handler: async (_, ctx) => { _lastCtx = ctx; await _cmdList(ctx); } });
  pi.registerCommand("remote-pi revoke", {
    description: "Revoke a paired device by its shortid",
    getArgumentCompletions: async (prefix) => _shortidCompletions(prefix),
    handler: async (args, ctx) => { _lastCtx = ctx; await _cmdRevoke(args.trim(), ctx); },
  });
  pi.registerCommand("remote-pi set-relay", { description: "Persist a new relay URL to user config", handler: async (args, ctx) => { _lastCtx = ctx; _cmdSetRelay(args.trim(), ctx); } });
  pi.registerCommand("remote-pi config",    { description: "Show the effective relay URL and its source", handler: async (_, ctx) => { _lastCtx = ctx; _cmdConfig(ctx); } });

  // Legacy aliases (deprecated, 1-release deprecation window).
  const legacyWarn = (ctx: ExtensionCommandContext, old: string, neu: string) =>
    ctx.ui.notify(`[remote-pi] '${old}' deprecated — use '${neu}'`, "warning");
  pi.registerCommand("remote-pi start", {
    description: "[DEPRECATED] alias of /remote-pi relay start (also auto-joins the default session)",
    handler: async (_, ctx) => { _lastCtx = ctx; legacyWarn(ctx, "/remote-pi start", "/remote-pi relay start"); await _cmdJoin("", ctx); await _cmdStart(ctx); },
  });
  pi.registerCommand("remote-pi stop", {
    description: "[DEPRECATED] alias of /remote-pi leave + /remote-pi relay stop",
    handler: async (_, ctx) => { _lastCtx = ctx; legacyWarn(ctx, "/remote-pi stop", "/remote-pi leave + /remote-pi relay stop"); await _cmdLeave(ctx); await _cmdStop(ctx); },
  });
  pi.registerCommand("remote-pi list", {
    description: "[DEPRECATED] alias of /remote-pi devices",
    handler: async (_, ctx) => { _lastCtx = ctx; legacyWarn(ctx, "/remote-pi list", "/remote-pi devices"); await _cmdList(ctx); },
  });
  pi.registerCommand("remote-pi add-relay", {
    description: "[DEPRECATED] alias of /remote-pi relay url",
    handler: async (args, ctx) => { _lastCtx = ctx; legacyWarn(ctx, "/remote-pi add-relay", "/remote-pi relay url"); _cmdSetRelay(args.trim(), ctx); },
  });
};

export default extension;

// ── Command implementations ───────────────────────────────────────────────────

function _showStatus(ctx: Pick<ExtensionContext, "ui">): void {
  const relayUrl = _relayUrl ?? resolveRelayUrl().url;
  const sessionPart = _sessionName ? `session=${_sessionName} (${_sessionPeerCount}) · ` : "";
  let msg: string;
  if      (_state === "idle")   msg = `[remote-pi] ${sessionPart}relay=idle (${relayUrl}). Run /remote-pi relay start to connect.`;
  else if (_state === "started") msg = `[remote-pi] ${sessionPart}relay=started (peer=${_peerShort || "?"}, ${relayUrl}) — run /remote-pi pair to show QR`;
  else                           msg = `[remote-pi] ${sessionPart}relay=paired (peer=${_peerShort}, ${relayUrl}) — connected and ready`;
  ctx.ui.notify(msg, "info");
}

async function _cmdStatus(ctx: Pick<ExtensionContext, "ui" | "cwd">): Promise<void> {
  const cwd = "cwd" in ctx ? (ctx as ExtensionCommandContext).cwd : process.cwd();

  // First-time wizard: no local config in this cwd → run interactive setup.
  if (!localConfigExists(cwd)) {
    const ui = ctx.ui as unknown as WizardUI;
    if (typeof ui.select !== "function") {
      _showStatus(ctx);
      return;
    }
    const baseDefault = defaultAgentName(cwd);
    const newConfig = await runSetupWizard(ui, {
      agent_name: baseDefault,
      session_name: baseDefault,
      auto_start_relay: true,
    });
    if (!newConfig) {
      ctx.ui.notify("[remote-pi] Setup cancelled.", "info");
      return;
    }
    saveLocalConfig(cwd, newConfig);
    ctx.ui.notify(
      `[remote-pi] Config saved to ${cwd}/.pi/remote-pi/config.json`,
      "info",
    );
    await _cmdJoin(newConfig.session_name ?? baseDefault, ctx);
    if (effectiveAutoStartRelay(newConfig)) await _cmdStart(ctx);
    _showStatus(ctx);
    return;
  }

  // Returning user with config: auto-start if requested + currently inactive.
  const config = loadLocalConfig(cwd);
  if (effectiveAutoStartRelay(config) && !_sessionPeer) {
    const sessionName = config.session_name ?? defaultAgentName(cwd);
    await _cmdJoin(sessionName, ctx);
    if (_state === "idle") await _cmdStart(ctx);
  }
  _showStatus(ctx);
}

async function _cmdSetup(ctx: Pick<ExtensionContext, "ui" | "cwd">): Promise<void> {
  const cwd = "cwd" in ctx ? (ctx as ExtensionCommandContext).cwd : process.cwd();
  const ui = ctx.ui as unknown as WizardUI;
  if (typeof ui.select !== "function") {
    ctx.ui.notify("[remote-pi] Setup requires an interactive UI.", "warning");
    return;
  }
  const current = loadLocalConfig(cwd);
  const baseDefault = defaultAgentName(cwd);
  const newConfig = await runSetupWizard(ui, {
    agent_name: current.agent_name ?? baseDefault,
    session_name: current.session_name ?? baseDefault,
    auto_start_relay: effectiveAutoStartRelay(current),
  });
  if (!newConfig) {
    ctx.ui.notify("[remote-pi] Setup cancelled.", "info");
    return;
  }
  saveLocalConfig(cwd, newConfig);
  ctx.ui.notify(
    "[remote-pi] Config updated. Run /remote-pi to apply now (join + relay).",
    "info",
  );
}

async function _cmdStart(ctx: Pick<ExtensionContext, "ui" | "cwd">): Promise<void> {
  if (_state !== "idle") {
    ctx.ui.notify("[remote-pi] Already started.", "warning");
    return;
  }

  const edKp = await getOrCreateEd25519Keypair();
  _cachedEd25519 = edKp;

  const { url: relayUrl, source } = resolveRelayUrl();
  const myShort = Buffer.from(edKp.publicKey).toString("base64").slice(0, 8);

  // Derive room from cwd so N parallel `pi -e` in different directories can
  // share the same Ed25519 identity without colliding on the relay.
  const cwd = "cwd" in ctx ? (ctx as ExtensionCommandContext).cwd : process.cwd();
  const roomId = roomIdForCwd(cwd);
  const sessionName = cwd.split("/").slice(-2).join("/") || "remote";

  // Initial model from ctx (ExtensionContext.model is the SDK's current
  // selection — set by user settings or last-used). May be undefined on
  // first boot before any model_select; that's fine, room_meta omits the
  // field then.
  const ctxModelName = (ctx as Partial<ExtensionContext> & { model?: { name?: string; id?: string } }).model;
  if (ctxModelName) _currentModel = ctxModelName.name ?? ctxModelName.id ?? undefined;

  const roomMeta: { name: string; cwd: string; model?: string } = { name: sessionName, cwd };
  const modelName = _currentModelName();
  if (modelName) roomMeta.model = modelName;
  // Persist so _attemptReconnect can replay the same hello payload — without
  // this, reconnect issues a bare hello and the relay creates a "default room"
  // entry that surfaces in the app as a phantom legacy session.
  _myRoomMeta = roomMeta;

  ctx.ui.notify(`[remote-pi] Connecting to relay ${relayUrl} (source: ${source}, room: ${roomId})…`, "info");

  const relay = new RelayClient(relayUrl, edKp);
  try {
    await relay.connect({ roomId, roomMeta });
  } catch (err) {
    if (err instanceof RoomAlreadyOpenError) {
      ctx.ui.notify(
        "[remote-pi] Already running in this cwd. Stop the other terminal first.",
        "error",
      );
      return;
    }
    ctx.ui.notify(`[remote-pi] relay connect failed: ${String(err)}`, "error");
    return;
  }

  _relay = relay;
  _relayUrl = relayUrl;
  _peerShort = myShort;
  _myRoomId = roomId;
  _state = "started";
  // Set _sessionStartedAt ONLY on first /remote-pi start since process boot.
  // Subsequent start cycles (after stop) preserve the original epoch so the
  // app keeps treating it as the same session (and merges new events from
  // the terminal turns that happened during the idle window). Pi process
  // restart is the only thing that produces a fresh session_started_at.
  if (_sessionStartedAt === null) _sessionStartedAt = Date.now();
  // _messageBuffer intentionally preserved across stop/start — it accumulates
  // message_end events for the lifetime of the Pi process, including turns
  // initiated from the terminal while the relay was disconnected.

  relay.on("close", _onRelayClose);

  _stopAutoListener = _installAutoListener(relay);
  _refreshFooter(ctx);

  ctx.ui.notify(`[remote-pi] state: started (peer=${myShort}) — Connected to relay ${relayUrl}`, "info");
}

async function _cmdPair(ctx: Pick<ExtensionContext, "ui" | "cwd">): Promise<void> {
  if (_state === "idle") {
    ctx.ui.notify("[remote-pi] Run /remote-pi start first.", "warning");
    return;
  }
  if (_state === "paired") {
    ctx.ui.notify(`[remote-pi] Already paired with ${_peerShort}. Run /remote-pi stop first.`, "warning");
    return;
  }

  const edKp = _cachedEd25519!;
  const cwd = "cwd" in ctx ? (ctx as ExtensionCommandContext).cwd : "";
  const sessionName = cwd.split("/").slice(-2).join("/") || "remote";

  const { token, expiresAt } = qrSession.issueToken();
  const roomId = _myRoomId ?? roomIdForCwd(cwd);
  const qrUri = buildQRUri(token, edKp.publicKey, sessionName, roomId);
  displayQR(qrUri);

  ctx.ui.notify(
    `[remote-pi] QR ready — valid until ${new Date(expiresAt).toLocaleTimeString()}. Scan with the app.`,
    "info",
  );
  // Returns immediately; the auto-listener transitions to 'paired' on pair_request.
}

async function _cmdStop(ctx: Pick<ExtensionContext, "ui">): Promise<void> {
  if (_state === "idle") {
    ctx.ui.notify("[remote-pi] Already idle — nothing to stop.", "info");
    return;
  }
  _goIdle("peer_stop");
  ctx.ui.notify("[remote-pi] state: idle — Disconnected.", "info");
}

async function _cmdList(ctx: Pick<ExtensionContext, "ui">): Promise<void> {
  const peers = await listPeers();
  if (peers.length === 0) { ctx.ui.notify("[remote-pi] No paired devices.", "info"); return; }
  const lines = peers.map((p) => {
    const shortid = p.remote_epk.slice(0, 8);
    const active = _state === "paired" && _appPeerId === p.remote_epk ? " (active)" : "";
    return `• ${shortid} — ${p.name}${active}`;
  }).join("\n");
  ctx.ui.notify(`[remote-pi] Paired devices:\n${lines}`, "info");
}

async function _cmdRevoke(arg: string, ctx: Pick<ExtensionContext, "ui">): Promise<void> {
  const shortid = arg.trim();
  if (!shortid) {
    ctx.ui.notify(
      "[remote-pi] Usage: /remote-pi revoke <shortid>. Run /remote-pi list to see shortids.",
      "warning",
    );
    return;
  }

  const peers = await listPeers();
  const matches = peers.filter((p) => p.remote_epk.startsWith(shortid));

  if (matches.length === 0) {
    ctx.ui.notify(
      `[remote-pi] No peer matching '${shortid}'. Run /remote-pi list to see shortids.`,
      "warning",
    );
    return;
  }

  if (matches.length > 1) {
    const collisions = matches.map((p) => p.remote_epk.slice(0, 8)).join(", ");
    ctx.ui.notify(
      `[remote-pi] Ambiguous shortid — ${matches.length} matches: ${collisions}. Use mais chars.`,
      "warning",
    );
    return;
  }

  const peer = matches[0]!;
  await removePeer(peer.remote_epk);
  _refreshPairingsCache();

  if (_state === "paired" && _appPeerId === peer.remote_epk) {
    _goIdle("session_replaced");
  }

  ctx.ui.notify(
    `[remote-pi] Revoked: ${peer.name} (${peer.remote_epk.slice(0, 8)}…)`,
    "info",
  );
}

async function _shortidCompletions(
  prefix: string,
  valuePrefix = "",
): Promise<Array<{ value: string; label: string }>> {
  const peers = await listPeers();
  return peers
    .map((p) => ({ shortid: p.remote_epk.slice(0, 8), name: p.name }))
    .filter((x) => x.shortid.startsWith(prefix))
    .map((x) => ({ value: `${valuePrefix}${x.shortid}`, label: `${x.shortid} (${x.name})` }));
}

function _cmdSetRelay(arg: string, ctx: Pick<ExtensionContext, "ui">): void {
  const url = arg.trim();
  if (!url) {
    ctx.ui.notify(
      "[remote-pi] Usage: /remote-pi set-relay <ws:// or wss:// url>",
      "warning",
    );
    return;
  }
  if (!isValidRelayUrl(url)) {
    ctx.ui.notify(
      `[remote-pi] Invalid URL: ${url}. Must start with ws:// or wss://`,
      "error",
    );
    return;
  }
  saveConfig({ relay: url });
  ctx.ui.notify(
    `[remote-pi] Relay set to ${url}. Run /remote-pi start (or restart) to apply.`,
    "info",
  );
}

function _cmdConfig(ctx: Pick<ExtensionContext, "ui">): void {
  const { url, source } = resolveRelayUrl();
  ctx.ui.notify(
    `[remote-pi] Relay: ${url}\n  Source: ${source}`,
    "info",
  );
}

// ── Agent-network commands (plano 19) ─────────────────────────────────────────

function _resolveExtensionDir(): string {
  // dist/index.js → dist; skills sit at <extensionRoot>/skills/. When we run
  // from src/ via tsx (dev), index.ts is in src/ and skills/ is sibling. We
  // detect by checking both locations.
  const here = fileURLToPath(import.meta.url);
  // dist/index.js or src/index.ts → parent = <dist or src>; sibling = ../skills
  const parent = here.replace(/\/[^/]+$/, "");
  const candidateA = join(parent, "..", "skills"); // dist → ../skills
  const candidateB = join(parent, "skills");        // src → skills
  if (existsSync(candidateA)) return parent.replace(/\/dist$/, "");
  if (existsSync(candidateB)) return parent;
  return parent;
}

function _deployAgentNetworkSkill(): void {
  // Pi SDK spec (core/skills.js): every skill must live at
  //   <skillsRoot>/<skill-name>/SKILL.md
  // The skill `name:` frontmatter must equal the parent directory name. We
  // ship the source pre-arranged that way so deploy is a straight copy into
  // ~/.pi/remote/skills/agent-network/SKILL.md.
  const root = _resolveExtensionDir();
  const src1 = join(root, "skills", "agent-network", "SKILL.md");
  const src2 = join(root, "..", "skills", "agent-network", "SKILL.md");
  const src = existsSync(src1) ? src1 : (existsSync(src2) ? src2 : null);
  if (!src) return;
  const dstDir = join(skillsDir(), "agent-network");
  const dst = join(dstDir, "SKILL.md");
  try {
    mkdirSync(dstDir, { recursive: true });
    copyFileSync(src, dst);
    // Cleanup legacy deploy at ~/.pi/remote/skills/agent-network.md (flat
    // layout, fails the Pi SDK's name-vs-parent-dir validation).
    const legacy = join(skillsDir(), "agent-network.md");
    if (existsSync(legacy)) {
      try { unlinkSync(legacy); } catch { /* ignored */ }
    }
  } catch { /* best-effort */ }
}

async function _cmdJoin(arg: string, ctx: Pick<ExtensionContext, "ui" | "cwd">): Promise<void> {
  const cwd = "cwd" in ctx ? (ctx as ExtensionCommandContext).cwd : process.cwd();
  const local = loadLocalConfig(cwd);
  const sessionName = (arg || local.session_name || defaultAgentName(cwd)).trim();
  const agentName = local.agent_name || defaultAgentName(cwd);

  if (_sessionPeer) {
    ctx.ui.notify(`[remote-pi] Already joined "${_sessionName}". Leave first.`, "warning");
    return;
  }

  ensureGlobalDirs();
  mkdirSync(join(skillsDir(), "..", "sessions", sessionName), { recursive: true });

  const sock = sessionSockPath(sessionName);
  const audit = sessionAuditPath(sessionName);
  const peer = new SessionPeer({ sockPath: sock, name: agentName, auditPath: audit });

  peer.onMessage((env) => {
    const body = env.body as { type?: string } | null;
    // Broker system events: re-query broker for authoritative count.
    // Incremental ±1 drifts when peer_left is missed (leader leaves cleanly,
    // failover, etc.) — querying list_peers makes the count self-healing.
    if (body && (body.type === "peer_joined" || body.type === "peer_left")) {
      _refreshSessionPeerCount(peer, ctx);
      return;
    }
    if (env.from === "broker") return;  // other broker control messages — ignore

    // Anything else is a real agent-to-agent message. SessionPeer already
    // correlated replies (env.re matched a pending request) before reaching
    // here — what arrives now is unsolicited and needs the LLM to react.
    // Inject as a user message so the model sees it as a turn input. Include
    // the `id` so the LLM can echo it via `agent_send(..., re=<id>)` when
    // replying (otherwise the sender's agent_request times out).
    if (!_pi) return;
    const bodyText = typeof env.body === "string" ? env.body : JSON.stringify(env.body);
    const header = `[agent-network] message from "${env.from}" (id=${env.id}${env.re ? `, re=${env.re}` : ""}):`;
    const footer = env.re
      ? "(This is a reply to a previous message of yours.)"
      : `(If a reply is expected, call agent_send with to="${env.from}" and re="${env.id}".)`;
    _pi.sendUserMessage(`${header}\n${bodyText}\n\n${footer}`);
  });

  // After failover (leader died, we re-elected): the new broker's peers map
  // starts fresh, but our cached `_sessionPeerCount` is stale. Re-seed it so
  // surviving peers don't carry the pre-failover count forever.
  peer.onReconnect(() => {
    _refreshSessionPeerCount(peer, ctx);
  });

  try {
    const assigned = await peer.start();
    _sessionPeer = peer;
    _sessionName = sessionName;
    _sessionPeerCount = 1;  // optimistic — overwritten by list_peers below
    // Broker broadcasts `peer_joined` only to existing peers when a new one
    // arrives — the newcomer doesn't get retroactive joined events. Ask the
    // broker for the live peer list to seed the count correctly on join.
    _refreshSessionPeerCount(peer, ctx);
    saveLocalConfig(cwd, { agent_name: assigned, session_name: sessionName });
    ctx.ui.notify(
      `[remote-pi] Joined session "${sessionName}" as "${assigned}" (${peer.currentRole()})`,
      "info",
    );
    _refreshFooter(ctx);
  } catch (err) {
    ctx.ui.notify(`[remote-pi] join failed: ${String(err)}`, "error");
  }
}

async function _cmdLeave(ctx: Pick<ExtensionContext, "ui">): Promise<void> {
  if (!_sessionPeer) {
    ctx.ui.notify("[remote-pi] Not in any session.", "info");
    return;
  }
  await _sessionPeer.leave();
  const name = _sessionName;
  _sessionPeer = null;
  _sessionName = null;
  _sessionPeerCount = 0;
  ctx.ui.notify(`[remote-pi] Left session "${name}".`, "info");
  _refreshFooter(ctx);
}

async function _cmdRename(arg: string, ctx: Pick<ExtensionContext, "ui" | "cwd">): Promise<void> {
  const newName = arg.trim();
  if (!newName) {
    ctx.ui.notify("[remote-pi] Usage: /remote-pi rename <new-name>", "warning");
    return;
  }
  if (!_sessionPeer) {
    ctx.ui.notify("[remote-pi] Not in any session. Run /remote-pi join first.", "warning");
    return;
  }
  try {
    const assigned = await _sessionPeer.rename(newName);
    const cwd = "cwd" in ctx ? (ctx as ExtensionCommandContext).cwd : process.cwd();
    saveLocalConfig(cwd, { agent_name: assigned });
    ctx.ui.notify(`[remote-pi] Renamed to "${assigned}".`, "info");
  } catch (err) {
    ctx.ui.notify(`[remote-pi] rename failed: ${String(err)}`, "error");
  }
}

function _cmdSessions(ctx: Pick<ExtensionContext, "ui">): void {
  const sessions = listSessions();
  if (sessions.length === 0) {
    ctx.ui.notify("[remote-pi] No sessions found.", "info");
    return;
  }
  const lines = sessions.map((s) => {
    const live = sessionHasSock(s) ? "🟢" : "⚪";
    const me = s === _sessionName ? " (current)" : "";
    return `  ${live} ${s}${me}`;
  });
  ctx.ui.notify(`[remote-pi] Sessions:\n${lines.join("\n")}`, "info");
}

async function _cmdRelayToggle(ctx: Pick<ExtensionContext, "ui" | "cwd">): Promise<void> {
  if (_state === "idle") await _cmdStart(ctx);
  else await _cmdStop(ctx);
}

function _cmdRelayStatus(ctx: Pick<ExtensionContext, "ui">): void {
  _showStatus(ctx);
}

// ── routeClientMessage ────────────────────────────────────────────────────────

export function routeClientMessage(
  msg: ClientMessage,
  ctx: Pick<ExtensionContext, "abort">,
): void {
  // session_sync has its own internal guards — handle before the strict
  // peer/pi guard so a missing _pi doesn't drop the reply.
  if (msg.type === "session_sync") {
    _handleSessionSync(msg);
    return;
  }
  if (!_peerChannel || !_pi) return;
  switch (msg.type) {
    case "user_message":
      _currentTurnId = msg.id;
      _pi.sendUserMessage(msg.text);
      break;
    case "approve_tool":
      // Approval gate was removed (plano 10.2 revisado). Type kept in
      // ClientMessage for forward-compat with a future permissions model;
      // ignore silently if the app still sends it from an older build.
      break;
    case "cancel":
      ctx.abort();
      _peerChannel.send({ type: "cancelled", in_reply_to: msg.id, target_id: msg.target_id });
      break;
    case "ping":
      _peerChannel.send({ type: "pong", in_reply_to: msg.id });
      break;
    case "pair_request":
      // Already paired — ignore subsequent pair_request to maintain idempotency.
      // (Token is already consumed and peer is in peers.json.)
      break;
  }
}

// ── session_sync handler + helpers ────────────────────────────────────────────

function _handleSessionSync(
  msg: Extract<ClientMessage, { type: "session_sync" }>,
): void {
  if (!_peerChannel) return;

  if (_sessionStartedAt === null) {
    _peerChannel.send({
      type: "session_history",
      in_reply_to: msg.id,
      session_started_at: 0,
      events: [],
      eos: true,
      truncated: false,
    });
    return;
  }

  // Mirror semantics: always return the last N events. App SUBSTITUTES its
  // local cache with this response — no delta/since_ts logic.
  const serverLimit = _getSyncLimit();
  const requested = msg.limit ?? serverLimit;
  const effectiveLimit = Math.min(requested, serverLimit);  // server clamps

  const allEvents = _mapAgentMessagesToEvents(_messageBuffer);
  const slice = effectiveLimit > 0 ? allEvents.slice(-effectiveLimit) : [];
  const truncated = allEvents.length > effectiveLimit;

  _peerChannel.send({
    type: "session_history",
    in_reply_to: msg.id,
    session_started_at: _sessionStartedAt,
    events: slice,
    eos: true,
    truncated,
  });
}

function _stringifyContent(content: unknown): string {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  return content
    .map((c) => {
      if (!c || typeof c !== "object") return "";
      const block = c as { type?: string; text?: unknown };
      return block.type === "text" ? String(block.text ?? "") : "";
    })
    .join("");
}

/**
 * Maps SDK AgentMessage[] (UserMessage / AssistantMessage / ToolResultMessage)
 * into the flat SessionHistoryEvent[] shape consumed by the app.
 *
 * Caveats (see report): in_reply_to of agent_message is the *last* user_input
 * id seen in a linear scan — fine for typical conversational flow but not
 * a perfect reconstruction of multi-turn ordering when tools interleave.
 * Stable id for user_input is `sync_<timestamp>`.
 */
export function _mapAgentMessagesToEvents(
  messages: BufferMsg[],
): SessionHistoryEvent[] {
  const events: SessionHistoryEvent[] = [];
  let lastUserId: string | null = null;

  for (const m of messages) {
    const ts = typeof m.timestamp === "number" ? m.timestamp : 0;

    if (m.role === "user") {
      const id = `sync_${ts}`;
      lastUserId = id;
      events.push({
        ts,
        type: "user_input",
        id,
        text: _stringifyContent(m.content),
      });
    } else if (m.role === "assistant") {
      const content = Array.isArray(m.content) ? m.content : [];
      const usage = m.usage
        ? { input_tokens: m.usage.input ?? 0, output_tokens: m.usage.output ?? 0 }
        : undefined;
      for (const raw of content) {
        if (!raw || typeof raw !== "object") continue;
        const block = raw as { type?: string; text?: unknown; id?: unknown; name?: unknown; arguments?: unknown };
        if (block.type === "text") {
          const text = String(block.text ?? "");
          if (!text) continue;
          const ev: SessionHistoryEvent = {
            ts,
            type: "agent_message",
            in_reply_to: lastUserId ?? `sync_${ts}`,
            text,
            ...(usage ? { usage } : {}),
          };
          events.push(ev);
        } else if (block.type === "toolCall") {
          events.push({
            ts,
            type: "tool_request",
            tool_call_id: String(block.id ?? ""),
            tool: String(block.name ?? ""),
            args: (block.arguments as Record<string, unknown>) ?? {},
          });
        }
      }
    } else if (m.role === "toolResult") {
      const text = _stringifyContent(m.content);
      const tcid = String(m.toolCallId ?? "");
      events.push(
        m.isError
          ? { ts, type: "tool_result", tool_call_id: tcid, error: text }
          : { ts, type: "tool_result", tool_call_id: tcid, result: text },
      );
    }
  }

  return events;
}

// ── Standalone CLI ────────────────────────────────────────────────────────────

if (import.meta.url === `file://${process.argv[1]}`) {
  const [, , subcmd, ...cliArgs] = process.argv;
  if (subcmd === "list") {
    const peers = await listPeers();
    if (peers.length === 0) { console.log("[remote-pi] No peers"); }
    else { for (const p of peers) console.log(`• ${p.remote_epk.slice(0, 8)} — ${p.name}`); }
  } else if (subcmd === "revoke") {
    const shortid = (cliArgs[0] ?? "").trim();
    if (!shortid) {
      console.log("Usage: revoke <shortid>");
    } else {
      const peers = await listPeers();
      const matches = peers.filter((p) => p.remote_epk.startsWith(shortid));
      if (matches.length === 0) console.log(`No peer matching '${shortid}'`);
      else if (matches.length > 1) console.log(`Ambiguous: ${matches.map((p) => p.remote_epk.slice(0, 8)).join(", ")}`);
      else {
        const peer = matches[0]!;
        const { removePeer } = await import("./pairing/storage.js");
        await removePeer(peer.remote_epk);
        console.log(`Revoked: ${peer.name} (${peer.remote_epk.slice(0, 8)}…)`);
      }
    }
  } else if (subcmd === "set-relay") {
    const url = (cliArgs[0] ?? "").trim();
    if (!url) {
      console.log(`Usage: set-relay <url> (default: ${kDefaultRelayUrl})`);
    } else if (!isValidRelayUrl(url)) {
      console.log(`Invalid URL: ${url}. Must start with ws:// or wss://`);
    } else {
      saveConfig({ relay: url });
      console.log(`Relay set to ${url}`);
    }
  } else if (subcmd === "config") {
    const { url, source } = resolveRelayUrl();
    console.log(`Relay: ${url}\n  Source: ${source}`);
  } else {
    const edKp = await getOrCreateEd25519Keypair();
    const sessionName = process.cwd().split("/").slice(-2).join("/");
    const { url: relayUrl, source } = resolveRelayUrl();
    const roomId = roomIdForCwd(process.cwd());
    console.log(`[remote-pi] relay: ${relayUrl} (source: ${source}), room: ${roomId}`);
    void cliArgs;
    const stop = startQRRotation(edKp.publicKey, sessionName, roomId);
    process.once("SIGINT", () => { stop(); process.exit(0); });
  }
}
