import { describe, expect, test, vi } from "vitest";
import { registerAgentTools } from "./tools.js";
import type { SessionPeer } from "./peer.js";
import type { ToolDefinition } from "@mariozechner/pi-coding-agent";

// Captures tools registered via pi.registerTool so we can invoke them directly.
function makeMockPi() {
  const tools = new Map<string, ToolDefinition>();
  const pi = {
    registerTool(t: ToolDefinition) {
      tools.set(t.name, t);
    },
    // other methods unused in this file
  };
  return { pi: pi as unknown as Parameters<typeof registerAgentTools>[0], tools };
}

function makeMockPeer(
  overrides: Partial<{ send: unknown; request: unknown }> & { name?: string } = {},
) {
  const myName = overrides.name ?? "orq";
  const { name: _name, ...rest } = overrides;
  return {
    name: () => myName,
    send: vi.fn().mockResolvedValue(undefined),
    request: vi.fn().mockResolvedValue({
      from: "backend", to: "orq", id: "uuid-reply", re: "uuid-orig",
      body: { ok: true, text: "pong" },
    }),
    ...rest,
  } as unknown as SessionPeer;
}

const TOOL_CALL_ID = "tc_test";

describe("agent_send tool", () => {
  test("1) calls SessionPeer.send with args + returns {ok:true}", async () => {
    const { pi, tools } = makeMockPi();
    const peer = makeMockPeer();
    registerAgentTools(pi, () => peer);
    const tool = tools.get("agent_send")!;

    const result = await tool.execute(
      TOOL_CALL_ID,
      { to: "backend", body: { task: "ping" } },
      undefined, undefined, {} as never,
    );

    expect(peer.send).toHaveBeenCalledWith("backend", { task: "ping" }, null);
    expect(result.details).toEqual({ ok: true });
  });

  test("1b) forwards `re` for correlated replies (fix do timeout do request)", async () => {
    const { pi, tools } = makeMockPi();
    const peer = makeMockPeer();
    registerAgentTools(pi, () => peer);
    const tool = tools.get("agent_send")!;

    const result = await tool.execute(
      TOOL_CALL_ID,
      { to: "frontend", body: { answer: "pong" }, re: "01976000-0000-7000-8000-000000000000" },
      undefined, undefined, {} as never,
    );

    expect(peer.send).toHaveBeenCalledWith(
      "frontend",
      { answer: "pong" },
      "01976000-0000-7000-8000-000000000000",
    );
    expect(result.details).toEqual({ ok: true });
  });

  test("2) returns 'Not in a session' when no SessionPeer", async () => {
    const { pi, tools } = makeMockPi();
    registerAgentTools(pi, () => null);
    const tool = tools.get("agent_send")!;

    const result = await tool.execute(
      TOOL_CALL_ID,
      { to: "backend", body: "hi" },
      undefined, undefined, {} as never,
    );

    expect(result.details).toMatchObject({
      ok: false,
      error: expect.stringContaining("Not in a session"),
    });
    expect(
      (result.content[0] as { type: "text"; text: string }).text,
    ).toContain("Not in a session");
  });

  test("6a) SessionPeer.send throws → structured error returned", async () => {
    const { pi, tools } = makeMockPi();
    const peer = makeMockPeer({
      send: vi.fn().mockRejectedValue(new Error("relay: not connected")),
    });
    registerAgentTools(pi, () => peer);
    const tool = tools.get("agent_send")!;

    const result = await tool.execute(
      TOOL_CALL_ID,
      { to: "backend", body: { x: 1 } },
      undefined, undefined, {} as never,
    );

    expect(result.details).toMatchObject({
      ok: false,
      error: "relay: not connected",
    });
  });

  test("7) body as string passes through intact", async () => {
    const { pi, tools } = makeMockPi();
    const peer = makeMockPeer();
    registerAgentTools(pi, () => peer);
    const tool = tools.get("agent_send")!;

    await tool.execute(
      TOOL_CALL_ID,
      { to: "backend", body: "plain string body" },
      undefined, undefined, {} as never,
    );
    expect(peer.send).toHaveBeenCalledWith("backend", "plain string body", null);
  });

  test("8) deeply nested body object passes through intact", async () => {
    const { pi, tools } = makeMockPi();
    const peer = makeMockPeer();
    registerAgentTools(pi, () => peer);
    const tool = tools.get("agent_send")!;

    const nested = { a: { b: { c: [1, 2, { d: "x" }] } }, e: null };
    await tool.execute(
      TOOL_CALL_ID,
      { to: "fanout", body: nested },
      undefined, undefined, {} as never,
    );
    expect(peer.send).toHaveBeenCalledWith("fanout", nested, null);
  });
});

