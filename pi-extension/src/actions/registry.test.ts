import { beforeEach, describe, expect, test } from "vitest";

import { _resetModelRegistryForTests, ensureModelRegistry } from "./registry.js";
import type { ActionModelRegistry } from "./handlers.js";

function fakeRegistry(tag: string): ActionModelRegistry {
  return {
    refresh() {},
    getAvailable() { return [{ id: tag } as never]; },
    find() { return undefined; },
  };
}

describe("ensureModelRegistry (issue #112)", () => {
  beforeEach(() => _resetModelRegistryForTests());

  test("returns the live registry off the ctx", () => {
    const reg = fakeRegistry("live");
    expect(ensureModelRegistry({ modelRegistry: reg })).toBe(reg);
  });

  test("never throws without a ctx — returns an inert stub", () => {
    const reg = ensureModelRegistry(null);
    expect(() => reg.refresh()).not.toThrow();
    expect(reg.getAvailable()).toEqual([]);
    expect(reg.find("anthropic", "claude")).toBeUndefined();
  });

  test("falls back to the last good registry when the ctx went stale", () => {
    const good = fakeRegistry("good");
    ensureModelRegistry({ modelRegistry: good });

    // A ctx captured before a session replacement throws on property READ.
    const stale = {
      get modelRegistry(): ActionModelRegistry {
        throw new Error("This extension ctx is stale after session replacement or reload.");
      },
    };
    expect(ensureModelRegistry(stale)).toBe(good);
  });

  test("falls back to the stub when the stale ctx is the very first one seen", () => {
    const stale = {
      get modelRegistry(): ActionModelRegistry {
        throw new Error("stale");
      },
    };
    expect(() => ensureModelRegistry(stale).getAvailable()).not.toThrow();
  });
});
