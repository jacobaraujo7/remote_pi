import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { existsSync, readFileSync, rmSync, statSync } from "node:fs";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

// Tests import the module after stubbing `os.homedir` so the fallback
// path writes inside a temp dir instead of the dev's real ~/.pi/remote.
// vi.mock must run before the real module load.
const _tmpHome = mkdtempSync(join(tmpdir(), "pi-storage-"));
vi.mock("node:os", async (importOriginal) => {
  const orig = await importOriginal<typeof import("node:os")>();
  return { ...orig, homedir: () => _tmpHome };
});

// Re-import after the mock is installed.
const storage = await import("./storage.js");
const {
  addPeer,
  getOrCreateEd25519Keypair,
  listOwnerPubkeys,
  _setKeyStoreBackendForTest,
  _unlinkIdentityFileForTest,
  _IDENTITY_FILE_FOR_TEST,
} = storage;
import type { KeyStoreBackend } from "./storage.js";

// ── In-memory backend for migration / round-trip tests ──────────────────────

class InMemoryBackend implements KeyStoreBackend {
  readonly store = new Map<string, string>();
  readonly reads: { service: string; account: string }[] = [];
  readonly writes: { service: string; account: string; value: string }[] = [];
  readonly deletes: { service: string; account: string }[] = [];
  private _failOn?: "read" | "write" | "delete";

  failNext(op: "read" | "write" | "delete" | undefined) {
    this._failOn = op;
  }

  async read(service: string, account: string) {
    this.reads.push({ service, account });
    if (this._failOn === "read") {
      this._failOn = undefined;
      throw new Error("simulated keyring unavailable");
    }
    return this.store.get(`${service}|${account}`);
  }
  async write(service: string, account: string, value: string) {
    this.writes.push({ service, account, value });
    if (this._failOn === "write") {
      this._failOn = undefined;
      throw new Error("simulated keyring write failure");
    }
    this.store.set(`${service}|${account}`, value);
  }
  async delete(service: string, account: string) {
    this.deletes.push({ service, account });
    const key = `${service}|${account}`;
    const had = this.store.has(key);
    this.store.delete(key);
    return had;
  }
}

const NEW_SERVICE = "dev.remotepi.pi";
const OLD_SERVICE = "dev.remotepi.mac";
const ACCOUNT = "longterm-ed25519";

beforeEach(async () => {
  // Silence the migration / fallback console output during tests so the
  // vitest output isn't polluted.
  vi.spyOn(console, "info").mockImplementation(() => undefined);
  vi.spyOn(console, "warn").mockImplementation(() => undefined);
  await _unlinkIdentityFileForTest();
  rmSync(join(_tmpHome, ".pi", "remote", "peers.json"), { force: true });
});

afterEach(() => {
  _setKeyStoreBackendForTest(null);
  vi.restoreAllMocks();
});

// ── Keyring path ────────────────────────────────────────────────────────────

describe("getOrCreateEd25519Keypair — keyring path", () => {
  test("returns existing entry from new service without writing", async () => {
    const backend = new InMemoryBackend();
    const original = JSON.stringify({
      pk: Buffer.from(new Uint8Array(32).fill(1)).toString("base64"),
      sk: Buffer.from(new Uint8Array(64).fill(2)).toString("base64"),
    });
    backend.store.set(`${NEW_SERVICE}|${ACCOUNT}`, original);
    _setKeyStoreBackendForTest(backend);

    const kp = await getOrCreateEd25519Keypair();
    expect(Buffer.from(kp.publicKey).toString("base64")).toBe(
      Buffer.from(new Uint8Array(32).fill(1)).toString("base64"),
    );
    expect(backend.writes.length).toBe(0);
    expect(backend.deletes.length).toBe(0);
  });

  test("generates + saves a fresh keypair when neither service has an entry", async () => {
    const backend = new InMemoryBackend();
    _setKeyStoreBackendForTest(backend);

    const kp = await getOrCreateEd25519Keypair();
    expect(kp.publicKey).toBeInstanceOf(Uint8Array);
    expect(kp.publicKey.length).toBe(32);
    expect(backend.writes.length).toBe(1);
    expect(backend.writes[0]!.service).toBe(NEW_SERVICE);
    expect(backend.writes[0]!.account).toBe(ACCOUNT);
    expect(backend.deletes.length).toBe(0);
  });

  test("idempotent across two calls — second call returns same key without write", async () => {
    const backend = new InMemoryBackend();
    _setKeyStoreBackendForTest(backend);

    const first = await getOrCreateEd25519Keypair();
    const second = await getOrCreateEd25519Keypair();

    expect(Buffer.from(first.publicKey).toString("base64")).toBe(
      Buffer.from(second.publicKey).toString("base64"),
    );
    expect(backend.writes.length).toBe(1);  // only the first call wrote
  });
});

// ── Migration path (legacy keytar service) ──────────────────────────────────

