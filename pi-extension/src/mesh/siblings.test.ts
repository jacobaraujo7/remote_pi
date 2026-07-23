import { createHash } from "node:crypto";
import { describe, expect, test, vi } from "vitest";
import {
  ed25519Sign,
  generateEd25519Keypair,
  type Ed25519Keypair,
} from "../pairing/crypto.js";
import { canonicalBytes } from "./canonical.js";
import type { MeshClient } from "./client.js";
import {
  buildTopologySnapshot,
  discoverSelfLabel,
  discoverSiblings,
  discoverTopology,
  fallbackLabel,
  type BoundOwnerMembership,
} from "./siblings.js";
import type { MeshEnvelope } from "./types.js";

interface TestMember {
  readonly remoteEpk: string;
  readonly nickname?: string;
}

function standardKey(keypair: Ed25519Keypair): string {
  return Buffer.from(keypair.publicKey).toString("base64");
}

function urlSafeKey(keypair: Ed25519Keypair): string {
  return Buffer.from(keypair.publicKey).toString("base64url");
}

function sha256Hex(bytes: Uint8Array): string {
  return createHash("sha256").update(bytes).digest("hex");
}

function rawFingerprint(raw: string): string {
  return createHash("sha256").update(raw, "utf8").digest("hex").slice(0, 8);
}

// Fixed 32-byte key: standard Base64 starts `+///AAAA`, while Base64url
// starts `-___AAAA`. This keeps legacy-prefix coverage deterministic.
const DETERMINISTIC_FALLBACK_PUBLIC_KEY = Uint8Array.from([
  0xfb, 0xff, 0xff, ...Array.from({ length: 29 }, (_, index) => index),
]);

function makeEnvelope(
  signingOwner: Ed25519Keypair,
  members: readonly TestMember[],
  options: {
    readonly embeddedOwner?: Uint8Array;
    readonly version?: number;
  } = {},
): MeshEnvelope {
  const blob = canonicalBytes({
    version: options.version ?? 1,
    issued_at: 1_700_000_000_000,
    owner_pk: Buffer.from(
      options.embeddedOwner ?? signingOwner.publicKey,
    ).toString("base64"),
    members: members.map((member, index) => ({
      remote_epk: member.remoteEpk,
      relay_url: "wss://relay.test",
      paired_at: `2026-05-22T0${index}:00:00Z`,
      ...(member.nickname !== undefined
        ? { nickname: member.nickname }
        : {}),
    })),
  });
  return { blob, sig: ed25519Sign(signingOwner.secretKey, blob) };
}

function makeClient(
  envelopesByHash: ReadonlyMap<string, MeshEnvelope | null>,
): { readonly client: MeshClient; readonly get: ReturnType<typeof vi.fn> } {
  const get = vi.fn(async (hash: string) => envelopesByHash.get(hash) ?? null);
  return { client: { get } as unknown as MeshClient, get };
}

function membership(
  owner: Ed25519Keypair,
  members: readonly TestMember[],
): BoundOwnerMembership {
  return {
    ownerPubkey: standardKey(owner),
    members: members.map((member) => ({
      pcPubkey: member.remoteEpk,
      ...(member.nickname !== undefined
        ? { nickname: member.nickname }
        : {}),
    })),
  };
}

