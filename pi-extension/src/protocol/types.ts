export type PairErrorCode =
  | "token_expired"
  | "token_consumed"
  | "token_unknown"
  | "internal_error";

export type ClientMessage =
  | { type: "pair_request"; id: string; token: string; device_name: string }
  // Plan/30: optional `images` carry inline base64 attachments (one today).
  // Omitted entirely on text-only messages — the no-image path is unchanged.
  | { type: "user_message"; id: string; text: string; images?: WireImage[] }
  | { type: "approve_tool"; id: string; tool_call_id: string; decision: "allow" | "deny" }
  | { type: "cancel"; id: string; target_id: string }
  | { type: "ping"; id: string }
  | { type: "session_sync"; id: string; limit?: number }
  // Plan/28 — Typed app actions on the paired Pi session. Each carries a
  // structured payload (no string parsing) and gets either `action_ok` or
  // `action_error` back. Visible side-effects (chat output, model change
  // broadcasts, compaction notice) still flow through the normal channels.
  | { type: "session_new"; id: string }
  | { type: "session_compact"; id: string }
  | { type: "model_set"; id: string; provider: string; model_id: string }
  | { type: "thinking_set"; id: string; level: ThinkingLevel }
  | { type: "list_models"; id: string };

/**
 * Plan/30 — one inline image attachment on a `user_message`. Mirrors the
 * SDK's `ImageContent` ({@link https }) split across the wire: `data` is the
 * base64-encoded (compressed) image bytes, `mime` its content type
 * (e.g. `"image/jpeg"`). The Pi maps `{ data, mime }` → the SDK's
 * `{ type:"image", data, mimeType }` before handing it to the model.
 */
export interface WireImage {
  /** Base64-encoded image bytes (compressed app-side). */
  data: string;
  /** MIME type, e.g. `"image/jpeg"`. Maps to the SDK's `mimeType`. */
  mime: string;
}

export type Usage = { input_tokens: number; output_tokens: number };

export type KnownErrorCode =
  | "tool_approval_required"
  | "invalid_message"
  | "unsupported_type"
  | "too_large"
  | "rate_limited"
  | "timeout"
  | "internal_error";

// aberto para forward-compat — receivers toleram codes desconhecidos
export type ErrorCode = KnownErrorCode | (string & {});

export type SessionHistoryEvent =
  | { ts: number; type: "user_input"; id: string; text: string }
  | {
      ts: number;
      type: "tool_request";
      tool_call_id: string;
      tool: string;
      args: Record<string, unknown>;
    }
  | {
      ts: number;
      type: "tool_result";
      tool_call_id: string;
      result?: unknown;
      error?: string;
    }
  | {
      ts: number;
      type: "agent_message";
      in_reply_to: string;
      text: string;
      usage?: Usage;
    };

