import { randomBytes } from "node:crypto";

/**
 * 5-field envelope for the agent-network local protocol (plano 19).
 * Serialized as JSONL (one JSON object per line) over UDS streams.
 */
export interface Envelope {
  from: string;
  to: string | string[];        // single name, list of names, or "broadcast"
  id: string;                   // UUID v7
  re: string | null;            // id of the message this replies to, or null
  body: unknown;
}

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export const TRANSPORT_ERROR_REASONS = [
  "offline",
  "not_authorized",
  "bad_envelope",
] as const;

export type TransportErrorReason = typeof TRANSPORT_ERROR_REASONS[number];

export interface TransportErrorBody {
  type: "transport_error";
  reason: TransportErrorReason;
}

export function isUuid(value: unknown): value is string {
  return typeof value === "string" && UUID_RE.test(value);
}

export function hasTransportErrorType(value: unknown): boolean {
  return (
    value !== null &&
    typeof value === "object" &&
    !Array.isArray(value) &&
    Object.hasOwn(value, "type") &&
    (value as Record<string, unknown>)["type"] === "transport_error"
  );
}

export function asTransportErrorBody(
  value: unknown,
): TransportErrorBody | null {
  if (
    !hasTransportErrorType(value) ||
    !Object.hasOwn(value as object, "reason")
  ) {
    return null;
  }
  const reason = (value as Record<string, unknown>)["reason"];
  if (
    reason !== "offline" &&
    reason !== "not_authorized" &&
    reason !== "bad_envelope"
  ) {
    return null;
  }
  return { type: "transport_error", reason };
}

/**
 * Generates a UUID v7 — time-ordered, monotonically increasing within the
 * same millisecond. Format:
 *   <48-bit ts ms><4-bit ver=7><12-bit rand><2-bit var=10><62-bit rand>
 */
export function uuidv7(): string {
  const ts = Date.now();
  const rand = randomBytes(10);
  // Encode 48-bit timestamp into bytes 0-5.
  const buf = Buffer.alloc(16);
  buf[0] = (ts / 2 ** 40) & 0xff;
  buf[1] = (ts / 2 ** 32) & 0xff;
  buf[2] = (ts / 2 ** 24) & 0xff;
  buf[3] = (ts / 2 ** 16) & 0xff;
  buf[4] = (ts / 2 ** 8) & 0xff;
  buf[5] = ts & 0xff;
  rand.copy(buf, 6);
  // Set version (7) in upper nibble of byte 6.
  buf[6] = (buf[6]! & 0x0f) | 0x70;
  // Set variant (10) in upper two bits of byte 8.
  buf[8] = (buf[8]! & 0x3f) | 0x80;
  const hex = buf.toString("hex");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

export class EnvelopeError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "EnvelopeError";
  }
}

export function serialize(env: Envelope): string {
  return JSON.stringify(env) + "\n";
}

export function parse(line: string): Envelope {
  let raw: unknown;
  try {
    raw = JSON.parse(line);
  } catch (e) {
    throw new EnvelopeError(`not JSON: ${(e as Error).message}`);
  }
  if (!raw || typeof raw !== "object") {
    throw new EnvelopeError("not an object");
  }
  const o = raw as Record<string, unknown>;
  if (typeof o["from"] !== "string" || (o["from"] as string).length === 0) {
    throw new EnvelopeError("from must be non-empty string");
  }
  const to = o["to"];
  if (typeof to !== "string" && !Array.isArray(to)) {
    throw new EnvelopeError("to must be string or array");
  }
  if (typeof to === "string" && to.length === 0) {
    throw new EnvelopeError("to must be non-empty");
  }
  if (Array.isArray(to)) {
    if (to.length === 0) throw new EnvelopeError("to[] must not be empty");
    for (const t of to) {
      if (typeof t !== "string" || t.length === 0) {
        throw new EnvelopeError("to[] entries must be non-empty strings");
      }
    }
  }
  if (!isUuid(o["id"])) {
    throw new EnvelopeError("id must be UUID");
  }
  const re = o["re"];
  if (re !== null && !isUuid(re)) {
    throw new EnvelopeError("re must be null or UUID");
  }
  if (!("body" in o)) {
    throw new EnvelopeError("body required");
  }
  return {
    from: o["from"] as string,
    to: to as string | string[],
    id: o["id"] as string,
    re: re as string | null,
    body: o["body"],
  };
}

/** Convenience: builds an envelope with id auto-generated. */
export function envelope(
  from: string,
  to: string | string[],
  body: unknown,
  re: string | null = null,
): Envelope {
  return { from, to, id: uuidv7(), re, body };
}
