import { randomUUID } from "node:crypto";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import type { ServerMessage } from "./protocol/types.js";

type JsonObject = Record<string, unknown>;
function object(value: unknown): JsonObject | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as JsonObject : undefined;
}

/** Optional pi-subagents public RPC; never starts or controls a run. */
export function createSubagentBridge(
  pi: ExtensionAPI,
  broadcast: (message: ServerMessage) => void,
  onRefresh: () => void = () => {},
) {
  const events = pi.events;
  const snapshots = new Map<string, ServerMessage[]>();
  const subscriptions: (() => void)[] = [];
  let timer: ReturnType<typeof setTimeout> | undefined;
  let timeout: ReturnType<typeof setTimeout> | undefined;
  let unsubscribeReply: (() => void) | undefined;
  let inFlight = false;
  let dirty = false;
  let disposed = false;

  function finish() {
    if (timeout) clearTimeout(timeout);
    timeout = undefined;
    unsubscribeReply?.();
    unsubscribeReply = undefined;
    inFlight = false;
    if (dirty) refresh();
  }

  function readStatus() {
    timer = undefined;
    if (disposed || inFlight) return;
    onRefresh();
    dirty = false;
    inFlight = true;
    const requestId = randomUUID();
    unsubscribeReply = events.on(`subagents:rpc:v1:reply:${requestId}`, (raw: unknown) => {
      if (disposed) return;
      const reply = object(raw);
      if (reply?.version !== 1 || reply.requestId !== requestId) return;
      if (reply.success === false) {
        console.warn("[remote-pi] subagent status failed:", object(reply.error)?.message);
      } else if (reply.success === true) {
        const snapshot = object(object(reply.data)?.asyncSnapshot);
        if (snapshot?.version === 1 && Array.isArray(snapshot.runs)) {
          const previous = new Set(snapshots.keys());
          snapshots.clear();
          for (const rawRun of snapshot.runs) {
            const run = object(rawRun);
            if (!run || typeof run.id !== "string" || typeof run.state !== "string") continue;
            const id = `subagent-run:${run.id}`;
            const details = { mode: "workflow", runs: [run], omitted: snapshot.omitted };
            const terminal = ["complete", "failed", "partial", "stopped", "rejected"].includes(run.state);
            const messages: ServerMessage[] = [
              { type: "tool_request", tool_call_id: id, tool: "subagent", args: { workflow: run.label ?? run.id } },
              terminal
                ? {
                    type: "tool_result", tool_call_id: id, details,
                    ...(run.state === "complete" ? { result: "Background workflow completed" } : { error: `Background workflow ${run.state}` }),
                  }
                : { type: "tool_update", tool_call_id: id, tool: "subagent", args: {}, details },
            ];
            snapshots.set(id, messages);
            for (const message of previous.has(id) ? messages.slice(1) : messages) broadcast(message);
          }
        }
      }
      finish();
    });
    // Absence of the optional package is not an error.
    timeout = setTimeout(finish, 2000);
    events.emit("subagents:rpc:v1:request", { version: 1, requestId, method: "status", params: {} });
  }

  function refresh() {
    if (disposed) return;
    dirty = true;
    if (!inFlight && !timer) timer = setTimeout(readStatus, 250);
  }

  for (const event of [
    "subagents:rpc:v1:ready",
    "subagent:jobs-changed",
    "subagent:async-started",
    "subagent:child-status",
    "subagent:async-complete",
    "subagent:process-terminal",
  ]) {
    subscriptions.push(events.on(event, refresh));
  }

  return {
    refresh,
    snapshot: () => [...snapshots.values()].flat(),
    dispose() {
      disposed = true;
      dirty = false;
      if (timer) clearTimeout(timer);
      finish();
      for (const unsubscribe of subscriptions) unsubscribe();
      snapshots.clear();
    },
  };
}
