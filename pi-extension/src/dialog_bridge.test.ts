import { describe, expect, it } from "vitest";
import { createDialogBridge, type DialogUi } from "./dialog_bridge.js";
import type { ExtensionUiResponseWire, ServerMessage } from "./protocol/types.js";

// ── Fake ui: dialogs stay open until the test settles or aborts them ────────
interface OpenDialog {
  method: string;
  args: unknown[];
  signal: AbortSignal | undefined;
  settle: (value: unknown) => void;
}

function fakeUi(): DialogUi & { open: OpenDialog[]; notify: () => void } {
  const open: OpenDialog[] = [];
  const dialog = (method: string, fallback: unknown) =>
    (...args: unknown[]) => {
      const last = args[args.length - 1] as { signal?: AbortSignal } | undefined;
      const signal = method === "editor" ? undefined : last?.signal;
      return new Promise((resolve) => {
        open.push({ method, args, signal, settle: resolve });
        signal?.addEventListener("abort", () => resolve(fallback), { once: true });
      });
    };
  return {
    open,
    select: dialog("select", undefined) as DialogUi["select"],
    confirm: dialog("confirm", false) as DialogUi["confirm"],
    input: dialog("input", undefined) as DialogUi["input"],
    editor: dialog("editor", undefined) as DialogUi["editor"],
    notify: () => {},
  };
}

function setup() {
  const sent: ServerMessage[] = [];
  const bridge = createDialogBridge((m) => sent.push(m));
  const ui = fakeUi();
  bridge.install(ui);
  return { sent, bridge, ui };
}

function lastRequestId(sent: ServerMessage[]): string {
  const req = [...sent].reverse().find(
    (m) => m.type === "extension_ui_request" && m.method !== "notify",
  );
  if (!req || req.type !== "extension_ui_request") throw new Error("no request");
  return req.id;
}

const response = (r: Omit<ExtensionUiResponseWire, "type">) =>
  ({ type: "extension_ui_response", ...r }) as ExtensionUiResponseWire;

describe("dialog_bridge", () => {
  it("broadcasts a select request and resolves with the app's answer", async () => {
    const { sent, bridge, ui } = setup();
    const p = ui.select("Pick", ["a", "b"]);
    expect(sent[0]).toMatchObject({
      type: "extension_ui_request",
      method: "select",
      title: "Pick",
      options: ["a", "b"],
    });
    expect(bridge.respond(response({ id: lastRequestId(sent), value: "b" }))).toBe(true);
    await expect(p).resolves.toBe("b");
  });

  it("aborts the desk dialog when the app answers first", async () => {
    const { sent, bridge, ui } = setup();
    const p = ui.confirm("Run?", "rm -rf build");
    const desk = ui.open[0];
    bridge.respond(response({ id: lastRequestId(sent), confirmed: true }));
    await expect(p).resolves.toBe(true);
    expect(desk?.signal?.aborted).toBe(true);
    // App answered: no dismiss notify needed.
    expect(sent.filter((m) => m.type === "extension_ui_request" && m.method === "notify")).toHaveLength(0);
  });

  it("dismisses the app request when the desk answers first", async () => {
    const { sent, bridge, ui } = setup();
    const p = ui.input("Name?", "placeholder");
    const id = lastRequestId(sent);
    ui.open[0]?.settle("desk");
    await expect(p).resolves.toBe("desk");
    expect(sent.at(-1)).toMatchObject({ type: "extension_ui_request", id, method: "notify" });
    // Late app answer is ignored and not claimed.
    expect(bridge.respond(response({ id, value: "late" }))).toBe(false);
    expect(bridge.pendingRequests()).toHaveLength(0);
  });

  it("maps cancelled to the method's default", async () => {
    const { sent, bridge, ui } = setup();
    const sel = ui.select("Pick", ["a"]);
    bridge.respond(response({ id: lastRequestId(sent), cancelled: true }));
    await expect(sel).resolves.toBeUndefined();
    const conf = ui.confirm("Ok?", "msg");
    bridge.respond(response({ id: lastRequestId(sent), cancelled: true }));
    await expect(conf).resolves.toBe(false);
  });

  it("follows the caller's abort signal and dismisses the app", async () => {
    const { sent, ui } = setup();
    const ac = new AbortController();
    const p = ui.select("Pick", ["a"], { signal: ac.signal });
    const id = lastRequestId(sent);
    ac.abort();
    await expect(p).resolves.toBeUndefined();
    expect(sent.at(-1)).toMatchObject({ id, method: "notify" });
  });

  it("forwards editor and lets the app win even though desk can't be aborted", async () => {
    const { sent, bridge, ui } = setup();
    const p = ui.editor("Edit", "prefill");
    expect(sent[0]).toMatchObject({ method: "editor", prefill: "prefill" });
    bridge.respond(response({ id: lastRequestId(sent), value: "edited" }));
    await expect(p).resolves.toBe("edited");
  });

  it("replays pending requests and ignores foreign ids", () => {
    const { sent, bridge, ui } = setup();
    void ui.select("Pick", ["a"]);
    expect(bridge.pendingRequests()).toEqual([sent[0]]);
    expect(bridge.respond(response({ id: "not-ours", value: "x" }))).toBe(false);
  });

  it("installs once per ui object and restores on dispose", () => {
    const sent: ServerMessage[] = [];
    const bridge = createDialogBridge((m) => sent.push(m));
    const ui = fakeUi();
    const original = ui.select;
    bridge.install(ui);
    const wrapped = ui.select;
    bridge.install(ui);
    expect(ui.select).toBe(wrapped);
    bridge.dispose();
    expect(ui.select).toBe(original);
  });

  it("ignores objects that are not dialog uis", () => {
    const bridge = createDialogBridge(() => {});
    expect(() => bridge.install(undefined)).not.toThrow();
    expect(() => bridge.install({ select: () => {} })).not.toThrow();
  });
});
