import { afterEach, describe, expect, test, vi } from "vitest";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { createSubagentBridge } from "./subagent_bridge.js";

function harness() {
  vi.useFakeTimers();
  const listeners = new Map<string, Set<(value: unknown) => void>>();
  const requests: Record<string, unknown>[] = [];
  const events = {
    on(name: string, handler: (value: unknown) => void) {
      if (!listeners.has(name)) listeners.set(name, new Set());
      listeners.get(name)!.add(handler);
      return () => { listeners.get(name)?.delete(handler); };
    },
    emit(name: string, value: unknown) {
      if (name === "subagents:rpc:v1:request") requests.push(value as Record<string, unknown>);
      for (const handler of [...listeners.get(name) ?? []]) handler(value);
    },
  };
  const broadcast = vi.fn();
  const bridge = createSubagentBridge({ events } as ExtensionAPI, broadcast);
  const reply = (runs: unknown[], request = requests.at(-1)!) => events.emit(
    `subagents:rpc:v1:reply:${request.requestId}`,
    { version: 1, requestId: request.requestId, success: true,
      data: { asyncSnapshot: { version: 1, runs } } },
  );
  return { bridge, broadcast, events, requests, reply, listeners };
}

afterEach(() => vi.useRealTimers());

describe("optional subagent background status bridge", () => {
  test("coalesces events and updates one stable row without starting any work", () => {
    const h = harness();
    h.events.emit("subagent:jobs-changed", { version: 1 });
    h.events.emit("subagent:async-started", {});
    vi.advanceTimersByTime(250);
    expect(h.requests).toHaveLength(1);
    expect(h.requests[0]).toMatchObject({ method: "status", params: {} });
    h.reply([{ id: "run-1", label: "Review", state: "running",
      children: [{ id: "review", agent: "reviewer", state: "running" }] }]);
    expect(h.broadcast.mock.calls.map(([m]) => m.type)).toEqual(["tool_request", "tool_update"]);
    expect(h.bridge.snapshot()).toHaveLength(2);
    h.bridge.refresh();
    vi.advanceTimersByTime(250);
    h.reply([{ id: "run-1", label: "Review", state: "complete" }]);
    expect(h.broadcast.mock.calls.at(-1)?.[0]).toMatchObject({
      type: "tool_result", tool_call_id: "subagent-run:run-1",
      result: "Background workflow completed",
    });
    expect(h.broadcast.mock.calls.filter(([m]) => m.type === "tool_request")).toHaveLength(1);
    h.bridge.dispose();
    expect(vi.getTimerCount()).toBe(0);
  });

  test("retains refreshes arriving while status is in flight", () => {
    const h = harness();
    h.bridge.refresh();
    vi.advanceTimersByTime(250);
    h.events.emit("subagent:child-status", {});
    h.reply([]);
    vi.advanceTimersByTime(250);
    expect(h.requests).toHaveLength(2);
    h.reply([{ id: "bad", state: "failed" }]);
    expect(h.broadcast.mock.calls.at(-1)?.[0]).toMatchObject({
      type: "tool_result", error: "Background workflow failed",
    });
    h.bridge.dispose();
  });

  test("absence of optional package times out without polling or leaking", () => {
    const h = harness();
    h.bridge.refresh();
    vi.advanceTimersByTime(10000);
    expect(h.requests).toHaveLength(1);
    expect(h.broadcast).not.toHaveBeenCalled();
    expect(h.bridge.snapshot()).toEqual([]);
    h.bridge.dispose();
    expect([...h.listeners.values()].every((set) => set.size === 0)).toBe(true);
    expect(vi.getTimerCount()).toBe(0);
  });

  test("disposal rejects stale replies and pending refreshes", () => {
    const h = harness();
    h.bridge.refresh();
    vi.advanceTimersByTime(250);
    const request = h.requests[0]!;
    h.bridge.dispose();
    h.reply([{ id: "old-session", state: "running" }], request);
    h.events.emit("subagent:jobs-changed", {});
    vi.advanceTimersByTime(5000);
    expect(h.broadcast).not.toHaveBeenCalled();
    expect(h.requests).toHaveLength(1);
  });

  test("RPC errors are visible and unknown snapshot versions are ignored", () => {
    const h = harness();
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
    h.bridge.refresh();
    vi.advanceTimersByTime(250);
    const request = h.requests[0]!;
    h.events.emit(`subagents:rpc:v1:reply:${request.requestId}`, {
      version: 1, requestId: request.requestId, success: false,
      error: { message: "Unavailable session" },
    });
    expect(warn).toHaveBeenCalledWith(
      "[remote-pi] subagent status failed:", "Unavailable session",
    );
    h.bridge.refresh();
    vi.advanceTimersByTime(250);
    const next = h.requests[1]!;
    h.events.emit(`subagents:rpc:v1:reply:${next.requestId}`, {
      version: 1, requestId: next.requestId, success: true,
      data: { asyncSnapshot: { version: 2, runs: [{ id: "future", state: "running" }] } },
    });
    expect(h.broadcast).not.toHaveBeenCalled();
    h.bridge.dispose();
    warn.mockRestore();
  });
});
