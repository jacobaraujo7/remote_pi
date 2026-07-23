/**
 * Mesh-membership types — pi-extension side. Mirrors the wire shape defined
 * in plan/24-mesh-membership.md and must stay bit-compatible with the Dart
 * (app) and Rust (relay) implementations of the same protocol.
 *
 * On the wire, JSON field names are `snake_case` (per the plan); this module
 * exposes `camelCase` for ergonomic TS use. Conversion happens at the
 * (de)serialization boundary in `verify.ts` / `canonical.ts`.
 */

export interface MeshMember {
  /** Pi Ed25519 pubkey, canonical RFC 4648 standard base64 with padding. */
  remoteEpk: string;
  /** Relay URL where this member registers. */
  relayUrl: string;
  /** ISO-8601 timestamp of when the pairing happened. */
  pairedAt: string;
  /** Optional Owner-set label. */
  nickname?: string;
}

export interface MeshHeader {
  /** Owner-scoped monotonic counter. Higher = newer. */
  version: number;
  /** Issued-at, ms since epoch. */
  issuedAt: number;
  /** Owner's Ed25519 pubkey, raw 32 bytes. */
  ownerPk: Uint8Array;
  members: MeshMember[];
}

export interface MeshEnvelope {
  /** Canonical JSON bytes of the header (snake_case keys, sorted, no whitespace). */
  blob: Uint8Array;
  /** Ed25519 signature of `blob`, 64 bytes. */
  sig: Uint8Array;
}
