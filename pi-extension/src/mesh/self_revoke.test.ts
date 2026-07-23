import { createHash } from "node:crypto";
import { describe, expect, test, vi } from "vitest";
import {
  ed25519Sign,
  generateEd25519Keypair,
  type Ed25519Keypair,
} from "../pairing/crypto.js";
import { canonicalBytes } from "./canonical.js";
import {
  MeshFetchInvalidResponseError,
  MeshFetchUnavailableError,
  type MeshClient,
} from "./client.js";
import { SelfRevoke, type SelfRevokeStorage } from "./self_revoke.js";
import { fallbackLabel, type MeshTopologySnapshot } from "./siblings.js";
import type { MeshEnvelope } from "./types.js";

interface TestMember {
  readonly remoteEpk: string;
  readonly nickname?: string;
}

interface TestContext {
  readonly owner: Ed25519Keypair;
  readonly otherOwner: Ed25519Keypair;
  readonly self: Ed25519Keypair;
  readonly sibling: Ed25519Keypair;
}

function standardKey(keypair: Ed25519Keypair): string {
  return Buffer.from(keypair.publicKey).toString("base64");
}

function urlSafeKey(keypair: Ed25519Keypair): string {
  return Buffer.from(keypair.publicKey).toString("base64url");
}

function ownerHash(owner: Ed25519Keypair): string {
  return createHash("sha256").update(owner.publicKey).digest("hex");
}

function rawFingerprint(raw: string): string {
  return createHash("sha256").update(raw, "utf8").digest("hex").slice(0, 8);
}

function makeEnvelope(
  owner: Ed25519Keypair,
  version: number,
  members: readonly TestMember[],
): MeshEnvelope {
  const blob = canonicalBytes({
    version,
    issued_at: 1_700_000_000_000,
    owner_pk: standardKey(owner),
    members: members.map((member, index) => ({
      remote_epk: member.remoteEpk,
      relay_url: "wss://relay.test",
      paired_at: `2026-05-22T0${index}:00:00Z`,
      ...(member.nickname !== undefined
        ? { nickname: member.nickname }
        : {}),
    })),
  });
  return { blob, sig: ed25519Sign(owner.secretKey, blob) };
}

function badSignature(envelope: MeshEnvelope): MeshEnvelope {
  const sig = new Uint8Array(envelope.sig);
  sig[0] = sig[0]! ^ 0xff;
  return { blob: envelope.blob, sig };
}

function defaultLog() {
  return {
    info: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
  };
}

function storage(
  listOwnerPubkeys: () => Promise<unknown[]>,
  removePeer: (remoteEpk: string, canCommit?: () => boolean) => Promise<boolean> = vi.fn().mockResolvedValue(true),
): SelfRevokeStorage {
  return {
    snapshotOwnerPubkeys: () => listOwnerPubkeys().then((rawOwners) => rawOwners.map(
      (rawOwnerPubkey) => ({ rawOwnerPubkey, token: String(rawOwnerPubkey) }),
    )),
    conditionalRemovePeer: async (remoteEpk, _token, canCommit) => {
      const removed = await removePeer(remoteEpk, canCommit);
      return removed
        ? { outcome: "removed" as const, nextToken: `${remoteEpk}:next` }
        : { outcome: "not_found" as const };
    },
  };
}

function client(get: ReturnType<typeof vi.fn>): MeshClient {
  return { get } as unknown as MeshClient;
}

function siblingKeys(snapshot: MeshTopologySnapshot): string[] {
  return snapshot.siblings.map((identity) => identity.pcPubkey);
}

