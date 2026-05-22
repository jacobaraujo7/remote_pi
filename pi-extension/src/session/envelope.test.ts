import { describe, expect, test } from "vitest";
import { envelope, parse, serialize, uuidv7, EnvelopeError } from "./envelope.js";

describe("uuidv7", () => {
  test("returns valid UUID format", () => {
    const id = uuidv7();
    expect(id).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
  });

  test("3 sequential IDs are time-ordered", () => {
    const a = uuidv7();
    // Small delay to ensure different ms timestamp.
    const wait = Date.now() + 2;
    while (Date.now() < wait) { /* spin */ }
    const b = uuidv7();
    const wait2 = Date.now() + 2;
    while (Date.now() < wait2) { /* spin */ }
    const c = uuidv7();
    expect(a < b).toBe(true);
    expect(b < c).toBe(true);
  });
});

describe("serialize/parse roundtrip", () => {
  test("task message (body object)", () => {
    const env = envelope("orq", "backend", { task: "implement X", ctx: "foo" });
    const line = serialize(env);
    expect(line.endsWith("\n")).toBe(true);
    const parsed = parse(line.trim());
    expect(parsed).toEqual(env);
  });

  test("reply with re set", () => {
    const origId = uuidv7();
    const env = envelope("backend", "orq", { status: "done" }, origId);
    const parsed = parse(serialize(env).trim());
    expect(parsed.re).toBe(origId);
  });

  test("broadcast (to is string)", () => {
    const env = envelope("orq", "broadcast", { event: "wave_started" });
    const parsed = parse(serialize(env).trim());
    expect(parsed.to).toBe("broadcast");
  });

  test("multicast (to is array)", () => {
    const env = envelope("orq", ["backend", "frontend"], { event: "freeze" });
    const parsed = parse(serialize(env).trim());
    expect(parsed.to).toEqual(["backend", "frontend"]);
  });
});

describe("parse rejects malformed envelopes", () => {
  test("not JSON", () => {
    expect(() => parse("not json {")).toThrow(EnvelopeError);
  });
  test("missing from", () => {
    expect(() => parse(JSON.stringify({ to: "x", id: uuidv7(), re: null, body: 1 }))).toThrow(/from/);
  });
  test("empty to", () => {
    expect(() => parse(JSON.stringify({ from: "a", to: "", id: uuidv7(), re: null, body: 1 }))).toThrow(/to/);
  });
  test("empty to[] array", () => {
    expect(() => parse(JSON.stringify({ from: "a", to: [], id: uuidv7(), re: null, body: 1 }))).toThrow(/to/);
  });
  test("id not UUID", () => {
    expect(() => parse(JSON.stringify({ from: "a", to: "b", id: "not-uuid", re: null, body: 1 }))).toThrow(/id/);
  });
  test("re not UUID and not null", () => {
    expect(() => parse(JSON.stringify({ from: "a", to: "b", id: uuidv7(), re: "junk", body: 1 }))).toThrow(/re/);
  });
  test("missing body", () => {
    expect(() => parse(JSON.stringify({ from: "a", to: "b", id: uuidv7(), re: null }))).toThrow(/body/);
  });
});
