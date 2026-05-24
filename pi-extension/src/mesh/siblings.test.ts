import { describe, expect, test } from "vitest";
import { generateEd25519Keypair, ed25519Sign } from "../pairing/crypto.js";
import { canonicalBytes } from "./canonical.js";
import { discoverSelfLabel, discoverSiblings, fallbackLabel } from "./siblings.js";
import type { MeshClient } from "./client.js";
import type { MeshEnvelope } from "./types.js";

/**
 * Build a signed mesh envelope from a member list. `members[i]` carries an
 * optional `nickname` so tests can model the real-world case where some
 * Owners label Pis and others don't.
 */
function makeEnvelope(
  ownerKp: { publicKey: Uint8Array; secretKey: Uint8Array },
  version: number,
  members: { remote_epk: string; nickname?: string }[],
): MeshEnvelope {
  const blob = canonicalBytes({
    version,
    issued_at: Date.now(),
    owner_pk: Buffer.from(ownerKp.publicKey).toString("base64"),
    members: members.map((m, i) => ({
      remote_epk: m.remote_epk,
      relay_url: "wss://test",
      paired_at: `2026-05-22T0${i}:00:00Z`,
      ...(m.nickname ? { nickname: m.nickname } : {}),
    })),
  });
  return { blob, sig: ed25519Sign(ownerKp.secretKey, blob) };
}

/**
 * `discoverSiblings` must keep label resolution symmetric across Pis even
 * when only SOME Owners label the members (real-world scenario from the
 * plan/25 Wave D production drop: Owner-A labeled "MacBook"/"MacMini",
 * Owner-B never set nicknames; PC-A self-labeled "MacBook" via Owner-A but
 * PC-B labeled PC-A as fallback "Bz02uLiw" because Owner-B came first in
 * the dedup map).
 */
