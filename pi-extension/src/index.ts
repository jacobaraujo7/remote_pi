#!/usr/bin/env node
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
} from "@earendil-works/pi-coding-agent";
import { SettingsManager } from "@earendil-works/pi-coding-agent";
import { type Ed25519Keypair } from "./pairing/crypto.js";
import { buildQRUri, qrSession, renderQRAscii, clampPairTtlMs, TOKEN_TTL_MS } from "./pairing/qr.js";
import {
  addPeer,
  getOrCreateEd25519Keypair,
  KeyringUnavailableError,
  listOwnerPubkeys,
  listPeers,
  removePeer,
  type PeerRecord,
} from "./pairing/storage.js";
import { MeshClient } from "./mesh/client.js";
import { SelfRevoke } from "./mesh/self_revoke.js";
import type {
  ClientMessage,
  PairErrorCode,
  ServerMessage,
  SessionHistoryEvent,
  ThinkingLevel,
  WireImage,
} from "./protocol/types.js";
import { RelayClient, RoomAlreadyOpenError } from "./transport/relay_client.js";
import { PlainPeerChannel } from "./transport/peer_channel.js";
import { roomIdFor } from "./rooms.js";
import { registerAgentTools } from "./session/tools.js";
import { formatPeerInventory } from "./session/peer_inventory.js";
import { MeshNode } from "./session/mesh_node.js";
import {
  handleSessionCompact,
  handleSessionNew,
  handleModelSet,
  handleThinkingSet,
  handleListModels,
  type ActionCtx,
} from "./actions/handlers.js";
import { ensureModelRegistry } from "./actions/registry.js";
import {
  ensureGlobalDirs,
  LOCAL_SESSION_NAME,
  sessionAuditPath,
  sessionSockPath,
  skillsDir,
} from "./session/global_config.js";
import { acquireCwdLock, type AcquiredLock } from "./session/cwd_lock.js";
import { addDaemon, listDaemons, removeDaemon } from "./daemon/registry.js";
import { callSupervisor, supervisorOnline, SupervisorOfflineError } from "./daemon/client.js";
import type { ControlRequest, DaemonInfo } from "./daemon/control_protocol.js";
import { EXIT_DAEMON_FRESH_SESSION } from "./daemon/rpc_child.js";
import { installService, uninstallService, linkCliBinaries, unlinkCliBinaries, LAUNCHD_LABEL, SYSTEMD_UNIT, WINDOWS_TASK_NAME } from "./daemon/install.js";
import {
  defaultAgentName,
  effectiveAutoStartRelay,
  loadLocalConfig,
  localConfigExists,
  saveLocalConfig,
} from "./session/local_config.js";
import { runSetupWizard, type WizardUI } from "./session/setup_wizard.js";
import { updateFooter, type FooterState } from "./ui/footer.js";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { mkdirSync, copyFileSync, existsSync, unlinkSync, readFileSync, writeFileSync, realpathSync } from "node:fs";
import { createInterface } from "node:readline";
import { spawnSync } from "node:child_process";
import { hostname, tmpdir } from "node:os";
import {
  kDefaultRelayUrl,
  resolveRelayUrl,
  saveConfig,
  isValidRelayUrl,
  isWebSocketScheme,
  toWebSocketUrl,
} from "./config.js";

// ── State machine ─────────────────────────────────────────────────────────────
//
// Pre-2026-05-23: `idle` → `started` → `paired` (one owner at a time, gate-kept
// by `_appPeerId`/`_peerChannel` singletons). The transition to `paired` was
// what unblocked the app from sending application messages.
//
// Now: `idle` → `started`. The `paired` state is a derived metric
// (`_activePeers.size > 0`) — N owners can be connected at once, each with
// its own `PlainPeerChannel` in `_activePeers`. Plan/24 W2D ("multi-channel
// broadcast"): pairing a second device no longer disconnects the first, and
// every connected owner receives the same agent stream in parallel.

export type RemoteState = "idle" | "started";

let _state: RemoteState = "idle";
let _relay: RelayClient | null = null;

/** Relay connectivity as seen by an RPC client (Cockpit). Derived from
 *  `_state` + `_relay`: "disconnected" = relay off (idle); "connected" = live
 *  WS; "reconnecting" = was on, WS dropped, retrying. Surfaced via the
 *  `remote-pi:relay-state` custom message (see `_emitRelayState`). */
export type RelayConnectivity = "connected" | "reconnecting" | "disconnected";

/** Last `RelayConnectivity` emitted, for change-dedup. Starts "disconnected"
 *  (the process boots with the relay down). */
let _lastRelayStatus: RelayConnectivity | null = null;

/** Sentinel prefix for a transparent control message an RPC client sends on the
 *  `prompt` channel (stdin). The `input` hook intercepts it, runs the action,
 *  and swallows it (`action:"handled"`) so it never becomes an LLM turn or a
 *  transcript entry. Starts with NUL so it can't collide with real user input
 *  and doesn't begin with "/" (which would route to the command parser). */
export const CTRL_PREFIX = "\x00remote-pi-ctrl:";
let _relayUrl: string | null = null;  // URL used by current _relay connection
/**
 * Owners currently connected via the relay. Key = app peer pubkey (Ed25519,
 * base64 standard); value = the dedicated PlainPeerChannel routing messages
 * to/from that owner.
 *
 * Operational notes:
 *   - Adding/removing entries is exclusively in `_attachPeerChannel` and
 *     `_detachPeerChannel` (or `_goIdle` for the bulk teardown). Don't mutate
 *     directly elsewhere — those helpers keep the footer/log/state in sync.
 *   - `paired` UX state is `_activePeers.size > 0`. The footer and the
 *     `/remote-pi status` output both derive from this.
 */
const _activePeers = new Map<string, PlainPeerChannel>();
let _peerShort = "";  // shortid of the most recently attached peer (UX hint only)

let _myRoomId: string | null = null;   // this Pi's room id (derived from cwd)
// Plan/28 Wave D.1: `thinking` published alongside `model` so the app's
// Quick Actions sheet hydrates the thinking segmented control on first
// open instead of starting null. The SDK fires `thinking_level_select`
// on every change (initial load + user toggle), mirrored to room_meta
// the same way model is — apps subscribe to one channel for both.
let _myRoomMeta: { name: string; cwd: string; model?: string; thinking?: ThinkingLevel; working?: boolean } | null = null;
let _currentModel: string | undefined = undefined;  // last-known model name
let _currentThinking: ThinkingLevel | undefined = undefined;  // last-known thinking level

// ── Agent-network session (plano 19) ──────────────────────────────────────────
// MeshNode owns both the local UDS mesh (SessionPeer) and the optional
// cross-PC relay bridge (BrokerRemote + PiForwardClient). The bridge is
// attached via `_meshNode.attachBridge()` once the relay WS is up and this
// Pi is the leader; MeshNode re-attaches it across UDS failovers.
let _meshNode: MeshNode | null = null;
let _sessionName: string | null = null;
let _sessionPeerCount = 0;
// Set true by the `session_shutdown` handler. The daemon auto-init defers the
// connect (`setTimeout(_cmdRoot, 0)`) and connecting is async, so a shutdown can
// land WHILE this instance's `_cmdRoot` is still mid-connect (`_meshNode` not
// assigned yet) — the handler would then find nothing to close, and the connect
// would finish afterwards as an unreachable ghost. `_cmdRoot`/`_cmdJoin` check
// this flag after each await and abort (closing any peer that already connected)
// so a torn-down instance never lingers on the broker. Per-module (jiti
// re-evaluates the module on every session replacement), so the replacement
// instance starts fresh with `_disposed = false`.
let _disposed = false;
// True once the auto-init has run on the first session_start for this
// process. Prevents re-running on session replacements (those re-init via
// the _disposed re-arm path above). The session_start handler below auto-starts
// remote-pi for ANY session whose local config has auto_start_relay (default
// true) — interactive AND daemon — instead of only REMOTE_PI_DAEMON=1.
let _autoInited = false;

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
  peer: MeshNode,
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

/**
 * Cache the active model name and fan it out to subscribed apps via a
 * `room_meta_update`. The relay push is a no-op when the room isn't up yet —
 * the next `room_meta` hello carries the cached value instead. Shared by the
 * `model_select` event and the connect/turn-start seeding, so a daemon that
 * just runs its DEFAULT model still reports it: `model_select` only fires on an
 * explicit set/cycle (never on settings load), so default-model daemons would
 * otherwise never surface their model.
 */
function _setCurrentModel(name: string): void {
  _currentModel = name;
  if (_myRoomMeta) _myRoomMeta = { ..._myRoomMeta, model: name };
  if (_relay && _myRoomId) {
    _relay.sendControl({ type: "room_meta_update", room_id: _myRoomId, meta: { model: name } });
  }
}

/**
 * Plan/32: publish the `working` flag as room_meta (raw, no debounce — the
 * app debounces). Same shape as model/thinking updates. Used by turn_start/end
 * AND by the compaction handlers: `compact()` doesn't run a turn (it
 * disconnects the agent + aborts, emitting compaction_start, NOT turn_start),
 * so room_meta.working must be bracketed manually around compaction.
 */
function _publishWorking(working: boolean): void {
  if (_myRoomMeta) _myRoomMeta = { ..._myRoomMeta, working };
  if (_relay && _myRoomId) {
    _relay.sendControl({ type: "room_meta_update", room_id: _myRoomId, meta: { working } });
  }
}

// ── Cross-PC mesh wiring (plan/25 Wave B/C) ───────────────────────────────────

/**
 * Hand the live relay to MeshNode so it can bring up the cross-PC bridge
 * (BrokerRemote + sibling discovery) — but only when this Pi is the leader
 * (broker host). MeshNode is idempotent + re-attaches across UDS failovers,
 * so this is safe to call from `_cmdStart`, relay reconnect, or SelfRevoke.
 * No-op until the relay WS + cached identity are both present.
 */
function _attachBridgeIfReady(): void {
  if (!_meshNode || !_relay || !_relayUrl || !_cachedEd25519) return;
  void _meshNode
    .attachBridge({ relay: _relay, relayUrl: _relayUrl, keypair: _cachedEd25519 })
    .catch(() => { /* best-effort — UDS mesh works regardless */ });
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
    // `devicePaired` now reflects "any owner currently attached" — picks one
    // shortid representatively (multi-owner UX detail surfaces in the
    // `/remote-pi status` line, not the footer slot).
    devicePaired: _anyPeerActive() ? _peerShort : undefined,
    hasPairings: _hasGlobalPairings,
    agentName: _meshNode?.name(),
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
  /** Plan/32: pre-compaction token count, set on the synthetic
   *  `role:"compaction"` marker pushed in `session_compact`. */
  tokensBefore?: number;
};
let _messageBuffer: BufferMsg[] = [];

/** Test-only override of the message buffer. */
/**
 * Test-only: emulate what `/remote-pi` does on the returning-user path
 * (join the local mesh, then start the relay) without touching the FS for
 * a `localConfigExists()` lookup. Lets tests bring the relay up without
 * mocking the wizard or the local config storage.
 *
 * Typed loosely to accept any ctx shape with `ui.notify` + `cwd` — the
 * unit tests use minimal mocks that don't satisfy the full
 * `ExtensionContext` interface.
 */
export async function _connectForTest(ctx: unknown): Promise<void> {
  const real = ctx as Parameters<typeof _cmdJoin>[0];
  await _cmdJoin(real);
  await _cmdStart(real);
}

/** Test-only: tear everything down (mirrors `/remote-pi stop`). */
export async function _stopForTest(ctx: unknown): Promise<void> {
  await _cmdStop(ctx as Parameters<typeof _cmdStop>[0]);
}

/** Test-only: read/reset the `_disposed` flag. In production it's per-module
 *  and never reset (a disposed instance is discarded), but tests share one
 *  module across cases, so they reset it to avoid cross-test pollution. */
export function _getDisposedForTest(): boolean { return _disposed; }
export function _setDisposedForTest(v: boolean): void { _disposed = v; }

/** Test-only: true when this instance holds a live local-mesh node. */
export function _hasMeshNodeForTest(): boolean { return _meshNode !== null; }

/** Test-only: the effective (possibly `#N`-suffixed) name the cwd-lock reserved. */
export function _getLockedNameForTest(): string | null { return _lockedName; }

/** Test-only: release + clear the cwd lock (the lock normally survives stop). */
export function _resetCwdLockForTest(): void {
  try { _cwdLock?.release(); } catch { /* ignored */ }
  _cwdLock = null;
  _lockedName = null;
}

/**
 * Test-only: relay-only startup, no UDS mesh join. Replaces the old
 * `remote-pi relay start` handler that some tests captured to bring up
 * the relay in isolation (e.g. ping/pong tests that don't care about the
 * agent-network broker).
 */
export async function _startRelayForTest(ctx: unknown): Promise<void> {
  await _cmdStart(ctx as Parameters<typeof _cmdStart>[0]);
}

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

/** Test-only: read the active turn id used for plain `cancel` routing. */
export function _getCurrentTurnIdForTest(): string | null {
  return _currentTurnId;
}

/** Test-only: override the bound AgentSession so a spy can capture the
 *  content handed to `sendUserMessage` (plan/30 multimodal ingest). */
export function _setPiForTest(pi: unknown): void {
  _pi = pi as typeof _pi;
}

/**
 * Persist a model change to the PROJECT settings (`<cwd>/.pi/settings.json`) so
 * a model picked from the app survives a Pi/daemon restart. `pi.setModel` only
 * sets the LIVE model — on the next restart a fresh session reads the saved
 * default and reverts (the reported bug). We write the PROJECT scope, NOT
 * global, deliberately: the SDK merges global←project with PROJECT winning
 * (`SettingsManager`), so a folder that already has a project default (every
 * created daemon does) would shadow a global write like the TUI's. Project
 * scope is also correct for a fleet — each daemon keeps its own model rather
 * than leaking one default globally.
 *
 * Read-merge-write + best-effort: preserves other keys and never throws (a
 * settings write must not fail the live model change, which already applied).
 */
function _persistModelDefault(provider: string, modelId: string): void {
  try {
    const path = join(process.cwd(), ".pi", "settings.json");
    let obj: Record<string, unknown> = {};
    try {
      const parsed = JSON.parse(readFileSync(path, "utf8")) as unknown;
      if (parsed && typeof parsed === "object") obj = parsed as Record<string, unknown>;
    } catch { /* no existing/parseable file → start fresh */ }
    obj["defaultProvider"] = provider;
    obj["defaultModel"] = modelId;
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, JSON.stringify(obj, null, 2));
  } catch { /* best-effort — model change already applied live */ }
}

// Per-turn messaging state
let _currentTurnId: string | null = null;

// Module-level pi reference
let _pi: ExtensionAPI | null = null;

let _stopAutoListener: (() => void) | null = null;

// Cached keypair (loaded once, reused across start/pair cycles)
let _cachedEd25519: Ed25519Keypair | null = null;

// Mesh-membership poller (plan/24 Wave 3). Lives across the relay
// connection lifecycle: started in _cmdStart after the WS is up, stopped
// in _goIdle when the relay is torn down.
let _selfRevoke: SelfRevoke | null = null;

// Per-cwd lock acquired by the first `/remote-pi` invocation in this
// process. Holds the UDS socket open until the process exits (OS auto-
// releases on crash too). Stays held across `/remote-pi stop` cycles —
// only released when the Node process itself dies.
let _cwdLock: AcquiredLock | null = null;
// Effective mesh name this instance locked. Equals the configured/derived name,
// OR a `#N`-suffixed variant when another agent already holds that (cwd, name)
// in this folder (same-name agents coexist instead of being refused). `_cmdJoin`
// registers under this name; the broker confirms it (and may bump it again under
// a live race). Null until the lock is acquired.
let _lockedName: string | null = null;

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

/**
 * Public state-snapshot helper. Returns the derived UX state, not the raw
 * `_state` enum: the W2D refactor collapsed the internal machine to
 * `idle | started` and made `paired` a derived metric
 * (`_activePeers.size > 0`). Tests and the footer keep the three-state
 * mental model via this getter.
 */
export function _getState(): "idle" | "started" | "paired" {
  if (_state === "idle") return "idle";
  return _activePeers.size > 0 ? "paired" : "started";
}

/** Test-only: number of owners currently attached via PlainPeerChannel. */
export function _getActivePeerCountForTest(): number {
  return _activePeers.size;
}

/** Test-only: true if a specific peer (base64 std) has an attached channel. */
export function _hasActivePeerForTest(appPeerIdStd: string): boolean {
  return _activePeers.has(appPeerIdStd);
}


// ── Multi-channel helpers ─────────────────────────────────────────────────────

/**
 * Sends `msg` to every currently-attached owner channel. The default
 * dispatch for application-level events that are part of "the agent
 * session is doing X" (agent_chunk, tool_request, tool_result, agent_done,
 * user_input mirror, room_meta_update, etc.) — all paired devices see the
 * same stream.
 *
 * Per-request responses (e.g. `session_history` answering a specific
 * `session_sync` query, or `pair_ok` answering `pair_request`) must NOT
 * use this — they go to the sender channel directly.
 */
function _broadcastToActive(msg: ServerMessage): void {
  for (const ch of _activePeers.values()) {
    try { ch.send(msg); } catch { /* best-effort per channel */ }
  }
}

/** Returns true when at least one owner is attached. Derived `paired` UX. */
function _anyPeerActive(): boolean {
  return _activePeers.size > 0;
}

/**
 * Adds an owner's channel to `_activePeers`. Also updates the UX hint
 * `_peerShort` (last-attached shortid) so the footer + status can pick
 * a representative device when only one is connected.
 */
function _attachPeerChannel(appPeerId: string, channel: PlainPeerChannel): void {
  _activePeers.set(appPeerId, channel);
  _peerShort = appPeerId.slice(0, 8);
}

/** Detaches a single owner's channel + removes it from the map. Used by
 *  `_onPeerDisconnect`, `_cmdRevoke`, and the SelfRevoke callback. */
function _detachPeerChannel(appPeerId: string): void {
  const ch = _activePeers.get(appPeerId);
  if (!ch) return;
  try { ch.detach(); } catch { /* best-effort */ }
  _activePeers.delete(appPeerId);
  if (_peerShort === appPeerId.slice(0, 8)) {
    // Pick a different remaining peer for the UX hint, or clear when none.
    const next = _activePeers.keys().next().value;
    _peerShort = next ? next.slice(0, 8) : "";
  }
}

// ── Display-name helpers ──────────────────────────────────────────────────────

/**
 * Resolves the name this Pi shows to the mobile app and the relay's
 * `room_meta.name`. Single source of truth for "what does this Pi call
 * itself when talking to others".
 *
 * Resolution order:
 *   1. Broker-assigned name (when this Pi is on the local UDS mesh) — may
 *      carry a `#N` suffix from a name collision. Matches what other
 *      agents see, so the mobile UI shows the exact same string.
 *   2. `agent_name` from `<cwd>/.pi/remote-pi/config.json` — set by the
 *      wizard on first run; this is "the name the user configured".
 *   3. `defaultAgentName(cwd)` (parent/folder) — fallback when no config
 *      exists yet and the mesh hasn't been joined.
 *
 * Pre-2026-05-23 callers computed `cwd.split('/').slice(-2).join('/')`
 * inline at three different sites (pair_ok, room_meta, QR URI); this
 * helper consolidates them and lifts the user's configured name above
 * the raw cwd path.
 */
