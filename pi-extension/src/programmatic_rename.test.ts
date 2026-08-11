import { describe, expect, test, vi } from "vitest";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import {
  createProgrammaticRenameApi,
  REMOTE_PI_RENAME_REQUEST_EVENT,
} from "./programmatic_rename.js";

type Listener = (payload: unknown) => void;

class FakeEventBus {
  private readonly listeners = new Map<string, Set<Listener>>();

  on(name: string, listener: Listener): () => void {
    const listeners = this.listeners.get(name) ?? new Set<Listener>();
    listeners.add(listener);
    this.listeners.set(name, listeners);
    return () => listeners.delete(listener);
  }

  emit(name: string, payload: unknown): void {
    for (const listener of this.listeners.get(name) ?? []) listener(payload);
  }
}

function makePi(events: FakeEventBus): ExtensionAPI {
  return { events } as unknown as ExtensionAPI;
}

function deferred(): { promise: Promise<void>; resolve(): void } {
  let resolve!: () => void;
  const promise = new Promise<void>((done) => { resolve = done; });
  return { promise, resolve };
}

describe("programmatic rename API", () => {
  test("trims and forwards a valid versioned request", async () => {
    const events = new FakeEventBus();
    const rename = vi.fn(async () => true);
    const api = createProgrammaticRenameApi(makePi(events), rename);

    events.emit(REMOTE_PI_RENAME_REQUEST_EVENT, {
      version: 1,
      name: "  Incident Investigation  ",
    });

    await vi.waitFor(() => {
      expect(rename).toHaveBeenCalledWith("Incident Investigation");
    });
    api?.();
  });

  test("ignores malformed, unsupported, and empty requests", async () => {
    const events = new FakeEventBus();
    const rename = vi.fn(async () => true);
    const api = createProgrammaticRenameApi(makePi(events), rename);

    events.emit(REMOTE_PI_RENAME_REQUEST_EVENT, null);
    events.emit(REMOTE_PI_RENAME_REQUEST_EVENT, { name: "missing version" });
    events.emit(REMOTE_PI_RENAME_REQUEST_EVENT, { version: 2, name: "future" });
    events.emit(REMOTE_PI_RENAME_REQUEST_EVENT, { version: 1, name: "   " });
    await Promise.resolve();

    expect(rename).not.toHaveBeenCalled();
    api?.();
  });

  test("serializes rename requests", async () => {
    const events = new FakeEventBus();
    const first = deferred();
    const calls: string[] = [];
    const rename = vi.fn(async (name: string) => {
      calls.push(name);
      if (name === "first") await first.promise;
      return true;
    });
    const api = createProgrammaticRenameApi(makePi(events), rename);

    events.emit(REMOTE_PI_RENAME_REQUEST_EVENT, { version: 1, name: "first" });
    events.emit(REMOTE_PI_RENAME_REQUEST_EVENT, { version: 1, name: "second" });

    await vi.waitFor(() => expect(calls).toEqual(["first"]));
    first.resolve();
    await vi.waitFor(() => expect(calls).toEqual(["first", "second"]));
    api?.();
  });

  test("dispose unsubscribes and drops queued requests", async () => {
    const events = new FakeEventBus();
    const first = deferred();
    const calls: string[] = [];
    const rename = vi.fn(async (name: string) => {
      calls.push(name);
      if (name === "first") await first.promise;
      return true;
    });
    const api = createProgrammaticRenameApi(makePi(events), rename);

    events.emit(REMOTE_PI_RENAME_REQUEST_EVENT, { version: 1, name: "first" });
    events.emit(REMOTE_PI_RENAME_REQUEST_EVENT, { version: 1, name: "queued" });
    await vi.waitFor(() => expect(calls).toEqual(["first"]));

    api?.();
    first.resolve();
    events.emit(REMOTE_PI_RENAME_REQUEST_EVENT, { version: 1, name: "late" });
    await Promise.resolve();
    await Promise.resolve();

    expect(calls).toEqual(["first"]);
  });
});
