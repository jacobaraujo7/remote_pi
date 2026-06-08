import { afterEach, describe, expect, test } from "vitest";
import { chmodSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { RpcChild, busyTransition, resolvePiBin, rpcSpawnArgs, type RpcChildExitEvent } from "./rpc_child.js";

/**
 * Regression for the orphaned-daemon bug: a deliberate `stop()` kills the
 * child by signal (SIGTERM/SIGKILL), which used to look like a crash and trip
 * the supervisor's auto-restart — re-spawning a daemon the operator just
 * stopped/removed. `stop()` must report a clean exit instead.
 *
 * We use a tiny executable that ignores the `--mode rpc -e <path>` args and
 * just sleeps, so the child is genuinely alive when we stop it.
 */
describe("rpcSpawnArgs", () => {
  test("includes --continue so a restart resumes the latest session (not a new one)", () => {
    expect(rpcSpawnArgs("/path/to/dist/index.js")).toEqual([
      "--mode", "rpc", "--continue", "-e", "/path/to/dist/index.js",
    ]);
  });

  test("pins the session display name via --name when one is given", () => {
    expect(rpcSpawnArgs("/path/to/dist/index.js", "PC")).toEqual([
      "--mode", "rpc", "--continue", "--name", "PC", "-e", "/path/to/dist/index.js",
    ]);
  });

  test("can omit --continue for one daemon fresh-session restart", () => {
    expect(rpcSpawnArgs("/path/to/dist/index.js", "PC", false)).toEqual([
      "--mode", "rpc", "--name", "PC", "-e", "/path/to/dist/index.js",
    ]);
  });
});

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

describe("resolvePiBin (plan/40 — Windows pi.cmd)", () => {
  test("POSIX → returns the bin name unchanged", () => {
    expect(resolvePiBin("pi", "darwin")).toBe("pi");
    expect(resolvePiBin("pi", "linux")).toBe("pi");
    expect(resolvePiBin("/opt/homebrew/bin/pi", "darwin")).toBe("/opt/homebrew/bin/pi");
  });
  test("Windows → an explicit path or suffixed name is used as-is (no lookup)", () => {
    expect(resolvePiBin("C:\\tools\\pi.cmd", "win32")).toBe("C:\\tools\\pi.cmd");
    expect(resolvePiBin("pi.cmd", "win32")).toBe("pi.cmd");
    expect(resolvePiBin("C:/tools/pi", "win32")).toBe("C:/tools/pi");
  });
  // The bare-`pi`-on-win32 lookup uses `where` (Windows-only); not unit-tested
  // here (no `where` on the POSIX dev host) — covered by the real Windows smoke.
});

describe("busyTransition (stream markers)", () => {
  test("message_start → true, message_end → false", () => {
    expect(busyTransition('{"type":"message_start"}')).toBe(true);
    expect(busyTransition('{"type":"message_end"}')).toBe(false);
  });
  test("other events + garbage → null (no change)", () => {
    expect(busyTransition('{"type":"session_info_changed"}')).toBeNull();
    expect(busyTransition('{"type":"response","command":"prompt"}')).toBeNull();
    expect(busyTransition("not json")).toBeNull();
  });
});

describe("RpcChild — isBusy", () => {
  let dir: string;
  afterEach(() => {
    try { rmSync(dir, { recursive: true, force: true }); } catch { /* best-effort */ }
  });

  test("passive flag opens/closes on stream markers", () => {
    dir = mkdtempSync(join(tmpdir(), "pi-busy-"));
    const child = new RpcChild({ piBin: "/usr/bin/true", extensionPath: "/x", cwd: dir });
    expect(child.isBusy).toBe(false);
    child._ingestStdoutForTest('{"type":"message_start"}');
    expect(child.isBusy).toBe(true);
    child._ingestStdoutForTest('{"type":"message_end"}');
    expect(child.isBusy).toBe(false);
  });

  test("refreshBusy syncs from get_state.isStreaming (authoritative)", async () => {
    dir = mkdtempSync(join(tmpdir(), "pi-busy-gs-"));
    // Stub that answers get_state with isStreaming:true (ignores rpc args).
    const stub = join(dir, "stub.mjs");
    writeFileSync(
      stub,
      "#!/usr/bin/env node\n" +
      "process.stdin.setEncoding('utf8');let b='';" +
      "process.stdin.on('data',c=>{b+=c;let n;while((n=b.indexOf('\\n'))>=0){const l=b.slice(0,n);b=b.slice(n+1);" +
      "try{const m=JSON.parse(l);if(m.type==='get_state')process.stdout.write(JSON.stringify({type:'response',command:'get_state',id:m.id,success:true,data:{isStreaming:true}})+'\\n');}catch{}}});" +
      "setInterval(()=>{},1e9);\n",
    );
    chmodSync(stub, 0o755);

    const child = new RpcChild({ piBin: stub, extensionPath: "/x", cwd: dir });
    child.spawn();
    await new Promise((r) => setTimeout(r, 80)); // let it exec
    const busy = await child.refreshBusy(1500);
    expect(busy).toBe(true);
    expect(child.isBusy).toBe(true);
    await child.stop();
  });

  test("refreshBusy returns the passive flag when the child isn't running", async () => {
    dir = mkdtempSync(join(tmpdir(), "pi-busy-off-"));
    const child = new RpcChild({ piBin: "/usr/bin/true", extensionPath: "/x", cwd: dir });
    // never spawned → not running → returns passive _busy (false)
    expect(await child.refreshBusy(200)).toBe(false);
  });
});
