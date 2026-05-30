/**
 * Plan/28 Wave B — typed action handlers.
 *
 * Each handler maps one `ClientMessage` action to a public Pi SDK call,
 * and replies with `action_ok` or `action_error`. Handlers take their
 * dependencies as parameters so the index.ts wiring is one-liner and
 * unit tests can pass fakes without touching global state.
 *
 * `models_list` lives next door because it shares the `ModelRegistry`
 * helper and the same wire vocabulary.
 *
 * SDK API surface used (see plan/28 Wave 0 for the full table):
 *
 *   - `ctx.compact()`            — non-blocking, fires `session_compact`
 *                                  event when done
 *   - `ctx.newSession()`         — only on `ExtensionCommandContext`;
 *                                  resolves with `{cancelled}` flag
 *   - `pi.setModel(model)`       — returns `false` if no auth configured
 *   - `pi.setThinkingLevel(lvl)` — synchronous
 *   - `ctx.getModel()`           — optional, undefined before first turn
 *   - `ModelRegistry.{refresh,getAvailable,find}` — see `registry.ts`
 */

import type {
  ClientMessage,
  ServerMessage,
  WireModel,
  ActionName,
} from "../protocol/types.js";

/**
 * Structural subset of the SDK's `Model<Api>` interface (defined in
 * `@mariozechner/pi-ai`, which is a transitive dep — not re-exported by
 * `@mariozechner/pi-coding-agent`'s main entry). Capturing just the
 * fields we touch keeps the handler decoupled from the SDK's full Model
 * surface and avoids a direct dep on `pi-ai`.
 */
export interface SdkModelLike {
  id: string;
  name: string;
  provider: string;
  reasoning: boolean;
  contextWindow: number;
}
// `Model` is the alias used throughout the file. Real SDK models structurally
// satisfy this — `pi.setModel(model)` accepts them because TypeScript
// validates structurally at the call site (the SDK's full Model has more
// fields than we declare here, which is fine for an input parameter).
type Model<_TApi = unknown> = SdkModelLike;

/**
 * Minimal channel surface needed to reply. Mirrors `PlainPeerChannel`'s
 * `.send` signature; tests pass an array-backed fake.
 */
export interface ActionReplySender {
  send(msg: ServerMessage): void;
}

/**
 * Narrow shape of the `ExtensionAPI` surface action handlers actually
 * call. Lets the test layer stub just these without rebuilding the full
 * SDK type (which has 30+ methods we don't use here).
 */
export interface ActionPi {
  setModel(model: Model<any>): Promise<boolean>;
  setThinkingLevel(level: import("../protocol/types.js").ThinkingLevel): void;
}

/**
 * Narrow shape of the per-call context. Drawn from the union of
 * `ExtensionContextActions` (compact, getModel) and
 * `ExtensionCommandContextActions` (newSession), since index.ts caches
 * the most-recent ctx and that's typically the command one.
 *
 * All fields are optional so a missing method (e.g. when only a plain
 * `ExtensionContext` was seen) becomes a typed `action_error` instead of
 * a runtime TypeError.
 */
export interface ActionCtx {
  compact?: (options?: object) => void;
  /**
   * Starts a new session. `withSession` is the SDK's blessed hook for
   * post-replacement work: it receives a FRESH, command-capable ctx bound to
   * the new session. The SDK marks any ctx captured BEFORE this call stale, so
   * callers must re-capture via `withSession` rather than reuse the old ctx.
   */
  newSession?: (options?: {
    withSession?: (ctx: ActionCtx) => Promise<void>;
  }) => Promise<{ cancelled: boolean }>;
  getModel?: () => Model<any> | undefined;
}

/**
 * Minimal shape of the registry surface. Maps 1:1 onto `ModelRegistry`
 * but lets tests fake catalogs without instantiating the real one.
 */
export interface ActionModelRegistry {
  refresh(): void;
  getAvailable(): Model<any>[];
  find(provider: string, modelId: string): Model<any> | undefined;
}

/** Project a SDK `Model<Api>` onto the wire schema. Shared by list_models
 *  and the `current` echo, so both stay in lockstep. */
export function wireFromModel(model: Model<any>): WireModel {
  return {
    id: model.id,
    name: model.name,
    provider: model.provider,
    reasoning: model.reasoning,
    context_window: model.contextWindow,
  };
}

// ── ack helpers ────────────────────────────────────────────────────────────

function ok(sender: ActionReplySender, msg: { id: string }, action: ActionName): void {
  sender.send({ type: "action_ok", in_reply_to: msg.id, action });
}

