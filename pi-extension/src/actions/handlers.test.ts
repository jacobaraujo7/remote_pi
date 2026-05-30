/**
 * Plan/28 Wave B — unit tests for action handlers.
 *
 * Each handler gets:
 *   - happy path → asserts `action_ok` (or `models_list`) shape
 *   - failure path → asserts `action_error` with structured `error` field
 *
 * No global state; everything passes through `ActionPi`/`ActionCtx`/
 * `ActionModelRegistry` interfaces — easy fakes, fast (synchronous where
 * possible).
 */

import { describe, expect, test } from "vitest";
import {
  handleSessionCompact,
  handleSessionNew,
  handleModelSet,
  handleThinkingSet,
  handleListModels,
  wireFromModel,
  type ActionCtx,
  type ActionPi,
  type ActionModelRegistry,
  type SdkModelLike,
} from "./handlers.js";
import type { ServerMessage } from "../protocol/types.js";

function makeSender() {
  const sent: ServerMessage[] = [];
  return {
    sent,
    send(msg: ServerMessage): void {
      sent.push(msg);
    },
  };
}

function fakePi(overrides: Partial<ActionPi> = {}): ActionPi {
  return {
    setModel: async () => true,
    setThinkingLevel: () => {},
    ...overrides,
  };
}

const sampleModel: SdkModelLike = {
  id: "claude-opus-4-7",
  name: "Claude Opus 4.7",
  provider: "anthropic",
  reasoning: true,
  contextWindow: 200_000,
};

function fakeRegistry(catalog: SdkModelLike[]): ActionModelRegistry {
  let refreshed = 0;
  return {
    refresh: () => { refreshed += 1; },
    getAvailable: () => catalog,
    find: (provider, modelId) =>
      catalog.find((m) => m.provider === provider && m.id === modelId),
    // expose refresh counter via a closure read for tests that care
    get _refreshes() { return refreshed; },
  } as ActionModelRegistry & { _refreshes: number };
}

// ── session_compact ────────────────────────────────────────────────────────

describe("handleSessionCompact", () => {
  test("calls ctx.compact() and replies action_ok", () => {
    let compacted = 0;
    const ctx: ActionCtx = { compact: () => { compacted += 1; } };
    const sender = makeSender();
    handleSessionCompact(ctx, sender, { type: "session_compact", id: "r1" });
    expect(compacted).toBe(1);
    expect(sender.sent).toEqual([
      { type: "action_ok", in_reply_to: "r1", action: "session_compact" },
    ]);
  });

  test("returns action_error when ctx is null", () => {
    const sender = makeSender();
    handleSessionCompact(null, sender, { type: "session_compact", id: "r1" });
    expect(sender.sent).toHaveLength(1);
    expect(sender.sent[0]).toMatchObject({
      type: "action_error",
      in_reply_to: "r1",
      action: "session_compact",
      error: expect.stringContaining("compact unavailable"),
    });
  });

  test("returns action_error when ctx.compact throws", () => {
    const ctx: ActionCtx = { compact: () => { throw new Error("boom"); } };
    const sender = makeSender();
    handleSessionCompact(ctx, sender, { type: "session_compact", id: "r1" });
    expect(sender.sent[0]).toMatchObject({
      type: "action_error",
      error: "boom",
    });
  });
});

// ── session_new ────────────────────────────────────────────────────────────

describe("handleSessionNew", () => {
  test("happy path → action_ok + returns true (drives Pi-side reset)", async () => {
    const ctx: ActionCtx = { newSession: async () => ({ cancelled: false }) };
    const sender = makeSender();
    const created = await handleSessionNew(ctx, sender, { type: "session_new", id: "r2" });
    expect(created).toBe(true);
    expect(sender.sent).toEqual([
      { type: "action_ok", in_reply_to: "r2", action: "session_new" },
    ]);
  });

  test("cancelled by extension hook → action_error + returns false (no reset)", async () => {
    const ctx: ActionCtx = { newSession: async () => ({ cancelled: true }) };
    const sender = makeSender();
    const created = await handleSessionNew(ctx, sender, { type: "session_new", id: "r2" });
    expect(created).toBe(false);
    expect(sender.sent[0]).toMatchObject({
      type: "action_error",
      action: "session_new",
      error: expect.stringContaining("cancelled"),
    });
  });

  test("ctx without newSession → action_error + returns false (no reset)", async () => {
    const sender = makeSender();
    const created = await handleSessionNew({}, sender, { type: "session_new", id: "r2" });
    expect(created).toBe(false);
    expect(sender.sent[0]).toMatchObject({
      type: "action_error",
      error: expect.stringContaining("newSession unavailable"),
    });
  });

  test("re-captures the fresh withSession ctx via onReplaced (avoids stale ctx)", async () => {
    // Simulate the SDK invoking withSession with a fresh, command-capable ctx
    // bound to the replacement session — exactly what makes the captured ctx
    // stale. handleSessionNew must forward that fresh ctx to onReplaced.
    const freshCtx: ActionCtx = {
      compact: () => undefined,
      newSession: async () => ({ cancelled: false }),
    };
    const ctx: ActionCtx = {
      newSession: async (opts) => {
        await opts?.withSession?.(freshCtx);
        return { cancelled: false };
      },
    };
    const sender = makeSender();
    let recaptured: ActionCtx | null = null;
    const created = await handleSessionNew(
      ctx,
      sender,
      { type: "session_new", id: "r2" },
      (c) => { recaptured = c; },
    );
    expect(created).toBe(true);
    expect(recaptured).toBe(freshCtx);
  });
});

