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
import { homedir } from "node:os";
import { join } from "node:path";
import { z } from "zod";
import { MeshNode } from "../session/mesh_node.js";
import { loadLocalConfig, defaultAgentName } from "../session/local_config.js";
import { resolveRelayUrl } from "../config.js";
import { acquireCwdLock } from "../session/cwd_lock.js";

// ── Args / config ─────────────────────────────────────────────────────────────

const _argv = process.argv.slice(2);
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
const BROKER_SOCK = join(homedir(), ".pi", "remote", "sessions", "local", "broker.sock");
const AUDIT_PATH = join(homedir(), ".pi", "remote", "sessions", "local", "audit.jsonl");

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

const mesh = new MeshNode({
  sockPath: BROKER_SOCK,
  name: AGENT_NAME,
  auditPath: AUDIT_PATH,
  // Own Pi-key cross-PC bridge — active only when this node leads (no Pi /
  // daemon already hosting the broker for this cwd). As a follower the
  // bridge stays dormant and cross-PC rides the existing leader.
  ...(_bridgeEnabled ? { bridge: { relayUrl, cwd: _cwd } } : {}),
  log: (_msg: string): void => { /* silent: stdio is the MCP channel */ },
});

let meshReady = false;

// ── MCP server setup ──────────────────────────────────────────────────────────

const mcp = new McpServer(
  { name: "remote-pi-mesh", version: "0.2.1" },
  {
    capabilities: { experimental: { "claude/channel": {} } },
    instructions: [
      `You are connected to the remote-pi agent mesh as "${AGENT_NAME}".`,
      "At the start of each turn call get_messages to check for incoming messages from other agents.",
      "Use list_peers to discover available agents.",
      "Use agent_send to send messages — use the exact peer name returned by list_peers.",
      'Use "broadcast" as the target to send to all peers at once.',
      "Follow the 'agent-network' skill for the full protocol (ACK statuses, replies via re, cross-PC <pc>:<peer> addressing).",
    ].join("\n"),
  },
);

function notReady() {
  return {
    content: [{ type: "text" as const, text: "Not connected to the mesh. Is remote-pi running in this folder?" }],
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
    to: z.string().describe('Peer name (from list_peers, may be "<pc>:<name>" cross-PC) or "broadcast"'),
    body: z.unknown().describe("Message body — any JSON value"),
    re: z.string().optional().describe("Optional: id of the message you are replying to"),
  },
}, async ({ to, body, re }) => {
  if (!meshReady) return notReady();
  if (to === mesh.name()) {
    return { content: [{ type: "text" as const, text: "Cannot send to yourself" }], isError: true };
  }
  try {
    if (to === "broadcast") {
      await mesh.send(to, body, re ?? null);
      return { content: [{ type: "text" as const, text: "Broadcast sent" }] };
    }
    const ack = await mesh.sendWithAck(to, body, re ?? null);
    const note =
      ack.status === "received" ? `Delivered to ${ack.target ?? to}` :
      ack.status === "busy" ? `${to} is busy (mid-turn) — message dropped, retry later` :
      ack.status === "denied" ? `${to} denied the message` :
      `No ACK from ${to} (timeout) — peer may be offline`;
    return {
      content: [{ type: "text" as const, text: note }],
      ...(ack.status === "received" ? {} : { isError: true }),
    };
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

async function main(): Promise<void> {
  // Per-cwd singleton — same kernel-enforced UDS lock the Pi extension's
  // `/remote-pi` takes (see cwd_lock.ts). At most one remote-pi agent (Pi OR
  // Claude) may own a folder. Without this, a second MCP in the same cwd joins
  // the global broker under the same cwd-derived name and the broker
  // disambiguates it to `Name#2` — an unresponsive ghost peer. We acquire the
  // lock BEFORE touching the mesh and hard-fail if refused: the process exits
  // before connecting the stdio transport, so Claude Code surfaces this MCP as
  // failed (the session keeps working, just without mesh tools).
  const lock = await acquireCwdLock(_cwd);
  if (!lock.ok) {
    process.stderr.write(
      `[remote-pi-mesh] folder already owned by another remote-pi agent ` +
      `(lock: ${lock.lockPath}). Refusing to start a duplicate mesh peer.\n`,
    );
    process.exit(1);
  }

  // Subscribe BEFORE connecting so we don't miss early envelopes. The
  // SessionPeer swallows broker ACKs / system events itself, so handlers
  // only see real peer messages (and replies, which carry `re`).
  mesh.onMessage((env) => {
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

  try {
    await mesh.connect();
    meshReady = true;
  } catch (e) {
    process.stderr.write(`[remote-pi-mesh] mesh offline: ${String(e)}\n`);
  }

  // Exit cleanly when Claude Code disconnects. The MeshNode keeps a UDS
  // socket (and, when leader, a relay WS) open, so without this the process
  // would linger forever after Claude exits — orphaning the mesh peer (it
  // keeps showing "online" with nothing actually attached). We leave the
  // mesh, then exit. Triggered by either the MCP transport closing or stdin
  // hitting EOF (whichever the host does first).
  let shuttingDown = false;
  const shutdown = (): void => {
    if (shuttingDown) return;
    shuttingDown = true;
    try { lock.release(); } catch { /* OS frees the UDS lock on exit anyway */ }
    void Promise.resolve(mesh.close())
      .catch(() => { /* best-effort */ })
      .finally(() => process.exit(0));
  };

  const transport = new StdioServerTransport();
  transport.onclose = shutdown;
  process.stdin.on("end", shutdown);
  process.stdin.on("close", shutdown);
  await mcp.connect(transport);
}

main().catch((err: unknown) => {
  process.stderr.write(`[remote-pi-mesh] fatal: ${String(err)}\n`);
  process.exit(1);
});
