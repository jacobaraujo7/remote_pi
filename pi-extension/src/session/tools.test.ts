import { describe, expect, test, vi } from "vitest";
import { registerAgentTools } from "./tools.js";
import type { SessionPeer, AckResult } from "./peer.js";
import type { ToolDefinition } from "@earendil-works/pi-coding-agent";

// Captures tools registered via pi.registerTool so we can invoke them directly.
function makeMockPi() {
  const tools = new Map<string, ToolDefinition>();
  const pi = {
    registerTool(t: ToolDefinition) {
      tools.set(t.name, t);
    },
  };
  return { pi: pi as unknown as Parameters<typeof registerAgentTools>[0], tools };
}

function makeMockPeer(
  overrides: Partial<{
    name?: string;
    send: unknown;
    sendWithAck: unknown;
    request: unknown;
  }> = {},
) {
  const myName = overrides.name ?? "orq";
  const { name: _name, ...rest } = overrides;
  return {
    name: () => myName,
    send: vi.fn().mockResolvedValue(undefined),
    sendWithAck: vi.fn().mockResolvedValue(
      { status: "received", id: "uuid-out", target: "backend" } satisfies AckResult,
    ),
    request: vi.fn().mockResolvedValue({
      from: "backend", to: "orq", id: "uuid-reply", re: "uuid-orig",
      body: { ok: true, text: "pong" },
    }),
    ...rest,
  } as unknown as SessionPeer;
}

const TOOL_CALL_ID = "tc_test";

describe("agent_send tool (ACK protocol)", () => {
  test("unicast idle peer → calls sendWithAck, returns status=received", async () => {
    const { pi, tools } = makeMockPi();
    const peer = makeMockPeer();
    registerAgentTools(pi, () => peer);
    const tool = tools.get("agent_send")!;

    const result = await tool.execute(
      TOOL_CALL_ID,
      { to: "backend", body: { task: "ping" } },
      undefined, undefined, {} as never,
    );

    expect(peer.sendWithAck).toHaveBeenCalledWith("backend", { task: "ping" }, null, 5_000);
    expect(result.details).toMatchObject({ status: "received", ok: true, target: "backend" });
  });

  test("plan/34: defensive busy ACK is framed as delivered (no retry-on-busy)", async () => {
    // The broker no longer emits `busy` for new work, but if a stale/legacy
    // ACK arrives, the tool must NOT tell the LLM to retry — it reads as
    // delivered (the peer's harness enqueues mid-turn messages).
    const { pi, tools } = makeMockPi();
    const peer = makeMockPeer({
      sendWithAck: vi.fn().mockResolvedValue(
        { status: "busy", id: "uuid-out", target: "backend" } satisfies AckResult,
      ),
    });
    registerAgentTools(pi, () => peer);
    const tool = tools.get("agent_send")!;

    const result = await tool.execute(
      TOOL_CALL_ID,
      { to: "backend", body: { x: 1 } },
      undefined, undefined, {} as never,
    );

    expect(
      (result.content[0] as { type: "text"; text: string }).text,
    ).toMatch(/delivered/i);
  });

  test("unicast denied peer → status=denied, ok=false", async () => {
    const { pi, tools } = makeMockPi();
    const peer = makeMockPeer({
      sendWithAck: vi.fn().mockResolvedValue(
        { status: "denied", id: "uuid-out", target: "backend" } satisfies AckResult,
      ),
    });
    registerAgentTools(pi, () => peer);
    const tool = tools.get("agent_send")!;

    const result = await tool.execute(
      TOOL_CALL_ID,
      { to: "backend", body: { x: 1 } },
      undefined, undefined, {} as never,
    );

    expect(result.details).toMatchObject({ status: "denied", ok: false });
  });

  test("unicast timeout → status=timeout, ok=false", async () => {
    const { pi, tools } = makeMockPi();
    const peer = makeMockPeer({
      sendWithAck: vi.fn().mockResolvedValue(
        { status: "timeout", id: "uuid-out" } satisfies AckResult,
      ),
    });
    registerAgentTools(pi, () => peer);
    const tool = tools.get("agent_send")!;

    const result = await tool.execute(
      TOOL_CALL_ID,
      { to: "backend", body: { x: 1 } },
      undefined, undefined, {} as never,
    );

    expect(result.details).toMatchObject({ status: "timeout", ok: false });
  });

  test("forwards `re` for replies (correlation field)", async () => {
    const { pi, tools } = makeMockPi();
    const peer = makeMockPeer();
    registerAgentTools(pi, () => peer);
    const tool = tools.get("agent_send")!;

    await tool.execute(
      TOOL_CALL_ID,
      { to: "frontend", body: { answer: "pong" }, re: "01976000-0000-7000-8000-000000000000" },
      undefined, undefined, {} as never,
    );

    expect(peer.sendWithAck).toHaveBeenCalledWith(
      "frontend",
      { answer: "pong" },
      "01976000-0000-7000-8000-000000000000",
      5_000,
    );
  });

  test("broadcast → fire-and-forget, status=sent, uses peer.send not sendWithAck", async () => {
    const { pi, tools } = makeMockPi();
    const peer = makeMockPeer();
    registerAgentTools(pi, () => peer);
    const tool = tools.get("agent_send")!;

    const result = await tool.execute(
      TOOL_CALL_ID,
      { to: "broadcast", body: { announce: "wave-2-started" } },
      undefined, undefined, {} as never,
    );

    expect(peer.send).toHaveBeenCalledWith("broadcast", { announce: "wave-2-started" }, null);
    expect(peer.sendWithAck).not.toHaveBeenCalled();
    expect(result.details).toMatchObject({ status: "sent", ok: true });
  });

  test("not in a session → status=refused", async () => {
    const { pi, tools } = makeMockPi();
    registerAgentTools(pi, () => null);
    const tool = tools.get("agent_send")!;

    const result = await tool.execute(
      TOOL_CALL_ID,
      { to: "backend", body: "hi" },
      undefined, undefined, {} as never,
    );

    expect(result.details).toMatchObject({
      status: "refused",
      ok: false,
      error: expect.stringContaining("Not in a session"),
    });
  });

  test("body as string passes through intact", async () => {
    const { pi, tools } = makeMockPi();
    const peer = makeMockPeer();
    registerAgentTools(pi, () => peer);
    const tool = tools.get("agent_send")!;

    await tool.execute(
      TOOL_CALL_ID,
      { to: "backend", body: "plain string body" },
      undefined, undefined, {} as never,
    );
    expect(peer.sendWithAck).toHaveBeenCalledWith("backend", "plain string body", null, 5_000);
  });

  test("nested body object passes through intact", async () => {
    const { pi, tools } = makeMockPi();
    const peer = makeMockPeer();
    registerAgentTools(pi, () => peer);
    const tool = tools.get("agent_send")!;

    const nested = { a: { b: { c: [1, 2, { d: "x" }] } }, e: null };
    await tool.execute(
      TOOL_CALL_ID,
      { to: "fanout-target", body: nested },
      undefined, undefined, {} as never,
    );
    expect(peer.sendWithAck).toHaveBeenCalledWith("fanout-target", nested, null, 5_000);
  });

  test("self-send refused early → sendWithAck not called", async () => {
    const { pi, tools } = makeMockPi();
    const peer = makeMockPeer({ name: "orq" });
    registerAgentTools(pi, () => peer);
    const tool = tools.get("agent_send")!;

    const result = await tool.execute(
      TOOL_CALL_ID,
      { to: "orq", body: { x: 1 } },
      undefined, undefined, {} as never,
    );

    expect(peer.sendWithAck).not.toHaveBeenCalled();
    expect(result.details).toMatchObject({
      status: "refused",
      ok: false,
      error: expect.stringContaining("cannot agent_send to yourself"),
    });
  });
});

