import { mkdir, readFile, writeFile, chmod, unlink } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { AsyncEntry } from "@napi-rs/keyring";
import { generateEd25519Keypair, type Ed25519Keypair } from "./crypto.js";

/**
 * Pi-secret storage (plan/27 Wave E1).
 *
 * The Ed25519 long-term identity of this Pi lives in the platform keyring
 * via `@napi-rs/keyring` (Keychain on macOS, libsecret on Linux desktop,
 * Credential Manager on Windows — DPAPI-backed). When the keyring is
 * unavailable (headless Linux without a D-Bus session, Docker containers,
 * VPS without GNOME Keyring/KWallet running) we fall back to a
 * file-backed store at `~/.pi/remote/identity.json` with `0o600`
 * permissions and the parent dir at `0o700`.
 *
 * **Migration**: previous builds used `keytar` against service
 * `dev.remotepi.mac`. This module reads from the old service if the new
 * service is empty, copies the entry to the new service `dev.remotepi.pi`,
 * and deletes the old one. Both keytar and `@napi-rs/keyring` address the
 * same OS-level credential store on every supported platform, so the read
 * succeeds without keeping the deprecated `keytar` dependency.
 */

const NEW_SERVICE = "dev.remotepi.pi";  // platform-neutral
const OLD_SERVICE = "dev.remotepi.mac"; // legacy keytar service (pre-2026-05-25)
const ACCOUNT = "longterm-ed25519";

const PI_DIR = join(homedir(), ".pi", "remote");
const IDENTITY_FILE = join(PI_DIR, "identity.json");
const PEERS_PATH = join(PI_DIR, "peers.json");

// ── KeyStore abstraction ─────────────────────────────────────────────────────

/**
 * Minimal backend interface for credential reads/writes. Swappable so
 * tests can inject a controlled in-memory store without touching the OS
 * keyring (which is shared with the developer's own credentials).
 *
 * Errors thrown by `read`/`write`/`delete` signal "backend unavailable on
 * this platform" — callers fall back to the file store on first failure.
 * Returning `undefined` from `read` means "no such entry" (a normal,
 * non-error condition).
 */
export interface KeyStoreBackend {
  read(service: string, account: string): Promise<string | undefined>;
  write(service: string, account: string, value: string): Promise<void>;
  delete(service: string, account: string): Promise<boolean>;
}

class NapiKeyringBackend implements KeyStoreBackend {
  async read(service: string, account: string): Promise<string | undefined> {
    const entry = new AsyncEntry(service, account);
    return entry.getPassword();  // returns undefined on no-entry
  }
  async write(service: string, account: string, value: string): Promise<void> {
    const entry = new AsyncEntry(service, account);
    await entry.setPassword(value);
  }
  async delete(service: string, account: string): Promise<boolean> {
    const entry = new AsyncEntry(service, account);
    try {
      return await entry.deleteCredential();
    } catch {
      return false;
    }
  }
}

let _backend: KeyStoreBackend | null = null;

function _getBackend(): KeyStoreBackend {
  if (!_backend) _backend = new NapiKeyringBackend();
  return _backend;
}

/** Test-only: swap (or clear with `null`) the keyring backend. */
export function _setKeyStoreBackendForTest(backend: KeyStoreBackend | null): void {
  _backend = backend;
}

// ── Keypair serialization ────────────────────────────────────────────────────

interface SerializedKeypair {
  pk: string;
  sk: string;
}

function _serialize(kp: Ed25519Keypair): string {
  const payload: SerializedKeypair = {
    pk: Buffer.from(kp.publicKey).toString("base64"),
    sk: Buffer.from(kp.secretKey).toString("base64"),
  };
  return JSON.stringify(payload);
}

function _deserialize(stored: string): Ed25519Keypair {
  const parsed = JSON.parse(stored) as SerializedKeypair;
  return {
    publicKey: Buffer.from(parsed.pk, "base64"),
    secretKey: Buffer.from(parsed.sk, "base64"),
  };
}

// ── File fallback (headless Linux) ──────────────────────────────────────────

async function _readKeypairFromFile(): Promise<Ed25519Keypair | null> {
  try {
    const raw = await readFile(IDENTITY_FILE, "utf8");
    return _deserialize(raw);
  } catch {
    return null;
  }
}

async function _writeKeypairToFile(kp: Ed25519Keypair): Promise<void> {
  await mkdir(PI_DIR, { recursive: true, mode: 0o700 });
  // Best-effort tighten of the dir in case it pre-existed with looser
  // permissions (mkdir's mode is only applied to NEW dirs).
  try { await chmod(PI_DIR, 0o700); } catch { /* not fatal */ }
  await writeFile(IDENTITY_FILE, _serialize(kp), { mode: 0o600 });
  try { await chmod(IDENTITY_FILE, 0o600); } catch { /* not fatal */ }
}

