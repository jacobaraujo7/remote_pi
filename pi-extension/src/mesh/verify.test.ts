import { describe, expect, test } from "vitest";
import { generateEd25519Keypair, ed25519Sign } from "../pairing/crypto.js";
import { canonicalBytes } from "./canonical.js";
import { verifyEnvelope } from "./verify.js";
import type { MeshEnvelope } from "./types.js";

const PI_ONE_BYTES = Uint8Array.from(
  { length: 32 },
  (_, index) => (index * 17 + 11) & 0xff,
);
const PI_TWO_BYTES = Uint8Array.from(
  { length: 32 },
  (_, index) => (index * 29 + 7) & 0xff,
);
const PI_ONE_STANDARD = Buffer.from(PI_ONE_BYTES).toString("base64");
const PI_TWO_STANDARD = Buffer.from(PI_TWO_BYTES).toString("base64");
const PI_TWO_URL_SAFE = Buffer.from(PI_TWO_BYTES).toString("base64url");

/** Builds a signed envelope from a logical header object for test use. */
function makeSignedEnvelope(
  logical: Record<string, unknown>,
  sk: Uint8Array,
): MeshEnvelope {
  const blob = canonicalBytes(logical);
  const sig = ed25519Sign(sk, blob);
  return { blob, sig };
}

