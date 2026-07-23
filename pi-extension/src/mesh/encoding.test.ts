import { describe, expect, test } from "vitest";
import {
  MeshPublicKeyError,
  allocateRoutingAliases,
  bytesEqual,
  canonicalizeEd25519PublicKey,
  decodeEd25519PublicKey,
  encodeEd25519PublicKey,
  encodeRoutingAlias,
  publicKeyFingerprint,
  selectRoutingNickname,
  toBase64UrlNoPad,
} from "./encoding.js";

const TECHNICAL_KEY_BYTES = Uint8Array.from(
  { length: 32 },
  (_, index) => (index * 17 + 11) & 0xff,
);
const STANDARD_PADDED = "CxwtPk9gcYKTpLXG1+j5ChssPU5fcIGSo7TF1uf4CRo=";
const STANDARD_UNPADDED = STANDARD_PADDED.slice(0, -1);
const URL_SAFE_PADDED = STANDARD_PADDED.replaceAll("+", "-").replaceAll("/", "_");
const URL_SAFE_UNPADDED = URL_SAFE_PADDED.slice(0, -1);
const SPECIAL_ALPHABET_BYTES = Uint8Array.from(
  { length: 32 },
  (_, index) => [0xfb, 0xff, 0xfe][index % 3],
);
const SPECIAL_STANDARD = Buffer.from(SPECIAL_ALPHABET_BYTES).toString("base64");
const SPECIAL_URL_SAFE = SPECIAL_STANDARD.replaceAll("+", "-").replaceAll("/", "_");

describe("strict Ed25519 public-key encoding", () => {
  test.each([
    ["standard padded", STANDARD_PADDED],
    ["standard unpadded", STANDARD_UNPADDED],
    ["URL-safe padded", URL_SAFE_PADDED],
    ["URL-safe unpadded", URL_SAFE_UNPADDED],
  ])("canonicalizes %s input", (_label, raw) => {
    expect(decodeEd25519PublicKey(raw, "member.remote_epk")).toEqual(
      TECHNICAL_KEY_BYTES,
    );
    expect(canonicalizeEd25519PublicKey(raw, "member.remote_epk")).toBe(
      STANDARD_PADDED,
    );
  });

  test("strictly accepts both special characters in each base64 alphabet", () => {
    expect(SPECIAL_STANDARD).toContain("+");
    expect(SPECIAL_STANDARD).toContain("/");
    expect(SPECIAL_URL_SAFE).toContain("-");
    expect(SPECIAL_URL_SAFE).toContain("_");
    expect(decodeEd25519PublicKey(SPECIAL_STANDARD)).toEqual(
      SPECIAL_ALPHABET_BYTES,
    );
    expect(decodeEd25519PublicKey(SPECIAL_URL_SAFE)).toEqual(
      SPECIAL_ALPHABET_BYTES,
    );
  });

  test("rejects invalid syntax, padding, trailing bits, and key lengths", () => {
    const mixedAlphabet = SPECIAL_STANDARD.replace("+", "-");
    const base64Alphabet =
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    const finalSextet = STANDARD_UNPADDED.at(-1)!;
    const finalSextetIndex = base64Alphabet.indexOf(finalSextet);
    const nonZeroTrailingBits =
      STANDARD_UNPADDED.slice(0, -1) + base64Alphabet[finalSextetIndex + 1];
    const thirtyOneBytes = Buffer.from(new Uint8Array(31)).toString("base64");
    const thirtyThreeBytes = Buffer.from(new Uint8Array(33)).toString("base64");

    expect(finalSextetIndex % 4).toBe(0);
    for (const raw of [
      "",
      " ",
      ` ${STANDARD_PADDED}`,
      `${STANDARD_PADDED} `,
      "bad key",
      mixedAlphabet,
      `${STANDARD_UNPADDED.slice(0, 8)}=${STANDARD_UNPADDED.slice(9)}`,
      `${STANDARD_PADDED}=`,
      `${STANDARD_UNPADDED}==`,
      nonZeroTrailingBits,
      thirtyOneBytes,
      thirtyThreeBytes,
    ]) {
      expect(() =>
        canonicalizeEd25519PublicKey(raw, "member.remote_epk"),
      ).toThrowError(MeshPublicKeyError);
    }
  });

  test("does not echo rejected key text in the error", () => {
    const raw = "secret-looking-invalid-key";
    try {
      canonicalizeEd25519PublicKey(raw, "owner_pk");
      throw new Error("expected key rejection");
    } catch (error) {
      expect(error).toBeInstanceOf(MeshPublicKeyError);
      expect((error as Error).message).not.toContain(raw);
      expect((error as MeshPublicKeyError).field).toBe("owner_pk");
    }
  });

  test("encodes only exact 32-byte keys and exposes stable derived forms", () => {
    expect(encodeEd25519PublicKey(TECHNICAL_KEY_BYTES)).toBe(STANDARD_PADDED);
    expect(toBase64UrlNoPad(TECHNICAL_KEY_BYTES)).toBe(URL_SAFE_UNPADDED);
    expect(publicKeyFingerprint(TECHNICAL_KEY_BYTES)).toBe("349e1858");
    expect(() => encodeEd25519PublicKey(new Uint8Array(31))).toThrowError(
      MeshPublicKeyError,
    );
    expect(() => encodeEd25519PublicKey(new Uint8Array(33))).toThrowError(
      MeshPublicKeyError,
    );
  });
});

