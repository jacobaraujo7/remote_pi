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
  test("calls ctx.compact() with an English-summary instruction and replies action_ok", () => {
    const compactArgs: unknown[] = [];
    const ctx: ActionCtx = { compact: (opts) => { compactArgs.push(opts); } };
    const sender = makeSender();
    handleSessionCompact(ctx, sender, { type: "session_compact", id: "r1" });
    expect(compactArgs).toHaveLength(1);
    // The summary must be forced to English (surfaced via the `compaction` msg).
    expect(JSON.stringify(compactArgs[0])).toMatch(/English/i);
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
    await handleModelSet(pi, null, reg, sender, {
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
    await handleModelSet(fakePi(), null, reg, sender, {
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
    await handleModelSet(pi, null, reg, sender, {
      type: "model_set", id: "r4", provider: "anthropic", model_id: "claude-opus-4-7",
    });
    expect(sender.sent[0]).toMatchObject({
      type: "action_error",
      error: expect.stringContaining("no auth configured"),
    });
  });

  test("persists the change via onPersist after a successful live set", async () => {
    const reg = fakeRegistry([sampleModel]);
    const pi = fakePi({ setModel: async () => true });
    const sender = makeSender();
    const persisted: Array<{ provider: string; modelId: string }> = [];
    await handleModelSet(
      pi, null, reg, sender,
      { type: "model_set", id: "r4", provider: "anthropic", model_id: "claude-opus-4-7" },
      (provider, modelId) => persisted.push({ provider, modelId }),
    );
    // onPersist receives the resolved model's provider/id so it survives restart.
    expect(persisted).toEqual([{ provider: "anthropic", modelId: "claude-opus-4-7" }]);
  });

  test("does NOT persist when the live set fails (no auth)", async () => {
    const reg = fakeRegistry([sampleModel]);
    const pi = fakePi({ setModel: async () => false });
    const sender = makeSender();
    let persistCalls = 0;
    await handleModelSet(
      pi, null, reg, sender,
      { type: "model_set", id: "r4", provider: "anthropic", model_id: "claude-opus-4-7" },
      () => { persistCalls += 1; },
    );
    expect(persistCalls).toBe(0);
    expect(sender.sent[0]).toMatchObject({ type: "action_error" });
  });

  test("does NOT persist when the model is unknown", async () => {
    const reg = fakeRegistry([sampleModel]);
    const sender = makeSender();
    let persistCalls = 0;
    await handleModelSet(
      fakePi(), null, reg, sender,
      { type: "model_set", id: "r4", provider: "anthropic", model_id: "nope-3" },
      () => { persistCalls += 1; },
    );
    expect(persistCalls).toBe(0);
  });
});

// ── list_models ────────────────────────────────────────────────────────────

describe("handleListModels", () => {
  test("returns wire-shaped catalog with current echo when ctx.getModel is set", async () => {
    const reg = fakeRegistry([sampleModel]);
    const ctx: ActionCtx = { getModel: () => sampleModel };
    const sender = makeSender();
    await handleListModels(ctx, reg, sender, { type: "list_models", id: "r5" });
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
        vision: false,
      },
    ]);
    expect(reply.current).toEqual(reply.models[0]);
  });

  test("omits `current` when ctx.getModel is undefined", async () => {
    const reg = fakeRegistry([sampleModel]);
    const sender = makeSender();
    await handleListModels(null, reg, sender, { type: "list_models", id: "r5" });
    const reply = sender.sent[0];
    expect(reply.type).toBe("models_list");
    if (reply.type !== "models_list") throw new Error("type guard");
    expect(reply.current).toBeUndefined();
  });

  test("prefers ctx.modelRegistry over the fallback registry", async () => {
    const fallback = fakeRegistry([sampleModel]);
    const liveModel: SdkModelLike = {
      id: "gpt-oss-20b",
      name: "GPT OSS 20B",
      provider: "lemonade",
      reasoning: false,
      contextWindow: 131_072,
    };
    const live = fakeRegistry([liveModel]);
    const ctx: ActionCtx = { modelRegistry: live };
    const sender = makeSender();
    await handleListModels(ctx, fallback, sender, { type: "list_models", id: "r5" });
    const reply = sender.sent[0];
    expect(reply.type).toBe("models_list");
    if (reply.type !== "models_list") throw new Error("type guard");
    expect(reply.models).toEqual([
      {
        id: "gpt-oss-20b",
        name: "GPT OSS 20B",
        provider: "lemonade",
        reasoning: false,
        context_window: 131_072,
        vision: false,
      },
    ]);
  });

  test("registry refresh failure surfaces as error envelope", async () => {
    const reg: ActionModelRegistry = {
      refresh: () => { throw new Error("models.json malformed"); },
      getAvailable: () => [],
      find: () => undefined,
    };
    const sender = makeSender();
    await handleListModels(null, reg, sender, { type: "list_models", id: "r5" });
    expect(sender.sent[0]).toMatchObject({
      type: "error",
      in_reply_to: "r5",
      code: "internal_error",
      message: expect.stringContaining("models.json malformed"),
    });
  });
});