// ── Public API ──────────────────────────────────────────────────────────────

/**
 * Returns the Pi-secret Ed25519 keypair, generating + persisting one on
 * first call. Resolution order:
 *   1. New keyring service `dev.remotepi.pi`
 *   2. Old keyring service `dev.remotepi.mac` (migrate → step 1, delete old)
 *   3. File `~/.pi/remote/identity.json` (headless-Linux fallback)
 *   4. Generate a fresh keypair + persist to the first available backend
 *
 * Idempotent: subsequent calls return the same identity. The migration
 * runs at most once per machine (the old entry is deleted after copy).
 */
export async function getOrCreateEd25519Keypair(): Promise<Ed25519Keypair> {
  const backend = _getBackend();

  // ── Path A: keyring ────────────────────────────────────────────────────
  try {
    const existing = await backend.read(NEW_SERVICE, ACCOUNT);
    if (existing) return _deserialize(existing);

    const legacy = await backend.read(OLD_SERVICE, ACCOUNT);
    if (legacy) {
      const kp = _deserialize(legacy);
      await backend.write(NEW_SERVICE, ACCOUNT, legacy);
      await backend.delete(OLD_SERVICE, ACCOUNT);
      // Silent migration: writing the chat surface would be premature
      // (Pi SDK isn't bound yet at this point in boot) and console
      // output bleeds outside the TUI. The presence of an entry under
      // NEW_SERVICE is itself the audit signal — re-running migration
      // is idempotent and harmless.
      return kp;
    }

    // Neither entry exists — generate and save to new service.
    const fresh = generateEd25519Keypair();
    await backend.write(NEW_SERVICE, ACCOUNT, _serialize(fresh));
    return fresh;
  } catch (err) {
    // Path B: file fallback (typically headless Linux without a D-Bus
    // session). Silent in the chat panel — for daemon mode, the
    // existence of `~/.pi/remote/identity.json` IS the signal that the
    // keyring path failed. Document this in CLAUDE.md / PROTOCOL.md
    // so headless users know what to look for.
    void err;
    const fromFile = await _readKeypairFromFile();
    if (fromFile) return fromFile;
    const fresh = generateEd25519Keypair();
    await _writeKeypairToFile(fresh);
    return fresh;
  }
}

// ── peers.json ────────────────────────────────────────────────────────────────

export interface PeerRecord {
  name: string;
  remote_epk: string; // relay-authenticated app peer key, base64 standard, 32B Ed25519
  paired_at: string;  // ISO-8601
  /** Owner signing public key proven by pair_request_v2. */
  owner_pk?: string;
  /** Relay-authenticated app peer key bound into pair_request_v2. */
  app_peer_pk?: string;
}

export async function listPeers(): Promise<PeerRecord[]> {
  try {
    const raw = await readFile(PEERS_PATH, "utf8");
    const parsed = JSON.parse(raw) as { peers: PeerRecord[] };
    return parsed.peers ?? [];
  } catch {
    return [];
  }
}

export async function addPeer(record: PeerRecord): Promise<void> {
  const peers = await listPeers();
  const idx = peers.findIndex((p) => p.remote_epk === record.remote_epk);
  if (idx >= 0) {
    peers[idx] = record; // idempotent re-pair
  } else {
    peers.push(record);
  }
  await mkdir(dirname(PEERS_PATH), { recursive: true });
  await writeFile(PEERS_PATH, JSON.stringify({ peers }, null, 2));
}

/**
 * Returns the set of distinct Owner signing public keys in peers.json.
 *
 * New pair_request_v2 records store `owner_pk` separately from the
 * relay-authenticated app peer key. Legacy records used `remote_epk` for the
 * Owner key, so keep that fallback for backward compatibility.
 */
export async function listOwnerPubkeys(): Promise<string[]> {
  const peers = await listPeers();
  const seen = new Set<string>();
  for (const p of peers) seen.add(p.owner_pk ?? p.remote_epk);
  return [...seen];
}

export async function removePeer(remoteEpk: string): Promise<boolean> {
  const peers = await listPeers();
  const filtered = peers.filter((p) => p.remote_epk !== remoteEpk);
  if (filtered.length === peers.length) return false;
  await mkdir(dirname(PEERS_PATH), { recursive: true });
  await writeFile(PEERS_PATH, JSON.stringify({ peers: filtered }, null, 2));
  return true;
}

// ── Test-only helpers ────────────────────────────────────────────────────────

/** Test-only: expose the identity-file path so tests can clean it. */
export const _IDENTITY_FILE_FOR_TEST = IDENTITY_FILE;
/** Test-only: expose unlink for cleanup. */
export const _unlinkIdentityFileForTest = async (): Promise<void> => {
  try { await unlink(IDENTITY_FILE); } catch { /* fine if missing */ }
};