export type ServerMessage =
  | {
      type: "pair_ok";
      in_reply_to: string;
      session_name: string;
      session_started_at: number;
      room_id: string;
      /**
       * Plan/27 Wave A: identifies the host coding agent driving this
       * pi-extension instance. `name` is hardcoded to "Pi coding agent"
       * today; future Pi forks (Claude Code, OpenCode) populate their own
       * here. `version` is the pi-extension `package.json` version.
       * Optional in the wire schema so app-side parsing tolerates older
       * Pi builds that predate this field — every new pairing emits both.
       */
      harness?: { name: string; version: string };
      /**
       * Plan/27 Wave A: `os.hostname()` of the machine the Pi runs on.
       * App displays it in the device list so the user can distinguish
       * two paired PCs that happen to share a nickname or sit in the
       * same project folder.
       */
      hostname?: string;
    }
  | { type: "pair_error"; in_reply_to: string; code: PairErrorCode; message: string }
  | { type: "user_input"; id: string; text: string }
  // Echo of an app-originated user_message, broadcast by the Pi to every
  // connected owner (including the sender). Source-of-truth model: each
  // app waits for this echo to render the message it sent, so all owners
  // see the same session timeline regardless of who typed.
  // Field shape mirrors the inbound ClientMessage `user_message` exactly,
  // and `id` is the sender-provided id — Pi never re-generates it (lets
  // future dedup logic use id as a stable key). See plan/24 W2D fix.
  // Plan/30: `images` echoed back so every owner renders the same image bubble.
  | { type: "user_message"; id: string; text: string; images?: WireImage[] }
  | { type: "agent_chunk"; in_reply_to: string; delta: string }
  | { type: "agent_done"; in_reply_to: string; usage?: Usage }
  | { type: "agent_message"; in_reply_to: string; text: string; usage?: Usage }
  | { type: "tool_request"; tool_call_id: string; tool: string; args: Record<string, unknown> }
  | { type: "tool_result"; tool_call_id: string; result?: unknown; error?: string }
  | { type: "error"; in_reply_to?: string; code: ErrorCode; message: string }
  | { type: "cancelled"; in_reply_to: string; target_id: string }
  | { type: "pong"; in_reply_to: string }
  | { type: "bye"; reason: ByeReason }
  | {
      type: "session_history";
      in_reply_to: string;
      session_started_at: number;
      events: SessionHistoryEvent[];
      eos: boolean;
      truncated: boolean;
    }
  // Plan/28 — Replies for typed app actions.
  // `action_ok` / `action_error` carry the original `ActionName` so the
  // app can demultiplex by action type rather than having to remember
  // every in-flight request id.
  // `models_list` is the response to a `list_models` request; the optional
  // `current` echoes the model the Pi is using right now so the app can
  // highlight the selected row without a second round-trip.
  | { type: "action_ok"; in_reply_to: string; action: ActionName }
  | { type: "action_error"; in_reply_to: string; action: ActionName; error: string }
  | { type: "models_list"; in_reply_to: string; models: WireModel[]; current?: WireModel };

/**
 * Plan/28 — Stable names for the typed actions the app can request. Kept
 * as a closed string union so a switch in either side gets exhaustiveness
 * checking from the compiler.
 */
export type ActionName =
  | "session_new"
  | "session_compact"
  | "model_set"
  | "thinking_set";

/**
 * Plan/28 — Mirror of the SDK's `ThinkingLevel` (defined in
 * `@mariozechner/pi-agent-core/types`). Re-declared locally so the wire
 * protocol owns its own enum and we don't leak SDK-internal types onto
 * the app's network surface.
 *
 * Note: `"xhigh"` is only honored by select model families — the SDK uses
 * each `Model.thinkingLevelMap` to decide if the requested level is
 * supported, falling back to a sensible neighbour when not. The app
 * surfaces all 6 buttons but can grey out unsupported ones using the
 * model's metadata if the picker fetches it later.
 */
export type ThinkingLevel =
  | "off" | "minimal" | "low" | "medium" | "high" | "xhigh";

/**
 * Plan/28 — Wire shape for one model entry in the app's model picker.
 *
 * Subset of the SDK's `Model<Api>` interface — only the fields the app
 * actually renders. Cost / max-tokens / API class are left off the wire
 * deliberately; if the app's picker grows to need them, they get added
 * here and to the handler's mapping in `index.ts` in one diff.
 */
export interface WireModel {
  /** Stable identifier inside the provider's catalog. E.g. `"claude-opus-4-7"`. */
  id: string;
  /** Display name for the picker row. E.g. `"Claude Opus 4.7"`. */
  name: string;
  /** Provider slug. E.g. `"anthropic"`, `"openai"`. */
  provider: string;
  /** Whether the model supports the thinking surface (`reasoning: true`
   *  in the SDK). Useful so the app can decide whether the thinking
   *  segmented control should be enabled when this model is selected. */
  reasoning: boolean;
  /** Context window in tokens, for display in the picker subtitle. */
  context_window: number;
  /** Plan/30: true when the model accepts image input (SDK `Model.input`
   *  includes `"image"`). The app uses it to enable/disable the attach
   *  button — a text-only model greys out image attachments. */
  vision: boolean;
}

export type ByeReason = "peer_stop" | "session_replaced" | "shutdown";
