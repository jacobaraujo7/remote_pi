import { createHash } from "node:crypto";

/**
 * Base64 + byte-array helpers shared by the mesh module.
 *
 * **Why this exists**: the mesh protocol crosses three languages (Dart in
 * the app, Rust in the relay, TypeScript here). Each language's default
 * base64 encoder picks a different variant — `dart:convert.base64Encode`
 * emits **standard** (`+`, `/`, `=`-padded), while the app's pairing layer
 * historically emitted **URL-safe** (`-`, `_`, no padding) in some places.
 * String comparison on those two encodings fails even when the underlying
 * 32 bytes are identical, producing silent self-revocations (see
 * `plan/24` Wave 3 incident report).
 *
 * The fix is to never compare base64 strings — decode both sides to bytes
 * and compare bytes through the strict Ed25519 boundary helper.
 */

const ED25519_PUBLIC_KEY_BYTES = 32;

export class MeshPublicKeyError extends Error {
  constructor(
    readonly field: string,
    message: string,
  ) {
    super(`${field}: ${message}`);
    this.name = "MeshPublicKeyError";
  }
}

/**
 * Strictly decodes a 32-byte Ed25519 public key accepted at a protocol boundary.
 * The rejected value is deliberately absent from every error message.
 */
export function decodeEd25519PublicKey(
  raw: string,
  field = "public key",
): Uint8Array {
  if (typeof raw !== "string" || raw.length === 0) {
    throw new MeshPublicKeyError(field, "invalid base64 encoding");
  }

  const hasStandardOnlyCharacters = /[+/]/.test(raw);
  const hasUrlSafeOnlyCharacters = /[-_]/.test(raw);
  if (hasStandardOnlyCharacters && hasUrlSafeOnlyCharacters) {
    throw new MeshPublicKeyError(field, "mixed base64 alphabets");
  }

  const firstPaddingIndex = raw.indexOf("=");
  const body = firstPaddingIndex === -1 ? raw : raw.slice(0, firstPaddingIndex);
  const padding = firstPaddingIndex === -1 ? "" : raw.slice(firstPaddingIndex);
  const bodyPattern = hasUrlSafeOnlyCharacters
    ? /^[A-Za-z0-9_-]+$/
    : /^[A-Za-z0-9+/]+$/;
  if (
    !bodyPattern.test(body) ||
    (padding !== "" && !/^={1,2}$/.test(padding))
  ) {
    throw new MeshPublicKeyError(field, "invalid base64 encoding");
  }

  const requiredPaddingLength = (4 - (body.length % 4)) % 4;
  if (
    requiredPaddingLength === 3 ||
    (padding.length > 0 && padding.length !== requiredPaddingLength)
  ) {
    throw new MeshPublicKeyError(field, "invalid base64 padding");
  }

  const normalizedBody = body.replaceAll("-", "+").replaceAll("_", "/");
  const normalizedPadded = normalizedBody + "=".repeat(requiredPaddingLength);
  const bytes = new Uint8Array(Buffer.from(normalizedPadded, "base64"));
  if (bytes.length !== ED25519_PUBLIC_KEY_BYTES) {
    throw new MeshPublicKeyError(
      field,
      `wrong length (${bytes.length}, expected ${ED25519_PUBLIC_KEY_BYTES})`,
    );
  }

  const canonicalPadded = Buffer.from(bytes).toString("base64");
  const canonicalUnpadded = canonicalPadded.replace(/=+$/, "");
  const normalizedInput = normalizedBody + padding;
  if (
    normalizedInput !== canonicalPadded &&
    normalizedInput !== canonicalUnpadded
  ) {
    throw new MeshPublicKeyError(field, "non-canonical base64 trailing bits");
  }

  return bytes;
}

/** Returns an Ed25519 public key in RFC 4648 standard padded base64. */
export function encodeEd25519PublicKey(
  bytes: Uint8Array,
  field = "public key",
): string {
  if (!(bytes instanceof Uint8Array) || bytes.length !== ED25519_PUBLIC_KEY_BYTES) {
    const length = bytes instanceof Uint8Array ? bytes.length : 0;
    throw new MeshPublicKeyError(
      field,
      `wrong length (${length}, expected ${ED25519_PUBLIC_KEY_BYTES})`,
    );
  }
  return Buffer.from(bytes).toString("base64");
}

/** Decodes then returns an Ed25519 public key in canonical standard base64. */
export function canonicalizeEd25519PublicKey(
  raw: string,
  field = "public key",
): string {
  return encodeEd25519PublicKey(decodeEd25519PublicKey(raw, field), field);
}

/** RFC 4648 URL-safe base64 without padding. */
export function toBase64UrlNoPad(bytes: Uint8Array): string {
  return Buffer.from(bytes)
    .toString("base64")
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replace(/=+$/, "");
}

/** Stable metadata-only fingerprint for a validated public key. */
export function publicKeyFingerprint(bytes: Uint8Array): string {
  return createHash("sha256").update(bytes).digest("hex").slice(0, 8);
}

export interface RoutingAliasInput {
  readonly pcPubkey: string;
  readonly nickname?: string;
}

