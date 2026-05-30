import { EventEmitter } from "node:events";
import { describe, expect, test, vi } from "vitest";
import { generateEd25519Keypair } from "../pairing/crypto.js";
import { signInnerV1 } from "../protocol/signed_inner.js";
import { PlainPeerChannel } from "./peer_channel.js";

class MockRelay extends EventEmitter {
  send = vi.fn();
}

function outerLine(peer: string, inner: unknown): string {
  return JSON.stringify({
    peer,
    ct: Buffer.from(JSON.stringify(inner)).toString("base64"),
  });
}

describe("PlainPeerChannel signed_inner_v1", () => {
  test("wraps outbound ServerMessage when negotiated", () => {
    const relay = new MockRelay();
    const pi = generateEd25519Keypair();
    const app = generateEd25519Keypair();
    const appPk = Buffer.from(app.publicKey).toString("base64");
    const channel = new PlainPeerChannel(
      relay as never,
      appPk,
      "room-1",
      () => undefined,
      undefined,
      {
        localKeypair: pi,
        expectedRemotePubkey: appPk,
        roomId: "room-1",
        requireSigned: true,
      },
    );

    channel.send({ type: "pong", in_reply_to: "p1" });

    const raw = relay.send.mock.calls[0]![0] as string;
    const outer = JSON.parse(raw) as { peer: string; ct: string };
    expect(outer.peer).toBe(appPk);
    const inner = JSON.parse(Buffer.from(outer.ct, "base64").toString("utf8")) as Record<string, unknown>;
    expect(inner["type"]).toBe("signed_inner_v1");
    expect(inner["sender_pk"]).toBe(Buffer.from(pi.publicKey).toString("base64"));
    expect(inner["recipient_pk"]).toBe(appPk);
    expect(inner["room_id"]).toBe("room-1");
    expect(inner["payload_type"]).toBe("pong");
    expect(inner["payload"]).toEqual({ type: "pong", in_reply_to: "p1" });
  });

  test("drops malformed relay frames without throwing", () => {
    const relay = new MockRelay();
    const app = generateEd25519Keypair();
    const appPk = Buffer.from(app.publicKey).toString("base64");
    const messages: unknown[] = [];
    new PlainPeerChannel(
      relay as never,
      appPk,
      "room-1",
      (msg) => messages.push(msg),
    );

    expect(() => relay.emit("message", "not-json")).not.toThrow();
    expect(() => relay.emit("message", JSON.stringify({ peer: appPk }))).not.toThrow();
    expect(() => relay.emit("message", JSON.stringify({ peer: appPk, ct: Buffer.from("not-json").toString("base64") }))).not.toThrow();
    expect(() => relay.emit("message", outerLine(appPk, { id: "no-type" }))).not.toThrow();
    expect(messages).toEqual([]);
  });

  test("unwraps signed inbound and drops unsigned/replayed frames in strict mode", () => {
    const relay = new MockRelay();
    const pi = generateEd25519Keypair();
    const app = generateEd25519Keypair();
    const appPk = Buffer.from(app.publicKey).toString("base64");
    const piPk = Buffer.from(pi.publicKey).toString("base64");
    const messages: unknown[] = [];
    new PlainPeerChannel(
      relay as never,
      appPk,
      "room-1",
      (msg) => messages.push(msg),
      undefined,
      {
        localKeypair: pi,
        expectedRemotePubkey: appPk,
        roomId: "room-1",
        requireSigned: true,
      },
    );

    relay.emit("message", outerLine(appPk, { type: "ping", id: "unsigned" }));
    expect(messages).toEqual([]);

    relay.emit("message", outerLine(appPk, { type: "signed_inner_v1", payload: null }));
    expect(messages).toEqual([]);

    const signed = signInnerV1({
      payload: { type: "ping", id: "p1" },
      sender: app,
      recipientPk: piPk,
      roomId: "room-1",
      now: Date.now(),
      msgId: "msg-1",
    });
    relay.emit("message", outerLine(appPk, signed));
    expect(messages).toEqual([{ type: "ping", id: "p1" }]);

    relay.emit("message", outerLine(appPk, signed));
    expect(messages).toHaveLength(1);
  });
});
