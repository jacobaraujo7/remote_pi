import { afterEach, beforeEach, describe, expect, test } from "vitest";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { acquireCwdLock, lockPathForCwd } from "./cwd_lock.js";

/** A fresh tmp cwd per test — each gets a unique room hash, so tests in
 *  parallel don't fight over the same lock socket. */
function tmpCwd(): string {
  return mkdtempSync(join(tmpdir(), "pi-cwdlock-"));
}

/** Redirect the lock dir away from the developer's real `~/.pi/remote/locks`
 *  so running the suite never binds sockets in the live mesh's directory. */
let testHome: string;

beforeEach(() => {
  testHome = mkdtempSync(join(tmpdir(), "pi-cwdlock-home-"));
  process.env["REMOTE_PI_HOME"] = testHome;
});

afterEach(() => {
  delete process.env["REMOTE_PI_HOME"];
  try { rmSync(testHome, { recursive: true, force: true }); } catch { /* best-effort */ }
});

describe("acquireCwdLock", () => {
  test("first call acquires; second call (same cwd) is refused", async () => {
    const cwd = tmpCwd();

    const first = await acquireCwdLock(cwd);
    expect(first.ok).toBe(true);

    const second = await acquireCwdLock(cwd);
    expect(second.ok).toBe(false);
    if (!second.ok) {
      expect(second.lockPath).toBe(lockPathForCwd(cwd));
    }

    if (first.ok) first.release();
  });

  test("releasing the lock allows a fresh acquire", async () => {
    const cwd = tmpCwd();

    const first = await acquireCwdLock(cwd);
    expect(first.ok).toBe(true);
    if (first.ok) first.release();

    // Some platforms keep the socket file around after close — the lock
    // primitive must self-heal via the stale-detect-then-unlink path.
    const second = await acquireCwdLock(cwd);
    expect(second.ok).toBe(true);
    if (second.ok) second.release();
  });

  test("different cwds get independent locks", async () => {
    const cwdA = tmpCwd();
    const cwdB = tmpCwd();

    const a = await acquireCwdLock(cwdA);
    const b = await acquireCwdLock(cwdB);

    expect(a.ok).toBe(true);
    expect(b.ok).toBe(true);
    expect(lockPathForCwd(cwdA)).not.toBe(lockPathForCwd(cwdB));

    if (a.ok) a.release();
    if (b.ok) b.release();
  });

  // The stale-socket self-heal path (a previous Pi died WITHOUT releasing
  // the lock — `kill -9` or crash) can't be reproduced reliably from a
  // single Node process: depending on Node version + OS, `server.close()`
  // either unlinks the socket file or leaves it behind. We rely on the
  // existing leader-election tests (which DO exercise the unlink-retry
  // path via real broker crashes in `src/session/leader_election.test.ts`)
  // to cover the OS primitive, and trust that `acquireCwdLock` composes
  // it correctly. Manual repro: `kill -9` a Pi process holding the lock,
  // then run `/remote-pi` again — acquires cleanly.

  test("refused result includes the canonical lockPath", async () => {
    const cwd = tmpCwd();
    const held = await acquireCwdLock(cwd);
    expect(held.ok).toBe(true);

    const refused = await acquireCwdLock(cwd);
    expect(refused.ok).toBe(false);
    if (!refused.ok) {
      // Same hash → same path, regardless of which call computes it.
      expect(refused.lockPath).toBe(lockPathForCwd(cwd));
    }

    if (held.ok) held.release();
  });
});