describe("SelfRevoke canonical Owner state", () => {
  test("groups standard and URL-safe raw Owners into one canonical fetch/contribution", async () => {
    const owner = generateEd25519Keypair();
    const self = generateEd25519Keypair();
    const sibling = generateEd25519Keypair();
    const get = vi.fn().mockResolvedValue(
      makeEnvelope(owner, 1, [
        { remoteEpk: urlSafeKey(self), nickname: "Self" },
        { remoteEpk: urlSafeKey(sibling), nickname: "Sibling" },
      ]),
    );
    const removePeer = vi.fn().mockResolvedValue(true);
    const onAuthoritativeOwners = vi.fn();
    const onTopologyChanged = vi.fn();
    const revoker = new SelfRevoke({
      client: client(get),
      storage: storage(
        vi.fn().mockResolvedValue([urlSafeKey(owner), standardKey(owner)]),
        removePeer,
      ),
      myPubkey: self.publicKey,
      onAuthoritativeOwners,
      onTopologyChanged,
      log: defaultLog(),
    });

    await revoker.checkOnce();

    expect(onAuthoritativeOwners).toHaveBeenCalledTimes(1);
    expect(onAuthoritativeOwners).toHaveBeenCalledWith([standardKey(owner)]);
    expect(get).toHaveBeenCalledTimes(1);
    expect(get).toHaveBeenCalledWith(ownerHash(owner), undefined);
    expect(removePeer).not.toHaveBeenCalled();
    expect(onTopologyChanged).toHaveBeenCalledTimes(1);
    const snapshot = onTopologyChanged.mock.calls[0]![0] as MeshTopologySnapshot;
    expect(snapshot.self.pcPubkey).toBe(standardKey(self));
    expect(siblingKeys(snapshot)).toEqual([standardKey(sibling)]);
  });

  test("self-revoke removes every exact raw handle and detaches by canonical Owner", async () => {
    const owner = generateEd25519Keypair();
    const self = generateEd25519Keypair();
    const other = generateEd25519Keypair();
    const rawOwners = [urlSafeKey(owner), standardKey(owner)];
    const removePeer = vi.fn().mockResolvedValue(true);
    const onRevoke = vi.fn();
    const onTopologyChanged = vi.fn();
    const revoker = new SelfRevoke({
      client: client(
        vi.fn().mockResolvedValue(
          makeEnvelope(owner, 2, [{ remoteEpk: standardKey(other) }]),
        ),
      ),
      storage: storage(vi.fn().mockResolvedValue(rawOwners), removePeer),
      myPubkey: self.publicKey,
      onRevoke,
      onTopologyChanged,
      log: defaultLog(),
    });

    await revoker.checkOnce();

    expect(removePeer).toHaveBeenCalledTimes(2);
    expect(removePeer.mock.calls.map(([raw]) => raw).sort()).toEqual(
      [...rawOwners].sort(),
    );
    expect(onRevoke).toHaveBeenCalledTimes(2);
    for (const [rawOwner, canonicalOwner] of onRevoke.mock.calls) {
      expect(rawOwners).toContain(rawOwner);
      expect(canonicalOwner).toBe(standardKey(owner));
    }
    const snapshot = onTopologyChanged.mock.calls[0]![0] as MeshTopologySnapshot;
    expect(snapshot.siblings).toEqual([]);
  });

  test("authoritative not_found detaches canonical Owner once", async () => {
    const owner = generateEd25519Keypair();
    const self = generateEd25519Keypair();
    const rawOwner = urlSafeKey(owner);
    const snapshotOwnerPubkeys = vi.fn().mockResolvedValue([
      { rawOwnerPubkey: rawOwner, token: "owner-v1" },
    ]);
    const conditionalRemovePeer = vi.fn().mockResolvedValue({ outcome: "not_found" });
    const onRevoke = vi.fn();
    const get = vi.fn()
      .mockResolvedValueOnce(makeEnvelope(owner, 1, []))
      .mockResolvedValueOnce(null);
    const revoker = new SelfRevoke({
      client: client(get),
      storage: { snapshotOwnerPubkeys, conditionalRemovePeer } as unknown as SelfRevokeStorage,
      myPubkey: self.publicKey,
      onRevoke,
      log: defaultLog(),
    });

    await revoker.checkOnce();
    await revoker.checkOnce();

    expect(conditionalRemovePeer).toHaveBeenCalledTimes(1);
    expect(onRevoke).toHaveBeenCalledTimes(1);
    expect(onRevoke).toHaveBeenCalledWith(rawOwner, standardKey(owner));
  });

  test("prunes an Owner removed from storage before publishing the next union", async () => {
    const owner = generateEd25519Keypair();
    const self = generateEd25519Keypair();
    const sibling = generateEd25519Keypair();
    const listOwnerPubkeys = vi
      .fn()
      .mockResolvedValueOnce([standardKey(owner)])
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([]);
    const onAuthoritativeOwners = vi
      .fn()
      .mockResolvedValueOnce(undefined)
      .mockRejectedValueOnce(new Error("authoritative Owner callback failed"))
      .mockResolvedValueOnce(undefined);
    const onTopologyChanged = vi.fn();
    const revoker = new SelfRevoke({
      client: client(
        vi.fn().mockResolvedValue(
          makeEnvelope(owner, 1, [
            { remoteEpk: standardKey(self) },
            { remoteEpk: standardKey(sibling) },
          ]),
        ),
      ),
      storage: storage(listOwnerPubkeys),
      myPubkey: self.publicKey,
      onAuthoritativeOwners,
      onTopologyChanged,
      log: defaultLog(),
    });

    await revoker.checkOnce();
    await revoker.checkOnce();
    await revoker.checkOnce();

    expect(onAuthoritativeOwners.mock.calls.map(([owners]) => owners)).toEqual([
      [standardKey(owner)],
      [],
      [],
    ]);
    expect(onTopologyChanged).toHaveBeenCalledTimes(2);
    expect(siblingKeys(onTopologyChanged.mock.calls[0]![0])).toEqual([
      standardKey(sibling),
    ]);
    expect(siblingKeys(onTopologyChanged.mock.calls[1]![0])).toEqual([]);
  });

  test("prunes before union when {self,B} becomes {B,C}; C never leaks", async () => {
    const owner = generateEd25519Keypair();
    const self = generateEd25519Keypair();
    const sibling = generateEd25519Keypair();
    const transitiveOnly = generateEd25519Keypair();
    const get = vi
      .fn()
      .mockResolvedValueOnce(
        makeEnvelope(owner, 1, [
          { remoteEpk: standardKey(self) },
          { remoteEpk: standardKey(sibling) },
        ]),
      )
      .mockResolvedValueOnce(
        makeEnvelope(owner, 2, [
          { remoteEpk: standardKey(sibling) },
          { remoteEpk: standardKey(transitiveOnly) },
        ]),
      );
    const removePeer = vi.fn().mockResolvedValue(true);
    const onTopologyChanged = vi.fn();
    const revoker = new SelfRevoke({
      client: client(get),
      storage: storage(
        vi.fn().mockResolvedValue([standardKey(owner)]),
        removePeer,
      ),
      myPubkey: self.publicKey,
      onTopologyChanged,
      log: defaultLog(),
    });

    await revoker.checkOnce();
    await revoker.checkOnce();

    expect(siblingKeys(onTopologyChanged.mock.calls[0]![0])).toEqual([
      standardKey(sibling),
    ]);
    expect(siblingKeys(onTopologyChanged.mock.calls[1]![0])).toEqual([]);
    for (const [snapshot] of onTopologyChanged.mock.calls) {
      expect(siblingKeys(snapshot)).not.toContain(standardKey(transitiveOnly));
    }
    expect(removePeer).toHaveBeenCalledWith(
      standardKey(owner),
      expect.any(Function),
    );
  });
});

