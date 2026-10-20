import { afterAll, beforeAll, describe, expect, test } from "vitest";
import { spawnSync, type SpawnSyncReturns } from "node:child_process";
import { existsSync, mkdtempSync, readdirSync, readFileSync, rmSync, statSync, symlinkSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

// End-to-end check that the packed package's CLI runs in a Pi-managed install,
// where peer dependencies are omitted. Builds, packs and installs from the npm
// registry, so it is opt-in: REMOTE_PI_PACKED_TEST=1 pnpm test cli_packed

const pkgDir = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const pkg = JSON.parse(readFileSync(join(pkgDir, "package.json"), "utf8")) as {
  peerDependencies: Record<string, string>;
};
const npm = process.platform === "win32" ? "npm.cmd" : "npm";
const isWindows = process.platform === "win32";

function run(cmd: string, args: string[], opts: { cwd?: string; env?: NodeJS.ProcessEnv } = {}): SpawnSyncReturns<string> {
  return spawnSync(cmd, args, {
    cwd: opts.cwd ?? pkgDir,
    env: { ...process.env, ...opts.env },
    encoding: "utf8",
    // Node refuses to spawn .cmd files without a shell.
    shell: isWindows && cmd.endsWith(".cmd"),
  });
}

function ok(r: SpawnSyncReturns<string>): string {
  expect(r.error).toBeUndefined();
  expect(r.status, `${r.stdout}\n${r.stderr}`).toBe(0);
  return r.stdout;
}

describe.skipIf(!process.env["REMOTE_PI_PACKED_TEST"])("packed CLI without host packages", () => {
  // Sibling temp dirs (not nested) so Node's parent-directory module lookup
  // can't find a host package from another tree.
  let packDir: string;
  let installDir: string;
  let homeDir: string;
  let installedPkg: string;
  let indexModeAfterInstall: number;

  beforeAll(() => {
    packDir = mkdtempSync(join(tmpdir(), "remote-pi-pack-"));
    installDir = mkdtempSync(join(tmpdir(), "remote-pi-install-"));
    homeDir = mkdtempSync(join(tmpdir(), "remote-pi-home-"));

    const tsc = createRequire(import.meta.url).resolve("typescript/bin/tsc");
    ok(run(process.execPath, [tsc, "-p", pkgDir]));
    ok(run(npm, ["pack", "--pack-destination", packDir]));
    const tarball = readdirSync(packDir).find((f) => f.endsWith(".tgz"));
    expect(tarball).toBeDefined();
    // Same flags Pi's package manager uses for npm installs.
    ok(run(npm, ["install", join(packDir, tarball!), "--prefix", installDir, "--legacy-peer-deps"]));
    installedPkg = join(installDir, "node_modules", "remote-pi");
    indexModeAfterInstall = statSync(join(installedPkg, "dist", "index.js")).mode;
  }, 300_000);

  afterAll(() => {
    for (const dir of [packDir, installDir, homeDir]) {
      if (dir) rmSync(dir, { recursive: true, force: true });
    }
  });

  const env = (): NodeJS.ProcessEnv => ({ HOME: homeDir, USERPROFILE: homeDir, REMOTE_PI_HOME: homeDir });

  test("install omits every host package", () => {
    for (const name of Object.keys(pkg.peerDependencies)) {
      expect(existsSync(join(installDir, "node_modules", name)), name).toBe(false);
    }
  });

  test("the extension module itself needs the host (control)", () => {
    const extensionJs = pathToFileURL(join(installedPkg, "dist", "extension.js")).href;
    const r = run(process.execPath, ["--input-type=module", "-e", `await import(${JSON.stringify(extensionJs)});`], { env: env() });
    expect(r.status).not.toBe(0);
    expect(r.stderr).toContain("ERR_MODULE_NOT_FOUND");
  });

  test("npm bin runs the CLI", () => {
    const bin = join(installDir, "node_modules", ".bin", isWindows ? "remote-pi.cmd" : "remote-pi");
    const out = ok(run(bin, [], { env: env() }));
    expect(out).toContain("Usage: remote-pi <command>");
  });

  test("CLI subcommands work via node dist/index.js (Cockpit)", () => {
    const script = join(installedPkg, "dist", "index.js");
    expect(ok(run(process.execPath, [script, "devices"], { env: env() }))).toContain("No peers");
    // On Windows the supervisor pipe is keyed by user name, not HOME, so this
    // would reach a real supervisor.
    if (!isWindows) {
      expect(ok(run(process.execPath, [script, "daemons"], { env: env() }))).toContain("No daemons registered");
    }
  });

  // Existing links (install.sh, /remote-pi install) point at dist/index.js,
  // and every `pi update` reinstalls it with npm's file modes, which only
  // mark `bin` files +x. So it must be executable as npm installed it.
  test.skipIf(isWindows)("a link to dist/index.js made by install.sh runs the CLI", () => {
    expect(indexModeAfterInstall & 0o111).not.toBe(0);
    const link = join(homeDir, "install-sh-remote-pi");
    symlinkSync(join(installedPkg, "dist", "index.js"), link);
    expect(ok(run(link, [], { env: env() }))).toContain("Usage: remote-pi <command>");
  });

  test.skipIf(isWindows)("the ~/.local/bin link from /remote-pi install runs the CLI", () => {
    const installJs = pathToFileURL(join(installedPkg, "dist", "daemon", "install.js")).href;
    ok(run(process.execPath, [
      "--input-type=module",
      "-e",
      `const m = await import(${JSON.stringify(installJs)}); m.linkCliBinaries(${JSON.stringify(homeDir)});`,
    ], { env: env() }));
    const out = ok(run(join(homeDir, ".local", "bin", "remote-pi"), [], { env: env() }));
    expect(out).toContain("Usage: remote-pi <command>");
  });
});
