#!/usr/bin/env node
/**
 * MCP server that bridges Claude Code to the remote-pi agent mesh.
 *
 * Spawned by Claude Code as an MCP server subprocess (stdio).
 * Joins the mesh through the shared `MeshNode` abstraction — the SAME
 * composition the Pi extension uses — so Claude is a first-class mesh
 * participant: it can lead the local UDS broker when no Pi/daemon is up,
 * and (as leader) bring up its own cross-PC relay bridge with its own
 * Pi-key. As a follower it rides the existing leader's bridge.
 *
 * Launched by `remote-pi claude` (registers this in Claude's local MCP
 * scope). Args: [--cwd <path>] [--name <agentName>] [--no-bridge]
 * Env: REMOTE_PI_MCP_CWD, REMOTE_PI_MCP_NAME
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { MeshNode } from "../session/mesh_node.js";
import { loadLocalConfig, defaultAgentName, localConfigExists } from "../session/local_config.js";
import { formatMeshAckResult } from "./mesh_result.js";
import { sessionSockPath, sessionAuditPath, LOCAL_SESSION_NAME } from "../session/global_config.js";
import { resolveRelayUrl } from "../config.js";
import { acquireCwdLock, type AcquiredLock } from "../session/cwd_lock.js";
import { realpathSync } from "node:fs";

// ── Args / config ─────────────────────────────────────────────────────────────

const _argv = process.argv.slice(2);
// This agent's folder = the dir the `claude` session was launched in, which
// Claude sets as this subprocess's `process.cwd()`. We deliberately do NOT use
// CLAUDE_PROJECT_DIR: that's the git repo root, which would collapse every
// monorepo subproject (app/, relay/, …) into one identity + one lock. The
// `remote-pi claude` launcher therefore registers us WITHOUT a baked `--cwd`,
// so one shared local-scope entry self-identifies per session. `--cwd` and
// REMOTE_PI_MCP_CWD remain as explicit overrides (tests / manual launches).
let _cwd = process.env["REMOTE_PI_MCP_CWD"] ?? process.cwd();
let _nameOverride = process.env["REMOTE_PI_MCP_NAME"];
let _bridgeEnabled = true;

for (let i = 0; i < _argv.length; i++) {
  if (_argv[i] === "--cwd" && _argv[i + 1]) { _cwd = _argv[++i]!; }
  else if (_argv[i] === "--name" && _argv[i + 1]) { _nameOverride = _argv[++i]; }
  else if (_argv[i] === "--no-bridge") { _bridgeEnabled = false; }
}

const _cfg = loadLocalConfig(_cwd);
const AGENT_NAME = _nameOverride ?? _cfg.agent_name ?? defaultAgentName(_cwd);
// Platform-aware (plan/40): POSIX → broker.sock file; Windows → named pipe.
const BROKER_SOCK = sessionSockPath(LOCAL_SESSION_NAME);
const AUDIT_PATH = sessionAuditPath(LOCAL_SESSION_NAME);

// ── Incoming message buffer ───────────────────────────────────────────────────

interface IncomingMsg {
  from: string;
  body: unknown;
  id: string;
  re: string | null;
  at: string;
}

const inbox: IncomingMsg[] = [];

// ── Mesh node ─────────────────────────────────────────────────────────────────

const { url: relayUrl } = resolveRelayUrl();

// Diagnostics go to STDERR — stdout is the JSON-RPC channel, so writing there
// would corrupt the MCP protocol. Claude Code captures an MCP server's stderr
// into its mcp-logs, which is where these land for debugging.
function logErr(msg: string): void {
  process.stderr.write(`[remote-pi-mesh ${isoNow()}] ${msg}\n`);
}

// Survive stray async failures. This process runs background work (relay WS
// churn, UDS failover, the MCP SDK) whose errors previously had NO global
// handler — a single unhandled rejection or exception silently killed this
// stdio subprocess, and Claude surfaced the MCP as "disconnected" with no
// trace. None of that background work is fatal to serving tools over stdio, so
// log loudly and keep running instead of dying. (We intentionally do NOT
// process.exit here: the tools stay available even if the mesh is degraded.)
process.on("unhandledRejection", (reason) => {
  logErr(`unhandledRejection: ${reason instanceof Error ? (reason.stack ?? reason.message) : String(reason)}`);
});
process.on("uncaughtException", (err) => {
  logErr(`uncaughtException: ${err.stack ?? err.message}`);
});

// Canonicalize so the (cwd, name) the broker keys us by matches roomIdForCwd
// and the Pi extension's own register (symlinked cwds map to one identity).
let _canonCwd = _cwd;
try { _canonCwd = realpathSync(_cwd); } catch { /* cwd missing — use raw path */ }

