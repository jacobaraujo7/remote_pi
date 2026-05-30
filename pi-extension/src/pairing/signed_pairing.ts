import { ed25519Verify } from "./crypto.js";

export interface PairRequestV2 {
  type: "pair_request_v2";
  id: string;
  token: string;
  device_name: string;
  owner_pk: string;
  app_peer_pk: string;
  pi_pk: string;
  room_id: string;
  pair_nonce: string;
  expires_at: number;
  sig: string;
}

export type PairRequestV2Validation =
  | { ok: true }
  | { ok: false; code: string; message: string };

export function canonicalPairRequestV2(req: Omit<PairRequestV2, "sig">): string {
  return JSON.stringify({
    type: req.type,
    id: req.id,
    token: req.token,
    device_name: req.device_name,
    owner_pk: req.owner_pk,
    app_peer_pk: req.app_peer_pk,
    pi_pk: req.pi_pk,
    room_id: req.room_id,
    pair_nonce: req.pair_nonce,
    expires_at: req.expires_at,
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

export function verifyPairRequestV2Signature(
  req: PairRequestV2,
  authenticatedAppPeerPk: string,
): PairRequestV2Validation {
  if (req.app_peer_pk !== authenticatedAppPeerPk) {
    return {
      ok: false,
      code: "app_peer_mismatch",
      message: "Pair request app peer does not match relay-authenticated peer.",
    };
  }

  const ownerPk = decodeB64(req.owner_pk, 32);
  if (!ownerPk) {
    return { ok: false, code: "bad_owner_pk", message: "Owner public key is invalid." };
  }
  if (!decodeB64(req.app_peer_pk, 32)) {
    return { ok: false, code: "bad_app_peer_pk", message: "App peer public key is invalid." };
  }
  if (!decodeB64(req.pi_pk, 32)) {
    return { ok: false, code: "bad_pi_pk", message: "Pi public key is invalid." };
  }
  const sig = decodeB64(req.sig, 64);
  if (!sig) {
    return { ok: false, code: "bad_signature", message: "Pair request signature is invalid." };
  }

  const canonical = canonicalPairRequestV2({
    type: req.type,
    id: req.id,
    token: req.token,
    device_name: req.device_name,
    owner_pk: req.owner_pk,
    app_peer_pk: req.app_peer_pk,
    pi_pk: req.pi_pk,
    room_id: req.room_id,
    pair_nonce: req.pair_nonce,
    expires_at: req.expires_at,
  });
  const ok = ed25519Verify(ownerPk, Buffer.from(canonical, "utf8"), sig);
  return ok
    ? { ok: true }
    : { ok: false, code: "signature_invalid", message: "Pair request signature verification failed." };
}
