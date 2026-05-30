import { describe, expect, test } from "vitest";
import { ed25519Sign, generateEd25519Keypair } from "./crypto.js";
import {
  canonicalPairRequestV2,
  type PairRequestV2,
  verifyPairRequestV2Signature,
} from "./signed_pairing.js";

function makeSigned(overrides: Partial<PairRequestV2> = {}): PairRequestV2 {
  const owner = generateEd25519Keypair();
  const pi = generateEd25519Keypair();
  const ownerPk = Buffer.from(owner.publicKey).toString("base64");
  const base = {
    type: "pair_request_v2" as const,
    id: "id-1",
    token: "token-1",
    device_name: "phone",
    owner_pk: ownerPk,
    app_peer_pk: ownerPk,
    pi_pk: Buffer.from(pi.publicKey).toString("base64"),
    room_id: "room-1",
    pair_nonce: "nonce-1",
    expires_at: 1_700_000_000_000,
  };
  const req = { ...base, ...overrides };
  const sig = Buffer.from(ed25519Sign(owner.secretKey, Buffer.from(canonicalPairRequestV2(req), "utf8")))
    .toString("base64");
  return { ...req, sig, ...overrides };
}

describe("signed pairing", () => {
  test("canonicalPairRequestV2 is stable and excludes sig", () => {
    const req = makeSigned();
    const canonical = canonicalPairRequestV2(req);
    expect(canonical).toBe(
      '{"type":"pair_request_v2","id":"id-1","token":"token-1","device_name":"phone",' +
      `"owner_pk":"${req.owner_pk}","app_peer_pk":"${req.app_peer_pk}",` +
      `"pi_pk":"${req.pi_pk}","room_id":"room-1","pair_nonce":"nonce-1",` +
      '"expires_at":1700000000000}',
    );
    expect(canonical).not.toContain(req.sig);
  });

  test("valid signature verifies", () => {
    const req = makeSigned();
    expect(verifyPairRequestV2Signature(req, req.app_peer_pk)).toEqual({ ok: true });
  });

  test("tampering and relay-authenticated peer mismatch fail", () => {
    const req = makeSigned();
    expect(verifyPairRequestV2Signature({ ...req, token: "other" }, req.app_peer_pk)).toMatchObject({
      ok: false,
      code: "signature_invalid",
    });
    expect(verifyPairRequestV2Signature(req, Buffer.from(generateEd25519Keypair().publicKey).toString("base64")))
      .toMatchObject({ ok: false, code: "app_peer_mismatch" });
  });
});