const mesh = new MeshNode({
  sockPath: BROKER_SOCK,
  name: AGENT_NAME,
  cwd: _canonCwd,  // plan/38: register with (cwd, name) → address `<cwd>@<name>`
  auditPath: AUDIT_PATH,
  // Own Pi-key cross-PC bridge — active only when this node leads (no Pi /
  // daemon already hosting the broker for this cwd). As a follower the
  // bridge stays dormant and cross-PC rides the existing leader.
  ...(_bridgeEnabled ? { bridge: { relayUrl, cwd: _cwd } } : {}),
  // Silent: stdout is the MCP JSON-RPC channel and stderr noise isn't wanted.
  // Real failures still surface via the global handlers / fail-loud below.
  log: () => { /* no-op */ },
});

let meshReady = false;
// When the mesh isn't joined, this explains why (folder busy / connecting), so
// the tools return something actionable instead of a generic "not connected".
let degradedReason = "connecting to the mesh…";

// ── MCP server setup ──────────────────────────────────────────────────────────

const mcp = new McpServer(
  { name: "remote-pi-mesh", version: "0.4.3" },
  {
    capabilities: { experimental: { "claude/channel": {} } },
    instructions: [
      `You are connected to the remote-pi agent mesh as "${AGENT_NAME}".`,
      "At the start of each turn call get_messages to check for incoming messages from other agents.",
      "Use list_peers to discover available agents.",
      "Use agent_send to send messages — pass the exact address returned by list_peers (form `<cwd>@<name>`, `<pc>:` prefix cross-PC) VERBATIM; never build one by hand.",
      'Use "broadcast" as the target to send to all peers in your folder (cwd) at once.',
      "Follow the agent-network protocol (in your system prompt) for the full details (ACK statuses, replies via re, `<cwd>@<name>` addresses, cross-PC `<pc>:` prefix).",
    ].join("\n"),
  },
);

function notReady() {
  return {
    content: [{ type: "text" as const, text: `Mesh not available yet — ${degradedReason}` }],
    isError: true,
  };
}

mcp.registerTool("list_peers", {
  description: "List all agents currently in the mesh (local + remote PCs).",
  inputSchema: {},
}, async () => {
  if (!meshReady) return notReady();
  try {
    const peers = await mesh.listPeers();
    return { content: [{ type: "text" as const, text: peers.length > 0 ? peers.join("\n") : "(no peers)" }] };
  } catch (e) {
    return { content: [{ type: "text" as const, text: `list_peers failed: ${String(e)}` }], isError: true };
  }
});

mcp.registerTool("agent_send", {
  description: 'Send a message to another agent. Use "broadcast" to send to all peers.',
  inputSchema: {
    to: z.string().describe('Peer address from list_peers (form "<cwd>@<name>", or "<pc>:<cwd>@<name>" cross-PC) echoed verbatim, or "broadcast"'),
    body: z.unknown().describe("Message body — any JSON value"),
    re: z.string().optional().describe("Optional: id of the message you are replying to"),
  },
}, async ({ to, body, re }) => {
  if (!meshReady) return notReady();
  if (to === mesh.address() || to === mesh.name()) {
    return { content: [{ type: "text" as const, text: "Cannot send to yourself" }], isError: true };
  }
  try {
    if (to === "broadcast") {
      await mesh.send(to, body, re ?? null);
      return { content: [{ type: "text" as const, text: "Broadcast sent" }] };
    }
    const ack = await mesh.sendWithAck(to, body, re ?? null);
    return formatMeshAckResult(to, ack);
  } catch (e) {
    return { content: [{ type: "text" as const, text: `send failed: ${String(e)}` }], isError: true };
  }
});