describe("agent_request tool", () => {
  test("3) calls SessionPeer.request → returns reply.body via details", async () => {
    const { pi, tools } = makeMockPi();
    const peer = makeMockPeer();
    registerAgentTools(pi, () => peer);
    const tool = tools.get("agent_request")!;

    const result = await tool.execute(
      TOOL_CALL_ID,
      { to: "backend", body: { q: "?" } },
      undefined, undefined, {} as never,
    );

    expect(peer.request).toHaveBeenCalledWith("backend", { q: "?" }, 30_000);
    expect(result.details).toEqual({ ok: true, text: "pong" });
  });

  test("4) custom timeout_ms is honored", async () => {
    const { pi, tools } = makeMockPi();
    const peer = makeMockPeer();
    registerAgentTools(pi, () => peer);
    const tool = tools.get("agent_request")!;

    await tool.execute(
      TOOL_CALL_ID,
      { to: "backend", body: { q: "?" }, timeout_ms: 5_000 },
      undefined, undefined, {} as never,
    );
    expect(peer.request).toHaveBeenCalledWith("backend", { q: "?" }, 5_000);
  });

  test("5) returns 'Not in a session' when no SessionPeer", async () => {
    const { pi, tools } = makeMockPi();
    registerAgentTools(pi, () => null);
    const tool = tools.get("agent_request")!;

    const result = await tool.execute(
      TOOL_CALL_ID,
      { to: "backend", body: "x" },
      undefined, undefined, {} as never,
    );
    expect(result.details).toMatchObject({
      error: expect.stringContaining("Not in a session"),
    });
  });

  test("6b) SessionPeer.request throws (timeout) → structured error", async () => {
    const { pi, tools } = makeMockPi();
    const peer = makeMockPeer({
      request: vi.fn().mockRejectedValue(new Error("request to backend timed out after 5000ms")),
    });
    registerAgentTools(pi, () => peer);
    const tool = tools.get("agent_request")!;

    const result = await tool.execute(
      TOOL_CALL_ID,
      { to: "backend", body: { q: "?" }, timeout_ms: 5_000 },
      undefined, undefined, {} as never,
    );
    expect(result.details).toMatchObject({
      error: expect.stringContaining("timed out"),
    });
  });
});

describe("self-loop guards (defesa em profundidade)", () => {
  test("agent_send to self → refused early, peer.send not called", async () => {
    const { pi, tools } = makeMockPi();
    const peer = makeMockPeer({ name: "orq" } as never);
    registerAgentTools(pi, () => peer);
    const tool = tools.get("agent_send")!;

    const result = await tool.execute(
      TOOL_CALL_ID,
      { to: "orq", body: { x: 1 } },
      undefined, undefined, {} as never,
    );

    expect(peer.send).not.toHaveBeenCalled();
    expect(result.details).toMatchObject({
      ok: false,
      error: expect.stringContaining("cannot agent_send to yourself"),
    });
  });

  test("agent_request to self → refused early, peer.request not called", async () => {
    const { pi, tools } = makeMockPi();
    const peer = makeMockPeer({ name: "orq" } as never);
    registerAgentTools(pi, () => peer);
    const tool = tools.get("agent_request")!;

    const result = await tool.execute(
      TOOL_CALL_ID,
      { to: "orq", body: { x: 1 } },
      undefined, undefined, {} as never,
    );

    expect(peer.request).not.toHaveBeenCalled();
    expect(result.details).toMatchObject({
      error: expect.stringContaining("cannot agent_request to yourself"),
    });
  });
});
