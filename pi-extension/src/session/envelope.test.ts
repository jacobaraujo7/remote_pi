import { describe, expect, test } from "vitest";
import {
  asTransportErrorBody,
  envelope,
  EnvelopeError,
  hasTransportErrorType,
  isUuid,
  parse,
  serialize,
  TRANSPORT_ERROR_REASONS,
  type TransportErrorBody,
  type TransportErrorReason,
  uuidv7,
} from "./envelope.js";

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

describe("shared UUID and transport-error grammar", () => {
  const CLOSED_REASONS = [
    "offline",
    "not_authorized",
    "bad_envelope",
  ] as const;

  test("accepts canonical hyphenated UUIDs without tightening the parser to v7", () => {
    expect(isUuid("550e8400-e29b-41d4-a716-446655440000")).toBe(true);
    expect(isUuid("01976000-0000-7000-8000-000000000000")).toBe(true);
    expect(isUuid("01976000000070008000000000000000")).toBe(false);
    expect(isUuid("not-a-uuid")).toBe(false);
    expect(isUuid(null)).toBe(false);
  });


  test.each(CLOSED_REASONS)(
    "normalizes the privileged %s body to its two protocol fields",
    (reason) => {
      const expected: TransportErrorBody = { type: "transport_error", reason };
      expect(asTransportErrorBody({
        type: "transport_error",
        reason,
        ignored: "must-not-cross-the-boundary",
      })).toEqual(expected);
    },
  );

  test.each([
    null,
    [],
    {},
    { type: "TRANSPORT_ERROR", reason: "offline" },
    { type: "transport_error" },
    { type: "transport_error", reason: "unknown" },
    { type: "transport_error", reason: ["offline", "bad_envelope"] },
    { type: "transport_error", reason: "offline,bad_envelope" },
  ])("rejects malformed or non-closed transport-error body %#", (value) => {
    expect(asTransportErrorBody(value)).toBeNull();
  });

  test("reserves any raw object with the exact transport_error type", () => {
    expect(hasTransportErrorType({ type: "transport_error", reason: "unknown" })).toBe(true);
    expect(hasTransportErrorType({ type: "transport_error" })).toBe(true);
    expect(hasTransportErrorType({ type: "TRANSPORT_ERROR", reason: "offline" })).toBe(false);
    expect(hasTransportErrorType("transport_error")).toBe(false);
    expect(hasTransportErrorType(null)).toBe(false);
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
  test("legacy 32-hex Relay id and correlation", () => {
    const legacyId = "01976000000070008000000000000000";
    expect(() => parse(JSON.stringify({ from: "a", to: "b", id: legacyId, re: null, body: 1 }))).toThrow(/id/);
    expect(() => parse(JSON.stringify({ from: "a", to: "b", id: uuidv7(), re: legacyId, body: 1 }))).toThrow(/re/);
  });
  test("keeps an opaque reserved body and null correlation parse-compatible", () => {
    const body = { type: "transport_error", reason: "future_reason", detail: { opaque: true } };
    expect(parse(JSON.stringify({ from: "a", to: "b", id: uuidv7(), re: null, body }))).toMatchObject({
      re: null,
      body,
    });
  });
  test("missing body", () => {
    expect(() => parse(JSON.stringify({ from: "a", to: "b", id: uuidv7(), re: null }))).toThrow(/body/);
  });
});