mcp.registerTool("get_messages", {
  description: "Return and clear all pending incoming messages from other agents. Call at the start of each turn.",
  inputSchema: {},
}, async () => {
  const msgs = inbox.splice(0);
  if (msgs.length === 0) return { content: [{ type: "text" as const, text: "(no messages)" }] };
  const lines = msgs.map((m) =>
    `[${m.at}] from=${m.from}${m.re ? ` re=${m.re}` : ""}\nid=${m.id}\n${JSON.stringify(m.body, null, 2)}`,
  );
  return { content: [{ type: "text" as const, text: lines.join("\n\n") }] };
});

// ── Main ──────────────────────────────────────────────────────────────────────

function isoNow(): string {
  return new Date().toISOString();
}

// Background lock+join state. The cwd lock enforces the per-folder singleton
// (at most one remote-pi agent — Pi OR Claude — per folder; a second peer with
// the same cwd-derived name would be a ghost).
//
// We retry only briefly — just enough to ride out a restart RACE (the previous
// MCP for this folder is still tearing down when Claude respawns us). After a
// short grace we FAIL LOUD (exit non-zero) rather than degrade forever: a
// silent connected-but-idle MCP hides the real problem (you launched claude in
// the wrong folder, or this folder already has a live agent — a duplicate
// session). Failing makes Claude show the MCP as errored so you actually see it.
const JOIN_RETRY_MS = 2_000;
const MAX_JOIN_ATTEMPTS = 4;  // ~6–8s grace for a restart race, then fail loud
let _lock: AcquiredLock | null = null;
let _lockRetryTimer: ReturnType<typeof setTimeout> | null = null;
let _lockAttempt = 0;
let _joined = false;
let _shuttingDown = false;

async function main(): Promise<void> {
  // Subscribe BEFORE connecting so we don't miss early envelopes. The
  // SessionPeer swallows broker ACKs / system events itself, so handlers
  // only see real peer messages (and replies, which carry `re`).
  mesh.onMessage((env) => {
    // plan/34 (passive presence): broker control/system envelopes
    // (`peer_joined` / `peer_left` / `list_peers_reply`) are presence signals,
    // NOT agent messages. Never push them to the inbox or the claude/channel —
    // otherwise a peer joining/leaving would wake this agent's turn. Discovery
    // is pull-based via `list_peers`. (Real broker ACKs and `re` replies are
    // already swallowed upstream by SessionPeer.)
    if (env.from === "broker" || env.from.endsWith(":broker")) return;

    const msg: IncomingMsg = {
      from: env.from,
      body: env.body,
      id: env.id,
      re: env.re,
      at: isoNow(),
    };
    inbox.push(msg);
    // Push via claude/channel so Claude wakes immediately (when the session
    // was launched with --dangerously-load-development-channels server:remote-pi-mesh).
    void mcp.server.notification({
      method: "notifications/claude/channel",
      params: { content: `📨 Message from ${msg.from}:\n${JSON.stringify(msg.body, null, 2)}` },
    }).catch(() => { /* channels not enabled — get_messages polling covers it */ });
  });

  // Connect the stdio transport FIRST and unconditionally, so Claude Code
  // always sees this server as connected and the tools stay reachable — even
  // before (or entirely without) a mesh join. The mesh join is layered on
  // best-effort below; a busy folder no longer kills the MCP.
  const transport = new StdioServerTransport();
  transport.onclose = shutdown;
  process.stdin.on("end", shutdown);
  process.stdin.on("close", shutdown);
  await mcp.connect(transport);

  // Only join the mesh if this folder is an actual remote-pi agent — i.e. it
  // has a local config (written by the `remote-pi claude` wizard) or an
  // explicit name override. `-s local` MCP registrations are inherited by
  // EVERY claude session in the git repo, so without this gate a plain claude
  // opened in any subfolder would auto-grab that folder's lock and join as a
  // stray agent — colliding with the real agent. No config ⇒ stay connected
  // but idle (tools report why); don't lock, don't join, don't retry.
  if (localConfigExists(_cwd) || _nameOverride !== undefined) {
    // Kick off the lock+join in the background. Never awaited — the MCP is
    // already serving; mesh availability arrives (and recovers) asynchronously.
    void tryJoinMesh();
  } else {
    degradedReason =
      `this folder is not a remote-pi agent (no config). Run "remote-pi claude" ` +
      `here to make it one. Mesh tools are idle.`;
  }
}