function fail(
  sender: ActionReplySender,
  msg: { id: string },
  action: ActionName,
  err: unknown,
): void {
  const error = err instanceof Error ? err.message : String(err);
  sender.send({ type: "action_error", in_reply_to: msg.id, action, error });
}

/** Run a synchronous action with uniform success/failure replies. */
function runSync(
  sender: ActionReplySender,
  msg: { id: string },
  action: ActionName,
  body: () => void,
): void {
  try {
    body();
    ok(sender, msg, action);
  } catch (e) {
    fail(sender, msg, action, e);
  }
}

/** Run an async action with uniform success/failure replies. */
async function runAsync(
  sender: ActionReplySender,
  msg: { id: string },
  action: ActionName,
  body: () => Promise<void>,
): Promise<boolean> {
  try {
    await body();
    ok(sender, msg, action);
    return true;
  } catch (e) {
    fail(sender, msg, action, e);
    return false;
  }
}

// ── individual handlers ───────────────────────────────────────────────────

type SessionCompactMsg = Extract<ClientMessage, { type: "session_compact" }>;
type SessionNewMsg = Extract<ClientMessage, { type: "session_new" }>;
type ModelSetMsg = Extract<ClientMessage, { type: "model_set" }>;
type ThinkingSetMsg = Extract<ClientMessage, { type: "thinking_set" }>;
type ListModelsMsg = Extract<ClientMessage, { type: "list_models" }>;

export function handleSessionCompact(
  ctx: ActionCtx | null,
  sender: ActionReplySender,
  msg: SessionCompactMsg,
): void {
  runSync(sender, msg, "session_compact", () => {
    if (!ctx?.compact) throw new Error("compact unavailable (no active session ctx)");
    ctx.compact();
  });
}

export async function handleSessionNew(
  ctx: ActionCtx | null,
  sender: ActionReplySender,
  msg: SessionNewMsg,
  onReplaced?: (freshCtx: ActionCtx) => void,
): Promise<boolean> {
  // Returns true only when a fresh session was actually created. index.ts
  // keys the Pi-side reset (clear _messageBuffer, restamp _sessionStartedAt,
  // fan out an empty session_history) off this signal — a `cancelled`/errored
  // new-session must NOT reset, so we return runAsync's success boolean.
  return runAsync(sender, msg, "session_new", async () => {
    if (!ctx?.newSession) throw new Error("newSession unavailable (no command ctx yet)");
    // newSession marks the caller's captured ctx (index.ts's `_lastCtx`) STALE
    // — reusing it later throws "stale after session replacement" (the
    // compact-after-New-session crash). `withSession` hands back a fresh,
    // command-capable ctx bound to the new session; forward it via onReplaced
    // so the caller re-captures and keeps later actions off the stale ctx.
    const result = await ctx.newSession({
      withSession: async (freshCtx) => { onReplaced?.(freshCtx); },
    });
    // `cancelled: true` happens when the SDK's hook chain vetoes the new
    // session (e.g. an extension's `session_before_switch` returned a
    // refusal). Surface as a typed error rather than silent success.
    if (result.cancelled) throw new Error("cancelled by extension hook");
  });
}

export function handleThinkingSet(
  pi: ActionPi,
  sender: ActionReplySender,
  msg: ThinkingSetMsg,
): void {
  runSync(sender, msg, "thinking_set", () => {
    pi.setThinkingLevel(msg.level);
  });
}

export async function handleModelSet(
  pi: ActionPi,
  reg: ActionModelRegistry,
  sender: ActionReplySender,
  msg: ModelSetMsg,
): Promise<void> {
  await runAsync(sender, msg, "model_set", async () => {
    // Refresh first so a model just-added via `/login` is visible.
    reg.refresh();
    const model = reg.find(msg.provider, msg.model_id);
    if (!model) {
      throw new Error(`model "${msg.provider}/${msg.model_id}" not in registry`);
    }
    const success = await pi.setModel(model);
    if (!success) throw new Error("no auth configured for this model");
  });
}

export function handleListModels(
  ctx: ActionCtx | null,
  reg: ActionModelRegistry,
  sender: ActionReplySender,
  msg: ListModelsMsg,
): void {
  // refresh() can throw if `models.json` is malformed — wrap in try so the
  // app gets an explicit error reply instead of a silent drop.
  try {
    reg.refresh();
    const models = reg.getAvailable().map(wireFromModel);
    const current = ctx?.getModel?.();
    sender.send({
      type: "models_list",
      in_reply_to: msg.id,
      models,
      current: current ? wireFromModel(current) : undefined,
    });
  } catch (e) {
    sender.send({
      type: "error",
      in_reply_to: msg.id,
      code: "internal_error",
      message: e instanceof Error ? e.message : String(e),
    });
  }
}