describe("SelfRevoke retention and invalid-response transitions", () => {
  const invalidEnvelopeCases: readonly [
    string,
    (context: TestContext) => MeshEnvelope,
  ][] = [
    [
      "wrong Owner",
      ({ otherOwner, self, sibling }) =>
        makeEnvelope(otherOwner, 6, [
          { remoteEpk: standardKey(self) },
          { remoteEpk: standardKey(sibling) },
        ]),
    ],
    [
      "bad signature",
      ({ owner, self, sibling }) =>
        badSignature(
          makeEnvelope(owner, 6, [
            { remoteEpk: standardKey(self) },
            { remoteEpk: standardKey(sibling) },
          ]),
        ),
    ],
    [
      "malformed member",
      ({ owner, self }) =>
        makeEnvelope(owner, 6, [
          { remoteEpk: standardKey(self) },
          { remoteEpk: "bad key" },
        ]),
    ],
  ];

  test.each(invalidEnvelopeCases)(
    "newly fetched %s prunes its old contribution without editing storage",
    async (_label, makeInvalid) => {
      const context: TestContext = {
        owner: generateEd25519Keypair(),
        otherOwner: generateEd25519Keypair(),
        self: generateEd25519Keypair(),
        sibling: generateEd25519Keypair(),
      };
      const valid = makeEnvelope(context.owner, 5, [
        { remoteEpk: standardKey(context.self) },
        { remoteEpk: standardKey(context.sibling) },
      ]);
      const get = vi
        .fn()
        .mockResolvedValueOnce(valid)
        .mockResolvedValueOnce(makeInvalid(context));
      const removePeer = vi.fn().mockResolvedValue(true);
      const onTopologyChanged = vi.fn();
      const revoker = new SelfRevoke({
        client: client(get),
        storage: storage(
          vi.fn().mockResolvedValue([standardKey(context.owner)]),
          removePeer,
        ),
        myPubkey: context.self.publicKey,
        onTopologyChanged,
        log: defaultLog(),
      });

      await revoker.checkOnce();
      await revoker.checkOnce();

      expect(onTopologyChanged).toHaveBeenCalledTimes(2);
      expect(siblingKeys(onTopologyChanged.mock.calls[1]![0])).toEqual([]);
      expect(removePeer).not.toHaveBeenCalled();
    },
  );

  test("typed invalid HTTP response prunes while null/network outage retains", async () => {
    const owner = generateEd25519Keypair();
    const self = generateEd25519Keypair();
    const sibling = generateEd25519Keypair();
    const valid = makeEnvelope(owner, 5, [
      { remoteEpk: standardKey(self) },
      { remoteEpk: standardKey(sibling) },
    ]);
    const get = vi
      .fn()
      .mockResolvedValueOnce(valid)
      .mockResolvedValueOnce(null)
      .mockRejectedValueOnce(new MeshFetchUnavailableError("unavailable"))
      .mockRejectedValueOnce(new MeshFetchInvalidResponseError("invalid"));
    const onTopologyChanged = vi.fn();
    const revoker = new SelfRevoke({
      client: client(get),
      storage: storage(
        vi.fn().mockResolvedValue([standardKey(owner)]),
      ),
      myPubkey: self.publicKey,
      onTopologyChanged,
      log: defaultLog(),
    });

    await revoker.checkOnce();
    await revoker.checkOnce();
    await revoker.checkOnce();
    expect(onTopologyChanged).toHaveBeenCalledTimes(1);
    await revoker.checkOnce();

    expect(onTopologyChanged).toHaveBeenCalledTimes(2);
    expect(siblingKeys(onTopologyChanged.mock.calls[1]![0])).toEqual([]);
  });

});