function _displayName(cwd: string): string {
  if (_meshNode) return _meshNode.name();
  const local = loadLocalConfig(cwd);
  return local.agent_name || defaultAgentName(cwd);
}

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
  // Broadcast bye to every still-attached owner so each app surfaces
  // "offline" immediately instead of waiting ~50s for a ping miss.
  if (byeReason && _state !== "idle" && _anyPeerActive()) {
    _broadcastToActive({ type: "bye", reason: byeReason });
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

  // Tear down every per-owner channel and clear the map.
  for (const ch of _activePeers.values()) {
    try { ch.detach(); } catch { /* best-effort */ }
  }
  _activePeers.clear();
  _peerShort = "";
  _currentTurnId = null;

  _relay?.close();
  _relay = null;
  _relayUrl = null;

  // Stop the mesh poller — it's bound to the relay-up lifecycle so a new
  // _cmdStart will spin up a fresh instance (with potentially a new relay
  // URL if the user changed it via /remote-pi relay url).
  _selfRevoke?.stop();
  _selfRevoke = null;

  // Cross-PC routing relies on _relay being up; tear it down here too.
  _meshNode?.detachBridge();

  // Preserve _sessionStartedAt + _messageBuffer across stop/start cycles.
  // The Pi agent session outlives the relay connection — `message_end` keeps
  // firing for terminal turns even while idle, and the buffer must survive
  // so those turns appear in the next session_sync. Only a Pi process
  // restart resets these (init-time values).

  _state = "idle";
  _refreshFooter();
  _emitRelayState();  // → disconnected
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

  // Detach every per-owner channel — relay is gone, none can route. The
  // auto-listener re-attaches owners after `_attemptReconnect` succeeds
  // (via the same known-peer + pair_request paths used on first connect).
  for (const ch of _activePeers.values()) {
    try { ch.detach(); } catch { /* best-effort */ }
  }
  _activePeers.clear();
  _peerShort = "";
  _currentTurnId = null;

  _relay = null;  // _relayUrl preserved for retry

  // Cross-PC routing relies on _relay; bring it down. Will be re-instated
  // by _attemptReconnect on success.
  _meshNode?.detachBridge();

  _state = "started";
  _refreshFooter();
  _emitRelayState();  // → reconnecting

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
  // _relayUrl is stored in canonical http(s):// form — convert at the
  // WS boundary, same as _cmdStart.
  const relay = new RelayClient(toWebSocketUrl(url), edKp);

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

  // Plan/25 Wave B/C: relay is back; bring cross-PC routing back online.
  _attachBridgeIfReady();

  // _state stays "started"; peer reconnect (if previously paired) flows
  // through _installAutoListener → _findKnownPeer → _promoteToPaired
  // automatically when the app sends any inner.
  _emitRelayState();
}

// ── Relay state event + transparent control channel (Cockpit toggle) ─────────

/** Current relay connectivity, derived from `_state` + `_relay`. */
function _relayStatus(): RelayConnectivity {
  if (_getState() === "idle") return "disconnected";
  return _relay ? "connected" : "reconnecting";
}

/**
 * Emit the `remote-pi:relay-state` custom message so an RPC client (Cockpit)
 * can render a relay on/off indicator. Pure data (`display:false`) — never
 * shown in the transcript. De-duped on the connectivity value; pass
 * `force=true` to answer an explicit `relay:status` query regardless.
 */
function _emitRelayState(force = false): void {
  const status = _relayStatus();
  if (!force && status === _lastRelayStatus) return;
  _lastRelayStatus = status;
  _pi?.sendMessage({
    customType: "remote-pi:relay-state",
    content: `Relay ${status}`,
    details: {
      status,
      connected: status === "connected",
      ...(_relayUrl ? { relayUrl: _relayUrl } : {}),
      ...(_myRoomId ? { room: _myRoomId } : {}),
    },
    display: false,
  });
}

/** Minimal ctx for relay start/stop driven by a control message (no command
 *  ctx is available in the `input` hook). cwd matches the daemon's launch dir,
 *  so the derived relay room is identical to the one `_cmdStart` first used. */
function _controlCtx(): Pick<ExtensionContext, "ui" | "cwd"> {
  return {
    ui: _headlessUi(),
    cwd: process.cwd(),
  } as unknown as Pick<ExtensionContext, "ui" | "cwd">;
}

/**
 * `ui.notify` for headless contexts (daemon auto-init + control channel). There
 * is no TUI, and the RPC client (Cockpit) already gets everything it needs via
 * structured events (`remote-pi:relay-state`, `remote-pi:name-assigned`,
 * room_meta) — so routine INFO chatter would just pollute the client's captured
 * stderr. We drop info and forward only warnings/errors (kept for the
 * supervisor's journal / genuine failures). The interactive Pi keeps its normal
 * footer/notify path — this only affects headless ctxs.
 */
function _headlessUi(): { notify: (msg: string, type?: "info" | "warning" | "error") => void } {
  return {
    notify: (msg: string, type?: "info" | "warning" | "error") => {
      if (type === "warning" || type === "error") process.stderr.write(`${msg}\n`);
    },
  };
}

/**
 * Handle a transparent control command from an RPC client (Cockpit), received
 * as a `CTRL_PREFIX`-tagged input the `input` hook swallowed. Toggles the relay
 * WITHOUT leaving the local mesh (relay-only: `_cmdStart` up / `_goIdle` down),
 * then emits the fresh state. `relay:status` just re-emits (no change) so the
 * client can sync its button after (re)attaching to the RPC stream.
 */
export async function _handleControl(cmd: string): Promise<void> {
  // `rename:<new-name>` carries an argument, so it's matched before the
  // fixed-verb switch. Renames the agent live (broker re-register + relay room
  // swap) WITHOUT restarting the process or losing the SDK session.
  if (cmd.startsWith("rename:")) {
    await _renameAgent(cmd.slice("rename:".length).trim());
    return;
  }
  switch (cmd) {
    case "relay:on":
      if (_getState() === "idle") await _cmdStart(_controlCtx());
      _emitRelayState(true);
      return;
    case "relay:off":
      if (_getState() !== "idle") _goIdle("peer_stop");
      _emitRelayState(true);
      return;
    case "relay:toggle":
      if (_getState() === "idle") await _cmdStart(_controlCtx());
      else _goIdle("peer_stop");
      _emitRelayState(true);
      return;
    case "relay:status":
      _emitRelayState(true);
      return;
    default:
      // Unknown control verb — ignore (forward-compat: a newer client may send
      // verbs an older extension doesn't know).
      return;
  }
}

/**
 * Rename the agent LIVE (plan/38/41), without restarting the process or losing
 * the SDK session/conversation. Touches two layers:
 *   1. **Broker (mesh)**: `MeshNode.rename` does a soft leave+rejoin → new
 *      address `<cwd>@<newName>` (broker may add `#N` on a same-(cwd,name)
 *      collision — we use the assigned result).
 *   2. **Relay room (App↔Pi)**: the room is keyed by `(cwd, name)`, so the new
 *      name = a new room. We cycle the relay (`_goIdle` → `_cmdStart`) so the
 *      room follows; the app re-keys the conversation onto the new tile (the
 *      inherent cost of room-per-name). Skipped when the relay was off.
 * Finally re-emits `remote-pi:name-assigned` so the Cockpit updates its label.
 *
 * The explicit name IS persisted (decision E only skips the runtime `#N`).
 */
async function _renameAgent(newName: string): Promise<void> {
  if (!newName) return;  // empty rename → no-op
  const ctx = _controlCtx();
  const cwd = process.cwd();
  saveLocalConfig(cwd, { agent_name: newName });

  if (!_meshNode) {
    // Not on the mesh yet — config persisted; applies on the next join.
    return;
  }

  // Relay room is derived from the name → cycle it so it follows. Tear down
  // first (also detaches the bridge) so the broker re-register below starts
  // clean; bring it back up after with the new name.
  const wasStarted = _getState() !== "idle";
  if (wasStarted) _goIdle("peer_stop");

  let assigned = newName;
  try {
    assigned = await _meshNode.rename(newName);  // broker soft rejoin
  } catch (err) {
    ctx.ui.notify(`[remote-pi] rename failed: ${String(err)}`, "error");
  }

  if (wasStarted && !_disposed) await _cmdStart(ctx);  // relay back up → roomIdFor(cwd, assigned)

  _pi?.sendMessage({
    customType: "remote-pi:name-assigned",
    content: assigned === newName
      ? `Mesh name: ${assigned}`
      : `Mesh name reassigned: "${newName}" → "${assigned}" (collision)`,
    details: { requested: newName, assigned, changed: assigned !== newName },
    display: false,
  });
}

/**
 * Per-owner disconnect callback. Fires when one specific owner's channel
 * detaches (e.g. relay told us the peer is gone). Other owners' channels
 * keep running — relay stays "started".
 *
 * Exported so tests can trigger the disconnect path for a specific peer.
 *
 * Backward-compat: a no-arg call (legacy tests / pre-W2D callers) falls
 * back to detaching the most recently attached peer, mirroring the old
 * singleton semantics.
 */
export function _onPeerDisconnect(appPeerId?: string): void {
  if (_state === "idle") return;
  const target = appPeerId ?? [..._activePeers.keys()].pop();
  if (!target) return;
  if (!_activePeers.has(target)) return;

  _detachPeerChannel(target);
  if (_anyPeerActive()) {
    // Other owners still attached — keep _currentTurnId so they continue
    // seeing the in-flight agent stream.
    _refreshFooter();
    return;
  }

  // No owner left. Conservatively clear the turn so the next pair_request
  // starts cleanly.
  _currentTurnId = null;
  _refreshFooter();
  _lastCtx?.ui.notify("[remote-pi] All app peers disconnected, listening for reconnect", "info");
  // Auto-listener stays up — same listener catches the reconnect on any peer.
}

/**
 * Attaches a new owner channel to the multi-owner set. Replaces the
 * pre-W2D singleton `_promoteToPaired` which set `_state = "paired"` and
 * a single `_peerChannel`. The relay state remains `started`; pairing
 * status is derived from `_activePeers.size`.
 *
 * Idempotent for the same `appPeerId` (re-attaching tears down the prior
 * channel and installs a fresh one — covers reconnect from the same
 * device without leaking listeners).
 */
function _attachOwner(
  relay: RelayClient,
  appPeerId: string,
  peerName: string,
  firstInner?: ClientMessage,
): PlainPeerChannel {
  const peerShort = appPeerId.slice(0, 8);

  // Drop any stale channel for this owner before re-attaching.
  if (_activePeers.has(appPeerId)) _detachPeerChannel(appPeerId);

  const channel = new PlainPeerChannel(
    relay,
    appPeerId,
    _myRoomId ?? undefined,
    (msg) => _routeClientMessageFrom(channel, msg, _lastCtx ?? _noopCtx),
    () => _onPeerDisconnect(appPeerId),
  );

  _attachPeerChannel(appPeerId, channel);
  _refreshFooter();

  _lastCtx?.ui.notify(
    `[remote-pi] Owner attached: peer=${peerShort}, name=${peerName} ` +
    `(${_activePeers.size} active)`,
    "info",
  );

  if (firstInner) {
    // The PlainPeerChannel listener fired on the same line that triggered
    // attachment in some flows; we route explicitly here too to ensure the
    // inner reaches the handler exactly once.
    void firstInner;
  }
  return channel;
}

// ── Auto-listener ─────────────────────────────────────────────────────────────
//
// Installed while in 'started' state. Decodes the outer envelope as
// base64(JSON) and dispatches per sender peer_id:
//   • Sender already in `_activePeers` → ignored here (the per-owner
//     PlainPeerChannel listens on the same relay event and handles its own
//     traffic via its `remotePeerId` filter)
//   • `pair_request` from a new peer → validate token, persist peer, send
//     pair_ok/pair_error, attach a new channel
//   • Non-pair message from a known peer (peers.json) without an active
//     channel yet → attach + route the inner (reconnect path)
//   • Anything else (unknown peer + non-pair) → emit `error: unknown_peer`

