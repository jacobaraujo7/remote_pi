import { writeFileSync } from "node:fs";
import { mkdir, readFile, writeFile, chmod, unlink } from "node:fs/promises";
import { dirname, join } from "node:path";
import { generateEd25519Keypair, type Ed25519Keypair } from "./crypto.js";
import { canonicalizeEd25519PublicKey } from "../mesh/encoding.js";
import { remotePiHome } from "../paths.js";

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

/**
 * The keyring read can THROW transiently rather than permanently — most
 * notably a macOS Keychain that's still locked right after login/wake (the
 * machine sat idle for days). Treating that throw as "backend unavailable"
 * and minting a fresh identity silently orphans the paired key (the
 * "lost pairing after a week idle" failure). So we retry the read a few times
 * before ever concluding the keyring is truly unavailable. Overridable for
 * tests via `_setKeyringRetryForTest`. */
let _keyringReadAttempts = 3;
let _keyringRetryDelayMs = 300;

/** Raised when the keyring is unreadable on a platform where it's a core OS
 *  service (macOS Keychain, Windows Credential Manager) AND no prior file
 *  identity exists. We refuse to generate a NEW identity here because that
 *  would break existing pairing — the caller surfaces this so the user can
 *  unlock the keychain and retry instead of silently re-pairing. */
export class KeyringUnavailableError extends Error {
  constructor(cause: unknown) {
    super(
      "Platform keyring is unreadable and no file-backed identity exists. " +
      "Refusing to generate a NEW identity (that would break existing " +
      "pairing). Unlock your keychain / start your secret service and retry. " +
      "Set REMOTE_PI_ALLOW_FILE_IDENTITY=1 to force a file-backed identity. " +
      `Cause: ${String(cause)}`,
    );
    this.name = "KeyringUnavailableError";
  }
}

/** Raised when no identity can be resolved (keyring unreadable, no identity
 *  file) BUT `peers.json` already lists paired devices. Minting a fresh key
 *  here would make SelfRevoke wipe those pairings — see issues #95 / #69. */
export class PairedIdentityMissingError extends Error {
  constructor(pairedCount: number, cause: unknown) {
    super(
      `No identity could be read, but ${pairedCount} device(s) are already ` +
      "paired. Refusing to generate a NEW identity — that would revoke every " +
      "paired device. This usually means this process cannot reach the same " +
      "keyring as the session that paired (e.g. a systemd --user daemon vs. " +
      "your desktop session). Fix the service's keyring access, or pin the " +
      "identity by copying the paired keypair to ~/.pi/remote/identity.json " +
      "(0600), which both contexts read first. " +
      `Cause: ${String(cause)}`,
    );
    this.name = "PairedIdentityMissingError";
  }
}

const PI_DIR = remotePiHome();
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

/**
 * Per-operation timeout for native keyring calls (gnome-keyring / libsecret
 * via @napi-rs/keyring). A healthy secret service settles in milliseconds; 3s
 * is generous. The point is NOT speed — it is converting a HANG into a thrown
 * error. The native getPassword()/setPassword() can block indefinitely when
 * gnome-keyring waits on a GUI authorization prompt that cannot be shown in
 * a headless / tmux / non-interactive context. A hang never settles, so
 * without this guard the promise never rejects and the retry + file-fallback
 * logic in getOrCreateEd25519Keypair() is unreachable — freezing the entire
 * /remote-pi pair bootstrap. Raising a real error here lets that fallback
 * chain run as designed.
 */
const KEYRING_OP_TIMEOUT_MS = 3_000;

function _withTimeout<T>(
  p: Promise<T>,
  op: string,
  ms: number = KEYRING_OP_TIMEOUT_MS,
): Promise<T> {
  return Promise.race([
    p,
    new Promise<T>((_, reject) =>
      setTimeout(() => reject(new Error(`keyring ${op} timed out after ${ms}ms`)), ms),
    ),
  ]);
}