describe("SelfRevoke anti-rollback", () => {
  test("same instance retains a higher signed version when a lower signed version follows", async () => {
    const owner = generateEd25519Keypair();
    const self = generateEd25519Keypair();
    const sibling = generateEd25519Keypair();
    const get = vi.fn()
      .mockResolvedValueOnce(makeEnvelope(owner, 2, [
        { remoteEpk: standardKey(self) },
        { remoteEpk: standardKey(sibling) },
      ]))
      .mockResolvedValueOnce(makeEnvelope(owner, 1, [
        { remoteEpk: standardKey(self) },
      ]));
    const onTopologyChanged = vi.fn();
    const log = defaultLog();
    const revoker = new SelfRevoke({
      client: client(get),
      storage: storage(vi.fn().mockResolvedValue([standardKey(owner)])),
      myPubkey: self.publicKey,
      onTopologyChanged,
      log,
    });

    await revoker.checkOnce();
    await revoker.checkOnce();

    expect(get).toHaveBeenNthCalledWith(1, ownerHash(owner), undefined);
    expect(get).toHaveBeenNthCalledWith(2, ownerHash(owner), 2);
    expect(onTopologyChanged).toHaveBeenCalledTimes(1);
    expect(siblingKeys(onTopologyChanged.mock.calls[0]![0])).toEqual([standardKey(sibling)]);
    expect(log.warn).toHaveBeenCalledWith(expect.stringMatching(/event=owner_rollback.*received_version=1.*retained_version=2/));
  });
});