describe("discoverSiblings — nickname always beats fallback (plan/25 Wave D fix)", () => {
  test("unlabeled owner first, labeled owner second → nickname wins", async () => {
    const ownerA = generateEd25519Keypair();
    const ownerB = generateEd25519Keypair();
    const me = generateEd25519Keypair();
    const sibling = generateEd25519Keypair();

    const meEpk = Buffer.from(me.publicKey).toString("base64");
    const sibEpk = Buffer.from(sibling.publicKey).toString("base64");
    const ownerAEpk = Buffer.from(ownerA.publicKey).toString("base64");
    const ownerBEpk = Buffer.from(ownerB.publicKey).toString("base64");

    // OwnerA: no nicknames (mirrors the production drop)
    // OwnerB: nicknames set
    const envA = makeEnvelope(ownerA, 1, [
      { remote_epk: meEpk },
      { remote_epk: sibEpk },
    ]);
    const envB = makeEnvelope(ownerB, 1, [
      { remote_epk: meEpk, nickname: "MacBook" },
      { remote_epk: sibEpk, nickname: "MacMini" },
    ]);

    const client = {
      get: async (hash: string) => {
        // Both blobs are served — the function discriminates by hash but
        // we just key on the order the caller asks: unlabeled first.
        if (hash === sha256Hex(ownerA.publicKey)) return envA;
        if (hash === sha256Hex(ownerB.publicKey)) return envB;
        return null;
      },
    } as unknown as MeshClient;

    const siblings = await discoverSiblings({
      client,
      ownerEpks: [ownerAEpk, ownerBEpk],  // unlabeled FIRST
      myPubkey: me.publicKey,
    });

    expect(siblings).toEqual([
      { pcPubkey: sibEpk, pcLabel: "MacMini" },
    ]);
  });

  test("labeled owner first, unlabeled owner second → nickname still wins", async () => {
    const ownerA = generateEd25519Keypair();
    const ownerB = generateEd25519Keypair();
    const me = generateEd25519Keypair();
    const sibling = generateEd25519Keypair();

    const meEpk = Buffer.from(me.publicKey).toString("base64");
    const sibEpk = Buffer.from(sibling.publicKey).toString("base64");
    const ownerAEpk = Buffer.from(ownerA.publicKey).toString("base64");
    const ownerBEpk = Buffer.from(ownerB.publicKey).toString("base64");

    const envA = makeEnvelope(ownerA, 1, [
      { remote_epk: meEpk, nickname: "MacBook" },
      { remote_epk: sibEpk, nickname: "MacMini" },
    ]);
    const envB = makeEnvelope(ownerB, 1, [
      { remote_epk: meEpk },
      { remote_epk: sibEpk },
    ]);

    const client = {
      get: async (hash: string) => {
        if (hash === sha256Hex(ownerA.publicKey)) return envA;
        if (hash === sha256Hex(ownerB.publicKey)) return envB;
        return null;
      },
    } as unknown as MeshClient;

    const siblings = await discoverSiblings({
      client,
      ownerEpks: [ownerAEpk, ownerBEpk],  // labeled FIRST
      myPubkey: me.publicKey,
    });

    expect(siblings).toEqual([
      { pcPubkey: sibEpk, pcLabel: "MacMini" },
    ]);
  });

  test("two owners with different nicknames for same pubkey → first-nickname wins (deterministic)", async () => {
    const ownerA = generateEd25519Keypair();
    const ownerB = generateEd25519Keypair();
    const me = generateEd25519Keypair();
    const sibling = generateEd25519Keypair();

    const sibEpk = Buffer.from(sibling.publicKey).toString("base64");
    const ownerAEpk = Buffer.from(ownerA.publicKey).toString("base64");
    const ownerBEpk = Buffer.from(ownerB.publicKey).toString("base64");

    const envA = makeEnvelope(ownerA, 1, [{ remote_epk: sibEpk, nickname: "Casa" }]);
    const envB = makeEnvelope(ownerB, 1, [{ remote_epk: sibEpk, nickname: "Home" }]);

    const client = {
      get: async (hash: string) => {
        if (hash === sha256Hex(ownerA.publicKey)) return envA;
        if (hash === sha256Hex(ownerB.publicKey)) return envB;
        return null;
      },
    } as unknown as MeshClient;

    const siblings = await discoverSiblings({
      client,
      ownerEpks: [ownerAEpk, ownerBEpk],
      myPubkey: me.publicKey,
    });

    expect(siblings).toEqual([{ pcPubkey: sibEpk, pcLabel: "Casa" }]);
  });

  test("zero owners label → fallback applied", async () => {
    const ownerA = generateEd25519Keypair();
    const me = generateEd25519Keypair();
    const sibling = generateEd25519Keypair();

    const sibEpk = Buffer.from(sibling.publicKey).toString("base64");
    const ownerAEpk = Buffer.from(ownerA.publicKey).toString("base64");

    const envA = makeEnvelope(ownerA, 1, [
      { remote_epk: Buffer.from(me.publicKey).toString("base64") },
      { remote_epk: sibEpk },
    ]);

    const client = {
      get: async () => envA,
    } as unknown as MeshClient;

    const siblings = await discoverSiblings({
      client,
      ownerEpks: [ownerAEpk],
      myPubkey: me.publicKey,
    });

    expect(siblings).toEqual([
      { pcPubkey: sibEpk, pcLabel: fallbackLabel(sibEpk) },
    ]);
  });

  test("self excluded even when present under multiple owners", async () => {
    const ownerA = generateEd25519Keypair();
    const me = generateEd25519Keypair();
    const meEpk = Buffer.from(me.publicKey).toString("base64");
    const ownerAEpk = Buffer.from(ownerA.publicKey).toString("base64");

    const envA = makeEnvelope(ownerA, 1, [
      { remote_epk: meEpk, nickname: "MeMyself" },
    ]);

    const client = {
      get: async () => envA,
    } as unknown as MeshClient;

    const siblings = await discoverSiblings({
      client,
      ownerEpks: [ownerAEpk],
      myPubkey: me.publicKey,
    });

    expect(siblings).toEqual([]);
  });
});

describe("discoverSelfLabel — symmetry with discoverSiblings", () => {
  test("labeled in any owner → returns nickname (matches siblings rule on the receiving side)", async () => {
    const ownerA = generateEd25519Keypair();
    const ownerB = generateEd25519Keypair();
    const me = generateEd25519Keypair();
    const meEpk = Buffer.from(me.publicKey).toString("base64");

    const envA = makeEnvelope(ownerA, 1, [{ remote_epk: meEpk }]);  // no nickname
    const envB = makeEnvelope(ownerB, 1, [{ remote_epk: meEpk, nickname: "MacBook" }]);

    const client = {
      get: async (hash: string) => {
        if (hash === sha256Hex(ownerA.publicKey)) return envA;
        if (hash === sha256Hex(ownerB.publicKey)) return envB;
        return null;
      },
    } as unknown as MeshClient;

    const { selfPcLabel } = await discoverSelfLabel({
      client,
      ownerEpks: [
        Buffer.from(ownerA.publicKey).toString("base64"),
        Buffer.from(ownerB.publicKey).toString("base64"),
      ],
      myPubkey: me.publicKey,
    });

    expect(selfPcLabel).toBe("MacBook");
  });
});

// helper — sha256 hex of bytes
function sha256Hex(bytes: Uint8Array): string {
  // Lazy require to keep top of file clean.
  const { createHash } = require("node:crypto") as typeof import("node:crypto");
  return createHash("sha256").update(bytes).digest("hex");
}
