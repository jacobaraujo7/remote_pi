import { afterEach, beforeEach, describe, expect, test } from "vitest";
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  loadLocalConfig,
  localConfigExists,
  effectiveAutoStartRelay,
} from "./local_config.js";

// Isolate the GLOBAL config (~/.pi/remote/config.json) into a tmp dir via
// REMOTE_PI_DIR, and neutralise any REMOTE_PI_DIRECT_CONFIG / REMOTE_PI_HOME /
// PI_CODING_AGENT_DIR the ambient shell may carry, so these assertions never
// touch the real home. PI_CODING_AGENT_DIR must be cleared because config.json
// resolves via it first (see remotePiConfigHome in paths.ts); leaving it set
// would send config reads to the agent dir instead of our REMOTE_PI_DIR tmp.
const SAVED = {
  dir: process.env["REMOTE_PI_DIR"],
  home: process.env["REMOTE_PI_HOME"],
  direct: process.env["REMOTE_PI_DIRECT_CONFIG"],
  agent: process.env["PI_CODING_AGENT_DIR"],
};

let globalDir: string;

function writeGlobalConfig(obj: unknown): void {
  writeFileSync(join(globalDir, "config.json"), JSON.stringify(obj, null, 2));
}

beforeEach(() => {
  globalDir = mkdtempSync(join(tmpdir(), "pi-globalcfg-"));
  process.env["REMOTE_PI_DIR"] = globalDir;
  delete process.env["REMOTE_PI_HOME"];
  delete process.env["REMOTE_PI_DIRECT_CONFIG"];
  delete process.env["PI_CODING_AGENT_DIR"];
});

afterEach(() => {
  rmSync(globalDir, { recursive: true, force: true });
  for (const [k, v] of [
    ["REMOTE_PI_DIR", SAVED.dir],
    ["REMOTE_PI_HOME", SAVED.home],
    ["REMOTE_PI_DIRECT_CONFIG", SAVED.direct],
    ["PI_CODING_AGENT_DIR", SAVED.agent],
  ] as const) {
    if (v === undefined) delete process.env[k];
    else process.env[k] = v;
  }
});

function freshCwd(): string {
  return mkdtempSync(join(tmpdir(), "pi-defaults-cwd-"));
}

describe("global config `defaults` as a machine-wide local-config fallback", () => {
  test("no defaults block → behaviour unchanged (fresh cwd is unconfigured)", () => {
    const cwd = freshCwd();
    expect(localConfigExists(cwd)).toBe(false);
    expect(loadLocalConfig(cwd).auto_start_relay).toBeUndefined();
  });

  test("defaults.auto_start_relay counts as configured (suppresses wizard)", () => {
    writeGlobalConfig({ defaults: { auto_start_relay: true } });
    const cwd = freshCwd();
    expect(localConfigExists(cwd)).toBe(true);
    expect(effectiveAutoStartRelay(loadLocalConfig(cwd))).toBe(true);
  });

  test("defaults.auto_start_relay:false disables relay for every unconfigured cwd", () => {
    writeGlobalConfig({ defaults: { auto_start_relay: false } });
    const cwd = freshCwd();
    expect(localConfigExists(cwd)).toBe(true);
    expect(loadLocalConfig(cwd).auto_start_relay).toBe(false);
    expect(effectiveAutoStartRelay(loadLocalConfig(cwd))).toBe(false);
  });

  test("a per-cwd file overrides the global default", () => {
    writeGlobalConfig({ defaults: { auto_start_relay: false } });
    const cwd = freshCwd();
    mkdirSync(join(cwd, ".pi", "remote-pi"), { recursive: true });
    writeFileSync(
      join(cwd, ".pi", "remote-pi", "config.json"),
      JSON.stringify({ agent_name: "x", auto_start_relay: true }),
    );
    expect(loadLocalConfig(cwd).auto_start_relay).toBe(true);
  });

  test("REMOTE_PI_DIRECT_CONFIG overrides the global default", () => {
    writeGlobalConfig({ defaults: { auto_start_relay: false } });
    process.env["REMOTE_PI_DIRECT_CONFIG"] = JSON.stringify({ auto_start_relay: true });
    const cwd = freshCwd();
    expect(loadLocalConfig(cwd).auto_start_relay).toBe(true);
  });

  test("a `relay`-only global config (no defaults) stays inert", () => {
    writeGlobalConfig({ relay: "https://relay.example" });
    const cwd = freshCwd();
    expect(localConfigExists(cwd)).toBe(false);
    expect(loadLocalConfig(cwd).auto_start_relay).toBeUndefined();
  });
});
