import { expect, test } from "vitest";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const packageRoot = fileURLToPath(new URL("../", import.meta.url));
const hostPackages = ["@earendil-works/pi-coding-agent", "@earendil-works/pi-tui", "typebox"];

test("host-provided packages are wildcard peers, not runtime dependencies", () => {
  const manifest = JSON.parse(readFileSync(join(packageRoot, "package.json"), "utf8"));
  for (const name of hostPackages) {
    expect(manifest.peerDependencies[name]).toBe("*");
    expect(manifest.dependencies[name]).toBeUndefined();
    expect(manifest.devDependencies[name]).toBeDefined();
  }
});

test("standalone CLI works without access to host-provided packages", () => {
  // Simulate Pi's managed install even though development copies are installed.
  const loader = `
    export function resolve(specifier, context, nextResolve) {
      if (${JSON.stringify(hostPackages)}.some(name => specifier === name || specifier.startsWith(name + "/"))) {
        throw new Error("CLI imported host-provided package: " + specifier);
      }
      return nextResolve(specifier, context);
    }
  `;
  const loaderUrl = `data:text/javascript,${encodeURIComponent(loader)}`;
  const hook = `import { register } from "node:module"; register(${JSON.stringify(loaderUrl)}, import.meta.url);`;
  const home = mkdtempSync(join(tmpdir(), "remote-pi-cli-"));
  try {
    for (const args of [[], ["daemons"], ["peers"]]) {
      const result = spawnSync(process.execPath, [
        "--import", "tsx",
        "--import", `data:text/javascript,${encodeURIComponent(hook)}`,
        join(packageRoot, "src/index.ts"), ...args,
      ], {
        cwd: packageRoot,
        env: { ...process.env, HOME: home, USERPROFILE: home },
        encoding: "utf8",
        timeout: 15_000,
      });
      expect(result.error).toBeUndefined();
      expect(result.status, result.stderr).toBe(0);
      expect(result.stdout).toContain(args.length === 0 ? "Usage: remote-pi" : "[remote-pi]");
    }
  } finally {
    rmSync(home, { recursive: true, force: true });
  }
}, 60_000);
