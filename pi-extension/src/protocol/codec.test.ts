import { readdirSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, test } from "vitest";
import { DecodeError, decodeServer, encodeClient } from "./codec.js";

const fixtureDir = fileURLToPath(
  new URL("../../../.orchestration/contracts/fixtures", import.meta.url),
);

const SERVER_TYPE_FILES = new Set([
  "pair_ok.jsonl",
  "pair_error.jsonl",
  "user_input.jsonl",
  "agent_stream.jsonl",
  "agent_message.jsonl",
  "tool_request.jsonl",
  "tool_result.jsonl",
  "error.jsonl",
  "cancelled.jsonl",
  "pong.jsonl",
  "bye.jsonl",
  "session_history.jsonl",
  "ask_user_prompt.jsonl",
  "ask_user_resolved.jsonl",
]);

// ask_user_response is a client-only fixture

describe("fixtures", () => {
  const files = readdirSync(fixtureDir).filter((f) => f.endsWith(".jsonl"));

  test("34 fixture files present", () => {
    expect(files).toHaveLength(34);
  });

  for (const file of files) {
    test(file, () => {
      const lines = readFileSync(`${fixtureDir}/${file}`, "utf8")
        .split("\n")
        .filter(Boolean);

      for (const line of lines) {
        if (SERVER_TYPE_FILES.has(file)) {
          const msg = decodeServer(line);
          expect(msg).toHaveProperty("type");
        } else {
          // client-only fixture — must throw unsupported_type, not invalid_message
          let caught: unknown;
          try {
            decodeServer(line);
          } catch (e) {
            caught = e;
          }
          expect(caught).toBeInstanceOf(DecodeError);
          expect((caught as DecodeError).code).toBe("unsupported_type");
        }
      }
    });
  }
});

describe("rejects junk", () => {
  test("invalid JSON → DecodeError invalid_message", () => {
    let err: unknown;
    try {
      decodeServer("not json {{{");
    } catch (e) {
      err = e;
    }
    expect(err).toBeInstanceOf(DecodeError);
    expect((err as DecodeError).code).toBe("invalid_message");
  });

  test("missing type field → DecodeError invalid_message", () => {
    let err: unknown;
    try {
      decodeServer('{"foo":1}');
    } catch (e) {
      err = e;
    }
    expect(err).toBeInstanceOf(DecodeError);
    expect((err as DecodeError).code).toBe("invalid_message");
    expect((err as DecodeError).message).toMatch(/missing 'type'/);
  });

  test("unknown type → DecodeError unsupported_type", () => {
    let err: unknown;
    try {
      decodeServer('{"type":"made_up"}');
    } catch (e) {
      err = e;
    }
    expect(err).toBeInstanceOf(DecodeError);
    expect((err as DecodeError).code).toBe("unsupported_type");
    expect((err as DecodeError).message).toMatch(/unknown type/);
  });
});

describe("encodeClient roundtrip", () => {
  test("ping", () => {
    const msg = { type: "ping" as const, id: "018f9c2a" };
    const encoded = encodeClient(msg);
    expect(encoded.endsWith("\n")).toBe(true);
    expect(JSON.parse(encoded.trim())).toEqual(msg);
  });

  test("user_message", () => {
    const msg = { type: "user_message" as const, id: "018f9c2a", text: "hello" };
    expect(JSON.parse(encodeClient(msg).trim())).toEqual(msg);
  });

  test("user_message with steer streaming behavior", () => {
    const msg = {
      type: "user_message" as const,
      id: "018f9c2a",
      text: "refine this",
      streaming_behavior: "steer" as const,
    };
    expect(JSON.parse(encodeClient(msg).trim())).toEqual(msg);
  });
});