describe("routing aliases", () => {
  const sharedPrefixBytesA = new Uint8Array(32);
  const sharedPrefixBytesB = new Uint8Array(32);
  sharedPrefixBytesB[31] = 1;
  const sharedPrefixKeyA = Buffer.from(sharedPrefixBytesA).toString("base64");
  const sharedPrefixKeyB = Buffer.from(sharedPrefixBytesB).toString("base64");
  const sharedPrefixUrlA = toBase64UrlNoPad(sharedPrefixBytesA);
  const sharedPrefixUrlB = toBase64UrlNoPad(sharedPrefixBytesB);

  test("percent-encodes every unsafe UTF-8 byte with uppercase hex", () => {
    expect(encodeRoutingAlias("A:B%~ é")).toBe(
      "A%3AB%25%7E%20%C3%A9",
    );
    expect(encodeRoutingAlias("AZaz09._-")).toBe("AZaz09._-");
    expect(encodeRoutingAlias("\u0000\n")).toBe("%00%0A");
  });

  test("selects the raw nickname by encoded ASCII order, independent of input order", () => {
    const candidates = ["z", "é", ":", ""];
    expect(selectRoutingNickname(candidates)).toBe(":");
    expect(selectRoutingNickname([...candidates].reverse())).toBe(":");
    expect(selectRoutingNickname(["", ""])).toBeUndefined();
  });

  test("uses the canonical key fallback for an empty nickname and encodes once", () => {
    const allocated = allocateRoutingAliases([
      { pcPubkey: URL_SAFE_UNPADDED, nickname: "" },
      { pcPubkey: SPECIAL_STANDARD, nickname: "A:B" },
    ]);

    expect(allocated.get(STANDARD_PADDED)).toBe("pc-CxwtPk9g");
    expect(allocated.get(SPECIAL_STANDARD)).toBe("A%3AB");
  });

  test("suffixes every member of a colliding group and expands through all 43 key characters", () => {
    expect(sharedPrefixUrlA).toHaveLength(43);
    expect(sharedPrefixUrlA.slice(0, 42)).toBe(
      sharedPrefixUrlB.slice(0, 42),
    );

    const allocated = allocateRoutingAliases([
      { pcPubkey: sharedPrefixKeyB, nickname: "Mac" },
      { pcPubkey: SPECIAL_STANDARD, nickname: "Other" },
      { pcPubkey: sharedPrefixKeyA, nickname: "Mac" },
    ]);

    expect(allocated.get(sharedPrefixKeyA)).toBe(`Mac~${sharedPrefixUrlA}`);
    expect(allocated.get(sharedPrefixKeyB)).toBe(`Mac~${sharedPrefixUrlB}`);
    expect(allocated.get(SPECIAL_STANDARD)).toBe("Other");
    expect(new Set(allocated.values()).size).toBe(allocated.size);
  });

  test("reserves fallback bases before resolving nickname collisions", () => {
    const fallbackBase = `pc-${sharedPrefixUrlA.slice(0, 8)}`;
    const allocated = allocateRoutingAliases([
      { pcPubkey: sharedPrefixKeyA },
      { pcPubkey: STANDARD_PADDED, nickname: fallbackBase },
    ]);

    expect(allocated.get(sharedPrefixKeyA)).toMatch(
      new RegExp(`^${fallbackBase}~`),
    );
    expect(allocated.get(STANDARD_PADDED)).toMatch(
      new RegExp(`^${fallbackBase}~`),
    );
    expect(new Set(allocated.values()).size).toBe(2);
  });

  test("is stable across input order and returns canonical-key entries", () => {
    const inputs = [
      { pcPubkey: URL_SAFE_UNPADDED, nickname: "same" },
      { pcPubkey: SPECIAL_STANDARD, nickname: "same" },
      { pcPubkey: sharedPrefixKeyB, nickname: "unique" },
    ] as const;
    const forward = [...allocateRoutingAliases(inputs).entries()];
    const reverse = [
      ...allocateRoutingAliases([...inputs].reverse()).entries(),
    ];

    expect(reverse).toEqual(forward);
    expect(forward.map(([key]) => key)).toEqual(
      [...forward.map(([key]) => key)].sort(),
    );
    expect(new Set(forward.map(([, alias]) => alias)).size).toBe(
      forward.length,
    );
  });

  test("rejects duplicate canonical identities even with different raw encodings", () => {
    expect(() =>
      allocateRoutingAliases([
        { pcPubkey: STANDARD_PADDED, nickname: "one" },
        { pcPubkey: URL_SAFE_UNPADDED, nickname: "two" },
      ]),
    ).toThrow(/duplicate routing identity/);
  });
});

describe("bytesEqual", () => {
  test("identical arrays → true", () => {
    const a = new Uint8Array([1, 2, 3, 4, 5]);
    const b = new Uint8Array([1, 2, 3, 4, 5]);
    expect(bytesEqual(a, b)).toBe(true);
  });

  test("empty arrays → true", () => {
    expect(bytesEqual(new Uint8Array(0), new Uint8Array(0))).toBe(true);
  });

  test("different lengths → false", () => {
    const a = new Uint8Array([1, 2, 3]);
    const b = new Uint8Array([1, 2, 3, 4]);
    expect(bytesEqual(a, b)).toBe(false);
  });

  test("different byte at one position → false", () => {
    const a = new Uint8Array([1, 2, 3, 4]);
    const b = new Uint8Array([1, 2, 9, 4]);
    expect(bytesEqual(a, b)).toBe(false);
  });

  test("different byte at last position → false (no early-out skipping the tail)", () => {
    const a = new Uint8Array([1, 2, 3, 4]);
    const b = new Uint8Array([1, 2, 3, 5]);
    expect(bytesEqual(a, b)).toBe(false);
  });
});
