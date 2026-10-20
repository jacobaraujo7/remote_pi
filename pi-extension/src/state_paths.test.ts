import { afterEach, describe, expect, test } from "vitest";
import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { registryPath, saveRegistry } from "./daemon/registry.js";
import { loadLocalConfig, saveLocalConfig } from "./session/local_config.js";
import {
  localConfigDir,
  projectSettingsPath,
  statePrefix,
  statePrefixForAgentBin,
  userStateRoot,
} from "./state_paths.js";

/**
 * State namespace pinning (issue #170): an oh-my-pi daemon must keep its
 * state under `~/.omp` while a pi daemon keeps `~/.pi` — the two installs
 * must never read each other's registry/config. The namespace follows
 * `REMOTE_PI_STATE_PREFIX` everywhere a `.pi` path is resolved.
 */
describe("state namespace pinning", () => {
  let home: string | undefined;
  let cwd: string | undefined;
  const originalHome = process.env["REMOTE_PI_HOME"];
  const originalPrefix = process.env["REMOTE_PI_STATE_PREFIX"];

  afterEach(() => {
    if (originalHome === undefined) delete process.env["REMOTE_PI_HOME"];
    else process.env["REMOTE_PI_HOME"] = originalHome;
    if (originalPrefix === undefined) delete process.env["REMOTE_PI_STATE_PREFIX"];
    else process.env["REMOTE_PI_STATE_PREFIX"] = originalPrefix;
    if (home) { try { rmSync(home, { recursive: true, force: true }); } catch { /* best-effort */ } }
    if (cwd) { try { rmSync(cwd, { recursive: true, force: true }); } catch { /* best-effort */ } }
    home = undefined;
    cwd = undefined;
  });

  test("defaults to .pi and flips to .omp via REMOTE_PI_STATE_PREFIX", () => {
    delete process.env["REMOTE_PI_STATE_PREFIX"];
    expect(statePrefix()).toBe(".pi");
    process.env["REMOTE_PI_STATE_PREFIX"] = ".omp";
    expect(statePrefix()).toBe(".omp");
    // Anything else (typos, empty) keeps the pi default.
    process.env["REMOTE_PI_STATE_PREFIX"] = "omp";
    expect(statePrefix()).toBe(".pi");
  });

  test("statePrefixForAgentBin: env pin wins, else omp* binary implies .omp", () => {
    delete process.env["REMOTE_PI_STATE_PREFIX"];
    expect(statePrefixForAgentBin("pi")).toBe(".pi");
    expect(statePrefixForAgentBin("omp")).toBe(".omp");
    expect(statePrefixForAgentBin("/Users/x/.bun/bin/omp")).toBe(".omp");
    process.env["REMOTE_PI_STATE_PREFIX"] = ".omp";
    expect(statePrefixForAgentBin("pi")).toBe(".omp");
  });

  test("pins home state root, registry, and cwd config to .omp end-to-end", () => {
    home = mkdtempSync(join(tmpdir(), "pi-state-home-"));
    cwd = mkdtempSync(join(tmpdir(), "pi-state-cwd-"));
    process.env["REMOTE_PI_HOME"] = home;
    process.env["REMOTE_PI_STATE_PREFIX"] = ".omp";

    expect(userStateRoot()).toBe(join(home, ".omp", "remote"));
    expect(registryPath()).toBe(join(home, ".omp", "remote", "daemons.json"));
    expect(projectSettingsPath(cwd)).toBe(join(cwd, ".omp", "settings.json"));
    expect(localConfigDir(cwd)).toBe(join(cwd, ".omp", "remote-pi"));

    saveRegistry({ daemons: [] });
    saveLocalConfig(cwd, { agent_name: "omp-agent" });

    expect(existsSync(join(home, ".omp", "remote", "daemons.json"))).toBe(true);
    expect(readFileSync(join(cwd, ".omp", "remote-pi", "config.json"), "utf8")).toContain("omp-agent");
    // saveLocalConfig locks the auto_start_relay default (true) in on first save.
    expect(loadLocalConfig(cwd)).toEqual({ agent_name: "omp-agent", auto_start_relay: true });
  });

  test("default namespace keeps writing under .pi (no behavior change)", () => {
    home = mkdtempSync(join(tmpdir(), "pi-state-home-"));
    process.env["REMOTE_PI_HOME"] = home;
    delete process.env["REMOTE_PI_STATE_PREFIX"];

    expect(userStateRoot()).toBe(join(home, ".pi", "remote"));
    saveRegistry({ daemons: [] });
    expect(existsSync(join(home, ".pi", "remote", "daemons.json"))).toBe(true);
  });
});