/** Acquire the per-cwd lock, then join the mesh. Retries briefly to absorb a
 *  restart race; if the lock or join still fails after MAX_JOIN_ATTEMPTS, FAIL
 *  LOUD (exit) so the failure is visible instead of silently degrading. */
async function tryJoinMesh(): Promise<void> {
  if (_joined || _shuttingDown) return;

  const res = await acquireCwdLock(_cwd);
  if (!res.ok) {
    _lockAttempt++;
    if (_lockAttempt >= MAX_JOIN_ATTEMPTS) {
      _failLoud(`folder already served by another remote-pi agent (lock: ${res.lockPath})`);
    }
    degradedReason = `folder busy (lock ${res.lockPath}); attempt ${_lockAttempt}/${MAX_JOIN_ATTEMPTS}`;
    _scheduleJoinRetry(JOIN_RETRY_MS);
    return;
  }
  _lock = res;

  try {
    await mesh.connect();
    meshReady = true;
    _joined = true;
    _lockAttempt = 0;
  } catch (e) {
    // Got the lock but the broker join failed (e.g. socket churn). Release the
    // lock so another contender isn't starved, then retry / fail loud.
    _lockAttempt++;
    try { _lock.release(); } catch { /* best-effort */ }
    _lock = null;
    if (_lockAttempt >= MAX_JOIN_ATTEMPTS) {
      _failLoud(`mesh join failed: ${String(e)}`);
    }
    degradedReason = `mesh join failed (attempt ${_lockAttempt}/${MAX_JOIN_ATTEMPTS}): ${String(e)}`;
    _scheduleJoinRetry(JOIN_RETRY_MS);
  }
}

function _scheduleJoinRetry(delayMs: number): void {
  if (_lockRetryTimer || _joined || _shuttingDown) return;
  const t = setTimeout(() => {
    _lockRetryTimer = null;
    void tryJoinMesh();
  }, delayMs);
  // Don't let the retry timer alone keep the process alive past stdin close.
  t.unref?.();
  _lockRetryTimer = t;
}

/** Exit non-zero with a loud, specific reason so Claude surfaces the MCP as
 *  errored (visible) instead of a silent connected-but-idle peer. */
function _failLoud(reason: string): never {
  logErr(
    `FATAL: ${reason}. Exiting so the failure is visible. cwd=${_cwd}. ` +
    `Most likely you launched claude in the WRONG FOLDER, or this folder ` +
    `already has a running remote-pi agent (a duplicate session). ` +
    `Launch one agent per folder via "remote-pi claude" from the project dir.`,
  );
  process.exit(1);
}

// Exit cleanly when Claude Code disconnects. The MeshNode keeps a UDS socket
// (and, when leader, a relay WS) open, so without this the process would linger
// after Claude exits — orphaning the mesh peer (it keeps showing "online" with
// nothing attached). We leave the mesh, then exit. Triggered by the MCP
// transport closing or stdin hitting EOF (whichever the host does first).
function shutdown(): void {
  if (_shuttingDown) return;
  _shuttingDown = true;
  if (_lockRetryTimer) { clearTimeout(_lockRetryTimer); _lockRetryTimer = null; }
  try { _lock?.release(); } catch { /* OS frees the UDS lock on exit anyway */ }
  void Promise.resolve(mesh.close())
    .catch(() => { /* best-effort */ })
    .finally(() => process.exit(0));
}

main().catch((err: unknown) => {
  process.stderr.write(`[remote-pi-mesh] fatal: ${String(err)}\n`);
  process.exit(1);
});
