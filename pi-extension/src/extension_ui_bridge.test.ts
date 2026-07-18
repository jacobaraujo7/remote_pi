import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { describe, expect, it } from "vitest";
import { createExtensionUiBridge } from "./extension_ui_bridge.js";
import type { ExtensionUiResponseWire, ServerMessage } from "./protocol/types.js";

// ── Fake pi.events bus ──────────────────────────────────────────────────────
// Records every emit (name + data) so tests can assert what the bridge forwarded
// to pi-ask, and dispatches to registered handlers so tests can simulate pi-ask
// firing started/completed/submit-result.
interface FakeBus {
  on(name: string, cb: (data: unknown) => void): () => void;
  emit(name: string, data: unknown): void;
  emitted: Array<{ name: string; data: unknown }>;
}

function fakeBus(): FakeBus {
  const handlers = new Map<string, Set<(data: unknown) => void>>();
  const emitted: Array<{ name: string; data: unknown }> = [];
  return {
    on(name, cb) {
      let set = handlers.get(name);
      if (!set) {
        set = new Set();
        handlers.set(name, set);
      }
      set.add(cb);
      return () => {
        set?.delete(cb);
      };
    },
    emit(name, data) {
      emitted.push({ name, data });
      handlers.get(name)?.forEach((cb) => cb(data));
    },
    emitted,
  };
}

function fakePi(bus: FakeBus): ExtensionAPI {
  return { events: bus } as unknown as ExtensionAPI;
}

function singleQuestionFlow(overrides: Partial<Record<string, unknown>> = {}) {
  return {
    version: 1,
    flowId: "tool:tc_1",
    toolCallId: "tc_1",
    source: "tool",
    title: "Direction",
    questions: [
      {
        id: "goal",
        label: "Goal",
        prompt: "What's the goal?",
        type: "single",
        required: true,
        options: [
          { value: "a", label: "Alpha" },
          { value: "b", label: "Beta", description: "second choice" },
        ],
      },
    ],
    ...overrides,
  };
}

const SUBMIT = "@eko24ive/pi-ask:submit";

