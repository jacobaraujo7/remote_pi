import { randomBytes } from "node:crypto";
import { ed25519Sign, ed25519Verify, type Ed25519Keypair } from "../pairing/crypto.js";

export interface SignedInnerV1 {
  type: "signed_inner_v1";
  sender_pk: string;
  recipient_pk: string;
  room_id: string;
  msg_id: string;
  issued_at: number;
  payload_type: string;
  payload: Record<string, unknown>;
  sig: string;
}

export type VerifySignedInnerResult =
  | { ok: true; payload: Record<string, unknown> }
  | { ok: false; code: string; message: string };

export class SignedInnerReplayCache {
  private readonly seen = new Map<string, number>();

  constructor(
    private readonly maxAgeMs = 5 * 60_000,
    private readonly maxEntries = 2048,
  ) {}

  accept(senderPk: string, roomId: string, msgId: string, issuedAt: number, now = Date.now()): boolean {
    this.prune(now);
    if (Math.abs(now - issuedAt) > this.maxAgeMs) return false;
    const key = `${senderPk}\u0000${roomId}\u0000${msgId}`;
    if (this.seen.has(key)) return false;
    this.seen.set(key, issuedAt);
    if (this.seen.size > this.maxEntries) {
      const first = this.seen.keys().next().value as string | undefined;
      if (first) this.seen.delete(first);
    }
    return true;
  }

  private prune(now: number): void {
    for (const [key, issuedAt] of this.seen) {
      if (Math.abs(now - issuedAt) > this.maxAgeMs) this.seen.delete(key);
    }
  }
}

function stableJson(value: unknown): string {
  if (value === null) return "null";
  const valueType = typeof value;
  if (valueType !== "object") {
    if (valueType === "undefined" || valueType === "function" || valueType === "symbol") return "null";
    return JSON.stringify(value) ?? "null";
  }
  if (Array.isArray(value)) {
    const items: string[] = [];
    for (let i = 0; i < value.length; i += 1) {
      const entry = Object.prototype.hasOwnProperty.call(value, i) ? value[i] : undefined;
      const entryType = typeof entry;
      items.push(
        entryType === "undefined" || entryType === "function" || entryType === "symbol"
          ? "null"
          : stableJson(entry),
      );
    }
    return `[${items.join(",")}]`;
  }
  const obj = value as Record<string, unknown>;
  return `{${Object.keys(obj).sort().flatMap((key) => {
    const entry = obj[key];
    const entryType = typeof entry;
    if (entryType === "undefined" || entryType === "function" || entryType === "symbol") return [];
    return [`${JSON.stringify(key)}:${stableJson(entry)}`];
  }).join(",")}}`;
}

export function canonicalSignedInnerV1(frame: Omit<SignedInnerV1, "sig">): string {
  return JSON.stringify({
    type: frame.type,
    sender_pk: frame.sender_pk,
    recipient_pk: frame.recipient_pk,
    room_id: frame.room_id,
    msg_id: frame.msg_id,
    issued_at: frame.issued_at,
    payload_type: frame.payload_type,
    payload: JSON.parse(stableJson(frame.payload)) as Record<string, unknown>,
  });
}

function decodeB64(value: string, expectedLength: number): Buffer | null {
  try {
    const bytes = Buffer.from(value, "base64");
    return bytes.length === expectedLength ? bytes : null;
  } catch {
    return null;
  }
}

export function signInnerV1(args: {
  payload: Record<string, unknown>;
  sender: Ed25519Keypair;
  recipientPk: string;
  roomId: string;
  now?: number;
  msgId?: string;
}): SignedInnerV1 {
  const senderPk = Buffer.from(args.sender.publicKey).toString("base64");
  const payloadType = String(args.payload["type"] ?? "");
  const unsigned: Omit<SignedInnerV1, "sig"> = {
    type: "signed_inner_v1",
    sender_pk: senderPk,
    recipient_pk: args.recipientPk,
    room_id: args.roomId,
    msg_id: args.msgId ?? randomBytes(16).toString("base64"),
    issued_at: args.now ?? Date.now(),
    payload_type: payloadType,
    payload: args.payload,
  };
  const sig = ed25519Sign(args.sender.secretKey, Buffer.from(canonicalSignedInnerV1(unsigned), "utf8"));
  return { ...unsigned, sig: Buffer.from(sig).toString("base64") };
}

export function verifyInnerV1(args: {
  frame: SignedInnerV1;
  expectedSenderPk: string;
  expectedRecipientPk: string;
  expectedRoomId: string;
  replay: SignedInnerReplayCache;
  now?: number;
}): VerifySignedInnerResult {
  const { frame } = args;
  if (frame.sender_pk !== args.expectedSenderPk) {
    return { ok: false, code: "wrong_sender", message: "Signed inner sender does not match paired peer." };
  }
  if (frame.recipient_pk !== args.expectedRecipientPk) {
    return { ok: false, code: "wrong_recipient", message: "Signed inner recipient does not match local peer." };
  }
  if (frame.room_id !== args.expectedRoomId) {
    return { ok: false, code: "wrong_room", message: "Signed inner room does not match active room." };
  }
  if (!frame.payload || typeof frame.payload !== "object" || Array.isArray(frame.payload)) {
    return { ok: false, code: "bad_payload", message: "Signed inner payload is invalid." };
  }
  if (frame.payload_type !== frame.payload["type"]) {
    return { ok: false, code: "payload_type_mismatch", message: "Signed inner payload type mismatch." };
  }
  const senderPk = decodeB64(frame.sender_pk, 32);
  const sig = decodeB64(frame.sig, 64);
  if (!senderPk || !sig) return { ok: false, code: "bad_signature", message: "Signed inner key or signature is invalid." };
  const { sig: _sig, ...unsigned } = frame;
  void _sig;
  if (!ed25519Verify(senderPk, Buffer.from(canonicalSignedInnerV1(unsigned), "utf8"), sig)) {
    return { ok: false, code: "signature_invalid", message: "Signed inner signature verification failed." };
  }
  if (!args.replay.accept(frame.sender_pk, frame.room_id, frame.msg_id, frame.issued_at, args.now)) {
    return { ok: false, code: "replay", message: "Signed inner message was replayed or is outside the freshness window." };
  }
  return { ok: true, payload: frame.payload };
}

export function isSignedInnerV1(value: unknown): value is SignedInnerV1 {
  return !!value && typeof value === "object" && (value as Record<string, unknown>).type === "signed_inner_v1";
}