describe("SelfRevoke atomic topology publication", () => {
  test("publishes alias-only changes once and suppresses a material no-op", async () => {
    const owner = generateEd25519Keypair();
    const self = generateEd25519Keypair();
    const sibling = generateEd25519Keypair();
    const get = vi
      .fn()
      .mockResolvedValueOnce(
        makeEnvelope(owner, 1, [
          { remoteEpk: standardKey(self), nickname: "Self" },
          { remoteEpk: standardKey(sibling), nickname: "Zulu" },
        ]),
      )
      .mockResolvedValueOnce(
        makeEnvelope(owner, 2, [
          { remoteEpk: standardKey(self), nickname: "Self" },
          { remoteEpk: standardKey(sibling), nickname: ":" },
        ]),
      )
      .mockResolvedValueOnce(
        makeEnvelope(owner, 3, [
          { remoteEpk: standardKey(self), nickname: "Self" },
          { remoteEpk: standardKey(sibling), nickname: ":" },
        ]),
      );
    const onTopologyChanged = vi.fn();
    const revoker = new SelfRevoke({
      client: client(get),
      storage: storage(
        vi.fn().mockResolvedValue([standardKey(owner)]),
      ),
      myPubkey: self.publicKey,
      onTopologyChanged,
      log: defaultLog(),
    });

    await revoker.checkOnce();
    await revoker.checkOnce();
    await revoker.checkOnce();

    expect(onTopologyChanged).toHaveBeenCalledTimes(2);
    expect(onTopologyChanged.mock.calls[0]![0].siblings[0]).toMatchObject({
      pcLabel: "Zulu",
      legacyPcLabel: "Zulu",
    });
    expect(onTopologyChanged.mock.calls[1]![0].siblings[0]).toMatchObject({
      pcLabel: "%3A",
      legacyPcLabel: ":",
    });
  });

  test("publishes at most once after a complete multi-Owner sweep", async () => {
    const ownerOne = generateEd25519Keypair();
    const ownerTwo = generateEd25519Keypair();
    const self = generateEd25519Keypair();
    const siblingOne = generateEd25519Keypair();
    const siblingTwo = generateEd25519Keypair();
    const envelopes = new Map([
      [
        ownerHash(ownerOne),
        makeEnvelope(ownerOne, 1, [
          { remoteEpk: standardKey(self) },
          { remoteEpk: standardKey(siblingOne) },
        ]),
      ],
      [
        ownerHash(ownerTwo),
        makeEnvelope(ownerTwo, 1, [
          { remoteEpk: standardKey(self) },
          { remoteEpk: standardKey(siblingTwo) },
        ]),
      ],
    ]);
    const onTopologyChanged = vi.fn();
    const revoker = new SelfRevoke({
      client: client(vi.fn(async (hash: string) => envelopes.get(hash) ?? null)),
      storage: storage(
        vi.fn().mockResolvedValue([
          standardKey(ownerTwo),
          standardKey(ownerOne),
        ]),
      ),
      myPubkey: self.publicKey,
      onTopologyChanged,
      log: defaultLog(),
    });

    await revoker.checkOnce();

    expect(onTopologyChanged).toHaveBeenCalledTimes(1);
    expect(siblingKeys(onTopologyChanged.mock.calls[0]![0]).sort()).toEqual(
      [standardKey(siblingOne), standardKey(siblingTwo)].sort(),
    );
  });

  test("stop during storage removal cannot delete a replacement pairing", async () => {
    const owner = generateEd25519Keypair();
    const self = generateEd25519Keypair();
    const sibling = generateEd25519Keypair();
    const rawOwner = standardKey(owner);
    const storedOwners = [rawOwner];
    let signalRemovalStarted!: () => void;
    const removalStarted = new Promise<void>((resolve) => {
      signalRemovalStarted = resolve;
    });
    let releaseCommit!: () => void;
    const commitGate = new Promise<void>((resolve) => {
      releaseCommit = resolve;
    });
    const removePeer = vi.fn(async (
      remoteEpk: string,
      canCommit?: () => boolean,
    ): Promise<boolean> => {
      signalRemovalStarted();
      await commitGate;
      if (canCommit && !canCommit()) return false;
      const index = storedOwners.indexOf(remoteEpk);
      if (index < 0) return false;
      storedOwners.splice(index, 1);
      return true;
    });
    const sharedStorage: SelfRevokeStorage = {
      snapshotOwnerPubkeys: async () => storedOwners.map((rawOwnerPubkey) => ({
        rawOwnerPubkey,
        token: "owner-v1",
      })),
      conditionalRemovePeer: async (remoteEpk, _token, canCommit) => {
        const removed = await removePeer(remoteEpk, canCommit);
        return removed
          ? { outcome: "removed", nextToken: "owner-v2" }
          : { outcome: "not_found" };
      },
    };
    const oldOnRevoke = vi.fn();
    const stale = new SelfRevoke({
      client: client(vi.fn().mockResolvedValue(makeEnvelope(owner, 1, [
        { remoteEpk: standardKey(sibling) },
      ]))),
      storage: sharedStorage,
      myPubkey: self.publicKey,
      onRevoke: oldOnRevoke,
      log: defaultLog(),
    });

    const staleSweep = stale.checkOnce();
    await removalStarted;
    stale.stop();

    // Re-pair and start the replacement producer while the old storage commit
    // is parked. The exact raw Owner handle remains the shared storage key.
    storedOwners.splice(0, storedOwners.length, rawOwner);
    const replacementTopology = vi.fn();
    const replacement = new SelfRevoke({
      client: client(vi.fn().mockResolvedValue(makeEnvelope(owner, 2, [
        { remoteEpk: standardKey(self) },
        { remoteEpk: standardKey(sibling) },
      ]))),
      storage: sharedStorage,
      myPubkey: self.publicKey,
      onTopologyChanged: replacementTopology,
      log: defaultLog(),
    });
    await replacement.checkOnce();

    releaseCommit();
    await staleSweep;

    expect(removePeer).toHaveBeenCalledTimes(1);
    expect(removePeer.mock.calls[0]![0]).toBe(rawOwner);
    expect(removePeer.mock.calls[0]![1]).toBeTypeOf("function");
    expect(storedOwners).toEqual([rawOwner]);
    expect(oldOnRevoke).not.toHaveBeenCalled();
    expect(replacementTopology).toHaveBeenCalledTimes(1);
  });

});