describe("asynchronous registry refresh", () => {
  function delayedRegistry(): ActionModelRegistry {
    let ready = false;
    return {
      refresh: async () => {
        await Promise.resolve();
        ready = true;
        // Modern Pi returns a result object, not just Promise<void>.
        return { aborted: false, errors: new Map() };
      },
      getAvailable: () => ready ? [sampleModel] : [],
      find: () => ready ? sampleModel : undefined,
    };
  }

  test("list_models awaits asynchronous live refresh before reading the catalog", async () => {
    const sender = makeSender();
    const live = delayedRegistry();
    await handleListModels({ modelRegistry: live }, fakeRegistry([]), sender,
      { type: "list_models", id: "async-list" });
    expect(sender.sent).toHaveLength(1);
    expect(sender.sent[0]).toMatchObject({
      type: "models_list", in_reply_to: "async-list",
      models: [wireFromModel(sampleModel)],
    });
  });

  test("model_set awaits asynchronous live refresh before finding the model", async () => {
    const sender = makeSender();
    const models: SdkModelLike[] = [];
    const persisted: string[] = [];
    await handleModelSet(fakePi({ setModel: async model => { models.push(model); return true; } }),
      { modelRegistry: delayedRegistry() }, fakeRegistry([]), sender,
      { type: "model_set", id: "async-set", provider: sampleModel.provider, model_id: sampleModel.id },
      (_provider, id) => persisted.push(id));
    expect(models).toEqual([sampleModel]);
    expect(persisted).toEqual([sampleModel.id]);
    expect(sender.sent).toEqual([
      { type: "action_ok", in_reply_to: "async-set", action: "model_set" },
    ]);
  });

  function rejectingRegistry(): ActionModelRegistry {
    return {
      refresh: async () => { throw new Error("async refresh failed"); },
      getAvailable: () => { throw new Error("catalog must not be read"); },
      find: () => { throw new Error("catalog must not be searched"); },
    };
  }

  test("list_models catches refresh rejection in the existing error envelope", async () => {
    const sender = makeSender();
    await handleListModels(null, rejectingRegistry(), sender,
      { type: "list_models", id: "failed-list" });
    expect(sender.sent).toEqual([{
      type: "error", in_reply_to: "failed-list", code: "internal_error",
      message: "async refresh failed",
    }]);
  });

  test("model_set catches refresh rejection without setting or persisting", async () => {
    const sender = makeSender();
    let effects = 0;
    await handleModelSet(fakePi({ setModel: async () => { effects++; return true; } }),
      null, rejectingRegistry(), sender,
      { type: "model_set", id: "failed-set", provider: sampleModel.provider, model_id: sampleModel.id },
      () => { effects++; });
    expect(effects).toBe(0);
    expect(sender.sent).toEqual([{
      type: "action_error", in_reply_to: "failed-set", action: "model_set",
      error: "async refresh failed",
    }]);
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
      vision: false,  // sampleModel has no `input` → text-only
    });
  });

  // Plan/30: `vision` reflects whether the model's `input` includes "image".
  test("vision=true when model.input includes \"image\"", () => {
    const visionModel: SdkModelLike = { ...sampleModel, input: ["text", "image"] };
    expect(wireFromModel(visionModel).vision).toBe(true);
  });

  test("vision=false when model.input is text-only", () => {
    const textOnly: SdkModelLike = { ...sampleModel, input: ["text"] };
    expect(wireFromModel(textOnly).vision).toBe(false);
  });
});