describe("extension_ui_bridge", () => {
  it("returns null when the SDK exposes no events bus (inert)", () => {
    const pi = {} as unknown as ExtensionAPI;
    expect(createExtensionUiBridge(pi, () => {})).toBeNull();
  });

  it("translates a pi-ask `started` event into one extension_ui_request", () => {
    const bus = fakeBus();
    const sent: ServerMessage[] = [];
    createExtensionUiBridge(fakePi(bus), (m) => sent.push(m));

    bus.emit("@eko24ive/pi-ask:started", singleQuestionFlow());

    expect(sent).toHaveLength(1);
    const req = sent[0];
    expect(req.type).toBe("extension_ui_request");
    if (req.type !== "extension_ui_request") return;
    expect(req.method).toBe("select");
    if (req.method !== "select") return;
    expect(req.id).toBe("tool:tc_1");
    expect(req.title).toBe("Direction");
    expect(req.options).toEqual(["Alpha", "Beta"]);
    expect(req.ask?.flow_id).toBe("tool:tc_1");
    expect(req.ask?.tool_call_id).toBe("tc_1");
    expect(req.ask?.source).toBe("tool");
    expect(req.ask?.questions).toHaveLength(1);
    expect(req.ask?.questions[0]?.options.map((o) => o.value)).toEqual(["a", "b"]);
    // description survives (pi-ask addition rides in the envelope)
    expect(req.ask?.questions[0]?.options[1]?.description).toBe("second choice");
  });

  it("forwards a rich answer back to pi-ask as a single submit", () => {
    const bus = fakeBus();
    const bridge = createExtensionUiBridge(fakePi(bus), () => {})!;

    const response: ExtensionUiResponseWire = {
      type: "extension_ui_response",
      id: "tool:tc_1",
      value: "Alpha",
      ask: {
        flow_id: "tool:tc_1",
        kind: "answer",
        mode: "submit",
        answers: { goal: { values: ["a"] } },
      },
    };
    bridge.respond(response);

    const submits = bus.emitted.filter((e) => e.name === SUBMIT);
    expect(submits).toHaveLength(1);
    expect(submits[0]?.data).toEqual({
      version: 1,
      requestId: "tool:tc_1",
      flowId: "tool:tc_1",
      response: {
        kind: "answer",
        mode: "submit",
        answers: { goal: { values: ["a"] } },
      },
    });
  });

  it("forwards a cancel as { kind: 'cancel' }", () => {
    const bus = fakeBus();
    const bridge = createExtensionUiBridge(fakePi(bus), () => {})!;

    bridge.respond({
      type: "extension_ui_response",
      id: "tool:tc_1",
      cancelled: true,
      ask: { flow_id: "tool:tc_1", kind: "cancel" },
    });

    const submits = bus.emitted.filter((e) => e.name === SUBMIT);
    expect(submits).toHaveLength(1);
    const data = submits[0]?.data as { response: { kind: string } };
    expect(data.response).toEqual({ kind: "cancel" });
  });

  it("maps a label-only response back to the option value (degraded client)", () => {
    const bus = fakeBus();
    const sent: ServerMessage[] = [];
    const bridge = createExtensionUiBridge(fakePi(bus), (m) => sent.push(m))!;

    bus.emit(
      "@eko24ive/pi-ask:started",
      singleQuestionFlow({ flowId: "f1", toolCallId: undefined }),
    );

    // A client that ignored the `ask` envelope and rendered only the SDK select.
    bridge.respond({ type: "extension_ui_response", id: "f1", value: "Beta" });

    const submits = bus.emitted.filter((e) => e.name === SUBMIT);
    expect(submits).toHaveLength(1);
    const data = submits[0]?.data as {
      response: { answers: Record<string, unknown> };
    };
    expect(data.response.answers).toEqual({ goal: { values: ["b"] } });
  });

  it("broadcasts a dismiss notify (same id as the request) on completed", () => {
    const bus = fakeBus();
    const sent: ServerMessage[] = [];
    createExtensionUiBridge(fakePi(bus), (m) => sent.push(m));

    bus.emit("@eko24ive/pi-ask:started", singleQuestionFlow());
    sent.length = 0;
    bus.emit("@eko24ive/pi-ask:completed", { version: 1, flowId: "tool:tc_1" });

    expect(sent).toHaveLength(1);
    expect(sent[0]).toMatchObject({
      type: "extension_ui_request",
      id: "tool:tc_1",
      method: "notify",
    });
  });

  it("broadcasts a warning notify on a submit-result error", () => {
    const bus = fakeBus();
    const sent: ServerMessage[] = [];
    createExtensionUiBridge(fakePi(bus), (m) => sent.push(m));

    bus.emit("@eko24ive/pi-ask:submit-result", {
      version: 1,
      requestId: "r1",
      ok: false,
      error: "invalid_answer",
      message: "Unknown option value.",
    });

    expect(sent).toHaveLength(1);
    expect(sent[0]).toMatchObject({
      type: "extension_ui_request",
      method: "notify",
      notify_type: "warning",
      message: "Unknown option value.",
    });
  });

  it("treats a successful submit-result as a no-op (completed drives dismissal)", () => {
    const bus = fakeBus();
    const sent: ServerMessage[] = [];
    createExtensionUiBridge(fakePi(bus), (m) => sent.push(m));

    bus.emit("@eko24ive/pi-ask:submit-result", {
      version: 1,
      requestId: "r1",
      ok: true,
    });
    expect(sent).toHaveLength(0);
  });

  it("ignores malformed started events (never broadcasts)", () => {
    const bus = fakeBus();
    const sent: ServerMessage[] = [];
    createExtensionUiBridge(fakePi(bus), (m) => sent.push(m));

    bus.emit("@eko24ive/pi-ask:started", { version: 1 }); // no flowId / questions
    bus.emit("@eko24ive/pi-ask:started", { version: 2, flowId: "x", questions: [] }); // wrong version
    bus.emit("@eko24ive/pi-ask:started", {
      version: 1,
      flowId: "y",
      questions: [{ id: "q", prompt: "p", type: "single", required: false, options: [] }], // empty options
    });

    expect(sent).toHaveLength(0);
  });

  it("drops a response for an unknown flow id (degraded path)", () => {
    const bus = fakeBus();
    const bridge = createExtensionUiBridge(fakePi(bus), () => {})!;

    bridge.respond({ type: "extension_ui_response", id: "never-seen", value: "x" });

    expect(bus.emitted.filter((e) => e.name === SUBMIT)).toHaveLength(0);
  });
});
