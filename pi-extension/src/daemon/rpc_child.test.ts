import { afterEach, describe, expect, test } from "vitest";
import { chmodSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { RpcChild, type RpcChildExitEvent } from "./rpc_child.js";

/**
 * Regression for the orphaned-daemon bug: a deliberate `stop()` kills the
 * child by signal (SIGTERM/SIGKILL), which used to look like a crash and trip
 * the supervisor's auto-restart — re-spawning a daemon the operator just
 * stopped/removed. `stop()` must report a clean exit instead.
 *
 * We use a tiny executable that ignores the `--mode rpc -e <path>` args and
 * just sleeps, so the child is genuinely alive when we stop it.
 */
describe("RpcChild — deliberate stop is not a crash", () => {
  let dir: string;

  afterEach(() => {
    try { rmSync(dir, { recursive: true, force: true }); } catch { /* best-effort */ }
  });

  test("stop() emits isCrash:false though the child dies by signal", async () => {
    dir = mkdtempSync(join(tmpdir(), "pi-rpcchild-"));
    const bin = join(dir, "staysalive.sh");
    writeFileSync(bin, "#!/bin/sh\nexec sleep 30\n");
    chmodSync(bin, 0o755);

    const child = new RpcChild({ piBin: bin, extensionPath: "/no/such.js", cwd: dir });
    const exited = new Promise<RpcChildExitEvent>((resolve) => child.once("exit", resolve));
    child.spawn();
    // Let the process actually exec before we signal it.
    await new Promise((r) => setTimeout(r, 50));
    await child.stop();

    const evt = await exited;
    expect(evt.isCrash).toBe(false);   // ← was `true` before the fix → spurious restart
    expect(child.state).toBe("stopped");
  });
});