/**
 * Lazily loaded `@napi-rs/keyring` binding — issue #113.
 *
 * A STATIC `import { AsyncEntry } from "@napi-rs/keyring"` is evaluated when
 * the extension module is loaded, so a native binding that cannot be resolved
 * takes the WHOLE extension down at load time ("Failed to load extension …:
 * Cannot find native binding"). That happens on a Bun-compiled `pi`: the
 * loader's first branch (`require("./keyring.<triple>.node")`) is fine, but its
 * fallback (`require("@napi-rs/keyring-<triple>")`, a bare package whose `main`
 * IS the .node file) resolves under Node and not under Bun — and the message it
 * prints then blames npm's optional-dependency bug, sending users off to delete
 * node_modules and losing their other pi packages.
 *
 * Loading on first use turns that fatal load error into an ordinary backend
 * failure, which the existing retry + file-identity fallback already handles.
 */
let _asyncEntryCtor: typeof import("@napi-rs/keyring").AsyncEntry | null = null;
let _nativeBindingError: unknown = null;

async function _loadAsyncEntry(): Promise<typeof import("@napi-rs/keyring").AsyncEntry> {
  if (_asyncEntryCtor) return _asyncEntryCtor;
  if (_nativeBindingError) throw _nativeBindingError;
  try {
    const mod = await import("@napi-rs/keyring");
    _asyncEntryCtor = mod.AsyncEntry;
    return _asyncEntryCtor;
  } catch (err) {
    _nativeBindingError = err;
    throw err;
  }
}

/**
 * Did the native binding fail to LOAD (as opposed to an operation failing)?
 *
 * A load failure is deterministic and platform-wide: no retry, no unlock, no
 * amount of waiting brings the keyring back in this process. So it must NOT be
 * treated like a transiently locked Keychain — on macOS/Windows that would
 * throw `KeyringUnavailableError` and leave the user with no working path at
 * all. The file-identity fallback (with its loud warning) is the only usable
 * route here, exactly as on headless Linux.
 */
function _nativeBindingUnavailable(): boolean {
  return _nativeBindingError !== null;
}

/** Test-only: force (or clear with `null`) a memoized binding-load failure, so
 *  the Bun/no-native-binding branch is reachable without a Bun host. */
export function _setNativeBindingErrorForTest(err: unknown): void {
  _asyncEntryCtor = null;
  _nativeBindingError = err;
}