describe("getOrCreateEd25519Keypair — keytar migration (plan/27 E1)", () => {
  test("legacy entry → copies to new service + deletes old", async () => {
    const backend = new InMemoryBackend();
    const legacy = JSON.stringify({
      pk: Buffer.from(new Uint8Array(32).fill(7)).toString("base64"),
      sk: Buffer.from(new Uint8Array(64).fill(8)).toString("base64"),
    });
    backend.store.set(`${OLD_SERVICE}|${ACCOUNT}`, legacy);
    _setKeyStoreBackendForTest(backend);

    const kp = await getOrCreateEd25519Keypair();

    // Preserved identity
    expect(Buffer.from(kp.publicKey).toString("base64")).toBe(
      Buffer.from(new Uint8Array(32).fill(7)).toString("base64"),
    );
    // New entry was written
    expect(backend.store.get(`${NEW_SERVICE}|${ACCOUNT}`)).toBe(legacy);
    // Old entry was deleted
    expect(backend.store.has(`${OLD_SERVICE}|${ACCOUNT}`)).toBe(false);
    expect(backend.deletes.find((d) => d.service === OLD_SERVICE)).toBeDefined();
  });

  test("new entry already present → does NOT touch legacy entry", async () => {
    const backend = new InMemoryBackend();
    const newVal = JSON.stringify({
      pk: Buffer.from(new Uint8Array(32).fill(3)).toString("base64"),
      sk: Buffer.from(new Uint8Array(64).fill(4)).toString("base64"),
    });
    const stale = JSON.stringify({
      pk: Buffer.from(new Uint8Array(32).fill(9)).toString("base64"),
      sk: Buffer.from(new Uint8Array(64).fill(9)).toString("base64"),
    });
    backend.store.set(`${NEW_SERVICE}|${ACCOUNT}`, newVal);
    backend.store.set(`${OLD_SERVICE}|${ACCOUNT}`, stale);
    _setKeyStoreBackendForTest(backend);

    const kp = await getOrCreateEd25519Keypair();
    expect(Buffer.from(kp.publicKey).toString("base64")).toBe(
      Buffer.from(new Uint8Array(32).fill(3)).toString("base64"),
    );
    // Legacy entry untouched (we never even read it)
    expect(backend.store.get(`${OLD_SERVICE}|${ACCOUNT}`)).toBe(stale);
    expect(backend.deletes.length).toBe(0);
  });
});

// ── Headless fallback ───────────────────────────────────────────────────────

describe("getOrCreateEd25519Keypair — headless Linux fallback", () => {
  test("keyring read throws → falls back to identity.json (chmod 0o600)", async () => {
    const backend = new InMemoryBackend();
    backend.failNext("read");
    _setKeyStoreBackendForTest(backend);

    const kp = await getOrCreateEd25519Keypair();
    expect(kp.publicKey.length).toBe(32);

    // File exists at the expected path with restrictive perms.
    expect(existsSync(_IDENTITY_FILE_FOR_TEST)).toBe(true);
    const stat = statSync(_IDENTITY_FILE_FOR_TEST);
    // Mode mask 0o777 isolates the perm bits (on Linux/macOS); on other
    // systems we just assert the bits are no looser than 0o600.
    const perms = stat.mode & 0o777;
    expect(perms & 0o077).toBe(0);  // group + other bits zero

    // Round-trip: parse and check it deserializes to the same key.
    const parsed = JSON.parse(readFileSync(_IDENTITY_FILE_FOR_TEST, "utf8")) as { pk: string; sk: string };
    expect(Buffer.from(parsed.pk, "base64").length).toBe(32);
  });

  test("fallback second call returns the file-stored key (no regen)", async () => {
    const backend = new InMemoryBackend();
    backend.failNext("read");
    _setKeyStoreBackendForTest(backend);
    const first = await getOrCreateEd25519Keypair();

    // Reset the backend so it would throw again on a fresh read.
    const backend2 = new InMemoryBackend();
    backend2.failNext("read");
    _setKeyStoreBackendForTest(backend2);
    const second = await getOrCreateEd25519Keypair();

    expect(Buffer.from(first.publicKey).toString("base64")).toBe(
      Buffer.from(second.publicKey).toString("base64"),
    );
  });

});

// ── peers.json ───────────────────────────────────────────────────────────────

describe("peers.json owner key helpers", () => {
  test("listOwnerPubkeys prefers pair_request_v2 owner_pk and falls back for legacy peers", async () => {
    await addPeer({
      name: "Signed Phone",
      remote_epk: "app-peer-key",
      paired_at: "2026-05-29T00:00:00.000Z",
      owner_pk: "owner-signing-key",
      app_peer_pk: "app-peer-key",
    });
    await addPeer({
      name: "Legacy Phone",
      remote_epk: "legacy-owner-key",
      paired_at: "2026-05-29T00:00:01.000Z",
    });

    expect(await listOwnerPubkeys()).toEqual(["owner-signing-key", "legacy-owner-key"]);
  });
});
