import { describe, expect, test } from "vitest";
import { generateEd25519Keypair } from "../pairing/crypto.js";
import {
  SignedInnerReplayCache,
  canonicalSignedInnerV1,
  signInnerV1,
  verifyInnerV1,
} from "./signed_inner.js";

describe("signed_inner_v1", () => {
  test("signs and verifies a payload", () => {
    const sender = generateEd25519Keypair();
    const recipient = generateEd25519Keypair();
    const recipientPk = Buffer.from(recipient.publicKey).toString("base64");
    const frame = signInnerV1({
      sender,
      recipientPk,
      roomId: "room-1",
      now: 1_700_000_000_000,
      msgId: "msg-1",
      payload: { type: "user_message", id: "u1", text: "hello" },
    });

    expect(verifyInnerV1({
      frame,
      expectedSenderPk: frame.sender_pk,
      expectedRecipientPk: recipientPk,
      expectedRoomId: "room-1",
      replay: new SignedInnerReplayCache(),
      now: 1_700_000_000_100,
    })).toMatchObject({ ok: true, payload: { type: "user_message", id: "u1", text: "hello" } });
  });

  test("cross-runtime vector stays stable", () => {
    const senderPk = "ebVWLo/mVPlAeLES6KmLp5AfhTrmlb7X4OORC60ElmQ=";
    const recipientPk = "ZWZnaGlqa2xtbm9wcXJzdHV2d3h5ent8fX5/gIGCg4Q=";
    const unsigned = {
      type: "signed_inner_v1" as const,
      sender_pk: senderPk,
      recipient_pk: recipientPk,
      room_id: "room-vector",
      msg_id: "msg-vector",
      issued_at: 1700000000123,
      payload_type: "user_message",
      payload: { type: "user_message", id: "u-vector", text: "hello", nested: { b: 2, a: 1 } },
    };
    expect(canonicalSignedInnerV1(unsigned)).toBe(
      '{"type":"signed_inner_v1","sender_pk":"ebVWLo/mVPlAeLES6KmLp5AfhTrmlb7X4OORC60ElmQ=",' +
      '"recipient_pk":"ZWZnaGlqa2xtbm9wcXJzdHV2d3h5ent8fX5/gIGCg4Q=","room_id":"room-vector",' +
      '"msg_id":"msg-vector","issued_at":1700000000123,"payload_type":"user_message",' +
      '"payload":{"id":"u-vector","nested":{"a":1,"b":2},"text":"hello","type":"user_message"}}',
    );
    expect(verifyInnerV1({
      frame: { ...unsigned, sig: "GxWRHj92N2l5IW1ApzmyE+5cfeWJAoLRoaqRhC5M40aV1rW13GYQ4pLI0ZMcIvbgOsfQwvwpMyQ4F/A972LxCA==" },
      expectedSenderPk: senderPk,
      expectedRecipientPk: recipientPk,
      expectedRoomId: "room-vector",
      replay: new SignedInnerReplayCache(),
      now: 1700000000200,
    })).toMatchObject({ ok: true, payload: { type: "user_message", id: "u-vector" } });
  });

  test("canonical payload is deterministic and excludes sig", () => {
    const unsigned = {
      type: "signed_inner_v1" as const,
      sender_pk: "sender",
      recipient_pk: "recipient",
      room_id: "room-1",
      msg_id: "msg-1",
      issued_at: 1,
      payload_type: "tool_request",
      payload: { z: 1, type: "tool_request", args: { b: true, a: false } },
    };
    expect(canonicalSignedInnerV1(unsigned)).toBe(
      '{"type":"signed_inner_v1","sender_pk":"sender","recipient_pk":"recipient",' +
      '"room_id":"room-1","msg_id":"msg-1","issued_at":1,"payload_type":"tool_request",' +
      '"payload":{"args":{"a":false,"b":true},"type":"tool_request","z":1}}',
    );
  });

  test("rejects tamper, wrong recipient, wrong room, replay, and stale timestamp", () => {
    const sender = generateEd25519Keypair();
    const recipient = generateEd25519Keypair();
    const other = generateEd25519Keypair();
    const recipientPk = Buffer.from(recipient.publicKey).toString("base64");
    const otherPk = Buffer.from(other.publicKey).toString("base64");
    const frame = signInnerV1({
      sender,
      recipientPk,
      roomId: "room-1",
      now: 1_700_000_000_000,
      msgId: "msg-1",
      payload: { type: "ping", id: "p1" },
    });

    const replay = new SignedInnerReplayCache();
    expect(verifyInnerV1({ frame: { ...frame, payload: { type: "ping", id: "p2" } }, expectedSenderPk: frame.sender_pk, expectedRecipientPk: recipientPk, expectedRoomId: "room-1", replay, now: 1_700_000_000_000 }))
      .toMatchObject({ ok: false, code: "signature_invalid" });
    expect(verifyInnerV1({ frame, expectedSenderPk: frame.sender_pk, expectedRecipientPk: otherPk, expectedRoomId: "room-1", replay, now: 1_700_000_000_000 }))
      .toMatchObject({ ok: false, code: "wrong_recipient" });
    expect(verifyInnerV1({ frame, expectedSenderPk: frame.sender_pk, expectedRecipientPk: recipientPk, expectedRoomId: "room-2", replay, now: 1_700_000_000_000 }))
      .toMatchObject({ ok: false, code: "wrong_room" });
    expect(verifyInnerV1({ frame, expectedSenderPk: frame.sender_pk, expectedRecipientPk: recipientPk, expectedRoomId: "room-1", replay, now: 1_700_000_000_000 }))
      .toMatchObject({ ok: true });
    expect(verifyInnerV1({ frame, expectedSenderPk: frame.sender_pk, expectedRecipientPk: recipientPk, expectedRoomId: "room-1", replay, now: 1_700_000_000_000 }))
      .toMatchObject({ ok: false, code: "replay" });
    expect(verifyInnerV1({ frame, expectedSenderPk: frame.sender_pk, expectedRecipientPk: recipientPk, expectedRoomId: "room-1", replay: new SignedInnerReplayCache(), now: 1_700_001_000_000 }))
      .toMatchObject({ ok: false, code: "replay" });
  });
});