class NapiKeyringBackend implements KeyStoreBackend {
  async read(service: string, account: string): Promise<string | undefined> {
    const AsyncEntry = await _loadAsyncEntry();
    const entry = new AsyncEntry(service, account);
    return _withTimeout(entry.getPassword(), `read(${service})`);  // undefined on no-entry
  }
  async write(service: string, account: string, value: string): Promise<void> {
    const AsyncEntry = await _loadAsyncEntry();
    const entry = new AsyncEntry(service, account);
    await _withTimeout(entry.setPassword(value), `write(${service})`);
  }
  async delete(service: string, account: string): Promise<boolean> {
    let entry: InstanceType<typeof import("@napi-rs/keyring").AsyncEntry>;
    try {
      const AsyncEntry = await _loadAsyncEntry();
      entry = new AsyncEntry(service, account);
    } catch {
      return false;
    }
    try {
      return await _withTimeout(entry.deleteCredential(), `delete(${service})`);
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

/**
 * Is the platform keyring a CORE OS service we should expect to be present?
 * macOS (Keychain) and Windows (Credential Manager) always have one, so a read
 * that throws there is transient/locked, NOT "headless" — we must not mint a
 * new identity. On Linux/other the secret service may be genuinely absent
 * (headless, no D-Bus), so the documented file fallback applies. Overridable
 * for tests via `_setKeyringExpectedForTest`. */
let _keyringExpectedOverride: boolean | null = null;
function _keyringExpectedAvailable(): boolean {
  if (_keyringExpectedOverride !== null) return _keyringExpectedOverride;
  // Binding never loaded (Bun-built pi, issue #113) → there is no keyring on
  // this platform *for this process*, whatever the OS normally offers.
  if (_nativeBindingUnavailable()) return false;
  return process.platform === "darwin" || process.platform === "win32";
}

/** Test-only: force `_keyringExpectedAvailable()` (so a darwin test host can
 *  exercise the Linux/headless branch and vice-versa). `null` restores the
 *  real platform check. */
export function _setKeyringExpectedForTest(value: boolean | null): void {
  _keyringExpectedOverride = value;
}

/** Test-only: shrink retry attempts/delay so the persistent-failure path is
 *  fast. `null`/omitted restores defaults. */
export function _setKeyringRetryForTest(attempts: number | null, delayMs?: number): void {
  _keyringReadAttempts = attempts ?? 3;
  _keyringRetryDelayMs = delayMs ?? 300;
}

function _sleep(ms: number): Promise<void> {
  return ms > 0 ? new Promise((r) => setTimeout(r, ms)) : Promise.resolve();
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
 *   1. Existing file `~/.pi/remote/identity.json`, if present — it WINS over
 *      the keyring. A file identity is only ever written by the headless/
 *      degraded fallback (step 4) or an explicit `REMOTE_PI_ALLOW_FILE_IDENTITY`
 *      opt-in, so its mere presence means this machine established its identity
 *      as a file and the mobile device paired against THAT pubkey. If the
 *      platform keyring later becomes readable (D-Bus/libsecret installed, a
 *      desktop session, or a stale/other entry from another install), reading
 *      it first would mask the file identity — returning a DIFFERENT key, or
 *      (when the keyring is empty) minting a fresh one and persisting it —
 *      silently breaking the existing pairing. So when both exist, file wins.
 *   2. New keyring service `dev.remotepi.pi` (read retried — a transiently
 *      locked Keychain throws; we don't treat that as "no key")
 *   3. Old keyring service `dev.remotepi.mac` (migrate → step 2, delete old)
 *   4. Generate a fresh keypair, BUT only when it's safe to: either both
 *      keyring reads succeeded and returned nothing (genuine first run), or
 *      the keyring is genuinely unavailable on a platform without a core one
 *      (headless Linux → a file identity is minted here). On macOS/Windows a
 *      persistent read failure with no file identity throws
 *      `KeyringUnavailableError` instead of minting a new key — generating
 *      there silently breaks existing pairing (the "lost pairing after idle"
 *      bug). `REMOTE_PI_ALLOW_FILE_IDENTITY=1` opts back into a file identity
 *      for headless macOS/Windows hosts.
 *
 * Idempotent: subsequent calls return the same identity. The migration
 * runs at most once per machine (the old entry is deleted after copy).
 */
export async function getOrCreateEd25519Keypair(): Promise<Ed25519Keypair> {
  const backend = _getBackend();

  // ── Path 0: an existing file-backed identity wins ──────────────────────
  // `~/.pi/remote/identity.json` is only ever written by the headless/degraded
  // fallback below (or an operator who set REMOTE_PI_ALLOW_FILE_IDENTITY=1) —
  // never on a keyring-backed install. So its presence means THIS machine
  // paired against the file key, and the keyring (readable or not, matching or
  // not) must not be allowed to mask it. Short-circuit before touching the
  // keyring so a keyring that later comes online can't return a different key,
  // nor mint a fresh one over the file identity. No file → normal keyring
  // resolution below; a headless first run still reaches Path B and mints one.
  const existingFile = await _readKeypairFromFile();
  if (existingFile) return existingFile;

  // ── Path A: keyring (retried) ──────────────────────────────────────────
  // A throw here means the keyring op FAILED — but on macOS/Windows that is
  // almost always a transiently locked Keychain (idle/just-woke machine), not
  // a missing backend. `read` returns `undefined` for "no such entry" (the
  // genuine first-run signal). So we retry on throw, and only a throw that
  // SURVIVES every attempt drops us to Path B.
  let keyringError: unknown;
  for (let attempt = 0; attempt < _keyringReadAttempts; attempt++) {
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

      // Both reads SUCCEEDED and returned nothing → genuine first run on a
      // working keyring. Generate and save to the new service.
      const fresh = generateEd25519Keypair();
      await backend.write(NEW_SERVICE, ACCOUNT, _serialize(fresh));
      return fresh;
    } catch (err) {
      keyringError = err;
      if (attempt < _keyringReadAttempts - 1) {
        // Linear backoff — a locked Keychain usually frees within seconds.
        await _sleep(_keyringRetryDelayMs * (attempt + 1));
      }
    }
  }

  // ── Path B: keyring threw on every attempt ─────────────────────────────
  // Path 0 already returned any pre-existing file identity; this defensive
  // re-check catches a file written concurrently by another Pi process during
  // the keyring-retry window (still: use it, never regenerate).
  const fromFile = await _readKeypairFromFile();
  if (fromFile) return fromFile;

  // No file identity AND the keyring is unreadable. CRITICAL FORK:
  //
  //  - On a platform without a guaranteed keyring (headless Linux, no D-Bus),
  //    minting a file-backed identity is the documented, correct first-run
  //    behavior.
  //  - On macOS/Windows the keyring is a core OS service, so a persistent read
  //    failure means it's LOCKED/denied — NOT that we're a fresh install.
  //    Generating a new key here is exactly what silently broke pairing after
  //    a week idle, and the new key then masks the real Keychain identity via
  //    the file. So we FAIL LOUD instead, unless the operator explicitly
  //    opts into a file identity.
  const forceFile = process.env.REMOTE_PI_ALLOW_FILE_IDENTITY === "1";
  if (_keyringExpectedAvailable() && !forceFile) {
    throw new KeyringUnavailableError(keyringError);
  }

  // Issues #95 / #69 — minting a NEW identity when devices are already paired
  // is destructive, on every platform.
  //
  // A daemon started by `systemd --user` resolves a different secret-service
  // store than the desktop session that ran the pairing, so the keyring read
  // fails, this path mints a fresh Ed25519 key, and the SelfRevoke poller then
  // finds that key absent from the relay-side owner envelope, concludes it was
  // revoked, and wipes `peers.json` — the phone silently goes offline a few
  // seconds after every `daemon start`. `peers.json` being non-empty is proof
  // that a working identity existed, so "no key found" here is a broken
  // environment, not a first run. Fail loud and keep the pairing intact; the
  // operator can pin the identity to a file (the confirmed workaround) or fix
  // the service's keyring access.
  if (!forceFile) {
    const paired = await listPeers();
    if (paired.length > 0) {
      throw new PairedIdentityMissingError(paired.length, keyringError);
    }
  }

  console.warn(
    _nativeBindingUnavailable()
      // Issue #113: the @napi-rs/keyring native binding could not be loaded at
      // all (typically a Bun-compiled pi). Name it explicitly — the error the
      // loader prints blames npm's optional-dependency bug and sends people off
      // to delete node_modules, which takes their other pi packages with it.
      ? "[remote-pi] @napi-rs/keyring native binding could not be loaded in this " +
        `runtime; using file-backed identity at ${IDENTITY_FILE} (0600) instead. ` +
        "This is expected on a Bun-built pi. Paired devices keyed to a previous " +
        `keyring identity must be re-paired. ${String(keyringError)}`
      : "[remote-pi] keyring unavailable; using file-backed identity at " +
        `${IDENTITY_FILE}. ${String(keyringError)}`,
  );
  const fresh = generateEd25519Keypair();
  await _writeKeypairToFile(fresh);
  return fresh;
}

// ── peers.json ────────────────────────────────────────────────────────────────

export interface PeerRecord {
  name: string;
  remote_epk: string; // raw standard/base64url 32B Ed25519 Owner handle; preserved exactly
  paired_at: string;  // ISO-8601
}

export async function listPeers(): Promise<PeerRecord[]> {
  try {
    const raw = await readFile(PEERS_PATH, "utf8");
    const parsed = JSON.parse(raw) as { peers?: unknown };
    return Array.isArray(parsed.peers) ? parsed.peers as PeerRecord[] : [];
  } catch {
    return [];
  }
}

/**
 * Authoritative container read for SelfRevoke's token path. Public readers
 * intentionally remain best-effort; only a missing file is proof of emptiness
 * here. Valid array elements are returned verbatim for corruption isolation.
 */
async function _readPeerContainerStrict(): Promise<unknown[]> {
  let raw: string;
  try {
    raw = await readFile(PEERS_PATH, "utf8");
  } catch (error) {
    if (
      typeof error === "object" &&
      error !== null &&
      "code" in error &&
      (error as { code?: unknown }).code === "ENOENT"
    ) {
      return [];
    }
    throw error;
  }
  const parsed = JSON.parse(raw) as { peers?: unknown };
  if (!Array.isArray(parsed.peers)) {
    throw new Error("Invalid peers.json container");
  }
  return parsed.peers;
}

let _peerMutationQueue: Promise<void> = Promise.resolve();
const _ownerSlotTokens = new Map<string, OwnerStorageToken>();
const _ownerStorageTokenBrand: unique symbol = Symbol("owner-storage-token");

/** Opaque, process-local provenance for one canonical Owner storage slot. */
export type OwnerStorageToken = {
  readonly [_ownerStorageTokenBrand]: true;
};

export interface OwnerStorageSnapshotRecord {
  readonly rawOwnerPubkey: unknown;
  readonly token: OwnerStorageToken;
}

export type ConditionalPeerRemoval =
  | { readonly outcome: "removed"; readonly nextToken: OwnerStorageToken }
  | { readonly outcome: "stale" | "not_found" | "no_authority" };

function _ownerSlotKey(rawOwnerPubkey: unknown): string {
  if (typeof rawOwnerPubkey !== "string") {
    // Invalid non-string records remain in snapshots, but SelfRevoke skips
    // them before conditional removal; quarantine-key collisions cannot
    // authorize a removal.
    return `raw:quarantine:${typeof rawOwnerPubkey}`;
  }
  try {
    return `owner:${canonicalizeEd25519PublicKey(rawOwnerPubkey, "Owner record")}`;
  } catch {
    return `raw:string:${rawOwnerPubkey}`;
  }
}

function _tokenForSlot(slot: string): OwnerStorageToken {
  const existing = _ownerSlotTokens.get(slot);
  if (existing) return existing;
  const token = Object.freeze({ [_ownerStorageTokenBrand]: true }) as OwnerStorageToken;
  _ownerSlotTokens.set(slot, token);
  return token;
}

function _invalidateOwnerSlot(rawOwnerPubkey: unknown): OwnerStorageToken {
  const slot = _ownerSlotKey(rawOwnerPubkey);
  const token = Object.freeze({ [_ownerStorageTokenBrand]: true }) as OwnerStorageToken;
  _ownerSlotTokens.set(slot, token);
  return token;
}

function _serializePeerMutation<T>(mutation: () => Promise<T>): Promise<T> {
  const result = _peerMutationQueue.then(mutation, mutation);
  _peerMutationQueue = result.then(() => undefined, () => undefined);
  return result;
}

export function addPeer(record: PeerRecord): Promise<void> {
  return _serializePeerMutation(async () => {
    const peers = await listPeers() as unknown[];
    const idx = peers.findIndex((peer) =>
      !!peer &&
      typeof peer === "object" &&
      (peer as { remote_epk?: unknown }).remote_epk === record.remote_epk,
    );
    if (idx >= 0) {
      peers[idx] = record; // idempotent re-pair
    } else {
      peers.push(record);
    }
    await mkdir(dirname(PEERS_PATH), { recursive: true });
    await writeFile(PEERS_PATH, JSON.stringify({ peers }, null, 2));
    // A successful re-pair is a new storage provenance event even when the
    // record bytes happen to be identical.
    _invalidateOwnerSlot(record.remote_epk);
  });
}

/**
 * Returns the set of distinct `remote_epk` values in peers.json.
 *
 * In the current pairing model (plan/23 + plan/24), each `remote_epk` is the
 * Owner's Ed25519 pubkey — and we treat each as a distinct Owner the Pi has
 * been paired with. Used by the mesh self-revoke poller (plan/24 Wave 3) to
 * know which Owners' mesh blobs to fetch.
 */
export async function listOwnerPubkeys(): Promise<unknown[]> {
  const peers = await listPeers() as unknown[];
  const seen = new Set<unknown>();
  for (const peer of peers) {
    if (!peer || typeof peer !== "object") {
      seen.add(peer);
      continue;
    }
    seen.add((peer as { remote_epk?: unknown }).remote_epk);
  }
  return [...seen];
}

/**
 * Atomically snapshots raw Owner handles and their canonical-slot provenance.
 * The token is deliberately process-local and opaque to callers.
 */
export function snapshotOwnerPubkeys(): Promise<readonly OwnerStorageSnapshotRecord[]> {
  return _serializePeerMutation(async () => {
    const peers = await _readPeerContainerStrict();
    const rawOwners = new Set<unknown>();
    for (const peer of peers) {
      if (!peer || typeof peer !== "object") {
        rawOwners.add(peer);
      } else {
        rawOwners.add((peer as { remote_epk?: unknown }).remote_epk);
      }
    }
    return [...rawOwners].map((rawOwnerPubkey) => ({
      rawOwnerPubkey,
      token: _tokenForSlot(_ownerSlotKey(rawOwnerPubkey)),
    }));
  });
}

/**
 * Removes one exact raw handle only when its snapshot provenance still owns
 * the target canonical Owner slot. The final authority/token checks and sync
 * write share the existing serialized mutation lane.
 */
export function conditionalRemovePeer(
  remoteEpk: string,
  expectedToken: OwnerStorageToken,
  canCommit?: () => boolean,
): Promise<ConditionalPeerRemoval> {
  return _serializePeerMutation(async () => {
    const slot = _ownerSlotKey(remoteEpk);
    // Provenance belongs to the canonical Owner slot, not the exact raw
    // spelling. A stale slot must therefore win over an absent old spelling.
    if (_tokenForSlot(slot) !== expectedToken) return { outcome: "stale" };
    const peers = await _readPeerContainerStrict();
    const filtered = peers.filter((peer) =>
      !peer ||
      typeof peer !== "object" ||
      (peer as { remote_epk?: unknown }).remote_epk !== remoteEpk,
    );
    if (filtered.length === peers.length) return { outcome: "not_found" };
    await mkdir(dirname(PEERS_PATH), { recursive: true });
    // No await may intervene between the final token/authority checks and
    // synchronous write, preserving the lane's fail-closed commit boundary.
    if (_tokenForSlot(slot) !== expectedToken) return { outcome: "stale" };
    if (canCommit) {
      let authorized = false;
      try { authorized = canCommit(); } catch { return { outcome: "no_authority" }; }
      if (!authorized) return { outcome: "no_authority" };
    }
    writeFileSync(PEERS_PATH, JSON.stringify({ peers: filtered }, null, 2));
    return { outcome: "removed", nextToken: _invalidateOwnerSlot(remoteEpk) };
  });
}

export function removePeer(
  remoteEpk: string,
  canCommit?: () => boolean,
): Promise<boolean> {
  return _serializePeerMutation(async () => {
    const peers = await listPeers() as unknown[];
    const filtered = peers.filter((peer) =>
      !peer ||
      typeof peer !== "object" ||
      (peer as { remote_epk?: unknown }).remote_epk !== remoteEpk,
    );
    if (filtered.length === peers.length) return false;
    await mkdir(dirname(PEERS_PATH), { recursive: true });

    const serialized = JSON.stringify({ peers: filtered }, null, 2);
    if (canCommit) {
      // Guarded SelfRevoke commits must be atomic with their final authority
      // check at the JavaScript level: fail closed on false/throw, then perform
      // the tiny JSON rewrite synchronously with no interruptible await between.
      let authorized = false;
      try { authorized = canCommit(); } catch { return false; }
      if (!authorized) return false;
      writeFileSync(PEERS_PATH, serialized);
    } else {
      // Manual removals keep the established asynchronous storage behavior.
      await writeFile(PEERS_PATH, serialized);
    }
    const removed = true;
    if (removed) _invalidateOwnerSlot(remoteEpk);
    return removed;
  });
}

// ── Test-only helpers ────────────────────────────────────────────────────────

/** Test-only: expose the identity-file path so tests can clean it. */
export const _IDENTITY_FILE_FOR_TEST = IDENTITY_FILE;
/** Test-only: expose unlink for cleanup. */
export const _unlinkIdentityFileForTest = async (): Promise<void> => {
  try { await unlink(IDENTITY_FILE); } catch { /* fine if missing */ }
};
