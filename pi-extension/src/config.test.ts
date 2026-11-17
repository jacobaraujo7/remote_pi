import { afterEach, describe, expect, test, vi } from "vitest";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import {
  isValidRelayUrl,
  isWebSocketScheme,
  toWebSocketUrl,
  toHttpUrl,
  kDefaultRelayUrl,
  loadConfig,
  saveConfig,
} from "./config.js";

describe("mesh delivery config", () => {
  afterEach(() => vi.restoreAllMocks());

  test("loads steer from the existing per-user config file", () => {
    const read = vi.spyOn(fs, "readFileSync").mockReturnValue('{"relay":"https://example.test","meshDelivery":"steer"}');
    expect(loadConfig()).toEqual({ relay: "https://example.test", meshDelivery: "steer" });
    expect(read).toHaveBeenCalledWith(path.join(os.homedir(), ".pi", "remote", "config.json"), "utf8");
  });

  test("saving a relay preserves meshDelivery and unrelated existing fields", () => {
    vi.spyOn(fs, "readFileSync").mockReturnValue('{"meshDelivery":"steer","other":"keep"}');
    vi.spyOn(fs, "mkdirSync").mockImplementation(() => undefined);
    const write = vi.spyOn(fs, "writeFileSync").mockImplementation(() => undefined);
    saveConfig({ relay: "https://example.test" });
    expect(JSON.parse(String(write.mock.calls[0]![1]))).toEqual({
      meshDelivery: "steer", other: "keep", relay: "https://example.test",
    });
  });
});

describe("isValidRelayUrl (strict http(s):// only)", () => {
  test("accepts http://", () => {
    expect(isValidRelayUrl("http://foo.test")).toBe(true);
    expect(isValidRelayUrl("http://foo.test:3000")).toBe(true);
    expect(isValidRelayUrl("http://192.168.1.10:3000")).toBe(true);
  });

  test("accepts https://", () => {
    expect(isValidRelayUrl("https://relay.example.tld")).toBe(true);
    expect(isValidRelayUrl("https://relay-rp1.jacobmoura.work")).toBe(true);
  });

  test("rejects ws:// (user must use http:// + auto-convert)", () => {
    expect(isValidRelayUrl("ws://foo.test")).toBe(false);
    expect(isValidRelayUrl("ws://192.168.1.10:3000")).toBe(false);
  });

  test("rejects wss:// (user must use https:// + auto-convert)", () => {
    expect(isValidRelayUrl("wss://relay.example.tld")).toBe(false);
  });

  test("rejects empty / non-URL / non-http scheme", () => {
    expect(isValidRelayUrl("")).toBe(false);
    expect(isValidRelayUrl("not a url")).toBe(false);
    expect(isValidRelayUrl("ftp://example.tld")).toBe(false);
    expect(isValidRelayUrl("file:///etc/passwd")).toBe(false);
  });
});

describe("isWebSocketScheme", () => {
  test("true for ws:// and wss://", () => {
    expect(isWebSocketScheme("ws://foo")).toBe(true);
    expect(isWebSocketScheme("wss://foo")).toBe(true);
    expect(isWebSocketScheme("WSS://Foo")).toBe(true); // case-insensitive
  });

  test("false for http://, https://, and others", () => {
    expect(isWebSocketScheme("http://foo")).toBe(false);
    expect(isWebSocketScheme("https://foo")).toBe(false);
    expect(isWebSocketScheme("ftp://foo")).toBe(false);
    expect(isWebSocketScheme("")).toBe(false);
  });
});

describe("toWebSocketUrl (http(s):// → ws(s)://)", () => {
  test("https:// → wss://", () => {
    expect(toWebSocketUrl("https://relay.example.tld")).toBe("wss://relay.example.tld");
    expect(toWebSocketUrl("https://foo:3000/path")).toBe("wss://foo:3000/path");
  });

  test("http:// → ws://", () => {
    expect(toWebSocketUrl("http://relay.example.tld")).toBe("ws://relay.example.tld");
    expect(toWebSocketUrl("http://192.168.1.10:3000")).toBe("ws://192.168.1.10:3000");
  });

  test("ws(s):// pass through (defensive — env override may bypass validation)", () => {
    expect(toWebSocketUrl("ws://foo")).toBe("ws://foo");
    expect(toWebSocketUrl("wss://foo")).toBe("wss://foo");
  });

  test("case-insensitive scheme match", () => {
    expect(toWebSocketUrl("HTTPS://Foo")).toBe("wss://Foo");
    expect(toWebSocketUrl("HTTP://Foo")).toBe("ws://Foo");
  });
});

describe("toHttpUrl (ws(s):// → http(s)://)", () => {
  test("wss:// → https://", () => {
    expect(toHttpUrl("wss://relay.example.tld")).toBe("https://relay.example.tld");
  });

  test("ws:// → http://", () => {
    expect(toHttpUrl("ws://192.168.1.10:3000")).toBe("http://192.168.1.10:3000");
  });

  test("http(s):// pass through", () => {
    expect(toHttpUrl("https://foo")).toBe("https://foo");
    expect(toHttpUrl("http://foo:3000")).toBe("http://foo:3000");
  });
});

describe("kDefaultRelayUrl", () => {
  test("is canonical https:// form (no scheme conversion needed at resolve time)", () => {
    expect(kDefaultRelayUrl).toMatch(/^https:\/\//);
    expect(kDefaultRelayUrl).toBe("https://relay-rp1.jacobmoura.work");
  });
});
