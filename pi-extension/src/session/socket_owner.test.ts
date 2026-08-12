import { spawn } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync, readFileSync, existsSync } from "node:fs";
import { createServer, type Server } from "node:net";
import { tmpdir } from "node:os";
import { basename, join } from "node:path";
import { once } from "node:events";
import { setTimeout as delay } from "node:timers/promises";
import { describe, expect, test } from "vitest";
import {
  describeRegistrationBlocker,
  describeSocketOwner,
  type SocketOwner,
} from "./socket_owner.js";

const onLinux = process.platform === "linux";

describe("describeSocketOwner", () => {
  test.runIf(onLinux)("names the process listening on the path", async () => {
    const dir = mkdtempSync(join(tmpdir(), "owner-"));
    const sockPath = join(dir, "broker.sock");
    let server: Server | undefined;
    try {
      server = createServer(() => {});
      server.listen(sockPath);
      await once(server, "listening");

      const owner = await describeSocketOwner(sockPath);

      expect(owner?.pid).toBe(process.pid);
      expect(owner?.halted).toBe(false);
      // `comm` would read "MainThread" for a Node process, which identifies
      // nothing in `ps`; the executable name is what an operator can act on.
      expect(owner?.command).toBe(basename(process.execPath));
    } finally {
      server?.close();
      rmSync(dir, { recursive: true, force: true });
    }
  });

  test.runIf(onLinux)("reports a suspended owner as unable to answer", async () => {
    const dir = mkdtempSync(join(tmpdir(), "owner-stopped-"));
    const sockPath = join(dir, "broker.sock");
    const script = join(dir, "listener.cjs");
    writeFileSync(script, `
      const { createServer } = require("node:net");
      createServer(() => {}).listen(process.argv[2], () => {
        process.kill(process.pid, "SIGSTOP");
      });
    `);
    const child = spawn(process.execPath, [script, sockPath], { stdio: "ignore" });
    try {
      for (let i = 0; i < 200 && !existsSync(sockPath); i++) await delay(25);
      // The listener only counts as suspended once the kernel says so.
      let state = "";
      for (let i = 0; i < 200; i++) {
        const stat = readFileSync(`/proc/${child.pid}/stat`, "utf8");
        state = stat.slice(stat.lastIndexOf(")") + 2).trim().charAt(0);
        if (state === "T") break;
        await delay(25);
      }
      expect(state).toBe("T");

      const owner = await describeSocketOwner(sockPath);

      expect(owner?.pid).toBe(child.pid);
      expect(owner?.halted).toBe(true);
      expect(owner?.state).toBe("suspended");
      expect(owner?.command).toBe(basename(process.execPath));
    } finally {
      child.kill("SIGKILL");
      // Reap it before removing the directory it still has open.
      await once(child, "exit");
      rmSync(dir, { recursive: true, force: true });
    }
  }, 15_000);

  test("returns null when nothing is listening on the path", async () => {
    const dir = mkdtempSync(join(tmpdir(), "owner-absent-"));
    try {
      expect(await describeSocketOwner(join(dir, "broker.sock"))).toBeNull();
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  test.runIf(onLinux)("gives up rather than scanning past its budget", async () => {
    const dir = mkdtempSync(join(tmpdir(), "owner-budget-"));
    const sockPath = join(dir, "broker.sock");
    let server: Server | undefined;
    try {
      server = createServer(() => {});
      server.listen(sockPath);
      await once(server, "listening");

      // The socket is resolvable; only the exhausted budget stops the walk.
      expect(await describeSocketOwner(sockPath, 0)).toBeNull();
      expect((await describeSocketOwner(sockPath))?.pid).toBe(process.pid);
    } finally {
      server?.close();
      rmSync(dir, { recursive: true, force: true });
    }
  });
});

describe("describeRegistrationBlocker", () => {
  const halted: SocketOwner = { pid: 4242, command: "omp", state: "suspended", halted: true };
  const running: SocketOwner = { pid: 4243, command: "omp", state: "running", halted: false };

  test("tells the operator how to resume a halted owner", () => {
    const message = describeRegistrationBlocker("/run/broker.sock", halted);

    expect(message).toContain("/run/broker.sock");
    expect(message).toContain("pid 4242 (omp)");
    expect(message).toContain("kill -CONT 4242");
    expect(message).toContain("then rejoin.");
  });

  test("never advises killing an owner that is merely late", () => {
    const message = describeRegistrationBlocker("/run/broker.sock", running);

    expect(message).toContain("pid 4243 (omp)");
    // Missing a fixed deadline does not prove a fault, so the message must not
    // read as an instruction to destroy a possibly healthy broker.
    expect(message).not.toContain("kill");
    expect(message).toContain("may be busy");
    expect(message).toContain("resume or terminate it, then rejoin.");
  });

  test("keeps one recovery instruction when the owner is unknown", () => {
    const message = describeRegistrationBlocker("/run/broker.sock", null);

    expect(message).toContain("/run/broker.sock");
    expect(message).not.toContain("pid ");
    expect(message).toContain("resume or terminate it, then rejoin.");
  });
});