describe("list_peers tool", () => {
  function makeListPeersPeer(
    peers: string[],
    overrides: { name?: string; request?: unknown } = {},
  ) {
    const myName = overrides.name ?? "orq";
    return {
      name: () => myName,
      send: vi.fn(),
      sendWithAck: vi.fn(),
      request: overrides.request ?? vi.fn().mockResolvedValue({
        from: "broker", to: myName, id: "uuid-reply", re: "uuid-orig",
        body: { type: "list_peers_reply", peers },
      }),
    } as unknown as SessionPeer;
  }

  test("returns locals + cross-PC entries, excludes self", async () => {
    const { pi, tools } = makeMockPi();
    const peer = makeListPeersPeer(["orq", "backend", "casa:agent-1"]);
    registerAgentTools(pi, () => peer);
    const tool = tools.get("list_peers")!;

    const result = await tool.execute(TOOL_CALL_ID, {}, undefined, undefined, {} as never);

    expect(peer.request).toHaveBeenCalledWith("broker", { type: "list_peers" }, 2_000);
    expect(result.details).toEqual({ peers: ["backend", "casa:agent-1"] });
    expect((result.content[0] as { type: "text"; text: string }).text).toBe(
      "backend\ncasa:agent-1",
    );
  });

  test("empty inventory → (no peers) text", async () => {
    const { pi, tools } = makeMockPi();
    const peer = makeListPeersPeer(["orq"]);  // only self
    registerAgentTools(pi, () => peer);
    const tool = tools.get("list_peers")!;

    const result = await tool.execute(TOOL_CALL_ID, {}, undefined, undefined, {} as never);
    expect(result.details).toEqual({ peers: [] });
    expect((result.content[0] as { type: "text"; text: string }).text).toBe("(no peers)");
  });

  test("not in session → empty peers + NOT_IN_SESSION text", async () => {
    const { pi, tools } = makeMockPi();
    registerAgentTools(pi, () => null);
    const tool = tools.get("list_peers")!;

    const result = await tool.execute(TOOL_CALL_ID, {}, undefined, undefined, {} as never);
    expect(result.details).toEqual({ peers: [] });
    expect((result.content[0] as { type: "text"; text: string }).text).toContain("Not in a session");
  });

  test("broker request throws → structured error, peers=[]", async () => {
    const { pi, tools } = makeMockPi();
    const peer = makeListPeersPeer([], {
      request: vi.fn().mockRejectedValue(new Error("request to broker timed out")),
    });
    registerAgentTools(pi, () => peer);
    const tool = tools.get("list_peers")!;

    const result = await tool.execute(TOOL_CALL_ID, {}, undefined, undefined, {} as never);
    expect(result.details).toEqual({ peers: [] });
    expect((result.content[0] as { type: "text"; text: string }).text).toContain("list_peers failed");
  });
});

describe("agent_request tool (deprecated, still functional)", () => {
  test("legacy: calls SessionPeer.request → returns reply.body via details", async () => {
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

  test("custom timeout_ms is honored", async () => {
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

  test("not in a session → structured error", async () => {
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

  test("SessionPeer.request throws (timeout) → structured error", async () => {
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

  test("self-request refused early → request not called", async () => {
    const { pi, tools } = makeMockPi();
    const peer = makeMockPeer({ name: "orq" });
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