describe("SelfRevoke failure isolation", () => {
  test("initial storage-list failure emits one safe fallback topology", async () => {
    const self = generateEd25519Keypair();
    const secret = "storage-secret";
    const onAuthoritativeOwners = vi.fn();
    const onTopologyChanged = vi.fn();
    const log = defaultLog();
    const revoker = new SelfRevoke({
      client: client(vi.fn()),
      storage: storage(vi.fn().mockRejectedValue(new Error(secret))),
      myPubkey: self.publicKey,
      onAuthoritativeOwners,
      onTopologyChanged,
      log,
    });

    await expect(revoker.checkOnce()).resolves.toBeUndefined();

    expect(onAuthoritativeOwners).not.toHaveBeenCalled();
    expect(onTopologyChanged).toHaveBeenCalledTimes(1);
    expect(onTopologyChanged).toHaveBeenCalledWith({
      self: {
        pcPubkey: standardKey(self),
        pcLabel: fallbackLabel(standardKey(self)),
        legacyPcLabel: standardKey(self).slice(0, 8),
      },
      siblings: [],
    });
    for (const mock of [log.warn, log.error]) {
      for (const [message] of mock.mock.calls) {
        expect(message).not.toContain(secret);
      }
    }
  });

  test("later storage-list failure retains the previous successful topology", async () => {
    const owner = generateEd25519Keypair();
    const self = generateEd25519Keypair();
    const sibling = generateEd25519Keypair();
    const listOwnerPubkeys = vi
      .fn()
      .mockResolvedValueOnce([standardKey(owner)])
      .mockRejectedValueOnce(new Error("later failure"));
    const onTopologyChanged = vi.fn();
    const revoker = new SelfRevoke({
      client: client(
        vi.fn().mockResolvedValue(
          makeEnvelope(owner, 1, [
            { remoteEpk: standardKey(self) },
            { remoteEpk: standardKey(sibling) },
          ]),
        ),
      ),
      storage: storage(listOwnerPubkeys),
      myPubkey: self.publicKey,
      onTopologyChanged,
      log: defaultLog(),
    });

    await revoker.checkOnce();
    await expect(revoker.checkOnce()).resolves.toBeUndefined();

    expect(onTopologyChanged).toHaveBeenCalledTimes(1);
    expect(siblingKeys(onTopologyChanged.mock.calls[0]![0])).toEqual([
      standardKey(sibling),
    ]);
  });

  test("isolates a malformed raw Owner, prunes stale state, and continues a valid slot", async () => {
    const oldOwner = generateEd25519Keypair();
    const validOwner = generateEd25519Keypair();
    const self = generateEd25519Keypair();
    const oldSibling = generateEd25519Keypair();
    const validSibling = generateEd25519Keypair();
    const malformedRaw = "malformed Owner record";
    const listOwnerPubkeys = vi
      .fn()
      .mockResolvedValueOnce([standardKey(oldOwner)])
      .mockResolvedValueOnce([
        null,
        42,
        malformedRaw,
        urlSafeKey(validOwner),
      ]);
    const envelopes = new Map([
      [
        ownerHash(oldOwner),
        makeEnvelope(oldOwner, 1, [
          { remoteEpk: standardKey(self) },
          { remoteEpk: standardKey(oldSibling) },
        ]),
      ],
      [
        ownerHash(validOwner),
        makeEnvelope(validOwner, 1, [
          { remoteEpk: standardKey(self) },
          { remoteEpk: standardKey(validSibling) },
        ]),
      ],
    ]);
    const onTopologyChanged = vi.fn();
    const log = defaultLog();
    const revoker = new SelfRevoke({
      client: client(vi.fn(async (hash: string) => envelopes.get(hash) ?? null)),
      storage: storage(listOwnerPubkeys),
      myPubkey: self.publicKey,
      onTopologyChanged,
      log,
    });

    await revoker.checkOnce();
    await revoker.checkOnce();

    expect(siblingKeys(onTopologyChanged.mock.calls[1]![0])).toEqual([
      standardKey(validSibling),
    ]);
    const messages = [...log.warn.mock.calls, ...log.error.mock.calls].map(
      ([message]) => message as string,
    );
    expect(messages.some((message) =>
      message.includes(rawFingerprint(malformedRaw)),
    )).toBe(true);
    expect(messages.every((message) => !message.includes(malformedRaw))).toBe(true);
  });

  test("an unavailable initial Owner fetch completes with safe fallback topology", async () => {
    const owner = generateEd25519Keypair();
    const self = generateEd25519Keypair();
    const onTopologyChanged = vi.fn();
    const revoker = new SelfRevoke({
      client: client(
        vi.fn().mockRejectedValue(new MeshFetchUnavailableError("timeout")),
      ),
      storage: storage(
        vi.fn().mockResolvedValue([standardKey(owner)]),
      ),
      myPubkey: self.publicKey,
      onTopologyChanged,
      log: defaultLog(),
    });

    await expect(revoker.checkOnce()).resolves.toBeUndefined();

    expect(onTopologyChanged).toHaveBeenCalledTimes(1);
    expect(onTopologyChanged.mock.calls[0]![0].siblings).toEqual([]);
  });
});