describe("buildTopologySnapshot", () => {
  test("includes only direct memberships containing self and freezes canonical output", () => {
    const ownerOne = generateEd25519Keypair();
    const ownerTwo = generateEd25519Keypair();
    const self = generateEd25519Keypair();
    const sibling = generateEd25519Keypair();
    const transitiveOnly = generateEd25519Keypair();

    const direct = membership(ownerOne, [
      { remoteEpk: urlSafeKey(self), nickname: "Self" },
      { remoteEpk: standardKey(sibling), nickname: "Sibling" },
    ]);
    const historical = membership(ownerTwo, [
      { remoteEpk: urlSafeKey(sibling), nickname: "Sibling" },
      { remoteEpk: standardKey(transitiveOnly), nickname: "Transitive" },
    ]);

    const snapshot = buildTopologySnapshot(self.publicKey, [historical, direct]);

    expect(snapshot).toEqual({
      self: { pcPubkey: standardKey(self), pcLabel: "Self", legacyPcLabel: "Self" },
      siblings: [
        { pcPubkey: standardKey(sibling), pcLabel: "Sibling", legacyPcLabel: "Sibling" },
      ],
    });
    expect(snapshot.siblings.some(
      (identity) => identity.pcPubkey === standardKey(transitiveOnly),
    )).toBe(false);
    expect(Object.isFrozen(snapshot)).toBe(true);
    expect(Object.isFrozen(snapshot.self)).toBe(true);
    expect(Object.isFrozen(snapshot.siblings)).toBe(true);
    expect(Object.isFrozen(snapshot.siblings[0])).toBe(true);
  });

  test("keeps raw selected nicknames only in the legacy wire label", () => {
    const ownerOne = generateEd25519Keypair();
    const ownerTwo = generateEd25519Keypair();
    const self = generateEd25519Keypair();
    const sibling = generateEd25519Keypair();
    const forward = buildTopologySnapshot(self.publicKey, [
      membership(ownerOne, [
        { remoteEpk: standardKey(self), nickname: "Self Alias" },
        { remoteEpk: standardKey(sibling), nickname: "Zulu" },
      ]),
      membership(ownerTwo, [
        { remoteEpk: standardKey(self), nickname: "Self Alias" },
        { remoteEpk: standardKey(sibling), nickname: "Alpha" },
      ]),
    ]);
    const reversed = buildTopologySnapshot(self.publicKey, [
      membership(ownerTwo, [
        { remoteEpk: standardKey(sibling), nickname: "Alpha" },
        { remoteEpk: standardKey(self), nickname: "Self Alias" },
      ]),
      membership(ownerOne, [
        { remoteEpk: standardKey(sibling), nickname: "Zulu" },
        { remoteEpk: standardKey(self), nickname: "Self Alias" },
      ]),
    ]);

    expect(forward).toEqual(reversed);
    expect(forward.self).toMatchObject({
      pcLabel: "Self%20Alias",
      legacyPcLabel: "Self Alias",
    });
    expect(forward.siblings[0]).toMatchObject({
      pcLabel: "Alpha",
      legacyPcLabel: "Alpha",
    });
  });

  test("uses canonical standard-padded key fallback for the legacy wire label", () => {
    const canonical = Buffer.from(DETERMINISTIC_FALLBACK_PUBLIC_KEY).toString("base64");
    const urlSafe = Buffer.from(DETERMINISTIC_FALLBACK_PUBLIC_KEY).toString("base64url");
    const snapshot = buildTopologySnapshot(DETERMINISTIC_FALLBACK_PUBLIC_KEY, []);

    expect(canonical.slice(0, 8)).toMatch(/[+/]/);
    expect(canonical.slice(0, 8)).not.toBe(urlSafe.slice(0, 8));
    expect(snapshot.self).toEqual({
      pcPubkey: canonical,
      pcLabel: fallbackLabel(canonical),
      legacyPcLabel: canonical.slice(0, 8),
    });
  });

  test("uses encoded-ASCII nickname selection and allocates self collisions together", () => {
    const ownerOne = generateEd25519Keypair();
    const ownerTwo = generateEd25519Keypair();
    const self = generateEd25519Keypair();
    const siblingOne = generateEd25519Keypair();
    const siblingTwo = generateEd25519Keypair();

    const first = membership(ownerOne, [
      { remoteEpk: standardKey(self), nickname: "Mac" },
      { remoteEpk: standardKey(siblingOne), nickname: "z" },
      { remoteEpk: standardKey(siblingTwo), nickname: "Mac" },
    ]);
    const second = membership(ownerTwo, [
      { remoteEpk: urlSafeKey(siblingTwo), nickname: "Mac" },
      { remoteEpk: urlSafeKey(siblingOne), nickname: ":" },
      { remoteEpk: urlSafeKey(self), nickname: "Mac" },
    ]);

    const forward = buildTopologySnapshot(self.publicKey, [first, second]);
    const reverse = buildTopologySnapshot(self.publicKey, [
      { ...second, members: [...second.members].reverse() },
      { ...first, members: [...first.members].reverse() },
    ]);

    expect(reverse).toEqual(forward);
    expect(forward.self.pcLabel).toMatch(/^Mac~/);
    expect(
      forward.siblings.find(
        (identity) => identity.pcPubkey === standardKey(siblingOne),
      )?.pcLabel,
    ).toBe("%3A");
    expect(
      forward.siblings.find(
        (identity) => identity.pcPubkey === standardKey(siblingTwo),
      )?.pcLabel,
    ).toMatch(/^Mac~/);
    const aliases = [forward.self, ...forward.siblings].map(
      (identity) => identity.pcLabel,
    );
    expect(new Set(aliases).size).toBe(aliases.length);
  });

  test("supports divergent receiver-local alias views", () => {
    const ownerMacView = generateEd25519Keypair();
    const ownerRtxView = generateEd25519Keypair();
    const mac = generateEd25519Keypair();
    const rtx = generateEd25519Keypair();

    const macView = buildTopologySnapshot(mac.publicKey, [
      membership(ownerMacView, [
        { remoteEpk: standardKey(mac), nickname: "Mac" },
        { remoteEpk: standardKey(rtx), nickname: "RTX4090" },
      ]),
    ]);
    const rtxView = buildTopologySnapshot(rtx.publicKey, [
      membership(ownerRtxView, [
        { remoteEpk: standardKey(mac), nickname: "mac" },
        { remoteEpk: standardKey(rtx), nickname: "Captiva-RTX-4090" },
      ]),
    ]);

    expect(macView.self.pcLabel).toBe("Mac");
    expect(macView.siblings[0]?.pcLabel).toBe("RTX4090");
    expect(rtxView.self.pcLabel).toBe("Captiva-RTX-4090");
    expect(rtxView.siblings[0]?.pcLabel).toBe("mac");
  });
});