describe("verifyEnvelope", () => {
  test("accepts a valid signed envelope and parses fields", async () => {
    const kp = generateEd25519Keypair();
    const ownerPkB64 = Buffer.from(kp.publicKey).toString("base64");
    const env = makeSignedEnvelope(
      {
        version: 7,
        issued_at: 1700000000000,
        owner_pk: ownerPkB64,
        members: [
          {
            remote_epk: PI_ONE_STANDARD,
            relay_url: "wss://r",
            paired_at: "2026-05-22T10:00:00Z",
            nickname: null,
          },
          {
            remote_epk: PI_TWO_URL_SAFE,
            relay_url: "wss://r",
            paired_at: "2026-05-23T10:00:00Z",
            nickname: "Mac",
          },
        ],
      },
      kp.secretKey,
    );

    const header = await verifyEnvelope(env);
    expect(header.version).toBe(7);
    expect(header.issuedAt).toBe(1700000000000);
    expect(Buffer.from(header.ownerPk).toString("base64")).toBe(ownerPkB64);
    expect(header.members).toHaveLength(2);
    expect(header.members[0]).toEqual({
      remoteEpk: PI_ONE_STANDARD,
      relayUrl: "wss://r",
      pairedAt: "2026-05-22T10:00:00Z",
    });
    expect(header.members[1]).toEqual({
      remoteEpk: PI_TWO_STANDARD,
      relayUrl: "wss://r",
      pairedAt: "2026-05-23T10:00:00Z",
      nickname: "Mac",
    });
  });

  test("verifies the untouched signed bytes before canonicalizing identities", async () => {
    const kp = generateEd25519Keypair();
    const logical = {
      members: [
        {
          nickname: "Mac",
          paired_at: "2026-05-23T10:00:00Z",
          relay_url: "wss://r",
          remote_epk: PI_TWO_URL_SAFE,
        },
      ],
      owner_pk: Buffer.from(kp.publicKey).toString("base64url"),
      issued_at: 1700000000000,
      version: 8,
    };
    const blob = new TextEncoder().encode(JSON.stringify(logical, null, 2));
    const env = { blob, sig: ed25519Sign(kp.secretKey, blob) };

    const header = await verifyEnvelope(env);

    expect(Buffer.from(header.ownerPk)).toEqual(Buffer.from(kp.publicKey));
    expect(header.members[0]?.remoteEpk).toBe(PI_TWO_STANDARD);
  });

  test("accepts an absent nickname", async () => {
    const kp = generateEd25519Keypair();
    const env = makeSignedEnvelope(
      {
        version: 1,
        issued_at: 1,
        owner_pk: Buffer.from(kp.publicKey).toString("base64"),
        members: [
          {
            remote_epk: PI_ONE_STANDARD,
            relay_url: "wss://r",
            paired_at: "now",
          },
        ],
      },
      kp.secretKey,
    );

    await expect(verifyEnvelope(env)).resolves.toMatchObject({
      members: [
        {
          remoteEpk: PI_ONE_STANDARD,
          relayUrl: "wss://r",
          pairedAt: "now",
        },
      ],
    });
  });

  test("accepts an explicit empty members array", async () => {
    const kp = generateEd25519Keypair();
    const env = makeSignedEnvelope(
      {
        version: 1,
        issued_at: 1,
        owner_pk: Buffer.from(kp.publicKey).toString("base64"),
        members: [],
      },
      kp.secretKey,
    );

    await expect(verifyEnvelope(env)).resolves.toMatchObject({ members: [] });
  });

  test.each([
    ["missing issued_at", { version: 1, members: [] }],
    ["missing members", { version: 1, issued_at: 1 }],
    ["wrong members type", { version: 1, issued_at: 1, members: {} }],
    ["non-object member", { version: 1, issued_at: 1, members: [null] }],
    [
      "missing remote_epk",
      {
        version: 1,
        issued_at: 1,
        members: [{ relay_url: "wss://r", paired_at: "now" }],
      },
    ],
    [
      "missing relay_url",
      {
        version: 1,
        issued_at: 1,
        members: [{ remote_epk: PI_ONE_STANDARD, paired_at: "now" }],
      },
    ],
    [
      "missing paired_at",
      {
        version: 1,
        issued_at: 1,
        members: [{ remote_epk: PI_ONE_STANDARD, relay_url: "wss://r" }],
      },
    ],
    [
      "invalid nickname type",
      {
        version: 1,
        issued_at: 1,
        members: [
          {
            remote_epk: PI_ONE_STANDARD,
            relay_url: "wss://r",
            paired_at: "now",
            nickname: 42,
          },
        ],
      },
    ],
  ])("rejects full-shape violation: %s", async (_label, partial) => {
    const kp = generateEd25519Keypair();
    const env = makeSignedEnvelope(
      {
        owner_pk: Buffer.from(kp.publicKey).toString("base64"),
        ...partial,
      },
      kp.secretKey,
    );

    await expect(verifyEnvelope(env)).rejects.toThrow();
  });

  test("rejects the whole contribution when one member key is malformed", async () => {
    const kp = generateEd25519Keypair();
    const env = makeSignedEnvelope(
      {
        version: 1,
        issued_at: 1,
        owner_pk: Buffer.from(kp.publicKey).toString("base64"),
        members: [
          {
            remote_epk: PI_ONE_STANDARD,
            relay_url: "wss://r",
            paired_at: "now",
          },
          {
            remote_epk: "bad key",
            relay_url: "wss://r",
            paired_at: "now",
          },
        ],
      },
      kp.secretKey,
    );

    await expect(verifyEnvelope(env)).rejects.toThrow(/members\[1\]\.remote_epk/);
  });

  test("rejects invalid signature (sig flipped)", async () => {
    const kp = generateEd25519Keypair();
    const env = makeSignedEnvelope(
      {
        version: 1,
        issued_at: 1,
        owner_pk: Buffer.from(kp.publicKey).toString("base64"),
        members: [],
      },
      kp.secretKey,
    );
    // Flip one byte of the signature.
    env.sig[0] = env.sig[0] ^ 0xff;
    await expect(verifyEnvelope(env)).rejects.toThrow(/signature verification failed/);
  });

  test("rejects corrupted blob (signed bytes mutated after sign)", async () => {
    const kp = generateEd25519Keypair();
    const env = makeSignedEnvelope(
      {
        version: 1,
        issued_at: 1,
        owner_pk: Buffer.from(kp.publicKey).toString("base64"),
        members: [],
      },
      kp.secretKey,
    );
    // Flip a byte in the blob → signature no longer matches.
    env.blob[10] = env.blob[10] ^ 0xff;
    // Either signature failure (most common) or JSON parse failure if we
    // happened to corrupt structural bytes — both are acceptable rejections.
    await expect(verifyEnvelope(env)).rejects.toThrow();
  });

  test("rejects envelope signed by a different keypair", async () => {
    const kpReal = generateEd25519Keypair();
    const kpAttacker = generateEd25519Keypair();
    // Header claims owner is the real key, but sig is from attacker.
    const env = makeSignedEnvelope(
      {
        version: 1,
        issued_at: 1,
        owner_pk: Buffer.from(kpReal.publicKey).toString("base64"),
        members: [],
      },
      kpAttacker.secretKey,
    );
    await expect(verifyEnvelope(env)).rejects.toThrow(/signature verification failed/);
  });

  test("rejects malformed JSON blob without echoing raw technical keys", async () => {
    const rawKey = PI_ONE_STANDARD;
    const env: MeshEnvelope = {
      blob: new TextEncoder().encode(rawKey),
      sig: new Uint8Array(64),
    };

    try {
      await verifyEnvelope(env);
      throw new Error("expected malformed JSON rejection");
    } catch (error) {
      expect((error as Error).message).toMatch(/not valid JSON/);
      expect((error as Error).message).not.toContain(rawKey.slice(0, 8));
    }
  });

  test("rejects missing required fields", async () => {
    const env: MeshEnvelope = {
      blob: new TextEncoder().encode('{"version":1}'),
      sig: new Uint8Array(64),
    };
    await expect(verifyEnvelope(env)).rejects.toThrow();
  });

  test("rejects owner_pk with wrong byte length", async () => {
    const shortKey = Buffer.from(new Uint8Array(8)).toString("base64"); // only 8 bytes
    const env: MeshEnvelope = {
      blob: canonicalBytes({
        version: 1,
        issued_at: 1,
        owner_pk: shortKey,
        members: [],
      }),
      sig: new Uint8Array(64),
    };
    await expect(verifyEnvelope(env)).rejects.toThrow(/owner_pk/);
  });
});
