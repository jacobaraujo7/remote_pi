import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { Type } from "typebox";
import type { SessionPeer } from "./peer.js";

const NOT_IN_SESSION = "Not in a session. Run /remote-pi join first";
const DEFAULT_TIMEOUT_MS = 30_000;

interface SendInput {
  to: string;
  body: unknown;
  re?: string;
}

interface RequestInput {
  to: string;
  body: unknown;
  timeout_ms?: number;
}

/**
 * Registers two native tools the Pi LLM can invoke to talk to other agents
 * in the same UDS session (plano 19 transport):
 *   - `agent_send`     — fire-and-forget delivery
 *   - `agent_request`  — request/reply with `re` correlation + timeout
 *
 * Both tools are registered unconditionally. When this Pi is not currently
 * joined to a session, the tool returns a structured error string instead
 * of throwing, so the LLM can react and tell the user.
 *
 * `getSessionPeer` is a getter (not a captured value) so changes to the
 * underlying `_sessionPeer` module variable are observed live.
 */
export function registerAgentTools(
  pi: ExtensionAPI,
  getSessionPeer: () => SessionPeer | null,
): void {
  const SendParams = Type.Object({
    to: Type.String({ description: "Recipient agent name (e.g. 'backend'), 'broadcast', or array of names." }),
    body: Type.Unknown({ description: "Free-form JSON payload. String or object — your choice." }),
    re: Type.Optional(Type.String({
      description:
        "When you are REPLYING to a message from another agent, set this to that " +
        "message's `id`. Required for `agent_request` correlation on the other side — " +
        "without it, the sender's pending request times out. Skip for unsolicited sends.",
    })),
  });

  const RequestParams = Type.Object({
    to: Type.String({ description: "Recipient agent name. Must be a single peer (not broadcast)." }),
    body: Type.Unknown({ description: "Free-form JSON payload to send." }),
    timeout_ms: Type.Optional(Type.Number({
      description: "Optional override of the default 30s reply timeout. Per-request.",
    })),
  });

  pi.registerTool<typeof SendParams, { ok: boolean; error?: string }>({
    name: "agent_send",
    label: "Agent Send",
    description:
      "Send a message to another Pi agent in the current local session. " +
      "Two uses: (1) fire-and-forget announcements, status updates, or anything " +
      "that doesn't need a reply — call without `re`. (2) REPLYING to a question " +
      "another agent sent you via `agent_request` — call with `re` set to the " +
      "incoming message's `id`. Without `re`, the requester times out.",
    promptSnippet:
      "agent_send({to, body, re?}): send/reply to peers. Set `re` to incoming message id when answering an agent_request.",
    parameters: SendParams,
    execute: async (_toolCallId, params) => {
      const peer = getSessionPeer();
      if (!peer) {
        return {
          content: [{ type: "text", text: NOT_IN_SESSION }],
          details: { ok: false, error: NOT_IN_SESSION },
        };
      }
      const { to, body, re } = params as SendInput;
      if (to === peer.name()) {
        const msg = `Refused: cannot agent_send to yourself ("${to}"). Just do the work directly.`;
        return {
          content: [{ type: "text", text: msg }],
          details: { ok: false, error: msg },
        };
      }
      try {
        await peer.send(to, body, re ?? null);
        return {
          content: [{ type: "text", text: `Sent to ${to}${re ? ` (re=${re})` : ""}.` }],
          details: { ok: true },
        };
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        return {
          content: [{ type: "text", text: `Failed to send: ${msg}` }],
          details: { ok: false, error: msg },
        };
      }
    },
  });

  pi.registerTool<typeof RequestParams, unknown>({
    name: "agent_request",
    label: "Agent Request",
    description:
      "Send a message to another Pi agent and wait for the reply. Resolves to the responder's " +
      "body field. Use when you need an answer from a peer before continuing your turn. " +
      "Default timeout 30s; override with `timeout_ms`.",
    promptSnippet:
      "agent_request({to, body, timeout_ms?}): synchronous request/reply with a peer (returns peer's body or {error}).",
    parameters: RequestParams,
    execute: async (_toolCallId, params) => {
      const peer = getSessionPeer();
      if (!peer) {
        return {
          content: [{ type: "text", text: NOT_IN_SESSION }],
          details: { error: NOT_IN_SESSION },
        };
      }
      const { to, body, timeout_ms } = params as RequestInput;
      if (to === peer.name()) {
        const msg = `Refused: cannot agent_request to yourself ("${to}"). Just do the work directly.`;
        return {
          content: [{ type: "text", text: msg }],
          details: { error: msg },
        };
      }
      const timeout = typeof timeout_ms === "number" && timeout_ms > 0
        ? timeout_ms
        : DEFAULT_TIMEOUT_MS;
      try {
        const reply = await peer.request(to, body, timeout);
        const text = typeof reply.body === "string"
          ? reply.body
          : JSON.stringify(reply.body);
        return {
          content: [{ type: "text", text }],
          details: reply.body,
        };
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        return {
          content: [{ type: "text", text: `Request failed: ${msg}` }],
          details: { error: msg },
        };
      }
    },
  });
}
