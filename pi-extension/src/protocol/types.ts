export type PairErrorCode =
  | "token_expired"
  | "token_consumed"
  | "token_unknown"
  | "pair_invalid"
  | "pair_unsupported"
  | "internal_error";

export type ClientMessage =
  | { type: "pair_request"; id: string; token: string; device_name: string }
  | {
      type: "pair_request_v2";
      id: string;
      token: string;
      device_name: string;
      owner_pk: string;
      app_peer_pk: string;
      pi_pk: string;
      room_id: string;
      pair_nonce: string;
      expires_at: number;
      sig: string;
    }
  | { type: "user_message"; id: string; text: string }
  | { type: "approve_tool"; id: string; tool_call_id: string; decision: "allow" | "deny" }
  | { type: "cancel"; id: string; target_id: string }
  | { type: "ping"; id: string }
  | { type: "session_sync"; id: string; limit?: number }
  // Plan/28 Wave A — slash commands surface for the app picker.
  // `list_commands` asks the paired Pi for its full command catalog
  // (builtins + extension-registered + prompt templates + skills).
  // `command_invoke` asks the Pi to run a canonized command as if the
  // user had typed it in the TUI. Only commands with `invokable: true`
  // in the corresponding `commands_list` reply are guaranteed to work.
  | { type: "list_commands"; id: string }
  | { type: "command_invoke"; id: string; name: string; args?: string };

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
  | { type: "user_message"; id: string; text: string }
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
  // Plan/28 Wave A — slash commands replies.
  // `commands_list` is the response to a `list_commands` request, carrying
  // the full catalog the app should render in its picker.
  // `command_result` is the response to a `command_invoke`, signaling only
  // whether dispatch succeeded — visible side-effects (chat output, model
  // changes, compaction notice) still flow via the normal channels
  // (`agent_chunk`/`agent_done`/`model_select` etc.).
  | { type: "commands_list"; in_reply_to: string; commands: WireCommand[] }
  | { type: "command_result"; in_reply_to: string; ok: boolean; error?: string };

/**
 * Plan/28 — Source of a slash command in the Pi runtime.
 *
 * - `builtin`: hardcoded in `@mariozechner/pi-coding-agent`'s interactive mode
 *   (e.g. `/compact`, `/model`). The SDK does NOT export this list publicly,
 *   so pi-extension carries a manually-maintained mirror.
 * - `extension`: registered via `pi.registerCommand(...)` by an extension
 *   (e.g. our own `/remote-pi`, `/remote-pi setup`, etc.).
 * - `prompt`: a prompt template the user installed.
 * - `skill`: a skill the user installed.
 */
export type CommandSource = "builtin" | "extension" | "prompt" | "skill";

/**
 * Plan/28 — Wire schema for a slash command exposed to the app.
 *
 * The app uses this to render its picker. `invokable` tells it whether the
 * Pi can actually run the command remotely (some builtins are tied to the
 * TUI and have no programmatic equivalent in the SDK); the app should
 * render non-invokable commands as informational only (e.g. grayed out
 * with a "available in terminal only" hint).
 */
export interface WireCommand {
  /** Slash name WITHOUT the leading `/`. E.g. `"compact"`, `"remote-pi"`. */
  name: string;
  /** Short human-readable description shown in the picker. */
  description?: string;
  /** Where the command lives in the Pi runtime. */
  source: CommandSource;
  /**
   * Whether this Pi build can actually invoke the command via
   * `command_invoke`. When `false`, the app should disable invocation
   * and surface a "terminal only" hint instead.
   */
  invokable: boolean;
  /**
   * Whether the command accepts free-text arguments after its name
   * (e.g. `/model claude-opus-4-7` takes args, `/compact` does not).
   * The app uses this to decide whether to keep the text input editable
   * after the chip is placed.
   */
  takes_args: boolean;
}

export type ByeReason = "peer_stop" | "session_replaced" | "shutdown";