function _installAutoListener(relay: RelayClient): () => void {
  const onMsg = async (line: string) => {
    let outer: { peer?: string; ct?: string };
    try { outer = JSON.parse(line) as { peer?: string; ct?: string }; }
    catch { return; }

    if (!outer.peer || !outer.ct) return;

    if (_state !== "started") return;
    // Already-attached owners: their PlainPeerChannel handles routing.
    if (_activePeers.has(outer.peer)) return;

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

    // Reconnect path: known peer (peers.json) without an active channel
    // sends a non-pair message → attach + route through the new channel.
    // See pairing.md §Reconexão.
    const known = await _findKnownPeer(appPeerId);
    if (known) {
      const channel = _attachOwner(relay, appPeerId, known.name);
      // The PlainPeerChannel listener for this owner won't have seen the
      // line that triggered the attach (we already consumed it); route
      // it explicitly via the new channel so the sender gets a reply.
      _routeClientMessageFrom(channel, inner, _lastCtx ?? _noopCtx);
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

/**
 * Plan/27 Wave A: lazily resolve the pi-extension package version from
 * disk so the `pair_ok.harness.version` field reflects what's actually
 * shipped. The lookup is best-effort — a parse failure (or running this
 * file out-of-tree) falls back to "0.0.0" which is still semver-valid
 * and the app tolerates it. Cached at module load.
 */
function _readExtensionVersion(): string {
  try {
    const here = fileURLToPath(import.meta.url);
    // dist/index.js → ../package.json. src/index.ts under tsx → also one level up.
    const pkgPath = join(here, "..", "..", "package.json");
    const pkg = JSON.parse(readFileSync(pkgPath, "utf8")) as { version?: string };
    return typeof pkg.version === "string" ? pkg.version : "0.0.0";
  } catch {
    return "0.0.0";
  }
}
const _HARNESS = {
  name: "Pi coding agent",
  version: _readExtensionVersion(),
} as const;
const _HOSTNAME = hostname();

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
      code === "token_expired"  ? "Ephemeral token expired. Generate a new QR with /remote-pi pair."
      : code === "token_consumed" ? "Token already consumed by another pair_request."
      : "Token was not issued by this Pi.";
    sendError(code, msg);
    return;
  }

  const pairedAt = new Date().toISOString();
  try {
    await addPeer({
      name: inner.device_name,
      remote_epk: appPeerId,
      paired_at: pairedAt,
    });
    _refreshPairingsCache();
  } catch (err) {
    sendError("internal_error", `Failed to persist peer: ${String(err)}`);
    return;
  }

  const cwd = _lastCtx && "cwd" in _lastCtx
    ? (_lastCtx as ExtensionCommandContext).cwd
    : process.cwd();
  // Prefer the user-configured agent_name (with broker suffix when on the
  // mesh) over the legacy parent/folder path — matches what the user sees
  // in the terminal title and in /remote-pi status.
  const sessionName = _displayName(cwd);

  _attachOwner(relay, appPeerId, inner.device_name);

  sendInner({
    type: "pair_ok",
    in_reply_to: inner.id,
    session_name: sessionName,
    session_started_at: _sessionStartedAt ?? Date.now(),
    // App uses this to address subsequent inner messages to the right room
    // when this Pi runs alongside others with the same epk. Defensive fallback
    // to roomIdFor(cwd, name) covers the edge case where pair_request lands
    // before _cmdStart could set _myRoomId (shouldn't happen in practice) —
    // and stays plan/41-consistent (same (cwd, name) derivation as the announce).
    room_id: _myRoomId ?? roomIdFor(cwd, sessionName),
    // Plan/27 Wave A — surface the host coding-agent identity + machine
    // hostname so the app can render a meaningful device row (and tell
    // two PCs apart even when nicknames collide).
    harness: _HARNESS,
    hostname: _HOSTNAME,
  });

  // Notify local RPC clients (e.g. Cockpit) that pairing completed, so they can
  // close the QR screen and show the new device. Pure data event (display:false)
  // — still emitted to the RPC stdout via the session stream.
  _pi?.sendMessage({
    customType: "remote-pi:paired",
    content: `Paired with ${inner.device_name}`,
    details: { name: inner.device_name, peerId: appPeerId, pairedAt },
    display: false,
  });
}

// ── Extension factory (default export) ───────────────────────────────────────

// Stores most recent command context so the auto-listener can use ui.notify.
// NOTE: this is a CAPTURED command ctx — the SDK marks it stale after a
// session replacement (newSession/fork/switch/reload). We re-capture it via
// `withSession` when WE drive a newSession (see the session_new dispatch).
let _lastCtx: Pick<ExtensionContext, "ui" | "abort" | "cwd"> | null = null;
// Freshest base ExtensionContext, re-captured on EVERY `session_start`
// (startup/new/fork/reload/resume). The session_start ctx is always bound to
// the CURRENT session, so compact + cancel (base-ctx methods) routed through
// here never hit a stale ctx — regardless of who triggered the replacement
// (an app Quick Action OR a `/new` typed in the Pi TUI). It carries only
// base-ctx methods (no newSession — that's command-ctx only), so command ops
// keep using `_lastCtx`.
let _lastEventCtx: Pick<ExtensionContext, "compact" | "abort"> | null = null;
const _noopCtx = { ui: { notify: () => undefined }, abort: () => undefined };

// A single Pi process can load this extension TWICE in the SAME session:
// pi-supervisord launches each daemon child as `pi -e <dist>/index.js`, but if
// remote-pi is ALSO installed as a pi-package (auto-discovered from
// ~/.pi/agent/extensions or <cwd>/.pi/extensions), Pi loads it a second time
// for that same session. Both loads receive the same session-scoped `pi` and
// would re-run registerTool/registerCommand for identical names — a hard
// duplicate-registration conflict that crashes the daemon child on boot (see
// daemon/rpc_child.ts). Idempotent, first-load-wins: whichever load runs first
// does all the wiring; the duplicate is an inert no-op. A genuine session
// REPLACEMENT gets a FRESH `pi`, so re-registration for the new session still
// happens.
//
// We track "already wired" in a process-global WeakSet keyed by `pi` rather
// than by mutating the host SDK object. The two loads are DISTINCT module
// instances (the SDK's jiti loader uses moduleCache:false, and the `-e` path vs
// the installed path resolve to different files), so a module-level Set can't
// dedupe them; the WeakSet lives on `globalThis` under a `Symbol.for` key so
// both module instances resolve the SAME set. Keying weakly by `pi` records the
// fact without adding a foreign property to the API object and lets each `pi`
// be GC'd when its session ends (no leak).
const _APPLIED_REGISTRY_KEY = Symbol.for("remote-pi.extension.appliedRegistry");
function _appliedRegistry(): WeakSet<object> {
  const g = globalThis as typeof globalThis & { [_APPLIED_REGISTRY_KEY]?: WeakSet<object> };
  return (g[_APPLIED_REGISTRY_KEY] ??= new WeakSet<object>());
}

const extension: ExtensionFactory = (pi: ExtensionAPI): void => {
  const applied = _appliedRegistry();
  if (applied.has(pi)) return;  // this session's pi was already wired
  applied.add(pi);

  _pi = pi;

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
  // session network natively. Getter captures `_meshNode` live so the
  // tool always sees the current state.
  registerAgentTools(pi, () => _meshNode?.peer() ?? null);

  // Tool calls execute without prompting the remote user. The Pi SDK has no
  // native `requiresApproval` per tool, and a hardcoded gate (Bash/Edit/Write)
  // misfired on every custom tool from third-party packages. Approval will
  // come back when the Pi ecosystem ships a permissions convention. tool_result
  // is still forwarded so the app shows tool activity transparently.

  // Mirror input typed in the Pi terminal (or sent via RPC) to every
  // connected owner. 'extension' source is our own sendUserMessage call
  // from routeClientMessage, which already set _currentTurnId — skip to
  // avoid a double turnId.
  pi.on("input", (event) => {
    // Transparent control channel: a `CTRL_PREFIX`-tagged input from an RPC
    // client (Cockpit button) toggles the relay. Run it and SWALLOW the input
    // (`action:"handled"`) so it never reaches the LLM or the transcript.
    // Checked first, before the peer-broadcast path, and regardless of source.
    if (event.text.startsWith(CTRL_PREFIX)) {
      void _handleControl(event.text.slice(CTRL_PREFIX.length).trim());
      return { action: "handled" } as const;
    }
    if (!_anyPeerActive()) return;
    if (event.source === "extension") return;
    const turnId = `local_${randomUUID()}`;
    _currentTurnId = turnId;
    _broadcastToActive({ type: "user_input", id: turnId, text: event.text });
    return undefined;
  });

  // Track active model so the app can show it in the SessionTile (plano 18).
  // SDK fires model_select on settings load + every user switch. We cache the
  // friendly name and broadcast a room_meta_update so the relay can fan it
  // out to subscribed apps without needing a new pair.
  pi.on("model_select", (event) => {
    const m = event?.model as { name?: string; id?: string } | undefined;
    const modelName = m?.name ?? m?.id;
    if (!modelName) return;
    // Cache + fan out. Keeps the cached room_meta fresh so a future reconnect
    // carries the current model in its hello, and pushes a room_meta_update to
    // apps already subscribed.
    _setCurrentModel(modelName);
  });

  // Plan/28 Wave D.1: mirror model's room_meta_update path for thinking
  // level so the app hydrates the segmented control on first open instead
  // of starting null. SDK fires `thinking_level_select` on settings load
  // AND on every user toggle (matching `model_select`'s behavior), so
  // late-pairing apps see the current level via `room_meta_updated`.
  pi.on("thinking_level_select", (event) => {
    const level = event?.level as ThinkingLevel | undefined;
    if (!level) return;
    _currentThinking = level;
    if (_myRoomMeta) _myRoomMeta = { ..._myRoomMeta, thinking: level };
    if (!_relay || !_myRoomId) return;
    _relay.sendControl({
      type: "room_meta_update",
      room_id: _myRoomId,
      meta: { thinking: level },
    });
  });

  pi.on("message_update", (event) => {
    if (!_anyPeerActive() || !_currentTurnId) return;
    const ae = event.assistantMessageEvent;
    if (ae.type === "text_delta") {
      _broadcastToActive({ type: "agent_chunk", in_reply_to: _currentTurnId, delta: ae.delta });
    }
  });

  // Notify every connected owner that a tool is about to run (visibility
  // only, NOT approval). tool_execution_start fires before the tool
  // executes; tool_execution_end closes the loop with the result. Together
  // they render a "Tool running… done" timeline in each paired app.
  pi.on("tool_execution_start", (event) => {
    if (!_anyPeerActive()) return;
    _broadcastToActive({
      type: "tool_request",
      tool_call_id: event.toolCallId,
      tool: event.toolName,
      args: _enrichToolArgs(event.toolName, event.args),
    });
  });

  pi.on("tool_execution_end", (event) => {
    if (!_anyPeerActive()) return;
    // Stringify like the history mapper (same helper) so the live text == what
    // a session_sync replays for this tool. Raw `String(event.result)` turned
    // a content-array/object into "[object Object]" and the success branch sent
    // the object unstringified — both diverging from re-sync.
    const text = _stringifyToolResult(event.result);
    const msg: ServerMessage = event.isError
      ? { type: "tool_result", tool_call_id: event.toolCallId, error: text }
      : { type: "tool_result", tool_call_id: event.toolCallId, result: text };
    _broadcastToActive(msg);
  });

  // Cumulative session buffer fed via `message_end`, which fires once per
  // persisted message (user, assistant, toolResult) — same hook the SDK uses
  // to persist to sessionManager (see agent-session.js:298-309). Pushing here
  // accumulates the whole session over time, so session_sync can replay every
  // turn — including turns initiated from the Pi terminal (source:"interactive")
  // or RPC. Previous impl overwrote on `agent_end` and lost everything but the
  // last turn (see diagnostics 14, 15).
  pi.on("message_end", (event) => {
    const m = event?.message as { role?: string; stopReason?: string; errorMessage?: string } | undefined;
    if (!m) return;
    if (m.role === "user" || m.role === "assistant" || m.role === "toolResult") {
      _messageBuffer.push(m as unknown as BufferMsg);
    }
    // Forward a failed turn to connected owners. Without this the app just
    // hangs with no response when the provider errors (e.g. the TUI's
    // "Provider finish_reason: error"): the SDK surfaces the failure as an
    // assistant message with stopReason "error" + an `errorMessage` (pi-ai).
    // `error` is an existing ServerMessage the app already renders — no
    // protocol/app change. `in_reply_to` ties it to the turn the app awaits.
    if (m.role === "assistant" && m.stopReason === "error" && _anyPeerActive()) {
      const message = typeof m.errorMessage === "string" && m.errorMessage
        ? m.errorMessage
        : "Provider error";
      const errMsg: ServerMessage = _currentTurnId
        ? { type: "error", in_reply_to: _currentTurnId, code: "provider_error", message }
        : { type: "error", code: "provider_error", message };
      _broadcastToActive(errMsg);
    }
  });

  pi.on("agent_end", () => {
    // Buffer is fed by `message_end`; here we only finalize the outbound
    // turn signal to every connected owner. No buffer mutation.
    if (!_anyPeerActive() || !_currentTurnId) return;
    _broadcastToActive({ type: "agent_done", in_reply_to: _currentTurnId });
    _currentTurnId = null;
  });

  // plan/34: the broker no longer gates delivery on busy state, so we no
  // longer notify it of turn lifecycle. Working state is still published as
  // room_meta over the relay (plan/32) below — that's independent of the
  // broker and drives the app's working indicator.
  pi.on("turn_start", (_event, ctx) => {
    // Late model hydration: if the model was still unknown at connect (resolved
    // lazily by the SDK), grab it on the first turn and fan it out — so a daemon
    // whose model only materialises at turn 1 still reports it to the app.
    if (!_currentModel) {
      try {
        const m = (ctx as Partial<ExtensionContext> & { getModel?: () => { name?: string; id?: string } | undefined }).getModel?.();
        const name = m?.name ?? m?.id;
        if (name) _setCurrentModel(name);
      } catch { /* defensive — never block a turn on a model lookup */ }
    }
    // Plan/32 Part B: publish working=true as room_meta (raw, no debounce —
    // the debounce lives in the app). Same shape as the model/thinking updates.
    if (_myRoomMeta) _myRoomMeta = { ..._myRoomMeta, working: true };
    if (_relay && _myRoomId) {
      _relay.sendControl({ type: "room_meta_update", room_id: _myRoomId, meta: { working: true } });
    }
  });
  pi.on("turn_end", () => {
    // Plan/32 Part B: publish working=false as room_meta (raw, no debounce).
    if (_myRoomMeta) _myRoomMeta = { ..._myRoomMeta, working: false };
    if (_relay && _myRoomId) {
      _relay.sendControl({ type: "room_meta_update", room_id: _myRoomId, meta: { working: false } });
    }
  });

  // Plan/32: compaction feedback. compact() doesn't run a turn, so bracket it
  // with working=true/false here. Returning void = no veto → default
  // compaction proceeds.
  pi.on("session_before_compact", () => {
    _publishWorking(true);
  });
  pi.on("session_compact", (event) => {
    const entry = event?.compactionEntry as { summary?: unknown; tokensBefore?: unknown } | undefined;
    const summary = typeof entry?.summary === "string" ? entry.summary : "";
    const tokensBefore = typeof entry?.tokensBefore === "number" ? entry.tokensBefore : 0;
    const ts = Date.now();
    // (2) Persist in history: the CompactionEntry never reaches _messageBuffer
    // via message_end (only user/assistant/toolResult), so push a synthetic
    // marker the mapper turns into a `compaction` event — survives session_sync.
    _messageBuffer.push({ role: "compaction", content: summary, timestamp: ts, tokensBefore });
    // (1) Live result to every connected owner.
    _broadcastToActive({ type: "compaction", summary, tokens_before: tokensBefore, ts });
    // (3) Working ends.
    _publishWorking(false);
  });

  // Re-capture the freshest base ctx on every session replacement so compact
  // never operates on a stale captured ctx — this is the fix for the
  // "stale after session replacement" crash when the app taps Compact after a
  // New session. Fires on startup/new/fork/reload/resume; the ctx is always
  // bound to the current session.
  pi.on("session_start", (_event, ctx) => {
    _lastEventCtx = ctx;
    // Rearm a reused-but-disposed instance. The session_shutdown teardown (below)
    // sets _disposed=true assuming the host re-evaluates THIS module fresh for the
    // replacement session, yielding a new instance with _disposed=false. Some hosts
    // instead REUSE the same module instance across ctx.newSession() — then the
    // _disposed latch is never cleared (nothing else resets it), so the relay never
    // reconnects and /remote-pi (via _cmdRoot) silently early-returns until a full
    // Pi restart. Clearing the latch + re-running the idempotent connect path
    // restores the relay automatically. No-op when a fresh instance IS created
    // (_disposed=false there → never fires) and at first boot.
    if (_disposed) {
      _disposed = false;
      void _cmdRoot(ctx);
    }
    // Auto-start remote-pi on a fresh boot when the cwd's local config has
    // auto_start_relay enabled (default true). Covers BOTH interactive
    // sessions (previously required typing /remote-pi each session) AND
    // headless daemons. We init here — on session_start — NOT via a
    // factory-return setTimeout(0): the SDK only calls bindCore() (which
    // replaces the throwing action-method stubs like pi.sendMessage) right
    // before emitting session_start, so a setTimeout(0) from the factory
    // raced it and crashed with "Extension runtime not initialized" inside
    // _emitRelayState -> sendMessage. session_start fires strictly AFTER
    // bindCore (agent-session bindExtensions), so pi.sendMessage is a real
    // function here. Guarded by _autoInited so session replacements re-init
    // only via the _disposed path above. Daemon mode has no interactive UI →
    // use the headless ctx; interactive sessions use the real session_start
    // ctx (has ui.notify + dialogs for the first-run wizard).
    if (!_autoInited) {
      // Daemon: always init (supervisor sets REMOTE_PI_DIRECT_CONFIG so a config
      // is present at process.cwd()). Interactive: only init when the
      // session_start ctx announces its cwd AND a local config already exists
      // there — never auto-pop the first-run wizard on session_start (a new dir
      // with no config stays idle until the user runs /remote-pi once). The
      // cwd guard also keeps tests with a minimal ctx (no cwd) from triggering
      // the wizard path.
      const isDaemon = process.env["REMOTE_PI_DAEMON"] === "1";
      const cwd = isDaemon ? process.cwd() : "cwd" in ctx ? ctx.cwd : undefined;
      if (cwd && localConfigExists(cwd) && effectiveAutoStartRelay(loadLocalConfig(cwd))) {
        _autoInited = true;
        const initCtx = isDaemon
          ? ({ ui: _headlessUi(), cwd: process.cwd() } as Pick<ExtensionContext, "ui" | "cwd">)
          : ctx;
        void _cmdRoot(initCtx);
      }
    }
  });

  // Tear down THIS instance's live handles when the SDK replaces the session
  // (switch_session / new / fork / reload / quit). This is the fix for the
  // "double mesh connection" the Cockpit hits when it restores a saved
  // conversation via switch_session on boot.
  //
  // Why it happens: the Pi SDK loads extensions through jiti with
  // `moduleCache: false`, so every session replacement re-evaluates THIS module
  // FRESH — a brand-new instance whose `_meshNode`, `_relay`, and `_cwdLock`
  // start back at null. The OUTGOING instance's broker socket, relay WS, and
  // cwd-lock UDS keep running regardless (module state is gone, but the OS
  // handles aren't). In daemon mode (REMOTE_PI_DAEMON=1, set by the Cockpit) the
  // fresh instance re-runs `_cmdRoot` on load, so without releasing the old
  // handles first we end up with TWO mesh peers under the same name on the
  // broker + two rooms on the relay. The per-cwd lock is meant to stop the
  // second connect, but its 500 ms connect-probe can miss the still-bound old
  // socket while the event loop is saturated at boot, fall through to the
  // stale-socket unlink path, and let the fresh instance bind a second lock.
  //
  // `session_shutdown` fires on the OUTGOING extension runner and is AWAITED by
  // the SDK (`teardownCurrent`) BEFORE the replacement runtime — and thus the
  // fresh extension instance — is created. Closing the mesh node, relay, and
  // lock here guarantees the next instance starts from a clean slate and stands
  // up exactly ONE connection bound to the restored session. Idempotent +
  // best-effort: every step is guarded so a partially-initialised instance
  // (e.g. shutdown lands mid-`_cmdRoot`) tears down without throwing.
  pi.on("session_shutdown", async () => {
    // Mark disposed FIRST so an in-flight `_cmdRoot`/`_cmdJoin` (the deferred
    // daemon connect) aborts instead of finishing as a ghost after we've torn
    // down — the race that left a mute `Backoffice` behind when the Cockpit
    // fired switch_session right after boot.
    _disposed = true;
    if (_meshNode) {
      try { await _meshNode.close(); } catch { /* best-effort */ }
      _meshNode = null;
      _sessionName = null;
      _sessionPeerCount = 0;
    }
    // No bye reason: the process keeps running and the fresh instance re-joins
    // the SAME relay room, so an explicit offline→online flap would be wrong.
    if (_state !== "idle") _goIdle();
    if (_cwdLock) {
      try { _cwdLock.release(); } catch { /* best-effort */ }
      _cwdLock = null;
      _lockedName = null;
    }
  });

  // ── Commands ──────────────────────────────────────────────────────────────
  //
  // Final surface: 8 commands. Pre-2026-05-23 we had 20 commands covering
  // multi-session UDS + granular relay control; in practice every install
  // converged on one session and the relay was always either fully on or
  // fully off. The simplified surface keeps the day-to-day path one-key
  // (`/remote-pi`) and exposes only the actions that have distinct user
  // intent: setup, status, stop, pair, devices, revoke, set-relay.
  pi.registerCommand("remote-pi", {
    description: "Connect (join local mesh + start relay), or run setup on first use",
    getArgumentCompletions: async (prefix) => {
      if (prefix.startsWith("revoke ") || prefix === "revoke") {
        const shortPrefix = prefix === "revoke" ? "" : prefix.slice("revoke ".length);
        return _shortidCompletions(shortPrefix, "revoke ");
      }
      return [
        "setup", "status", "stop",
        "pair", "devices", "revoke",
        "set-relay",
        "peers",  // plan/25 Wave D — local + cross-PC inventory
        "create", "remove", "daemons",  // daemon registry (plan/26 W1)
        // Fleet ops use the `daemon` prefix so `/remote-pi stop` keeps
        // meaning "stop this local Pi" — the local UX shipped in plan/25.
        "daemon start", "daemon stop", "daemon restart",
        "daemon send", "daemon status",
        "cron", "cron add", "cron list", "cron remove", "cron enable", "cron disable", "cron run", "cron log",
        "install", "uninstall",  // service install (plan/26 W3)
      ]
        .filter((o) => o.startsWith(prefix))
        .map((o) => ({ value: o, label: o }));
    },
    handler: async (args, ctx) => {
      _lastCtx = ctx;
      const sub = args.trim();
      if      (sub === "")                       { await _cmdRoot(ctx); }
      else if (sub === "setup")                  { await _cmdSetup(ctx); }
      else if (sub === "status")                 { _cmdStatus(ctx); }
      else if (sub === "stop")                   { await _cmdStop(ctx); }
      else if (sub === "pair" || sub.startsWith("pair ")) { await _cmdPair(ctx, sub.slice("pair".length).trim()); }
      else if (sub === "devices")                { await _cmdList(ctx); }
      else if (sub.startsWith("revoke"))         { await _cmdRevoke(sub.slice("revoke".length).trim(), ctx); }
      else if (sub.startsWith("set-relay"))      { _cmdSetRelay(sub.slice("set-relay".length).trim(), ctx); }
      else if (sub === "peers")                  { await _cmdPeers(ctx); }
      else if (sub.startsWith("create"))         { await _cmdCreate(sub.slice("create".length).trim(), ctx); }
      else if (sub.startsWith("remove"))         { await _cmdRemove(sub.slice("remove".length).trim(), ctx); }
      else if (sub === "daemons")                { await _cmdDaemonsList(ctx); }
      else if (sub === "daemon start" || sub.startsWith("daemon start "))     { await _cmdDaemonStart(ctx, sub.slice("daemon start".length).trim() || undefined); }
      else if (sub === "daemon stop" || sub.startsWith("daemon stop "))       { await _cmdDaemonStop(ctx, sub.slice("daemon stop".length).trim() || undefined); }
      else if (sub === "daemon restart" || sub.startsWith("daemon restart ")) { await _cmdDaemonRestart(ctx, sub.slice("daemon restart".length).trim() || undefined); }
      else if (sub === "daemon status")          { await _cmdDaemonStatus(ctx); }
      else if (sub.startsWith("daemon send"))    { await _cmdDaemonSend(sub.slice("daemon send".length).trim(), ctx); }
      else if (sub === "cron" || sub.startsWith("cron ")) { await _cmdCron(sub.slice("cron".length).trim(), ctx); }
      else if (sub === "install")                { _cmdInstall(ctx, { linkCli: true }); }
      else if (sub === "uninstall")              { _cmdUninstall(ctx, { linkCli: true }); }
      else                                       { await _cmdRoot(ctx); }
    },
  });

  // Nested registrations (one entry per public action). The flat handler
  // above already routes `/remote-pi <sub>` — these exist for the SDK's
  // command palette and slash-autocomplete in some UI modes.
  pi.registerCommand("remote-pi setup",    { description: "Run the setup wizard and update local config", handler: async (_, ctx) => { _lastCtx = ctx; await _cmdSetup(ctx); } });
  pi.registerCommand("remote-pi status",   { description: "Show local mesh + relay status", handler: async (_, ctx) => { _lastCtx = ctx; _cmdStatus(ctx); } });
  pi.registerCommand("remote-pi stop",     { description: "Stop everything (leave local mesh + disconnect relay)", handler: async (_, ctx) => { _lastCtx = ctx; await _cmdStop(ctx); } });
  pi.registerCommand("remote-pi pair",     { description: "Show a QR code to pair a new mobile device (optional: --ttl <seconds>)", handler: async (args, ctx) => { _lastCtx = ctx; await _cmdPair(ctx, args.trim()); } });
  pi.registerCommand("remote-pi devices",  { description: "List paired mobile devices", handler: async (_, ctx) => { _lastCtx = ctx; await _cmdList(ctx); } });
  pi.registerCommand("remote-pi revoke", {
    description: "Revoke a paired device by its shortid",
    getArgumentCompletions: async (prefix) => _shortidCompletions(prefix),
    handler: async (args, ctx) => { _lastCtx = ctx; await _cmdRevoke(args.trim(), ctx); },
  });
  pi.registerCommand("remote-pi set-relay", { description: "Persist a new relay URL to user config", handler: async (args, ctx) => { _lastCtx = ctx; _cmdSetRelay(args.trim(), ctx); } });

  // Plan/25 Wave D
  pi.registerCommand("remote-pi peers", {
    description: "List local + cross-PC mesh peers, grouped by PC label",
    handler: async (_, ctx) => { _lastCtx = ctx; await _cmdPeers(ctx); },
  });

  // Daemon registry (plan/26 Wave 1) — create + remove. start/stop/send/
  // status/install/uninstall come in later waves with the supervisor.
  pi.registerCommand("remote-pi create", {
    description: "Register a folder as a daemon and start it (when the supervisor is running)",
    handler: async (args, ctx) => { _lastCtx = ctx; await _cmdCreate(args.trim(), ctx); },
  });
  pi.registerCommand("remote-pi remove", {
    description: "Stop + unregister a daemon by id (local config is preserved)",
    handler: async (args, ctx) => { _lastCtx = ctx; await _cmdRemove(args.trim(), ctx); },
  });

  // Fleet ops via the supervisor (plan/26 W2). `/remote-pi stop` stays as
  // local stop — fleet stop is `/remote-pi daemon stop`.
  pi.registerCommand("remote-pi daemons",        { description: "List registered daemons + state", handler: async (_, ctx) => { _lastCtx = ctx; await _cmdDaemonsList(ctx); } });
  pi.registerCommand("remote-pi daemon start",   { description: "Start daemons: all, or one by id (`daemon start <id>`)", handler: async (args, ctx) => { _lastCtx = ctx; await _cmdDaemonStart(ctx, args.trim() || undefined); } });
  pi.registerCommand("remote-pi daemon stop",    { description: "Stop daemons: all, or one by id (`daemon stop <id>`)", handler: async (args, ctx) => { _lastCtx = ctx; await _cmdDaemonStop(ctx, args.trim() || undefined); } });
  pi.registerCommand("remote-pi daemon restart", { description: "Restart daemons: all, or one by id (`daemon restart <id>`)", handler: async (args, ctx) => { _lastCtx = ctx; await _cmdDaemonRestart(ctx, args.trim() || undefined); } });
  pi.registerCommand("remote-pi daemon status",  { description: "Show fleet runtime status (pid, uptime, restarts)", handler: async (_, ctx) => { _lastCtx = ctx; await _cmdDaemonStatus(ctx); } });
  pi.registerCommand("remote-pi daemon send",    { description: "Send a prompt to a daemon: `daemon send <id> \"<text>\"`", handler: async (args, ctx) => { _lastCtx = ctx; await _cmdDaemonSend(args.trim(), ctx); } });
  pi.registerCommand("remote-pi cron",           { description: "Schedule recurring prompts to daemons: `cron <add|list|remove|enable|disable|run|log>`", handler: async (args, ctx) => { _lastCtx = ctx; await _cmdCron(args.trim(), ctx); } });

  // Service install / uninstall (plan/26 W3)
  pi.registerCommand("remote-pi install",   { description: "Install pi-supervisord as a system service + link the remote-pi CLI (systemd/launchd/Task Scheduler; Windows prompts for admin)", handler: async (_, ctx) => { _lastCtx = ctx; _cmdInstall(ctx, { linkCli: true }); } });
  pi.registerCommand("remote-pi uninstall", { description: "Remove the pi-supervisord system service + the CLI shims (daemons registry preserved; Windows prompts for admin)", handler: async (_, ctx) => { _lastCtx = ctx; _cmdUninstall(ctx, { linkCli: true }); } });

  // Auto-init now runs from the session_start handler (above), AFTER the
  // SDK calls bindCore(). The original setTimeout(0) here fired before bindCore
  // replaced the throwing action-method stubs, so the first pi.sendMessage in
  // _emitRelayState crashed the headless pi process with "Extension runtime not
  // initialized" in a 5s supervisor crash-loop. The session_start handler now
  // auto-starts for ANY session with auto_start_relay (default true), so new
  // interactive pi sessions are on remote automatically — no /remote-pi needed.
};

export default extension;

// ── Command implementations ───────────────────────────────────────────────────

/**
 * `/remote-pi status` — full state snapshot. Two lines: local mesh + relay.
 *
 * Always callable; safe when nothing is up (renders the off variants).
 * Reuses the same icons as the footer so terminal + status output stay
 * visually consistent.
 */
function _cmdStatus(ctx: Pick<ExtensionContext, "ui">): void {
  const relayUrl = _relayUrl ?? resolveRelayUrl().url;

  // Mesh line
  let meshLine: string;
  if (_meshNode) {
    const name = _meshNode.name();
    meshLine = `🟢 Local mesh: connected as "${name}" (${_sessionPeerCount} peer${_sessionPeerCount === 1 ? "" : "s"})`;
  } else {
    meshLine = "⚪ Local mesh: not connected";
  }

  // Relay line — paired state is derived from _activePeers.size now.
  let relayLine: string;
  if (_state === "idle") {
    relayLine = `⚪ Relay: off (${relayUrl}) — run /remote-pi to start`;
  } else if (_activePeers.size > 0) {
    const count = _activePeers.size;
    const shortids = [..._activePeers.keys()].map((k) => k.slice(0, 8)).join(", ");
    relayLine = `🟢 Relay: ${count} owner${count === 1 ? "" : "s"} online (${shortids}) (${relayUrl})`;
  } else {
    relayLine = _hasGlobalPairings
      ? `🟢 Relay: on, waiting for an app to connect (${relayUrl})`
      : `🟡 Relay: on, waiting for first pairing (${relayUrl})`;
  }

  ctx.ui.notify(`[remote-pi]\n  ${meshLine}\n  ${relayLine}`, "info");
}

/**
 * Plan/25 Wave D: `/remote-pi peers`.
 *
 * Queries the local broker for the aggregated peer inventory (`list_peers`
 * returns locals + cross-PC entries prefixed with `<pc_label>:`). Formats
 * the result grouped by source so users can see at a glance who's on
 * their machine vs. on a paired sibling Pi.
 */
async function _cmdPeers(ctx: Pick<ExtensionContext, "ui">): Promise<void> {
  if (!_meshNode) {
    ctx.ui.notify("[remote-pi] Not on the local mesh. Run /remote-pi to join.", "warning");
    return;
  }
  let peers: string[];
  try {
    const reply = await _meshNode.request("broker", { type: "list_peers" }, 2000);
    peers = (reply.body as { peers?: string[] } | null)?.peers ?? [];
  } catch (err) {
    ctx.ui.notify(`[remote-pi] peers list failed: ${String(err)}`, "error");
    return;
  }
  // Exclude self from the printed list — `list_peers` returns every peer
  // registered with the broker including the caller, which is noise here.
  const selfName = _meshNode.name();
  ctx.ui.notify(`[remote-pi] peers:\n${formatPeerInventory(peers, selfName)}`, "info");
}

/**
 * Root handler for `/remote-pi`. On first run (no local config) drops into
 * the wizard; on subsequent runs auto-joins the local mesh + starts the
 * relay (if opted in during setup), then prints the status.
 *
 * `/remote-pi` is intentionally the only command users need day-to-day:
 * idempotent connect + status display.
 */
async function _cmdRoot(ctx: Pick<ExtensionContext, "ui" | "cwd">): Promise<void> {
  // This instance was torn down (session replacement) before its deferred
  // auto-init ran — don't connect, or we'd resurrect a ghost the broker can't
  // reach. The replacement instance (fresh module) drives the live connect.
  if (_disposed) return;

  const cwd = "cwd" in ctx ? (ctx as ExtensionCommandContext).cwd : process.cwd();
  // Lock identity is (cwd, name). Several agents may run in the SAME folder; the
  // requested name just has to be made unique. Derive the name the same way
  // `_cmdJoin` does so the lock and the mesh registration agree on identity.
  const requestedName = loadLocalConfig(cwd).agent_name || defaultAgentName(cwd);

  // Per-(cwd,name) lock, but COLLISION DOESN'T REFUSE — it auto-suffixes. If
  // `(cwd, "Backoffice")` is already held by a live agent, try
  // `(cwd, "Backoffice#2")`, `#3`, … until one binds. So a second agent with the
  // same name in the same folder comes up as `Backoffice#2` (matching the
  // broker's `_uniqueName` suffix scheme) instead of being turned away. The
  // suffix N matches the broker's (`#2`-based) so lock + mesh name line up. The
  // lock is a UDS socket (kernel auto-releases on exit/crash) bound for THIS
  // process's lifetime; repeat `/remote-pi` calls are idempotent.
  if (_cwdLock === null) {
    for (let n = 1; n <= 1000; n++) {
      const candidate = n === 1 ? requestedName : `${requestedName}#${n}`;
      const result = await acquireCwdLock(cwd, candidate);
      if (result.ok) { _cwdLock = result; _lockedName = candidate; break; }
    }
    if (_cwdLock === null) {
      ctx.ui.notify(
        `[remote-pi] Could not start: too many agents named "${requestedName}" already running in this folder.`,
        "warning",
      );
      return;
    }
  }

  // First-time wizard: no local config in this cwd → run interactive setup.
  if (!localConfigExists(cwd)) {
    const ui = ctx.ui as unknown as WizardUI;
    if (typeof ui.select !== "function") {
      _cmdStatus(ctx);
      return;
    }
    const baseDefault = defaultAgentName(cwd);
    const newConfig = await runSetupWizard(ui, {
      agent_name: baseDefault,
      use_relay: true,
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
    await _cmdJoin(ctx);
    if (effectiveAutoStartRelay(newConfig)) await _cmdStart(ctx);
    _cmdStatus(ctx);
    return;
  }

  // Returning user with config: ALWAYS join the local UDS mesh on connect; the
  // relay is the only thing gated by auto_start_relay. So auto_start_relay:false
  // now means "local mesh, no relay" (matching the first-time/wizard path and
  // the field's documented intent) — previously a false flag skipped the mesh
  // join entirely, leaving the agent (incl. daemons) fully idle.
  const config = loadLocalConfig(cwd);
  if (!_meshNode) await _cmdJoin(ctx);
  // `_cmdJoin` aborts cleanly when a `session_shutdown` lands mid-connect, but
  // returns void — so recheck here before bringing the relay up, or we'd start
  // a ghost relay connection on an already-disposed instance (the replacement
  // instance owns the live connect).
  if (_disposed) return;
  if (effectiveAutoStartRelay(config) && _state === "idle") await _cmdStart(ctx);
  _cmdStatus(ctx);
}

/**
 * `/remote-pi setup` — re-run the wizard. Defaults pre-fill from the
 * existing config so it doubles as an "edit" flow.
 */
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
    use_relay: effectiveAutoStartRelay(current),
  });
  if (!newConfig) {
    ctx.ui.notify("[remote-pi] Setup cancelled.", "info");
    return;
  }
  saveLocalConfig(cwd, newConfig);
  ctx.ui.notify(
    "[remote-pi] Config updated. Run /remote-pi to apply now.",
    "info",
  );
}