describe("discoverTopology", () => {
  test("canonicalizes and groups raw Owners per record with hash-only invalid logs", async () => {
    const owner = generateEd25519Keypair();
    const self = generateEd25519Keypair();
    const sibling = generateEd25519Keypair();
    const invalidRawOwner = "not a public key";
    const envelope = makeEnvelope(owner, [
      { remoteEpk: urlSafeKey(self), nickname: "Self" },
      { remoteEpk: urlSafeKey(sibling), nickname: "Sibling" },
    ]);
    const { client, get } = makeClient(
      new Map([[sha256Hex(owner.publicKey), envelope]]),
    );
    const log = { warn: vi.fn() };

    const snapshot = await discoverTopology({
      client,
      ownerEpks: [invalidRawOwner, urlSafeKey(owner), standardKey(owner)],
      myPubkey: self.publicKey,
      log,
    });

    expect(get).toHaveBeenCalledTimes(1);
    expect(get).toHaveBeenCalledWith(sha256Hex(owner.publicKey));
    expect(snapshot.siblings).toEqual([
      { pcPubkey: standardKey(sibling), pcLabel: "Sibling", legacyPcLabel: "Sibling" },
    ]);
    expect(log.warn).toHaveBeenCalledWith(
      expect.stringContaining(rawFingerprint(invalidRawOwner)),
    );
    for (const [message] of log.warn.mock.calls) {
      expect(message).not.toContain(invalidRawOwner);
      expect(message).not.toContain(standardKey(owner));
    }
  });

  test("skips non-string raw Owner records without blocking a later valid Owner", async () => {
    const owner = generateEd25519Keypair();
    const self = generateEd25519Keypair();
    const sibling = generateEd25519Keypair();
    const envelope = makeEnvelope(owner, [
      { remoteEpk: standardKey(self), nickname: "Self" },
      { remoteEpk: standardKey(sibling), nickname: "Sibling" },
    ]);
    const { client, get } = makeClient(
      new Map([[sha256Hex(owner.publicKey), envelope]]),
    );
    const log = { warn: vi.fn() };

    const snapshot = await discoverTopology({
      client,
      ownerEpks: [null, 42, urlSafeKey(owner)],
      myPubkey: self.publicKey,
      log,
    });

    expect(get).toHaveBeenCalledTimes(1);
    expect(snapshot.siblings).toEqual([
      { pcPubkey: standardKey(sibling), pcLabel: "Sibling", legacyPcLabel: "Sibling" },
    ]);
    expect(log.warn).toHaveBeenCalledTimes(2);
    for (const [message] of log.warn.mock.calls) {
      expect(message).toMatch(
        /^\[mesh\] event=invalid_owner_record owner_fp=[0-9a-f]{8}$/,
      );
    }
  });

  test("rejects a valid blob whose embedded Owner does not match the requested slot", async () => {
    const requestedOwner = generateEd25519Keypair();
    const otherOwner = generateEd25519Keypair();
    const self = generateEd25519Keypair();
    const injected = generateEd25519Keypair();
    const wrongEnvelope = makeEnvelope(otherOwner, [
      { remoteEpk: standardKey(self), nickname: "Self" },
      { remoteEpk: standardKey(injected), nickname: "Injected" },
    ]);
    const { client } = makeClient(
      new Map([[sha256Hex(requestedOwner.publicKey), wrongEnvelope]]),
    );
    const log = { warn: vi.fn() };

    const snapshot = await discoverTopology({
      client,
      ownerEpks: [standardKey(requestedOwner)],
      myPubkey: self.publicKey,
      log,
    });

    expect(snapshot.siblings).toEqual([]);
    expect(snapshot.self.pcLabel).toBe(fallbackLabel(standardKey(self)));
    expect(log.warn).toHaveBeenCalledTimes(1);
  });

  test("excludes transitive members and is stable under Owner/member reversal", async () => {
    const directOwner = generateEd25519Keypair();
    const historicalOwner = generateEd25519Keypair();
    const self = generateEd25519Keypair();
    const sibling = generateEd25519Keypair();
    const transitiveOnly = generateEd25519Keypair();
    const directMembers = [
      { remoteEpk: urlSafeKey(self), nickname: "Self" },
      { remoteEpk: standardKey(sibling), nickname: "Sibling" },
    ];
    const historicalMembers = [
      { remoteEpk: urlSafeKey(sibling), nickname: "Sibling" },
      { remoteEpk: standardKey(transitiveOnly), nickname: "Transitive" },
    ];
    const envelopeMap = new Map([
      [sha256Hex(directOwner.publicKey), makeEnvelope(directOwner, directMembers)],
      [
        sha256Hex(historicalOwner.publicKey),
        makeEnvelope(historicalOwner, historicalMembers),
      ],
    ]);

    const forward = await discoverTopology({
      client: makeClient(envelopeMap).client,
      ownerEpks: [standardKey(directOwner), standardKey(historicalOwner)],
      myPubkey: self.publicKey,
    });
    const reversedMap = new Map([
      [
        sha256Hex(directOwner.publicKey),
        makeEnvelope(directOwner, [...directMembers].reverse()),
      ],
      [
        sha256Hex(historicalOwner.publicKey),
        makeEnvelope(historicalOwner, [...historicalMembers].reverse()),
      ],
    ]);
    const reverse = await discoverTopology({
      client: makeClient(reversedMap).client,
      ownerEpks: [standardKey(historicalOwner), standardKey(directOwner)],
      myPubkey: self.publicKey,
    });

    expect(reverse).toEqual(forward);
    expect(forward.siblings.map((identity) => identity.pcPubkey)).toEqual([
      standardKey(sibling),
    ]);
  });

  test("invalidates one malformed contribution without aborting another Owner", async () => {
    const malformedOwner = generateEd25519Keypair();
    const validOwner = generateEd25519Keypair();
    const self = generateEd25519Keypair();
    const sibling = generateEd25519Keypair();
    const malformed = makeEnvelope(malformedOwner, [
      { remoteEpk: standardKey(self), nickname: "Self" },
      { remoteEpk: "bad key", nickname: "Bad" },
    ]);
    const valid = makeEnvelope(validOwner, [
      { remoteEpk: standardKey(self), nickname: "Self" },
      { remoteEpk: standardKey(sibling), nickname: "Sibling" },
    ]);
    const { client } = makeClient(
      new Map([
        [sha256Hex(malformedOwner.publicKey), malformed],
        [sha256Hex(validOwner.publicKey), valid],
      ]),
    );
    const log = { warn: vi.fn() };

    const snapshot = await discoverTopology({
      client,
      ownerEpks: [standardKey(malformedOwner), standardKey(validOwner)],
      myPubkey: self.publicKey,
      log,
    });

    expect(snapshot.siblings).toEqual([
      { pcPubkey: standardKey(sibling), pcLabel: "Sibling", legacyPcLabel: "Sibling" },
    ]);
    expect(log.warn).toHaveBeenCalledTimes(1);
  });
});

describe("compatibility wrappers", () => {
  test("derive encoded effective aliases through the topology builder", async () => {
    const owner = generateEd25519Keypair();
    const self = generateEd25519Keypair();
    const sibling = generateEd25519Keypair();
    const envelope = makeEnvelope(owner, [
      { remoteEpk: standardKey(self), nickname: "Self Alias" },
      { remoteEpk: standardKey(sibling), nickname: "Sibling" },
    ]);
    const envelopeMap = new Map([[sha256Hex(owner.publicKey), envelope]]);
    const options = {
      ownerEpks: [urlSafeKey(owner)],
      myPubkey: self.publicKey,
    };

    const selfResult = await discoverSelfLabel({
      ...options,
      client: makeClient(envelopeMap).client,
    });
    const siblings = await discoverSiblings({
      ...options,
      client: makeClient(envelopeMap).client,
    });

    expect(selfResult).toEqual({ selfPcLabel: "Self%20Alias" });
    expect(siblings).toEqual([
      { pcPubkey: standardKey(sibling), pcLabel: "Sibling" },
    ]);
    expect(fallbackLabel(urlSafeKey(self))).toBe(
      `pc-${Buffer.from(self.publicKey).toString("base64url").slice(0, 8)}`,
    );
  });
});