function isRoutingAliasSafeByte(byte: number): boolean {
  return (
    (byte >= 0x41 && byte <= 0x5a) ||
    (byte >= 0x61 && byte <= 0x7a) ||
    (byte >= 0x30 && byte <= 0x39) ||
    byte === 0x2e ||
    byte === 0x5f ||
    byte === 0x2d
  );
}

/** Percent-encodes a nickname into the receiver-local routing grammar. */
export function encodeRoutingAlias(rawNickname: string): string {
  let encoded = "";
  for (const byte of Buffer.from(rawNickname, "utf8")) {
    encoded += isRoutingAliasSafeByte(byte)
      ? String.fromCharCode(byte)
      : `%${byte.toString(16).toUpperCase().padStart(2, "0")}`;
  }
  return encoded;
}

/** Selects a raw nickname by encoded ASCII order, then raw UTF-8 bytes. */
export function selectRoutingNickname(
  candidates: readonly string[],
): string | undefined {
  let selected: string | undefined;
  let selectedEncoded: string | undefined;
  for (const candidate of candidates) {
    if (candidate.length === 0) continue;
    const encoded = encodeRoutingAlias(candidate);
    if (
      selected === undefined ||
      encoded < selectedEncoded! ||
      (encoded === selectedEncoded &&
        Buffer.compare(Buffer.from(candidate), Buffer.from(selected)) < 0)
    ) {
      selected = candidate;
      selectedEncoded = encoded;
    }
  }
  return selected;
}

interface PreparedRoutingAlias {
  readonly pcPubkey: string;
  readonly keyUrl: string;
  readonly base: string;
}

/**
 * Allocates a deterministic bijection from canonical Pi key to effective alias.
 * Every colliding base is suffixed with an adaptively expanded key prefix.
 */
export function allocateRoutingAliases(
  inputs: readonly RoutingAliasInput[],
): ReadonlyMap<string, string> {
  const preparedByKey = new Map<string, PreparedRoutingAlias>();
  for (const [index, input] of inputs.entries()) {
    const keyBytes = decodeEd25519PublicKey(
      input.pcPubkey,
      `routingAliases[${index}].pcPubkey`,
    );
    const pcPubkey = encodeEd25519PublicKey(keyBytes);
    if (preparedByKey.has(pcPubkey)) {
      throw new Error("mesh: duplicate routing identity");
    }
    const keyUrl = toBase64UrlNoPad(keyBytes);
    const base = input.nickname
      ? encodeRoutingAlias(input.nickname)
      : `pc-${keyUrl.slice(0, 8)}`;
    preparedByKey.set(pcPubkey, { pcPubkey, keyUrl, base });
  }

  const prepared = [...preparedByKey.values()].sort((left, right) =>
    left.pcPubkey < right.pcPubkey
      ? -1
      : left.pcPubkey > right.pcPubkey
        ? 1
        : 0,
  );
  const groupsByBase = new Map<string, PreparedRoutingAlias[]>();
  for (const identity of prepared) {
    const group = groupsByBase.get(identity.base);
    if (group) group.push(identity);
    else groupsByBase.set(identity.base, [identity]);
  }

  const reservedBases = new Set(groupsByBase.keys());
  const aliasByKey = new Map<string, string>();
  const allocatedAliases = new Set<string>();
  for (const group of groupsByBase.values()) {
    if (group.length !== 1) continue;
    const identity = group[0]!;
    aliasByKey.set(identity.pcPubkey, identity.base);
    allocatedAliases.add(identity.base);
  }

  const collidingGroups = [...groupsByBase.entries()]
    .filter(([, group]) => group.length > 1)
    .sort(([left], [right]) => (left < right ? -1 : left > right ? 1 : 0));
  for (const [base, group] of collidingGroups) {
    const fullPrefixLength = group[0]!.keyUrl.length;
    let allocated = false;
    for (let prefixLength = 8; prefixLength <= fullPrefixLength; prefixLength++) {
      const candidates = group.map(
        (identity) => `${base}~${identity.keyUrl.slice(0, prefixLength)}`,
      );
      const uniqueCandidates = new Set(candidates);
      const conflicts = candidates.some(
        (candidate) =>
          reservedBases.has(candidate) || allocatedAliases.has(candidate),
      );
      if (uniqueCandidates.size !== group.length || conflicts) continue;

      for (let index = 0; index < group.length; index++) {
        const identity = group[index]!;
        const alias = candidates[index]!;
        aliasByKey.set(identity.pcPubkey, alias);
        allocatedAliases.add(alias);
      }
      allocated = true;
      break;
    }
    if (!allocated) {
      throw new Error("mesh: routing alias collision invariant failed");
    }
  }

  return new Map(
    prepared.map((identity) => [
      identity.pcPubkey,
      aliasByKey.get(identity.pcPubkey)!,
    ]),
  );
}

/**
 * Constant-time-ish byte equality for validated public keys. Returns false
 * immediately on length mismatch.
 *
 * Not strictly constant-time — Ed25519 pubkeys aren't secrets, so the
 * short-circuit on length and the byte-by-byte compare are acceptable.
 */
export function bytesEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) return false;
  }
  return true;
}
