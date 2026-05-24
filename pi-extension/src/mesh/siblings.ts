import { createHash } from "node:crypto";
import type { MeshClient } from "./client.js";
import { verifyEnvelope } from "./verify.js";
import { bytesEqual, decodeB64Any } from "./encoding.js";

/**
 * Plan/25 — discover Pis-irmãos of every Owner this Pi is paired with.
 *
 * For each Owner pubkey (from `peers.json`), pulls the latest signed
 * `mesh_versions` blob from the relay, verifies it, and walks the members
 * list to extract all Pi-pubkeys other than this one. The same member may
 * appear under multiple Owners — we de-dupe by Pi-pubkey.
 *
 * Returned `pcLabel` priority:
 *   1. `member.nickname` (set by the Owner at pairing time)
 *   2. First 8 chars of the base64-encoded Pi-pubkey (defensive fallback —
 *      keeps cross-PC addressing working even when nicknames are missing)
 *
 * Tolerates per-owner errors: a missing/malformed blob for one Owner does
 * NOT prevent siblings of other Owners from being discovered. Logs and
 * continues.
 */

export interface SiblingPi {
  pcLabel: string;
  pcPubkey: string;
}

export interface DiscoverSelfLabelResult {
  /** This Pi's effective `pc_label` (nickname when any Owner has set one;
   *  pubkey prefix fallback otherwise). */
  selfPcLabel: string;
}

export interface DiscoverOptions {
  client: MeshClient;
  ownerEpks: string[];
  myPubkey: Uint8Array;
  log?: { warn(msg: string): void };
}

const FALLBACK_LABEL_LEN = 8;

/** Derive the fallback label from a base64-encoded Pi pubkey. */
export function fallbackLabel(pcPubkey: string): string {
  return pcPubkey.slice(0, FALLBACK_LABEL_LEN);
}

/**
 * Resolve self pc_label by scanning every Owner's mesh blob for an entry
 * matching `myPubkey`. Returns the first nickname found; falls back to the
 * base64 prefix when no Owner has labeled us.
 */
export async function discoverSelfLabel(
  opts: DiscoverOptions,
): Promise<DiscoverSelfLabelResult> {
  const log = opts.log ?? { warn: (m) => console.warn(m) };
  const myB64 = Buffer.from(opts.myPubkey).toString("base64");

  for (const ownerEpk of opts.ownerEpks) {
    try {
      const env = await _fetchOwnerBlob(opts.client, ownerEpk);
      if (!env) continue;
      const header = await verifyEnvelope(env);
      for (const m of header.members) {
        if (bytesEqual(decodeB64Any(m.remoteEpk), opts.myPubkey) && m.nickname) {
          return { selfPcLabel: m.nickname };
        }
      }
    } catch (err) {
      log.warn(`[siblings] self-label fetch failed for owner ${ownerEpk.slice(0, 8)}…: ${String(err)}`);
    }
  }
  return { selfPcLabel: fallbackLabel(myB64) };
}

/**
 * Enumerate Pis-irmãos across all Owners. De-duplicated by `pcPubkey`.
 * Excludes `myPubkey`.
 *
 * Label resolution rule (anti-asymmetry — see plan/25 Wave D fix):
 *   1. Scan EVERY Owner blob first, collecting all distinct sibling
 *      pubkeys and any nicknames seen for each.
 *   2. For each pubkey, pick label as: first nickname encountered (if
 *      any Owner labeled this Pi), else `fallbackLabel(pubkey)`.
 *
 * Why: if two Pis are paired to the same set of Owners but only some
 * Owners labeled them, naive first-wins dedup can pick the unlabeled
 * occurrence and discard the labeled one — producing different
 * `pc_label`s between Pis (PC-A's `discoverSelfLabel` skips non-labeled,
 * but old `discoverSiblings` didn't). The asymmetry triggers anti-spoof
 * drops in `broker_remote.handleIncoming`. This rule keeps both sides in
 * sync: nickname always wins over fallback.
 */
export async function discoverSiblings(opts: DiscoverOptions): Promise<SiblingPi[]> {
  const log = opts.log ?? { warn: (m) => console.warn(m) };
  // pcPubkey → first nickname seen across owners (or undefined if none).
  const labels = new Map<string, string | undefined>();

  for (const ownerEpk of opts.ownerEpks) {
    try {
      const env = await _fetchOwnerBlob(opts.client, ownerEpk);
      if (!env) continue;
      const header = await verifyEnvelope(env);
      for (const m of header.members) {
        if (bytesEqual(decodeB64Any(m.remoteEpk), opts.myPubkey)) continue;
        const existing = labels.get(m.remoteEpk);
        if (existing) continue;  // first-nickname wins; never overwrite a real label
        if (m.nickname) {
          labels.set(m.remoteEpk, m.nickname);
        } else if (!labels.has(m.remoteEpk)) {
          // Seen pubkey for the first time, no nickname yet — record the
          // slot so later iterations may upgrade it via the `if (existing)
          // continue` check above only matching truthy nicknames.
          labels.set(m.remoteEpk, undefined);
        }
      }
    } catch (err) {
      log.warn(`[siblings] discover failed for owner ${ownerEpk.slice(0, 8)}…: ${String(err)}`);
    }
  }

  const out: SiblingPi[] = [];
  for (const [pcPubkey, nickname] of labels) {
    out.push({ pcPubkey, pcLabel: nickname ?? fallbackLabel(pcPubkey) });
  }
  return out;
}

async function _fetchOwnerBlob(client: MeshClient, ownerEpk: string) {
  const ownerPk = Uint8Array.from(Buffer.from(ownerEpk, "base64"));
  const hash = createHash("sha256").update(ownerPk).digest("hex");
  return client.get(hash);
}
