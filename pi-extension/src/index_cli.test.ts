import { afterAll, beforeAll, describe, expect, test } from "vitest";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import * as nodeModule from "node:module";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

// Runs `src/index.ts` as the CLI with every host package unresolvable, the
// way a Pi-managed install (`--legacy-peer-deps`) leaves them. Catches the
// extension being loaded before the direct-run check, which the static
// import walk (cli_imports.test.ts) can't see. Needs module.registerHooks
// (Node >= 22.15).

const pkgDir = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const pkg = JSON.parse(readFileSync(join(pkgDir, "package.json"), "utf8")) as {
  peerDependencies: Record<string, string>;
};

describe.skipIf(typeof nodeModule.registerHooks !== "function")("CLI with host packages blocked", () => {
  let tmp: string;
  let blocker: string;

  beforeAll(() => {
    tmp = mkdtempSync(join(tmpdir(), "remote-pi-nohost-"));
    blocker = join(tmp, "block-host.mjs");
    writeFileSync(blocker, `
import { registerHooks } from "node:module";
const host = ${JSON.stringify(Object.keys(pkg.peerDependencies))};
registerHooks({
  resolve(specifier, context, nextResolve) {
    if (host.some((name) => specifier === name || specifier.startsWith(name + "/"))) {
      throw Object.assign(new Error("blocked host package " + specifier), { code: "ERR_MODULE_NOT_FOUND" });
    }
    return nextResolve(specifier, context);
  },
});
`);
  });

  afterAll(() => {
    if (tmp) rmSync(tmp, { recursive: true, force: true });
  });

  function runTs(file: string, args: string[]) {
    return spawnSync(
      process.execPath,
      ["--import", pathToFileURL(blocker).href, "--import", "tsx", join(pkgDir, "src", file), ...args],
      {
        cwd: pkgDir,
        env: { ...process.env, HOME: tmp, USERPROFILE: tmp, REMOTE_PI_HOME: tmp },
        encoding: "utf8",
      },
    );
  }

  test("index.ts runs the CLI", () => {
    const r = runTs("index.ts", ["devices"]);
    expect(r.status, r.stderr).toBe(0);
    expect(r.stdout).toContain("No peers");
  });

  test("the extension module fails with the host blocked (control)", () => {
    const r = runTs("extension.ts", []);
    expect(r.status).not.toBe(0);
    expect(r.stderr).toContain("blocked host package");
  });
});