async function _cmdStart(ctx: Pick<ExtensionContext, "ui" | "cwd">): Promise<void> {
  if (_state !== "idle") {
    ctx.ui.notify("[remote-pi] Already started.", "warning");
    return;
  }

  let edKp: Awaited<ReturnType<typeof getOrCreateEd25519Keypair>>;
  try {
    edKp = await getOrCreateEd25519Keypair();
  } catch (err) {
    if (err instanceof KeyringUnavailableError) {
      // The platform keyring (macOS Keychain / Windows Credential Manager) is
      // locked/denied and there's no file identity to fall back to. We refuse
      // to mint a new key (that's what silently broke pairing after idle), so
      // abort cleanly with an actionable message instead of crashing or
      // re-pairing. Unlocking the keychain and re-running fixes it.
      ctx.ui.notify(
        "[remote-pi] Could not read this machine's identity: the system " +
        "keychain is locked or access was denied. Unlock it (open the app / " +
        "log in) and run /remote-pi again. Your pairing is NOT lost. " +
        "(Set REMOTE_PI_ALLOW_FILE_IDENTITY=1 only for headless hosts.)",
        "error",
      );
      return;
    }
    throw err;
  }
  _cachedEd25519 = edKp;

  const { url: relayUrl, source } = resolveRelayUrl();
  const myShort = Buffer.from(edKp.publicKey).toString("base64").slice(0, 8);

  const cwd = "cwd" in ctx ? (ctx as ExtensionCommandContext).cwd : process.cwd();
  // Same name we send in pair_ok — keeps room_meta.name and the per-pair
  // session_name aligned so the app shows consistent labels.
  const sessionName = _displayName(cwd);
  // plan/41: derive the App↔Pi room from (cwd, name) so several agents in the
  // SAME folder get distinct rooms (the app renders one tile per agent). The
  // default/unnamed case preserves the legacy cwd-only id (no re-keying). Uses
  // the SAME name as room_meta.name / pair_ok below — the invariant that the
  // app pairs on the room the Pi actually announces.
  const roomId = roomIdFor(cwd, sessionName);

  // Seed the current model from the SDK's resolved selection so room_meta
  // carries it on connect. `model_select` only fires on an explicit set/cycle
  // (NOT on settings load), so a headless daemon that just runs its default
  // model never emits it — without this its room_meta would omit the model and
  // the app shows "unknown". `getModel()` returns the session's resolved model
  // in every mode (interactive + RPC daemon); turn_start hydrates it later if
  // the SDK resolves the model lazily.
  if (!_currentModel) {
    try {
      const c = ctx as Partial<ExtensionContext> & {
        model?: { name?: string; id?: string };
        getModel?: () => { name?: string; id?: string } | undefined;
      };
      // Prefer the live getModel() / ctx.model — populated for an interactive
      // Pi. For a HEADLESS DAEMON both are undefined at connect: the SDK only
      // resolves `this.model` lazily at the first turn, and `model_select`
      // never fires for a default-model session. So fall back to the CONFIGURED
      // default (defaultProvider/defaultModel in <cwd>/.pi/settings.json) — the
      // model the daemon will actually use. Without this an idle daemon (never
      // prompted → no turn) would never report its model and the app shows
      // "unknown". turn_start still hydrates a later override.
      const live = c.getModel?.() ?? c.model;
      if (live) {
        _currentModel = live.name ?? live.id ?? undefined;
      } else {
        const sm = SettingsManager.create(cwd);
        const provider = sm.getDefaultProvider();
        const modelId = sm.getDefaultModel();
        if (modelId) {
          const found = provider ? ensureModelRegistry().find(provider, modelId) : undefined;
          _currentModel = found?.name ?? modelId;
        }
      }
    } catch { /* defensive — never block start on a model lookup */ }
  }

  // Plan/28 Wave D.1: seed thinking from the SDK's current level so the
  // first room_meta hello already carries it. `pi.getThinkingLevel()` is
  // safe at this point — extension factory has been bound by the SDK
  // before any command handler fires. Future toggles go through the
  // `thinking_level_select` event handler above.
  try {
    _currentThinking = _pi?.getThinkingLevel() as ThinkingLevel | undefined;
  } catch { /* defensive — never block /remote-pi start on this */ }

  const roomMeta: { name: string; cwd: string; model?: string; thinking?: ThinkingLevel } = { name: sessionName, cwd };
  const modelName = _currentModelName();
  if (modelName) roomMeta.model = modelName;
  if (_currentThinking) roomMeta.thinking = _currentThinking;
  // Persist so _attemptReconnect can replay the same hello payload — without
  // this, reconnect issues a bare hello and the relay creates a "default room"
  // entry that surfaces in the app as a phantom legacy session.
  _myRoomMeta = roomMeta;

  ctx.ui.notify(`[remote-pi] Connecting to relay ${relayUrl} (source: ${source}, room: ${roomId})…`, "info");

  // Transport opens WebSocket; convert the canonical http(s):// stored
  // form to ws(s):// at this boundary. The relayUrl variable keeps the
  // http(s):// form for logging + mesh client construction below.
  const relay = new RelayClient(toWebSocketUrl(relayUrl), edKp);
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

  // Race guard: a `session_shutdown` may have landed while we were awaiting the
  // keypair or `relay.connect()` (the Cockpit fires switch_session right after
  // boot, tearing down THIS instance mid-`_cmdStart`). At that point `_state` is
  // still "idle" — `_cmdStart` only sets "started" below — so the shutdown
  // handler's `_goIdle()` is skipped and CANNOT close this still-local `relay`.
  // Without this guard the WS finishes connecting as a ghost that holds the
  // relay room (keyed by pubkey + roomIdForCwd), and the replacement instance's
  // own connect is refused with `room_already_open` — the agent never enters
  // the cross-PC mesh. Close the fresh relay and bail; the replacement instance
  // (fresh module) drives the real connect. Mirrors the `_cmdJoin` guard.
  if (_disposed) {
    try { relay.close(); } catch { /* best-effort */ }
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

  // Plan/24 Wave 3: poll mesh_versions to detect remote revocation. The
  // poller is independent of WS (uses HTTP) and self-heals across relay
  // reconnects, so a single start here per relay-up cycle is enough.
  if (_selfRevoke === null) {
    _selfRevoke = new SelfRevoke({
      client: new MeshClient(relayUrl),
      storage: { listOwnerPubkeys, removePeer },
      myPubkey: edKp.publicKey,
      onRevoke: (ownerEpk) => {
        // Multi-channel (W2D): drop only the revoked owner's channel.
        // Other owners keep their session. Only fall back to full idle
        // when there are zero attached owners left.
        _refreshPairingsCache();
        if (_activePeers.has(ownerEpk)) {
          _detachPeerChannel(ownerEpk);
          _refreshFooter();
        }
        // Surface the revocation inside the Pi chat panel via
        // `pi.sendMessage` (same channel the QR pair-code uses). Plain
        // `console.info` from the SelfRevoke poller bypasses the TUI
        // widget and bleeds into the prompt area, garbling the layout
        // — same issue we hit with the QR ASCII before plan/24 Wave 3.
        // sendMessage with a customType keeps the line inline with
        // the agent's transcript. The poller's own `log.info` keeps
        // running for daemons/CI where no TUI is attached.
        const short = ownerEpk.slice(0, 8);
        _pi?.sendMessage({
          customType: "remote-pi:mesh-revoked",
          content:
            `🔒 Revoked by Owner ${short}…\n\n` +
            `The mobile app for this Owner removed this PC from the mesh. ` +
            `Re-pair via /remote-pi pair if this was unexpected.`,
          display: true,
        });
      },
      // Plan/25 Wave D: keep the cross-PC sibling list in sync with
      // mesh_versions. The poller fires this whenever the union of Pi
      // members across owners changes — adding/removing a sibling, or an
      // owner relabeling a nickname. MeshNode.setSiblings is a no-op until
      // the bridge is up (follower / relay down), so this is always safe.
      onMembersChanged: (siblings) => {
        _meshNode?.setSiblings(siblings);
      },
      // Silent log: routine self-revoke audit and per-Owner fetch
      // failures don't belong in the TUI chat panel. User-facing
      // revocation events flow through `onRevoke` → `pi.sendMessage`.
      log: { info: () => {}, warn: () => {}, error: () => {} },
    });
    _selfRevoke.start();
  }

  // Plan/25 Wave B/C: bring up cross-PC routing if local broker is ready.
  // No-op when we're a follower (the bridge needs the local Broker instance
  // the leader hosts). Best-effort; failures don't surface.
  _attachBridgeIfReady();

  _emitRelayState();  // → connected
  ctx.ui.notify(`[remote-pi] state: started (peer=${myShort}) — Connected to relay ${relayUrl}`, "info");
}

/**
 * `/remote-pi pair` — always generates a fresh QR when the relay is up.
 *
 * Pre-W2D this rejected with "Already paired with X" once one owner was
 * connected, forcing /remote-pi stop to pair a second device — the
 * catch-22 the multi-channel refactor was designed to break. Now the new
 * device is **added** to `_activePeers` after scanning, while existing
 * owners keep their session.
 */
async function _cmdPair(ctx: Pick<ExtensionContext, "ui" | "cwd">, args = ""): Promise<void> {
  const cwd = "cwd" in ctx ? (ctx as ExtensionCommandContext).cwd : "";

  // Auto-bootstrap when services are down. Before this, `/remote-pi pair`
  // on a fresh terminal forced the user to call `/remote-pi` first — every
  // session began with the same surprise warning + second command. Now we
  // do the join + relay-start inline so the common "I just opened a
  // terminal and want to pair my phone" flow is a single command.
  //
  // We don't run the first-time wizard here: pair is a focused operation
  // and the wizard prompts are wrong UX in that flow. If there's no local
  // config, the user truly needs to run `/remote-pi` first to configure.
  if (_state === "idle") {
    if (!localConfigExists(cwd)) {
      ctx.ui.notify(
        "[remote-pi] First-time setup needed. Run /remote-pi to configure, then /remote-pi pair.",
        "warning",
      );
      return;
    }
    ctx.ui.notify("[remote-pi] Starting mesh + relay before pairing…", "info");
    if (!_meshNode) await _cmdJoin(ctx);
    if (_state === "idle") await _cmdStart(ctx);
  }

  // Relay must be up — the QR carries a token the app exchanges through
  // the relay. Without a live WS there's nothing for the scan to land on.
  if (_state === "idle" || !_relay) {
    ctx.ui.notify(
      "[remote-pi] Pair requires the relay to be connected. " +
      "Run /remote-pi to start it (or fix your relay URL via /remote-pi set-relay).",
      "warning",
    );
    return;
  }

  const edKp = _cachedEd25519!;
  // Embed the user-configured name in the QR so the app shows it on the
  // pairing screen before pair_ok lands (better UX than "remote" or a
  // raw path snippet).
  const sessionName = _displayName(cwd);

  // Optional `--ttl <seconds>` — RPC clients (e.g. Cockpit) pass a caller-
  // defined expiry. Defaults to TOKEN_TTL_MS, clamped to the safe window.
  const ttlMatch = /--ttl\s+(\d+)/.exec(args);
  const ttlMs = ttlMatch ? clampPairTtlMs(Number(ttlMatch[1]) * 1000) : TOKEN_TTL_MS;
  const { token, expiresAt } = qrSession.issueToken(ttlMs);
  const roomId = _myRoomId ?? roomIdFor(cwd, sessionName);
  const qrUri = buildQRUri(token, edKp.publicKey, sessionName, roomId);
  // Render both the QR ASCII and the copy-paste URI inside the Pi TUI's
  // chat panel via `pi.sendMessage` — the same channel the SDK uses for
  // agent responses + tool results. `process.stderr.write` (the old QR
  // path via `displayQR`) broke the TUI layout because it bypassed the
  // chat widget and bled into the prompt area. qrcode-terminal v0.12
  // small mode is pure Unicode (█ ▀ ▄ space, no ANSI escapes — see
  // `lib/main.js:48-53`), so embedding the ASCII inside a sendMessage
  // content string renders correctly without raw escape bytes.
  if (_pi) {
    const qrAscii = renderQRAscii(qrUri);
    _pi.sendMessage({
      customType: "remote-pi:pair-code",
      content:
        `📱 Scan to pair:\n\n${qrAscii}\n` +
        `📋 Or copy this pairing code (camera-less devices):\n\n${qrUri}`,
      // Structured payload for RPC clients (e.g. Cockpit): render their own QR
      // from `uri` + show the expiry, without scraping the display string.
      details: { uri: qrUri, token, expiresAt, roomId, name: sessionName },
      display: true,
    });
  }

  ctx.ui.notify(
    `[remote-pi] QR ready — valid until ${new Date(expiresAt).toLocaleTimeString()}. ` +
    `Scan with the app, or copy the pairing code printed above.`,
    "info",
  );
  // Returns immediately; the auto-listener transitions to 'paired' on pair_request.
}

/**
 * `/remote-pi stop` — full teardown. Leaves the local UDS mesh AND closes
 * the relay. Safe when one or both are already off. To resume, run
 * `/remote-pi` again.
 */
async function _cmdStop(ctx: Pick<ExtensionContext, "ui">): Promise<void> {
  const meshUp = _meshNode !== null;
  const relayUp = _state !== "idle";
  if (!meshUp && !relayUp) {
    ctx.ui.notify("[remote-pi] Already stopped — nothing to do.", "info");
    return;
  }

  if (meshUp) {
    try {
      await _meshNode!.close();
    } catch { /* best-effort */ }
    _meshNode = null;
    _sessionName = null;
    _sessionPeerCount = 0;
  }

  if (relayUp) _goIdle("peer_stop");

  ctx.ui.notify("[remote-pi] Stopped (mesh + relay disconnected).", "info");
  _refreshFooter(ctx);
}

async function _cmdList(ctx: Pick<ExtensionContext, "ui">): Promise<void> {
  const peers = await listPeers();
  if (peers.length === 0) { ctx.ui.notify("[remote-pi] No paired devices.", "info"); return; }
  // Multi-channel (W2D): each peer is either `online` (channel attached
  // right now) or `offline` (in peers.json but not connected). Replaces
  // the singleton " (active)" marker that only ever marked one peer.
  const lines = peers.map((p) => {
    const shortid = p.remote_epk.slice(0, 8);
    const tag = _activePeers.has(p.remote_epk) ? " 🟢 online" : " ⚪ offline";
    return `• ${shortid} — ${p.name}${tag}`;
  }).join("\n");
  ctx.ui.notify(`[remote-pi] Paired devices:\n${lines}`, "info");
}

async function _cmdRevoke(arg: string, ctx: Pick<ExtensionContext, "ui" | "cwd">): Promise<void> {
  const shortid = arg.trim();
  if (!shortid) {
    ctx.ui.notify(
      "[remote-pi] Usage: /remote-pi revoke <shortid>. Run /remote-pi list to see shortids.",
      "warning",
    );
    return;
  }

  // Revoke needs the relay so the revoked device gets a `bye` and its live
  // channel is torn down — not just a silent peers.json edit. Auto-bootstrap
  // the mesh + relay when down, mirroring `_cmdPair`.
  const cwd = "cwd" in ctx ? (ctx as ExtensionCommandContext).cwd : "";
  if (_state === "idle") {
    if (!localConfigExists(cwd)) {
      ctx.ui.notify(
        "[remote-pi] First-time setup needed. Run /remote-pi to configure, then /remote-pi revoke.",
        "warning",
      );
      return;
    }
    ctx.ui.notify("[remote-pi] Starting mesh + relay before revoking…", "info");
    if (!_meshNode) await _cmdJoin(ctx);
    if (_state === "idle") await _cmdStart(ctx);
  }
  if (_state === "idle" || !_relay) {
    ctx.ui.notify(
      "[remote-pi] Revoke requires the relay to be connected. " +
      "Run /remote-pi to start it (or fix your relay URL via /remote-pi set-relay).",
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

  // Multi-channel (W2D): close just this owner's channel. Other connected
  // owners keep their session — the relay stays `started`.
  if (_activePeers.has(peer.remote_epk)) {
    // Notify the revoked device explicitly before tearing the channel
    // down — otherwise it would only know via ping miss.
    const ch = _activePeers.get(peer.remote_epk);
    try { ch?.send({ type: "bye", reason: "session_replaced" }); } catch { /* best-effort */ }
    _detachPeerChannel(peer.remote_epk);
    _refreshFooter();
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
  const raw = arg.trim();
  if (!raw) {
    ctx.ui.notify(
      "[remote-pi] Usage: /remote-pi set-relay <http:// or https:// url>",
      "warning",
    );
    return;
  }
  if (isWebSocketScheme(raw)) {
    ctx.ui.notify(
      `[remote-pi] Use http:// or https://. The extension converts to WebSocket automatically.`,
      "error",
    );
    return;
  }
  if (!isValidRelayUrl(raw)) {
    ctx.ui.notify(
      `[remote-pi] Invalid URL: ${raw}. Must start with http:// or https://`,
      "error",
    );
    return;
  }
  saveConfig({ relay: raw });
  ctx.ui.notify(
    `[remote-pi] Relay set to ${raw}. Run /remote-pi start (or restart) to apply.`,
    "info",
  );
}

// ── Daemon registry commands (plan/26 Wave 1) ─────────────────────────────────

/**
 * `/remote-pi create [<cwd>] [--name <name>]`
 *
 * Promotes a folder to a daemon entry in `~/.pi/remote/daemons.json`. The
 * cwd is **always normalized to an absolute realpath** before storage —
 * `~/Movies`, `./Movies`, `../foo/Movies` all collapse to a single
 * canonical entry. Relative paths resolve against the Pi process's
 * current working directory, not the slash-command's `ctx.cwd`.
 *
 * Side effects on the cwd's local config (`<cwd>/.pi/remote-pi/config.json`):
 *   - If the config doesn't exist: created with `auto_start_relay=true`
 *     (mandatory for daemons) and `agent_name` from `--name` if provided.
 *   - If the config already exists: left untouched. Re-running `create`
 *     on an existing daemon is idempotent at this layer; the registry
 *     itself rejects duplicate cwds.
 */
async function _cmdCreate(arg: string, ctx: Pick<ExtensionContext, "ui">): Promise<void> {
  // Parse `[cwd] [--name "value with spaces" | --name word]` in any order.
  // The first non-flag token is the cwd; the rest of the line after
  // `--name` (quoted or unquoted) is the display name.
  const nameMatch = arg.match(/--name\s+"([^"]+)"|--name\s+(\S+)/);
  const name = nameMatch ? (nameMatch[1] ?? nameMatch[2]) : undefined;
  const cwdRaw = arg.replace(/--name\s+"[^"]+"|--name\s+\S+/, "").trim();
  if (!cwdRaw) {
    ctx.ui.notify(
      "[remote-pi] Usage: /remote-pi create <absolute-or-relative-cwd> [--name \"Display name\"]",
      "warning",
    );
    return;
  }

  let result: { id: string; cwd: string; name: string };
  try {
    result = addDaemon(cwdRaw, name);
  } catch (err) {
    ctx.ui.notify(`[remote-pi] create failed: ${String(err)}`, "error");
    return;
  }

  // No local `.pi/remote-pi/config.json` is written anymore — the name lives
  // in the registry and the supervisor injects the full config (agent_name,
  // auto_start_relay true) via REMOTE_PI_DIRECT_CONFIG when it spawns the
  // daemon. The cwd needs no init folder.

  ctx.ui.notify(
    `[remote-pi] Daemon registered: id=${result.id} name="${result.name}" cwd=${result.cwd}`,
    "info",
  );

  // Auto-start: register alone used to leave the daemon idle until the next
  // supervisor restart (the reported bug — `create` didn't run anything). Ask
  // the supervisor to spawn THIS daemon now; it reads the name from the
  // registry and injects the config via env. When the supervisor is offline we
  // keep the
  // registration and tell the user it'll boot on the next supervisor start.
  try {
    await callSupervisor({ op: "start", id: result.id });
    ctx.ui.notify(`[remote-pi] Daemon started: id=${result.id}`, "info");
  } catch (err) {
    if (err instanceof SupervisorOfflineError) {
      ctx.ui.notify(
        `[remote-pi] Registered, but the supervisor is offline — not running yet. ` +
        `Run \`remote-pi install\` (or start \`pi-supervisord\`); it auto-starts on the next supervisor boot.`,
        "warning",
      );
      return;
    }
    ctx.ui.notify(`[remote-pi] Registered, but auto-start failed: ${String(err)}`, "error");
  }
}

/**
 * `/remote-pi remove <id>`
 *
 * Unregisters a daemon by its 8-hex-char id (the same id printed by
 * `/remote-pi create` and `/remote-pi daemons`). The cwd's local config
 * stays on disk — re-creating later with the same cwd is a no-op
 * because the existing config wins.
 */
async function _cmdRemove(arg: string, ctx: Pick<ExtensionContext, "ui">): Promise<void> {
  const id = arg.trim();
  if (!id) {
    ctx.ui.notify(
      "[remote-pi] Usage: /remote-pi remove <id>. Run /remote-pi daemons to see ids.",
      "warning",
    );
    return;
  }

  // Prefer the supervisor's `unregister`: it STOPS the running child (SIGTERM →
  // SIGKILL) BEFORE deleting the registry entry. Removing only the registry
  // (the old behaviour) left an orphaned `pi --mode rpc` process running with
  // nothing left to manage it — the reported bug. Fall back to a registry-only
  // removal when the supervisor is offline (no managed process to stop anyway).
  try {
    const data = await callSupervisor({ op: "unregister", id });
    if (!data.removed) {
      const known = listDaemons().map((d) => d.id).join(", ") || "(none)";
      ctx.ui.notify(`[remote-pi] No daemon with id "${id}". Known ids: ${known}`, "warning");
      return;
    }
    ctx.ui.notify(
      `[remote-pi] Daemon removed + process stopped: id=${id} cwd=${data.cwd}. ` +
      `Local config at ${data.cwd}/.pi/remote-pi/config.json was kept.`,
      "info",
    );
    return;
  } catch (err) {
    if (!(err instanceof SupervisorOfflineError)) {
      ctx.ui.notify(`[remote-pi] remove failed: ${String(err)}`, "error");
      return;
    }
    // Supervisor offline — fall through to registry-only removal below.
  }

  let result: { removed: boolean; cwd?: string };
  try {
    result = removeDaemon(id);
  } catch (err) {
    ctx.ui.notify(`[remote-pi] remove failed: ${String(err)}`, "error");
    return;
  }

  if (!result.removed) {
    const known = listDaemons().map((d) => d.id).join(", ") || "(none)";
    ctx.ui.notify(`[remote-pi] No daemon with id "${id}". Known ids: ${known}`, "warning");
    return;
  }

  ctx.ui.notify(
    `[remote-pi] Daemon removed from registry: id=${id} cwd=${result.cwd}. ` +
    `Supervisor was offline, so any running process was NOT stopped. Local config kept.`,
    "warning",
  );
}

// ── Fleet-ops commands (plan/26 W2) — talk to the supervisor over UDS ─────────
//
// Every command here is a thin wrapper around `callSupervisor(...)`. When
// the supervisor isn't running we fall back to a friendly hint instead of
// the raw error, so the user can't get stuck on "what's wrong?".

function _notifyOffline(ctx: Pick<ExtensionContext, "ui">, err: SupervisorOfflineError): void {
  ctx.ui.notify(`[remote-pi] ${err.message}`, "warning");
}

function _formatDaemonTable(daemons: DaemonInfo[]): string {
  if (daemons.length === 0) return "(no daemons registered)";
  const rows = daemons.map((d) => {
    const uptime = d.uptime_s !== undefined ? `${d.uptime_s}s` : "—";
    const pid = d.pid !== undefined ? String(d.pid) : "—";
    const restarts = d.restart_count ?? 0;
    return `  ${d.id}  ${d.state.padEnd(8)}  pid=${pid}  up=${uptime}  restarts=${restarts}  ${d.name}  ${d.cwd}`;
  });
  return rows.join("\n");
}

/**
 * `/remote-pi daemons` — registry + runtime state in one view. When the
 * supervisor is offline we still show registry-only output (state =
 * "stopped" everywhere), so the user can see what's configured even
 * before `install`.
 */
async function _cmdDaemonsList(ctx: Pick<ExtensionContext, "ui">): Promise<void> {
  if (!(await supervisorOnline())) {
    const registry = listDaemons();
    if (registry.length === 0) {
      ctx.ui.notify("[remote-pi] No daemons registered. Run /remote-pi create <cwd>.", "info");
      return;
    }
    const rows = registry.map((d) => {
      const cfg = loadLocalConfig(d.cwd);
      const name = cfg.agent_name ?? defaultAgentName(d.cwd);
      return `  ${d.id}  ${name}  ${d.cwd}  (supervisor offline)`;
    }).join("\n");
    ctx.ui.notify(`[remote-pi] Daemons (registry only — run install to bring supervisor up):\n${rows}`, "info");
    return;
  }
  try {
    const data = await callSupervisor({ op: "list" });
    ctx.ui.notify(`[remote-pi] Daemons:\n${_formatDaemonTable(data.daemons)}`, "info");
  } catch (err) {
    if (err instanceof SupervisorOfflineError) { _notifyOffline(ctx, err); return; }
    ctx.ui.notify(`[remote-pi] daemons failed: ${String(err)}`, "error");
  }
}

async function _cmdDaemonStatus(ctx: Pick<ExtensionContext, "ui">): Promise<void> {
  try {
    const data = await callSupervisor({ op: "status" });
    ctx.ui.notify(`[remote-pi] Fleet status:\n${_formatDaemonTable(data.daemons)}`, "info");
  } catch (err) {
    if (err instanceof SupervisorOfflineError) { _notifyOffline(ctx, err); return; }
    ctx.ui.notify(`[remote-pi] status failed: ${String(err)}`, "error");
  }
}

async function _cmdDaemonStart(ctx: Pick<ExtensionContext, "ui">, id?: string): Promise<void> {
  try {
    if (id) {
      const data = await callSupervisor({ op: "start", id });
      ctx.ui.notify(
        data.started
          ? `[remote-pi] Started daemon ${id} (${data.state}).`
          : `[remote-pi] Daemon ${id} already ${data.state}.`,
        "info",
      );
      return;
    }
    const data = await callSupervisor({ op: "start_all" });
    ctx.ui.notify(
      `[remote-pi] Started ${data.started.length} daemon(s), ` +
      `${data.already_running.length} already running.`,
      "info",
    );
  } catch (err) {
    if (err instanceof SupervisorOfflineError) { _notifyOffline(ctx, err); return; }
    ctx.ui.notify(`[remote-pi] start failed: ${String(err)}`, "error");
  }
}

async function _cmdDaemonStop(ctx: Pick<ExtensionContext, "ui">, id?: string): Promise<void> {
  try {
    if (id) {
      const data = await callSupervisor({ op: "stop", id });
      ctx.ui.notify(
        data.stopped
          ? `[remote-pi] Stopped daemon ${id}.`
          : `[remote-pi] Daemon ${id} already ${data.state}.`,
        "info",
      );
      return;
    }
    const data = await callSupervisor({ op: "stop_all" });
    ctx.ui.notify(
      `[remote-pi] Stopped ${data.stopped.length} daemon(s), ` +
      `${data.already_stopped.length} already stopped.`,
      "info",
    );
  } catch (err) {
    if (err instanceof SupervisorOfflineError) { _notifyOffline(ctx, err); return; }
    ctx.ui.notify(`[remote-pi] stop failed: ${String(err)}`, "error");
  }
}

async function _cmdDaemonRestart(ctx: Pick<ExtensionContext, "ui">, id?: string): Promise<void> {
  try {
    if (id) {
      const data = await callSupervisor({ op: "restart", id });
      ctx.ui.notify(`[remote-pi] Restarted daemon ${id} (${data.state}).`, "info");
      return;
    }
    const data = await callSupervisor({ op: "restart_all" });
    ctx.ui.notify(`[remote-pi] Restarted ${data.restarted.length} daemon(s).`, "info");
  } catch (err) {
    if (err instanceof SupervisorOfflineError) { _notifyOffline(ctx, err); return; }
    ctx.ui.notify(`[remote-pi] restart failed: ${String(err)}`, "error");
  }
}

/**
 * `/remote-pi daemon send <id> "<text>"` — injects a prompt into a
 * running daemon via its RPC stdin. The agent processes the prompt as
 * if a user typed it; output flows back via the relay/mesh, not here.
 *
 * Fire-and-forget at this layer — the CLI just confirms delivery.
 */
async function _cmdDaemonSend(arg: string, ctx: Pick<ExtensionContext, "ui">): Promise<void> {
  // Parse `<id> <text...>` — id is the first token, rest is the prompt.
  // The text may be quoted; if so, strip the outer quotes. Otherwise
  // take the entire remainder verbatim.
  const m = arg.match(/^(\S+)\s+(?:"([^"]*)"|(.*))$/);
  if (!m) {
    ctx.ui.notify(
      "[remote-pi] Usage: /remote-pi daemon send <id> \"<prompt text>\"",
      "warning",
    );
    return;
  }
  const id = m[1]!;
  const text = (m[2] ?? m[3] ?? "").trim();
  if (!text) {
    ctx.ui.notify("[remote-pi] daemon send: prompt text is empty.", "warning");
    return;
  }
  try {
    const data = await callSupervisor({ op: "send", id, text });
    if (data.delivered) {
      ctx.ui.notify(`[remote-pi] Sent to ${id}: ${text.slice(0, 60)}${text.length > 60 ? "…" : ""}`, "info");
    } else {
      ctx.ui.notify(`[remote-pi] daemon ${id} did not accept the prompt (not running?)`, "warning");
    }
  } catch (err) {
    if (err instanceof SupervisorOfflineError) { _notifyOffline(ctx, err); return; }
    ctx.ui.notify(`[remote-pi] daemon send failed: ${String(err)}`, "error");
  }
}

// ── Cron — scheduled prompts for daemons (plan/39) ──────────────────────────

/** Splits an arg string into tokens, honoring double-quoted groups. */
function _tokenizeArgs(s: string): string[] {
  const out: string[] = [];
  const re = /"([^"]*)"|(\S+)/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(s)) !== null) out.push(m[1] !== undefined ? m[1] : m[2]!);
  return out;
}

/**
 * `/remote-pi cron <add|list|remove|enable|disable|run|log>` — schedules
 * recurring prompts to daemons via the supervisor. All subcommands require the
 * supervisor running (offline → friendly notice, not a crash).
 */
async function _cmdCron(arg: string, ctx: Pick<ExtensionContext, "ui">): Promise<void> {
  const trimmed = arg.trim();
  const sp = trimmed.indexOf(" ");
  const sub = (sp === -1 ? trimmed : trimmed.slice(0, sp)).toLowerCase();
  const rest = sp === -1 ? "" : trimmed.slice(sp + 1).trim();
  try {
    switch (sub) {
      case "":
      case "list":    return await _cronList(ctx);
      case "add":     return await _cronAdd(rest, ctx);
      case "remove":
      case "rm":      return await _cronMutate({ op: "cron_remove", job_id: rest.trim() }, rest.trim(), ctx);
      case "enable":  return await _cronMutate({ op: "cron_enable", job_id: rest.trim(), enabled: true }, rest.trim(), ctx);
      case "disable": return await _cronMutate({ op: "cron_enable", job_id: rest.trim(), enabled: false }, rest.trim(), ctx);
      case "run":     return await _cronRun(rest.trim(), ctx);
      case "log":     return await _cronLog(rest, ctx);
      default:
        ctx.ui.notify("[remote-pi] Usage: /remote-pi cron <add|list|remove|enable|disable|run|log>", "warning");
    }
  } catch (err) {
    if (err instanceof SupervisorOfflineError) {
      ctx.ui.notify(
        "[remote-pi] Cron needs the supervisor running. Run `remote-pi install` " +
        "(or start `pi-supervisord`).",
        "warning",
      );
      return;
    }
    ctx.ui.notify(`[remote-pi] cron ${sub || "list"} failed: ${String(err)}`, "error");
  }
}

async function _cronAdd(rest: string, ctx: Pick<ExtensionContext, "ui">): Promise<void> {
  const toks = _tokenizeArgs(rest);
  let tz: string | undefined;
  let wake = false;
  let skipBusy = true;
  let catchup = false;
  const pos: string[] = [];
  for (let i = 0; i < toks.length; i++) {
    const t = toks[i]!;
    if (t === "--wake") wake = true;
    else if (t === "--no-skip-busy") skipBusy = false;
    else if (t === "--catchup") catchup = true;
    else if (t === "--tz") tz = toks[++i];
    else pos.push(t);
  }
  const [daemonId, schedule, prompt] = pos;
  if (!daemonId || !schedule || !prompt) {
    ctx.ui.notify(
      '[remote-pi] Usage: /remote-pi cron add <daemonId> "<cron-expr>" "<prompt>" ' +
      "[--tz Area/City] [--wake] [--no-skip-busy] [--catchup]",
      "warning",
    );
    return;
  }
  const req: Extract<ControlRequest, { op: "cron_add" }> = {
    op: "cron_add", daemon_id: daemonId, schedule, prompt,
  };
  if (tz) req.tz = tz;
  if (wake) req.wake = true;
  if (!skipBusy) req.skip_if_busy = false;
  if (catchup) req.catchup = true;
  const data = await callSupervisor(req);
  ctx.ui.notify(
    `[remote-pi] Cron ${data.job.id} added → daemon ${daemonId}: "${schedule}"` +
    `${tz ? ` (${tz})` : ""}. Next run: ${data.job.next_run ?? "?"}`,
    "info",
  );
}

async function _cronList(ctx: Pick<ExtensionContext, "ui">): Promise<void> {
  const data = await callSupervisor({ op: "cron_list" });
  if (data.jobs.length === 0) {
    ctx.ui.notify("[remote-pi] No cron jobs.", "info");
    return;
  }
  const lines = data.jobs.map((j) =>
    `${j.enabled ? "✓" : "✗"} ${j.id}  "${j.schedule}"${j.tz ? ` (${j.tz})` : ""}  → ${j.daemon_id}  ` +
    `next:${j.next_run ?? "?"}  last:${j.last_status ?? "—"}${j.last_run ? `@${j.last_run}` : ""}`,
  );
  ctx.ui.notify(`[remote-pi] Cron jobs (${data.jobs.length}):\n${lines.join("\n")}`, "info");
}

async function _cronMutate(
  req: Extract<ControlRequest, { op: "cron_remove" | "cron_enable" }>,
  jobId: string,
  ctx: Pick<ExtensionContext, "ui">,
): Promise<void> {
  if (!jobId) {
    ctx.ui.notify(`[remote-pi] Usage: /remote-pi cron ${req.op === "cron_remove" ? "remove" : "enable|disable"} <jobId>`, "warning");
    return;
  }
  if (req.op === "cron_remove") {
    const data = await callSupervisor(req);
    ctx.ui.notify(data.removed ? `[remote-pi] Cron ${jobId} removed.` : `[remote-pi] No cron job ${jobId}.`, data.removed ? "info" : "warning");
  } else {
    const data = await callSupervisor(req);
    ctx.ui.notify(
      data.updated ? `[remote-pi] Cron ${jobId} ${data.enabled ? "enabled" : "disabled"}.` : `[remote-pi] No cron job ${jobId}.`,
      data.updated ? "info" : "warning",
    );
  }
}

async function _cronRun(jobId: string, ctx: Pick<ExtensionContext, "ui">): Promise<void> {
  if (!jobId) {
    ctx.ui.notify("[remote-pi] Usage: /remote-pi cron run <jobId>", "warning");
    return;
  }
  const data = await callSupervisor({ op: "cron_run", job_id: jobId });
  ctx.ui.notify(`[remote-pi] Cron ${jobId} fired now → ${data.result}`, "info");
}

async function _cronLog(rest: string, ctx: Pick<ExtensionContext, "ui">): Promise<void> {
  const toks = _tokenizeArgs(rest);
  let jobId: string | undefined;
  let tail = 20;
  for (let i = 0; i < toks.length; i++) {
    const t = toks[i]!;
    if (t === "--tail") { const n = Number(toks[++i]); if (Number.isFinite(n)) tail = n; }
    else if (!t.startsWith("--")) jobId = t;
  }
  const req: Extract<ControlRequest, { op: "cron_log" }> = { op: "cron_log", tail };
  if (jobId) req.job_id = jobId;
  const data = await callSupervisor(req);
  if (data.entries.length === 0) {
    ctx.ui.notify("[remote-pi] No cron log entries.", "info");
    return;
  }
  const lines = data.entries.map((e) =>
    `${new Date(e.ts).toISOString()}  ${e.fired ? "▶" : "∅"} ${e.result}  ${e.job_id} → ${e.daemon_id}  ${e.prompt_preview}`,
  );
  ctx.ui.notify(`[remote-pi] Cron log (last ${data.entries.length}):\n${lines.join("\n")}`, "info");
}

// ── Install/uninstall the supervisor service (plan/26 W3) ────────────────────
//
// Installs `pi-supervisord` as a user-level system service (systemd
// `--user` unit on Linux, launchd LaunchAgent on macOS). Once installed:
//   - Supervisor starts at login + survives reboots.
//   - `remote-pi daemon start/stop/send/...` work without manually
//     spawning the supervisor.
// Uninstall is the inverse — leaves the registry (`daemons.json`) intact,
// so re-installing later picks up where you left off.

/**
 * `linkCli` controls whether we symlink `remote-pi` + `pi-supervisord`
 * into `~/.local/bin/`. The slash-command path passes `true` (user is
 * inside Pi's TUI — they installed via `pi install npm:remote-pi` and
 * need us to expose the CLI for them). The standalone-CLI path passes
 * `false` because the user is already running our binary from PATH (they
 * did `npm install -g remote-pi`), so re-linking would point their
 * `remote-pi` at the Pi-extension copy and diverge on upgrades.
 */
/** Returns true on success, false when install failed (so the standalone CLI
 *  can exit non-zero — e.g. the Cockpit / CI detect failure by exit code).
 *  We do NOT process.exit here: this also runs inside the Pi TUI, where exiting
 *  would kill the session. */
function _cmdInstall(ctx: Pick<ExtensionContext, "ui">, opts: { linkCli?: boolean } = {}): boolean {
  const linkCli = opts.linkCli ?? false;
  try {
    const result = installService();
    const sections = [
      `[remote-pi] Supervisor service installed (${result.platform}).`,
      `  Unit: ${result.unitPath}`,
      `  Steps:\n${result.log.map((l) => "    " + l).join("\n")}`,
    ];
    if (linkCli) {
      const link = linkCliBinaries();
      sections.push(
        `  CLI bins linked into ${link.binDir}:`,
        link.links.map((l) => `    ${l.name} → ${l.target}`).join("\n"),
        `  Steps:\n${link.log.map((l) => "    " + l).join("\n")}`,
      );
      if (!link.onPath) {
        if (process.platform === "win32") {
          sections.push(
            `  ⚠ ${link.binDir} was just added to your user PATH (it wasn't there yet).`,
            `    Open a NEW terminal and run \`remote-pi daemons\` to verify.`,
          );
        } else {
          sections.push(
            `  ⚠ ${link.binDir} is not on $PATH yet. Add this line to ~/.zshrc / ~/.bashrc:`,
            `      export PATH="$HOME/.local/bin:$PATH"`,
            `    Then open a new terminal and run \`remote-pi daemons\` to verify.`,
          );
        }
      }
    }
    ctx.ui.notify(sections.join("\n"), "info");
    return true;
  } catch (err) {
    ctx.ui.notify(`[remote-pi] install failed: ${String(err)}`, "error");
    return false;
  }
}

function _cmdUninstall(ctx: Pick<ExtensionContext, "ui">, opts: { linkCli?: boolean } = {}): void {
  const linkCli = opts.linkCli ?? false;
  try {
    const result = uninstallService();
    const sections = [
      `[remote-pi] Supervisor service uninstalled (${result.platform}).`,
      `  Unit: ${result.unitPath} (${result.removed ? "removed" : "not present"})`,
      `  Steps:\n${result.log.map((l) => "    " + l).join("\n")}`,
      `  Note: daemons registry (~/.pi/remote/daemons.json) kept — re-install restores everything.`,
    ];
    if (linkCli) {
      const unlink = unlinkCliBinaries();
      sections.push(
        `  CLI bins cleanup (${unlink.binDir}):`,
        unlink.removed
          .map((r) => `    ${r.name} (${r.existed ? "removed" : "not present"})`)
          .join("\n"),
      );
    }
    ctx.ui.notify(sections.join("\n"), "info");
  } catch (err) {
    ctx.ui.notify(`[remote-pi] uninstall failed: ${String(err)}`, "error");
  }
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

/**
 * Inject text into the agent as a user message, waking a turn. The Pi SDK's
 * `ExtensionAPI.sendUserMessage` is fire-and-forget (returns `void`) and
 * "always triggers a turn" — the SDK runtime owns any *async* turn failure
 * (no model/API key, expired auth, provider error), which surfaces in the
 * agent's own output, not back to us. Two gaps this helper closes, both of
 * which previously failed silently:
 *
 *   1. `_pi` not bound yet (activation race / mesh joined before the session
 *      attached): the old code did `if (!_pi) return`, dropping the message
 *      with no trace. We log it (the daemon forwards child stderr to its log
 *      with a cwd prefix, so it's visible in `journalctl`).
 *   2. A *synchronous* throw from `sendUserMessage` (e.g. malformed content):
 *      the old fire-and-forget call let it propagate out of the `onMessage`
 *      callback, which could wedge the read loop and blackout every later
 *      message. We catch + surface it instead.
 *
 * NOTE: this does NOT make a wake that fails *inside* the SDK observable —
 * that requires a fix in the Pi runtime (no extension-level error event
 * exists for it). See `.orchestration/results/mesh-liveness-stale-peer.md`.
 */
type SendUserMessageOptions =
  NonNullable<Parameters<ExtensionAPI["sendUserMessage"]>[1]>;

type WakeAgentResult =
  | { ok: true }
  | { ok: false; detail: string };

function _wakeAgent(
  content: Parameters<ExtensionAPI["sendUserMessage"]>[0],
  label: string,
  steeringBehavior?: SendUserMessageOptions["deliverAs"],
): WakeAgentResult {
  if (!_pi) {
    const detail = "agent session not bound yet";
    console.error(`[remote-pi] ${label}: ${detail} — message dropped`);
    return { ok: false, detail };
  }
  try {
    const options = steeringBehavior
      ? ({ deliverAs: steeringBehavior })
      : undefined;
    _pi.sendUserMessage(content, options);
    return { ok: true };
  } catch (err) {
    const detail = err instanceof Error ? err.message : String(err);
    console.error(`[remote-pi] ${label}: agent rejected incoming message: ${detail}`);
    _lastCtx?.ui.notify(`[remote-pi] failed to process incoming message: ${detail}`, "error");
    return { ok: false, detail };
  }
}

/**
 * Deliver an inbound agent-network (mesh) message to the agent + the app.
 *
 * Display: the app renders it in the TOOL timeline (a matched
 * tool_request/tool_result "agent-network" pair) — NOT as the user's own
 * message, which is what `sendUserMessage` used to produce (the reported bug).
 *
 * Wake: we inject a CUSTOM message (role:"custom"), not a user message. The
 * SDK's `convertToLlm` maps custom → a user-role LLM message, so the agent
 * still sees + replies to it, but `message_end` does NOT buffer role:"custom",
 * so it never replays as `user_input` on session_sync. `triggerTurn` runs the
 * turn; `id` lets the LLM echo it via `agent_send(..., re=<id>)`.
 */
function _deliverMeshMessageToAgent(
  env: { id: string; from: string; re: string | null; body: unknown },
): void {
  const bodyText = typeof env.body === "string" ? env.body : JSON.stringify(env.body);
  const toolCallId = `mesh_${env.id}`;
  _broadcastToActive({
    type: "tool_request",
    tool_call_id: toolCallId,
    tool: "agent-network",
    args: env.re
      ? { from: env.from, re: env.re, message: bodyText }
      : { from: env.from, message: bodyText },
  });
  _broadcastToActive({ type: "tool_result", tool_call_id: toolCallId, result: { from: env.from, message: bodyText } });

  const label = `agent-network message from "${env.from}"`;
  if (!_pi) {
    console.error(`[remote-pi] ${label}: agent session not bound yet — message dropped`);
    return;
  }
  const header = `[agent-network] message from "${env.from}" (id=${env.id}${env.re ? `, re=${env.re}` : ""}):`;
  const footer = env.re
    ? "(This is a reply to a previous message of yours.)"
    : `(If a reply is expected, call agent_send with to="${env.from}" and re="${env.id}".)`;
  try {
    _pi.sendMessage(
      { customType: "remote-pi:mesh-message", content: `${header}\n${bodyText}\n\n${footer}`, display: true },
      { triggerTurn: true },
    );
  } catch (err) {
    const detail = err instanceof Error ? err.message : String(err);
    console.error(`[remote-pi] ${label}: agent rejected incoming message: ${detail}`);
    _lastCtx?.ui.notify(`[remote-pi] failed to process incoming message: ${detail}`, "error");
  }
}

/**
 * Joins the fixed local UDS mesh ("local" session — see LOCAL_SESSION_NAME).
 * Called by `_cmdRoot` on first run and on subsequent runs when the relay
 * is up and the user hasn't explicitly stopped. The session name is no
 * longer user-configurable: every Pi on the same machine joins the same
 * broker.
 */
async function _cmdJoin(ctx: Pick<ExtensionContext, "ui" | "cwd">): Promise<void> {
  const cwd = "cwd" in ctx ? (ctx as ExtensionCommandContext).cwd : process.cwd();
  const local = loadLocalConfig(cwd);
  const sessionName = LOCAL_SESSION_NAME;
  // What the user configured for this agent…
  const requestedName = local.agent_name || defaultAgentName(cwd);
  // …and what we actually register: the name the cwd-lock reserved, which is
  // `requestedName` or a `#N` variant when same-named agents share this folder.
  // Falls back to requestedName when join runs without a prior `_cmdRoot` lock
  // (e.g. legacy/test paths).
  const agentName = _lockedName ?? requestedName;

  if (_meshNode) {
    ctx.ui.notify("[remote-pi] Already on the local mesh.", "warning");
    return;
  }

  ensureGlobalDirs();
  mkdirSync(join(skillsDir(), "..", "sessions", sessionName), { recursive: true });

  const sock = sessionSockPath(sessionName);
  const audit = sessionAuditPath(sessionName);
  // Forward the cwd so the broker keys this peer by (cwd, name): a same-folder
  // same-name reincarnation (switch_session re-eval, app restart) takes over the
  // name instead of registering behind a mute `name#N` ghost. Canonicalize via
  // realpath so symlinked cwds map to one identity (matches roomIdForCwd).
  let canonCwd = cwd;
  try { canonCwd = realpathSync(cwd); } catch { /* cwd missing — use raw path */ }
  const peer = new MeshNode({ sockPath: sock, name: agentName, cwd: canonCwd, auditPath: audit });

  peer.onMessage((env) => {
    const body = env.body as { type?: string } | null;
    // Broker system events: re-query broker for authoritative count.
    // Incremental ±1 drifts when peer_left is missed (leader leaves cleanly,
    // failover, etc.) — querying list_peers makes the count self-healing.
    if (body && (body.type === "peer_joined" || body.type === "peer_left")) {
      _refreshSessionPeerCount(peer, ctx);
      // Plan/25 Wave B: push fresh peer list to all siblings so their
      // remotePeers cache stays current without polling.
      void peer.request("broker", { type: "list_peers" }, 2000)
        .then((reply) => {
          const body = reply.body as {
            peers?: string[];
            peers_detailed?: Array<{ pc?: string; address?: string }>;
          } | null;
          // onLocalPeersChanged wants LOCAL-only addresses (list_peers returns
          // the aggregated local + cross-PC roster). Prefer the structured
          // roster (plan/38): a local peer has no `pc`. This is drive-letter
          // safe — a Windows local address `C:\…@app` contains ':' but is NOT
          // remote, so the old naive `!p.includes(":")` misclassified it.
          let local: string[] | null = null;
          const detailed = body?.peers_detailed;
          if (Array.isArray(detailed)) {
            local = detailed
              .filter((p) => !p.pc && typeof p.address === "string")
              .map((p) => p.address as string);
          } else if (Array.isArray(body?.peers)) {
            // Fallback for a legacy broker without `peers_detailed`.
            local = body!.peers!.filter((p) => !p.includes(":"));
          }
          // No-op when the bridge isn't up (follower / relay down).
          if (local) peer.onLocalPeersChanged(local);
        })
        .catch(() => { /* bridge not bound yet, or list_peers failed */ });
      return;
    }
    if (env.from === "broker") return;  // other broker control messages — ignore

    // Real agent-to-agent message (SessionPeer already correlated replies via
    // env.re before this point). Show it in the app's TOOL timeline and wake
    // the agent as a CUSTOM message — never as the user's own message.
    _deliverMeshMessageToAgent(env);
  });

  // After failover (leader died, we re-elected): the new broker's peers map
  // starts fresh, but our cached `_sessionPeerCount` is stale. Re-seed it so
  // surviving peers don't carry the pre-failover count forever.
  //
  // The cross-PC bridge re-attach on failover (drop the stale broker ref,
  // re-wire against the fresh `localBroker()` if we were promoted to leader)
  // is handled INSIDE MeshNode — no manual teardown/ensure needed here.
  peer.onReconnect(() => {
    _refreshSessionPeerCount(peer, ctx);
  });

  try {
    const assigned = await peer.connect();
    // Race guard: a `session_shutdown` may have landed while `connect()` was
    // in flight (the broker now has us registered, but this instance is being
    // discarded). Leave immediately instead of publishing a ghost peer that
    // the replacement instance would then collide with as `name#2`.
    if (_disposed) {
      try { await peer.close(); } catch { /* best-effort */ }
      return;
    }
    _meshNode = peer;
    _sessionName = sessionName;
    _sessionPeerCount = 1;  // optimistic — overwritten by list_peers below
    // Broker broadcasts `peer_joined` only to existing peers when a new one
    // arrives — the newcomer doesn't get retroactive joined events. Ask the
    // broker for the live peer list to seed the count correctly on join.
    _refreshSessionPeerCount(peer, ctx);
    // Tell RPC clients (e.g. Cockpit) the EFFECTIVE mesh name. The broker
    // appends a `#N` suffix only on a same-(cwd,name) collision, so the name we
    // requested and the one actually assigned can differ. Emit a pure-data event
    // (display:false) carrying both + a `changed` flag so the client can rename
    // the agent in its own UI to match what the mesh/relay will show. Fired on
    // every join (incl. failover re-elect, which can re-assign the name), so the
    // client always reflects the live name, not just the first one.
    //
    // plan/38 decision E: we deliberately DO NOT persist `assigned`. A `#N` is a
    // RUNTIME collision resolution; freezing it into `agent_name` fossilizes an
    // accident and causes cross-folder name ping-pong across restarts. The clean
    // name (wizard / explicit `agent_name`) already lives in config or re-derives
    // from `basename(cwd)`; the event above carries the live `#N` for the UI.
    _pi?.sendMessage({
      customType: "remote-pi:name-assigned",
      content: assigned === requestedName
        ? `Mesh name: ${assigned}`
        : `Mesh name reassigned: "${requestedName}" → "${assigned}" (collision)`,
      details: { requested: requestedName, assigned, changed: assigned !== requestedName },
      display: false,
    });
    ctx.ui.notify(
      `[remote-pi] Joined local mesh as "${assigned}" (${peer.currentRole()})`,
      "info",
    );
    _refreshFooter(ctx);
    // Plan/25 Wave B/C: try to bring up cross-PC routing now that the
    // local broker exists. No-op if the relay isn't up yet (will fire
    // again from `_cmdStart`).
    _attachBridgeIfReady();
  } catch (err) {
    ctx.ui.notify(`[remote-pi] join failed: ${String(err)}`, "error");
  }
}

// ── routeClientMessage ────────────────────────────────────────────────────────

/**
 * Per-channel router. Replaces the W2D-pre `routeClientMessage` which
 * implicitly used the `_peerChannel` singleton for replies. Each
 * PlainPeerChannel now carries its own `sender` and passes it here so
 * sender-specific responses (cancelled, pong, session_history) flow back
 * through the right wire instead of being broadcast.
 *
 * Broadcast messages (user_input mirror, agent_chunk, tool_*) still use
 * `_broadcastToActive` from the SDK event handlers; this router only
 * handles incoming app→pi requests.
 */
function _abortCurrentTurn(
  fallbackCtx?: Pick<ExtensionContext, "abort">,
): boolean {
  const candidates: Array<Pick<ExtensionContext, "abort"> | null | undefined> = [
    _lastEventCtx,
    _lastCtx,
    fallbackCtx,
  ];

  for (const candidate of candidates) {
    if (!candidate || candidate === _noopCtx) continue;
    if (typeof candidate.abort !== "function") continue;
    candidate.abort();
    return true;
  }

  return false;
}

export function _routeClientMessageFrom(
  sender: PlainPeerChannel,
  msg: ClientMessage,
  ctx: Pick<ExtensionContext, "abort">,
): void {
  // session_sync has its own internal guards — handle before the strict
  // pi-binding guard so a missing _pi doesn't drop the reply.
  if (msg.type === "session_sync") {
    _handleSessionSync(sender, msg);
    return;
  }
  if (msg.type === "cancel") {
    try {
      const aborted = _abortCurrentTurn(ctx);
      if (!aborted) {
        sender.send({
          type: "error",
          code: "internal_error",
          in_reply_to: msg.id,
          message: "No active Pi context to abort",
        });
        return;
      }
      sender.send({ type: "cancelled", in_reply_to: msg.id, target_id: msg.target_id });
    } catch (err) {
      sender.send({
        type: "error",
        code: "internal_error",
        in_reply_to: msg.id,
        message: `Abort failed: ${String(err)}`,
      });
    }
    return;
  }
  if (!_pi) return;
  switch (msg.type) {
    case "user_message": {
      // Source-of-truth rebroadcast (plan/24 W2D fix). Echo the message
      // back to every attached owner (sender included) after the SDK accepts
      // the handoff, so optimistic app bubbles only confirm on real delivery.
      //   1. The sender's app waits for this echo to render (no eager
      //      local store), keeping all owners visually consistent.
      //   2. Other owners see what was said, not just the agent's reply.
      //   3. `id` is preserved verbatim, so future dedup logic on the app
      //      side can key off it.
      // The user_message is also recorded in _messageBuffer indirectly
      // via `pi.on("message_end")` after the SDK persists the turn — so
      // a later `session_sync` returns it in the history events.
      // Plan/30: echo any inline images too so every owner renders the same
      // image bubble. No-image path is byte-identical to before (no `images`
      // key on the wire).
      const requestedSteer = msg.streaming_behavior === "steer";
      const inferredBusySteer = !requestedSteer && _myRoomMeta?.working === true;
      const shouldSteer = requestedSteer || inferredBusySteer;
      // A reconnecting app can correctly send `steer` while our mirror has no
      // turn id (for example, the turn started while no owner was attached).
      // Also be defensive for clients that send a plain user_message while the
      // room is already working. Tell the SDK this is steering; otherwise it
      // rejects the message as a normal busy prompt. Seed a fallback id so
      // later chunks/done have a target instead of being dropped.
      const previousTurnId = _currentTurnId;
      const seededTurnId = !shouldSteer || _currentTurnId === null;
      if (seededTurnId) {
        _currentTurnId = msg.id;
      }
      const content: Parameters<ExtensionAPI["sendUserMessage"]>[0] =
        msg.images && msg.images.length > 0
          ? [
              ...msg.images.map((img) => ({ type: "image" as const, data: img.data, mimeType: img.mime })),
              { type: "text" as const, text: msg.text },
            ]
          : msg.text;
      // Always include a streaming delivery mode for app-originated messages.
      // The SDK ignores `deliverAs` when idle, but requires it when a turn is
      // already running. This avoids a race where Remote Pi's mirror has not
      // seen turn_start/currentTurnId yet but the SDK is already busy.
      const wake = _wakeAgent(
        content,
        msg.images && msg.images.length > 0
          ? `app user_message id=${msg.id} (+${msg.images.length} image)`
          : `app user_message id=${msg.id}`,
        "steer",
      );
      if (!wake.ok) {
        if (seededTurnId) _currentTurnId = previousTurnId;
        sender.send({
          type: "error",
          code: "internal_error",
          in_reply_to: msg.id,
          message: `Agent rejected incoming message: ${wake.detail}`,
        });
        break;
      }
      const echo: ServerMessage = {
        type: "user_message",
        id: msg.id,
        text: msg.text,
        ...(msg.images && msg.images.length > 0 ? { images: msg.images } : {}),
        ...(shouldSteer ? { streaming_behavior: "steer" as const } : {}),
      };
      _broadcastToActive(echo);
      break;
    }
    case "approve_tool":
      // Approval gate was removed (plano 10.2 revisado). Type kept in
      // ClientMessage for forward-compat with a future permissions model;
      // ignore silently if the app still sends it from an older build.
      break;
    case "ping":
      sender.send({ type: "pong", in_reply_to: msg.id });
      break;
    case "pair_request":
      // Already paired — ignore subsequent pair_request to maintain idempotency.
      // (Token is already consumed and peer is in peers.json.)
      break;
    // Plan/28 — Typed app actions. Each delegates to the pure handler in
    // `actions/handlers.ts`; the only thing this layer does is unify the
    // dep injection (sender, _pi, _lastCtx, registry). `_lastCtx` may be
    // null or a narrower Pick than the handlers want, so we cast to
    // `ActionCtx` — fields that aren't present at runtime are surfaced
    // as `action_error` by the handlers, not as a TypeError.
    case "session_compact":
      // Route through _lastEventCtx (refreshed on every session_start), NOT the
      // capturable-stale _lastCtx — compact must never hit a ctx left stale by
      // a prior New session. compact() is a base-ctx method, so the
      // session_start ctx suffices. Fall back to _lastCtx defensively if no
      // session_start has landed yet (keeps the pre-replacement happy path).
      handleSessionCompact((_lastEventCtx ?? _lastCtx) as ActionCtx | null, sender, msg);
      break;
    case "session_new": {
      const actionCtx = _lastCtx as ActionCtx | null;
      if (process.env["REMOTE_PI_DAEMON"] === "1" && !actionCtx?.newSession) {
        // Headless RPC daemon has no ExtensionCommandContext, so ctx.newSession
        // is unavailable. Ack, clear remote-pi's mirror, then exit with a
        // private code; the supervisor restarts once without --continue, which
        // creates a fresh Pi session. Later restarts resume that fresh session.
        sender.send({ type: "action_ok", in_reply_to: msg.id, action: "session_new" });
        _resetSessionForNew(msg.id);
        setTimeout(() => process.exit(EXIT_DAEMON_FRESH_SESSION), 100);
        break;
      }
      void handleSessionNew(
        actionCtx,
        sender,
        msg,
        (freshCtx) => {
          // newSession just made the captured _lastCtx STALE (the SDK throws
          // if it's reused). Re-capture the fresh command-capable ctx the SDK
          // passes to withSession so later command ops (another New session,
          // list_models) run on the current session, not the stale one. The
          // runtime object also carries ui/abort/cwd, so storing it in the
          // narrowly-typed _lastCtx slot is sound (mirrors the read-site casts).
          _lastCtx = freshCtx as unknown as typeof _lastCtx;
        },
      ).then((created) => {
        // Pi-side reset is durable only here: handleSessionNew swaps the SDK
        // session, but the app's session_sync log (_messageBuffer) and the
        // session clock (_sessionStartedAt) live in this module. Reset them +
        // fan out an empty history so every owner drops the stale conversation
        // — not just the sender, who also clears locally on action_ok.
        if (created) _resetSessionForNew(msg.id);
      });
      break;
    }
    case "model_set":
      void handleModelSet(
        _pi,
        (_lastEventCtx ?? _lastCtx) as ActionCtx | null,
        ensureModelRegistry(),
        sender,
        msg,
        _persistModelDefault,
      );
      break;
    case "thinking_set":
      handleThinkingSet(_pi, sender, msg);
      break;
    case "list_models":
      handleListModels(((_lastEventCtx ?? _lastCtx) as ActionCtx | null), ensureModelRegistry(), sender, msg);
      break;
  }
}

/**
 * Backward-compatible shim for legacy callers + tests that didn't track
 * a specific sender channel. Routes to the most recently attached owner,
 * mirroring the pre-W2D singleton behavior.
 */
export function routeClientMessage(
  msg: ClientMessage,
  ctx: Pick<ExtensionContext, "abort">,
): void {
  const fallback = [..._activePeers.values()].pop();
  if (!fallback) return;
  _routeClientMessageFrom(fallback, msg, ctx);
}

// ── session_sync handler + helpers ────────────────────────────────────────────

/**
 * `session_sync` is a per-sender query: the owner asking gets the reply,
 * not the whole broadcast. Otherwise a session_sync from owner A would
 * also dump history to owner B's wire — duplicate traffic + the wrong
 * `in_reply_to`.
 */
function _handleSessionSync(
  sender: PlainPeerChannel,
  msg: Extract<ClientMessage, { type: "session_sync" }>,
): void {
  if (_sessionStartedAt === null) {
    sender.send({
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

  sender.send({
    type: "session_history",
    in_reply_to: msg.id,
    session_started_at: _sessionStartedAt,
    events: slice,
    eos: true,
    truncated,
  });
}

/**
 * Resets the Pi-side session view after a SUCCESSFUL `session_new`. The app's
 * New Session clears its local store on `action_ok`, but that alone isn't
 * durable: `_messageBuffer` (which answers `session_sync`) is append-only and
 * `_sessionStartedAt` is stamped once, so a later reconnect/restart would
 * replay the OLD history. We clear the buffer, restamp the clock, and
 * broadcast an EMPTY `session_history` — the exact shape `_handleSessionSync`
 * sends, just with `events: []` — so every attached owner drops the stale
 * conversation. The app's `_applyHistory` substitutes its cache wholesale, so
 * no new app-side code is needed.
 *
 * Unlike a per-request session_history reply (which must go to the sender
 * channel only — see `_broadcastToActive`), this is an intentional fan-out:
 * a new session is global state, so every owner must see the reset.
 */
function _resetSessionForNew(inReplyTo: string): void {
  _messageBuffer = [];
  _sessionStartedAt = Date.now();
  _broadcastToActive({
    type: "session_history",
    in_reply_to: inReplyTo,
    session_started_at: _sessionStartedAt,
    events: [],
    eos: true,
    truncated: false,
  });
}

type ToolArgs = Record<string, unknown>;
type DiffLine =
  | { kind: "context"; oldLine?: number; newLine?: number; text: string }
  | { kind: "remove"; oldLine?: number; text: string }
  | { kind: "add"; newLine?: number; text: string }
  | { kind: "ellipsis" };

function _enrichToolArgs(tool: string, args: unknown): ToolArgs {
  if (!args || typeof args !== "object") return {};
  const base = args as ToolArgs;

  switch (tool.toLowerCase()) {
    case "edit":
      return _enrichEditToolArgs(base);
    default:
      return base;
  }
}

function _enrichEditToolArgs(base: ToolArgs): ToolArgs {
  const filePath = _stringArg(base, ["path", "file_path"]);
  const rawEdits = base["edits"];
  const edits = Array.isArray(rawEdits) ? rawEdits : [base];
  const text = _readToolFile(filePath);
  const hunks: { lines: DiffLine[] }[] = [];
  let searchFrom = 0;
  for (const rawEdit of edits) {
    if (!rawEdit || typeof rawEdit !== "object") continue;
    const edit = rawEdit as ToolArgs;
    const oldText = _stringArg(edit, ["oldText", "old_text", "old_string", "oldString"]);
    const newText = _stringArg(edit, ["newText", "new_text", "new_string", "newString"]);
    if (!oldText && !newText) continue;

    const matchAt = oldText && text !== null ? text.indexOf(oldText, searchFrom) : -1;
    const fallbackAt = oldText && matchAt < 0 && text !== null ? text.indexOf(oldText) : matchAt;
    const startOffset = fallbackAt >= 0 ? fallbackAt : searchFrom;
    if (text === null) continue;
    const hunk = _buildEditHunk(text, startOffset, oldText, newText);
    if (hunk.length > 0) hunks.push({ lines: hunk });
    searchFrom = startOffset + Math.max(oldText.length, 1);
  }

  return hunks.length === 0 ? base : { ...base, hunks };
}

function _readToolFile(filePath: string): string | null {
  if (!filePath) return null;
  const cwd = _lastCtx && "cwd" in _lastCtx ? _lastCtx.cwd : process.cwd();
  const homePath = filePath.startsWith("~/") && process.env.HOME
    ? resolve(process.env.HOME, filePath.slice(2))
    : null;
  const candidates = [filePath, resolve(cwd, filePath), resolve(process.cwd(), filePath), homePath]
    .filter((p): p is string => typeof p === "string");
  for (const candidate of candidates) {
    try {
      return readFileSync(candidate, "utf8");
    } catch {
      // try next candidate
    }
  }
  return null;
}


function _buildEditHunk(
  fileText: string,
  startOffset: number,
  oldText: string,
  newText: string,
): DiffLine[] {
  const context = 4;
  const fileLines = fileText.split("\n");
  const oldLines = _splitPreviewLines(oldText);
  const newLines = _splitPreviewLines(newText);
  const oldStart = _lineNumberAt(fileText, startOffset);
  const newStart = oldStart;
  const startIndex = oldStart - 1;
  const beforeStart = Math.max(0, startIndex - context);
  const afterStart = startIndex + oldLines.length;
  const afterEnd = Math.min(fileLines.length, afterStart + context);
  const out: DiffLine[] = [];

  if (beforeStart > 0) out.push({ kind: "ellipsis" });
  for (let i = beforeStart; i < startIndex; i++) {
    out.push({ kind: "context", oldLine: i + 1, newLine: i + 1, text: fileLines[i] ?? "" });
  }
  let commonPrefix = 0;
  while (
    commonPrefix < oldLines.length &&
    commonPrefix < newLines.length &&
    oldLines[commonPrefix] === newLines[commonPrefix]
  ) {
    commonPrefix++;
  }

  let commonSuffix = 0;
  while (
    commonSuffix < oldLines.length - commonPrefix &&
    commonSuffix < newLines.length - commonPrefix &&
    oldLines[oldLines.length - 1 - commonSuffix] === newLines[newLines.length - 1 - commonSuffix]
  ) {
    commonSuffix++;
  }

  for (let i = 0; i < commonPrefix; i++) {
    out.push({ kind: "context", oldLine: oldStart + i, newLine: newStart + i, text: oldLines[i] ?? "" });
  }
  for (let i = commonPrefix; i < oldLines.length - commonSuffix; i++) {
    out.push({ kind: "remove", oldLine: oldStart + i, text: oldLines[i] ?? "" });
  }
  for (let i = commonPrefix; i < newLines.length - commonSuffix; i++) {
    out.push({ kind: "add", newLine: newStart + i, text: newLines[i] ?? "" });
  }
  for (let i = oldLines.length - commonSuffix; i < oldLines.length; i++) {
    const newLine = newStart + newLines.length - (oldLines.length - i);
    out.push({ kind: "context", oldLine: oldStart + i, newLine, text: oldLines[i] ?? "" });
  }
  for (let i = afterStart; i < afterEnd; i++) {
    const newLine = newStart + newLines.length + (i - afterStart);
    out.push({ kind: "context", oldLine: i + 1, newLine, text: fileLines[i] ?? "" });
  }
  if (afterEnd < fileLines.length) out.push({ kind: "ellipsis" });
  return out;
}

function _lineNumberAt(text: string, offset: number): number {
  let line = 1;
  for (let i = 0; i < Math.max(0, offset); i++) if (text[i] === "\n") line++;
  return line;
}

function _splitPreviewLines(text: string): string[] {
  if (!text) return [];
  const lines = text.split("\n");
  if (lines.length > 0 && lines[lines.length - 1] === "") lines.pop();
  return lines;
}

function _stringArg(args: ToolArgs, keys: string[]): string {
  for (const key of keys) {
    const value = args[key];
    if (typeof value === "string") return value;
  }
  return "";
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
 * Stringify a tool result consistently for BOTH the live `tool_execution_end`
 * broadcast AND the history mapper, so the app shows the same text live and on
 * re-sync. The SDK's `ToolExecutionEndEvent.result` is `any` — usually a
 * content-array of `{type:"text"}` blocks; `String()` on that yields the
 * "[object Object]" bug. Rules: string → as-is; content-array → join its text
 * (same as `_stringifyContent`); any other object → readable JSON; other
 * primitives → `String()`; null/undefined → "". Never "[object Object]".
 */
function _stringifyToolResult(value: unknown): string {
  if (typeof value === "string") return value;
  if (Array.isArray(value)) return _stringifyContent(value);
  if (value !== null && typeof value === "object") {
    // The LIVE `tool_execution_end` result is a WRAPPER object
    // `{ content: [{type:"text",...}], details:{} }` — not the bare
    // content-array the history path (`m.content`) carries. Unwrap `content`
    // (or a plain `text`) so live == re-sync; JSON is only the last fallback.
    const obj = value as { content?: unknown; text?: unknown };
    if (Array.isArray(obj.content)) return _stringifyContent(obj.content);
    if (typeof obj.text === "string") return obj.text;
    try { return JSON.stringify(value); } catch { return ""; }
  }
  return value === null || value === undefined ? "" : String(value);
}

/**
 * Plan/30: extract `ImageContent` blocks ({type:"image", data, mimeType}) from
 * an SDK message's content and map them to the wire shape (`mimeType` → `mime`).
 * Used by the history mapper so a re-synced image bubble keeps its bytes —
 * `_stringifyContent` only pulls text and would otherwise drop the image.
 */
function _imagesFromContent(content: unknown): WireImage[] {
  if (!Array.isArray(content)) return [];
  const out: WireImage[] = [];
  for (const c of content) {
    if (!c || typeof c !== "object") continue;
    const block = c as { type?: string; data?: unknown; mimeType?: unknown };
    if (block.type === "image" && typeof block.data === "string" && typeof block.mimeType === "string") {
      out.push({ data: block.data, mime: block.mimeType });
    }
  }
  return out;
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

    if (m.role === "compaction") {
      // Plan/32: re-render the compaction notice on history re-sync.
      events.push({
        ts,
        type: "compaction",
        summary: typeof m.content === "string" ? m.content : "",
        tokens_before: typeof m.tokensBefore === "number" ? m.tokensBefore : 0,
      });
    } else if (m.role === "user") {
      const id = `sync_${ts}`;
      lastUserId = id;
      // Plan/30: keep any image blocks so a re-sync rebuilds the bubble. The
      // bytes are already in _messageBuffer; only attach `images` when present
      // so the text-only path stays byte-identical (no `images` key).
      const images = _imagesFromContent(m.content);
      const ev: SessionHistoryEvent = {
        ts,
        type: "user_input",
        id,
        text: _stringifyContent(m.content),
      };
      if (images.length > 0) ev.images = images;
      events.push(ev);
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
      // Same helper as the live `tool_execution_end` broadcast → live == re-sync.
      const text = _stringifyToolResult(m.content);
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

/**
 * `remote-pi restart-supervisor` — restarts the `pi-supervisord` PROCESS
 * (not the daemons). The supervisor is a long-running Node process with no
 * hot-reload, so after a `dist` rebuild the old code keeps running until the
 * process is restarted. The Cockpit "Restart supervisor" button shells out to
 * this; the OS-specific restart lives here so the app stays cross-platform.
 *
 * Restarting the supervisor re-spawns every daemon as a side effect. Exits 0
 * on success, non-zero on failure (the Cockpit detects failure by exit code).
 */
/** One step of a restart sequence. `ignoreFailure` steps (e.g. `schtasks /End`
 *  when the task isn't running) don't abort the sequence. */
export interface RestartStep { cmd: string; args: string[]; ignoreFailure?: boolean }

/** Pure: the OS command sequence that restarts the supervisor service, or null
 *  when the platform isn't supported. Most platforms are 1 step; Windows is 2
 *  (`schtasks /End` then `/Run`). Exported for tests. */
export function _restartSupervisorCommand(
  platform: NodeJS.Platform,
  uid: number,
): RestartStep[] | null {
  if (platform === "darwin") return [{ cmd: "launchctl", args: ["kickstart", "-k", `gui/${uid}/${LAUNCHD_LABEL}`] }];
  if (platform === "linux") return [{ cmd: "systemctl", args: ["--user", "restart", SYSTEMD_UNIT] }];
  if (platform === "win32") return [
    { cmd: "schtasks", args: ["/End", "/TN", WINDOWS_TASK_NAME], ignoreFailure: true },
    { cmd: "schtasks", args: ["/Run", "/TN", WINDOWS_TASK_NAME] },
  ];
  return null;
}

function _restartSupervisor(): void {
  const uid = process.getuid?.() ?? 0;
  const steps = _restartSupervisorCommand(process.platform, uid);
  if (!steps) {
    console.error(
      `[remote-pi] restart-supervisor is not supported on '${process.platform}' yet. ` +
      "Restart pi-supervisord manually.",
    );
    process.exit(1);
  }
  for (const step of steps) {
    const r = spawnSync(step.cmd, step.args, { stdio: ["ignore", "pipe", "pipe"], encoding: "utf8" });
    if (r.error) {
      if (step.ignoreFailure) continue;
      console.error(`[remote-pi] restart-supervisor failed: ${step.cmd} not runnable (${r.error.message}). Is the service installed? Run \`remote-pi install\`.`);
      process.exit(1);
    }
    if (r.status !== 0 && !step.ignoreFailure) {
      const detail = (r.stderr || r.stdout || "").trim();
      console.error(`[remote-pi] restart-supervisor failed (${step.cmd} exited ${r.status})${detail ? `: ${detail}` : ""}.`);
      process.exit(r.status === null ? 1 : r.status);
    }
  }
  console.log("[remote-pi] Supervisor restarted.");
}

function _isDirectRun(): boolean {
  try {
    return fileURLToPath(import.meta.url) === realpathSync(process.argv[1] ?? "");
  } catch {
    return false;
  }
}

/**
 * Read-only probe of the local UDS broker for the mesh roster, backing
 * `remote-pi peers`. Opens a raw connection to `sockPath`, sends a single
 * unregistered `list_peers` request, and resolves with the peer names from the
 * broker's reply (local UDS peers + cross-PC `<pc>:<peer>` entries).
 *
 * The probe deliberately does NOT register as a peer: the broker answers
 * observer probes without assigning a name or broadcasting peer_joined/left
 * (see Broker._tryObserverProbe), so a shell query never perturbs the mesh —
 * no phantom peer flashes in anyone's roster, local or cross-PC.
 *
 * Resolves null when no broker is reachable (connection refused / no socket
 * file — i.e. no Pi or daemon is leading the mesh on this machine), or on
 * timeout, so the caller can print an "offline" message instead of an empty
 * roster.
 */
export async function probeListPeers(
  sockPath: string,
  timeoutMs = 2000,
): Promise<string[] | null> {
  const { createConnection } = await import("node:net");
  return new Promise<string[] | null>((resolve) => {
    const sock = createConnection({ path: sockPath });
    let buf = "";
    let settled = false;
    const done = (result: string[] | null): void => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      try { sock.destroy(); } catch { /* already gone */ }
      resolve(result);
    };
    const timer = setTimeout(() => done(null), timeoutMs);
    sock.setEncoding("utf8");
    sock.on("connect", () => {
      try { sock.write(JSON.stringify({ type: "list_peers" }) + "\n"); }
      catch { done(null); }
    });
    sock.on("data", (chunk: string) => {
      buf += chunk;
      const nl = buf.indexOf("\n");
      if (nl < 0) return;  // wait for a full line
      const line = buf.slice(0, nl);
      try {
        const env = JSON.parse(line) as { body?: { type?: string; peers?: unknown } };
        const body = env.body;
        if (body && body.type === "list_peers_reply" && Array.isArray(body.peers)) {
          done(body.peers.filter((p): p is string => typeof p === "string"));
          return;
        }
      } catch { /* fall through */ }
      done(null);  // a line arrived but it wasn't the reply we expected
    });
    sock.on("error", () => done(null));  // ECONNREFUSED / ENOENT → mesh offline
    sock.on("close", () => done(null));
  });
}

if (_isDirectRun()) {
  const [, , subcmd, ...cliArgs] = process.argv;
  if (subcmd === "devices" || subcmd === "list") {
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
    const raw = (cliArgs[0] ?? "").trim();
    if (!raw) {
      console.log(`Usage: set-relay <url> (default: ${kDefaultRelayUrl})`);
    } else if (isWebSocketScheme(raw)) {
      console.log(`Use http:// or https://. The extension converts to WebSocket automatically.`);
    } else if (!isValidRelayUrl(raw)) {
      console.log(`Invalid URL: ${raw}. Must start with http:// or https://`);
    } else {
      saveConfig({ relay: raw });
      console.log(`Relay set to ${raw}`);
    }
  } else if (subcmd === "create") {
    // Standalone: `remote-pi create <cwd> [--name "X"]`. The shell already
    // split the args and stripped the outer quotes, so an arg like
    // `Tmp Agent` arrives as a single element with embedded space. Re-add
    // quotes around any arg containing whitespace so the regex-based
    // parser (shared with the slash-command path) sees the same shape
    // as it would from a Pi interactive prompt.
    const joined = cliArgs.map((a) => (/\s/.test(a) ? `"${a}"` : a)).join(" ");
    await _cmdCreate(joined, {
      ui: { notify: (msg: string) => console.log(msg) } as unknown as ExtensionContext["ui"],
    });
  } else if (subcmd === "remove") {
    const id = (cliArgs[0] ?? "").trim();
    await _cmdRemove(id, {
      ui: { notify: (msg: string) => console.log(msg) } as unknown as ExtensionContext["ui"],
    });
  } else if (subcmd === "daemons") {
    // Mirror the slash handler: ask the supervisor when reachable,
    // fall back to registry-only when not.
    const stubCtx = { ui: { notify: (msg: string) => console.log(msg) } as unknown as ExtensionContext["ui"] };
    await _cmdDaemonsList(stubCtx);
  } else if (subcmd === "daemon") {
    // `remote-pi daemon <op> [args]`. Reuse the fleet-ops handlers — they
    // already accept a minimal ctx with `notify`.
    const op = cliArgs[0] ?? "";
    const rest = cliArgs.slice(1).map((a) => (/\s/.test(a) ? `"${a}"` : a)).join(" ");
    const stubCtx = { ui: { notify: (msg: string) => console.log(msg) } as unknown as ExtensionContext["ui"] };
    if      (op === "start")   { await _cmdDaemonStart(stubCtx, cliArgs[1]); }
    else if (op === "stop")    { await _cmdDaemonStop(stubCtx, cliArgs[1]); }
    else if (op === "restart") { await _cmdDaemonRestart(stubCtx, cliArgs[1]); }
    else if (op === "status")  { await _cmdDaemonStatus(stubCtx); }
    else if (op === "send")    { await _cmdDaemonSend(rest, stubCtx); }
    else {
      console.log("Usage: remote-pi daemon <start|stop|restart [<id>]|status|send <id> \"<text>\">");
    }
  } else if (subcmd === "cron") {
    // `remote-pi cron <op> [args]`. Re-quote args with spaces so the shared
    // parser sees the same shape as a Pi slash prompt.
    const joined = cliArgs.map((a) => (/\s/.test(a) ? `"${a}"` : a)).join(" ");
    const stubCtx = { ui: { notify: (msg: string) => console.log(msg) } as unknown as ExtensionContext["ui"] };
    await _cmdCron(joined, stubCtx);
  } else if (subcmd === "peers") {
    // Read-only roster of the local + cross-PC mesh. Unlike `devices` (which
    // reads paired phones from peers.json), the mesh roster lives only in the
    // running broker's memory, so we probe the UDS broker. The probe never
    // registers as a peer — it leaves no trace on the mesh (see
    // Broker._tryObserverProbe). Null = no broker reachable on this machine.
    const peers = await probeListPeers(sessionSockPath(LOCAL_SESSION_NAME));
    if (peers === null) {
      console.log("[remote-pi] Mesh offline — no agent is running on this machine.");
    } else {
      console.log(`[remote-pi] peers:\n${formatPeerInventory(peers)}`);
    }
  } else if (subcmd === "claude") {
    await _cmdClaudeCli(cliArgs);
  } else if (subcmd === "install") {
    // CLI mode = user installed via `npm install -g remote-pi`, so the
    // `remote-pi` / `pi-supervisord` bins are already on $PATH via npm's
    // global prefix. Explicit `linkCli: false` so we never stomp those
    // with symlinks pointing at a parallel Pi-extension install.
    const stubCtx = { ui: { notify: (msg: string) => console.log(msg) } as unknown as ExtensionContext["ui"] };
    // Propagate failure as a non-zero exit so callers (Cockpit / CI) detect it
    // — installService throws on a failed schtasks/launchctl/systemctl step.
    if (!_cmdInstall(stubCtx, { linkCli: false })) process.exit(1);
  } else if (subcmd === "uninstall") {
    const stubCtx = { ui: { notify: (msg: string) => console.log(msg) } as unknown as ExtensionContext["ui"] };
    // `linkCli: true` even from the CLI: unlinking is ALWAYS safe and must run
    // regardless of how install ran. `unlinkCliBinaries` only removes OUR
    // reserved symlinks (`remote-pi` / `pi-supervisord`) under `~/.local/bin`;
    // npm-global bins live in a different prefix and are never touched. So a
    // user who installed via the TUI (`/remote-pi install`, which links) and
    // uninstalls from a shell still gets the links cleaned up — the asymmetry
    // that left an orphaned `~/.local/bin/remote-pi` behind.
    _cmdUninstall(stubCtx, { linkCli: true });
  } else if (subcmd === "restart-supervisor") {
    _restartSupervisor();
  } else {
    console.log([
      "Usage: remote-pi <command>",
      "",
      "Daemon registry:",
      "  create <cwd> [--name \"Name\"]   Register a folder as a daemon",
      "  remove <id>                     Unregister a daemon",
      "  daemons                         List registered daemons",
      "",
      "Fleet control:",
      "  daemon start [<id>]             Start all daemons, or one by id",
      "  daemon stop [<id>]              Stop all daemons, or one by id",
      "  daemon restart [<id>]           Restart all daemons, or one by id",
      "  daemon status                   Show pid / uptime / restarts",
      "  daemon send <id> \"<text>\"       Send a prompt to a daemon",
      "  cron add <id> \"<expr>\" \"<txt>\"  Schedule a recurring prompt (≥60s; --tz, --wake)",
      "  cron list|run|remove|log        Manage scheduled prompts (needs the supervisor)",
      "",
      "Service:",
      "  install                         Install pi-supervisord as a system service",
      "  uninstall                       Remove the system service",
      "  restart-supervisor              Restart the pi-supervisord process",
      "",
      "Devices:",
      "  devices                         List paired phones (peers.json)",
      "  revoke <shortid>                Revoke a paired device",
      "",
      "Config:",
      "  set-relay <url>                 Set the relay URL (http:// or https://)",
      "",
      "Agent mesh:",
      "  peers                           List agents on the local + cross-PC mesh",
      "  claude [cwd]                    Start Claude Code connected to the agent mesh",
    ].join("\n"));
  }
}

// ── `remote-pi claude` — launch Claude Code connected to the mesh ─────────────

/**
 * Resolve the packaged agent-network skill path
 * (`<pkgRoot>/skills/agent-network/SKILL.md`). Single source of truth shared
 * by both runtimes: Pi discovers it via `resources_discover`, and the Claude
 * launcher injects it as a system prompt (see `_cmdClaudeCli`). Returns null
 * if the file is missing (e.g. running before `pnpm build`).
 */
function _agentNetworkSkillPath(): string | null {
  const here = fileURLToPath(import.meta.url);            // dist/index.js (or src/index.ts via tsx)
  const pkgRoot = dirname(dirname(here));                 // package root (dist → ..; src → ..)
  const skill = join(pkgRoot, "skills", "agent-network", "SKILL.md");
  return existsSync(skill) ? skill : null;
}

async function _cmdClaudeCli(args: string[]): Promise<void> {
  // Contract: `remote-pi claude [cwd] [claude-flags...]`. The optional cwd is
  // ONLY the leading positional (first token, not a flag); everything after it
  // is forwarded verbatim to the `claude` binary (e.g. `--resume`, `-c`,
  // `-p "prompt"`). Restricting cwd to the leading token avoids mistaking a
  // flag's value (e.g. the id in `--resume <id>`) for the cwd.
  const hasCwdArg = args.length > 0 && !args[0]!.startsWith("-");
  const targetCwd = hasCwdArg ? args[0]! : process.cwd();
  const passthroughArgs = hasCwdArg ? args.slice(1) : args;

  // Wizard when no local config exists
  if (!localConfigExists(targetCwd)) {
    const suggested = defaultAgentName(targetCwd);
    process.stdout.write(`\n[remote-pi] No config found for ${targetCwd}\n`);
    process.stdout.write("Let's set up this agent.\n\n");

    const rl = createInterface({ input: process.stdin, output: process.stdout });
    const agentName: string = await new Promise((res) =>
      rl.question(`Agent name [${suggested}]: `, (ans) => { rl.close(); res(ans.trim() || suggested); }),
    );

    saveLocalConfig(targetCwd, { agent_name: agentName, auto_start_relay: true });
    process.stdout.write(`[remote-pi] Config saved: agent="${agentName}"\n\n`);
  }

  // Resolve mesh server script path (dist/mcp/mesh_server.js)
  const here = fileURLToPath(import.meta.url);
  const distRoot = dirname(here);
  const meshServerPath = resolve(distRoot, "mcp/mesh_server.js");

  if (!existsSync(meshServerPath)) {
    console.log(`[remote-pi] mesh server not found at ${meshServerPath}. Run pnpm build first.`);
    process.exit(1);
  }

  const absCwd = resolve(targetCwd);
  const SERVER_NAME = "remote-pi-mesh";

  // The mesh MCP must be visible ONLY inside a `remote-pi claude` session — a
  // plain `claude` in the same repo must NOT inherit it (otherwise every
  // ordinary session silently joins the mesh as a stray agent).
  //
  // Older builds registered the server with `claude mcp add -s local`. That
  // scope lives in `~/.claude.json` keyed by the **git repo root** and is
  // inherited by EVERY claude session under that root — which is exactly the
  // leak we're closing. So we no longer write any persistent scope; we load
  // the server through an ephemeral `--mcp-config <tmpfile>` passed on the
  // launch command line (see below). That config is session-only: it is never
  // recorded in any scope `claude mcp list` enumerates, so a normal `claude`
  // sees nothing.
  //
  // Migration: best-effort scrub of the stale `-s local` entry that prior
  // versions left behind (and that is the source of the inherited-mesh bug).
  // Idempotent — a no-op (non-zero, ignored) when the entry is already gone.
  spawnSync("claude", ["mcp", "remove", SERVER_NAME, "-s", "local"], {
    cwd: absCwd, stdio: "ignore", shell: false,
  });

  // Ephemeral MCP config consumed by `--mcp-config` below. We do NOT bake a
  // `cwd` into it: the server resolves its folder from its own `process.cwd()`,
  // which Claude sets to the directory the session was launched in (verified
  // empirically — NOT the git root, NOT CLAUDE_PROJECT_DIR). We spawn claude
  // with `cwd: absCwd`, the MCP child inherits it, so the server self-identifies
  // as the right agent without leaking that path to any other session.
  // Unique per pid so concurrent `remote-pi claude` launches don't collide.
  const mcpConfigPath = join(tmpdir(), `remote-pi-mesh-mcp-${process.pid}.json`);
  writeFileSync(mcpConfigPath, JSON.stringify({
    mcpServers: {
      [SERVER_NAME]: { command: process.execPath, args: [meshServerPath] },
    },
  }));

  // Inject the agent-network protocol as a system prompt instead of deploying a
  // skill file into ~/.claude. Anyone running `remote-pi claude` is here to use
  // the mesh, so load the protocol unconditionally — no lazy skill gating, no
  // global skills-dir pollution, and the packaged file is the single source of
  // truth shared with the Pi runtime. Skipped only if the file is missing.
  const skillPath = _agentNetworkSkillPath();

  // Launch flags:
  //   --mcp-config <tmpfile>                       — load the mesh server for
  //       THIS session only (never a persistent scope). We intentionally omit
  //       `--strict-mcp-config` so the user's own persistent MCP servers stay
  //       available alongside the mesh.
  //   --dangerously-load-development-channels TAG  — enable claude/channel push
  //       for our local (non-allowlisted) server, so incoming mesh messages
  //       wake Claude instead of waiting for a get_messages poll. Entries must
  //       be tagged: `server:<name>` for a manually configured MCP server
  //       (`plugin:<name>@<marketplace>` is the plugin form). Shows a one-time
  //       confirmation dialog at startup. Works against the `--mcp-config`
  //       server in current Claude Code; if a build ever fails to match it, the
  //       per-turn `get_messages` poll (mandated by the mesh protocol) still
  //       delivers — we lose the wake, not the messages.
  //   --dangerously-skip-permissions               — auto-approve tool calls
  //   --append-system-prompt-file=<skill>           — load the mesh protocol
  // `--append-system-prompt-file` uses the glued `--flag=value` form (a SINGLE
  // argv token) on purpose: tools that restore a session by capturing and
  // replaying the live process's argv (e.g. cmux) drop the TRAILING token,
  // which here was the skill path — leaving a dangling `--append-system-prompt-file`
  // → `claude` aborts with "argument missing" and the session never comes back.
  // As one token, the worst case is the whole flag being dropped: claude still
  // starts (just without the injected protocol), which is recoverable instead
  // of fatal. (The other flags stay separate pairs — never last, so unaffected,
  // and we don't risk a parser that may not accept `=`.)
  // Any extra args the user passed (e.g. `--resume`, `-c`) are appended last so
  // they reach the claude binary; ours come first as sensible defaults.
  try {
    spawnSync("claude", [
      "--mcp-config", mcpConfigPath,
      "--dangerously-load-development-channels", `server:${SERVER_NAME}`,
      "--dangerously-skip-permissions",
      ...(skillPath ? [`--append-system-prompt-file=${skillPath}`] : []),
      ...passthroughArgs,
    ], {
      cwd: absCwd,
      stdio: "inherit",
      shell: false,
    });
  } finally {
    // Session over — drop the ephemeral config so it never lingers as a stray
    // file. spawnSync blocks until claude exits, so claude has long since read
    // it. Best-effort: ignore if already gone.
    try { unlinkSync(mcpConfigPath); } catch { /* already removed */ }
  }
}
