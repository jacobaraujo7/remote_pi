import { ed25519Verify } from "../pairing/crypto.js";
import {
  canonicalizeEd25519PublicKey,
  decodeEd25519PublicKey,
} from "./encoding.js";
import type { MeshEnvelope, MeshHeader, MeshMember } from "./types.js";

interface RawMeshMember {
  readonly remoteEpk: string;
  readonly relayUrl: string;
  readonly pairedAt: string;
  readonly nickname?: string;
}

/**
 * Verifies the Ed25519 signature on a mesh envelope and decodes the blob
 * into a typed `MeshHeader`.
 *
 * The verification key is extracted *from the blob* (`owner_pk` field) —
 * the caller MUST then check that `sha256(header.ownerPk)` matches the
 * URL hash they queried with. Otherwise a malicious relay could serve a
 * valid-but-different-owner blob at our hash slot.
 *
 * Throws on:
 *   - JSON parse failure
 *   - Missing or wrong-type required fields
 *   - `owner_pk` not 32 bytes
 *   - Signature mismatch
 */
export async function verifyEnvelope(env: MeshEnvelope): Promise<MeshHeader> {
  let parsed: unknown;
  try {
    parsed = JSON.parse(new TextDecoder().decode(env.blob));
  } catch {
    throw new Error("mesh: blob is not valid JSON");
  }
  if (!parsed || typeof parsed !== "object") {
    throw new Error("mesh: blob is not a JSON object");
  }
  const o = parsed as Record<string, unknown>;

  if (typeof o["owner_pk"] !== "string") {
    throw new Error("mesh: owner_pk missing or not a string");
  }
  if (typeof o["version"] !== "number" || !Number.isInteger(o["version"])) {
    throw new Error("mesh: version missing or not an integer");
  }
  if (typeof o["issued_at"] !== "number" || !Number.isInteger(o["issued_at"])) {
    throw new Error("mesh: issued_at missing or not an integer");
  }
  if (!Array.isArray(o["members"])) {
    throw new Error("mesh: members missing or not an array");
  }

  const rawMembers: RawMeshMember[] = (o["members"] as unknown[]).map(
    (raw, index) => {
      if (!raw || typeof raw !== "object") {
        throw new Error(`mesh: members[${index}] is not an object`);
      }
      const member = raw as Record<string, unknown>;
      if (typeof member["remote_epk"] !== "string") {
        throw new Error(`mesh: members[${index}].remote_epk invalid`);
      }
      if (typeof member["relay_url"] !== "string") {
        throw new Error(`mesh: members[${index}].relay_url invalid`);
      }
      if (typeof member["paired_at"] !== "string") {
        throw new Error(`mesh: members[${index}].paired_at invalid`);
      }
      const nickname = member["nickname"];
      if (
        nickname !== undefined &&
        nickname !== null &&
        typeof nickname !== "string"
      ) {
        throw new Error(`mesh: members[${index}].nickname invalid`);
      }
      return {
        remoteEpk: member["remote_epk"],
        relayUrl: member["relay_url"],
        pairedAt: member["paired_at"],
        ...(typeof nickname === "string" ? { nickname } : {}),
      };
    },
  );

  const ownerPk = decodeEd25519PublicKey(o["owner_pk"], "owner_pk");
  if (!ed25519Verify(ownerPk, env.blob, env.sig)) {
    throw new Error("mesh: signature verification failed");
  }

  const members: MeshMember[] = rawMembers.map((member, index) => ({
    remoteEpk: canonicalizeEd25519PublicKey(
      member.remoteEpk,
      `members[${index}].remote_epk`,
    ),
    relayUrl: member.relayUrl,
    pairedAt: member.pairedAt,
    ...(member.nickname !== undefined ? { nickname: member.nickname } : {}),
  }));

  return {
    version: o["version"] as number,
    issuedAt: o["issued_at"] as number,
    ownerPk,
    members,
  };
}