// ── thinking_set ───────────────────────────────────────────────────────────

describe("handleThinkingSet", () => {
  test("forwards level to pi.setThinkingLevel and replies action_ok", () => {
    const calls: string[] = [];
    const pi = fakePi({ setThinkingLevel: (lvl) => { calls.push(lvl); } });
    const sender = makeSender();
    handleThinkingSet(pi, sender, { type: "thinking_set", id: "r3", level: "high" });
    expect(calls).toEqual(["high"]);
    expect(sender.sent).toEqual([
      { type: "action_ok", in_reply_to: "r3", action: "thinking_set" },
    ]);
  });

  test("setThinkingLevel throwing surfaces as action_error", () => {
    const pi = fakePi({ setThinkingLevel: () => { throw new Error("nope"); } });
    const sender = makeSender();
    handleThinkingSet(pi, sender, { type: "thinking_set", id: "r3", level: "low" });
    expect(sender.sent[0]).toMatchObject({
      type: "action_error",
      action: "thinking_set",
      error: "nope",
    });
  });
});

// ── model_set ──────────────────────────────────────────────────────────────

describe("handleModelSet", () => {
  test("happy path → refreshes, looks up, sets, action_ok", async () => {
    const reg = fakeRegistry([sampleModel]);
    const setModelArgs: SdkModelLike[] = [];
    const pi = fakePi({
      setModel: async (m) => { setModelArgs.push(m as SdkModelLike); return true; },
    });
    const sender = makeSender();
    await handleModelSet(pi, reg, sender, {
      type: "model_set", id: "r4", provider: "anthropic", model_id: "claude-opus-4-7",
    });
    expect(setModelArgs).toHaveLength(1);
    expect(setModelArgs[0].id).toBe("claude-opus-4-7");
    expect(sender.sent[0]).toMatchObject({
      type: "action_ok", action: "model_set",
    });
  });

  test("unknown model → action_error", async () => {
    const reg = fakeRegistry([sampleModel]);
    const sender = makeSender();
    await handleModelSet(fakePi(), reg, sender, {
      type: "model_set", id: "r4", provider: "anthropic", model_id: "nope-3",
    });
    expect(sender.sent[0]).toMatchObject({
      type: "action_error",
      error: expect.stringContaining("not in registry"),
    });
  });

  test("setModel returning false (no auth) → action_error", async () => {
    const reg = fakeRegistry([sampleModel]);
    const pi = fakePi({ setModel: async () => false });
    const sender = makeSender();
    await handleModelSet(pi, reg, sender, {
      type: "model_set", id: "r4", provider: "anthropic", model_id: "claude-opus-4-7",
    });
    expect(sender.sent[0]).toMatchObject({
      type: "action_error",
      error: expect.stringContaining("no auth configured"),
    });
  });
});

// ── list_models ────────────────────────────────────────────────────────────

describe("handleListModels", () => {
  test("returns wire-shaped catalog with current echo when ctx.getModel is set", () => {
    const reg = fakeRegistry([sampleModel]);
    const ctx: ActionCtx = { getModel: () => sampleModel };
    const sender = makeSender();
    handleListModels(ctx, reg, sender, { type: "list_models", id: "r5" });
    const reply = sender.sent[0];
    expect(reply.type).toBe("models_list");
    if (reply.type !== "models_list") throw new Error("type guard");
    expect(reply.in_reply_to).toBe("r5");
    expect(reply.models).toEqual([
      {
        id: "claude-opus-4-7",
        name: "Claude Opus 4.7",
        provider: "anthropic",
        reasoning: true,
        context_window: 200_000,
      },
    ]);
    expect(reply.current).toEqual(reply.models[0]);
  });

  test("omits `current` when ctx.getModel is undefined", () => {
    const reg = fakeRegistry([sampleModel]);
    const sender = makeSender();
    handleListModels(null, reg, sender, { type: "list_models", id: "r5" });
    const reply = sender.sent[0];
    expect(reply.type).toBe("models_list");
    if (reply.type !== "models_list") throw new Error("type guard");
    expect(reply.current).toBeUndefined();
  });

  test("registry refresh failure surfaces as error envelope", () => {
    const reg: ActionModelRegistry = {
      refresh: () => { throw new Error("models.json malformed"); },
      getAvailable: () => [],
      find: () => undefined,
    };
    const sender = makeSender();
    handleListModels(null, reg, sender, { type: "list_models", id: "r5" });
    expect(sender.sent[0]).toMatchObject({
      type: "error",
      in_reply_to: "r5",
      code: "internal_error",
      message: expect.stringContaining("models.json malformed"),
    });
  });
});

// ── wireFromModel ──────────────────────────────────────────────────────────

describe("wireFromModel", () => {
  test("maps SDK Model fields to wire schema 1:1 (camelCase → snake_case)", () => {
    expect(wireFromModel(sampleModel)).toEqual({
      id: "claude-opus-4-7",
      name: "Claude Opus 4.7",
      provider: "anthropic",
      reasoning: true,
      context_window: 200_000,
    });
  });
});
